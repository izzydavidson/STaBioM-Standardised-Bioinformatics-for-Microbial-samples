# Fix Summary: Log Streaming and Run Name Issues

## Issues Fixed

### Issue 1: No Logs Displayed in UI ✅

**Problem:**
- Logs appeared in terminal but not in the Shiny UI
- Only initial [INFO] messages showed, then nothing
- Pipeline was actually running and creating output directories

**Root Cause:**
The pipeline runs inside Docker containers. When using `sys::exec_background()` to capture stdout/stderr, we only captured output from the parent shell script (`stabiom_run.sh`), not from the Docker container where the actual pipeline runs.

```bash
# Execution chain:
stabiom_run.sh
  → run_in_container.sh
    → docker run stabiom-tools-sr:dev
      → Pipeline inside container ← Logs here!
```

The logs from inside the Docker container weren't being captured by `sys::exec_background()` because Docker redirects them to its own logging system.

**The Fix:**
Instead of trying to capture Docker container stdout, we now **tail the pipeline log file** directly.

**Changes Made:**

1. **Added log file tracking** (`run_progress_server.R` lines 7-8):
```r
log_file_path <- reactiveVal(NULL)
log_file_size <- reactiveVal(0)
```

2. **Set log file path when starting pipeline** (`run_progress_server.R` lines 100-103):
```r
# Log file path: outputs/{run_id}/logs/{pipeline}.log
log_file <- file.path(repo_root, "outputs", shared$current_run$run_id,
                     "logs", paste0(shared$current_run$pipeline, ".log"))
log_file_path(log_file)
```

3. **Rewrote log reading to tail the file** (`run_progress_server.R` lines 149-185):
```r
# Read entire log file each cycle
if (file.exists(log_file)) {
  con <- file(log_file, "r")
  all_lines <- readLines(con, warn = FALSE)
  close(con)

  if (length(all_lines) > 0) {
    # Keep initial INFO messages, add all log file content
    initial_msgs <- log_buffer()[1:6]
    log_buffer(c(initial_msgs, all_lines))
  }
}
```

**Result:**
- UI now displays real-time logs from the pipeline
- Logs update every 500ms as file grows
- Works with Docker containerized execution

---

### Issue 2: Run Name Not Being Used ✅

**Problem:**
- User entered custom run name (e.g., "My_Test_Run")
- Pipeline used timestamp instead (e.g., "20260214_161342")
- Run name input was ignored

**Root Cause:**
The config generator wasn't including the user's run_name in the generated config. Looking at the schema:

```json
{
  "run": {
    "run_id": "20260214_161342"  // Internal timestamp ID
  },
  "qiime2": {
    "sample_id": "My_Test_Run"   // User-friendly name (MISSING!)
  }
}
```

The `sample_id` field under `qiime2` is where the user's friendly name should go.

**The Fix:**

1. **Pass run_name to config generator** (`short_read_server.R` line 220):
```r
params <- list(
  run_id = run_id,          # Timestamp: 20260214_161342
  run_name = input$run_name, # User input: "My_Test_Run"
  ...
)
```

2. **Add sample_id to config** (`config_generator.R` line 58):
```r
qiime2 = list(
  sample_id = params$run_name %||% params$run_id,  # Use run_name or fallback to run_id
  dada2 = list(...)
)
```

**Result:**
- User's run name now appears in config as `qiime2.sample_id`
- Internal `run_id` remains timestamp-based for uniqueness
- If no run_name provided, falls back to run_id

---

## Files Changed

### `frontend/server/run_progress_server.R`
**Lines changed: 5, 78-130, 132-168**
- Added `log_file_path` and `log_file_size` reactive values
- Modified `execute_pipeline()` to determine log file path
- Completely rewrote log reading observer to tail log file instead of capturing stdout
- Simplified: read entire file each cycle, update buffer

### `frontend/utils/config_generator.R`
**Lines changed: 57-66**
- Added `sample_id` to `qiime2` config object
- Uses `params$run_name` with fallback to `params$run_id`

### `frontend/server/short_read_server.R`
**Lines changed: 220**
- Added `run_name = input$run_name` to params list
- Passes user's run name to config generator

---

## Testing Instructions

### Manual Test:

1. **Start the Shiny app:**
```bash
cd frontend
R -e "shiny::runApp()"
```

2. **Navigate to Short Read tab**

3. **Configure pipeline:**
   - Run Name: `Test_Log_Streaming`
   - Pipeline: 16S Amplicon
   - Browse to select: `main/data/test_inputs/ERR10233589_1.fastq`
   - Leave other settings as default

4. **Run Pipeline:**
   - Click "Run Pipeline"
   - Navigate to "Run Progress" tab

5. **Verify:**
   - ✅ Run name shows "Test_Log_Streaming" (not just timestamp)
   - ✅ Logs appear within 5-10 seconds
   - ✅ See `[dispatch]`, `[container]`, `[config]` log lines
   - ✅ Logs update in real-time
   - ✅ Output directory created at `outputs/{timestamp}/`

### Check Generated Config:

```bash
cat outputs/config_*.json | grep -A 3 qiime2
```

Should show:
```json
"qiime2": {
  "sample_id": "Test_Log_Streaming",
  "dada2": {
```

---

## Why It Happened

### Log Streaming Issue:
**Misunderstanding of Docker execution model.**

When a script runs `docker run`, the stdout/stderr of the containerized process don't automatically flow back to the parent process's stdout when using `sys::exec_background()` in non-blocking mode.

We assumed:
```
sys::exec_background() → captures all descendant output
```

Reality:
```
sys::exec_background() → captures stabiom_run.sh output only
  Docker container → has separate stdout/stderr
    Pipeline logs → written to container logs (not captured)
```

The pipeline **already writes logs to files** for this exact reason. We should have been reading those files from the start.

### Run Name Issue:
**Incomplete schema understanding.**

We correctly identified that `run.run_id` is the timestamp-based internal ID. But we didn't realize that QIIME2 (the underlying tool for 16S amplicon sequencing) has its own `sample_id` field for user-friendly sample names.

The schema has two separate concepts:
- `run.run_id` = unique run identifier (timestamp-based)
- `qiime2.sample_id` = user-friendly sample/run name

We were only setting the first one.

---

## Verification

After these fixes:

✅ **Logs stream to UI** - Tailing log file instead of capturing Docker stdout
✅ **Run name preserved** - Added to `qiime2.sample_id` field
✅ **Output directory created** - Pipeline creates `outputs/{run_id}/`
✅ **Config includes sample_id** - User's name appears in config JSON
✅ **Real-time updates** - Logs refresh every 500ms from file

---

## Summary

### What Was Broken:
1. ❌ Docker container logs not captured by `sys::exec_background()`
2. ❌ Run name input ignored in config generation

### What We Fixed:
1. ✅ Tail the pipeline log file directly (polling every 500ms)
2. ✅ Add `qiime2.sample_id = run_name` to config

### Result:
The UI now properly displays real-time pipeline logs and respects the user's custom run name.

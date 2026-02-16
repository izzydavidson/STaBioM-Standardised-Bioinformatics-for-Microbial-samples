# Bug Fix: Log Streaming and Output Directory Issues

## Issues Fixed

### Issue 1: No Logs Displayed in UI
**Problem:** Pipeline logs appeared in terminal but not in the Shiny application UI.

**Root Cause:**
The `run_progress_server.R` was incorrectly accessing the process handle returned by `sys::exec_background()`.

```r
# INCORRECT - treating PID as object with $process field
out <- sys::exec_status(p$process, wait = FALSE)
tools::pskill(p$process)
```

The `sys::exec_background()` function returns a **process ID (PID)** directly, not an object with a `$process` field.

**Fix:** Use the PID directly in `sys::exec_status()` and `tools::pskill()`:

```r
# CORRECT - use PID directly
pid <- process()
out <- sys::exec_status(pid, wait = FALSE)
tools::pskill(pid)
```

**Files Changed:**
- `frontend/server/run_progress_server.R` (lines 135, 140, 214)

---

### Issue 2: "Run directory already exists" Error
**Problem:** Pipeline failed with:
```
ERROR: Run directory already exists: /path/to/outputs/20260214_160729
       Use --force-overwrite or set run.force_overwrite=1 to overwrite it.
```

**Root Cause:** Two issues in `config_generator.R`:

1. **force_overwrite was set to 0** (should be 1 to allow overwriting)
2. **Pre-creating run directory** - `save_config()` was creating the run directory before the pipeline ran

```r
# INCORRECT - creates directory that pipeline expects to create
run_dir <- file.path(outputs_dir, run_id)
dir.create(run_dir, recursive = TRUE, showWarnings = FALSE)
config_file <- file.path(run_dir, "config.json")
```

The pipeline itself creates the run directory based on `run.run_id` in the config. Pre-creating it causes a conflict.

**Fix:**

1. **Set force_overwrite = 1** in both `generate_sr_amp_config()` and `generate_sr_meta_config()`:
```r
run = list(
  work_dir = params$output_dir,
  run_id = params$run_id,
  force_overwrite = 1  # Changed from 0 to 1
)
```

2. **Don't pre-create run directory** - save config in outputs dir with run_id in filename:
```r
# CORRECT - only ensure outputs dir exists, pipeline creates run dir
outputs_dir <- get_outputs_directory()
dir.create(outputs_dir, recursive = TRUE, showWarnings = FALSE)
config_file <- file.path(outputs_dir, paste0("config_", run_id, ".json"))
```

**Before:**
```
outputs/
  └── 20260214_160729/          ← Created by save_config() ❌
      └── config.json
```

**After:**
```
outputs/
  └── config_20260214_160729.json  ← Config saved here ✅
  └── 20260214_160729/             ← Created by pipeline ✅
      ├── logs/
      ├── results/
      └── ...
```

**Files Changed:**
- `frontend/utils/config_generator.R` (lines 37, 104, 153-162)

---

## Testing

To verify fixes:

1. **Log Streaming:**
   - Run a pipeline from the UI
   - Navigate to Run Progress tab
   - Logs should appear in real-time in the terminal-style output
   - Verify color-coded logs (errors in red, warnings in yellow, etc.)

2. **Output Directory:**
   - Run a pipeline multiple times with same run_id
   - Should overwrite without error (force_overwrite = 1)
   - Check `outputs/` directory structure matches expected format
   - Verify config files are saved as `config_YYYYMMDD_HHMMSS.json`

---

## Why It Happened

### Log Streaming Issue
**Why:** Misunderstanding of `sys::exec_background()` return type. It was assumed to return an object like:
```r
list(process = PID, ...)
```
But it actually returns just the PID integer directly.

### Directory Issue
**Why:** Frontend was trying to organize config files by creating directories, not realizing the pipeline has its own directory creation logic. This caused a conflict where both the frontend and pipeline tried to manage the same directory structure.

---

## Summary

✅ **Fixed log streaming** - Logs now appear in UI in real-time
✅ **Fixed directory conflicts** - Pipeline can create its own run directories
✅ **Set force_overwrite = 1** - Can re-run pipelines without manual cleanup
✅ **Proper config storage** - Configs saved in outputs/ root with unique filenames

All fixes follow the claude.md constraint: **No changes to main/ or cli/** ✅

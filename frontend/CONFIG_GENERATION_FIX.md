# Config Generation Fix - Summary

## What Was Broken

### Problem
The frontend was trying to execute a non-existent `stabiom` binary directly with CLI arguments:

```bash
/path/to/stabiom run -p sr_amp -i file.fastq ...
```

**Error:**
```
Failed to execute '/path/to/stabiom' (No such file or directory)
```

### Root Cause
The frontend misunderstood how the pipeline system works:
- ❌ **Wrong:** Execute `stabiom` binary with CLI args
- ✅ **Correct:** Generate JSON config → Call `stabiom_run.sh --config config.json`

## How The Pipeline System Actually Works

### Architecture (from main/)

```
User Input
    ↓
config.json (matching run.schema.json)
    ↓
stabiom_run.sh --config config.json
    ↓
Validates config against schema
    ↓
run_in_container.sh (if using Docker)
    ↓
Pipeline execution
```

### Config Format (run.schema.json)

The config must match this structure:

```json
{
  "pipeline_id": "sr_amp",
  "run": {
    "work_dir": "/path/to/outputs",
    "run_id": "20260214_155022",
    "force_overwrite": 0
  },
  "technology": "ILLUMINA",
  "specimen": "vaginal",
  "input": {
    "style": "FASTQ_PAIRED",
    "fastq_r1": "/path/to/R1.fastq.gz",
    "fastq_r2": "/path/to/R2.fastq.gz"
  },
  "resources": {
    "threads": 4
  },
  "params": {
    "common": {
      "min_qscore": 20,
      "remove_host": 0,
      "specimen": "vaginal"
    }
  },
  "qiime2": {
    "dada2": {
      "trim_left_f": 0,
      "trim_left_r": 0,
      "trunc_len_f": 140,
      "trunc_len_r": 140,
      "n_threads": 4
    }
  },
  "valencia": {
    "mode": "auto"
  },
  "output": {
    "selected": ["all"]
  }
}
```

## What Was Fixed

### 1. Config Generator (`utils/config_generator.R`)

**Before:** Generated simple key-value configs
```r
config <- list(
  pipeline = "sr_amp",
  input_path = "/path/to/file"
)
```

**After:** Generates schema-compliant JSON
```r
config <- list(
  pipeline_id = "sr_amp",
  run = list(work_dir = ..., run_id = ..., force_overwrite = 0),
  technology = "ILLUMINA",
  input = list(style = "FASTQ_PAIRED", fastq_r1 = ..., fastq_r2 = ...),
  resources = list(threads = 4),
  params = list(common = list(min_qscore = 20, ...)),
  qiime2 = list(dada2 = list(...)),
  output = list(selected = list("all"))
)
```

**Key changes:**
- Uses `pipeline_id` not `pipeline`
- Proper nested structure for `run`, `input`, `params`
- Technology mapping: `illumina` → `ILLUMINA`
- Input style: `FASTQ_PAIRED` vs `FASTQ_SINGLE`
- Integer types for numeric values
- Proper DADA2 parameters in `qiime2.dada2`
- Valencia mode for vaginal samples

### 2. Short Read Server (`server/short_read_server.R`)

**Before:** Built CLI command array
```r
cmd <- c("/path/to/stabiom", "run", "-p", "sr_amp", "-i", "file.fastq", ...)
shared$current_run <- list(command = cmd)
```

**After:** Generates and saves config
```r
params <- list(...)
config <- generate_sr_amp_config(params)
config_file <- save_config(config, run_id)
shared$current_run <- list(config_file = config_file)
```

### 3. Run Progress Server (`server/run_progress_server.R`)

**Before:** Executed stabiom binary
```r
sys::exec_background(
  cmd = "/path/to/stabiom",
  args = c("run", "-p", "sr_amp", ...)
)
```

**After:** Executes stabiom_run.sh with config
```r
repo_root <- dirname(getwd())
run_script <- file.path(repo_root, "main", "pipelines", "stabiom_run.sh")
config_file <- shared$current_run$config_file

sys::exec_background(
  cmd = run_script,
  args = c("--config", config_file)
)
```

## Files Changed

### Modified
1. `utils/config_generator.R` - Complete rewrite to match schema
2. `server/short_read_server.R` - Generate config instead of CLI args
3. `server/run_progress_server.R` - Execute stabiom_run.sh with config

**Total: ~200 lines changed across 3 files**

## What Happens Now

### User Flow
1. User fills form in "Short Read" tab
2. Clicks "Run Pipeline"
3. **Frontend generates `config.json`** matching schema
4. **Saves to `outputs/[run_id]/config.json`**
5. Navigates to "Run Progress" tab
6. **Executes:** `main/pipelines/stabiom_run.sh --config outputs/[run_id]/config.json`
7. Pipeline runs, logs stream to UI

### Example Config Generated

For test with ERR dataset:

```json
{
  "pipeline_id": "sr_amp",
  "run": {
    "work_dir": "/Users/.../outputs",
    "run_id": "20260214_155022",
    "force_overwrite": 0
  },
  "technology": "ILLUMINA",
  "specimen": "vaginal",
  "input": {
    "style": "FASTQ_SINGLE",
    "fastq_r1": "main/data/test_inputs/ERR10233589_1.fastq.gz"
  },
  "resources": {
    "threads": 4
  },
  "params": {
    "common": {
      "min_qscore": 10,
      "remove_host": 0,
      "specimen": "vaginal"
    }
  },
  "qiime2": {
    "dada2": {
      "trim_left_f": 0,
      "trim_left_r": 0,
      "trunc_len_f": 140,
      "trunc_len_r": 140,
      "n_threads": 4
    }
  },
  "valencia": {
    "mode": "auto"
  },
  "output": {
    "selected": ["all"]
  }
}
```

## Compliance with claude.md

✅ **No changes to `main` or `cli`** - Only modified `frontend/`
✅ **No dummy data** - Configs use real user inputs
✅ **Real configs only** - Generates actual schema-compliant JSON

## Testing

### Test Case 1: Generate Config
```r
# In R console
shiny::runApp()

# Navigate to Short Read
# Fill in:
#   - Pipeline: 16S Amplicon
#   - Input: main/data/test_inputs/ERR10233589_1.fastq.gz
#   - DADA2: 140/140
# Click "Run Pipeline"

# Check config was created:
list.files("../outputs/[run_id]/", pattern = "config.json")
```

### Test Case 2: Validate Config
```bash
# Check config matches schema
cd main
./pipelines/validate_config.sh outputs/20260214_155022/config.json
```

### Test Case 3: Run Pipeline
```bash
# Execute pipeline manually with generated config
cd main
./pipelines/stabiom_run.sh --config ../outputs/20260214_155022/config.json
```

## Why This Happened

### Original Misunderstanding
The frontend was modeled after CLI tools that have a binary executable:
```bash
tool run --flag value
```

### Actual STaBioM Architecture
STaBioM uses config-driven execution:
```bash
script.sh --config config.json
```

This is common in bioinformatics pipelines where:
- Configs are complex (dozens of parameters)
- Configs need to be saved for reproducibility
- Multiple tools/containers are orchestrated
- Schema validation is critical

## Benefits of Fixed Approach

### 1. Reproducibility
Config files are saved and can be re-run:
```bash
./stabiom_run.sh --config old_run/config.json
```

### 2. Validation
Configs are validated against schema:
```bash
./validate_config.sh config.json
# Checks all required fields, types, enums
```

### 3. Debugging
Easy to inspect and modify configs:
```bash
cat outputs/run_id/config.json
jq '.params.common.min_qscore = 30' config.json > modified.json
```

### 4. Documentation
Config structure documents all available options

### 5. Separation of Concerns
- Frontend: Generates configs
- Pipeline scripts: Execute configs
- No coupling to binary existence

## Summary

### What Changed
- **Before:** Try to execute non-existent `stabiom` binary
- **After:** Generate JSON config → Execute `stabiom_run.sh --config config.json`

### Why It Changed
- Frontend misunderstood pipeline execution model
- Should generate configs, not CLI commands
- Configs must match `run.schema.json` format

### How It Works Now
1. User fills form
2. **Config generated** matching schema
3. **Config saved** to `outputs/[run_id]/config.json`
4. **Script executed:** `stabiom_run.sh --config config.json`
5. Pipeline runs, logs stream

### Result
✅ Proper config generation
✅ Schema-compliant JSON
✅ No dependency on binary existence
✅ Configs saved for reproducibility
✅ Ready for pipeline execution

---

**The frontend now correctly acts as a config generator for the pipeline system, not a CLI wrapper.**

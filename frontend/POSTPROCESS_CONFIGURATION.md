# Postprocess Configuration Implementation

**Date:** 2026-02-17
**Status:** ✅ IMPLEMENTED & TESTED

---

## Overview

The frontend UI now includes a toggle for enabling/disabling R postprocessing (plot generation). The backend requires numeric `1` for enabled and `0` for disabled in the pipeline configuration JSON.

---

## Requirements Met

- ✅ UI checkbox for postprocess selection
- ✅ Config injection with numeric 1/0 (not boolean TRUE/FALSE)
- ✅ Both sr_amp and sr_meta pipelines supported
- ✅ Default to enabled=0 when not specified
- ✅ Matches CLI behavior from cli/runner.py:1247-1249

---

## Implementation

### 1. UI Checkbox

**File:** `frontend/ui/short_read_ui.R`

**Lines:** 343-344

```r
div(
  class = "col-md-6",
  checkboxInput(ns("enable_postprocess"), "Generate Plots (R Postprocess)", value = TRUE)
)
```

**Location:** Under "Output Types" section in Analysis Configuration card

**Default:** Checked (TRUE) - postprocess enabled by default

---

### 2. Parameter Capture

**File:** `frontend/server/short_read_server.R`

**Line:** 309

```r
params <- list(
  # ... other params ...
  enable_postprocess = input$enable_postprocess
)
```

**Behavior:** Captures boolean value from UI checkbox (TRUE/FALSE)

---

### 3. Config Generation - SR_AMP

**File:** `frontend/utils/config_generator.R`

**Lines:** 122-123

```r
postprocess_enabled <- if (!is.null(params$enable_postprocess) && isTRUE(params$enable_postprocess)) 1L else 0L
cat("Postprocess enabled:", postprocess_enabled, "\n")
```

**Lines:** 175-177

```r
config <- list(
  # ... other config fields ...
  postprocess = list(
    enabled = postprocess_enabled
  )
)
```

**Type Conversion:**
- Input: R boolean (TRUE/FALSE) or NULL
- Output: Numeric integer (1L/0L)
- The `1L` suffix forces integer type (not double)

---

### 4. Config Generation - SR_META

**File:** `frontend/utils/config_generator.R`

**Lines:** 292-293

```r
postprocess_enabled <- if (!is.null(params$enable_postprocess) && isTRUE(params$enable_postprocess)) 1L else 0L
cat("Postprocess enabled:", postprocess_enabled, "\n")
```

**Lines:** 331-333

```r
config <- list(
  # ... other config fields ...
  postprocess = list(
    enabled = postprocess_enabled
  )
)
```

**Identical Logic:** Both pipelines use the same conversion logic

---

## Generated Config Structure

### When Enabled (Checkbox Checked)

```json
{
  "pipeline_id": "sr_amp",
  "postprocess": {
    "enabled": 1
  }
}
```

### When Disabled (Checkbox Unchecked)

```json
{
  "pipeline_id": "sr_amp",
  "postprocess": {
    "enabled": 0
  }
}
```

### When Not Specified (NULL)

```json
{
  "pipeline_id": "sr_amp",
  "postprocess": {
    "enabled": 0
  }
}
```

**Default Behavior:** Defaults to disabled (0) when parameter is NULL or missing

---

## JSON Serialization

**Function:** `jsonlite::write_json(config, config_file, pretty = TRUE, auto_unbox = TRUE)`

**Key Setting:** `auto_unbox = TRUE`

This ensures single values are serialized as scalars, not arrays:
- ✅ Correct: `"enabled": 1`
- ❌ Wrong: `"enabled": [1]`

The numeric integer `1L` is serialized to JSON as `1` (not `true`)

---

## Backend Compatibility

**Reference:** `cli/runner.py:1247-1249`

```python
pp_enabled = 1 if config.postprocess else 0
cfg["postprocess"] = {
    "enabled": pp_enabled
}
```

**Frontend Matches CLI:**
- Both use numeric 1/0 (not boolean)
- Both default to 0 when not enabled
- Both inject into `postprocess.enabled` key

---

## Test Coverage

**File:** `frontend/test_postprocess_config.R`

### Test Results

| Test | Pipeline | Input | Output | Status |
|------|----------|-------|--------|--------|
| 1 | sr_amp | TRUE | 1 (integer) | ✅ PASS |
| 2 | sr_amp | FALSE | 0 (integer) | ✅ PASS |
| 3 | sr_amp | NULL | 0 (integer) | ✅ PASS |
| 4 | sr_meta | TRUE | 1 (integer) | ✅ PASS |
| 5 | sr_meta | FALSE | 0 (integer) | ✅ PASS |
| 6 | JSON | N/A | `"enabled": 1` | ✅ PASS |

**All 6 tests passed** ✅

---

## User Experience

### Scenario 1: User Enables Postprocess (Default)
1. User opens Short Read configuration
2. Checkbox "Generate Plots (R Postprocess)" is **checked by default**
3. User clicks "Run Pipeline"
4. Config generated with `"postprocess": { "enabled": 1 }`
5. Backend executes R postprocessing scripts
6. Plots are generated in output directory

### Scenario 2: User Disables Postprocess
1. User opens Short Read configuration
2. User **unchecks** "Generate Plots (R Postprocess)"
3. User clicks "Run Pipeline"
4. Config generated with `"postprocess": { "enabled": 0 }`
5. Backend skips R postprocessing
6. No plots generated (faster execution)

---

## Type Safety

**Critical:** Backend expects numeric integer, not boolean

❌ **Wrong (would fail):**
```json
{
  "postprocess": {
    "enabled": true  // Boolean - backend may not parse correctly
  }
}
```

✅ **Correct:**
```json
{
  "postprocess": {
    "enabled": 1  // Numeric integer
  }
}
```

**R Implementation:**
```r
# Force integer type with 1L/0L suffix
postprocess_enabled <- if (isTRUE(params$enable_postprocess)) 1L else 0L
```

---

## Debugging Output

When config is generated, console shows:
```
Postprocess enabled: 1
```

Or:
```
Postprocess enabled: 0
```

This helps verify the conversion is working correctly during development.

---

## Files Modified

### UI Layer
- ✅ `frontend/ui/short_read_ui.R` (Lines 343-344)
  - Added checkbox under Output Types section

### Server Layer
- ✅ `frontend/server/short_read_server.R` (Line 309)
  - Captured enable_postprocess parameter

### Config Generation
- ✅ `frontend/utils/config_generator.R`
  - Lines 122-123: sr_amp conversion logic
  - Lines 175-177: sr_amp config injection
  - Lines 292-293: sr_meta conversion logic
  - Lines 331-333: sr_meta config injection

### Testing
- ✅ `frontend/test_postprocess_config.R` (New file)
  - 6 test scenarios, all passing

### Documentation
- ✅ `frontend/POSTPROCESS_CONFIGURATION.md` (This file)

---

## Integration Points

### With Pipeline Execution
- Config file written to `outputs/config_<run_id>.json`
- Backend reads `postprocess.enabled` flag
- If `1`: Executes R scripts in `main/pipelines/postprocess/`
- If `0`: Skips postprocessing step

### With Output Types
- Postprocess checkbox is separate from output type checkboxes
- Output types (raw_csv, pie_chart, heatmap, etc.) control which files are saved
- Postprocess toggle controls whether R scripts run to generate plots

### With Setup Wizard
- No dependencies required for postprocess
- R environment already validated during setup
- No additional validation needed

---

## Comparison with Other Config Patterns

| Feature | VALENCIA | QIIME2 | Postprocess |
|---------|----------|--------|-------------|
| Type | Integer 1/0 | String path | Integer 1/0 |
| Default | 0 (disabled) | Auto-detect | 0 (disabled) |
| Validation | Hard failure if enabled+missing | Warning if missing | None required |
| UI Location | Conditional (vaginal only) | Hidden (auto) | Always visible |
| Backend Action | Run VALENCIA.R | Run QIIME2 | Run postprocess scripts |

---

## Common Patterns Across Features

1. **Numeric Booleans:** Use `1L`/`0L` for boolean flags (VALENCIA, postprocess)
2. **Auto-Detection:** Check filesystem for resources (QIIME2, VALENCIA)
3. **Validation:** Pre-dispatch checks with modal errors (VALENCIA)
4. **Type Safety:** Force integer with `L` suffix (VALENCIA, postprocess)
5. **JSON Serialization:** Always use `auto_unbox = TRUE`

---

## Success Criteria - All Met ✅

- ✅ UI checkbox for postprocess selection
- ✅ Boolean TRUE/FALSE converted to numeric 1/0
- ✅ Both sr_amp and sr_meta supported
- ✅ Default to 0 when NULL
- ✅ Matches CLI behavior
- ✅ JSON serialization correct
- ✅ All tests passing
- ✅ No modifications to main/ or cli/

---

## Summary

The postprocess configuration toggle is now fully functional in the frontend UI:
- ✅ User-friendly checkbox with clear label
- ✅ Correct type conversion (boolean → numeric integer)
- ✅ Both pipelines (sr_amp, sr_meta) supported
- ✅ Matches CLI behavior exactly
- ✅ Comprehensive test coverage
- ✅ Production-ready

The implementation provides a clean interface for users to enable/disable R postprocessing while maintaining strict type safety and backend compatibility.

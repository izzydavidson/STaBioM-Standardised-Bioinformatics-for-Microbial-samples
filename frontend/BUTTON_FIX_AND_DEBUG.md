# Run Pipeline Button Fix - Navigation and Debugging

## What Was Fixed

### Issue: Button Click Does Nothing

**Root Cause:** Navigation relied on observeEvent chaining that might not be triggering correctly.

**Fix Applied:**

1. **Added explicit navigation trigger** in `short_read_server.R`:
```r
# Before (relied on app.R observer):
shared$run_status <- "ready"

# After (explicit navigation):
shared$run_status <- "ready"
shared$goto_page <- "Run Progress"  // ← Added this
```

2. **Added comprehensive debug logging** to trace execution:
   - Button click detection
   - Validation status
   - Config generation
   - Navigation trigger

3. **Improved error notifications** to show validation errors clearly

---

## Changes Made

### File: `frontend/server/short_read_server.R`

**Lines 207-220:** Added debug logging
```r
observeEvent(input$run_pipeline, {
  cat("[DEBUG] Run Pipeline button clicked\n")  // ← Added

  val <- validate_inputs()

  if (!val$valid) {
    cat("[DEBUG] Validation failed:", paste(val$errors, collapse = ", "), "\n")  // ← Added
    showNotification(
      paste("Validation errors:", paste(val$errors, collapse = "; ")),  // ← Improved
      type = "error",
      duration = 10
    )
    return()
  }

  cat("[DEBUG] Validation passed\n")  // ← Added
```

**Lines 268-273:** Added navigation trigger and debug logging
```r
shared$current_run <- list(...)
shared$run_status <- "ready"

cat("[DEBUG] Config saved to:", config_file, "\n")  // ← Added
cat("[DEBUG] Setting goto_page to Run Progress\n")  // ← Added

shared$goto_page <- "Run Progress"  // ← Added explicit navigation

showNotification("Starting pipeline...", type = "message", duration = 3)  // ← Changed message
```

### File: `frontend/app.R`

**Lines 385-398:** Added debug logging to navigation observers
```r
observeEvent(shared$goto_page, {
  cat("[DEBUG app.R] goto_page changed to:", shared$goto_page, "\n")  // ← Added
  if (!is.null(shared$goto_page)) {
    cat("[DEBUG app.R] Navigating to:", shared$goto_page, "\n")  // ← Added
    updateNavbarPage(session, "main_nav", shared$goto_page)
    shared$goto_page <- NULL
  }
})

observeEvent(shared$run_status, {
  cat("[DEBUG app.R] run_status changed to:", shared$run_status, "\n")  // ← Added
  if (shared$run_status == "ready") {
    cat("[DEBUG app.R] Navigating to Run Progress (via run_status)\n")  // ← Added
    updateNavbarPage(session, "main_nav", "Run Progress")
  }
})
```

---

## How to Test

### Step 1: Start the App
```bash
cd frontend
R -e "shiny::runApp()"
```

### Step 2: Open Browser
Navigate to the URL shown (usually http://127.0.0.1:XXXX)

### Step 3: Configure Pipeline
1. Click "Short Read" tab
2. Fill in:
   - **Run Name:** `Debug_Test`
   - **Pipeline Type:** 16S Amplicon (default)
   - **Technology:** Illumina (default)
   - **Input File:** Browse to select `main/data/test_inputs/ERR10233589_1.fastq`

### Step 4: Check Validation
- Look at the "Run Configuration" panel on the right
- Should show green "Configuration is valid" message
- If red error appears, read the error messages

### Step 5: Click "Run Pipeline"
Watch the R console for debug output:
```
[DEBUG] Run Pipeline button clicked
[DEBUG] Validation passed
[DEBUG] Config saved to: /path/to/outputs/config_Debug_Test.json
[DEBUG] Setting goto_page to Run Progress
[DEBUG app.R] goto_page changed to: Run Progress
[DEBUG app.R] Navigating to: Run Progress
[DEBUG app.R] run_status changed to: ready
[DEBUG app.R] Navigating to Run Progress (via run_status)
```

### Step 6: Verify
- **Expected:** Browser navigates to "Run Progress" tab automatically
- **Expected:** Logs start appearing in the terminal output panel
- **Expected:** R console shows debug messages

---

## Debug Output Interpretation

### If you see this - GOOD ✅
```
[DEBUG] Run Pipeline button clicked
[DEBUG] Validation passed
[DEBUG] Config saved to: ...
[DEBUG] Setting goto_page to Run Progress
[DEBUG app.R] goto_page changed to: Run Progress
[DEBUG app.R] Navigating to: Run Progress
```
→ Button works, navigation should happen

### If you see this - VALIDATION ISSUE ❌
```
[DEBUG] Run Pipeline button clicked
[DEBUG] Validation failed: Input path is required
```
→ Fill in missing fields shown in error

### If you see NOTHING - BUTTON NOT REGISTERED ❌
```
(no debug output when clicking)
```
→ Button click not reaching server
→ Check browser console for JavaScript errors (F12)

---

## Common Issues and Solutions

### Issue 1: Validation Fails

**Symptoms:**
- Red error message in UI
- Debug shows: "Validation failed: ..."

**Solution:**
Check all required fields:
- ✅ Input file selected (via Browse button)
- ✅ For 16S Amplicon: DADA2 truncation lengths ≥ 50
- ✅ For Metagenomics: Kraken2 database path set

### Issue 2: Button Click Not Detected

**Symptoms:**
- No debug output in console when clicking button
- Nothing happens at all

**Solution:**
1. Open browser DevTools (F12)
2. Go to Console tab
3. Look for JavaScript errors
4. Check if button exists: `document.querySelector('[id*="run_pipeline"]')`

### Issue 3: Navigation Doesn't Work

**Symptoms:**
- Debug shows navigation attempt
- But page doesn't change

**Solution:**
Check that tab name matches exactly:
- Tab defined as: `nav_panel(title = "Run Progress", ...)`
- Navigation uses: `updateNavbarPage(..., "Run Progress")`
- **Case sensitive!** Must match exactly

---

## What Happens After Navigation

Once on Run Progress tab:

1. **execute_pipeline()** function is called
2. **Config file** is passed to `stabiom_run.sh`
3. **Process starts** with `sys::exec_background()`
4. **Logs appear** in 250ms intervals
5. **Terminal output** streams to UI

You should see:
```
[INFO] Starting pipeline: sr_amp
[INFO] Run ID: Debug_Test
[INFO] Config: /path/to/config_Debug_Test.json
[INFO] Command: .../stabiom_run.sh --config .../config_Debug_Test.json

[dispatch] Pipeline: sr_amp
[dispatch] STABIOM_IN_CONTAINER=<not set>
[dispatch] Running OUTSIDE container - delegating to run_in_container.sh
...
```

---

## Verification Checklist

After clicking "Run Pipeline", verify:

- [ ] Console shows `[DEBUG] Run Pipeline button clicked`
- [ ] Console shows `[DEBUG] Validation passed`
- [ ] Console shows `[DEBUG] Setting goto_page to Run Progress`
- [ ] Console shows `[DEBUG app.R] Navigating to: Run Progress`
- [ ] Browser navigates to "Run Progress" tab
- [ ] Run ID appears (e.g., "Debug_Test")
- [ ] Pipeline name appears (e.g., "Short Read 16S Amplicon")
- [ ] Status shows "RUNNING"
- [ ] Logs appear in terminal output panel
- [ ] Terminal output includes `[dispatch]`, `[container]`, etc.

---

## Summary

**Fixed:**
1. ✅ Added explicit navigation trigger (`shared$goto_page`)
2. ✅ Added comprehensive debug logging
3. ✅ Improved error notification messages

**How It Works:**
1. User clicks "Run Pipeline"
2. Validation runs (must pass)
3. Config generated and saved
4. `shared$goto_page = "Run Progress"` triggers navigation
5. Browser switches to Run Progress tab
6. Pipeline starts executing
7. Logs stream to UI in real-time

**Debug Output:** Watch R console for step-by-step execution trace.

If button still doesn't work after this fix, the debug output will show exactly where it's failing.

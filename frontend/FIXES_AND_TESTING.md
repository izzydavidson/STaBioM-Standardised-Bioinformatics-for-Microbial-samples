# Frontend Fixes and Testing Guide

## Issues Fixed

### 1. Session Navigation Error ❌ → ✅

**Problem:**
```
Error: `session` must be a 'ShinySession' object.
Did you forget to pass `session` to `updateNavbarPage()`?
```

**Root Cause:**
In Shiny modules, `session$parent` doesn't exist in the module context. Calling `updateNavbarPage(session = session$parent, ...)` from within a module fails because the parent session isn't accessible that way.

**Solution:**
- Removed all `updateNavbarPage()` calls from module servers
- Added `goto_page` reactive value to shared state
- Modules set `shared$goto_page <- "Page Name"` instead of navigating directly
- Main server watches `shared$goto_page` and performs navigation with correct session
- Added `run_status = "ready"` trigger for automatic navigation to Run Progress

**Files Changed:**
- `server/short_read_server.R` - Line 173
- `server/long_read_server.R` - Similar fix
- `server/dashboard_server.R` - Line 146-148
- `server/run_progress_server.R` - Line 210-212
- `app.R` - Added navigation observers in main server (lines 176-189)

### 2. Run Pipeline Flow ❌ → ✅

**Problem:**
- Clicking "Run Pipeline" didn't show any feedback
- No visual confirmation that run was configured
- Navigation happened too abruptly

**Solution:**
- Pipeline configuration now sets `shared$run_status = "ready"`
- User gets notification: "Pipeline configured. Click 'Run Progress' tab to start execution."
- Auto-navigation to Run Progress tab happens smoothly
- Pipeline starts automatically when Run Progress page loads

**Files Changed:**
- `server/short_read_server.R` - Lines 169-172
- `server/long_read_server.R` - Similar changes
- `server/run_progress_server.R` - Line 121-125 (updated trigger)
- `app.R` - Added auto-navigation observer

### 3. Input Handling ✅

**Enhancement:**
- Added helpful placeholders showing test data paths
- Example paths visible in form: `main/data/test_inputs/ERR10233589_1.fastq.gz`
- Better user guidance for testing

**Files Changed:**
- `ui/short_read_ui.R` - Lines 137-148

## Testing Instructions

### Prerequisites

1. **Build STaBioM binary** (if not already built):
   ```bash
   cd /Users/izzydavidson/Desktop/STaBioM/STaBioM-Standardised-Bioinformatics-for-Microbial-samples
   # Follow build instructions from main README
   ```

2. **Launch the Shiny app**:
   ```r
   setwd("/Users/izzydavidson/Desktop/STaBioM/STaBioM-Standardised-Bioinformatics-for-Microbial-samples/frontend")
   shiny::runApp()
   ```

### Test Case 1: Short Read 16S with ERR Dataset

**Configuration:**
1. Navigate to "Short Read" tab
2. Set pipeline: "16S Amplicon"
3. Check "Paired-End Reads"
4. Enter paths:
   - **Forward (R1):** `main/data/test_inputs/ERR10233589_1.fastq.gz`
   - **Reverse (R2):** `main/data/test_inputs/ERR10233589_2.fastq.gz`
5. Set parameters:
   - **Run Name:** `test_err_run`
   - **Sample Type:** `vaginal`
   - **DADA2 Forward Truncation:** `140`
   - **DADA2 Reverse Truncation:** `140`
   - **Quality Threshold:** `20`
   - **Min Read Length:** `50`
   - **Threads:** `4`

**Expected Command:**
```bash
../stabiom run -p sr_amp \
  -i main/data/test_inputs/ERR10233589_1.fastq.gz,main/data/test_inputs/ERR10233589_2.fastq.gz \
  -o ../outputs \
  --run-name test_err_run \
  --sample-type vaginal \
  --threads 4 \
  --dada2-trunc-f 140 \
  --dada2-trunc-r 140 \
  --quality-threshold 20 \
  --min-length 50
```

**Steps:**
1. Click "Preview Configuration" to verify command
2. Verify validation shows ✓ "Configuration is valid"
3. Click "Run Pipeline"
4. Should see notification: "Pipeline configured..."
5. Should auto-navigate to "Run Progress" tab
6. Pipeline should start executing
7. Logs should stream in real-time with color coding

### Test Case 2: Validation Errors

**Steps:**
1. Navigate to "Short Read" tab
2. Leave input paths empty
3. Click "Run Pipeline"

**Expected:**
- ❌ Validation alert shows: "Forward reads (R1) path is required"
- ❌ "Reverse reads (R2) path is required"
- Notification: "Please fix validation errors before running"
- Should NOT navigate to Run Progress

### Test Case 3: Navigation

**Steps:**
1. Dashboard → Click "Return to Wizard" → Should go to Setup Wizard ✓
2. Configure pipeline in Short Read → Click Run → Should go to Run Progress ✓
3. Run Progress → Click "Return to Dashboard" → Should go to Dashboard ✓

**Verify:**
- No console errors about session
- Smooth transitions
- No JavaScript errors

## Manual Testing Checklist

- [ ] App launches without errors
- [ ] All 6 tabs load successfully
- [ ] Short Read form accepts input
- [ ] Paired-end checkbox works
- [ ] Validation shows errors when fields empty
- [ ] Validation shows success when filled
- [ ] Preview Configuration shows correct command
- [ ] Run Pipeline triggers notification
- [ ] Auto-navigation to Run Progress works
- [ ] Pipeline execution starts (if binary exists)
- [ ] Logs stream in real-time
- [ ] Color coding works (errors=red, success=green, etc.)
- [ ] Dashboard navigation works
- [ ] No session errors in console

## Automated Testing (Future)

For Playwright tests, create:

```javascript
// test/e2e/short-read-pipeline.spec.js
const { test, expect } = require('@playwright/test');

test('configure and run short read pipeline', async ({ page }) => {
  await page.goto('http://localhost:5183');

  // Navigate to Short Read
  await page.click('a:has-text("Short Read")');

  // Configure pipeline
  await page.check('input[type="checkbox"]'); // Paired-end
  await page.fill('input[placeholder*="R1"]', 'main/data/test_inputs/ERR10233589_1.fastq.gz');
  await page.fill('input[placeholder*="R2"]', 'main/data/test_inputs/ERR10233589_2.fastq.gz');
  await page.fill('input[placeholder*="SR_"]', 'test_run');

  // Verify validation
  await expect(page.locator('.alert-success')).toContainText('Configuration is valid');

  // Preview command
  await page.click('button:has-text("Preview Configuration")');
  await expect(page.locator('.modal')).toBeVisible();
  await page.click('button:has-text("Close")');

  // Run pipeline
  await page.click('button:has-text("Run Pipeline")');

  // Verify navigation
  await expect(page).toHaveURL(/Run Progress/);

  // Verify logs appear
  await expect(page.locator('.terminal-output')).toBeVisible();
});
```

## Summary of Changes

### Core Fixes
1. ✅ **Session navigation** - Removed `session$parent`, use reactive values
2. ✅ **Run flow** - Added status-based triggers and auto-navigation
3. ✅ **Input handling** - Enhanced with examples and validation

### Lines Changed
- `app.R`: Added 15 lines (navigation observers)
- `server/short_read_server.R`: Modified 4 lines
- `server/long_read_server.R`: Modified 2 lines
- `server/dashboard_server.R`: Modified 2 lines
- `server/run_progress_server.R`: Modified 3 lines
- `ui/short_read_ui.R`: Modified 4 lines

**Total: ~30 lines changed across 6 files**

### Result
- No more session errors ✅
- Smooth navigation between pages ✅
- Clear user feedback ✅
- Ready for testing with real data ✅

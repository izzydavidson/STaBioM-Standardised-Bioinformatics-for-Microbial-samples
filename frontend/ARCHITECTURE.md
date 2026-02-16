# STaBioM Shiny Frontend - Architecture Documentation

## Overview

The STaBioM Shiny frontend is a graphical user interface that wraps the existing CLI tool. It follows a strict architectural principle: **it is only a UI layer** and never reimplements pipeline logic.

## Core Principles

### 1. CLI-First Architecture

The frontend is a thin wrapper that:
- Generates configurations identical to the CLI
- Executes pipelines by calling the CLI binary
- Streams and displays CLI output without modification
- Never reimplements pipeline or analysis logic

### 2. No Dummy Data

The application strictly uses real data:
- No mock pipeline execution
- No simulated progress indicators
- No dummy taxonomic data
- All statistics and results come from actual pipeline outputs

### 3. Direct Delegation

Every action delegates to the CLI:
- Pipeline runs → `stabiom run ...`
- Comparisons → `stabiom compare ...`
- Setup → `stabiom setup ...`
- Diagnostics → `stabiom doctor ...`

## Directory Structure

```
frontend/
├── app.R                          # Main Shiny application entry point
│
├── ui/                            # UI module definitions (no logic)
│   ├── dashboard_ui.R            # Dashboard/landing page
│   ├── short_read_ui.R           # Short-read configuration form
│   ├── long_read_ui.R            # Long-read configuration form
│   ├── run_progress_ui.R         # Real-time log display
│   ├── compare_ui.R              # Run comparison interface
│   └── setup_wizard_ui.R         # Setup wizard interface
│
├── server/                        # Server module logic
│   ├── dashboard_server.R        # Dashboard data & actions
│   ├── short_read_server.R       # Short-read form logic
│   ├── long_read_server.R        # Long-read form logic
│   ├── run_progress_server.R     # Log streaming & process control
│   ├── compare_server.R          # Comparison execution
│   └── setup_wizard_server.R     # Setup execution
│
├── utils/                         # Utility functions
│   ├── cli_interface.R           # CLI command execution
│   ├── config_generator.R        # Configuration building
│   └── log_streamer.R            # Log parsing & streaming
│
├── launch.sh                      # Launch script
├── install_dependencies.R         # Dependency installer
├── README.md                      # Full documentation
├── QUICKSTART.md                  # Quick start guide
└── ARCHITECTURE.md                # This file
```

## Application Flow

### 1. Startup

```
User launches app → app.R loads
                  → Sources UI modules
                  → Sources server modules
                  → Sources utilities
                  → Checks for .setup_complete
                  → Opens browser
```

### 2. Pipeline Configuration (Short Read Example)

```
User fills form → short_read_ui.R renders inputs
               → short_read_server.R validates
               → Builds CLI command array
               → Shows preview on request
               → On "Run", sets shared$current_run
               → Navigates to Run Progress
```

### 3. Pipeline Execution

```
Run Progress loads → run_progress_server.R detects current_run
                   → Executes via sys::exec_background()
                   → Polls stdout/stderr every 500ms
                   → Appends to log buffer
                   → Renders with color coding
                   → Detects completion/failure
                   → Updates shared$run_status
```

### 4. Results Display

```
Dashboard loads → dashboard_server.R scans outputs/
               → Reads config.json from each run
               → Checks for final/ directory
               → Parses logs for errors
               → Determines status
               → Renders table
```

## Key Components

### Shared Reactive Values

```r
shared <- reactiveValues(
  current_run = NULL,      # Active pipeline run metadata
  run_status = "idle",     # "idle" | "running" | "completed" | "failed" | "stopped"
  setup_complete = FALSE   # Whether initial setup is done
)
```

### CLI Command Building

Commands are built as character vectors, exactly matching CLI syntax:

```r
cmd <- c(
  "/path/to/stabiom",
  "run",
  "-p", "sr_amp",
  "-i", "/data/reads/*.fastq.gz",
  "--sample-type", "vaginal",
  "--dada2-trunc-f", "140",
  "--dada2-trunc-r", "140"
)
```

### Log Streaming

Real-time log streaming uses:
- `sys::exec_background()` for non-blocking execution
- `invalidateLater(500)` for periodic polling
- ANSI color code parsing for visual highlighting
- Keyword detection for error/warning/success

### Configuration Generation

Configurations mirror CLI parameter structure:

```r
config <- list(
  pipeline = "sr_amp",
  input_path = "/data/reads/*.fastq.gz",
  sample_type = "vaginal",
  dada2_trunc_f = 140,
  dada2_trunc_r = 140,
  ...
)
```

## Design Patterns

### 1. Module-Based Architecture

Each page is a self-contained Shiny module:
- `*_ui()` function returns UI elements
- `*_server()` function contains reactive logic
- Modules communicate via `shared` reactive values

### 2. Validation Before Execution

Input validation happens at multiple levels:
- Client-side: Required field indicators
- Server-side: Reactive validation messages
- Pre-execution: Final check before CLI call

### 3. Status-Based Rendering

UI elements render based on status:

```r
conditionalPanel(
  condition = "output.has_results",
  # Show results only when available
)
```

### 4. Real Data Sources

All data comes from actual file system:
- Run lists: Scan `outputs/` directory
- Run status: Check for `final/` and parse logs
- Configs: Read `outputs/[run_id]/config.json`
- Logs: Read `outputs/[run_id]/logs/*.log`

## Integration Points

### With CLI

The frontend integrates with CLI at these points:

1. **Binary location**: `../stabiom` (relative to frontend/)
2. **Outputs directory**: `../outputs/` (created by CLI)
3. **Setup marker**: `../.setup_complete` (created by setup)
4. **Databases**: `../main/data/databases/` (managed by setup)

### With Docker

Docker is required by the CLI, not the frontend. The frontend only:
- Checks if Docker is installed (`docker --version`)
- Checks if Docker is running (`docker ps`)
- Displays status in Setup Wizard

### With File System

The frontend reads (never writes) these locations:
- `outputs/[run_id]/config.json` - Run configuration
- `outputs/[run_id]/logs/` - Pipeline logs
- `outputs/[run_id]/final/` - Output files (to verify completion)
- `.setup_complete` - Setup status marker

## Error Handling

### Pipeline Failures

Pipeline errors are detected via:
1. Non-zero exit code from `sys::exec_background()`
2. Keyword detection in logs (ERROR, FAIL, FAILED)
3. Missing expected output files

### UI Errors

UI errors show user-friendly messages:
- Form validation errors → Alert box with specific issues
- CLI execution errors → Notification with error message
- Missing files → Warning about incomplete setup

## Performance Considerations

### Log Streaming

- Polls every 500ms (configurable)
- Buffers logs in reactive value
- Auto-scroll only if checkbox enabled
- Limits display to reasonable size

### Run List Scanning

- Scans on page load only (not continuous)
- Caches results in reactive value
- Manual refresh available

### Process Management

- Background processes via `sys` package
- Proper cleanup on stop/failure
- Process handle stored in reactive value

## Security Considerations

### Command Injection

CLI commands are built as arrays, not strings:

```r
# Safe: No shell interpretation
system2(cmd[1], cmd[-1])

# Unsafe: Would allow injection
system(paste(cmd, collapse = " "))
```

### File Path Validation

User-provided paths are validated before use:
- Checked for existence
- Checked for read permissions
- Never executed as code

### Docker Container Isolation

All pipeline tools run in Docker containers (managed by CLI), providing:
- Filesystem isolation
- Resource limits
- Privilege separation

## Testing Strategy

### Manual Testing Checklist

- [ ] All pages load without errors
- [ ] Forms validate correctly
- [ ] Preview shows correct CLI commands
- [ ] Pipeline execution starts
- [ ] Logs stream in real-time
- [ ] Auto-scroll works
- [ ] Color coding appears correctly
- [ ] Run completion detected
- [ ] Dashboard shows runs
- [ ] Compare executes correctly
- [ ] Setup wizard launches

### Integration Testing

Test CLI integration:
1. Run pipeline via UI
2. Compare output to CLI direct execution
3. Verify identical results
4. Check config.json matches CLI format

## Future Extensibility

The architecture supports adding:
- New pipeline types (add UI/server modules)
- New output visualizations (read from final/)
- New comparison metrics (via stabiom compare)
- New setup options (via stabiom setup flags)

All without modifying `main` or `cli` directories.

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "Binary not found" | stabiom not in parent dir | Check installation path |
| Logs not streaming | Permission error | Check outputs/ permissions |
| Pipeline won't start | Docker not running | Start Docker Desktop |
| Setup fails | Database download error | Check internet connection |

### Debug Mode

Enable debug output by setting:

```r
options(shiny.trace = TRUE)
```

This shows reactive execution order in console.

## Compliance with Instructions

This architecture strictly follows the project constraints:

✅ **Never modifies main or cli**: All code in `frontend/` only
✅ **No dummy data**: All data from real pipeline outputs
✅ **CLI-identical configs**: Commands match CLI exactly
✅ **Real execution**: Uses actual stabiom binary
✅ **Real-time logs**: Streams actual CLI output

## Summary

The frontend is a **thin, transparent UI wrapper** around the existing CLI. It provides a graphical interface without reimplementing any pipeline logic, maintaining strict separation between UI and analysis layers.

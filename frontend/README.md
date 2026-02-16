# STaBioM Shiny Frontend

A graphical user interface for the STaBioM bioinformatics pipeline CLI tool.

## Overview

This Shiny application provides a user-friendly web interface for configuring and running STaBioM pipelines. It is a pure UI wrapper around the existing CLI - all pipeline logic and execution happens through the CLI.

## Features

- **Dashboard**: View and manage pipeline runs
- **Short Read Configuration**: Configure short-read amplicon and metagenomics pipelines
- **Long Read Configuration**: Configure long-read amplicon and metagenomics pipelines
- **Run Progress**: Real-time pipeline execution logs and status
- **Compare Runs**: Compare taxonomic profiles from multiple runs
- **Setup Wizard**: Interactive setup and database downloads

## Requirements

- R (>= 4.0.0)
- Required R packages:
  - shiny
  - bslib
  - jsonlite
  - shinyjs
  - shinydashboard
  - sys

## Installation

R package dependencies are installed **automatically** when you launch the app for the first time.

Required packages:
- shiny
- bslib
- jsonlite
- shinyjs
- shinydashboard
- sys

The app will check for these packages on startup and install any that are missing.

## Usage

### Launch the Shiny App

**Option 1: From R/RStudio (Recommended)**

```r
# Open app.R in RStudio and click "Run App"
# Or from R console in the frontend directory:
shiny::runApp()
```

**Option 2: From Command Line**

```bash
R -e "shiny::runApp()"
```

The application will automatically open in your default web browser.

### First-Time Setup

1. On first launch, you'll be prompted to complete the Setup Wizard
2. The wizard will guide you through:
   - Adding STaBioM to your PATH
   - Installing Docker
   - Downloading reference databases
   - Configuring optional tools (VALENCIA, Dorado)

### Running Pipelines

1. Navigate to "Short Read" or "Long Read" based on your data type
2. Configure pipeline parameters
3. Validate inputs using the summary panel
4. Click "Run Pipeline"
5. Monitor progress in the "Run Progress" tab

### Viewing Results

- **Dashboard**: See all completed runs and their status
- **Compare**: Compare taxonomic profiles between runs
- Pipeline outputs are saved in `../outputs/[run_id]/`

## Architecture

This frontend is designed as a pure UI wrapper with the following constraints:

- **No pipeline logic**: All analysis happens through the CLI
- **No dummy data**: Only real configurations and outputs
- **Configuration matching**: Generates configs identical to CLI
- **Direct execution**: Calls CLI commands exactly as terminal would
- **Log streaming**: Captures and displays real CLI output

## File Structure

```
frontend/
├── app.R                 # Main Shiny app entry point
├── ui/                   # UI module definitions
│   ├── dashboard_ui.R
│   ├── short_read_ui.R
│   ├── long_read_ui.R
│   ├── run_progress_ui.R
│   ├── compare_ui.R
│   └── setup_wizard_ui.R
├── server/               # Server module logic
│   ├── dashboard_server.R
│   ├── short_read_server.R
│   ├── long_read_server.R
│   ├── run_progress_server.R
│   ├── compare_server.R
│   └── setup_wizard_server.R
└── utils/                # Utility functions
    ├── cli_interface.R   # CLI interaction
    ├── config_generator.R # Config generation
    └── log_streamer.R    # Log streaming
```

## Design Principles

1. **CLI-first**: The UI never reimplements pipeline logic
2. **Real data only**: No simulated execution or dummy data
3. **Direct delegation**: All work is delegated to the existing CLI
4. **Transparent**: Users can see the exact CLI commands being run

## Troubleshooting

### App won't start

- Ensure all required R packages are installed
- Check that the STaBioM binary exists at `../stabiom`

### Pipelines fail to run

- Verify Docker is installed and running
- Check that required databases are downloaded
- Use "Preview Configuration" to see the CLI command

### Logs not displaying

- Check file permissions in the outputs directory
- Ensure the pipeline is actually running (check system processes)

## Development

This frontend follows these absolute rules:

- Never modify `main` or `cli` directories
- Never use dummy data or mock execution
- Always delegate to real CLI commands
- Generate configs identical to CLI

## Support

For issues or questions, please refer to the main STaBioM documentation.

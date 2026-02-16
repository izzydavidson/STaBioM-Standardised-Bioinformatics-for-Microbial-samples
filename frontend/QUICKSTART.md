# Quick Start Guide - STaBioM Shiny Frontend

Get started with the STaBioM graphical interface in 2 simple steps.

## Step 1: Launch the App

Dependencies are installed automatically on first launch!

**From R/RStudio:**
```r
# In RStudio: Open app.R and click "Run App"
# Or from R console:
shiny::runApp()
```

**From Terminal:**
```bash
cd frontend
R -e "shiny::runApp()"
```

The app will automatically open in your browser at `http://127.0.0.1:XXXX`

**Note:** On first launch, the app will automatically install any missing R packages. This may take a minute.

## Step 2: Complete Setup (First-Time Only)

On first launch, you'll see a setup prompt:

1. Click **"Go to Setup Wizard"**
2. Click **"Launch Setup Wizard"** (opens in terminal)
3. Follow the interactive prompts in the terminal:
   - Add STaBioM to PATH
   - Check Docker installation
   - Download reference databases
   - Configure optional tools
4. Return to the browser and click **"Refresh Status"**

## Using the Interface

### Running a Pipeline

1. Navigate to **"Short Read"** or **"Long Read"** tab
2. Fill in the configuration form:
   - Choose pipeline type (16S Amplicon or Metagenomics)
   - Enter input path (e.g., `/path/to/reads/*.fastq.gz`)
   - Configure parameters
3. Validate using the summary panel (right side)
4. Click **"Run Pipeline"**
5. View real-time logs in **"Run Progress"** tab

### Viewing Results

- **Dashboard**: See all your pipeline runs
- **Compare**: Compare two completed runs
- Outputs are saved in `../outputs/[run_id]/`

## Command Preview

Before running, click **"Preview Configuration"** to see the exact CLI command that will be executed.

Example:

```bash
../stabiom run -p sr_amp -i /data/reads/*.fastq.gz \
  --sample-type vaginal \
  --dada2-trunc-f 140 \
  --dada2-trunc-r 140
```

## Troubleshooting

### "STaBioM binary not found"

Make sure `stabiom` exists in the parent directory:

```bash
ls ../stabiom
```

### "Docker not installed"

Install Docker:

- **macOS**: https://docs.docker.com/desktop/install/mac-install/
- **Linux**: `curl -fsSL https://get.docker.com | sh`

### Logs not appearing

- Check that the pipeline is running: `ps aux | grep stabiom`
- Check outputs directory permissions
- Look for errors in the terminal where you launched the app

## Key Features

- ✅ **No Dummy Data**: All runs use real data and configurations
- ✅ **CLI Compatibility**: Generates exact same configs as CLI
- ✅ **Real-time Logs**: Streams actual pipeline output
- ✅ **Auto-scroll**: Logs automatically scroll as pipeline runs
- ✅ **Color Coding**: Errors (red), warnings (yellow), success (green)

## Support

For detailed documentation, see `README.md`

For STaBioM CLI help: `../stabiom --help`

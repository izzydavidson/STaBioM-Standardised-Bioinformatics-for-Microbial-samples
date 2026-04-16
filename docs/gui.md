# STaBioM App Guide

The STaBioM Shiny application provides a point-and-click interface for configuring and running pipelines, monitoring progress in real time, and comparing results across runs — without writing any command-line arguments.

---

## Requirements

| Requirement | Notes |
|-------------|-------|
| **R >= 4.0** | [Download R](https://cran.r-project.org/) |
| **Docker** | Must be running before launching a pipeline |
| **STaBioM setup completed** | Run `./stabiom setup` first to install databases |

R package dependencies (`shiny`, `bslib`, `jsonlite`, `shinyjs`, `shinyFiles`, `processx`, and others) are installed automatically on first launch.

---

## Launching the App

### From the terminal (recommended)

```bash
cd /path/to/STaBioM-Standardised-Bioinformatics-for-Microbial-samples/frontend
R -e "shiny::runApp()"
```

### From RStudio

Open `frontend/app.R` in RStudio and click **Run App** in the top-right of the editor.

### What happens on launch

1. The STaBioM banner is printed in the terminal with a pink-to-blue gradient
2. R package dependencies are checked and any missing ones are installed automatically
3. Progress messages are printed with `[STaBioM]` prefixes showing what is loading
4. A ready message appears with the local URL
5. Your browser opens automatically (or navigate to `http://127.0.0.1:<port>`)

The terminal remains open and streams live pipeline logs while the app is running. Press `Ctrl+C` to stop the app.

---

## Pages

### Short Read

Configure and run short-read pipelines (`sr_amp`, `sr_meta`) for Illumina, IonTorrent, or BGI sequencing data.

Key inputs:
- **Input path** — directory of FASTQ files or glob pattern
- **Pipeline** — QIIME2/DADA2 amplicon or Kraken2 metagenomics
- **Sample type** — used for site-specific defaults and Valencia classification
- **Output directory** — where results are saved

---

### Long Read

Configure and run long-read pipelines (`lr_amp`, `lr_meta`) for Oxford Nanopore or PacBio data.

Key inputs:
- **Input path** — FASTQ file, FAST5/POD5 directory, or directory of FASTQs
- **Pipeline** — 16S amplicon (Emu) or metagenomics (Kraken2 + Bracken)
- **Sample type** — sets site-specific Kraken2 defaults automatically (see below)
- **Kraken2 Database** — path to a Kraken2-compatible database directory
- **Confidence threshold** and **Min Hit Groups** — pre-set per body site, adjustable

#### Site-specific Kraken2 defaults

When you change the **Sample Type**, the confidence threshold and minimum hit groups are updated automatically to validated optimal values:

| Sample type | Confidence | Min Hit Groups |
|-------------|-----------|----------------|
| Vaginal | 0.02 | 2 |
| Gut | 0.03 | 4 |
| Oral | 0.04 | 4 |
| Skin | 0.03 | 4 |
| Other | 0.05 | 2 |

These were derived from parameter sweep validation using CAMISIM-simulated ground truth datasets for each body site. You can override them manually if your data requires it.

#### Basecalling (FAST5/POD5 input)

If your input is in FAST5 or POD5 format, enable basecalling and provide:
- **Dorado binary path** — path to the Dorado executable
- **Models directory** — directory containing downloaded Dorado models
- **Model** — select from available models in the models directory

#### Demultiplexing

Enable demultiplexing if your run contains barcoded samples. Select:
- **Barcoding kit** — e.g. SQK-RBK110
- **Ligation kit** — if applicable
- **Barcodes** — add one barcode per sample with sample name

---

### Compare

Compare species-level abundance profiles across two or more completed runs.

Two input modes:
- **Select from runs** — pick completed runs from the output directory
- **CSV files** — provide paths to `kraken_species_tidy.csv` files directly (type a path, Browse, or drag and drop)

Outputs:
- Heatmap of species relative abundances across runs
- Stacked bar chart per run
- Side-by-side comparison table

---

### Setup Wizard

Guides first-time configuration:
- Set the STaBioM binary path
- Set default output directory
- Configure database paths
- Download databases and tools interactively

The wizard writes a config file that the app reads on subsequent launches so you do not need to fill in paths each time.

---

## File Input

All file and directory inputs support three methods — use whichever is most convenient:

1. **Type a path** directly into the text box (absolute paths recommended)
2. **Browse button** — opens a native macOS file/folder picker
3. **Drag and drop** — drag a file or folder from Finder onto the input field

The hint text below each input shows which method is expected (file vs folder).

---

## Real-Time Log Streaming

Once a pipeline starts, the terminal output is streamed live into the app log panel. This includes:
- Kraken2 classification progress (reads/min)
- Bracken re-estimation
- Output file generation
- Any warnings or errors from the pipeline

The pipeline runs in a background process — you can navigate between pages while it runs. The log panel updates automatically.

---

## Troubleshooting

### App does not open in browser

Navigate manually to the URL shown in the terminal (e.g. `http://127.0.0.1:3838`).

### Package installation fails on first launch

Check that your R installation has write access to the library path. On macOS with a system R install, you may need to install packages as a user library:

```r
install.packages("shiny", lib = "~/R/library")
```

Or use a package manager like `renv`.

### "Docker not running" error when starting a pipeline

Start Docker Desktop and wait for it to show "Docker is running" before submitting a pipeline run.

### Pipeline starts but produces no output

- Check the log panel for error messages
- Verify your database path is correct and the directory contains `hash.k2d`
- Verify your Kraken2 database has a `database<N>mers.kmer_distrib` file for Bracken (build one with `bracken-build` if missing)
- Run `stabiom doctor` in the terminal for a full diagnosis

### Browse button not working (macOS)

The Browse button uses macOS `osascript` to open a native file picker. If it does not respond, check that your terminal / R process has permission to display dialogs in **System Settings → Privacy & Security → Automation**.

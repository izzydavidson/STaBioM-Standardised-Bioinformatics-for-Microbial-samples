# STaBioM — Standardised Bioinformatics for Microbial Samples

A unified CLI and graphical interface for running microbiome analysis pipelines on long-read and short-read sequencing data, supporting both 16S amplicon and shotgun metagenomics workflows.

---

## Features

- **Multiple pipelines** — Short-read amplicon (QIIME2/DADA2), long-read amplicon (Emu/Kraken2), and metagenomics (Kraken2 + Bracken re-estimation)
- **Dual interfaces** — Command-line tool + Shiny web application
- **Zero dependencies** — Download and run; Python is bundled in the binary
- **Interactive setup** — Guided installation of Docker and reference databases
- **Containerized tools** — All bioinformatics tools run in Docker containers
- **Bracken re-estimation** — Abundance estimates are automatically re-estimated at species level using Bracken after Kraken2 classification
- **Standardised outputs** — Consistent taxonomy tables, visualizations (pie charts, heatmaps, stacked bar charts), and CSV exports
- **Valencia CST analysis** — Automatic community state type classification for vaginal samples
- **Body-site databases** — Custom Kraken2 databases optimized for vaginal, gut, oral, and skin microbiomes (see [Databases](#databases))

---

## Interfaces

### 1. Shiny Web Application (Recommended for most users)

A point-and-click graphical interface with real-time progress monitoring, file browsing, and interactive result comparison.

**Requirements:** R >= 4.0, Docker

**Launch:**
```bash
cd frontend
R -e "shiny::runApp()"
```

Or open `frontend/app.R` in RStudio and click **Run App**.

The app will open in your browser. R package dependencies (`shiny`, `bslib`, `jsonlite`, `shinyjs`, `shinyFiles`) are installed automatically on first launch.

**Features:**
- Short Read and Long Read pipeline configuration pages
- Three-way file/directory input: type a path, use the Browse button, or drag and drop
- Real-time pipeline log streaming
- Run comparison page with heatmaps and stacked bar charts
- Setup wizard for first-time configuration

### 2. Command-Line Interface (CLI)

Fast, scriptable, suitable for HPC and automation:

```bash
stabiom run -p lr_meta -i /path/to/reads/ --sample-type vaginal
```

---

## Quick Start

### 1. Download

Download the latest release for your platform from [GitHub Releases](https://github.com/izzydavidson/STaBioM-Standardised-Bioinformatics-for-Microbial-samples/releases):

| Platform | Download |
|----------|----------|
| macOS (Apple Silicon M1/M2/M3) | `stabiom-vX.X.X-macos-arm64.tar.gz` |
| macOS (Intel) | `stabiom-vX.X.X-macos-x64.tar.gz` |
| Linux (x64) | `stabiom-vX.X.X-linux-x64.tar.gz` |

```bash
# Extract
tar -xzf stabiom-vX.X.X-macos-arm64.tar.gz
cd stabiom-vX.X.X-macos-arm64
```

### 2. Run Setup

```bash
./stabiom setup
```

This will:
1. Add `stabiom` to your PATH
2. Check for Docker and provide installation instructions if missing
3. Download reference databases (interactive)
4. Download VALENCIA for vaginal CST classification (optional)
5. Download Dorado models for FAST5/POD5 basecalling (optional)

After setup, restart your terminal or run:
```bash
source ~/.zshrc   # or ~/.bashrc for bash
```

### 3. Launch the App or Run a Pipeline

**Graphical interface:**
```bash
cd frontend
R -e "shiny::runApp()"
```

**CLI:**
```bash
stabiom run -p lr_meta -i /path/to/reads/ --sample-type vaginal --db /path/to/db
```

---

## Available Pipelines

| Pipeline | Description | Classifier | Abundance estimation |
|----------|-------------|------------|---------------------|
| `sr_amp` | Short-read 16S amplicon (Illumina, IonTorrent, BGI) | QIIME2/DADA2 | ASV-based |
| `sr_meta` | Short-read shotgun metagenomics | Kraken2 | Bracken |
| `lr_amp` | Long-read 16S amplicon (ONT, PacBio) | Emu or Kraken2 | Emu or Bracken |
| `lr_meta` | Long-read shotgun metagenomics | Kraken2 | Bracken |

All Kraken2 pipelines use **Bracken re-estimation** — after Kraken2 classifies reads, Bracken redistributes genus-level counts to species level using kmer distribution files, producing more accurate species-level abundance estimates. The final graphs and CSV outputs reflect Bracken-estimated abundances where available.

---

## Databases

STaBioM supports any Kraken2-compatible database. For best results, use a database matched to your sample type.

### Body-Site Specific Databases (Recommended)

Custom databases built from NCBI RefSeq representative genomes, optimized for each body site. Smaller, faster, and more accurate than generic databases for the relevant sample types.

| Database | Size | Body site | Contents |
|----------|------|-----------|----------|
| `stabiom-vaginal` | ~1 GB | Vaginal | 112+ organisms: all CST-relevant Lactobacillus spp., Gardnerella, BV anaerobes (Fannyhessea, Sneathia, Mobiluncus, Megasphaera, Dialister, Prevotella, Peptoniphilus, Anaerococcus), STI pathogens (Chlamydia, Gonorrhoeae, Treponema, HSV, HPV, HIV, Trichomonas), vaginal fungi (Candida spp.) |
| `stabiom-core` | TBA | Gut / Oral / Skin | Coming soon |

The vaginal database covers all [Community State Types (CST I–V)](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3102268/):

| CST | Dominant organism | Included |
|-----|-------------------|---------|
| CST I | *Lactobacillus crispatus* | ✓ |
| CST II | *Lactobacillus gasseri* | ✓ |
| CST III | *Lactobacillus iners* | ✓ |
| CST IV-A/B | *Gardnerella* spp. + *Fannyhessea vaginae* | ✓ |
| CST IV-C0/C1 | *Prevotella* spp. | ✓ |
| CST IV-C2 | *Enterococcus* spp. | ✓ |
| CST IV-C3 | *Bifidobacterium* spp. | ✓ |
| CST IV-C4 | *Staphylococcus* spp. | ✓ |
| CST V | *Lactobacillus jensenii* | ✓ |

### Generic Databases

| Database | Size | Used by |
|----------|------|---------|
| Kraken2 Standard-8 | ~8 GB | sr_meta, lr_meta, lr_amp |
| Kraken2 Standard-16 | ~16 GB | sr_meta, lr_meta, lr_amp |
| Kraken2 PlusPF | ~87 GB | sr_meta, lr_meta, lr_amp |
| Emu Default | ~0.5 GB | lr_amp (full-length 16S) |

---

## CLI Commands

### `stabiom setup`

Interactive setup wizard. Run after first installing STaBioM.

```bash
stabiom setup                    # Interactive
stabiom setup --non-interactive  # Automated (for CI)
```

### `stabiom run`

```bash
stabiom run -p <pipeline> -i <input> [options]

# Examples
stabiom run -p lr_meta -i sample.fastq --sample-type vaginal --db /path/to/stabiom-vaginal
stabiom run -p sr_amp  -i reads/*.fastq.gz
stabiom run -p lr_amp  -i pod5_pass/ --sample-type vaginal

# Key options
  -p, --pipeline      Pipeline: sr_amp | sr_meta | lr_amp | lr_meta (required)
  -i, --input         Input file, directory, or glob pattern (required)
  -o, --outdir        Output directory (default: ./outputs)
  --sample-type       vaginal | gut | oral | skin | other
  --db                Kraken2 database path
  --threads           CPU threads (default: 4)
  --dry-run           Preview configuration without running
```

### `stabiom compare`

```bash
stabiom compare --run outputs/run1 --run outputs/run2
```

### `stabiom doctor`

Diagnose installation, check Docker, databases, and disk space.

```bash
stabiom doctor
```

---

## Output Structure

```
outputs/
└── <run_id>/
    └── lr_meta/
        └── final/
            ├── tables/
            │   ├── kraken_species_tidy.csv     # Species abundances (Bracken-estimated)
            │   └── valencia_cst.csv            # CST classification (vaginal only)
            └── plots/
                ├── piechart.html
                ├── heatmap.html
                └── stacked_bar.html
```

---

## Requirements

### What's Included

- Python runtime (bundled in binary)
- Pipeline scripts
- Configuration schemas

### What You Need

- **Docker** — Required to run pipelines
- **R >= 4.0** — Required for the Shiny app
- **Reference databases** — Download via `stabiom setup` or manually

### Dorado Models (FAST5/POD5 Basecalling)

For FAST5 or POD5 input, Dorado basecalling models are required. Install via `stabiom setup` (recommended) or manually:

```bash
docker run -v $(pwd)/models:/models ontresearch/dorado:latest \
  dorado download --model dna_r10.4.1_e8.2_400bps_hac@v5.2.0 --models-directory /models
```

---

## Development

```bash
git clone https://github.com/izzydavidson/STaBioM-Standardised-Bioinformatics-for-Microbial-samples.git
cd STaBioM-Standardised-Bioinformatics-for-Microbial-samples

# Run CLI from source
python -m cli --help

# Run Shiny app
cd frontend
R -e "shiny::runApp()"
```

---

## Troubleshooting

### "Docker not found"
```bash
stabiom setup   # provides installation instructions
```
Or install manually: [Docker Desktop](https://docs.docker.com/desktop/install/mac-install/) (macOS) / `curl -fsSL https://get.docker.com | sh` (Linux)

### "stabiom: command not found"
Run `stabiom setup` again, then restart your terminal.

### Bracken not running
Bracken requires a `database<readlen>mers.kmer_distrib` file in your Kraken2 database directory. If missing, the pipeline will log a warning and fall back to raw Kraken2 output. Build kmer distribution files with:
```bash
bracken-build -d /path/to/db -t 8 -l 1200 -k 35
```

---

## Citation

If you use STaBioM in your research, please cite:

```
[Citation pending publication]
```

## License

[License pending]

## Contact

For questions, issues, or feature requests, please [open an issue](https://github.com/izzydavidson/STaBioM-Standardised-Bioinformatics-for-Microbial-samples/issues).

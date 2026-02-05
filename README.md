# STaBioM - Standardised Bioinformatics for Microbial Samples

A unified CLI for running microbiome analysis pipelines on long-read and short-read sequencing data, supporting both 16S amplicon and shotgun metagenomics workflows.

## Features

- **Multiple pipelines**: Short-read amplicon (QIIME2/DADA2), long-read amplicon (Emu/Kraken2), and metagenomics (Kraken2/Bracken)
- **Zero dependencies**: Download and run - Python is bundled in the binary
- **Interactive setup**: Guided installation of Docker and reference databases
- **Containerized tools**: All bioinformatics tools run in Docker containers
- **Standardized outputs**: Consistent taxonomy tables, diversity metrics, and visualizations
- **Valencia CST analysis**: Automatic community state type classification for vaginal samples

## Quick Start

### 1. Download

Download the latest release for your platform from [GitHub Releases](https://github.com/izzydavidson/STaBioM-Standardised-Bioinformatics-for-Microbial-samples/releases):

| Platform | Download |
|----------|----------|
| macOS (Apple Silicon M1/M2/M3) | `stabiom-vX.X.X-macos-arm64.tar.gz` |
| macOS (Intel) | `stabiom-vX.X.X-macos-x64.tar.gz` |
| Linux (x64) | `stabiom-vX.X.X-linux-x64.tar.gz` |

```bash
# Download (replace URL with actual release)
curl -LO https://github.com/izzydavidson/STaBioM-Standardised-Bioinformatics-for-Microbial-samples/releases/download/v1.0.0/stabiom-v1.0.0-macos-arm64.tar.gz

# Extract
tar -xzf stabiom-v1.0.0-macos-arm64.tar.gz
cd stabiom-v1.0.0-macos-arm64
```

### 2. Run Setup

The setup wizard configures everything you need:

```bash
./stabiom setup
```

This will:
1. **Add `stabiom` to your PATH** - so you can run it from anywhere
2. **Check for Docker** - and provide installation instructions if missing
3. **Download reference databases** - Kraken2 and Emu databases (optional, interactive)
4. **Download analysis tools** - VALENCIA for vaginal CST classification (optional, interactive)

After setup completes, restart your terminal or run:
```bash
source ~/.zshrc  # or ~/.bashrc for bash users
```

### 3. Run a Pipeline

```bash
# List available pipelines
stabiom list

# Run short-read 16S amplicon analysis
stabiom run -p sr_amp -i /path/to/reads/

# Run long-read 16S amplicon analysis
stabiom run -p lr_amp -i /path/to/reads/

# Dry-run to preview configuration
stabiom run -p sr_amp -i /path/to/reads/ --dry-run
```

## Available Pipelines

| Pipeline | Description | Classifier |
|----------|-------------|------------|
| `sr_amp` | Short-read 16S amplicon (Illumina, IonTorrent, BGI) | QIIME2/DADA2 |
| `sr_meta` | Short-read shotgun metagenomics | Kraken2/Bracken |
| `lr_amp` | Long-read 16S amplicon (ONT, PacBio) | Emu or Kraken2 |
| `lr_meta` | Long-read shotgun metagenomics | Kraken2/Bracken |

**Note:** Long-read pipelines support FAST5, POD5, and FASTQ input. For FAST5 input, Dorado basecalling models must be downloaded manually (see Dorado Models section below).

## Commands

### `stabiom setup`

Interactive setup wizard. Run this after first installing STaBioM.

```bash
stabiom setup                    # Interactive setup
stabiom setup --non-interactive  # Automated setup (for CI)
stabiom setup -d kraken2-standard-8  # Download specific database
```

### `stabiom run`

Run a microbiome analysis pipeline.

```bash
# Basic usage
stabiom run -p <pipeline> -i <input>

# Examples
stabiom run -p sr_amp -i reads/*.fastq.gz
stabiom run -p lr_amp -i pod5_pass/ --sample-type vaginal
stabiom run -p sr_meta -i reads/ --db /path/to/kraken2/db -o ./results

# Key options
  -p, --pipeline      Pipeline: sr_amp | sr_meta | lr_amp | lr_meta (required)
  -i, --input         Input files, directory, or glob pattern (required)
  -o, --outdir        Output directory (default: ./outputs)
  --sample-type       Sample type: vaginal | gut | oral | skin | other
  --db                Kraken2 database path
  --threads           Number of CPU threads (default: 4)
  --dry-run           Preview configuration without running
  --no-container      Run without Docker (use local tools)

# FAST5 input (requires Dorado)
stabiom run -p lr_amp -i fast5/*.fast5 \
  --dorado-bin /path/to/dorado/bin/dorado \
  --dorado-models-dir /path/to/models \
  --dorado-model dna_r10.4.1_e8.2_400bps_hac@v5.2.0
```

**Note**: FAST5 input requires:
- `--dorado-bin`: Absolute path to Dorado binary
- `--dorado-models-dir`: Absolute path to directory containing Dorado models
- `--dorado-model`: Model name (must exist in the models directory)

See [Dorado Models](#dorado-models-manual-download-required) section for download instructions.

### `stabiom compare`

Compare taxonomic profiles from multiple pipeline runs.

```bash
stabiom compare --run outputs/run1 --run outputs/run2
stabiom compare --run run1 --run run2 --rank species --norm clr
```

### `stabiom list`

List all available pipelines with descriptions.

```bash
stabiom list
```

### `stabiom info`

Show detailed information about pipelines.

```bash
stabiom info           # Show all pipelines
stabiom info sr_amp    # Show specific pipeline
```

### `stabiom doctor`

Diagnose your installation and check system requirements.

```bash
stabiom doctor
```

Shows status of:
- PATH configuration
- Docker installation
- Downloaded databases
- Disk space
- Required dependencies

## Requirements

### What's Included (No Installation Needed)

- Python runtime (bundled in binary)
- Pipeline scripts
- Configuration schemas

### What You Need

- **Docker**: Required to run pipelines (installed via `stabiom setup`)
- **Reference databases**: Downloaded via `stabiom setup` or manually

### Supported Databases

| Database | Size | Used By |
|----------|------|---------|
| Kraken2 Standard-8 | ~8 GB | sr_meta, lr_meta, lr_amp (partial) |
| Kraken2 Standard-16 | ~16 GB | sr_meta, lr_meta, lr_amp (partial) |
| Emu Default | ~0.5 GB | lr_amp (full-length 16S) |

### Dorado Models (Manual Download Required)

For FAST5 input with long-read pipelines, Dorado basecalling models are required. These must be downloaded manually:

**Option 1: Using Docker (Recommended)**
```bash
# Download a specific model
docker run -v $(pwd)/models:/models ontresearch/dorado:latest \
  dorado download --model dna_r10.4.1_e8.2_400bps_hac@v5.2.0 --models-directory /models

# Move to STaBioM models directory
mv models/* /path/to/stabiom/tools/models/dorado/
```

**Option 2: Using Dorado Binary**

Install Dorado from [GitHub releases](https://github.com/nanoporetech/dorado/releases) and follow the [official download instructions](https://github.com/nanoporetech/dorado#downloading-models).

**Available Models:**
- `dna_r10.4.1_e8.2_400bps_hac@v5.2.0` - High-accuracy (recommended)
- `dna_r10.4.1_e8.2_400bps_sup@v5.2.0` - Super-accuracy (slower)
- `dna_r10.4.1_e8.2_400bps_fast@v5.2.0` - Fast (less accurate)

For a full list of available models, see the [Dorado models documentation](https://github.com/nanoporetech/dorado#models).

## Sample Types

| Type | Valencia CST | Notes |
|------|--------------|-------|
| `vaginal` | Auto-enabled | Community state type analysis |
| `gut` | Disabled | Gut microbiome |
| `oral` | Disabled | Oral microbiome |
| `skin` | Disabled | Skin microbiome |
| `other` | Disabled | Generic (default) |

## Output Structure

Each pipeline run produces:

```
outputs/
└── 20240131_143052/           # Run ID (timestamp)
    ├── config.json            # Run configuration
    ├── outputs.json           # Output file manifest
    ├── logs/                  # Pipeline logs
    ├── intermediate/          # Intermediate files
    │   ├── qc/               # Quality control
    │   ├── filtered/         # Filtered reads
    │   └── classification/   # Raw classifier output
    └── final/                 # Analysis-ready outputs
        ├── taxonomy/         # Abundance tables
        ├── diversity/        # Alpha/beta diversity
        ├── plots/            # Visualizations
        └── report/           # Summary reports
```

## Development Installation

For contributors or advanced users who want to run from source:

```bash
# Clone the repository
git clone https://github.com/izzydavidson/STaBioM-Standardised-Bioinformatics-for-Microbial-samples.git
cd STaBioM

# Run directly with Python
python -m cli --help
python -m cli run -p sr_amp -i reads/

# Or install in development mode
pip install -e .
stabiom --help
```

### Building the Binary

```bash
# Install PyInstaller
pip install pyinstaller

# Build
./scripts/build-release.sh --version v1.0.0

# Test
./dist/stabiom-v1.0.0-macos-arm64/stabiom --help
```

## Troubleshooting

### "Docker not found"

Run the setup wizard to get installation instructions:
```bash
stabiom setup
```

Or install Docker manually:
- **macOS**: [Docker Desktop for Mac](https://docs.docker.com/desktop/install/mac-install/)
- **Linux**: `curl -fsSL https://get.docker.com | sh`

### "stabiom: command not found"

The PATH wasn't configured. Either:
1. Run `stabiom setup` again
2. Restart your terminal
3. Or run with full path: `./stabiom`

### Check system status

```bash
stabiom doctor
```

This shows what's working and what needs attention.

## Citation

If you use STaBioM in your research, please cite:

```
[Citation pending publication]
```

## License

[License pending]

## Contact

For questions, issues, or feature requests, please [open an issue](https://github.com/izzydavidson/STaBioM-Standardised-Bioinformatics-for-Microbial-samples/issues).

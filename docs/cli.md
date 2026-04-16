# STaBioM CLI Guide

The `stabiom` binary is a self-contained command-line tool. Python is bundled — no separate Python installation is required.

---

## Installation

### Download and extract

```bash
tar -xzf stabiom-vX.X.X-macos-arm64.tar.gz
cd stabiom-vX.X.X-macos-arm64
```

### Add to PATH

```bash
./stabiom setup
```

This adds `stabiom` to your shell profile. Restart your terminal or run `source ~/.zshrc` (bash: `source ~/.bashrc`) afterwards.

---

## Commands

### `stabiom setup`

Interactive setup wizard. Run once after installing.

```bash
stabiom setup                    # Interactive
stabiom setup --non-interactive  # Automated (CI/scripted environments)
```

What it does:
1. Adds `stabiom` to your PATH
2. Checks for Docker and provides installation instructions if missing
3. Downloads reference databases (your choice)
4. Downloads VALENCIA for vaginal CST classification (optional)
5. Downloads Dorado basecalling models for FAST5/POD5 input (optional)

---

### `stabiom run`

Run a pipeline.

```bash
stabiom run -p <pipeline> -i <input> [options]
```

**Required flags:**

| Flag | Description |
|------|-------------|
| `-p`, `--pipeline` | Pipeline: `sr_amp` \| `sr_meta` \| `lr_amp` \| `lr_meta` |
| `-i`, `--input` | Input file, directory, or glob (e.g. `reads/*.fastq.gz`) |

**Common options:**

| Flag | Default | Description |
|------|---------|-------------|
| `-o`, `--outdir` | `./outputs` | Output directory |
| `--sample-type` | `other` | `vaginal` \| `gut` \| `oral` \| `skin` \| `other` |
| `--db` | — | Kraken2 database path |
| `--threads` | `4` | CPU threads |
| `--confidence` | site-specific | Kraken2 confidence threshold (0–1) |
| `--min-hit-groups` | site-specific | Minimum distinct k-mer hit groups |
| `--dry-run` | — | Preview config without running |

**Site-specific Kraken2 defaults** (applied automatically when `--sample-type` is set):

| Site | `--confidence` | `--min-hit-groups` |
|------|---------------|-------------------|
| vaginal | 0.02 | 2 |
| gut | 0.03 | 4 |
| oral | 0.04 | 4 |
| skin | 0.03 | 4 |

These thresholds were derived from validation sweeps against CAMISIM-simulated ground truth datasets for each body site. Override them explicitly if your data warrants it.

**Examples:**

```bash
# Long-read metagenomics — vaginal sample
stabiom run -p lr_meta -i sample.fastq \
  --sample-type vaginal \
  --db /path/to/stabiom-vaginal

# Long-read metagenomics — gut sample, custom output dir
stabiom run -p lr_meta -i reads/ \
  --sample-type gut \
  --db /path/to/stabiom-gut \
  -o /data/results/run1

# Short-read amplicon — paired Illumina reads
stabiom run -p sr_amp -i reads/*.fastq.gz

# Long-read amplicon — Emu classification
stabiom run -p lr_amp -i pod5_pass/ --sample-type vaginal

# Dry run — preview without executing
stabiom run -p lr_meta -i reads/ --db /path/to/db --dry-run
```

---

### `stabiom compare`

Compare abundance profiles across two or more runs.

```bash
stabiom compare --run outputs/run1 --run outputs/run2
stabiom compare --run outputs/run1 --run outputs/run2 -o comparison_output/
```

Generates heatmaps and stacked bar charts comparing species-level abundances. Both runs must have completed successfully and produced `kraken_species_tidy.csv` outputs.

---

### `stabiom doctor`

Diagnose installation issues.

```bash
stabiom doctor
```

Checks:
- Docker installation and daemon status
- Disk space for databases
- Database path validity
- Container images

---

## Output Structure

```
outputs/
└── <run_id>/
    └── <pipeline>/
        └── final/
            ├── tables/
            │   ├── kraken_species_tidy.csv     # Species abundances (Bracken-estimated)
            │   ├── kraken_species_raw.csv       # Raw Kraken2 output
            │   └── valencia_cst.csv            # CST classification (vaginal only)
            └── plots/
                ├── piechart.html
                ├── heatmap.html
                └── stacked_bar.html
```

All Kraken2 pipelines use **Bracken re-estimation**: after Kraken2 classifies reads, Bracken redistributes genus-level counts to species level using kmer distribution files. Final outputs reflect Bracken abundances where a matching kmer_distrib file is found, otherwise raw Kraken2 counts are used.

---

## Bracken

Bracken requires a `database<readlen>mers.kmer_distrib` file in your Kraken2 database directory. STaBioM ships kmer_distrib files for each body-site database at 500, 750, 1000, 1200, 1500, and 2000 bp read lengths.

If using a custom or third-party database without kmer_distrib files, build them with:

```bash
bracken-build -d /path/to/db -t 8 -l 1200 -k 35
```

---

## Dorado Basecalling (FAST5/POD5 input)

For FAST5 or POD5 input, Dorado basecalling models are required. Install via setup (recommended):

```bash
stabiom setup   # follow prompts for Dorado models
```

Or manually:

```bash
docker run -v $(pwd)/models:/models ontresearch/dorado:latest \
  dorado download --model dna_r10.4.1_e8.2_400bps_hac@v5.2.0 --models-directory /models
```

---

## Troubleshooting

### `stabiom: command not found`

Run `stabiom setup` again, then restart your terminal.

### `Docker not found`

```bash
stabiom setup   # provides platform-specific instructions
```

Or install manually:
- macOS: [Docker Desktop](https://docs.docker.com/desktop/install/mac-install/)
- Linux: `curl -fsSL https://get.docker.com | sh`

### Bracken not running

Check that your database directory contains a `database<N>mers.kmer_distrib` file. Build one if missing (see [Bracken](#bracken) above).

### Pipeline exits with no output

Run with `--dry-run` first to validate your configuration. Check Docker is running (`docker ps`). Run `stabiom doctor` for a full diagnosis.

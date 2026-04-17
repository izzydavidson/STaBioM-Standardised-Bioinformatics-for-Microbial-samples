# STaBioM CLI Guide

The `stabiom` binary is self-contained — Python is bundled inside it. No separate Python installation is required.

---

## Installation

### 1. Download and extract

Download the release for your platform from [GitHub Releases](https://github.com/izzydavidson/STaBioM-Standardised-Bioinformatics-for-Microbial-samples/releases), then:

```bash
tar -xzf stabiom-vX.X.X-macos-arm64.tar.gz
cd stabiom-vX.X.X-macos-arm64
```

### 2. Run setup

```bash
./stabiom setup
```

This adds `stabiom` to your PATH, checks Docker, and lets you download databases interactively. After setup completes, open a new terminal (or run `source ~/.zshrc`) so the `stabiom` command is available.

### 3. Verify

```bash
stabiom doctor
```

You should see `[OK]` for Docker and your databases. Fix any issues the doctor reports before running pipelines.

---

## Commands

### `stabiom list`

List all available pipelines.

```bash
stabiom list
```

Output:
```
Available pipelines:
  sr_amp               - Short-Read Amplicon (16S)
  sr_meta              - Short-Read Metagenomics
  lr_amp               - Long-Read Amplicon (Full-length 16S or Partial 16S)
  lr_meta              - Long-Read Metagenomics
```

---

### `stabiom info`

Show detailed information about a pipeline.

```bash
stabiom info            # all pipelines
stabiom info lr_meta    # one pipeline
```

---

### `stabiom doctor`

Check that your installation is healthy.

```bash
stabiom doctor
```

Reports on:
- Whether `stabiom` is in your PATH
- Docker installation and running status
- Installed Docker images
- Downloaded databases
- Disk space
- Python packages needed for `stabiom compare`

Run this first whenever something isn't working.

---

### `stabiom setup`

Interactive setup wizard. Run this once after first installing STaBioM, or again if you need to download additional databases or tools.

```bash
stabiom setup                    # interactive (default)
stabiom setup --non-interactive  # automated, no prompts (for CI/scripts)
```

The wizard will:
1. Add `stabiom` to your PATH
2. Check for Docker and provide install instructions if missing
3. Let you download reference databases (Kraken2, Emu)
4. Download VALENCIA for vaginal CST classification
5. Download Dorado models for FAST5/POD5 basecalling

---

### `stabiom run`

Run a microbiome analysis pipeline.

```bash
stabiom run --pipeline <id> --input <path> [options]
```

**Required:**

| Flag | Description |
|------|-------------|
| `-p`, `--pipeline` | Pipeline ID: `lr_meta` \| `lr_amp` \| `sr_meta` \| `sr_amp` |
| `-i`, `--input` | Input file, directory, or glob pattern |

**Common options:**

| Flag | Default | Description |
|------|---------|-------------|
| `-o`, `--outdir` | `./outputs` | Where to save results |
| `--run-id` | timestamp | Name for this run (e.g. `patient_01_run1`) |
| `--sample-type` | `other` | `vaginal` \| `gut` \| `oral` \| `skin` \| `other` |
| `--db` | — | Path to Kraken2 database directory |
| `--threads` | `4` | Number of CPU threads to use |
| `--dry-run` | — | Show what would run without executing |
| `--force` | — | Overwrite an existing run with the same ID |
| `-v`, `--verbose` | on | Detailed progress output |

**Examples:**

```bash
# Long-read metagenomics — vaginal sample, STaBioM vaginal database
stabiom run \
  --pipeline lr_meta \
  --input /path/to/sample.fastq \
  --sample-type vaginal \
  --db /path/to/stabiom-vaginal \
  --run-id patient_01

# Long-read metagenomics — gut sample
stabiom run \
  --pipeline lr_meta \
  --input /path/to/reads/ \
  --sample-type gut \
  --db /path/to/stabiom-gut \
  --run-id gut_run_01 \
  --threads 8

# Long-read amplicon — full-length 16S (Emu classifier)
stabiom run \
  --pipeline lr_amp \
  --input /path/to/reads/ \
  --sample-type vaginal

# Short-read metagenomics — Illumina paired-end reads
stabiom run \
  --pipeline sr_meta \
  --input /path/to/reads/ \
  --db /path/to/kraken2-standard-8 \
  --run-id illumina_run_01

# Short-read amplicon — Illumina 16S
stabiom run \
  --pipeline sr_amp \
  --input /path/to/reads/*.fastq.gz \
  --primer-f CCTACGGGNGGCWGCAG \
  --primer-r GACTACHVGGGTATCTAATCC

# Dry run — see what configuration would be used without running
stabiom run \
  --pipeline lr_meta \
  --input /path/to/reads/ \
  --db /path/to/db \
  --dry-run
```

#### Specifying input

STaBioM accepts several input formats:

```bash
# Single file
--input /path/to/sample.fastq.gz

# Directory (all FASTQ files inside will be used)
--input /path/to/reads/

# Glob pattern (quote it to prevent shell expansion)
--input '/path/to/reads/*.fastq.gz'
```

For paired-end short reads, point to the directory or use a glob — STaBioM detects R1/R2 pairs automatically.

#### Sample type and Kraken2 tuning

When you set `--sample-type`, STaBioM automatically applies validated confidence and minimum hit group thresholds for that body site:

| Sample type | Confidence | Min hit groups | Notes |
|-------------|-----------|----------------|-------|
| `vaginal` | 0.02 | 2 | Also enables Valencia CST classification |
| `gut` | 0.03 | 4 | |
| `oral` | 0.04 | 4 | |
| `skin` | 0.03 | 4 | |
| `other` | 0.05 | 2 | Generic default |

These were determined from parameter sweep validation against CAMISIM-simulated ground truth datasets. You can override them:

```bash
stabiom run --pipeline lr_meta --input reads/ --db /path/to/db \
  --sample-type gut \
  --confidence 0.05 \
  --min-hit-groups 6
```

#### FAST5 / POD5 input (long-read pipelines)

For raw signal data (FAST5 or POD5), STaBioM runs Dorado basecalling first. If you installed Dorado via `stabiom setup`, it is auto-detected:

```bash
stabiom run --pipeline lr_meta --input /path/to/pod5/ --db /path/to/db
```

If Dorado is installed manually, specify the paths explicitly:

```bash
stabiom run --pipeline lr_amp \
  --input /path/to/fast5/ \
  --dorado-bin /path/to/dorado/bin/dorado \
  --dorado-models-dir /path/to/models/ \
  --dorado-model dna_r10.4.1_e8.2_400bps_hac@v5.2.0
```

#### Multiplexed / barcoded runs

If your run contains multiple barcoded samples:

```bash
stabiom run --pipeline lr_amp \
  --input /path/to/data/ \
  --barcode-kit SQK-NBD114-24 \
  --sample-type vaginal
```

---

### `stabiom compare`

Compare taxonomic profiles from two or more completed pipeline runs.

```bash
stabiom compare --run <path> --run <path> [options]
```

**Examples:**

```bash
# Compare two runs by directory
stabiom compare \
  --run outputs/patient_01 \
  --run outputs/patient_02

# Compare with custom output location and species-level resolution
stabiom compare \
  --run outputs/run_a \
  --run outputs/run_b \
  --rank species \
  --outdir comparisons/

# Compare from raw CSV tables instead of run directories
stabiom compare \
  --table path/to/table1.tsv \
  --table path/to/table2.tsv

# Differential abundance (requires exactly 2 runs)
stabiom compare \
  --run outputs/control \
  --run outputs/treatment \
  --diff
```

**Options:**

| Flag | Default | Description |
|------|---------|-------------|
| `--run` | — | Path to a completed run directory (repeat for each run) |
| `--table` | — | Path to a TSV abundance table (alternative to `--run`) |
| `--rank` | `genus` | Taxonomic rank: `species` \| `genus` \| `family` |
| `--norm` | `relative` | Normalisation: `relative` \| `clr` |
| `--top-n` | `20` | Number of top taxa to show in plots |
| `--diff` | — | Run differential abundance analysis (2 runs only) |
| `-o`, `--outdir` | `./outputs` | Where to save the comparison |

The compare command generates an HTML report, heatmaps, stacked bar charts, and a Venn diagram of taxa overlap.

---

## Output Structure

Each pipeline run produces:

```
outputs/
└── <run_id>/
    ├── config.json              # Exact configuration used for this run
    ├── outputs.json             # Manifest of all output files
    ├── logs/                    # Pipeline log files
    └── results/
        └── tables/
            ├── results.csv                  # Main results table
            ├── kraken_species_tidy.csv      # Species abundances (Bracken-estimated)
            ├── kraken_genus_tidy.csv        # Genus-level abundances
            ├── summary_stats.csv            # Read counts and QC summary
            └── valencia_cst.csv            # CST classification (vaginal only)
```

The most useful output file is `results/tables/kraken_species_tidy.csv` — a tidy table with one row per species per sample, with Bracken-estimated relative abundances.

---

## Bracken Re-estimation

All Kraken2 pipelines use Bracken to re-estimate species-level abundances after classification. Bracken requires a `database<N>mers.kmer_distrib` file inside your database directory, where `<N>` is the read length (e.g. `database1500mers.kmer_distrib` for 1500 bp reads).

STaBioM's body-site databases ship with kmer_distrib files for read lengths: 500, 750, 1000, 1200, 1500, and 2000 bp.

If you are using a third-party database without kmer_distrib files, build them with:

```bash
bracken-build -d /path/to/db -t 8 -l 1200
```

STaBioM will use raw Kraken2 counts if no matching kmer_distrib file is found.

---

## Troubleshooting

### `stabiom: command not found`

Setup did not add it to your PATH. Either:
```bash
./stabiom setup          # run setup again
source ~/.zshrc          # reload your shell config
```
Or run it with the full path: `/path/to/stabiom-folder/stabiom`.

### Docker errors

Make sure Docker Desktop is open and running (whale icon in menu bar on macOS). Then:
```bash
stabiom doctor     # check Docker status
docker ps          # verify Docker is responding
```

### Pipeline exits with no output

```bash
stabiom doctor                                 # check system requirements
stabiom run ... --dry-run                      # validate configuration
stabiom run ... --verbose                      # see detailed progress
```
Check the log file in `outputs/<run_id>/logs/` for the specific error.

### Bracken not running

Your database directory is missing a kmer_distrib file. See [Bracken Re-estimation](#bracken-re-estimation) above.

### macOS security warning on first run

Go to **System Settings → Privacy & Security** and click **Allow Anyway** next to the STaBioM entry.

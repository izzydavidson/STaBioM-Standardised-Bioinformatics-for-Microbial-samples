# STaBioM — Standardised Bioinformatics for Microbial Samples

A unified CLI and graphical interface for running microbiome analysis pipelines on long-read and short-read sequencing data, supporting 16S amplicon and shotgun metagenomics workflows.

---

## Features

- **Multiple pipelines** — Short-read amplicon (QIIME2/DADA2), long-read amplicon (Emu/Kraken2), and metagenomics (Kraken2 + Bracken)
- **Dual interfaces** — Command-line tool and Shiny web application
- **Zero dependencies** — Download and run; Python is bundled in the binary
- **Containerized tools** — All bioinformatics tools run in Docker containers
- **Bracken re-estimation** — Species-level abundance re-estimation after Kraken2 classification
- **Valencia CST analysis** — Automatic community state type classification for vaginal samples
- **Body-site databases** — Custom Kraken2 databases optimized for vaginal, gut, oral, and skin microbiomes
- **Site-specific tuning** — Confidence and hit-group parameters pre-set per body site based on validation results

---

## Quick Start

### 1. Download

Download the latest release from [GitHub Releases](https://github.com/izzydavidson/STaBioM-Standardised-Bioinformatics-for-Microbial-samples/releases):

| Platform | File |
|----------|------|
| macOS (Apple Silicon) | `stabiom-vX.X.X-macos-arm64.tar.gz` |
| macOS (Intel) | `stabiom-vX.X.X-macos-x64.tar.gz` |
| Linux (x64) | `stabiom-vX.X.X-linux-x64.tar.gz` |

```bash
tar -xzf stabiom-vX.X.X-macos-arm64.tar.gz
cd stabiom-vX.X.X-macos-arm64
```

### 2. Run Setup

```bash
./stabiom setup
```

This installs `stabiom` to your PATH, checks Docker, and downloads reference databases interactively. Restart your terminal (or `source ~/.zshrc`) after setup.

### 3. Choose Your Interface

**Graphical app** — recommended for most users:
```bash
cd frontend
R -e "shiny::runApp()"
```

**Command line** — scriptable, HPC-friendly:
```bash
stabiom run -p lr_meta -i /path/to/reads/ --sample-type vaginal --db /path/to/db
```

---

## Documentation

| Guide | Description |
|-------|-------------|
| [App Guide](docs/gui.md) | Launching and using the Shiny web application |
| [CLI Guide](docs/cli.md) | All `stabiom` commands, options, and examples |

---

## Available Pipelines

| Pipeline | Description | Classifier | Abundance |
|----------|-------------|------------|-----------|
| `sr_amp` | Short-read 16S amplicon (Illumina, IonTorrent, BGI) | QIIME2/DADA2 | ASV-based |
| `sr_meta` | Short-read shotgun metagenomics | Kraken2 | Bracken |
| `lr_amp` | Long-read 16S amplicon (ONT, PacBio) | Emu or Kraken2 | Emu or Bracken |
| `lr_meta` | Long-read shotgun metagenomics | Kraken2 | Bracken |

---

## Databases

### Body-Site Specific (Recommended)

| Database | Body site | Contents |
|----------|-----------|----------|
| `stabiom-vaginal` | Vaginal | 112+ organisms: all CST-relevant Lactobacillus spp., Gardnerella, BV anaerobes, STI pathogens, vaginal fungi |
| `stabiom-gut` | Gut | Coming soon |
| `stabiom-oral` | Oral | Coming soon |
| `stabiom-skin` | Skin | Coming soon |

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

| Database | Size | Suitable for |
|----------|------|--------------|
| Kraken2 Standard-8 | ~8 GB | General metagenomics |
| Kraken2 Standard-16 | ~16 GB | General metagenomics |
| Kraken2 PlusPF | ~87 GB | Comprehensive classification |
| Emu Default | ~0.5 GB | Long-read full-length 16S |

---

## Requirements

| Requirement | Purpose |
|-------------|---------|
| Docker | Run all pipeline containers |
| R >= 4.0 | Shiny web application only |
| Reference database | Download via `stabiom setup` |

---

## Development

```bash
git clone https://github.com/izzydavidson/STaBioM-Standardised-Bioinformatics-for-Microbial-samples.git
cd STaBioM-Standardised-Bioinformatics-for-Microbial-samples

# CLI from source
python -m cli --help

# Shiny app
cd frontend && R -e "shiny::runApp()"
```

---

## Citation

```
[Citation pending publication]
```

## License

MIT License — see [LICENSE](LICENSE) for details.

## Contact

[Open an issue](https://github.com/izzydavidson/STaBioM-Standardised-Bioinformatics-for-Microbial-samples/issues) for questions, bugs, or feature requests.

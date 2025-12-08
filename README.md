# STaMP-Standardised-Taxonomic-Microbiome-Pipeline-for-Nanopore-data

This repository provides a standardised analysis pipeline for Nanopore metagenomic microbiome data across multiple specimen types. The goal is to **reduce method-driven variability** by enforcing consistent inputs, preprocessing, QC, classification, and reporting.

The pipeline supports two entry modes:

* **FASTQ mode**: for publicly available data or already basecalled reads (performed by any tool)
* **FAST5 mode**: for raw, unbasecalled sequencing output that requires basecalling first

Both modes converge on consistent QC, taxonomy outputs, and standardized summary tables and plots.

---

## Supported Specimen Types

This pipeline currently supports:

* **Skin**
* **Oral**
* **Gut / faecal**
* **Vaginal**

Sample type selection may drive validated parameter presets and determine whether vaginal-specific classification (VALENCIA) is enabled.

---

## Core Contract (Inputs & Outputs)

### Accepted Input Types

#### 1) FASTQ (basecalled reads)

Use this mode when you have:

* publicly downloaded reads, or
* outputs from separate basecalling and/or demultiplexing

Accepted formats:

* `.fastq`
* `.fastq.gz`

Expectations:

* Files are readable and non-empty.
* Sample naming/barcode mapping is consistent with your metadata, if applicable.

---

#### 2) FAST5 (raw, unbasecalled Nanopore output)

Use this mode when starting from:

* raw sequencer output that has not been basecalled

Accepted formats:

* `.fast5` (single- or multi-FAST5)

Expectations:

* Files are organized in a coherent run directory.
* Basecalling will be performed within the FAST5 pipeline.

---

## Pipeline Stages (High Level)

### FAST5 Pipeline (Raw Input)

Typical flow:

1. **Basecalling** (Dorado)
2. **Demultiplexing** (Dorado)
3. **Trimming** (Dorado)
4. **Low-quality read removal**
5. **FASTQ standardization**
6. **FastQC**
7. **MultiQC**
8. **Kraken classification**
9. **VALENCIA** (vaginal samples)
10. **Tidy summary tables + run-level plots**

---

### FASTQ Pipeline (Basecalled Input)

Typical flow:

1. **Demultiplexing** (if needed; non-Dorado toolchain)
2. **Trimming**
3. **Low-quality read removal**
4. **FASTQ standardization**
5. **FastQC**
6. **MultiQC**
7. **Kraken classification**
8. **VALENCIA** (vaginal samples)
9. **Tidy summary tables + run-level plots**

---

## Outputs

Each run produces a standardized `results/` directory containing:

### Quality Control

* **FastQC outputs**
* **MultiQC report**

### Classification Outputs

* **Kraken outputs** (reports, summaries)
* **VALENCIA outputs** *(when applicable, see below)*

### Analysis-ready Summary

* A **tidied `.csv`** linking:

  * sample IDs
  * bacterial taxa
  * abundance fields

### Run-level Visualization

* A **stacked bar chart** summarizing microbial composition across the run.

---

## Standard Output Structure

A typical run is expected to produce:

* `results/`

  * `fastqc/`
  * `multiqc/`
  * `kraken/`
  * `valencia/`
  * `tables/`

    * `tidy_taxa_by_sample.csv`
  * `plots/`

    * `stacked_bar_run.png` (or `.pdf`)
  * `summaries/`

    * `params_used.json`
    * `versions.txt`

Folder names may vary slightly by implementation, but the **content categories** above are part of the core contract.

---

## VALENCIA Behaviour

VALENCIA is a vaginal CST classifier.

Default behaviour:

* **Enabled automatically for `sample_type: vaginal`.**
* **Disabled for skin/oral/gut unless explicitly overridden.**

This keeps the pipeline biologically appropriate by default while still allowing advanced users to run VALENCIA manually if needed.

---

## Tidy CSV Schema (Example)

The pipeline produces a run-level tidy table intended for downstream stats and visualization.

Expected columns may include:

* `sample_id`
* `taxon`
* `rank` (optional)
* `read_count` (optional)
* `relative_abundance`
* `sample_type` (optional but recommended)
* `run_id` (optional but recommended)

Example (illustrative):

| sample_id | taxon                   | relative_abundance |
| --------- | ----------------------- | ------------------ |
| S01       | Lactobacillus crispatus | 0.72               |
| S01       | Gardnerella vaginalis   | 0.11               |
| S02       | Bacteroides fragilis    | 0.18               |

Your exact fields can be refined as your downstream needs evolve, but the contract requires at minimum:

* **sample ID**
* **bacteria/taxon**
* **an abundance field**

---

## Configuration

The pipeline is driven by a unified config that supports both modes.

Key concept fields:

* `input_type: fastq | fast5`
* `sample_type: skin | oral | gut | vaginal`
* `prep_profile: dorado | alt_fastq_prep` *(if you expose this)*
* input paths
* optional barcode kit and trimming policies

---

## Example Usage Patterns

These examples are intentionally high-level and can be adapted to your final CLI.

### FASTQ Mode (public or pre-basecalled)

Example pattern:

* Provide FASTQs
* Select sample type
* Run

```bash
./run_fastq.sh --config config.yaml
```

---

### FAST5 Mode (raw sequencer output)

Example pattern:

* Provide FAST5 folder
* Dorado basecall + demux + trim
* Continue into QC + classification

```bash
./run_raw.sh --config config.yaml
```

---

## Reproducibility & Variability Reduction

This pipeline reduces method-driven variability by:

* Standardizing input expectations and sample type presets
* Using consistent preprocessing and QC stages per mode
* Producing harmonized outputs across workflows
* Recording:

  * tool versions
  * parameters used
  * (where applicable) database versions

Each run should emit:

* `summaries/versions.txt`
* `summaries/params_used.json`

---

## Validation Status

Current focus:

* Cloud testing across:

  * **vaginal**
  * **gut**
  * **skin**

Once these are validated:

* presets will be finalized
* test datasets + expected output checks will be bundled
* the UI “wizard” layer will be added

---

## Future Interface (Planned)

A lightweight plug-and-play UI will be added to:

* select input type (FASTQ vs FAST5)
* choose sample type
* apply validated presets
* generate a config automatically
* run the appropriate pipeline
* show logs and link outputs

The UI will not contain scientific logic; it will **operate the workflow safely** to preserve reproducibility.

---

## License & Citation

A license and citation guide will be added prior to public release to support reuse and appropriate attribution.

---

## Contact

For questions, collaboration, or feature requests, please open an issue.

---

If you want, I can also add:

* a **“Quickstart”** section with a minimal config example
* a **parameter presets** section per sample type
* a short **Methods-ready paragraph** you can drop straight into your paper.

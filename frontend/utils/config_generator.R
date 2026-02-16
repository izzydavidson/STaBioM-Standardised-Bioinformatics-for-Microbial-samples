# Configuration Generator Utilities
# Functions to generate pipeline configurations that match the run.schema.json format

get_outputs_directory <- function() {
  repo_root <- dirname(getwd())
  file.path(repo_root, "outputs")
}

generate_sr_amp_config <- function(params) {
  cat("\n========== BUILDING SR_AMP CONFIG ==========\n")
  cat("Received params:\n")
  cat(paste(names(params), "=", sapply(params, function(x) paste(x, collapse=",")), "\n"))

  # Map technology
  tech_map <- c(
    "illumina" = "ILLUMINA",
    "iontorrent" = "IONTORRENT",
    "bgi" = "BGI"
  )
  technology <- tech_map[params$technology] %||% "ILLUMINA"
  cat("Mapped technology:", technology, "\n")

  # Determine input style
  input_style <- if (params$paired_end) "FASTQ_PAIRED" else "FASTQ_SINGLE"
  cat("Input style:", input_style, "\n")

  # Build input object
  input_obj <- list(style = input_style)
  if (params$paired_end) {
    input_obj$fastq_r1 <- params$input_r1
    input_obj$fastq_r2 <- params$input_r2
    cat("Paired-end: R1=", params$input_r1, "R2=", params$input_r2, "\n")
  } else {
    input_obj$fastq_r1 <- params$input_path
    cat("Single-end:", params$input_path, "\n")
  }

  # Parse primer sequences from textarea
  primer_forward <- NULL
  primer_reverse <- NULL
  if (!is.null(params$primer_sequences) && nchar(trimws(params$primer_sequences)) > 0) {
    primer_lines <- strsplit(params$primer_sequences, "\n")[[1]]
    primer_lines <- trimws(primer_lines)
    primer_lines <- primer_lines[nchar(primer_lines) > 0]
    if (length(primer_lines) >= 1) primer_forward <- primer_lines[1]
    if (length(primer_lines) >= 2) primer_reverse <- primer_lines[2]
    cat("Primers: forward=", primer_forward, "reverse=", primer_reverse, "\n")
  }

  # Parse barcode sequences from textarea
  barcode_sequences <- NULL
  if (!is.null(params$barcode_sequences) && nchar(trimws(params$barcode_sequences)) > 0) {
    barcode_lines <- strsplit(params$barcode_sequences, "\n")[[1]]
    barcode_lines <- trimws(barcode_lines)
    barcode_lines <- barcode_lines[nchar(barcode_lines) > 0]
    if (length(barcode_lines) > 0) {
      barcode_sequences <- barcode_lines
      cat("Barcodes:", length(barcode_lines), "sequences\n")
    }
  }

  # Build output.selected array - ensure it's a character vector for JSON array
  output_selected <- if (!is.null(params$output_selected) && length(params$output_selected) > 0) {
    as.character(params$output_selected)
  } else {
    c("all")
  }
  cat("Output selected:", paste(output_selected, collapse=", "), "\n")

  # Determine specimen
  specimen <- params$sample_type %||% "other"
  cat("Specimen:", specimen, "\n")

  # Determine threads
  threads <- as.integer(params$threads %||% 4)
  cat("Threads:", threads, "\n")

  # Quality threshold
  quality_threshold <- as.integer(params$quality_threshold %||% 20)
  cat("Quality threshold:", quality_threshold, "\n")

  # Minimum read length
  min_read_length <- if (!is.null(params$min_read_length)) as.integer(params$min_read_length) else NULL
  if (!is.null(min_read_length)) cat("Min read length:", min_read_length, "\n")

  # Trim adapter
  trim_adapter <- if (!is.null(params$trim_adapter)) as.logical(params$trim_adapter) else NULL
  if (!is.null(trim_adapter)) cat("Trim adapter:", trim_adapter, "\n")

  # Demultiplex
  demultiplex <- if (!is.null(params$demultiplex)) as.logical(params$demultiplex) else NULL
  if (!is.null(demultiplex)) cat("Demultiplex:", demultiplex, "\n")

  # Run scope
  run_scope <- params$run_scope %||% NULL
  if (!is.null(run_scope)) cat("Run scope:", run_scope, "\n")

  # Barcoding kit
  barcoding_kit <- if (!is.null(params$barcoding_kit) && nchar(trimws(params$barcoding_kit)) > 0) {
    trimws(params$barcoding_kit)
  } else {
    NULL
  }
  if (!is.null(barcoding_kit)) cat("Barcoding kit:", barcoding_kit, "\n")

  # DADA2 parameters
  dada2_trunc_f <- as.integer(params$dada2_trunc_f %||% 220)
  dada2_trunc_r <- as.integer(params$dada2_trunc_r %||% 200)
  cat("DADA2 trunc_len_f:", dada2_trunc_f, "trunc_len_r:", dada2_trunc_r, "\n")

  # Auto-detect SILVA classifier (matches CLI behavior at cli/runner.py:1269-1291)
  repo_root <- dirname(getwd())  # frontend -> repo_root
  classifier_path <- file.path(repo_root, "main", "data", "reference", "qiime2", "silva-138-99-nb-classifier.qza")
  if (file.exists(classifier_path)) {
    cat("Auto-detected SILVA classifier:", classifier_path, "\n")
  } else {
    classifier_path <- ""
    cat("SILVA classifier not found - taxonomy classification will be skipped\n")
  }

  # Build params.common with all UI selections
  params_common <- list(
    min_qscore = quality_threshold,
    remove_host = 0L,
    specimen = specimen
  )

  # Add optional fields to params.common if provided
  if (!is.null(min_read_length)) params_common$min_read_length <- min_read_length
  if (!is.null(trim_adapter)) params_common$trim_adapter <- trim_adapter
  if (!is.null(demultiplex)) params_common$demultiplex <- demultiplex

  # Generate config matching schema
  config <- list(
    pipeline_id = "sr_amp",

    run = list(
      work_dir = params$output_dir,
      run_id = params$run_id,
      force_overwrite = 1L
    ),

    technology = technology,
    specimen = specimen,

    input = input_obj,

    resources = list(
      threads = threads
    ),

    params = list(
      common = params_common
    ),

    qiime2 = list(
      sample_id = params$run_id,
      classifier = list(
        qza = classifier_path  # Auto-detected SILVA classifier or empty string
      ),
      dada2 = list(
        trim_left_f = 0L,
        trim_left_r = 0L,
        trunc_len_f = dada2_trunc_f,
        trunc_len_r = dada2_trunc_r,
        n_threads = threads
      )
    ),

    output = list(
      selected = output_selected
    )
  )

  # Add run_scope if provided
  if (!is.null(run_scope)) {
    config$run$scope <- run_scope
  }

  # Add qiime2.primers if provided
  if (!is.null(primer_forward) || !is.null(primer_reverse)) {
    primers_obj <- list()
    if (!is.null(primer_forward)) primers_obj$forward <- primer_forward
    if (!is.null(primer_reverse)) primers_obj$reverse <- primer_reverse
    config$qiime2$primers <- primers_obj
    cat("Added primers to config\n")
  }

  # Add barcode sequences if provided
  if (!is.null(barcode_sequences)) {
    if (is.null(config$input$barcodes)) config$input$barcodes <- list()
    config$input$barcodes$sequences <- barcode_sequences
    cat("Added barcode sequences to config\n")
  }

  # Add barcoding kit if provided
  if (!is.null(barcoding_kit)) {
    if (is.null(config$tools)) config$tools <- list()
    config$tools$barcoding_kit <- barcoding_kit
    cat("Added barcoding kit to config\n")
  }

  # Add Valencia if vaginal and map UI selection correctly
  if (specimen == "vaginal") {
    valencia_enabled <- if (!is.null(params$valencia) && params$valencia == "yes") {
      1L
    } else if (!is.null(params$valencia) && params$valencia == "no") {
      0L
    } else {
      0L
    }
    config$valencia <- list(enabled = valencia_enabled)
    cat("Valencia enabled:", valencia_enabled, "\n")
  }

  # Add external database if provided
  if (!is.null(params$external_db_dir) && nchar(trimws(params$external_db_dir)) > 0) {
    if (is.null(config$host)) config$host <- list()
    if (is.null(config$host$resources)) config$host$resources <- list()

    config$host$resources$external_db <- list(
      host_path = trimws(params$external_db_dir)
    )
    cat("External DB:", trimws(params$external_db_dir), "\n")
  }

  cat("========== SR_AMP CONFIG COMPLETE ==========\n\n")
  config
}

generate_sr_meta_config <- function(params) {
  cat("\n========== BUILDING SR_META CONFIG ==========\n")
  cat("Received params:\n")
  cat(paste(names(params), "=", sapply(params, function(x) paste(x, collapse=",")), "\n"))

  tech_map <- c(
    "illumina" = "ILLUMINA",
    "iontorrent" = "IONTORRENT",
    "bgi" = "BGI"
  )
  technology <- tech_map[params$technology] %||% "ILLUMINA"
  cat("Mapped technology:", technology, "\n")

  input_style <- if (params$paired_end) "FASTQ_PAIRED" else "FASTQ_SINGLE"
  cat("Input style:", input_style, "\n")

  input_obj <- list(style = input_style)
  if (params$paired_end) {
    input_obj$fastq_r1 <- params$input_r1
    input_obj$fastq_r2 <- params$input_r2
    cat("Paired-end: R1=", params$input_r1, "R2=", params$input_r2, "\n")
  } else {
    input_obj$fastq_r1 <- params$input_path
    cat("Single-end:", params$input_path, "\n")
  }

  # Build output.selected array - ensure it's a character vector for JSON array
  output_selected <- if (!is.null(params$output_selected) && length(params$output_selected) > 0) {
    as.character(params$output_selected)
  } else {
    c("all")
  }
  cat("Output selected:", paste(output_selected, collapse=", "), "\n")

  # Determine specimen
  specimen <- params$sample_type %||% "other"
  cat("Specimen:", specimen, "\n")

  # Determine threads
  threads <- as.integer(params$threads %||% 4)
  cat("Threads:", threads, "\n")

  # Quality threshold
  quality_threshold <- as.integer(params$quality_threshold %||% 20)
  cat("Quality threshold:", quality_threshold, "\n")

  # Minimum read length
  min_read_length <- if (!is.null(params$min_read_length)) as.integer(params$min_read_length) else NULL
  if (!is.null(min_read_length)) cat("Min read length:", min_read_length, "\n")

  # Trim adapter
  trim_adapter <- if (!is.null(params$trim_adapter)) as.logical(params$trim_adapter) else NULL
  if (!is.null(trim_adapter)) cat("Trim adapter:", trim_adapter, "\n")

  # Demultiplex
  demultiplex <- if (!is.null(params$demultiplex)) as.logical(params$demultiplex) else NULL
  if (!is.null(demultiplex)) cat("Demultiplex:", demultiplex, "\n")

  # Run scope
  run_scope <- params$run_scope %||% NULL
  if (!is.null(run_scope)) cat("Run scope:", run_scope, "\n")

  # Human depletion
  human_depletion <- if (!is.null(params$human_depletion) && params$human_depletion) 1L else 0L
  cat("Human depletion (remove_host):", human_depletion, "\n")

  # Build params.common with all UI selections
  params_common <- list(
    min_qscore = quality_threshold,
    remove_host = human_depletion,
    specimen = specimen
  )

  # Add optional fields to params.common if provided
  if (!is.null(min_read_length)) params_common$min_read_length <- min_read_length
  if (!is.null(trim_adapter)) params_common$trim_adapter <- trim_adapter
  if (!is.null(demultiplex)) params_common$demultiplex <- demultiplex

  # Generate config matching schema
  config <- list(
    pipeline_id = "sr_meta",

    run = list(
      work_dir = params$output_dir,
      run_id = params$run_id,
      force_overwrite = 1L
    ),

    technology = technology,
    specimen = specimen,

    input = input_obj,

    resources = list(
      threads = threads
    ),

    params = list(
      common = params_common
    ),

    output = list(
      selected = output_selected
    )
  )

  # Add run_scope if provided
  if (!is.null(run_scope)) {
    config$run$scope <- run_scope
  }

  # Add Kraken2 DB if provided (either from kraken_db field or external_db_dir)
  kraken_db_path <- NULL
  if (!is.null(params$kraken_db) && nchar(trimws(params$kraken_db)) > 0) {
    kraken_db_path <- trimws(params$kraken_db)
    cat("Kraken2 DB from kraken_db field:", kraken_db_path, "\n")
  } else if (!is.null(params$external_db_dir) && nchar(trimws(params$external_db_dir)) > 0) {
    db_type <- params$database_type %||% "auto"
    if (db_type %in% c("auto", "kraken2")) {
      kraken_db_path <- trimws(params$external_db_dir)
      cat("Kraken2 DB from external_db_dir:", kraken_db_path, "\n")
    }
  }

  if (!is.null(kraken_db_path)) {
    config$host <- list(
      resources = list(
        kraken2_db = list(
          host_path = kraken_db_path
        )
      )
    )
  }

  cat("========== SR_META CONFIG COMPLETE ==========\n\n")
  config
}

generate_lr_amp_config <- function(params) {
  stop("Long-read amplicon config generation not yet implemented")
}

generate_lr_meta_config <- function(params) {
  stop("Long-read metagenomics config generation not yet implemented")
}

save_config <- function(config, run_id) {
  outputs_dir <- get_outputs_directory()

  dir.create(outputs_dir, recursive = TRUE, showWarnings = FALSE)

  cat("\n========== FINAL CONFIG OBJECT ==========\n")
  cat("Structure:\n")
  print(str(config))
  cat("\nJSON representation:\n")
  cat(jsonlite::toJSON(config, auto_unbox = TRUE, pretty = TRUE))
  cat("\n=========================================\n\n")

  config_file <- file.path(outputs_dir, paste0("config_", run_id, ".json"))
  jsonlite::write_json(config, config_file, pretty = TRUE, auto_unbox = TRUE)

  cat("Config written to:", config_file, "\n")
  config_file
}

load_config <- function(run_id) {
  outputs_dir <- get_outputs_directory()
  config_file <- file.path(outputs_dir, run_id, "config.json")

  if (!file.exists(config_file)) {
    return(NULL)
  }

  jsonlite::fromJSON(config_file)
}

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || is.na(x)) y else x
}

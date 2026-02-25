# Kit barcode count lookup — caps the "+ Add barcode" button
KIT_BARCODE_COUNTS <- list(
  "EXP-PBC001"    = 12L, "EXP-PBC096"    = 96L,
  "EXP-NBD104"    = 24L, "EXP-NBD196"    = 96L,
  "SQK-RBK004"    = 12L, "SQK-RBK110"    = 96L,
  "SQK-16S024"    = 24L, "SQK-NBD114-24" = 24L,
  "SQK-NBD114-96" = 96L, "SQK-RPB114-24" = 24L
)

get_kit_max <- function(kit) {
  for (k in names(KIT_BARCODE_COUNTS)) {
    if (grepl(k, kit, fixed = TRUE)) return(KIT_BARCODE_COUNTS[[k]])
  }
  96L  # safe default for unknown kits
}

long_read_server <- function(id, shared) {
  moduleServer(id, function(input, output, session) {

    ns <- session$ns

    volumes <- c(
      Desktop   = fs::path_home("Desktop"),
      Project   = dirname(getwd()),
      Home      = fs::path_home(),
      Documents = fs::path_home("Documents"),
      Root      = "/"
    )

    # Helper: load saved default root for this input (falls back to "Desktop")
    .lr_root <- function(key, default = "Desktop") get_ui_pref(paste0("lr_", key, "_root"), default)
    .lr_rel  <- function(key) get_ui_pref(paste0("lr_", key, "_rel"), "")

    # --- Detect installed Dorado models (uses same logic as wizard) ---
    detect_installed_models <- function() {
      repo_root <- dirname(getwd())
      models_dir <- file.path(repo_root, "tools", "models", "dorado")

      # Use exact same model list as wizard_defs.R WIZARD_DORADO_MODELS
      wizard_models <- list(
        list(id = "dna_r10.4.1_e8.2_400bps_hac@v5.2.0", name = "HAC v5.2.0 (RECOMMENDED)", desc = "High accuracy for modern 5kHz ONT data"),
        list(id = "dna_r10.4.1_e8.2_400bps_sup@v5.2.0", name = "SUP v5.2.0", desc = "Super accuracy for 5kHz ONT data (slower)"),
        list(id = "dna_r10.4.1_e8.2_400bps_hac@v5.0.0", name = "HAC v5.0.0", desc = "High accuracy stable release"),
        list(id = "dna_r10.4.1_e8.2_400bps_hac@v4.3.0", name = "HAC v4.3.0", desc = "Legacy high accuracy model"),
        list(id = "dna_r10.4.1_e8.2_400bps_hac@v4.2.0", name = "HAC v4.2.0", desc = "Legacy baseline model"),
        list(id = "dna_r10.4.1_e8.2_400bps_hac@v3.5.2", name = "HAC v3.5.2 (Legacy 4kHz)", desc = "High accuracy for LEGACY 4kHz R10.4.1 E8.2 data")
      )

      installed <- character(0)
      if (dir.exists(models_dir)) {
        for (m in wizard_models) {
          if (dir.exists(file.path(models_dir, m$id))) {
            installed <- c(installed, m$id)
          }
        }
      }
      installed
    }

    # Build Dorado model choices matching wizard display
    # Uses exact same model list and indicators as wizard_defs.R WIZARD_DORADO_MODELS
    build_dorado_choices <- function() {
      installed <- detect_installed_models()
      checkmark <- "\u2713"  # ✓ unicode checkmark (matches wizard badge)

      # Model definitions matching wizard_defs.R WIZARD_DORADO_MODELS exactly
      wizard_models <- list(
        list(id = "dna_r10.4.1_e8.2_400bps_hac@v5.2.0", name = "HAC v5.2.0 (RECOMMENDED)"),
        list(id = "dna_r10.4.1_e8.2_400bps_sup@v5.2.0", name = "SUP v5.2.0"),
        list(id = "dna_r10.4.1_e8.2_400bps_hac@v5.0.0", name = "HAC v5.0.0"),
        list(id = "dna_r10.4.1_e8.2_400bps_hac@v4.3.0", name = "HAC v4.3.0"),
        list(id = "dna_r10.4.1_e8.2_400bps_hac@v4.2.0", name = "HAC v4.2.0"),
        list(id = "dna_r10.4.1_e8.2_400bps_hac@v3.5.2", name = "HAC v3.5.2 (Legacy 4kHz)")
      )

      # Build choices with ✓ checkmark for installed models (matches wizard)
      choices <- c("Auto-detect" = "")
      for (m in wizard_models) {
        label <- paste0(m$name, if (m$id %in% installed) paste0(" ", checkmark) else "")
        choices <- c(choices, setNames(m$id, label))
      }
      choices
    }

    # Update dorado_model choices when UI loads and periodically (to detect wizard installs)
    observe({
      # Re-check every time the tab is accessed or models might have changed
      invalidateLater(5000)  # Check every 5 seconds for newly installed models
      updateSelectInput(session, "dorado_model", choices = build_dorado_choices())
    })

    # --- Barcode mapping state ---
    n_barcodes <- reactiveVal(0L)

    # Reset rows when the kit changes
    observeEvent(input$barcoding_kit, {
      n_barcodes(0L)
    }, ignoreInit = TRUE)

    # Add a barcode row (capped by kit max)
    observeEvent(input$add_barcode_row, {
      cur     <- n_barcodes()
      max_bc  <- get_kit_max(input$barcoding_kit %||% "")
      if (cur < max_bc) n_barcodes(cur + 1L)
    })

    # Remove the last barcode row
    observeEvent(input$remove_barcode_row, {
      cur <- n_barcodes()
      if (cur > 0L) n_barcodes(cur - 1L)
    })

    # Render dynamic barcode rows
    output$barcode_map_rows <- renderUI({
      n <- n_barcodes()
      if (n == 0L) return(NULL)
      tagList(lapply(seq_len(n), function(i) {
        bc_id <- sprintf("barcode%02d", i)
        div(
          class = "row mb-2 align-items-center",
          div(class = "col-md-3", tags$code(bc_id)),
          div(
            class = "col-md-9",
            textInput(
              ns(paste0("bc_name_", i)), NULL,
              placeholder = "Sample name",
              value = isolate(input[[paste0("bc_name_", i)]] %||% "")
            )
          )
        )
      }))
    })

    # Collect sample_map from current barcode rows
    get_sample_map <- reactive({
      n <- n_barcodes()
      if (n == 0L) return(NULL)
      m <- list()
      for (i in seq_len(n)) {
        nm <- trimws(input[[paste0("bc_name_", i)]] %||% "")
        if (nchar(nm) > 0) m[[sprintf("barcode%02d", i)]] <- nm
      }
      if (length(m) == 0L) NULL else m
    })

    # --- File / directory choosers (defaultRoot from saved prefs) ---
    shinyFileChoose(input, "input_file_browse", roots = volumes, session = session,
                    filetypes = c("fastq", "fq", "gz", "fast5", "pod5", ""),
                    defaultRoot = .lr_root("input"), defaultPath = .lr_rel("input"))

    shinyDirChoose(input, "kraken_db_browse", roots = volumes, session = session,
                   defaultRoot = .lr_root("kraken", "Home"), defaultPath = .lr_rel("kraken"))
    shinyDirChoose(input, "external_db_dir_browse", roots = volumes, session = session,
                   defaultRoot = .lr_root("extdb", "Home"), defaultPath = .lr_rel("extdb"))
    shinyDirChoose(input, "dorado_models_dir_browse", roots = volumes, session = session,
                   defaultRoot = .lr_root("dorado_models", "Home"), defaultPath = .lr_rel("dorado_models"))
    shinyFileChoose(input, "dorado_bin_browse", roots = volumes, session = session,
                    filetypes = c(""),
                    defaultRoot = .lr_root("dorado_bin", "Home"), defaultPath = .lr_rel("dorado_bin"))

    # Helper: update a drop-zone display field and trigger has-path class update
    .set_display <- function(id, path) {
      # Escape single quotes in path for JS safety
      safe_path <- gsub("'", "\\\\'", path)
      shinyjs::runjs(sprintf("$('#%s').val('%s').trigger('change')", session$ns(id), safe_path))
    }

    # Populate input_path from file browse
    observeEvent(input$input_file_browse, {
      if (!is.integer(input$input_file_browse)) {
        fp <- parseFilePaths(volumes, input$input_file_browse)
        if (nrow(fp) > 0) {
          full_paths <- as.character(fp$datapath)

          # If multiple files selected from same directory, pass the directory instead
          # (pipeline expects directory path for batch processing, not comma-separated files)
          if (length(full_paths) > 1) {
            dirs <- unique(dirname(full_paths))
            if (length(dirs) == 1) {
              final_path <- dirs[1]
            } else {
              final_path <- full_paths[1]
              showNotification(
                "Multiple files from different directories selected. Using first file only. To process multiple files, select files from the same directory or enter the directory path directly.",
                type = "warning",
                duration = 10
              )
            }
          } else {
            final_path <- full_paths[1]
          }

          updateTextInput(session, "input_path", value = final_path)
          .set_display("input_path_display", final_path)
          info <- vol_for_path(final_path, volumes)
          save_ui_pref("lr_input_root", info$root)
          save_ui_pref("lr_input_rel",  info$rel)
        }
      }
    })

    # Populate kraken_db from directory browse
    observeEvent(input$kraken_db_browse, {
      if (!is.integer(input$kraken_db_browse)) {
        dp <- parseDirPath(volumes, input$kraken_db_browse)
        if (length(dp) > 0 && nchar(dp) > 0) {
          full_path <- as.character(dp)
          updateTextInput(session, "kraken_db", value = full_path)
          .set_display("kraken_db_display", full_path)
          info <- vol_for_path(full_path, volumes)
          save_ui_pref("lr_kraken_root", info$root)
          save_ui_pref("lr_kraken_rel",  info$rel)
        }
      }
    })

    # Populate external_db_dir from directory browse
    observeEvent(input$external_db_dir_browse, {
      if (!is.integer(input$external_db_dir_browse)) {
        dp <- parseDirPath(volumes, input$external_db_dir_browse)
        if (length(dp) > 0 && nchar(dp) > 0) {
          full_path <- as.character(dp)
          updateTextInput(session, "external_db_dir", value = full_path)
          .set_display("external_db_dir_display", full_path)
          info <- vol_for_path(full_path, volumes)
          save_ui_pref("lr_extdb_root", info$root)
          save_ui_pref("lr_extdb_rel",  info$rel)
        }
      }
    })

    # Populate dorado_bin from file browse
    observeEvent(input$dorado_bin_browse, {
      if (!is.integer(input$dorado_bin_browse)) {
        fp <- parseFilePaths(volumes, input$dorado_bin_browse)
        if (nrow(fp) > 0) {
          full_path <- as.character(fp$datapath[1])
          updateTextInput(session, "dorado_bin", value = full_path)
          .set_display("dorado_bin_display", full_path)
          info <- vol_for_path(full_path, volumes)
          save_ui_pref("lr_dorado_bin_root", info$root)
          save_ui_pref("lr_dorado_bin_rel",  info$rel)
        }
      }
    })

    # Populate dorado_models_dir from directory browse
    observeEvent(input$dorado_models_dir_browse, {
      if (!is.integer(input$dorado_models_dir_browse)) {
        dp <- parseDirPath(volumes, input$dorado_models_dir_browse)
        if (length(dp) > 0 && nchar(dp) > 0) {
          full_path <- as.character(dp)
          updateTextInput(session, "dorado_models_dir", value = full_path)
          .set_display("dorado_models_dir_display", full_path)
          info <- vol_for_path(full_path, volumes)
          save_ui_pref("lr_dorado_models_root", info$root)
          save_ui_pref("lr_dorado_models_rel",  info$rel)
        }
      }
    })

    # Auto-detect Dorado paths from wizard-installed locations
    observe({
      repo_root <- dirname(getwd())
      dorado_candidates <- c(
        file.path(repo_root, "main", "tools", "dorado", "bin", "dorado"),
        file.path(repo_root, "tools", "dorado", "bin", "dorado")
      )
      for (candidate in dorado_candidates) {
        if (file.exists(candidate) && nchar(input$dorado_bin) == 0) {
          updateTextInput(session, "dorado_bin", value = candidate)
          .set_display("dorado_bin_display", candidate)
          models_dir <- file.path(dirname(dirname(candidate)), "models")
          if (dir.exists(models_dir) && nchar(input$dorado_models_dir) == 0) {
            updateTextInput(session, "dorado_models_dir", value = models_dir)
            .set_display("dorado_models_dir_display", models_dir)
          }
          break
        }
      }
    })

    # --- Display dynamic values ---
    output$quality_threshold_display <- renderText({ as.character(input$quality_threshold) })
    output$min_read_length_display   <- renderText({ as.character(input$min_read_length) })

    # --- Summary panel ---
    output$summary_pipeline <- renderText({
      switch(input$pipeline,
        "lr_amp"  = "Long Read 16S Amplicon (Emu)",
        "lr_meta" = "Long Read Metagenomics",
        input$pipeline
      )
    })

    output$summary_technology <- renderText({
      switch(input$lr_technology,
        "ont"    = "Oxford Nanopore (ONT)",
        "pacbio" = "PacBio",
        toupper(input$lr_technology)
      )
    })

    output$summary_format <- renderText({ toupper(input$input_format) })

    output$summary_sample_type <- renderText({ tools::toTitleCase(input$sample_type) })

    output$summary_run_scope <- renderText({
      switch(input$run_scope,
        "full" = "Full Pipeline",
        "qc"   = "QC Only",
        tools::toTitleCase(input$run_scope)
      )
    })

    # --- Validation ---
    validate_inputs <- reactive({
      errors <- character(0)

      if (nchar(input$input_path) == 0) {
        errors <- c(errors, "Input path is required")
      }

      if (input$pipeline == "lr_meta") {
        kraken_db_provided <- nchar(input$kraken_db) > 0 ||
          (nchar(input$external_db_dir %||% "") > 0 &&
           (input$database_type %||% "auto") %in% c("auto", "kraken2"))
        if (!kraken_db_provided) {
          errors <- c(errors, "Kraken2 database path is required for metagenomics")
        }
      }

      if (input$input_format %in% c("fast5", "pod5") && nchar(input$barcoding_kit) == 0) {
        errors <- c(errors, "Barcoding Kit is required for FAST5/POD5 input (Dorado demultiplexing)")
      }

      list(valid = length(errors) == 0, errors = errors)
    })

    output$validation_messages <- renderUI({
      val <- validate_inputs()

      if (val$valid) {
        div(
          class = "alert alert-success",
          role = "alert",
          style = "font-size: 0.875rem;",
          icon("check-circle"), " Configuration is valid"
        )
      } else {
        div(
          class = "alert alert-danger",
          role = "alert",
          style = "font-size: 0.875rem;",
          icon("triangle-exclamation"), " ", tags$b("Issues:"),
          tags$ul(
            class = "mb-0 mt-2",
            lapply(val$errors, function(e) tags$li(e))
          )
        )
      }
    })

    # --- Aggregate output checkboxes into output_selected vector ---
    get_output_selected <- reactive({
      selected <- c(
        if (isTRUE(input$output_raw_csv))         "raw_csv",
        if (isTRUE(input$output_pie_chart))       "pie_chart",
        if (isTRUE(input$output_heatmap))         "heatmap",
        if (isTRUE(input$output_stacked_bar))     "stacked_bar",
        if (isTRUE(input$output_quality_reports)) "quality_reports"
      )
      if (length(selected) == 0) c("all") else selected
    })

    # Kit values from Input Configuration section
    # - FAST5/POD5: required for Dorado basecalling
    # - FASTQ: optional for demultiplexing
    get_effective_barcoding_kit <- reactive({
      input$barcoding_kit
    })

    get_effective_ligation_kit <- reactive({
      input$ligation_kit
    })

    # --- Build CLI command (dry-run preview only) ---
    build_command <- reactive({
      cmd <- c(
        file.path(dirname(getwd()), "stabiom"),
        "run",
        "-p", input$pipeline,
        "-i", input$input_path
      )

      if (nchar(input$output_dir) > 0)  cmd <- c(cmd, "-o", input$output_dir)
      if (nchar(input$run_name) > 0)    cmd <- c(cmd, "--run-name", input$run_name)

      cmd <- c(cmd, "--sample-type", input$sample_type)
      cmd <- c(cmd, "--threads",     as.character(input$threads))
      cmd <- c(cmd, "--technology",  toupper(input$lr_technology %||% "ont"))

      if (!is.null(input$run_scope) && nchar(input$run_scope) > 0) {
        cmd <- c(cmd, "--scope", input$run_scope)
      }

      if (input$input_format %in% c("fast5", "pod5")) {
        if (nchar(input$dorado_bin) > 0)        cmd <- c(cmd, "--dorado-bin",        input$dorado_bin)
        if (nchar(input$dorado_models_dir) > 0) cmd <- c(cmd, "--dorado-models-dir", input$dorado_models_dir)
        if (nchar(input$dorado_model) > 0)      cmd <- c(cmd, "--dorado-model",      input$dorado_model)
        if (nchar(input$barcoding_kit) > 0)     cmd <- c(cmd, "--barcoding-kit",     input$barcoding_kit)
        if (nchar(input$ligation_kit) > 0)      cmd <- c(cmd, "--ligation-kit",      input$ligation_kit)
      }

      if (input$pipeline == "lr_meta" && nchar(input$kraken_db) > 0) {
        cmd <- c(cmd, "--db", input$kraken_db)
      }

      if (input$sample_type == "vaginal" && !is.null(input$valencia)) {
        cmd <- c(cmd, "--valencia", input$valencia)
      }

      cmd <- c(cmd, "--quality-threshold", as.character(input$quality_threshold))
      cmd <- c(cmd, "--min-length",        as.character(input$min_read_length))

      if (isTRUE(input$trim_adapter)) cmd <- c(cmd, "--trim-adapter")
      if (isTRUE(input$demultiplex))  cmd <- c(cmd, "--demultiplex")

      cmd
    })

    # --- Dry run preview ---
    observeEvent(input$dry_run, {
      cmd <- build_command()

      showModal(modalDialog(
        title = "Preview: Pipeline Command",
        tags$p("The following command will be executed:"),
        tags$pre(
          style = "background: #f3f4f6; padding: 1rem; border-radius: 0.375rem; overflow-x: auto;",
          paste(cmd, collapse = " \\\n  ")
        ),
        footer = modalButton("Close"),
        size = "l"
      ))
    })

    # --- Run pipeline ---
    observeEvent(input$run_pipeline, {
      val <- validate_inputs()

      if (!val$valid) {
        showNotification(
          paste("Validation errors:", paste(val$errors, collapse = "; ")),
          type = "error", duration = 10
        )
        return()
      }

      run_id <- if (!is.null(input$run_name) && nchar(trimws(input$run_name)) > 0) {
        sanitized <- trimws(input$run_name)
        sanitized <- gsub("[\\/: *?\"<>|\\\\]", "_", sanitized)
        sanitized <- gsub("\\s+", "_", sanitized)
        sanitized
      } else {
        format(Sys.time(), "%Y%m%d_%H%M%S")
      }

      params <- list(
        run_id            = run_id,
        pipeline          = input$pipeline,
        technology        = input$lr_technology,
        input_format      = input$input_format,
        input_path        = input$input_path,
        output_dir        = input$output_dir,
        run_scope         = input$run_scope,
        quality_threshold = input$quality_threshold,
        min_read_length   = input$min_read_length,
        threads           = input$threads,
        sample_type       = input$sample_type,
        trim_adapter      = input$trim_adapter,
        demultiplex       = input$demultiplex,
        primer_sequences  = input$primer_sequences,
        barcode_sequences = input$barcode_sequences,
        barcoding_kit     = get_effective_barcoding_kit(),
        ligation_kit      = get_effective_ligation_kit(),
        kraken_db              = input$kraken_db,
        kraken_confidence      = input$kraken_confidence,
        kraken_min_hit_groups  = input$kraken_min_hit_groups,
        external_db_dir        = input$external_db_dir,
        database_type          = input$database_type,
        human_depletion        = input$human_depletion,
        valencia          = input$valencia,
        dorado_bin        = input$dorado_bin,
        dorado_models_dir = input$dorado_models_dir,
        dorado_model      = input$dorado_model,
        output_selected   = get_output_selected(),
        enable_postprocess = any(c(isTRUE(input$output_raw_csv), isTRUE(input$output_pie_chart),
                                   isTRUE(input$output_heatmap), isTRUE(input$output_stacked_bar),
                                   isTRUE(input$output_quality_reports))),
        sample_map        = get_sample_map()
      )

      config <- if (input$pipeline == "lr_amp") {
        generate_lr_amp_config(params)
      } else {
        generate_lr_meta_config(params)
      }

      config_file <- save_config(config, run_id)

      shared$current_run <- list(
        run_id      = run_id,
        pipeline    = input$pipeline,
        config_file = config_file,
        run_name    = input$run_name,
        sample_type = input$sample_type
      )

      shared$run_status <- "ready"
    })
  })
}

long_read_server <- function(id, shared) {
  moduleServer(id, function(input, output, session) {

    volumes <- c(
      Home    = fs::path_home(),
      Root    = "/",
      Desktop = fs::path_home("Desktop"),
      Documents = fs::path_home("Documents"),
      Project = dirname(getwd())
    )

    # --- File / directory choosers ---
    shinyFileChoose(input, "input_file_browse", roots = volumes, session = session,
                    filetypes = c("fastq", "fq", "gz", ""))

    shinyDirChoose(input, "input_dir_browse",         roots = volumes, session = session)
    shinyDirChoose(input, "kraken_db_browse",         roots = volumes, session = session)
    shinyDirChoose(input, "dorado_models_dir_browse", roots = volumes, session = session)
    shinyFileChoose(input, "dorado_bin_browse", roots = volumes, session = session, filetypes = c(""))

    # Populate input_path from file browse
    observeEvent(input$input_file_browse, {
      if (!is.integer(input$input_file_browse)) {
        fp <- parseFilePaths(volumes, input$input_file_browse)
        if (nrow(fp) > 0) {
          full_path <- as.character(fp$datapath[1])
          updateTextInput(session, "input_path", value = full_path)
          shinyjs::runjs(sprintf("$('#%s').val('%s')", session$ns("input_path_display"), full_path))
        }
      }
    })

    # Populate input_path from directory browse
    observeEvent(input$input_dir_browse, {
      if (!is.integer(input$input_dir_browse)) {
        dp <- parseDirPath(volumes, input$input_dir_browse)
        if (length(dp) > 0 && nchar(dp) > 0) {
          full_path <- as.character(dp)
          updateTextInput(session, "input_path", value = full_path)
          shinyjs::runjs(sprintf("$('#%s').val('%s')", session$ns("input_path_display"), full_path))
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
          shinyjs::runjs(sprintf("$('#%s').val('%s')", session$ns("kraken_db_display"), full_path))
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
          shinyjs::runjs(sprintf("$('#%s').val('%s')", session$ns("dorado_bin_display"), full_path))
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
          shinyjs::runjs(sprintf("$('#%s').val('%s')", session$ns("dorado_models_dir_display"), full_path))
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
          shinyjs::runjs(sprintf("$('#%s').val('%s')", session$ns("dorado_bin_display"), candidate))
          models_dir <- file.path(dirname(dirname(candidate)), "models")
          if (dir.exists(models_dir) && nchar(input$dorado_models_dir) == 0) {
            updateTextInput(session, "dorado_models_dir", value = models_dir)
            shinyjs::runjs(sprintf("$('#%s').val('%s')", session$ns("dorado_models_dir_display"), models_dir))
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

      if (input$pipeline == "lr_meta" && nchar(input$kraken_db) == 0) {
        errors <- c(errors, "Kraken2 database path is required for metagenomics")
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

    # Determine effective kit values:
    # - FAST5/POD5: use kits from Input Configuration section (required for Dorado)
    # - FASTQ: use kits from Processing Parameters section (optional)
    get_effective_barcoding_kit <- reactive({
      if (input$input_format %in% c("fast5", "pod5")) input$barcoding_kit else input$barcoding_kit_proc
    })

    get_effective_ligation_kit <- reactive({
      if (input$input_format %in% c("fast5", "pod5")) input$ligation_kit else input$ligation_kit_proc
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
        kraken_db         = input$kraken_db,
        human_depletion   = input$human_depletion,
        valencia          = input$valencia,
        dorado_bin        = input$dorado_bin,
        dorado_models_dir = input$dorado_models_dir,
        dorado_model      = input$dorado_model,
        output_selected   = get_output_selected(),
        enable_postprocess = any(c(isTRUE(input$output_raw_csv), isTRUE(input$output_pie_chart),
                                   isTRUE(input$output_heatmap), isTRUE(input$output_stacked_bar),
                                   isTRUE(input$output_quality_reports)))
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

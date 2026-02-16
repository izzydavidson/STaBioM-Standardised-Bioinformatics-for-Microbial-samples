short_read_server <- function(id, shared) {
  moduleServer(id, function(input, output, session) {

    volumes <- c(
      Home = fs::path_home(),
      Root = "/",
      Desktop = fs::path_home("Desktop"),
      Documents = fs::path_home("Documents"),
      Project = dirname(getwd())
    )

    shinyFileChoose(input, "input_path_browse", roots = volumes, session = session,
                    filetypes = c("fastq", "fq", "gz", ""))

    shinyFileChoose(input, "input_r1_browse", roots = volumes, session = session,
                    filetypes = c("fastq", "fq", "gz", ""))
    shinyFileChoose(input, "input_r2_browse", roots = volumes, session = session,
                    filetypes = c("fastq", "fq", "gz", ""))

    observeEvent(input$input_path_browse, {
      if (!is.integer(input$input_path_browse)) {
        file_path <- parseFilePaths(volumes, input$input_path_browse)
        if (nrow(file_path) > 0) {
          full_path <- as.character(file_path$datapath[1])
          updateTextInput(session, "input_path", value = full_path)
          shinyjs::runjs(sprintf("$('#%s').val('%s')", session$ns("input_path_display"), full_path))
        }
      }
    })

    observeEvent(input$input_r1_browse, {
      if (!is.integer(input$input_r1_browse)) {
        file_path <- parseFilePaths(volumes, input$input_r1_browse)
        if (nrow(file_path) > 0) {
          full_path <- as.character(file_path$datapath[1])
          updateTextInput(session, "input_r1", value = full_path)
          shinyjs::runjs(sprintf("$('#%s').val('%s')", session$ns("input_r1_display"), full_path))
        }
      }
    })

    observeEvent(input$input_r2_browse, {
      if (!is.integer(input$input_r2_browse)) {
        file_path <- parseFilePaths(volumes, input$input_r2_browse)
        if (nrow(file_path) > 0) {
          full_path <- as.character(file_path$datapath[1])
          updateTextInput(session, "input_r2", value = full_path)
          shinyjs::runjs(sprintf("$('#%s').val('%s')", session$ns("input_r2_display"), full_path))
        }
      }
    })

    output$quality_threshold_display <- renderText({ as.character(input$quality_threshold) })
    output$min_read_length_display <- renderText({ as.character(input$min_read_length) })

    output$summary_pipeline <- renderText({
      switch(input$pipeline,
        "sr_amp" = "16S rRNA Sequencing",
        "sr_meta" = "Metagenomics (WGS)",
        input$pipeline
      )
    })

    output$summary_technology <- renderText({
      switch(input$technology,
        "illumina" = "Illumina",
        "iontorrent" = "Ion Torrent",
        "bgi" = "BGI Platforms",
        input$technology
      )
    })

    output$summary_sample_type <- renderText({
      tools::toTitleCase(input$sample_type)
    })

    output$summary_run_scope <- renderText({
      switch(input$run_scope,
        "full" = "Full Pipeline",
        "qc" = "QC Only",
        "analysis" = "Analysis Only",
        input$run_scope
      )
    })

    get_repo_root <- reactive({
      dirname(getwd())
    })

    validate_output_dir <- reactive({
      output_dir <- input$output_dir
      repo_root <- get_repo_root()

      if (is.null(output_dir) || nchar(trimws(output_dir)) == 0) {
        return(list(valid = FALSE, message = "Output directory cannot be empty"))
      }

      output_dir_normalized <- normalizePath(output_dir, mustWork = FALSE)
      repo_root_normalized <- normalizePath(repo_root, mustWork = FALSE)

      is_inside <- startsWith(output_dir_normalized, repo_root_normalized)

      if (!is_inside) {
        return(list(
          valid = FALSE,
          message = "Output directory must be inside the STaBioM repository"
        ))
      }

      list(valid = TRUE, message = "")
    })

    output$output_dir_validation <- renderUI({
      val <- validate_output_dir()

      if (!val$valid) {
        tags$small(
          class = "text-danger",
          style = "display: block; margin-top: 0.25rem;",
          icon("triangle-exclamation"), " ", val$message
        )
      } else {
        NULL
      }
    })

    validate_inputs <- reactive({
      errors <- character(0)

      output_dir_val <- validate_output_dir()
      if (!output_dir_val$valid) {
        errors <- c(errors, output_dir_val$message)
      }

      if (input$paired_end) {
        if (nchar(input$input_r1) == 0) errors <- c(errors, "Forward reads (R1) path is required")
        if (nchar(input$input_r2) == 0) errors <- c(errors, "Reverse reads (R2) path is required")
      } else {
        if (nchar(input$input_path) == 0) errors <- c(errors, "Input path is required")
      }

      if (input$pipeline == "sr_meta" && nchar(input$kraken_db) == 0) {
        errors <- c(errors, "Kraken2 database path is required for metagenomics")
      }

      if (input$pipeline == "sr_amp") {
        if (is.na(input$dada2_trunc_f) || input$dada2_trunc_f < 50) {
          errors <- c(errors, "DADA2 forward truncation length must be at least 50")
        }
        if (is.na(input$dada2_trunc_r) || input$dada2_trunc_r < 50) {
          errors <- c(errors, "DADA2 reverse truncation length must be at least 50")
        }
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

    build_command <- reactive({
      cmd <- c(
        file.path(dirname(getwd()), "stabiom"),
        "run",
        "-p", input$pipeline
      )

      if (input$paired_end) {
        cmd <- c(cmd, "-i", sprintf("%s,%s", input$input_r1, input$input_r2))
      } else {
        cmd <- c(cmd, "-i", input$input_path)
      }

      if (nchar(input$output_dir) > 0) {
        cmd <- c(cmd, "-o", input$output_dir)
      }

      if (nchar(input$run_name) > 0) {
        cmd <- c(cmd, "--run-name", input$run_name)
      }

      cmd <- c(cmd, "--sample-type", input$sample_type)

      if (input$manually_allocate_threads) {
        cmd <- c(cmd, "--threads", as.character(input$threads))
      }

      if (input$pipeline == "sr_amp") {
        cmd <- c(cmd, "--dada2-trunc-f", as.character(input$dada2_trunc_f))
        cmd <- c(cmd, "--dada2-trunc-r", as.character(input$dada2_trunc_r))
      } else if (input$pipeline == "sr_meta") {
        if (nchar(input$kraken_db) > 0) {
          cmd <- c(cmd, "--db", input$kraken_db)
        }
        if (input$human_depletion) {
          cmd <- c(cmd, "--human-depletion")
        }
      }

      cmd <- c(cmd, "--quality-threshold", as.character(input$quality_threshold))
      cmd <- c(cmd, "--min-length", as.character(input$min_read_length))

      cmd
    })

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

    observeEvent(input$run_pipeline, {
      cat("[DEBUG] Run Pipeline button clicked\n")

      val <- validate_inputs()

      if (!val$valid) {
        cat("[DEBUG] Validation failed:", paste(val$errors, collapse = ", "), "\n")
        showNotification(
          paste("Validation errors:", paste(val$errors, collapse = "; ")),
          type = "error",
          duration = 10
        )
        return()
      }

      cat("[DEBUG] Validation passed\n")

      run_id <- if (!is.null(input$run_name) && nchar(trimws(input$run_name)) > 0) {
        sanitized <- trimws(input$run_name)
        sanitized <- gsub("[\\/:*?\"<>|\\\\]", "_", sanitized)
        sanitized <- gsub("\\s+", "_", sanitized)
        sanitized
      } else {
        format(Sys.time(), "%Y%m%d_%H%M%S")
      }

      threads_value <- if (input$manually_allocate_threads) {
        input$threads
      } else {
        4
      }

      output_selected <- c()
      if (input$output_raw_csv) output_selected <- c(output_selected, "raw_csv")
      if (input$output_pie_chart) output_selected <- c(output_selected, "pie_chart")
      if (input$output_heatmap) output_selected <- c(output_selected, "heatmap")
      if (input$output_stacked_bar) output_selected <- c(output_selected, "stacked_bar")
      if (input$output_quality_reports) output_selected <- c(output_selected, "quality_reports")
      if (length(output_selected) == 0) output_selected <- c("all")

      params <- list(
        run_id = run_id,
        pipeline = input$pipeline,
        technology = input$technology,
        sample_type = input$sample_type,
        paired_end = input$paired_end,
        input_path = input$input_path,
        input_r1 = input$input_r1,
        input_r2 = input$input_r2,
        output_dir = input$output_dir,
        quality_threshold = input$quality_threshold,
        min_read_length = input$min_read_length,
        threads = threads_value,
        dada2_trunc_f = input$dada2_trunc_f,
        dada2_trunc_r = input$dada2_trunc_r,
        kraken_db = input$kraken_db,
        human_depletion = input$human_depletion,
        trim_adapter = input$trim_adapter,
        demultiplex = input$demultiplex,
        primer_sequences = input$primer_sequences,
        barcode_sequences = input$barcode_sequences,
        barcoding_kit = input$barcoding_kit,
        external_db_dir = input$external_db_dir,
        database_type = input$database_type,
        run_scope = input$run_scope,
        valencia = input$valencia,
        output_selected = output_selected
      )

      config <- if (input$pipeline == "sr_amp") {
        generate_sr_amp_config(params)
      } else {
        generate_sr_meta_config(params)
      }

      config_file <- save_config(config, run_id)

      shared$current_run <- list(
        run_id = run_id,
        pipeline = input$pipeline,
        config_file = config_file,
        run_name = input$run_name,
        sample_type = input$sample_type
      )

      cat("[DEBUG] Config saved to:", config_file, "\n")
      cat("[DEBUG] Setting run_status to ready (will trigger modal)\n")

      shared$run_status <- "ready"
    })
  })
}

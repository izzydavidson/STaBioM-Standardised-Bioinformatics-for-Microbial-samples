short_read_server <- function(id, shared) {
  moduleServer(id, function(input, output, session) {

    ns <- session$ns

    # ── Native OS file/dir pickers via osascript ──────────────────────────────

    observeEvent(input$input_path_browse_file, {
      path <- suppressWarnings(trimws(system("osascript -e 'POSIX path of (choose file)'", intern = TRUE)))
      if (length(path) > 0 && nchar(path) > 0) updateTextInput(session, "input_path", value = path)
    })

    observeEvent(input$input_path_browse_dir, {
      path <- suppressWarnings(trimws(system("osascript -e 'POSIX path of (choose folder)'", intern = TRUE)))
      if (length(path) > 0 && nchar(path) > 0) updateTextInput(session, "input_path", value = path)
    })

    observeEvent(input$input_r1_browse, {
      path <- suppressWarnings(trimws(system("osascript -e 'POSIX path of (choose file)'", intern = TRUE)))
      if (length(path) > 0 && nchar(path) > 0) updateTextInput(session, "input_r1", value = path)
    })

    observeEvent(input$input_r2_browse, {
      path <- suppressWarnings(trimws(system("osascript -e 'POSIX path of (choose file)'", intern = TRUE)))
      if (length(path) > 0 && nchar(path) > 0) updateTextInput(session, "input_r2", value = path)
    })

    observeEvent(input$kraken_db_browse, {
      path <- suppressWarnings(trimws(system("osascript -e 'POSIX path of (choose folder)'", intern = TRUE)))
      if (length(path) > 0 && nchar(path) > 0) updateTextInput(session, "kraken_db", value = path)
    })

    observeEvent(input$external_db_dir_browse, {
      path <- suppressWarnings(trimws(system("osascript -e 'POSIX path of (choose folder)'", intern = TRUE)))
      if (length(path) > 0 && nchar(path) > 0) updateTextInput(session, "external_db_dir", value = path)
    })

    observeEvent(input$extra_output_dir_browse, {
      path <- suppressWarnings(trimws(system("osascript -e 'POSIX path of (choose folder)'", intern = TRUE)))
      if (length(path) > 0 && nchar(path) > 0) {
        updateTextInput(session, "extra_output_dir", value = path)
        shared$additional_output_dir <- path
      }
    })

    # --- Barcode mapping state ---
    n_barcodes <- reactiveVal(0L)

    # Reset rows when demultiplex is unchecked
    observeEvent(input$demultiplex, {
      if (!isTRUE(input$demultiplex)) n_barcodes(0L)
    }, ignoreInit = TRUE)

    # Add a barcode row (capped at 96 for short-read — no kit-specific limit)
    observeEvent(input$add_barcode_row, {
      cur <- n_barcodes()
      if (cur < 96L) n_barcodes(cur + 1L)
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

    # --- Additional output directory ---
    # Text field: sync to shared whenever the user types or drag-drops a path
    observeEvent(input$extra_output_dir, {
      val <- trimws(input$extra_output_dir %||% "")
      shared$additional_output_dir <- if (nchar(val) > 0) val else NULL
    }, ignoreInit = TRUE)

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

    validate_inputs <- reactive({
      errors <- character(0)

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

      cmd <- c(cmd, "-o", file.path(dirname(getwd()), "outputs"))

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
        output_dir = file.path(dirname(getwd()), "outputs"),
        quality_threshold = input$quality_threshold,
        min_read_length = input$min_read_length,
        threads = threads_value,
        dada2_trunc_f = input$dada2_trunc_f,
        dada2_trunc_r = input$dada2_trunc_r,
        kraken_db             = input$kraken_db,
        kraken_memory_mapping = input$kraken_memory_mapping,
        human_depletion       = input$human_depletion,
        trim_adapter = input$trim_adapter,
        demultiplex = input$demultiplex,
        primer_sequences = input$primer_sequences,
        barcode_sequences = input$barcode_sequences,
        barcoding_kit = input$barcoding_kit,
        external_db_dir = input$external_db_dir,
        database_type = input$database_type,
        run_scope = input$run_scope,
        valencia = input$valencia,
        output_selected = output_selected,
        enable_postprocess = any(c(isTRUE(input$output_raw_csv), isTRUE(input$output_pie_chart),
                                   isTRUE(input$output_heatmap), isTRUE(input$output_stacked_bar),
                                   isTRUE(input$output_quality_reports))),
        sample_map        = get_sample_map()
      )

      config <- if (input$pipeline == "sr_amp") {
        generate_sr_amp_config(params)
      } else {
        generate_sr_meta_config(params)
      }

      dep_validation <- validate_dependencies(config)

      if (!dep_validation$valid) {
        error_msg <- paste(c(
          "Missing required dependencies:",
          dep_validation$errors
        ), collapse = "\n• ")

        showModal(modalDialog(
          title = "Missing Dependencies",
          tags$div(
            class = "alert alert-danger",
            icon("triangle-exclamation"), " ", tags$b("Cannot start pipeline"),
            tags$ul(
              class = "mt-2 mb-0",
              lapply(dep_validation$errors, function(e) tags$li(e))
            )
          ),
          footer = tagList(
            actionButton("goto_setup_from_error", "Go to Setup Wizard", class = "btn-primary"),
            modalButton("Cancel")
          ),
          easyClose = FALSE
        ))

        observeEvent(input$goto_setup_from_error, {
          removeModal()
          shared$goto_page <- "Setup Wizard"
        }, once = TRUE)

        return()
      }

      if (length(dep_validation$warnings) > 0) {
        showNotification(
          paste(dep_validation$warnings, collapse = "\n"),
          type = "warning",
          duration = 10
        )
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
      cat("[DEBUG] Dependency validation passed\n")
      cat("[DEBUG] Setting run_status to ready (will trigger modal)\n")

      shared$run_status <- "ready"
    })
  })
}

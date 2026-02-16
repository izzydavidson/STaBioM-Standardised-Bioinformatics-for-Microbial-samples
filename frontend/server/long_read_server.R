long_read_server <- function(id, shared) {
  moduleServer(id, function(input, output, session) {

    # Display dynamic values
    output$quality_threshold_display <- renderText({ as.character(input$quality_threshold) })
    output$min_read_length_display <- renderText({ as.character(input$min_read_length) })

    # Summary panel outputs
    output$summary_pipeline <- renderText({
      switch(input$pipeline,
        "lr_amp" = "Long Read 16S Amplicon",
        "lr_meta" = "Long Read Metagenomics",
        input$pipeline
      )
    })

    output$summary_format <- renderText({
      toupper(input$input_format)
    })

    output$summary_sample_type <- renderText({
      tools::toTitleCase(input$sample_type)
    })

    # Validation
    validate_inputs <- reactive({
      errors <- character(0)

      # Check input path
      if (nchar(input$input_path) == 0) {
        errors <- c(errors, "Input path is required")
      }

      # Check Kraken DB for metagenomics or kraken2 classifier
      needs_kraken <- input$pipeline == "lr_meta" ||
                      (input$pipeline == "lr_amp" && input$classifier == "kraken2")

      if (needs_kraken && nchar(input$kraken_db) == 0) {
        errors <- c(errors, "Kraken2 database path is required")
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

    # Build CLI command
    build_command <- reactive({
      cmd <- c(
        file.path(dirname(getwd()), "stabiom"),
        "run",
        "-p", input$pipeline,
        "-i", input$input_path
      )

      # Output
      if (nchar(input$output_dir) > 0) {
        cmd <- c(cmd, "-o", input$output_dir)
      }

      # Run name
      if (nchar(input$run_name) > 0) {
        cmd <- c(cmd, "--run-name", input$run_name)
      }

      # Sample type
      cmd <- c(cmd, "--sample-type", input$sample_type)

      # Threads
      cmd <- c(cmd, "--threads", as.character(input$threads))

      # Dorado params for FAST5
      if (input$input_format == "fast5") {
        if (nchar(input$dorado_bin) > 0) {
          cmd <- c(cmd, "--dorado-bin", input$dorado_bin)
        }
        if (nchar(input$dorado_models_dir) > 0) {
          cmd <- c(cmd, "--dorado-models-dir", input$dorado_models_dir)
        }
        if (nchar(input$dorado_model) > 0) {
          cmd <- c(cmd, "--dorado-model", input$dorado_model)
        }
      }

      # Pipeline-specific params
      if (input$pipeline == "lr_amp") {
        cmd <- c(cmd, "--classifier", input$classifier)
        if (input$classifier == "kraken2" && nchar(input$kraken_db) > 0) {
          cmd <- c(cmd, "--db", input$kraken_db)
        }
      } else if (input$pipeline == "lr_meta") {
        if (nchar(input$kraken_db) > 0) {
          cmd <- c(cmd, "--db", input$kraken_db)
        }
      }

      # Quality params
      cmd <- c(cmd, "--quality-threshold", as.character(input$quality_threshold))
      cmd <- c(cmd, "--min-length", as.character(input$min_read_length))

      cmd
    })

    # Dry run
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

    # Run pipeline
    observeEvent(input$run_pipeline, {
      val <- validate_inputs()

      if (!val$valid) {
        showNotification("Please fix validation errors before running", type = "error")
        return()
      }

      # Set up run context
      # Use user's run name if provided, otherwise generate timestamp
      run_id <- if (!is.null(input$run_name) && nchar(trimws(input$run_name)) > 0) {
        # Sanitize run name: remove invalid filesystem characters
        sanitized <- trimws(input$run_name)
        sanitized <- gsub("[\\/:*?\"<>|\\\\]", "_", sanitized)
        sanitized <- gsub("\\s+", "_", sanitized)
        sanitized
      } else {
        # Fallback to timestamp if no run name provided
        format(Sys.time(), "%Y%m%d_%H%M%S")
      }
      shared$current_run <- list(
        run_id = run_id,
        pipeline = input$pipeline,
        command = build_command(),
        run_name = input$run_name,
        sample_type = input$sample_type
      )

      shared$run_status <- "ready"

      showNotification("Pipeline configured. Click 'Run Progress' tab to start execution.", type = "message", duration = 5)
    })
  })
}

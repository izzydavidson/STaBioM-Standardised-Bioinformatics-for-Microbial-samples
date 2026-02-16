pipeline_modal_server <- function(id, shared) {
  moduleServer(id, function(input, output, session) {

    pipeline_process <- reactiveVal(NULL)
    start_time <- reactiveVal(NULL)
    run_dir <- reactiveVal(NULL)
    pipeline_key <- reactiveVal(NULL)
    log_offsets <- reactiveVal(list())
    combined_log_buffer <- reactiveVal(character())

    observeEvent(shared$run_status, {
      if (shared$run_status == "ready" && !is.null(shared$current_run)) {
        cat("[DEBUG] Showing pipeline modal\n")

        config_json <- tryCatch({
          jsonlite::toJSON(
            jsonlite::fromJSON(shared$current_run$config_file),
            pretty = TRUE,
            auto_unbox = TRUE
          )
        }, error = function(e) {
          paste("Error reading config:", e$message)
        })

        showModal(pipeline_modal_ui(
          shared$current_run$run_id,
          switch(shared$current_run$pipeline,
            "sr_amp" = "Short Read 16S Amplicon",
            "sr_meta" = "Short Read Metagenomics",
            "lr_amp" = "Long Read 16S Amplicon",
            "lr_meta" = "Long Read Metagenomics",
            shared$current_run$pipeline
          ),
          config_json,
          session
        ))

        execute_pipeline()
      }
    })

    execute_pipeline <- function() {
      cat("[DEBUG] Starting pipeline execution\n")

      start_time(Sys.time())
      shared$run_status <- "running"
      combined_log_buffer(character())
      log_offsets(list())

      tryCatch({
        repo_root <- dirname(getwd())
        run_script <- file.path(repo_root, "main", "pipelines", "stabiom_run.sh")
        config_file <- shared$current_run$config_file

        if (!file.exists(run_script)) {
          stop("Pipeline script not found at: ", run_script)
        }

        if (!file.exists(config_file)) {
          stop("Config file not found at: ", config_file)
        }

        config <- jsonlite::fromJSON(config_file)
        output_dir <- config$run$work_dir

        sanitized_run_id <- tolower(shared$current_run$run_id)
        sanitized_run_id <- gsub("[^a-z0-9_-]", "", sanitized_run_id)
        sanitized_run_id <- gsub("^-+|-+$", "", sanitized_run_id)

        expected_run_dir <- file.path(output_dir, sanitized_run_id)
        expected_run_dir_abs <- normalizePath(expected_run_dir, mustWork = FALSE)

        run_dir(expected_run_dir_abs)
        pipeline_key(shared$current_run$pipeline)

        cat("[DEBUG] Run directory:", expected_run_dir_abs, "\n")
        cat("[DEBUG] Pipeline key:", shared$current_run$pipeline, "\n")

        proc <- processx::process$new(
          command = run_script,
          args = c("--config", config_file),
          wd = repo_root,
          stdout = "|",
          stderr = "|",
          supervise = TRUE
        )

        pipeline_process(proc)
        cat("[DEBUG] Pipeline process started with PID:", proc$get_pid(), "\n")

      }, error = function(e) {
        shared$run_status <- "failed"
        cat("[ERROR]", e$message, "\n")
      })
    }

    output$modal_status_badge <- renderUI({
      status <- shared$run_status

      if (status == "running") {
        tags$span(
          class = "badge bg-warning",
          style = "font-size: 1rem; padding: 0.5rem 1rem;",
          icon("spinner", class = "fa-spin"), " PIPELINE IN PROGRESS"
        )
      } else if (status == "completed") {
        tags$span(
          class = "badge bg-success",
          style = "font-size: 1rem; padding: 0.5rem 1rem;",
          icon("check-circle"), " PIPELINE COMPLETE!"
        )
      } else if (status == "failed") {
        tags$span(
          class = "badge bg-danger",
          style = "font-size: 1rem; padding: 0.5rem 1rem;",
          icon("times-circle"), " PIPELINE FAILED"
        )
      } else {
        tags$span(
          class = "badge bg-secondary",
          style = "font-size: 1rem; padding: 0.5rem 1rem;",
          status
        )
      }
    })

    output$elapsed_time <- renderText({
      invalidateLater(1000, session)

      st <- start_time()
      if (is.null(st)) return("--:--:--")

      elapsed <- as.numeric(difftime(Sys.time(), st, units = "secs"))
      hours <- floor(elapsed / 3600)
      mins <- floor((elapsed %% 3600) / 60)
      secs <- floor(elapsed %% 60)

      sprintf("%02d:%02d:%02d", hours, mins, secs)
    })

    observe({
      invalidateLater(500, session)

      rd <- run_dir()
      pk <- pipeline_key()

      if (is.null(rd) || is.null(pk)) return()

      logs <- discover_run_logs(rd, pk)

      if (length(logs) > 0) {
        offsets <- log_offsets()
        current_buffer <- combined_log_buffer()

        for (log in logs) {
          log_path <- log$path
          log_name <- log$name

          if (!file.exists(log_path)) next

          if (is.null(offsets[[log_name]])) {
            offsets[[log_name]] <- 0
          }

          current_size <- file.info(log_path)$size
          last_offset <- offsets[[log_name]]

          if (current_size > last_offset) {
            tryCatch({
              con <- file(log_path, "r")
              seek(con, last_offset)
              new_lines <- readLines(con, warn = FALSE)
              close(con)

              if (length(new_lines) > 0) {
                timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
                prefixed_lines <- paste0("[", timestamp, "] [", log$display_name, "] ", new_lines)
                current_buffer <- c(current_buffer, prefixed_lines)
              }

              offsets[[log_name]] <- current_size
            }, error = function(e) {
              cat("[ERROR] Reading log", log_name, ":", e$message, "\n")
            })
          }
        }

        log_offsets(offsets)
        combined_log_buffer(current_buffer)
      }

      proc <- pipeline_process()
      if (!is.null(proc) && !proc$is_alive()) {
        cat("[DEBUG] Pipeline process has exited\n")

        Sys.sleep(1)

        logs <- discover_run_logs(rd, pk)
        if (length(logs) > 0) {
          offsets <- log_offsets()
          current_buffer <- combined_log_buffer()

          for (log in logs) {
            log_path <- log$path
            if (!file.exists(log_path)) next

            final_size <- file.info(log_path)$size
            last_offset <- offsets[[log$name]]
            if (is.null(last_offset)) last_offset <- 0

            if (final_size > last_offset) {
              tryCatch({
                con <- file(log_path, "r")
                seek(con, last_offset)
                final_lines <- readLines(con, warn = FALSE)
                close(con)

                if (length(final_lines) > 0) {
                  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
                  prefixed_lines <- paste0("[", timestamp, "] [", log$display_name, "] ", final_lines)
                  current_buffer <- c(current_buffer, prefixed_lines)
                }

                offsets[[log$name]] <- final_size
              }, error = function(e) {
                cat("[ERROR] Reading final log", log$name, ":", e$message, "\n")
              })
            }
          }

          log_offsets(offsets)
          combined_log_buffer(current_buffer)
        }

        exit_code <- tryCatch({
          proc$get_exit_status()
        }, error = function(e) -1)

        if (exit_code == 0) {
          shared$run_status <- "completed"
          cat("[INFO] Pipeline completed successfully\n")
        } else {
          shared$run_status <- "failed"
          cat("[INFO] Pipeline failed with exit code:", exit_code, "\n")
        }

        pipeline_process(NULL)
      }
    })

    output$pipeline_log_stream <- renderUI({
      lines <- combined_log_buffer()

      if (length(lines) == 0) {
        return(HTML("<span style='color: #888888;'>Waiting for logs...</span>"))
      }

      colored_lines <- sapply(lines, function(line) {
        style <- if (grepl("ERROR", line, ignore.case = TRUE)) {
          "color: #ff4d4d; font-weight: bold;"
        } else if (grepl("WARNING", line, ignore.case = TRUE)) {
          "color: #ffa500; font-weight: bold;"
        } else if (grepl("succeeded", line, ignore.case = TRUE)) {
          "color: #00cc66; font-weight: bold;"
        } else if (grepl("Started|started", line)) {
          "color: #00e5ff;"
        } else {
          "color: #888888;"
        }

        escaped_line <- htmltools::htmlEscape(line)
        paste0("<span style='", style, "'>", escaped_line, "</span>")
      }, USE.NAMES = FALSE)

      HTML(paste(colored_lines, collapse = "<br>"))
    })

    observeEvent(input$cancel_run, {
      proc <- pipeline_process()

      if (!is.null(proc) && proc$is_alive()) {
        cat("[DEBUG] Cancelling pipeline (PID:", proc$get_pid(), ")\n")

        tryCatch({
          proc$kill_tree()
          shared$run_status <- "cancelled"
          pipeline_process(NULL)
        }, error = function(e) {
          cat("[ERROR] Failed to cancel:", e$message, "\n")
        })
      }
    })

    observeEvent(input$return_dashboard, {
      cat("[DEBUG] Returning to dashboard\n")
      removeModal()
      shared$goto_page <- "Dashboard"
      shared$run_status <- "idle"
      pipeline_process(NULL)
    })
  })
}

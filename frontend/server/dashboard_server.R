dashboard_server <- function(id, shared) {
  moduleServer(id, function(input, output, session) {

    get_run_status <- function(run_dir) {
      logs_dir <- file.path(run_dir, "logs")

      if (!dir.exists(logs_dir)) {
        return("Pending")
      }

      log_files <- list.files(logs_dir, pattern = "\\.log$", full.names = TRUE)

      if (length(log_files) == 0) {
        return("Pending")
      }

      for (log_file in log_files) {
        if (file.exists(log_file) && file.info(log_file)$size > 0) {
          log_content <- tryCatch({
            paste(readLines(log_file, warn = FALSE), collapse = "\n")
          }, error = function(e) "")

          if (grepl("CONTAINER FAILED|ERROR: Module failed|exit code: [1-9]|Pipeline failed", log_content, ignore.case = FALSE)) {
            return("Failed")
          }

          if (grepl("Pipeline completed successfully|Pipeline finished|To retry:", log_content, ignore.case = FALSE)) {
            return("Completed")
          }

          if (nchar(log_content) > 0) {
            return("In Progress")
          }
        }
      }

      return("Pending")
    }

    get_pipeline_type <- function(run_dir) {
      config_file <- file.path(run_dir, "config.json")
      effective_config_file <- file.path(run_dir, "effective_config.json")
      config_original_file <- file.path(run_dir, "config.original.json")

      for (cfg_file in c(effective_config_file, config_file, config_original_file)) {
        if (file.exists(cfg_file)) {
          config <- tryCatch({
            jsonlite::fromJSON(cfg_file)
          }, error = function(e) NULL)

          if (!is.null(config) && !is.null(config$pipeline_id)) {
            return(config$pipeline_id)
          }
        }
      }

      return("unknown")
    }

    get_sample_type <- function(run_dir) {
      config_file <- file.path(run_dir, "config.json")
      effective_config_file <- file.path(run_dir, "effective_config.json")
      config_original_file <- file.path(run_dir, "config.original.json")

      for (cfg_file in c(effective_config_file, config_file, config_original_file)) {
        if (file.exists(cfg_file)) {
          config <- tryCatch({
            jsonlite::fromJSON(cfg_file)
          }, error = function(e) NULL)

          if (!is.null(config)) {
            if (!is.null(config$specimen)) {
              return(config$specimen)
            }
            if (!is.null(config$params) && !is.null(config$params$common) && !is.null(config$params$common$specimen)) {
              return(config$params$common$specimen)
            }
          }
        }
      }

      return("other")
    }

    get_run_date <- function(run_dir) {
      dir_info <- file.info(run_dir)
      if (!is.na(dir_info$mtime)) {
        return(format(dir_info$mtime, "%Y-%m-%d %H:%M"))
      }
      return("")
    }

    project_stats <- reactive({
      outputs_dir <- file.path(dirname(getwd()), "outputs")

      if (!dir.exists(outputs_dir)) {
        return(list(
          total = 0,
          completed = 0,
          in_progress = 0,
          failed = 0,
          recent = data.frame()
        ))
      }

      run_dirs <- list.dirs(outputs_dir, recursive = FALSE, full.names = TRUE)

      if (length(run_dirs) == 0) {
        return(list(
          total = 0,
          completed = 0,
          in_progress = 0,
          failed = 0,
          recent = data.frame()
        ))
      }

      runs <- lapply(run_dirs, function(run_dir) {
        run_id <- basename(run_dir)
        status <- get_run_status(run_dir)
        pipeline <- get_pipeline_type(run_dir)
        sample_type <- get_sample_type(run_dir)
        date <- get_run_date(run_dir)

        data.frame(
          run_id = run_id,
          pipeline = pipeline,
          sample_type = sample_type,
          status = status,
          date = date,
          stringsAsFactors = FALSE
        )
      })

      runs_df <- do.call(rbind, runs)

      if (is.null(runs_df) || nrow(runs_df) == 0) {
        return(list(
          total = 0,
          completed = 0,
          in_progress = 0,
          failed = 0,
          recent = data.frame()
        ))
      }

      runs_df <- runs_df[order(runs_df$date, decreasing = TRUE), ]

      list(
        total = nrow(runs_df),
        completed = sum(runs_df$status == "Completed"),
        in_progress = sum(runs_df$status == "In Progress"),
        failed = sum(runs_df$status == "Failed"),
        recent = head(runs_df, 10)
      )
    })

    output$total_projects <- renderText({
      as.character(project_stats()$total)
    })

    output$completed_projects <- renderText({
      as.character(project_stats()$completed)
    })

    output$in_progress_projects <- renderText({
      as.character(project_stats()$in_progress)
    })

    output$failed_projects <- renderText({
      as.character(project_stats()$failed)
    })

    output$recent_projects_table <- renderTable({
      recent <- project_stats()$recent

      if (nrow(recent) == 0) {
        return(data.frame(
          Message = "No projects found. Run a pipeline to get started!"
        ))
      }

      recent$Pipeline <- sapply(recent$pipeline, function(p) {
        switch(p,
          "sr_amp" = "Short Read 16S",
          "sr_meta" = "Short Read Metagenomics",
          "lr_amp" = "Long Read 16S",
          "lr_meta" = "Long Read Metagenomics",
          p
        )
      })

      data.frame(
        "Run ID" = recent$run_id,
        "Type" = recent$Pipeline,
        "Sample Type" = tools::toTitleCase(recent$sample_type),
        "Status" = recent$status,
        "Date" = recent$date,
        check.names = FALSE
      )
    }, striped = TRUE, hover = TRUE, bordered = TRUE, spacing = "s", width = "100%")

    observeEvent(input$return_to_wizard, {
      shared$show_wizard <- TRUE
    })
  })
}

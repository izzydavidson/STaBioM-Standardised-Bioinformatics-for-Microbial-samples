compare_server <- function(id, shared) {
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

    available_runs <- reactive({
      outputs_dir <- file.path(dirname(getwd()), "outputs")

      if (!dir.exists(outputs_dir)) {
        return(list("No completed runs found" = ""))
      }

      run_dirs <- list.dirs(outputs_dir, recursive = FALSE, full.names = FALSE)

      if (length(run_dirs) == 0) {
        return(list("No completed runs found" = ""))
      }

      completed_runs <- Filter(function(run_id) {
        run_dir <- file.path(outputs_dir, run_id)
        status <- get_run_status(run_dir)
        status == "Completed"
      }, run_dirs)

      if (length(completed_runs) > 0) {
        setNames(completed_runs, completed_runs)
      } else {
        list("No completed runs found" = "")
      }
    })

    observe({
      runs <- available_runs()
      updateSelectInput(session, "run1", choices = runs)
      updateSelectInput(session, "run2", choices = runs)
    })

    comparison_results <- reactiveVal(NULL)

    output$has_results <- reactive({
      !is.null(comparison_results())
    })
    outputOptions(output, "has_results", suspendWhenHidden = FALSE)

    observeEvent(input$compare_runs, {
      if (input$run1 == "" || input$run2 == "") {
        showNotification("Please select two completed runs to compare", type = "warning")
        return()
      }

      if (input$run1 == input$run2) {
        showNotification("Please select two different runs", type = "warning")
        return()
      }

      outputs_dir <- file.path(dirname(getwd()), "outputs")
      run1_path <- file.path(outputs_dir, input$run1)
      run2_path <- file.path(outputs_dir, input$run2)

      cmd <- c(
        file.path(dirname(getwd()), "stabiom"),
        "compare",
        "--run", run1_path,
        "--run", run2_path,
        "--rank", input$rank,
        "--norm", input$normalization
      )

      withProgress(message = "Running comparison...", value = 0.5, {
        result <- tryCatch({
          system2(cmd[1], cmd[-1], stdout = TRUE, stderr = TRUE)
        }, error = function(e) {
          paste("Error:", e$message)
        })

        comparison_results(result)
      })

      showNotification("Comparison completed", type = "message")
    })

    output$comparison_output <- renderUI({
      results <- comparison_results()

      if (is.null(results)) {
        return(NULL)
      }

      tags$pre(
        style = "background: #f9fafb; padding: 1rem; border-radius: 0.375rem; border: 1px solid #e5e7eb; overflow-x: auto; max-height: 600px;",
        paste(results, collapse = "\n")
      )
    })
  })
}

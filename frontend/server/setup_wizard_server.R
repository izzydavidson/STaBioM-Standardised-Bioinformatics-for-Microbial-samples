setup_wizard_server <- function(id, shared) {
  moduleServer(id, function(input, output, session) {

    setup_output_buffer <- reactiveVal(character(0))

    output$has_setup_output <- reactive({
      length(setup_output_buffer()) > 0
    })
    outputOptions(output, "has_setup_output", suspendWhenHidden = FALSE)

    # Check setup status
    check_setup_status <- reactive({
      input$check_status  # Dependency

      repo_root <- dirname(getwd())
      setup_complete_file <- file.path(repo_root, ".setup_complete")

      status <- list(
        setup_complete = file.exists(setup_complete_file),
        docker_available = FALSE,
        databases = list(),
        dorado_available = FALSE,
        r_packages = list()
      )

      # Check R packages
      required_packages <- c("shiny", "bslib", "jsonlite", "shinyjs", "shinydashboard", "sys")
      installed_packages <- sapply(required_packages, requireNamespace, quietly = TRUE)
      status$r_packages <- list(
        required = required_packages,
        installed = sum(installed_packages),
        total = length(required_packages),
        all_installed = all(installed_packages)
      )

      # Check Docker
      docker_check <- tryCatch({
        system2("docker", "--version", stdout = TRUE, stderr = TRUE)
        TRUE
      }, error = function(e) FALSE)

      status$docker_available <- docker_check

      # Check for databases
      db_dir <- file.path(repo_root, "main", "data", "databases")
      if (dir.exists(db_dir)) {
        kraken_dirs <- list.dirs(file.path(db_dir, "kraken2"), recursive = FALSE, full.names = FALSE)
        emu_dirs <- list.dirs(file.path(db_dir, "emu"), recursive = FALSE, full.names = FALSE)

        status$databases <- list(
          kraken2 = kraken_dirs,
          emu = emu_dirs
        )
      }

      # Check for Dorado
      dorado_check <- tryCatch({
        system2("dorado", "--version", stdout = TRUE, stderr = TRUE)
        TRUE
      }, error = function(e) {
        # Also check in common installation paths
        dorado_path <- file.path(repo_root, "main", "tools", "dorado")
        file.exists(file.path(dorado_path, "bin", "dorado"))
      })

      status$dorado_available <- dorado_check

      status
    })

    # Display setup status
    output$setup_status <- renderUI({
      status <- check_setup_status()

      status_items <- list(
        div(
          class = "d-flex align-items-center mb-2",
          if (status$r_packages$all_installed) {
            icon("check-circle", class = "text-success me-2")
          } else {
            icon("circle-xmark", class = "text-warning me-2")
          },
          tags$span("R Packages: ", tags$b(sprintf("%d/%d installed",
            status$r_packages$installed, status$r_packages$total)))
        ),
        div(
          class = "d-flex align-items-center mb-2",
          if (status$setup_complete) {
            icon("check-circle", class = "text-success me-2")
          } else {
            icon("circle-xmark", class = "text-danger me-2")
          },
          tags$span("Setup Completed: ", tags$b(if (status$setup_complete) "Yes" else "No"))
        ),
        div(
          class = "d-flex align-items-center mb-2",
          if (status$docker_available) {
            icon("check-circle", class = "text-success me-2")
          } else {
            icon("circle-xmark", class = "text-danger me-2")
          },
          tags$span("Docker Installed: ", tags$b(if (status$docker_available) "Yes" else "No"))
        ),
        div(
          class = "d-flex align-items-center mb-2",
          if (status$dorado_available) {
            icon("check-circle", class = "text-success me-2")
          } else {
            icon("circle-xmark", class = "text-warning me-2")
          },
          tags$span("Dorado Available: ", tags$b(if (status$dorado_available) "Yes" else "No (optional)"))
        )
      )

      # Add database status
      if (length(status$databases$kraken2) > 0) {
        status_items <- c(status_items, list(
          div(
            class = "d-flex align-items-center mb-2",
            icon("check-circle", class = "text-success me-2"),
            tags$span("Kraken2 Databases: ", tags$b(paste(status$databases$kraken2, collapse = ", ")))
          )
        ))
      } else {
        status_items <- c(status_items, list(
          div(
            class = "d-flex align-items-center mb-2",
            icon("circle-xmark", class = "text-warning me-2"),
            tags$span("Kraken2 Databases: ", tags$b("None installed"))
          )
        ))
      }

      if (length(status$databases$emu) > 0) {
        status_items <- c(status_items, list(
          div(
            class = "d-flex align-items-center mb-2",
            icon("check-circle", class = "text-success me-2"),
            tags$span("Emu Databases: ", tags$b(paste(status$databases$emu, collapse = ", ")))
          )
        ))
      } else {
        status_items <- c(status_items, list(
          div(
            class = "d-flex align-items-center mb-2",
            icon("circle-xmark", class = "text-warning me-2"),
            tags$span("Emu Databases: ", tags$b("None installed"))
          )
        ))
      }

      do.call(tagList, status_items)
    })

    # Launch setup wizard
    observeEvent(input$launch_wizard, {
      stabiom_path <- file.path(dirname(getwd()), "stabiom")

      if (!file.exists(stabiom_path)) {
        showNotification("STaBioM binary not found. Please check your installation.", type = "error")
        return()
      }

      # Launch setup in terminal
      tryCatch({
        # On macOS, use Terminal.app
        if (Sys.info()["sysname"] == "Darwin") {
          system2("osascript", c(
            "-e",
            sprintf("'tell application \"Terminal\" to do script \"%s setup\"'", stabiom_path)
          ), wait = FALSE)
        } else {
          # On Linux, try common terminals
          system2(stabiom_path, "setup", wait = FALSE)
        }

        showNotification("Setup wizard launched in terminal. Complete the setup there, then click 'Refresh Status'.", type = "message", duration = 10)

      }, error = function(e) {
        showNotification(paste("Failed to launch setup wizard:", e$message), type = "error")
      })
    })

    # Download specific database
    observeEvent(input$download_db, {
      if (input$database_choice == "") {
        showNotification("Please select a database to download", type = "warning")
        return()
      }

      stabiom_path <- file.path(dirname(getwd()), "stabiom")
      cmd <- c(stabiom_path, "setup", "-d", input$database_choice)

      withProgress(message = paste("Downloading", input$database_choice, "..."), value = 0.5, {
        result <- tryCatch({
          system2(cmd[1], cmd[-1], stdout = TRUE, stderr = TRUE)
        }, error = function(e) {
          paste("Error:", e$message)
        })

        setup_output_buffer(c(setup_output_buffer(), result))
      })

      showNotification("Database download initiated. Check terminal for progress.", type = "message")
    })

    # Display setup output
    output$setup_output <- renderUI({
      output <- setup_output_buffer()

      if (length(output) == 0) {
        return(NULL)
      }

      tags$div(
        lapply(output, function(line) tags$div(line))
      )
    })

    # Update shared setup status
    observe({
      status <- check_setup_status()
      shared$setup_complete <- status$setup_complete
    })
  })
}

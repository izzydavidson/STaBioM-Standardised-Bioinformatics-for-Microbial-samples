setup_wizard_ui <- function(id) {
  ns <- NS(id)

  tagList(
    div(
      class = "container-fluid p-4",

      # Page header
      div(
        class = "mb-4",
        h1("Setup Wizard"),
        p(class = "text-muted", "Configure STaBioM and download required tools")
      ),

      # Setup status
      div(
        class = "card mb-4",
        div(
          class = "card-body",
          h2("Setup Status"),
          div(
            class = "mt-3",
            uiOutput(ns("setup_status"))
          )
        )
      ),

      # Launch setup wizard
      div(
        class = "card mb-4",
        div(
          class = "card-body",
          h2("Run Setup"),
          p("The setup wizard will guide you through:"),
          tags$ul(
            tags$li("Installing R package dependencies (automatic)"),
            tags$li("Adding STaBioM to your PATH"),
            tags$li("Checking Docker installation"),
            tags$li("Downloading reference databases (Kraken2, Emu)"),
            tags$li("Downloading VALENCIA for vaginal CST classification"),
            tags$li("Downloading Dorado models for FAST5 basecalling")
          ),
          div(
            class = "mt-4",
            actionButton(ns("launch_wizard"), "Launch Setup Wizard",
              icon = icon("wand-magic-sparkles"),
              class = "btn btn-primary btn-lg"
            ),
            actionButton(ns("check_status"), "Refresh Status",
              icon = icon("rotate"),
              class = "btn btn-outline-secondary ms-2"
            )
          ),
          hr(),
          div(
            class = "alert alert-warning",
            role = "alert",
            icon("triangle-exclamation"), " ", tags$b("Note:"), " The setup wizard will open in a terminal window. Follow the interactive prompts there."
          )
        )
      ),

      # Terminal output for setup
      conditionalPanel(
        condition = sprintf("output['%s']", ns("has_setup_output")),
        div(
          class = "card",
          div(
            class = "card-body",
            h2("Setup Output"),
            div(
              class = "terminal-output",
              style = "max-height: 400px;",
              uiOutput(ns("setup_output"))
            )
          )
        )
      ),

      # Manual setup options
      div(
        class = "card",
        div(
          class = "card-body",
          h2("Manual Setup Options"),
          p("Advanced users can run specific setup commands:"),
          div(
            class = "row mt-3",
            div(
              class = "col-md-6 mb-3",
              tags$label(class = "form-label", "Database to Download"),
              selectInput(ns("database_choice"), NULL,
                choices = c(
                  "Select..." = "",
                  "Kraken2 Standard-8" = "kraken2-standard-8",
                  "Kraken2 Standard-16" = "kraken2-standard-16",
                  "Emu Default" = "emu-default"
                )
              )
            ),
            div(
              class = "col-md-6 mb-3",
              div(style = "margin-top: 32px;",
                actionButton(ns("download_db"), "Download Database",
                  icon = icon("download"),
                  class = "btn btn-primary"
                )
              )
            )
          )
        )
      )
    )
  )
}

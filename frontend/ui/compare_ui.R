compare_ui <- function(id) {
  ns <- NS(id)

  tagList(
    div(
      class = "container-fluid p-4",

      # Page header
      div(
        class = "mb-4",
        h1("Compare Pipeline Runs"),
        p(class = "text-muted", "Compare taxonomic profiles from multiple runs")
      ),

      # Selection panel
      div(
        class = "card mb-4",
        div(
          class = "card-body",
          h2("Select Runs to Compare"),
          div(
            class = "row",
            div(
              class = "col-md-6 mb-3",
              tags$label(class = "form-label", "Run 1"),
              selectInput(ns("run1"), NULL, choices = NULL)
            ),
            div(
              class = "col-md-6 mb-3",
              tags$label(class = "form-label", "Run 2"),
              selectInput(ns("run2"), NULL, choices = NULL)
            ),
            div(
              class = "col-md-6 mb-3",
              tags$label(class = "form-label", "Taxonomic Rank"),
              selectInput(ns("rank"), NULL,
                choices = c("Species" = "species", "Genus" = "genus", "Family" = "family", "Order" = "order", "Class" = "class", "Phylum" = "phylum"),
                selected = "species"
              )
            ),
            div(
              class = "col-md-6 mb-3",
              tags$label(class = "form-label", "Normalization"),
              selectInput(ns("normalization"), NULL,
                choices = c("CLR" = "clr", "Relative Abundance" = "relative", "Raw Counts" = "raw"),
                selected = "clr"
              )
            )
          ),
          div(
            class = "mt-3",
            actionButton(ns("compare_runs"), "Compare Runs",
              icon = icon("code-compare"),
              class = "btn btn-primary"
            )
          )
        )
      ),

      # Results panel
      conditionalPanel(
        condition = sprintf("output['%s']", ns("has_results")),
        div(
          class = "card",
          div(
            class = "card-body",
            h2("Comparison Results"),
            div(
              class = "alert alert-info",
              role = "alert",
              icon("info-circle"), " Comparison analysis is performed using the `stabiom compare` command with real pipeline outputs."
            ),
            div(
              class = "mt-3",
              uiOutput(ns("comparison_output"))
            )
          )
        )
      )
    )
  )
}

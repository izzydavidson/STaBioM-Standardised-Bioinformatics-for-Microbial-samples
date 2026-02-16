long_read_ui <- function(id) {
  ns <- NS(id)

  tagList(
    div(
      class = "container-fluid p-4",

      # Page header
      div(
        class = "mb-4",
        h1("Long Read Sequencing"),
        p(class = "text-muted", "Oxford Nanopore, PacBio platforms")
      ),

      div(
        class = "row",

        # Left column - Configuration forms
        div(
          class = "col-lg-8",

          # Input Configuration
          div(
            class = "card mb-4",
            div(
              class = "card-body",
              h2(icon("file-text"), " Input Configuration"),
              div(
                class = "row",
                div(
                  class = "col-md-6 mb-3",
                  tags$label(class = "form-label", "Pipeline Type"),
                  selectInput(ns("pipeline"), NULL,
                    choices = c("16S Amplicon" = "lr_amp", "Metagenomics" = "lr_meta"),
                    selected = "lr_amp"
                  )
                ),
                div(
                  class = "col-md-6 mb-3",
                  tags$label(class = "form-label", "Input Format"),
                  selectInput(ns("input_format"), NULL,
                    choices = c("FASTQ" = "fastq", "FAST5" = "fast5", "POD5" = "pod5"),
                    selected = "fastq"
                  )
                ),
                div(
                  class = "col-md-6 mb-3",
                  tags$label(class = "form-label", "Run Name/ID"),
                  textInput(ns("run_name"), NULL, placeholder = "e.g., LR_2026_001")
                ),
                div(
                  class = "col-md-6 mb-3",
                  tags$label(class = "form-label", "Output Directory"),
                  textInput(ns("output_dir"), NULL, value = file.path(dirname(getwd()), "outputs"))
                )
              ),

              # File Input
              div(
                class = "mb-3",
                tags$label(class = "form-label", "Input Directory or Files"),
                textInput(ns("input_path"), NULL, placeholder = "/path/to/reads/"),
                tags$small(class = "text-muted", "Enter directory path or glob pattern")
              ),

              # Dorado configuration (for FAST5)
              conditionalPanel(
                condition = sprintf("input['%s'] == 'fast5'", ns("input_format")),
                hr(),
                h3("Basecalling Configuration (Dorado)"),
                div(
                  class = "alert alert-info",
                  role = "alert",
                  style = "font-size: 0.875rem;",
                  icon("info-circle"), " FAST5 input requires Dorado for basecalling. If installed via Setup Wizard, paths will be auto-detected."
                ),
                div(
                  class = "row",
                  div(
                    class = "col-md-6 mb-3",
                    tags$label(class = "form-label", "Dorado Binary Path (optional)"),
                    textInput(ns("dorado_bin"), NULL, placeholder = "Auto-detected if installed via wizard")
                  ),
                  div(
                    class = "col-md-6 mb-3",
                    tags$label(class = "form-label", "Dorado Models Directory (optional)"),
                    textInput(ns("dorado_models_dir"), NULL, placeholder = "Auto-detected if installed via wizard")
                  ),
                  div(
                    class = "col-md-12 mb-3",
                    tags$label(class = "form-label", "Dorado Model"),
                    selectInput(ns("dorado_model"), NULL,
                      choices = c(
                        "Auto-detect" = "",
                        "dna_r10.4.1_e8.2_400bps_hac@v5.2.0 (HAC)" = "dna_r10.4.1_e8.2_400bps_hac@v5.2.0",
                        "dna_r10.4.1_e8.2_400bps_sup@v5.2.0 (SUP)" = "dna_r10.4.1_e8.2_400bps_sup@v5.2.0",
                        "dna_r10.4.1_e8.2_400bps_fast@v5.2.0 (FAST)" = "dna_r10.4.1_e8.2_400bps_fast@v5.2.0"
                      ),
                      selected = ""
                    )
                  )
                )
              )
            )
          ),

          # Processing Parameters
          div(
            class = "card mb-4",
            div(
              class = "card-body",
              h2(icon("gears"), " Processing Parameters"),
              div(
                class = "mb-4",
                tags$label(class = "form-label",
                  tags$span("Quality Score Threshold: "),
                  tags$span(class = "text-primary", textOutput(ns("quality_threshold_display"), inline = TRUE))
                ),
                sliderInput(ns("quality_threshold"), NULL, min = 0, max = 40, value = 10, step = 1)
              ),
              div(
                class = "mb-4",
                tags$label(class = "form-label",
                  tags$span("Minimum Read Length: "),
                  tags$span(class = "text-primary", textOutput(ns("min_read_length_display"), inline = TRUE), " bp")
                ),
                sliderInput(ns("min_read_length"), NULL, min = 100, max = 10000, value = 1000, step = 100)
              ),
              div(
                class = "mb-3",
                tags$label(class = "form-label", "Number of Threads"),
                numericInput(ns("threads"), NULL, value = 4, min = 1, max = 32)
              )
            )
          ),

          # Analysis Configuration
          div(
            class = "card mb-4",
            div(
              class = "card-body",
              h2("Analysis Configuration"),
              div(
                class = "row",
                div(
                  class = "col-md-6 mb-3",
                  tags$label(class = "form-label", "Sample Type"),
                  selectInput(ns("sample_type"), NULL,
                    choices = c("Vaginal" = "vaginal", "Gut" = "gut", "Oral" = "oral", "Skin" = "skin", "Other" = "other"),
                    selected = "vaginal"
                  )
                ),
                conditionalPanel(
                  condition = sprintf("input['%s'] == 'vaginal'", ns("sample_type")),
                  div(
                    class = "col-md-6 mb-3",
                    tags$label(class = "form-label", "VALENCIA Classification"),
                    selectInput(ns("valencia"), NULL, choices = c("Yes" = "yes", "No" = "no"), selected = "yes")
                  )
                ),
                conditionalPanel(
                  condition = sprintf("input['%s'] == 'lr_amp'", ns("pipeline")),
                  div(
                    class = "col-md-6 mb-3",
                    tags$label(class = "form-label", "Classifier"),
                    selectInput(ns("classifier"), NULL,
                      choices = c("Emu (full-length 16S)" = "emu", "Kraken2 (partial 16S)" = "kraken2"),
                      selected = "emu"
                    )
                  )
                ),
                conditionalPanel(
                  condition = sprintf("input['%s'] == 'lr_meta' || (input['%s'] == 'lr_amp' && input['%s'] == 'kraken2')", ns("pipeline"), ns("pipeline"), ns("classifier")),
                  div(
                    class = "col-md-6 mb-3",
                    tags$label(class = "form-label", "Kraken2 Database Path"),
                    textInput(ns("kraken_db"), NULL, placeholder = "/path/to/kraken2/db")
                  )
                )
              )
            )
          )
        ),

        # Right column - Summary panel
        div(
          class = "col-lg-4",
          div(
            class = "summary-panel",
            h2("Run Configuration"),
            div(
              class = "summary-item",
              p(class = "text-muted mb-1", style = "font-size: 0.875rem;", "Pipeline"),
              p(style = "margin: 0;", textOutput(ns("summary_pipeline")))
            ),
            div(
              class = "summary-item",
              p(class = "text-muted mb-1", style = "font-size: 0.875rem;", "Input Format"),
              p(style = "margin: 0;", textOutput(ns("summary_format")))
            ),
            div(
              class = "summary-item",
              p(class = "text-muted mb-1", style = "font-size: 0.875rem;", "Sample Type"),
              p(style = "margin: 0;", textOutput(ns("summary_sample_type")))
            ),
            uiOutput(ns("validation_messages")),
            hr(),
            actionButton(ns("run_pipeline"), "Run Pipeline",
              icon = icon("play"),
              class = "btn btn-primary w-100 mb-2"
            ),
            actionButton(ns("dry_run"), "Preview Configuration",
              icon = icon("eye"),
              class = "btn btn-outline-secondary w-100"
            )
          )
        )
      )
    )
  )
}

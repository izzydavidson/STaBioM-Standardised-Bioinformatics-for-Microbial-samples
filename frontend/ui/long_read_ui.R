long_read_ui <- function(id) {
  ns <- NS(id)

  tagList(
    div(
      class = "container-fluid p-4",

      div(
        class = "mb-4",
        h1("Long Read Sequencing"),
        p(class = "text-muted", "Oxford Nanopore, PacBio platforms")
      ),

      div(
        class = "row",

        # Left column
        div(
          class = "col-lg-8",

          # ── Input Configuration ──────────────────────────────────
          div(
            class = "card mb-4",
            div(
              class = "card-body",
              h2(icon("file-text"), " Input Configuration"),
              div(
                class = "row",
                div(
                  class = "col-md-6 mb-3",
                  tags$label(class = "form-label", "Technology Used"),
                  selectInput(ns("lr_technology"), NULL,
                    choices = c("Oxford Nanopore" = "ont", "PacBio" = "pacbio"),
                    selected = "ont"
                  )
                ),
                div(
                  class = "col-md-6 mb-3",
                  tags$label(class = "form-label", "Input Type"),
                  selectInput(ns("input_format"), NULL,
                    choices = c("FASTQ" = "fastq", "FAST5" = "fast5", "POD5" = "pod5"),
                    selected = "fastq"
                  ),
                  uiOutput(ns("input_format_hint"))
                ),
                # Barcoding Kit — required when FAST5, optional when FASTQ
                div(
                  class = "col-md-6 mb-3",
                  tags$label(class = "form-label",
                    "Barcoding Kit",
                    conditionalPanel(
                      condition = sprintf("input['%s'] == 'fast5' || input['%s'] == 'pod5'", ns("input_format"), ns("input_format")),
                      tags$span(class = "text-danger", " *")
                    )
                  ),
                  textInput(ns("barcoding_kit"), NULL, placeholder = "e.g., SQK-RBK004")
                ),
                # Ligation Kit — required when FAST5, optional when FASTQ
                div(
                  class = "col-md-6 mb-3",
                  tags$label(class = "form-label",
                    "Ligation Kit",
                    conditionalPanel(
                      condition = sprintf("input['%s'] == 'fast5' || input['%s'] == 'pod5'", ns("input_format"), ns("input_format")),
                      tags$span(class = "text-danger", " *")
                    )
                  ),
                  textInput(ns("ligation_kit"), NULL, placeholder = "e.g., SQK-LSK109")
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

              hr(),
              h3(icon("upload"), " Input Files"),

              # FASTQ: file or directory browse
              conditionalPanel(
                condition = sprintf("input['%s'] == 'fastq'", ns("input_format")),
                div(
                  class = "mb-3",
                  tags$label(class = "form-label", "FASTQ File or Directory"),
                  div(
                    class = "input-group mb-2",
                    tags$input(type = "text", class = "form-control",
                      id = ns("input_path_display"),
                      placeholder = "Click to browse for file or directory",
                      readonly = "readonly"),
                    div(class = "input-group-append",
                      shinyFilesButton(ns("input_file_browse"), "File",
                        "Select FASTQ file", multiple = FALSE,
                        class = "btn btn-outline-secondary"),
                      shinyDirButton(ns("input_dir_browse"), "Dir",
                        "Select FASTQ directory",
                        class = "btn btn-outline-secondary")
                    )
                  ),
                  tags$small(class = "text-muted", "FASTQ, FQ (.gz supported)"),
                  div(style = "display: none;", textInput(ns("input_path"), NULL, value = ""))
                )
              ),

              # FAST5 / POD5: directory only
              conditionalPanel(
                condition = sprintf("input['%s'] == 'fast5' || input['%s'] == 'pod5'", ns("input_format"), ns("input_format")),
                div(
                  class = "mb-3",
                  tags$label(class = "form-label", "FAST5/POD5 Directory"),
                  div(
                    class = "input-group mb-2",
                    tags$input(type = "text", class = "form-control",
                      id = ns("input_path_display"),
                      placeholder = "Click to browse for FAST5/POD5 directory",
                      readonly = "readonly"),
                    div(class = "input-group-append",
                      shinyDirButton(ns("input_dir_browse"), "Browse",
                        "Select FAST5/POD5 directory",
                        class = "btn btn-primary")
                    )
                  ),
                  tags$small(class = "text-muted", "Select the directory containing FAST5 or POD5 files."),
                  div(style = "display: none;", textInput(ns("input_path"), NULL, value = ""))
                )
              ),

              # Dorado config (FAST5/POD5 only)
              conditionalPanel(
                condition = sprintf("input['%s'] == 'fast5' || input['%s'] == 'pod5'", ns("input_format"), ns("input_format")),
                hr(),
                h3("Basecalling Configuration (Dorado)"),
                div(
                  class = "alert alert-info", role = "alert", style = "font-size: 0.875rem;",
                  icon("info-circle"), " Paths are auto-detected if Dorado was installed via Setup Wizard."
                ),
                div(
                  class = "row",
                  div(
                    class = "col-md-6 mb-3",
                    tags$label(class = "form-label", "Dorado Binary Path (optional)"),
                    div(
                      class = "input-group mb-2",
                      tags$input(type = "text", class = "form-control",
                        id = ns("dorado_bin_display"),
                        placeholder = "Auto-detected if installed via wizard",
                        readonly = "readonly"),
                      div(class = "input-group-append",
                        shinyFilesButton(ns("dorado_bin_browse"), "Browse",
                          "Select Dorado binary", multiple = FALSE,
                          class = "btn btn-outline-secondary")
                      )
                    ),
                    div(style = "display: none;", textInput(ns("dorado_bin"), NULL, value = ""))
                  ),
                  div(
                    class = "col-md-6 mb-3",
                    tags$label(class = "form-label", "Dorado Models Directory (optional)"),
                    div(
                      class = "input-group mb-2",
                      tags$input(type = "text", class = "form-control",
                        id = ns("dorado_models_dir_display"),
                        placeholder = "Auto-detected if installed via wizard",
                        readonly = "readonly"),
                      div(class = "input-group-append",
                        shinyDirButton(ns("dorado_models_dir_browse"), "Browse",
                          "Select Dorado models directory",
                          class = "btn btn-outline-secondary")
                      )
                    ),
                    div(style = "display: none;", textInput(ns("dorado_models_dir"), NULL, value = ""))
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

          # ── Processing Parameters ────────────────────────────────
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
                sliderInput(ns("quality_threshold"), NULL, min = 0, max = 20, value = 7, step = 1),
                tags$small(class = "text-muted", "0 (Low) → 20 (High)")
              ),
              div(
                class = "mb-4",
                tags$label(class = "form-label",
                  tags$span("Minimum Read Length: "),
                  tags$span(class = "text-primary", textOutput(ns("min_read_length_display"), inline = TRUE), " bp")
                ),
                sliderInput(ns("min_read_length"), NULL, min = 500, max = 10000, value = 1000, step = 500),
                tags$small(class = "text-muted", "500 bp → 10 kb")
              ),
              div(
                class = "row",
                div(
                  class = "col-md-6 mb-3",
                  checkboxInput(ns("trim_adapter"), "Trim Adapter Sequences", value = TRUE)
                ),
                div(
                  class = "col-md-6 mb-3",
                  checkboxInput(ns("demultiplex"), "Demultiplex", value = FALSE)
                )
              ),
              div(
                class = "mb-3",
                tags$label(class = "form-label", "Primer Sequences"),
                textAreaInput(ns("primer_sequences"), NULL,
                  placeholder = "Enter primer sequences (one per line)",
                  rows = 2, value = ""),
                tags$small(class = "text-muted", "Optional. Leave empty to skip primer trimming.")
              ),
              div(
                class = "mb-3",
                tags$label(class = "form-label", "Barcode Sequences"),
                textAreaInput(ns("barcode_sequences"), NULL,
                  placeholder = "Enter barcode sequences (one per line)",
                  rows = 2, value = ""),
                tags$small(class = "text-muted", "Optional. Used for demultiplexing.")
              ),
              # FASTQ-only kit fields (optional when fastq)
              conditionalPanel(
                condition = sprintf("input['%s'] == 'fastq'", ns("input_format")),
                div(
                  class = "row",
                  div(
                    class = "col-md-6 mb-3",
                    tags$label(class = "form-label", "Barcoding Kit (Optional)"),
                    textInput(ns("barcoding_kit_proc"), NULL, placeholder = "e.g., SQK-RBK004")
                  ),
                  div(
                    class = "col-md-6 mb-3",
                    tags$label(class = "form-label", "Ligation Kit (Optional)"),
                    textInput(ns("ligation_kit_proc"), NULL, placeholder = "e.g., SQK-LSK109")
                  )
                )
              ),
              div(
                class = "mb-3",
                tags$label(class = "form-label", "Number of Threads"),
                numericInput(ns("threads"), NULL, value = 4, min = 1, max = 32)
              )
            )
          ),

          # ── Analysis Configuration ───────────────────────────────
          div(
            class = "card mb-4",
            div(
              class = "card-body",
              h2("Analysis Configuration"),
              div(
                class = "row",
                div(
                  class = "col-md-6 mb-3",
                  tags$label(class = "form-label", "Sequencing Approach"),
                  selectInput(ns("pipeline"), NULL,
                    choices = c("16S rRNA Sequencing (Emu)" = "lr_amp", "Metagenomics" = "lr_meta"),
                    selected = "lr_amp"
                  )
                ),
                div(
                  class = "col-md-6 mb-3",
                  tags$label(class = "form-label", "Sample Type"),
                  selectInput(ns("sample_type"), NULL,
                    choices = c("Vaginal" = "vaginal", "Gut" = "gut", "Oral" = "oral", "Skin" = "skin", "Other" = "other"),
                    selected = "vaginal"
                  )
                ),
                div(
                  class = "col-md-6 mb-3",
                  tags$label(class = "form-label", "Run Scope"),
                  selectInput(ns("run_scope"), NULL,
                    choices = c("Full Pipeline" = "full", "QC Only" = "qc"),
                    selected = "full"
                  )
                ),
                conditionalPanel(
                  condition = sprintf("input['%s'] == 'vaginal'", ns("sample_type")),
                  div(
                    class = "col-md-6 mb-3",
                    tags$label(class = "form-label", "VALENCIA Classification"),
                    selectInput(ns("valencia"), NULL,
                      choices = c("Yes" = "yes", "No" = "no"), selected = "yes")
                  )
                ),
                # lr_meta: Kraken2 DB + Human depletion
                conditionalPanel(
                  condition = sprintf("input['%s'] == 'lr_meta'", ns("pipeline")),
                  div(
                    class = "col-md-12 mb-3",
                    tags$label(class = "form-label", "Kraken2 Database Path"),
                    div(
                      class = "input-group mb-2",
                      tags$input(type = "text", class = "form-control",
                        id = ns("kraken_db_display"),
                        placeholder = "Click to browse for Kraken2 database directory",
                        readonly = "readonly"),
                      div(class = "input-group-append",
                        shinyDirButton(ns("kraken_db_browse"), "Browse",
                          "Select Kraken2 database directory",
                          class = "btn btn-outline-secondary")
                      )
                    ),
                    div(style = "display: none;", textInput(ns("kraken_db"), NULL, value = ""))
                  ),
                  div(
                    class = "col-md-12 mb-3",
                    checkboxInput(ns("human_depletion"), "Human Read Depletion", value = FALSE),
                    tags$small(class = "text-muted", "Remove human-derived sequences from the dataset")
                  )
                ),
                # Output Types
                div(
                  class = "col-md-12 mb-3",
                  tags$h4("Output Types"),
                  div(
                    class = "row",
                    div(class = "col-md-6",
                      checkboxInput(ns("output_raw_csv"), "Raw Data (.csv)", value = TRUE)),
                    div(class = "col-md-6",
                      checkboxInput(ns("output_pie_chart"), "Pie Chart", value = FALSE)),
                    div(class = "col-md-6",
                      checkboxInput(ns("output_heatmap"), "Heatmap", value = FALSE)),
                    div(class = "col-md-6",
                      checkboxInput(ns("output_stacked_bar"), "Stacked Bar Chart", value = FALSE)),
                    div(class = "col-md-6",
                      checkboxInput(ns("output_quality_reports"), "Quality Reports", value = FALSE))
                  )
                )
              )
            )
          )
        ),

        # Right column — summary
        div(
          class = "col-lg-4",
          div(
            class = "summary-panel",
            h2("Run Configuration"),
            div(class = "summary-item",
              p(class = "text-muted mb-1", style = "font-size: 0.875rem;", "Technology"),
              p(style = "margin: 0;", textOutput(ns("summary_technology")))
            ),
            div(class = "summary-item",
              p(class = "text-muted mb-1", style = "font-size: 0.875rem;", "Approach"),
              p(style = "margin: 0;", textOutput(ns("summary_pipeline")))
            ),
            div(class = "summary-item",
              p(class = "text-muted mb-1", style = "font-size: 0.875rem;", "Input Format"),
              p(style = "margin: 0;", textOutput(ns("summary_format")))
            ),
            div(class = "summary-item",
              p(class = "text-muted mb-1", style = "font-size: 0.875rem;", "Sample Type"),
              p(style = "margin: 0;", textOutput(ns("summary_sample_type")))
            ),
            div(class = "summary-item",
              p(class = "text-muted mb-1", style = "font-size: 0.875rem;", "Run Scope"),
              p(style = "margin: 0;", textOutput(ns("summary_run_scope")))
            ),
            conditionalPanel(
              condition = sprintf("input['%s'] == 'vaginal'", ns("sample_type")),
              div(class = "alert alert-info",
                icon("info-circle"), " VALENCIA classification will be performed")
            ),
            uiOutput(ns("validation_messages")),
            hr(),
            actionButton(ns("run_pipeline"), "Run Pipeline",
              icon = icon("play"), class = "btn btn-primary w-100 mb-2"),
            actionButton(ns("dry_run"), "Preview Configuration",
              icon = icon("eye"), class = "btn btn-outline-secondary w-100")
          )
        )
      )
    )
  )
}

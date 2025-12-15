library(shiny)
library(bslib)

options(shiny.maxRequestSize = 5 * 1024^3) # 5GB upload limit

stamp_config_defaults <- list(
  input_type = "fastq",
  sample_type = "vaginal",
  run_id = "run_001",
  output_dir = "/path/to/output",
  prep_profile = "alt_fastq_prep",
  barcode_kit = "",
  min_qscore = 10,
  valencia_enabled = "auto",
  output_styles = c("stacked_bar", "raw_csv"),
  run_scope = "full",
  
  # NEW defaults (2x2 options live here)
  sequencing_approach = "shotgun",  # shotgun | amplicon
  read_technology = "long",         # long | short
  platform = "nanopore",            # nanopore | pacbio | illumina
  marker = "16S"                    # only used when amplicon
)

ui <- page_fluid(
  theme = bs_theme(
    version = 5,
    primary = "#2D89C8"
  ),
  
  tags$style(HTML("
    .sidebar h4, .sidebar h5 {
      margin-bottom: 0.2rem !important;
    }
    .sidebar p {
      margin-bottom: 0.35rem !important;
    }
    .sidebar .control-label {
      margin-bottom: 0.15rem !important;
    }
    .sidebar .shiny-input-container {
      margin-bottom: 0.4rem !important;
    }
    .sidebar #sample_files,
    .sidebar #sample_dir,
    .sidebar #run_label,
    .sidebar #output_dir,
    .sidebar #sequencing_approach,
    .sidebar #input_type,
    .sidebar #sample_type,
    .sidebar #prep_profile,
    .sidebar #barcode_kit,
    .sidebar #min_qscore,
    .sidebar #valencia_enabled,
    .sidebar #output_styles,
    .sidebar #run_scope {
      margin-bottom: 0.25rem !important;
    }
    .sidebar hr {
      margin-top: 0.35rem !important;
      margin-bottom: 0.45rem !important;
    }
    .stamp-inputs-block {
      margin-bottom: 0.2rem;
    }

    .bslib-sidebar h4, .bslib-sidebar h5 {
      margin-bottom: 0.2rem !important;
    }
    .bslib-sidebar p {
      margin-bottom: 0.35rem !important;
    }
    .bslib-sidebar .control-label {
      margin-bottom: 0.15rem !important;
    }
    .bslib-sidebar .shiny-input-container {
      margin-bottom: 0.4rem !important;
    }
    .bslib-sidebar #sample_files,
    .bslib-sidebar #sample_dir,
    .bslib-sidebar #run_label,
    .bslib-sidebar #output_dir,
    .bslib-sidebar #sequencing_approach,
    .bslib-sidebar #input_type,
    .bslib-sidebar #sample_type,
    .bslib-sidebar #prep_profile,
    .bslib-sidebar #barcode_kit,
    .bslib-sidebar #min_qscore,
    .bslib-sidebar #valencia_enabled,
    .bslib-sidebar #output_styles,
    .bslib-sidebar #run_scope {
      margin-bottom: 0.25rem !important;
    }
    .bslib-sidebar hr {
      margin-top: 0.35rem !important;
      margin-bottom: 0.45rem !important;
    }

    .stamp-hero {
      padding: 0.25rem 0 0.5rem 0;
    }
    .stamp-hero h1 {
      margin-bottom: 0.25rem;
    }

    .stamp-section-title {
      margin-top: 0.15rem;
    }

    .stamp-run-bar {
      display: flex;
      align-items: center;
      justify-content: flex-end;
      gap: 0.5rem;
      padding: 0.25rem 0 0.5rem 0;
    }
    .stamp-run-bar .btn {
      min-width: 160px;
    }

    .stamp-subtle {
      color: rgba(255,255,255,0.75);
    }

    @media (max-width: 991px) {
      .stamp-run-bar {
        justify-content: flex-start;
      }
      .stamp-run-bar .btn {
        width: 100%;
      }
    }
  ")),
  
  layout_sidebar(
    fill = FALSE,  # ✅ prevents the “box” when adding more inputs
    
    sidebar = sidebar(
      h4("Inputs"),
      p("Add files for a new run."),
      
      div(
        class = "stamp-inputs-block",
        
        fileInput(
          inputId = "sample_files",
          label = "Select files",
          multiple = TRUE,
          accept = c(
            ".fastq", ".fq", ".fastq.gz", ".fq.gz",
            ".fast5",
            ".tsv", ".csv", ".txt",
            ".json", ".yaml", ".yml"
          )
        ),
        
        fileInput(
          inputId = "sample_dir",
          label = "Select a folder (Chrome/Edge recommended)",
          multiple = TRUE,
          accept = c(
            ".fastq", ".fq", ".fastq.gz", ".fq.gz",
            ".fast5",
            ".tsv", ".csv", ".txt",
            ".json", ".yaml", ".yml"
          )
        )
      ),
      
      tags$script(HTML("
        (function() {
          function enableDir() {
            var el = document.getElementById('sample_dir');
            if (el) {
              el.setAttribute('webkitdirectory', '');
              el.setAttribute('directory', '');
              el.setAttribute('multiple', '');
            }
          }
          document.addEventListener('DOMContentLoaded', enableDir);
          setTimeout(enableDir, 250);
          setTimeout(enableDir, 1000);
        })();
      ")),
      
      hr(),
      
      h5("Run configuration"),
      p("Set analysis mode and preprocessing options for this run."),
      
      # NEW (step 1 only)
      selectInput(
        inputId = "sequencing_approach",
        label = "Sequencing approach",
        choices = c(
          "Shotgun metagenomics" = "shotgun",
          "Amplicon sequencing" = "amplicon"
        ),
        selected = stamp_config_defaults$sequencing_approach
      ),
      
      selectInput(
        inputId = "input_type",
        label = "Input type",
        choices = c("fastq", "fast5"),
        selected = stamp_config_defaults$input_type
      ),
      
      selectInput(
        inputId = "sample_type",
        label = "Sample type",
        choices = c("skin", "oral", "gut", "vaginal"),
        selected = stamp_config_defaults$sample_type
      ),
      
      textInput(
        inputId = "run_label",
        label = "Run ID",
        value = stamp_config_defaults$run_id,
        placeholder = "e.g., run_001 or 2025-12-09_gut_batch1"
      ),
      
      textInput(
        inputId = "output_dir",
        label = "Output directory",
        value = stamp_config_defaults$output_dir,
        placeholder = "/path/to/output"
      ),
      
      selectInput(
        inputId = "run_scope",
        label = "Run scope",
        choices = c(
          "Run full pipeline and gather all results" = "full",
          "QC only (FastQC raw + post-processing)" = "qc_only"
        ),
        selected = stamp_config_defaults$run_scope
      ),
      
      hr(),
      
      h5("Preprocessing"),
      p("Adjust only if you need to override the preset behaviour."),
      
      selectInput(
        inputId = "prep_profile",
        label = "Prep profile",
        choices = c("dorado", "alt_fastq_prep"),
        selected = stamp_config_defaults$prep_profile
      ),
      
      textInput(
        inputId = "barcode_kit",
        label = "Barcode kit (optional)",
        value = stamp_config_defaults$barcode_kit,
        placeholder = "e.g., SQK-RBK114.24"
      ),
      
      numericInput(
        inputId = "min_qscore",
        label = "Minimum Q-score",
        value = stamp_config_defaults$min_qscore,
        min = 0,
        step = 1
      ),
      
      hr(),
      
      h5("Classification"),
      p("Vaginal CST classification can be enabled automatically when relevant."),
      
      selectInput(
        inputId = "valencia_enabled",
        label = "VALENCIA",
        choices = c("auto", "true", "false"),
        selected = stamp_config_defaults$valencia_enabled
      ),
      
      hr(),
      
      h5("Output style"),
      p("Choose one or more outputs to generate for this run."),
      
      selectInput(
        inputId = "output_styles",
        label = "Outputs",
        choices = c(
          "Heatmap" = "heatmap",
          "Stacked bar chart" = "stacked_bar",
          "Pie chart" = "pie_chart",
          "Raw data .csv file" = "raw_csv"
        ),
        selected = stamp_config_defaults$output_styles,
        multiple = TRUE
      ),
      
      width = 320
    ),
    
    div(
      class = "stamp-hero",
      h1("STaBioM"),
      p(
        "STaBioM – Standardised Bioinformatics for Microbial samples ",
        "is a lightweight interface for preparing microbial sequencing runs. ",
        "Upload sequencing inputs, choose your run configuration, review the files received, ",
        "then run your local workflow."
      )
    ),
    
    h4("Uploaded files", class = "stamp-section-title"),
    p(
      "Files are held in a temporary session location after upload. ",
      "Review names and sizes, remove anything incorrect, then run. ",
      "Sizes are shown in MB."
    ),
    
    uiOutput("upload_table"),
    
    div(
      class = "stamp-run-bar",
      actionButton("run_pipeline", "Run analysis", class = "btn-primary")
    ),
    
    hr(),
    
    h4("Validation messages", class = "stamp-section-title"),
    p("This panel displays messages emitted by the run script."),
    verbatimTextOutput("upload_messages")
  )
)


pipeline_modal_ui <- function(run_id, pipeline, config_json, session) {
  ns <- session$ns

  modalDialog(
    title = NULL,
    size = "xl",
    easyClose = FALSE,
    footer = NULL,

    # Make it full screen
    tags$style(HTML("
      .modal-dialog {
        max-width: 100% !important;
        width: 100% !important;
        height: 100vh !important;
        margin: 0 !important;
      }
      .modal-content {
        height: 100vh !important;
        border-radius: 0 !important;
      }
      #pipeline_modal-pipeline_log_stream {
        background: #000000;
        color: #888888;
        font-family: 'SF Mono', 'Monaco', 'Consolas', monospace;
        font-size: 0.875rem;
        line-height: 1.5;
        white-space: pre-wrap;
        word-wrap: break-word;
        margin: 0;
        padding: 1rem;
        border: none;
        overflow-y: auto;
        height: 450px;
      }
      .log-scroll-container {
        height: 450px;
        overflow-y: auto;
        background: #000000;
        padding: 0;
        border-radius: 0.5rem;
        border: 1px solid #1e293b;
      }
    ")),

    tags$script(HTML("
      Shiny.addCustomMessageHandler('scrollLogs', function(id) {
        var el = document.getElementById(id);
        if (el) {
          el.scrollTop = el.scrollHeight;
        }
      });
    ")),

    div(
      class = "container-fluid",
      style = "padding: 0;",

      # Status header
      div(
        class = "p-3",
        style = "background: #f8fafc; border-bottom: 2px solid #e2e8f0;",
        div(
          class = "d-flex justify-content-between align-items-center",
          div(
            h3(class = "mb-0", style = "font-weight: 700;",
               icon("flask"), " ", pipeline),
            tags$small(class = "text-muted", paste("Run ID:", run_id))
          ),
          div(
            uiOutput(ns("modal_status_badge"))
          )
        ),
        div(
          class = "mt-2 d-flex gap-3",
          div(
            tags$small(class = "text-muted", "Elapsed Time:"),
            tags$strong(textOutput(ns("elapsed_time"), inline = TRUE))
          )
        )
      ),

      # Main content
      div(
        class = "row g-0",
        style = "height: 70vh;",

        # Left sidebar - Configuration
        div(
          class = "col-md-4",
          style = "border-right: 1px solid #e2e8f0; background: #fafafa; overflow-y: auto; padding: 1.5rem;",
          h5(icon("gear"), " Configuration"),
          tags$pre(
            style = "background: white; padding: 1rem; border-radius: 0.5rem; border: 1px solid #e2e8f0; font-size: 0.75rem; max-height: calc(70vh - 100px); overflow-y: auto;",
            config_json
          )
        ),

        # Right side - Continuous log stream
        div(
          class = "col-md-8",
          style = "display: flex; flex-direction: column; padding: 1.5rem;",
          div(
            class = "mb-3",
            div(
              class = "d-flex justify-content-between align-items-center",
              h5(class = "mb-0", icon("terminal"), " Pipeline Logs"),
              div(
                style = "display: inline-block;",
                checkboxInput(ns("auto_scroll"), "Auto-scroll", value = TRUE)
              )
            )
          ),

          # Single continuous log stream
          div(
            class = "log-scroll-container",
            id = ns("log_container"),
            uiOutput(ns("pipeline_log_stream"))
          )
        )
      ),

      # Footer with actions
      div(
        class = "p-3",
        style = "background: #f8fafc; border-top: 2px solid #e2e8f0;",
        div(
          class = "d-flex justify-content-between",
          actionButton(ns("return_dashboard"), "Return to Dashboard",
                      icon = icon("home"),
                      class = "btn btn-outline-secondary"),
          actionButton(ns("cancel_run"), "Cancel Run",
                      icon = icon("stop"),
                      class = "btn btn-danger")
        )
      )
    )
  )
}

# STaBioM Shiny Frontend
# A graphical interface for the STaBioM CLI tool
# This is a pure UI wrapper - all logic is delegated to the existing CLI

# Auto-install missing packages
source("check_and_install_packages.R", local = TRUE)

library(shiny)
library(bslib)
library(jsonlite)
library(shinyjs)
library(shinydashboard)
library(shinyFiles)
library(fs)
library(processx)

# Source UI modules
source("ui/dashboard_ui.R")
source("ui/short_read_ui.R")
source("ui/long_read_ui.R")
source("ui/compare_ui.R")
source("ui/pipeline_modal_ui.R")
source("ui/setup_wizard_ui.R")

# Source server modules
source("server/dashboard_server.R")
source("server/short_read_server.R")
source("server/long_read_server.R")
source("server/compare_server.R")
source("server/pipeline_modal_server.R")
source("server/setup_wizard_server.R")

# Source utilities
source("utils/cli_interface.R")
source("utils/config_generator.R")
source("utils/log_streamer.R")
source("utils/log_discovery.R")

# Define UI
ui <- page_navbar(
  title = "STaBioM",
  id = "main_nav",
  theme = bs_theme(
    version = 5,
    bg = "#f8fafc",
    fg = "#0f172a",
    primary = "#3b82f6",
    secondary = "#64748b",
    success = "#10b981",
    danger = "#ef4444",
    warning = "#f59e0b",
    info = "#3b82f6",
    base_font = font_google("Inter"),
    heading_font = font_google("Inter"),
    font_scale = 0.95
  ),
  header = tags$head(
    tags$style(HTML("
      /* Global Styles */
      body {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Helvetica', 'Arial', sans-serif;
        background: #f8fafc;
        color: #1e293b;
      }

      /* Navigation */
      .navbar {
        background: linear-gradient(135deg, #1e293b 0%, #334155 100%) !important;
        border-bottom: 1px solid #475569;
        box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
      }
      .navbar-brand {
        color: white !important;
        font-weight: 700;
        font-size: 1.5rem;
        letter-spacing: -0.025em;
      }
      .nav-link {
        color: #cbd5e1 !important;
        font-weight: 500;
        transition: all 0.2s;
        padding: 0.5rem 1rem !important;
        border-radius: 0.375rem;
        margin: 0 0.25rem;
      }
      .nav-link:hover {
        color: white !important;
        background: rgba(255, 255, 255, 0.1);
      }
      .nav-link.active {
        color: white !important;
        background: rgba(255, 255, 255, 0.15);
      }

      /* Cards */
      .card {
        background: white;
        border: 1px solid #e2e8f0;
        border-radius: 0.75rem;
        box-shadow: 0 1px 3px 0 rgba(0, 0, 0, 0.1), 0 1px 2px 0 rgba(0, 0, 0, 0.06);
        transition: all 0.2s;
      }
      .card:hover {
        box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
      }
      .card-body {
        padding: 1.5rem;
      }

      /* Stat Cards */
      .stat-card {
        background: white;
        padding: 1.5rem;
        border-radius: 0.75rem;
        border: 1px solid #e2e8f0;
        box-shadow: 0 1px 3px 0 rgba(0, 0, 0, 0.1);
        transition: all 0.2s;
      }
      .stat-card:hover {
        box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
        transform: translateY(-2px);
      }

      /* Terminal Output */
      .terminal-output {
        background: #0f172a;
        color: #e2e8f0;
        font-family: 'SF Mono', 'Monaco', 'Inconsolata', 'Fira Code', 'Consolas', monospace;
        padding: 1.25rem;
        border-radius: 0.5rem;
        overflow-y: auto;
        max-height: 600px;
        white-space: pre-wrap;
        font-size: 0.875rem;
        line-height: 1.5;
        border: 1px solid #1e293b;
      }
      .log-error { color: #f87171; font-weight: 500; }
      .log-warning { color: #fbbf24; }
      .log-success { color: #4ade80; font-weight: 500; }
      .log-info { color: #60a5fa; }

      /* Summary Panel */
      .summary-panel {
        position: sticky;
        top: 1.5rem;
        background: white;
        border: 1px solid #e2e8f0;
        border-radius: 0.75rem;
        padding: 1.5rem;
        box-shadow: 0 1px 3px 0 rgba(0, 0, 0, 0.1);
      }
      .summary-item {
        padding: 1rem;
        background: #f8fafc;
        border: 1px solid #e2e8f0;
        border-radius: 0.5rem;
        margin-bottom: 0.75rem;
        transition: all 0.2s;
      }
      .summary-item:hover {
        background: #f1f5f9;
      }

      /* Forms */
      .form-label {
        color: #1e293b;
        font-weight: 600;
        margin-bottom: 0.5rem;
        font-size: 0.875rem;
        letter-spacing: 0.025em;
      }
      .form-control, .form-select {
        border: 1px solid #cbd5e1;
        border-radius: 0.5rem;
        padding: 0.625rem 0.875rem;
        transition: all 0.2s;
        font-size: 0.9375rem;
      }
      .form-control:focus, .form-select:focus {
        border-color: #3b82f6;
        box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
        outline: none;
      }

      /* Buttons */
      .btn {
        font-weight: 600;
        padding: 0.625rem 1.25rem;
        border-radius: 0.5rem;
        transition: all 0.2s;
        border: none;
      }
      .btn-primary {
        background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%);
        color: white;
        box-shadow: 0 1px 3px 0 rgba(0, 0, 0, 0.1);
      }
      .btn-primary:hover {
        background: linear-gradient(135deg, #2563eb 0%, #1d4ed8 100%);
        box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
        transform: translateY(-1px);
      }
      .btn-outline-secondary {
        border: 1px solid #cbd5e1;
        color: #475569;
        background: white;
      }
      .btn-outline-secondary:hover {
        background: #f8fafc;
        border-color: #94a3b8;
      }
      .btn-danger {
        background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%);
        color: white;
      }

      /* Typography */
      h1 {
        color: #0f172a;
        font-size: 2rem;
        font-weight: 700;
        margin-bottom: 0.5rem;
        letter-spacing: -0.025em;
      }
      h2 {
        color: #1e293b;
        font-size: 1.5rem;
        font-weight: 700;
        margin-bottom: 1rem;
        letter-spacing: -0.025em;
      }
      h3 {
        color: #334155;
        font-size: 1.125rem;
        font-weight: 600;
      }
      .text-muted {
        color: #64748b;
      }

      /* Tables */
      table {
        background: white;
      }
      thead {
        background: #f8fafc;
        border-bottom: 2px solid #e2e8f0;
      }
      th {
        color: #475569;
        font-weight: 600;
        font-size: 0.875rem;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        padding: 0.75rem 1rem !important;
      }
      td {
        padding: 0.75rem 1rem !important;
        border-bottom: 1px solid #f1f5f9;
      }
      tr:hover {
        background: #f8fafc;
      }

      /* Badges */
      .badge {
        padding: 0.375rem 0.75rem;
        font-weight: 600;
        border-radius: 0.375rem;
        font-size: 0.875rem;
      }

      /* Alerts */
      .alert {
        border-radius: 0.5rem;
        border: none;
        padding: 1rem;
        margin-bottom: 1rem;
      }
      .alert-success {
        background: #dcfce7;
        color: #166534;
      }
      .alert-danger {
        background: #fee2e2;
        color: #991b1b;
      }
      .alert-warning {
        background: #fef3c7;
        color: #92400e;
      }
      .alert-info {
        background: #dbeafe;
        color: #1e40af;
      }

      /* Validation */
      .validation-required {
        border-left: 3px solid #ef4444;
      }
      .validation-valid {
        border-left: 3px solid #10b981;
      }

      /* Misc */
      hr {
        border-color: #e2e8f0;
        opacity: 1;
      }
    "))
  ),
  useShinyjs(),

  # Navigation panels
  nav_panel(
    title = "Dashboard",
    icon = icon("home"),
    dashboard_ui("dashboard")
  ),
  nav_panel(
    title = "Short Read",
    icon = icon("dna"),
    short_read_ui("short_read")
  ),
  nav_panel(
    title = "Long Read",
    icon = icon("magnifying-glass-chart"),
    long_read_ui("long_read")
  ),
  nav_panel(
    title = "Compare",
    icon = icon("code-compare"),
    compare_ui("compare")
  ),
  nav_panel(
    title = "Setup Wizard",
    icon = icon("wand-magic-sparkles"),
    setup_wizard_ui("setup_wizard")
  )
)

# Define server
server <- function(input, output, session) {

  # Shared reactive values
  shared <- reactiveValues(
    current_run = NULL,
    run_status = "idle",
    setup_complete = file.exists(file.path(dirname(getwd()), ".setup_complete")),
    goto_page = NULL
  )

  # Module servers
  dashboard_server("dashboard", shared)
  short_read_server("short_read", shared)
  long_read_server("long_read", shared)
  compare_server("compare", shared)
  pipeline_modal_server("pipeline_modal", shared)
  setup_wizard_server("setup_wizard", shared)

  # Check if setup is complete on startup
  observe({
    if (!shared$setup_complete) {
      showModal(modalDialog(
        title = "Welcome to STaBioM",
        "It looks like this is your first time using STaBioM. Please complete the Setup Wizard before running pipelines.",
        footer = tagList(
          modalButton("Cancel"),
          actionButton("goto_setup", "Go to Setup Wizard", class = "btn-primary")
        ),
        easyClose = FALSE
      ))
    }
  })

  observeEvent(input$goto_setup, {
    removeModal()
    updateNavbarPage(session, "main_nav", "Setup Wizard")
  })

  # Handle page navigation from modules
  observeEvent(shared$goto_page, {
    cat("[DEBUG app.R] goto_page changed to:", shared$goto_page, "\n")
    if (!is.null(shared$goto_page)) {
      cat("[DEBUG app.R] Navigating to:", shared$goto_page, "\n")
      updateNavbarPage(session, "main_nav", shared$goto_page)
      shared$goto_page <- NULL
    }
  })
}

# Run the app with auto-launch
options(shiny.launch.browser = TRUE)
shinyApp(ui = ui, server = server)

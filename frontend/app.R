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
source("utils/wizard_defs.R")
source("utils/ui_prefs.R")

# Determine whether wizard overlay should start hidden
# (file.exists evaluated at UI-build time — before server starts)
.wizard_init_hidden <- file.exists(
  file.path(dirname(getwd()), ".setup_complete")
)

# Define UI
ui <- page_navbar(
  title = "STaBioM",
  id = "main_nav",
  theme = bs_theme(
    version = 5,
    bg = "#f9fafb",
    fg = "#111827",
    primary = "#2563eb",
    secondary = "#64748b",
    success = "#10b981",
    danger = "#d4183d",
    warning = "#f59e0b",
    info = "#2563eb",
    font_scale = 0.95
  ),
  # The wizard overlay lives here — always in DOM, shown/hidden via shinyjs.
  # position:fixed + z-index:9999 covers the entire viewport (including navbar).
  header = tagList(
    div(
      id    = "setup-wizard-overlay",
      style = if (.wizard_init_hidden) "display:none;" else "",
      setup_wizard_ui("setup_wizard")
    ),
  tags$head(
    tags$style(HTML("
      /* Global Styles */
      body {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Helvetica Neue', Arial, sans-serif;
        background: #f9fafb;
        color: #111827;
        font-size: 0.9375rem;
        line-height: 1.5;
        -webkit-font-smoothing: antialiased;
        -moz-osx-font-smoothing: grayscale;
      }
      /* Apply same system-font stack to headings so they match body */
      h1, h2, h3, h4, h5, h6,
      .navbar-brand, .form-label, label, button, .btn {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Helvetica Neue', Arial, sans-serif;
      }

      /* Navigation */
      .navbar {
        background: #ffffff !important;
        border-bottom: 1px solid #e5e7eb;
        box-shadow: 0 1px 3px 0 rgba(0, 0, 0, 0.05);
      }
      .navbar-brand {
        color: #111827 !important;
        font-weight: 700;
        font-size: 1.5rem;
        letter-spacing: -0.025em;
      }
      .nav-link {
        color: #4b5563 !important;
        font-weight: 500;
        transition: color 0.2s, border-color 0.2s;
        padding: 0.75rem 1rem !important;
        border-bottom: 2px solid transparent;
        border-radius: 0;
        margin: 0;
      }
      .nav-link:hover {
        color: #111827 !important;
        background: transparent;
        border-bottom-color: #d1d5db;
      }
      .nav-link.active {
        color: #2563eb !important;
        background: transparent;
        border-bottom-color: #2563eb;
      }

      /* Cards */
      .card {
        background: white;
        border: 1px solid #e5e7eb;
        border-radius: 0.75rem;
        box-shadow: 0 1px 3px 0 rgba(0, 0, 0, 0.07);
        transition: box-shadow 0.2s;
      }
      .card:hover {
        box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
      }
      .card-body {
        padding: 1.5rem;
      }

      /* Stat Cards */
      .stat-card {
        background: white;
        padding: 1.5rem;
        border-radius: 0.75rem;
        border: 1px solid #e5e7eb;
        box-shadow: 0 1px 3px 0 rgba(0, 0, 0, 0.07);
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
        border: 1px solid #e5e7eb;
        border-radius: 0.75rem;
        padding: 1.5rem;
        box-shadow: 0 1px 3px 0 rgba(0, 0, 0, 0.07);
      }
      .summary-item {
        padding: 0.75rem;
        background: #f9fafb;
        border: 1px solid #e5e7eb;
        border-radius: 0.5rem;
        margin-bottom: 0.75rem;
        transition: background 0.2s;
      }
      .summary-item:hover {
        background: #f3f4f6;
      }

      /* Input container normalisation — remove Shiny default bottom margin so
         col-md-6 pairs align evenly; spacing is handled by the mb-3 wrappers in R */
      .shiny-input-container {
        width: 100% !important;
        margin-bottom: 0 !important;
      }

      /* conditionalPanel fix — Shiny wraps conditional content in a plain div
         that becomes a full-width flex item inside Bootstrap .row, breaking the
         grid. display:contents makes the wrapper invisible to layout so its
         col-md-* children participate directly in the flex row.
         When Shiny hides the panel it sets inline display:none which has
         higher specificity than this rule and correctly takes over. */
      .row > .shiny-panel-conditional {
        display: contents;
      }
      /* CSS selectors are structural, not visual. After display:contents the
         col-md-* grandchildren participate in the flex row visually but
         Bootstrap's .row > * rule (which adds gutter padding) no longer matches
         them because they are still structurally grandchildren, not direct
         children. Restore those missing gutter styles so every column — including
         VALENCIA — has identical padding to its siblings. */
      .row > .shiny-panel-conditional > * {
        flex-shrink: 0;
        max-width: 100%;
        padding-right: calc(var(--bs-gutter-x, 1.5rem) * 0.5);
        padding-left: calc(var(--bs-gutter-x, 1.5rem) * 0.5);
        margin-top: var(--bs-gutter-y, 0);
      }
      /* number inputs — hide browser spinners so height matches text inputs */
      input[type='number']::-webkit-inner-spin-button,
      input[type='number']::-webkit-outer-spin-button {
        -webkit-appearance: none;
        margin: 0;
      }
      input[type='number'] {
        -moz-appearance: textfield;
      }

      /* Forms — demo: block text-gray-700 mb-2 / w-full px-3 py-2 border border-gray-300 rounded-md */
      .form-label {
        color: #374151;
        font-weight: 500;
        margin-bottom: 0.375rem;
        font-size: 0.875rem;
        display: block;
      }

      /* Single source of truth for every input/select/textarea box */
      .form-control,
      .form-select,
      input[type='text'],
      input[type='number'],
      input[type='email'],
      input[type='password'],
      textarea.form-control {
        display: block;
        width: 100%;
        box-sizing: border-box;
        padding: 0.5rem 0.75rem;
        border: 1px solid #d1d5db;
        border-radius: 0.375rem;
        font-size: 0.9375rem;
        line-height: 1.5;
        color: #111827;
        background: #ffffff;
        font-family: inherit;
        transition: border-color 0.15s, box-shadow 0.15s;
      }
      .form-control:focus,
      .form-select:focus,
      input[type='text']:focus,
      input[type='number']:focus,
      input[type='email']:focus,
      input[type='password']:focus,
      textarea.form-control:focus {
        border-color: #2563eb;
        box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.12);
        outline: none;
      }

      /* Selectize — pixel-identical to form-control above */
      .selectize-control {
        width: 100%;
      }
      .selectize-input {
        display: block !important;
        width: 100% !important;
        box-sizing: border-box !important;
        padding: 0.5rem 0.75rem !important;
        border: 1px solid #d1d5db !important;
        border-radius: 0.375rem !important;
        font-size: 0.9375rem !important;
        line-height: 1.5 !important;
        color: #111827 !important;
        background: #ffffff !important;
        box-shadow: none !important;
        min-height: 0 !important;
        cursor: default !important;
        transition: border-color 0.15s, box-shadow 0.15s !important;
      }
      .selectize-input.focus {
        border-color: #2563eb !important;
        box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.12) !important;
        outline: none !important;
      }
      /* Selected item text inside the box */
      .selectize-input .item {
        line-height: 1.5 !important;
        padding: 0 !important;
        margin: 0 !important;
        color: #111827 !important;
        font-size: 0.9375rem !important;
      }
      /* Hidden search input — keep functional, zero size when collapsed */
      .selectize-input > input {
        font-size: 0.9375rem !important;
        line-height: 1.5 !important;
        padding: 0 !important;
        margin: 0 !important;
        color: #111827 !important;
        background: transparent !important;
        border: none !important;
      }
      /* Open dropdown menu */
      .selectize-dropdown {
        border: 1px solid #d1d5db !important;
        border-radius: 0.375rem !important;
        box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.08), 0 2px 4px -1px rgba(0, 0, 0, 0.04) !important;
        font-size: 0.9375rem !important;
        margin-top: 2px !important;
        background: #ffffff !important;
      }
      .selectize-dropdown .option {
        padding: 0.5rem 0.75rem !important;
        color: #374151 !important;
        line-height: 1.5 !important;
        cursor: pointer !important;
      }
      .selectize-dropdown .option:hover,
      .selectize-dropdown .option.active {
        background: #eff6ff !important;
        color: #1d4ed8 !important;
      }
      .selectize-dropdown .option.selected {
        background: #dbeafe !important;
        color: #1d4ed8 !important;
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
        background: #2563eb;
        color: white;
        box-shadow: 0 1px 2px 0 rgba(0, 0, 0, 0.05);
      }
      .btn-primary:hover {
        background: #1d4ed8;
        box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
        transform: translateY(-1px);
      }
      .btn-outline-secondary {
        border: 1px solid #d1d5db;
        color: #374151;
        background: white;
      }
      .btn-outline-secondary:hover {
        background: #f9fafb;
        border-color: #9ca3af;
      }
      .btn-danger {
        background: #d4183d;
        color: white;
      }

      /* Typography — sizes and weights from demo globals.css */
      h1 {
        color: #111827;
        font-size: 1.5rem;
        font-weight: 500;
        line-height: 1.5;
        margin-bottom: 0.5rem;
      }
      h2 {
        color: #111827;
        font-size: 1.25rem;
        font-weight: 500;
        line-height: 1.5;
        margin-bottom: 0.75rem;
      }
      h3 {
        color: #111827;
        font-size: 1.125rem;
        font-weight: 500;
        line-height: 1.5;
        margin-bottom: 0.5rem;
      }
      h4 {
        color: #374151;
        font-size: 1rem;
        font-weight: 500;
        line-height: 1.5;
        margin-bottom: 0.5rem;
      }
      .text-muted {
        color: #6b7280;
      }

      /* Tables */
      table {
        background: white;
      }
      thead {
        background: #f9fafb;
        border-bottom: 1px solid #e5e7eb;
      }
      th {
        color: #374151;
        font-weight: 600;
        font-size: 0.875rem;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        padding: 0.75rem 1rem !important;
      }
      td {
        padding: 0.75rem 1rem !important;
        border-bottom: 1px solid #f3f4f6;
        color: #374151;
      }
      tr:hover {
        background: #f9fafb;
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
        border-color: #e5e7eb;
        opacity: 1;
      }

      /* Disable Shiny's built-in recalculating fade entirely.
         Shiny exposes --shiny-fade-opacity as the intended override point.
         Setting it to 1 at :root prevents any opacity change on recalculating
         outputs. The transition is also killed so there is no animation
         artefact even if the class briefly lingers. Polling is unaffected. */
      :root {
        --shiny-fade-opacity: 1;
        --bs-font-sans-serif: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Helvetica Neue', Arial, sans-serif;
      }
      .recalculating {
        transition: none !important;
      }

      /* ── File input zone: native picker + drag-drop + text path ─────── */
      .file-input-zone {
        border: 1.5px dashed #d1d5db;
        border-radius: 0.5rem;
        padding: 0.875rem 1rem 0.75rem;
        background: #fafafa;
        transition: border-color 0.2s, background 0.2s;
      }
      .file-input-zone.drag-over {
        border-color: #2563eb;
        background: #eff6ff;
      }
      .file-input-zone .shiny-input-container {
        margin-bottom: 0 !important;
      }
      .fiz-hint {
        font-size: 0.8rem;
        color: #9ca3af;
        margin: 0 0 0.45rem;
      }
      .fiz-chosen {
        font-size: 0.78rem;
        color: #6b7280;
        font-style: italic;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .fiz-chosen.has-file {
        color: #374151;
        font-style: normal;
      }
    ")),
  tags$script(HTML("
    $(function() {
      /* drag-over highlight */
      $(document).on('dragenter dragover', '.file-input-zone', function(e) {
        e.preventDefault(); e.stopPropagation();
        $(this).addClass('drag-over');
      });
      $(document).on('dragleave', '.file-input-zone', function(e) {
        var rt = e.relatedTarget;
        if (rt && (this === rt || $.contains(this, rt))) return;
        $(this).removeClass('drag-over');
      });
      /* drop: extract file:// URI and populate the text input */
      $(document).on('drop', '.file-input-zone', function(e) {
        e.preventDefault(); e.stopPropagation();
        $(this).removeClass('drag-over');
        var $txt = $(this).find('input[type=\"text\"]').first();
        if (!$txt.length) return;
        var dt = e.originalEvent.dataTransfer;
        var uri = (dt && dt.getData && (dt.getData('text/uri-list') || dt.getData('text/plain'))) || '';
        if (!uri && dt && dt.files && dt.files.length > 0) { uri = dt.files[0].path || ''; }
        uri = uri.split(/\\r?\\n/)[0].trim();
        if (uri.indexOf('file://') === 0) { uri = decodeURIComponent(uri.substring(7)); }
        if (uri) {
          $txt.val(uri).trigger('input');
          $(this).find('.fiz-chosen').text(uri.split('/').pop()).addClass('has-file');
        }
      });
      /* native picker: show chosen filename as hint (path cannot be read from browser) */
      $(document).on('change', '.fiz-native', function() {
        var f = this.files && this.files[0];
        var $chosen = $(this).closest('.file-input-zone').find('.fiz-chosen');
        if (f) { $chosen.text(f.name).addClass('has-file'); }
        else    { $chosen.text('').removeClass('has-file'); }
      });
    });
  ")),
  )  # end tagList for header
  ),
  useShinyjs(),

  # Navigation panels — Setup Wizard is NOT a tab; it's the full-screen overlay above
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
  )
)

# Define server
server <- function(input, output, session) {

  # Shared reactive values
  shared <- reactiveValues(
    current_run           = NULL,
    run_status            = "idle",
    setup_complete        = file.exists(file.path(dirname(getwd()), ".setup_complete")),
    goto_page             = NULL,
    show_wizard           = FALSE,   # set TRUE by dashboard "Return to Wizard" button
    additional_output_dir = NULL     # optional second copy destination set by SR/LR modules
  )

  # Module servers
  dashboard_server("dashboard", shared)
  short_read_server("short_read", shared)
  long_read_server("long_read", shared)
  compare_server("compare", shared)
  pipeline_modal_server("pipeline_modal", shared)
  setup_wizard_server("setup_wizard", shared)

  # Handle page navigation from modules
  observeEvent(shared$goto_page, {
    if (!is.null(shared$goto_page)) {
      updateNavbarPage(session, "main_nav", shared$goto_page)
      shared$goto_page <- NULL
    }
  })
}

# ── Ready message printed to terminal ────────────────────────────────────────
local({
  w   <- 58L
  top <- paste0("\u2554", paste(rep("\u2550", w), collapse = ""), "\u2557")
  bot <- paste0("\u255a", paste(rep("\u2550", w), collapse = ""), "\u255d")
  row <- function(txt) {
    pad <- w - 2L - nchar(txt)
    paste0("\u2551 ", txt, paste(rep(" ", max(0L, pad)), collapse = ""), " \u2551")
  }
  cat(top, "\n", sep = "")
  cat(row("  STaBioM is starting \u2014 opening browser automatically"), "\n", sep = "")
  cat(row("  If the browser does not open, navigate to the URL shown"), "\n", sep = "")
  cat(row("  below. Press Ctrl+C in this terminal to stop the app."), "\n", sep = "")
  cat(bot, "\n\n", sep = "")
})

# Run the app with auto-launch
options(shiny.launch.browser = TRUE)
shinyApp(ui = ui, server = server)

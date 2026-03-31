# Auto-check and install required R packages
# Prints the STaBioM startup banner and ensures the environment is ready.

.stabiom_banner <- function() {
  w   <- 58L
  top <- paste0("\u2554", paste(rep("\u2550", w), collapse = ""), "\u2557")
  mid <- paste0("\u2560", paste(rep("\u2550", w), collapse = ""), "\u2563")
  bot <- paste0("\u255a", paste(rep("\u2550", w), collapse = ""), "\u255d")
  row <- function(txt) {
    pad <- w - 2L - nchar(txt)
    paste0("\u2551 ", txt, paste(rep(" ", max(0L, pad)), collapse = ""), " \u2551")
  }
  blank <- paste0("\u2551", paste(rep(" ", w), collapse = ""), "\u2551")

  cat("\n")
  cat(top,   "\n", sep = "")
  cat(blank, "\n", sep = "")
  cat(row("  \u2588\u2588\u2588\u2588\u2588\u2588\u2588 \u2588\u2588\u2588\u2588\u2588\u2588\u2588 "), "\n", sep = "")
  cat(row("  \u2588\u2588\u2588\u2588\u2588\u2588\u2588 \u2588\u2588\u2588\u2588\u2588\u2588\u2588 "), "\n", sep = "")
  cat(row("  STaBioM  \u2500  Standardised Bioinformatics"), "\n", sep = "")
  cat(row("               for Microbial Samples"), "\n", sep = "")
  cat(blank, "\n", sep = "")
  cat(mid,   "\n", sep = "")
  cat(row("  Checking environment \u2026"), "\n", sep = "")
  cat(bot,   "\n", sep = "")
  cat("\n")
}

check_and_install_packages <- function(quiet = FALSE) {
  required_packages <- c(
    "shiny", "bslib", "jsonlite", "shinyjs", "shinydashboard",
    "sys", "shinyFiles", "fs", "processx"
  )

  missing_packages <- required_packages[
    !sapply(required_packages, requireNamespace, quietly = TRUE)
  ]

  if (length(missing_packages) > 0) {
    message("[STaBioM] Installing missing packages: ",
            paste(missing_packages, collapse = ", "), " ...")
    tryCatch(
      install.packages(missing_packages,
                       repos  = "https://cloud.r-project.org/",
                       quiet  = quiet),
      error = function(e) {
        stop("[STaBioM] install.packages() failed: ", conditionMessage(e))
      }
    )
    still_missing <- missing_packages[
      !sapply(missing_packages, requireNamespace, quietly = TRUE)
    ]
    if (length(still_missing) > 0) {
      stop("[STaBioM] Failed to install: ",
           paste(still_missing, collapse = ", "))
    }
    message("[STaBioM] All packages installed successfully.")
  } else if (!quiet) {
    message("[STaBioM] All required packages present.")
  }

  invisible(TRUE)
}

# ── Run at source time ────────────────────────────────────────────────────────
.stabiom_banner()
check_and_install_packages()

# Auto-check and install required R packages
# Prints the STaBioM startup banner and ensures the environment is ready.

.stabiom_banner <- function() {
  # ANSI codes — degrade gracefully on non-colour terminals
  X  <- "\033[0m"              # reset
  C  <- "\033[96m"             # bright cyan  (box chrome)
  PK <- "\033[1;4;38;5;213m"  # bold + underline + hot pink  (STaBioM title)
  W  <- "\033[97m"             # bright white  (subtitle)
  DG <- "\033[90m"             # dark grey  (version line)
  Y  <- "\033[93m"             # amber  (status line)

  w <- 58L  # inner width (chars between the two ║)

  top   <- paste0(C, "\u2554", strrep("\u2550", w), "\u2557", X)
  mid   <- paste0(C, "\u2560", strrep("\u2550", w), "\u2563", X)
  bot   <- paste0(C, "\u255a", strrep("\u2550", w), "\u255d", X)
  blank <- paste0(C, "\u2551", strrep(" ", w), "\u2551", X)

  # row(): plain = visible text for width, display = ANSI-decorated version
  row <- function(plain, display = plain) {
    pad <- max(0L, w - 2L - nchar(plain, type = "chars"))
    paste0(C, "\u2551 ", X, display, strrep(" ", pad), C, " \u2551", X)
  }

  # Get version from git — falls back gracefully if git is unavailable
  git_ver <- tryCatch({
    v <- system2("git", c("describe", "--tags", "--always"),
                 stdout = TRUE, stderr = FALSE)
    if (length(v) > 0 && nchar(trimws(v[1])) > 0) trimws(v[1]) else "dev"
  }, error = function(e) "dev")

  # Plain strings (for width calc — no ANSI codes)
  t1p  <- " STaBioM"                                                # 8 chars
  t2p  <- " Standardised Bioinformatics for Microbial Samples"      # 51 chars
  vp   <- paste0(" ", git_ver)                                      # varies
  chkp <- " Checking environment\u2026"                             # 22 chars

  # Display strings (with ANSI codes)
  t1d  <- paste0(" ", PK, "STaBioM", X)
  t2d  <- paste0(" ", W, "Standardised Bioinformatics for Microbial Samples", X)
  vd   <- paste0(" ", DG, git_ver, X)
  chkd <- paste0(" ", Y, "Checking environment\u2026", X)

  cat("\n")
  cat(top,              "\n", sep = "")
  cat(blank,            "\n", sep = "")
  cat(row(t1p,  t1d),   "\n", sep = "")
  cat(blank,            "\n", sep = "")
  cat(row(t2p,  t2d),   "\n", sep = "")
  cat(blank,            "\n", sep = "")
  cat(row(vp,   vd),    "\n", sep = "")
  cat(blank,            "\n", sep = "")
  cat(mid,              "\n", sep = "")
  cat(row(chkp, chkd),  "\n", sep = "")
  cat(bot,              "\n", sep = "")
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
                       repos = "https://cloud.r-project.org/",
                       quiet = quiet),
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

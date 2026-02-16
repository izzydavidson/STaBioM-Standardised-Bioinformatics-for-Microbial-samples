# Auto-check and install required R packages
# This runs automatically when the app loads

check_and_install_packages <- function(quiet = FALSE) {
  required_packages <- c("shiny", "bslib", "jsonlite", "shinyjs", "shinydashboard", "sys", "shinyFiles", "fs", "processx")

  missing_packages <- required_packages[!sapply(required_packages, requireNamespace, quietly = TRUE)]

  if (length(missing_packages) > 0) {
    if (!quiet) {
      message("Installing missing R packages: ", paste(missing_packages, collapse = ", "))
    }

    install.packages(missing_packages, repos = "https://cloud.r-project.org/", quiet = quiet)

    # Verify installation
    still_missing <- missing_packages[!sapply(missing_packages, requireNamespace, quietly = TRUE)]

    if (length(still_missing) > 0) {
      stop("Failed to install packages: ", paste(still_missing, collapse = ", "))
    }

    if (!quiet) {
      message("Successfully installed all required packages")
    }
  }

  invisible(TRUE)
}

# Run check
check_and_install_packages()

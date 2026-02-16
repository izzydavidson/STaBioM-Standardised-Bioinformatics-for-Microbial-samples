# CLI Interface Utilities
# Functions to interact with the STaBioM CLI

get_stabiom_path <- function() {
  # Get the path to the stabiom binary
  repo_root <- dirname(getwd())
  file.path(repo_root, "stabiom")
}

check_stabiom_available <- function() {
  # Check if stabiom binary is available
  stabiom_path <- get_stabiom_path()
  file.exists(stabiom_path)
}

run_stabiom_command <- function(args, wait = TRUE, stdout = TRUE, stderr = TRUE) {
  # Run a stabiom command with given arguments
  stabiom_path <- get_stabiom_path()

  if (!file.exists(stabiom_path)) {
    stop("STaBioM binary not found at: ", stabiom_path)
  }

  system2(stabiom_path, args, wait = wait, stdout = stdout, stderr = stderr)
}

list_available_pipelines <- function() {
  # Get list of available pipelines from stabiom list
  tryCatch({
    result <- run_stabiom_command("list", wait = TRUE, stdout = TRUE, stderr = FALSE)

    # Parse output to extract pipeline IDs
    pipelines <- grep("^  [a-z_]+", result, value = TRUE)
    gsub("^  ([a-z_]+).*", "\\1", pipelines)

  }, error = function(e) {
    c("sr_amp", "sr_meta", "lr_amp", "lr_meta")  # Fallback to known pipelines
  })
}

get_pipeline_info <- function(pipeline_id) {
  # Get detailed information about a specific pipeline
  tryCatch({
    result <- run_stabiom_command(c("info", pipeline_id), wait = TRUE, stdout = TRUE, stderr = FALSE)
    paste(result, collapse = "\n")
  }, error = function(e) {
    paste("Error getting pipeline info:", e$message)
  })
}

check_docker_status <- function() {
  # Check if Docker is installed and running
  docker_installed <- tryCatch({
    system2("docker", "--version", stdout = FALSE, stderr = FALSE) == 0
  }, error = function(e) FALSE)

  docker_running <- if (docker_installed) {
    tryCatch({
      system2("docker", "ps", stdout = FALSE, stderr = FALSE) == 0
    }, error = function(e) FALSE)
  } else {
    FALSE
  }

  list(
    installed = docker_installed,
    running = docker_running
  )
}

get_outputs_directory <- function() {
  # Get the default outputs directory
  repo_root <- dirname(getwd())
  file.path(repo_root, "outputs")
}

list_pipeline_runs <- function() {
  # List all pipeline runs from the outputs directory
  outputs_dir <- get_outputs_directory()

  if (!dir.exists(outputs_dir)) {
    return(data.frame())
  }

  run_dirs <- list.dirs(outputs_dir, recursive = FALSE, full.names = FALSE)

  if (length(run_dirs) == 0) {
    return(data.frame())
  }

  # Get info for each run
  runs_info <- lapply(run_dirs, function(run_id) {
    config_file <- file.path(outputs_dir, run_id, "config.json")

    if (!file.exists(config_file)) {
      return(NULL)
    }

    config <- tryCatch({
      jsonlite::fromJSON(config_file)
    }, error = function(e) NULL)

    if (is.null(config)) {
      return(NULL)
    }

    data.frame(
      run_id = run_id,
      pipeline = config$pipeline %||% "unknown",
      run_name = config$run_name %||% run_id,
      sample_type = config$sample_type %||% "unknown",
      timestamp = run_id,
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, Filter(Negate(is.null), runs_info))
}

# Null coalescing operator
`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

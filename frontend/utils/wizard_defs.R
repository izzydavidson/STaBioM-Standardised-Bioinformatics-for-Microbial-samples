# ---------------------------------------------------------------------------
# wizard_defs.R
# Shared definitions for the Shiny setup wizard.
# Mirrors wizard.R and cli/setup.py paths exactly.
# Do NOT modify main/ or cli/.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
wizard_repo_root <- function() normalizePath(dirname(getwd()))

wizard_marker_file <- function(repo_root = wizard_repo_root()) {
  file.path(repo_root, ".setup_complete")
}

wizard_is_complete <- function(repo_root = wizard_repo_root()) {
  file.exists(wizard_marker_file(repo_root))
}

wizard_mark_complete <- function(repo_root = wizard_repo_root()) {
  writeLines(format(Sys.time()), wizard_marker_file(repo_root))
}

wizard_check_docker <- function() {
  tryCatch({
    result <- system2("docker", args = "info",
                      stdout = TRUE, stderr = TRUE, timeout = 8)
    sc <- attr(result, "status")
    is.null(sc) || sc == 0L
  }, error = function(e) FALSE)
}

# ---------------------------------------------------------------------------
# Database, tool, and model definitions
# Must match wizard.R / cli/setup.py exactly (URLs, dest paths)
# ---------------------------------------------------------------------------
WIZARD_DATABASES <- list(
  list(
    id          = "kraken2-standard-8",
    name        = "Kraken2 Standard-8",
    desc        = "8 GB: Bacteria, Archaea, Viral, Human",
    size        = "8",
    pipelines   = "sr_meta, lr_meta",
    url         = "https://genome-idx.s3.amazonaws.com/kraken/k2_standard_08gb_20240605.tar.gz",
    is_tarball  = TRUE
  ),
  list(
    id          = "kraken2-standard-16",
    name        = "Kraken2 Standard-16",
    desc        = "16 GB: Bacteria, Archaea, Viral, Human",
    size        = "16",
    pipelines   = "sr_meta, lr_meta",
    url         = "https://genome-idx.s3.amazonaws.com/kraken/k2_standard_16gb_20240605.tar.gz",
    is_tarball  = TRUE
  ),
  list(
    id          = "emu-default",
    name        = "Emu Default",
    desc        = "17K species for long-read amplicon",
    size        = "0.1",
    pipelines   = "lr_amp",
    url         = "https://files.osf.io/v1/resources/56uf7/providers/osfstorage/63da8a656946a0023a7a54ef",
    is_tarball  = TRUE
  ),
  list(
    id          = "emu-silva",
    name        = "Emu SILVA",
    desc        = "100K+ species for long-read amplicon",
    size        = "0.6",
    pipelines   = "lr_amp",
    url         = "https://files.osf.io/v1/resources/56uf7/providers/osfstorage/63da837c7d0187023fbc4993",
    is_tarball  = TRUE
  ),
  list(
    id          = "emu-rdp",
    name        = "Emu RDP (RECOMMENDED)",
    desc        = "280K+ species for long-read amplicon",
    size        = "1.3",
    pipelines   = "lr_amp",
    url         = "https://files.osf.io/v1/resources/56uf7/providers/osfstorage/63da84611e96860221b25460",
    is_tarball  = TRUE
  ),
  list(
    id            = "qiime2-silva-138",
    name          = "QIIME2 SILVA 138",
    desc          = "Naive-Bayes classifier — REQUIRED for sr_amp",
    size          = "0.21",
    pipelines     = "sr_amp",
    url           = "https://data.qiime2.org/classifiers/sklearn-1.4.2/silva/silva-138-99-nb-classifier.qza",
    is_single_file = TRUE,
    dest_subdir   = "reference/qiime2",
    dest_filename = "silva-138-99-nb-classifier.qza"
  ),
  list(
    id            = "human-grch38",
    name          = "Human GRCh38",
    desc          = "Reference genome for host-read depletion",
    size          = "0.9",
    pipelines     = "sr_meta, lr_meta",
    url           = "https://ftp.ncbi.nlm.nih.gov/genomes/all/GCA/000/001/405/GCA_000001405.15_GRCh38/seqs_for_alignment_pipelines.ucsc_ids/GCA_000001405.15_GRCh38_no_alt_analysis_set.fna.gz",
    is_single_file = TRUE,
    dest_subdir   = "reference/human/grch38",
    dest_filename = "GCA_000001405.15_GRCh38_no_alt_analysis_set.fna.gz"
  )
)

WIZARD_TOOLS <- list(
  list(
    id      = "valencia",
    name    = "VALENCIA",
    desc    = "Vaginal Community State Type (CST) classification",
    size    = "~2 MB",
    samples = "vaginal",
    url     = "https://github.com/ravel-lab/VALENCIA/archive/refs/heads/master.zip"
  )
)

WIZARD_DORADO_MODELS <- list(
  list(id = "dna_r10.4.1_e8.2_400bps_hac@v5.2.0",
       name = "HAC v5.2.0 (RECOMMENDED)",
       desc = "High accuracy for modern 5kHz ONT data",
       size = "~400 MB"),
  list(id = "dna_r10.4.1_e8.2_400bps_sup@v5.2.0",
       name = "SUP v5.2.0",
       desc = "Super accuracy for 5kHz ONT data (slower)",
       size = "~400 MB"),
  list(id = "dna_r10.4.1_e8.2_400bps_hac@v5.0.0",
       name = "HAC v5.0.0",
       desc = "High accuracy stable release",
       size = "~400 MB"),
  list(id = "dna_r10.4.1_e8.2_400bps_hac@v4.3.0",
       name = "HAC v4.3.0",
       desc = "Legacy high accuracy model",
       size = "~400 MB"),
  list(id = "dna_r10.4.1_e8.2_400bps_hac@v4.2.0",
       name = "HAC v4.2.0",
       desc = "Legacy baseline model",
       size = "~400 MB")
)

# ---------------------------------------------------------------------------
# Detection  — paths must match wizard.R exactly
# ---------------------------------------------------------------------------
wizard_detect_installed <- function(repo_root = wizard_repo_root()) {
  inst <- list(databases = character(0), tools = character(0), models = character(0))

  for (db in WIZARD_DATABASES) {
    if (isTRUE(db$is_single_file)) {
      p <- file.path(repo_root, "main", "data", db$dest_subdir, db$dest_filename)
      if (file.exists(p)) inst$databases <- c(inst$databases, db$id)
    } else {
      p <- file.path(repo_root, "main", "data", "databases", db$id)
      if (dir.exists(p) && length(list.files(p)) > 0)
        inst$databases <- c(inst$databases, db$id)
    }
  }

  # VALENCIA — check canonical centroids path (matches wizard.R line 41-44)
  centroids <- file.path(repo_root, "tools", "VALENCIA", "CST_centroids_012920.csv")
  if (file.exists(centroids)) inst$tools <- c(inst$tools, "valencia")

  # Dorado models — download target is tools/models/dorado/<model_id>/
  models_dir <- file.path(repo_root, "tools", "models", "dorado")
  for (m in WIZARD_DORADO_MODELS) {
    if (dir.exists(file.path(models_dir, m$id)))
      inst$models <- c(inst$models, m$id)
  }

  inst
}

# ---------------------------------------------------------------------------
# wizard_run_downloads()
# Designed to be called from a background Rscript subprocess.
# Writes structured lines to stdout — parsed by the Shiny polling observer.
#
# Line protocol:
#   [LOG] text       — regular info line
#   [OK]  text       — success (green)
#   [ERR] text       — error   (red)
#   [PROG:N] text    — progress bar (N = 0–100)
#   [DONE:ok]        — all completed successfully
#   [DONE:fail]      — one or more items failed
# ---------------------------------------------------------------------------
wiz_emit <- function(prefix, msg) {
  cat(prefix, msg, "\n", sep = "")
  flush.console()
}
wiz_log  <- function(msg)        wiz_emit("[LOG] ", msg)
wiz_ok   <- function(msg)        wiz_emit("[OK] ",  msg)
wiz_err  <- function(msg)        wiz_emit("[ERR] ", msg)
wiz_prog <- function(pct, text)  { cat("[PROG:", pct, "] ", text, "\n", sep = ""); flush.console() }

wizard_run_downloads <- function(selected_db_ids, selected_tool_ids,
                                 selected_model_ids, repo_root) {

  data_dir   <- file.path(repo_root, "main", "data", "databases")
  tools_dir  <- file.path(repo_root, "tools")
  models_dir <- file.path(tools_dir, "models", "dorado")
  dir.create(data_dir,   recursive = TRUE, showWarnings = FALSE)
  dir.create(models_dir, recursive = TRUE, showWarnings = FALSE)

  total  <- length(selected_db_ids) + length(selected_tool_ids) + length(selected_model_ids)
  done   <- 0L
  failed <- character(0)

  wiz_log(paste("Repository:", repo_root))
  wiz_log(paste("Total items to install:", total))
  wiz_prog(0, "Starting installation...")

  # ---- Databases ----
  if (length(selected_db_ids) > 0) {
    wiz_log(">>> Installing databases")
    for (db_id in selected_db_ids) {
      db <- Filter(function(x) x$id == db_id, WIZARD_DATABASES)[[1]]
      done  <- done + 1L
      wiz_prog(round(done / (total + 1) * 95), paste("Installing", db$name))
      wiz_log(paste("Installing:", db$name, sprintf("(~%s GB)", db$size)))

      t0 <- proc.time()["elapsed"]

      tryCatch({
        if (isTRUE(db$is_single_file)) {
          dest_dir  <- file.path(repo_root, "main", "data", db$dest_subdir)
          dest_file <- file.path(dest_dir, db$dest_filename)
          dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)

          if (file.exists(dest_file) && file.size(dest_file) > 1e6) {
            wiz_ok(paste(db$name, "already installed"))
          } else {
            wiz_log(paste("Downloading:", db$url))
            download.file(db$url, dest_file, mode = "wb", quiet = TRUE, method = "auto")
            elapsed <- round(proc.time()["elapsed"] - t0, 1)
            if (file.exists(dest_file) && file.size(dest_file) > 1e6) {
              wiz_ok(sprintf("%s completed (%.1f MB, %.1fs)",
                             db$name, file.size(dest_file) / 1024 / 1024, elapsed))
            } else {
              wiz_err(paste(db$name, "failed: file too small or missing"))
              failed <- c(failed, db$name)
              if (file.exists(dest_file)) unlink(dest_file)
            }
          }
        } else {
          db_path      <- file.path(data_dir, db$id)
          archive_path <- file.path(data_dir, paste0(db$id, ".tar.gz"))

          if (dir.exists(db_path) && length(list.files(db_path)) > 0) {
            wiz_ok(paste(db$name, "already installed"))
          } else {
            wiz_log(paste("Downloading:", db$url))
            download.file(db$url, archive_path, mode = "wb", quiet = TRUE, method = "auto")

            if (!file.exists(archive_path) || file.size(archive_path) < 1e6) {
              wiz_err(paste(db$name, "failed: download too small"))
              failed <- c(failed, db$name)
              if (file.exists(archive_path)) unlink(archive_path)
            } else {
              arch_mb <- round(file.size(archive_path) / 1024 / 1024, 1)
              wiz_log(paste("Downloaded:", arch_mb, "MB — extracting..."))
              dir.create(db_path, recursive = TRUE, showWarnings = FALSE)
              rc <- untar(archive_path, exdir = db_path, tar = "internal")
              elapsed <- round(proc.time()["elapsed"] - t0, 1)
              if (rc == 0 && dir.exists(db_path) && length(list.files(db_path)) > 0) {
                unlink(archive_path)
                wiz_ok(sprintf("%s completed (%.1fs)", db$name, elapsed))
              } else {
                wiz_err(paste(db$name, "failed: extraction error"))
                failed <- c(failed, db$name)
                unlink(archive_path, force = TRUE)
                unlink(db_path, recursive = TRUE, force = TRUE)
              }
            }
          }
        }
      }, error = function(e) {
        wiz_err(paste(db$name, "error:", e$message))
        failed <<- c(failed, db$name)
      })
    }
  }

  # ---- Tools (VALENCIA) ----
  if (length(selected_tool_ids) > 0) {
    wiz_log(">>> Installing tools")
    for (tool_id in selected_tool_ids) {
      tool <- Filter(function(x) x$id == tool_id, WIZARD_TOOLS)[[1]]
      done <- done + 1L
      wiz_prog(round(done / (total + 1) * 95), paste("Installing", tool$name))
      wiz_log(paste("Installing:", tool$name))

      tool_dest    <- file.path(tools_dir, toupper(tool$id))
      archive_path <- file.path(tools_dir, paste0(tool$id, ".zip"))
      dir.create(tools_dir, recursive = TRUE, showWarnings = FALSE)

      tryCatch({
        if (dir.exists(tool_dest) && length(list.files(tool_dest)) > 0) {
          centroids <- file.path(tool_dest, "CST_centroids_012920.csv")
          if (file.exists(centroids)) {
            wiz_ok(paste(tool$name, "already installed"))
            next
          }
        }

        t0 <- proc.time()["elapsed"]
        wiz_log(paste("Downloading:", tool$url))
        download.file(tool$url, archive_path, mode = "wb", quiet = TRUE, method = "auto")

        if (!file.exists(archive_path) || file.size(archive_path) < 1e5) {
          wiz_err(paste(tool$name, "failed: download too small"))
          failed <- c(failed, tool$name)
          if (file.exists(archive_path)) unlink(archive_path)
        } else {
          wiz_log("Extracting archive...")
          temp_extract <- file.path(tools_dir, paste0(tool$id, "_temp"))
          unzip(archive_path, exdir = temp_extract, overwrite = TRUE)

          top_dirs <- list.dirs(temp_extract, full.names = TRUE, recursive = FALSE)
          if (length(top_dirs) == 1) {
            if (dir.exists(tool_dest)) unlink(tool_dest, recursive = TRUE)
            file.rename(top_dirs[1], tool_dest)
            unlink(temp_extract, recursive = TRUE)
          } else {
            if (dir.exists(tool_dest)) unlink(tool_dest, recursive = TRUE)
            file.rename(temp_extract, tool_dest)
          }

          unlink(archive_path)
          elapsed <- round(proc.time()["elapsed"] - t0, 1)

          centroids <- file.path(tool_dest, "CST_centroids_012920.csv")
          if (file.exists(centroids)) {
            wiz_ok(sprintf("%s installed (%.1fs)", tool$name, elapsed))
          } else {
            wiz_err(paste(tool$name, "installed but centroids file not found"))
            failed <- c(failed, tool$name)
          }
        }
      }, error = function(e) {
        wiz_err(paste(tool$name, "error:", e$message))
        failed <<- c(failed, tool$name)
        if (file.exists(archive_path)) unlink(archive_path)
      })
    }
  }

  # ---- Dorado Models ----
  if (length(selected_model_ids) > 0) {
    wiz_log(">>> Installing Dorado models")

    machine  <- Sys.info()["machine"]
    sysname  <- Sys.info()["sysname"]
    dorado_bin <- NULL

    if (sysname == "Darwin") {
      host_platform <- ifelse(machine == "arm64", "osx-arm64", "osx-x64")
      dorado_host_dir <- file.path(tools_dir, "dorado-host")
      dorado_bin      <- file.path(dorado_host_dir, "bin", "dorado")

      if (!file.exists(dorado_bin)) {
        wiz_log("Downloading Dorado binary for macOS...")
        dir.create(dorado_host_dir, recursive = TRUE, showWarnings = FALSE)
        dorado_url     <- sprintf("https://cdn.oxfordnanoportal.com/software/analysis/dorado-1.3.1-%s.zip",
                                  host_platform)
        dorado_archive <- file.path(dorado_host_dir, "dorado.zip")

        tryCatch({
          download.file(dorado_url, dorado_archive, mode = "wb", quiet = TRUE)
          wiz_log("Extracting Dorado...")
          unzip(dorado_archive, exdir = dorado_host_dir, overwrite = TRUE)
          unlink(dorado_archive)

          extracted_dirs <- list.dirs(dorado_host_dir, full.names = TRUE, recursive = FALSE)
          if (length(extracted_dirs) == 1 && basename(extracted_dirs[1]) != "bin") {
            for (item in list.files(extracted_dirs[1], full.names = TRUE)) {
              dest_item <- file.path(dorado_host_dir, basename(item))
              if (!file.exists(dest_item)) file.rename(item, dest_item)
            }
            unlink(extracted_dirs[1], recursive = TRUE)
          }

          if (file.exists(dorado_bin)) {
            Sys.chmod(dorado_bin, "0755")
            wiz_ok(paste("Dorado binary ready:", dorado_bin))
          } else {
            wiz_err("Dorado binary not found after extraction")
            dorado_bin <- NULL
          }
        }, error = function(e) {
          wiz_err(paste("Failed to download Dorado:", e$message))
          dorado_bin <<- NULL
        })
      } else {
        wiz_log("Dorado binary already present")
      }

    } else if (sysname == "Linux") {
      platform_str <- ifelse(machine %in% c("x86_64", "amd64"), "linux-x64", "linux-arm64")
      dorado_dir   <- file.path(tools_dir, "dorado")
      dorado_bin   <- file.path(dorado_dir, "bin", "dorado")

      if (!file.exists(dorado_bin)) {
        wiz_log("Downloading Dorado binary for Linux...")
        dir.create(dorado_dir, recursive = TRUE, showWarnings = FALSE)
        dorado_url     <- sprintf("https://cdn.oxfordnanoportal.com/software/analysis/dorado-1.3.1-%s.tar.gz",
                                  platform_str)
        dorado_archive <- file.path(dorado_dir, "dorado.tar.gz")

        tryCatch({
          download.file(dorado_url, dorado_archive, mode = "wb", quiet = TRUE)
          wiz_log("Extracting Dorado...")
          system(sprintf("cd '%s' && tar xzf dorado.tar.gz", dorado_dir))
          unlink(dorado_archive)

          if (file.exists(dorado_bin)) {
            Sys.chmod(dorado_bin, "0755")
            wiz_ok(paste("Dorado binary ready:", dorado_bin))
          } else {
            wiz_err("Dorado binary not found after extraction")
            dorado_bin <- NULL
          }
        }, error = function(e) {
          wiz_err(paste("Failed to download Dorado:", e$message))
          dorado_bin <<- NULL
        })
      } else {
        wiz_log("Dorado binary already present")
      }
    } else {
      wiz_err(paste("Unsupported OS for Dorado:", sysname))
    }

    if (!is.null(dorado_bin) && file.exists(dorado_bin)) {
      for (model_id in selected_model_ids) {
        model <- Filter(function(x) x$id == model_id, WIZARD_DORADO_MODELS)[[1]]
        done  <- done + 1L
        wiz_prog(round(done / (total + 1) * 95), paste("Installing", model$name))
        wiz_log(paste("Installing model:", model$id))

        model_path <- file.path(models_dir, model$id)
        if (dir.exists(model_path) && length(list.files(model_path, recursive = TRUE)) > 5) {
          wiz_ok(paste(model$name, "already installed"))
          next
        }

        t0  <- proc.time()["elapsed"]
        cmd <- sprintf("'%s' download --model %s --models-directory '%s' 2>&1",
                       dorado_bin, model$id, models_dir)
        rc  <- system(cmd, wait = TRUE)
        elapsed <- round(proc.time()["elapsed"] - t0, 1)

        if (rc == 0 && dir.exists(model_path) && length(list.files(model_path, recursive = TRUE)) > 5) {
          wiz_ok(sprintf("%s installed (%.1fs)", model$name, elapsed))
        } else {
          wiz_err(sprintf("%s failed (exit %d, %.1fs)", model$name, rc, elapsed))
          failed <- c(failed, model$name)
        }
      }
    } else {
      wiz_err("Dorado binary unavailable — skipping model downloads")
      for (model_id in selected_model_ids)
        failed <- c(failed, model_id)
    }
  }

  wiz_prog(100, "Installation complete")
  wiz_log("=== Summary ===")
  wiz_log(paste("Succeeded:", total - length(failed), "/", total))

  if (length(failed) > 0) {
    for (f in failed) wiz_err(paste("FAILED:", f))
    cat("[DONE:fail]\n"); flush.console()
  } else {
    wiz_ok("All items installed successfully")
    cat("[DONE:ok]\n"); flush.console()
  }
}

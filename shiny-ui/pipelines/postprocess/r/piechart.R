#!/usr/bin/env Rscript

# =============================================================================
# STaBioM R Postprocess: Pie Chart
# Works with both sr_amp (QIIME2) and sr_meta/lr_meta (Kraken2) outputs
# =============================================================================

suppressPackageStartupMessages({
  if (requireNamespace("jsonlite", quietly = TRUE)) library(jsonlite)
})

# Parse arguments
args <- commandArgs(trailingOnly = TRUE)
outputs_json <- NULL
out_dir <- NULL
params_json <- "{}"
module_name <- NULL

i <- 1
while (i <= length(args)) {
  if (args[i] == "--outputs_json" && i < length(args)) {
    outputs_json <- args[i + 1]
    i <- i + 2
  } else if (args[i] == "--out_dir" && i < length(args)) {
    out_dir <- args[i + 1]
    i <- i + 2
  } else if (args[i] == "--params_json" && i < length(args)) {
    params_json <- args[i + 1]
    i <- i + 2
  } else if (args[i] == "--module" && i < length(args)) {
    module_name <- args[i + 1]
    i <- i + 2
  } else {
    i <- i + 1
  }
}

if (is.null(outputs_json) || is.null(out_dir)) {
  stop("Usage: piechart.R --outputs_json <path> --out_dir <dir> [--params_json <json>] [--module <name>]")
}

# Load outputs.json
outputs <- fromJSON(outputs_json)
params <- tryCatch(fromJSON(params_json), error = function(e) list())

cat("[piechart] Module:", module_name, "\n")
cat("[piechart] Output dir:", out_dir, "\n")

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# Load data
data <- NULL
taxon_col <- NULL
count_col <- NULL

if (module_name %in% c("sr_meta", "lr_meta", "lr_amp") || is.null(module_name)) {
  postprocess_dir <- outputs$postprocess$dir
  if (!is.null(postprocess_dir)) {
    species_tidy <- file.path(postprocess_dir, "kraken_species_tidy.csv")
    genus_tidy <- file.path(postprocess_dir, "kraken_genus_tidy.csv")
    
    if (file.exists(species_tidy)) {
      data <- read.csv(species_tidy, stringsAsFactors = FALSE)
      taxon_col <- "species"
      count_col <- "reads"
      cat("[piechart] Using Kraken2 species data\n")
    } else if (file.exists(genus_tidy)) {
      data <- read.csv(genus_tidy, stringsAsFactors = FALSE)
      taxon_col <- "genus"
      count_col <- "reads"
      cat("[piechart] Using Kraken2 genus data\n")
    }
  }
}

if (is.null(data) && (module_name == "sr_amp" || is.null(module_name))) {
  qiime2_exports <- outputs$qiime2_exports
  if (!is.null(qiime2_exports)) {
    table_tsv <- qiime2_exports$table_tsv
    taxonomy_tsv <- qiime2_exports$taxonomy_tsv
    
    if (!is.null(table_tsv) && file.exists(table_tsv) &&
        !is.null(taxonomy_tsv) && file.exists(taxonomy_tsv)) {
      cat("[piechart] Using QIIME2 exports\n")
      
      lines <- readLines(table_tsv)
      header_idx <- which(grepl("^#OTU ID", lines))[1]
      if (!is.na(header_idx)) {
        table_df <- read.delim(
          text = paste(lines[header_idx:length(lines)], collapse = "\n"),
          sep = "\t",
          stringsAsFactors = FALSE,
          check.names = FALSE
        )
        colnames(table_df)[1] <- "FeatureID"
        
        tax_df <- read.delim(taxonomy_tsv, stringsAsFactors = FALSE, check.names = FALSE)
        colnames(tax_df)[1] <- "FeatureID"
        
        parse_taxon <- function(taxon) {
          if (is.na(taxon) || taxon == "") return("Unassigned")
          parts <- strsplit(taxon, ";")[[1]]
          parts <- trimws(parts)
          genus <- ""
          species <- ""
          for (p in parts) {
            if (grepl("^g__", p)) genus <- sub("^g__", "", p)
            if (grepl("^s__", p)) species <- sub("^s__", "", p)
            if (grepl("^D_5__", p)) genus <- sub("^D_5__", "", p)
            if (grepl("^D_6__", p)) species <- sub("^D_6__", "", p)
          }
          if (genus != "" && species != "") {
            paste(genus, species)
          } else if (genus != "") {
            genus
          } else {
            for (p in rev(parts)) {
              val <- sub("^[a-zA-Z]__", "", p)
              val <- sub("^D_[0-9]__", "", val)
              if (val != "" && !grepl("^unclassified", val, ignore.case = TRUE)) return(val)
            }
            "Unassigned"
          }
        }
        
        tax_df$taxon_label <- vapply(tax_df$Taxon, parse_taxon, character(1))
        sample_cols <- setdiff(colnames(table_df), "FeatureID")
        
        tidy_rows <- list()
        for (r in seq_len(nrow(table_df))) {
          fid <- table_df$FeatureID[r]
          taxon <- tax_df$taxon_label[match(fid, tax_df$FeatureID)]
          if (is.na(taxon)) taxon <- "Unassigned"
          
          for (s in sample_cols) {
            count <- suppressWarnings(as.numeric(table_df[r, s]))
            if (!is.na(count) && count > 0) {
              tidy_rows[[length(tidy_rows) + 1]] <- data.frame(
                taxon = taxon,
                count = count,
                stringsAsFactors = FALSE
              )
            }
          }
        }
        
        if (length(tidy_rows) > 0) {
          data <- do.call(rbind, tidy_rows)
          taxon_col <- "taxon"
          count_col <- "count"
        }
      }
    }
  }
}

if (is.null(data) || nrow(data) == 0) {
  cat("[piechart] No suitable data found for plotting\n")
  quit(save = "no", status = 0)
}

top_n <- if (!is.null(params$top_n)) params$top_n else 12

taxon_totals <- aggregate(data[[count_col]], by = list(taxon = data[[taxon_col]]), FUN = sum)
colnames(taxon_totals) <- c("taxon", "count")
taxon_totals <- taxon_totals[order(-taxon_totals$count), ]

top_taxa <- head(taxon_totals, top_n)
other_count <- sum(taxon_totals$count[-(1:min(top_n, nrow(taxon_totals)))])
if (other_count > 0) {
  top_taxa <- rbind(top_taxa, data.frame(taxon = "Other", count = other_count))
}

total <- sum(top_taxa$count)
top_taxa$pct <- round(100 * top_taxa$count / total, 1)

# ----------------------------
# Legend sizing controls
# Change these to alter legend size/shape
# ----------------------------
legend_cex <- 0.35     # legend text size
legend_ncol <- 1       # legend columns (2 makes it shorter)
legend_inset <- c(0, 0) # adjust if you want it closer/further
# ----------------------------

out_png <- file.path(out_dir, "piechart.png")
png(out_png, width = 800, height = 800, res = 150, bg = "white")

par(mar = c(1, 1, 3, 1))

colors <- rainbow(nrow(top_taxa), s = 0.7, v = 0.8)
if ("Other" %in% top_taxa$taxon) {
  colors[which(top_taxa$taxon == "Other")] <- "gray70"
}

labels <- paste0(top_taxa$taxon, " (", top_taxa$pct, "%)")
labels_pie <- ifelse(top_taxa$pct >= 2, labels, "")

pie(
  top_taxa$count,
  labels = labels_pie,
  col = colors,
  border = "white",
  main = paste("Overall Composition (Top", top_n, "Taxa)"),
  cex = 0.4
)

legend(
  "bottomleft",
  inset = legend_inset,
  legend = labels,
  fill = colors,
  border = NA,
  cex = legend_cex,
  bty = "n",
  ncol = legend_ncol
)

dev.off()

cat("[piechart] Generated:", out_png, "\n")

out_csv <- file.path(out_dir, "piechart_data.csv")
write.csv(top_taxa, out_csv, row.names = FALSE)
cat("[piechart] Generated:", out_csv, "\n")

cat("[piechart] Complete\n")

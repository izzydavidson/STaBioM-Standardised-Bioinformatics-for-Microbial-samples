#!/usr/bin/env Rscript

# =============================================================================
# STaBioM R Postprocess: Heatmap
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
  stop("Usage: heatmap.R --outputs_json <path> --out_dir <dir> [--params_json <json>] [--module <name>]")
}

# Load outputs.json
outputs <- fromJSON(outputs_json)
params <- tryCatch(fromJSON(params_json), error = function(e) list())

cat("[heatmap] Module:", module_name, "\n")
cat("[heatmap] Output dir:", out_dir, "\n")

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# Load data (same logic as relative_abundance.R)
data <- NULL
taxon_col <- NULL
abundance_col <- NULL

if (module_name %in% c("sr_meta", "lr_meta", "lr_amp") || is.null(module_name)) {
  postprocess_dir <- outputs$postprocess$dir
  if (!is.null(postprocess_dir)) {
    species_tidy <- file.path(postprocess_dir, "kraken_species_tidy.csv")
    genus_tidy <- file.path(postprocess_dir, "kraken_genus_tidy.csv")
    
    if (file.exists(species_tidy)) {
      data <- read.csv(species_tidy, stringsAsFactors = FALSE)
      taxon_col <- "species"
      abundance_col <- "fraction"
      cat("[heatmap] Using Kraken2 species data\n")
    } else if (file.exists(genus_tidy)) {
      data <- read.csv(genus_tidy, stringsAsFactors = FALSE)
      taxon_col <- "genus"
      abundance_col <- "fraction"
      cat("[heatmap] Using Kraken2 genus data\n")
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
      cat("[heatmap] Using QIIME2 exports\n")
      
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
                sample_id = s,
                taxon = taxon,
                count = count,
                stringsAsFactors = FALSE
              )
            }
          }
        }
        
        if (length(tidy_rows) > 0) {
          data <- do.call(rbind, tidy_rows)
          data <- aggregate(count ~ sample_id + taxon, data = data, FUN = sum)
          
          totals <- aggregate(count ~ sample_id, data = data, FUN = sum)
          colnames(totals)[2] <- "total"
          data <- merge(data, totals, by = "sample_id")
          data$fraction <- data$count / data$total
          
          taxon_col <- "taxon"
          abundance_col <- "fraction"
        }
      }
    }
  }
}

if (is.null(data) || nrow(data) == 0) {
  cat("[heatmap] No suitable data found for plotting\n")
  quit(save = "no", status = 0)
}

# Get top N taxa
top_n <- if (!is.null(params$top_n)) params$top_n else 25

# Calculate total abundance per taxon
taxon_totals <- aggregate(data[[abundance_col]], by = list(taxon = data[[taxon_col]]), FUN = sum)
colnames(taxon_totals) <- c("taxon", "total")
taxon_totals <- taxon_totals[order(-taxon_totals$total), ]
top_taxa <- head(taxon_totals$taxon, top_n)

# Filter to top taxa only
data_top <- data[data[[taxon_col]] %in% top_taxa, ]

# Create wide matrix for heatmap
samples <- unique(data_top$sample_id)
taxa <- top_taxa

mat <- matrix(0, nrow = length(taxa), ncol = length(samples))
rownames(mat) <- taxa
colnames(mat) <- samples

for (r in seq_len(nrow(data_top))) {
  s <- data_top$sample_id[r]
  t <- data_top[[taxon_col]][r]
  if (t %in% taxa && s %in% samples) {
    mat[t, s] <- data_top[[abundance_col]][r]
  }
}

# ----------------------------
# Legend sizing controls (colorbar)
# Change these to alter legend label sizing and spacing
# ----------------------------
legend_axis_cex <- 0.5     # tick label size on the colorbar
legend_title_cex <- 0.5    # "Rel. Abundance" label size
legend_title_line <- 1     # distance of title from axis (bigger = more space)
# ----------------------------

# Generate heatmap using base R
out_png <- file.path(out_dir, "heatmap.png")

n_taxa <- nrow(mat)
n_samples <- ncol(mat)

plot_width <- max(800, n_samples * 100 + 250)
plot_height <- max(800, n_taxa * 30 + 200)

png(out_png, width = plot_width, height = plot_height, res = 150)

layout(matrix(c(1, 2), nrow = 1), widths = c(4, 1))

par(mar = c(8, 12, 3, 1))

n_colors <- 100
colors <- colorRampPalette(c("white", "lightyellow", "orange", "red", "darkred"))(n_colors)

image(
  1:n_samples, 1:n_taxa, t(mat),
  col = colors,
  xlab = "", ylab = "",
  axes = FALSE,
  main = paste("Heatmap: Relative Abundance (Top", top_n, "Taxa)")
)

axis(1, at = 1:n_samples, labels = colnames(mat), las = 2, cex.axis = 0.7)
axis(2, at = 1:n_taxa, labels = rownames(mat), las = 1, cex.axis = 0.6)

abline(h = 0.5:(n_taxa + 0.5), col = "gray90", lwd = 0.5)
abline(v = 0.5:(n_samples + 0.5), col = "gray90", lwd = 0.5)

# Colorbar (legend)
par(mar = c(8, 1, 3, 3))
image(
  1, seq(0, 1, length.out = n_colors), t(matrix(1:n_colors)),
  col = colors,
  xlab = "", ylab = "",
  axes = FALSE
)
axis(
  4,
  at = c(0, 0.25, 0.5, 0.75, 1),
  labels = format(c(0, 0.25, 0.5, 0.75, 1), digits = 2),
  las = 1,
  cex.axis = legend_axis_cex
)
mtext("Rel. Abundance", side = 4, line = legend_title_line, cex = legend_title_cex)

dev.off()

cat("[heatmap] Generated:", out_png, "\n")

out_csv <- file.path(out_dir, "heatmap_data.csv")
write.csv(as.data.frame(mat), out_csv, row.names = TRUE)
cat("[heatmap] Generated:", out_csv, "\n")

cat("[heatmap] Complete\n")

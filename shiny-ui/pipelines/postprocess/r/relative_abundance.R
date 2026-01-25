#!/usr/bin/env Rscript

# =============================================================================
# STaBioM R Postprocess: Relative Abundance Stacked Bar Chart
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
  stop("Usage: relative_abundance.R --outputs_json <path> --out_dir <dir> [--params_json <json>] [--module <name>]")
}

# Load outputs.json
outputs <- fromJSON(outputs_json)
params <- tryCatch(fromJSON(params_json), error = function(e) list())

cat("[relative_abundance] Module:", module_name, "\n")
cat("[relative_abundance] Output dir:", out_dir, "\n")

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

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
      cat("[relative_abundance] Using Kraken2 species data\n")
    } else if (file.exists(genus_tidy)) {
      data <- read.csv(genus_tidy, stringsAsFactors = FALSE)
      taxon_col <- "genus"
      abundance_col <- "fraction"
      cat("[relative_abundance] Using Kraken2 genus data\n")
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
      cat("[relative_abundance] Using QIIME2 exports\n")
      
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
  cat("[relative_abundance] No suitable data found for plotting\n")
  quit(save = "no", status = 0)
}

top_n <- if (!is.null(params$top_n)) params$top_n else 15

taxon_totals <- aggregate(data[[abundance_col]], by = list(taxon = data[[taxon_col]]), FUN = sum)
colnames(taxon_totals) <- c("taxon", "total")
taxon_totals <- taxon_totals[order(-taxon_totals$total), ]
top_taxa <- head(taxon_totals$taxon, top_n)

data$taxon_plot <- ifelse(data[[taxon_col]] %in% top_taxa, data[[taxon_col]], "Other")

plot_data <- aggregate(
  data[[abundance_col]],
  by = list(sample = data$sample_id, taxon = data$taxon_plot),
  FUN = sum
)
colnames(plot_data) <- c("sample", "taxon", "abundance")

sample_totals <- aggregate(abundance ~ sample, data = plot_data, FUN = sum)
colnames(sample_totals)[2] <- "total"
plot_data <- merge(plot_data, sample_totals, by = "sample")
plot_data$abundance <- plot_data$abundance / plot_data$total

taxa_order <- unique(plot_data$taxon)
taxa_order <- c(setdiff(taxa_order, "Other"), "Other")[c(setdiff(taxa_order, "Other"), "Other") %in% taxa_order]
plot_data$taxon <- factor(plot_data$taxon, levels = taxa_order)

samples <- unique(plot_data$sample)
n_samples <- length(samples)
n_taxa <- length(taxa_order)

colors <- rainbow(n_taxa, s = 0.7, v = 0.8)
if ("Other" %in% taxa_order) {
  colors[which(taxa_order == "Other")] <- "gray70"
}

# ----------------------------
# Legend sizing controls
# Change these to alter legend size/shape
# ----------------------------
legend_cex <- 0.3        # legend text size
legend_inset <- c(-0.60, 0) # move legend in/out of plot area
legend_ncol <- 1         # legend columns (2 makes it shorter)
legend_x <- "topright"   # legend anchor position
# ----------------------------

out_png <- file.path(out_dir, "relative_abundance_bar.png")
png(out_png, width = max(800, n_samples * 80), height = 600, res = 150)

par(mar = c(8, 4, 3, 12), xpd = TRUE)

mat <- matrix(0, nrow = n_taxa, ncol = n_samples)
rownames(mat) <- taxa_order
colnames(mat) <- samples

for (r in seq_len(nrow(plot_data))) {
  s <- as.character(plot_data$sample[r])
  t <- as.character(plot_data$taxon[r])
  mat[t, s] <- plot_data$abundance[r]
}

barplot(
  mat,
  col = colors,
  border = NA,
  las = 2,
  cex.names = 0.7,
  ylab = "Relative Abundance",
  main = paste("Relative Abundance (Top", top_n, "Taxa)"),
  ylim = c(0, 1)
)

legend(
  legend_x,
  inset = legend_inset,
  legend = taxa_order,
  fill = colors,
  border = NA,
  cex = legend_cex,
  bty = "n",
  ncol = legend_ncol,
  title = "Taxa"
)

dev.off()

cat("[relative_abundance] Generated:", out_png, "\n")

out_csv <- file.path(out_dir, "relative_abundance_data.csv")
write.csv(plot_data[, c("sample", "taxon", "abundance")], out_csv, row.names = FALSE)
cat("[relative_abundance] Generated:", out_csv, "\n")

cat("[relative_abundance] Complete\n")

#!/usr/bin/env Rscript

# =============================================================================
# STaBioM R Postprocess: Stacked Bar Chart (Multi-Sample Comparison)
# Works with lr_meta, sr_meta (Kraken2), and sr_amp (QIIME2) outputs
# =============================================================================

suppressPackageStartupMessages({
  if (requireNamespace("jsonlite", quietly = TRUE)) {
    library(jsonlite)
  }
  if (requireNamespace("ggplot2", quietly = TRUE)) {
    library(ggplot2)
  }
  if (requireNamespace("dplyr", quietly = TRUE)) {
    library(dplyr)
  }
  if (requireNamespace("tidyr", quietly = TRUE)) {
    library(tidyr)
  }
  if (requireNamespace("RColorBrewer", quietly = TRUE)) {
    library(RColorBrewer)
  }
  if (requireNamespace("grid", quietly = TRUE)) {
    library(grid)
  }
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
  stop("Usage: stacked_bar.R --outputs_json <path> --out_dir <dir> [--params_json <json>] [--module <name>]")
}

# Load outputs.json
outputs <- fromJSON(outputs_json)
params <- tryCatch(fromJSON(params_json), error = function(e) list())

cat("[stacked_bar] Module:", module_name, "\n")
cat("[stacked_bar] Output dir:", out_dir, "\n")

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# Determine data source based on module type
data <- NULL
sample_col <- "sample_id"
taxon_col <- NULL
abundance_col <- NULL

# Try Kraken2 tidy outputs (lr_meta, sr_meta)
if (module_name %in% c("lr_meta", "sr_meta", "lr_amp") || is.null(module_name)) {
  postprocess_dir <- outputs$postprocess$dir
  if (!is.null(postprocess_dir)) {
    species_tidy <- file.path(postprocess_dir, "kraken_species_tidy.csv")
    genus_tidy <- file.path(postprocess_dir, "kraken_genus_tidy.csv")
    
    if (file.exists(species_tidy)) {
      data <- read.csv(species_tidy, stringsAsFactors = FALSE)
      taxon_col <- "species"
      abundance_col <- "fraction"
      cat("[stacked_bar] Using Kraken2 species data\n")
    } else if (file.exists(genus_tidy)) {
      data <- read.csv(genus_tidy, stringsAsFactors = FALSE)
      taxon_col <- "genus"
      abundance_col <- "fraction"
      cat("[stacked_bar] Using Kraken2 genus data\n")
    }
  }
}

# Try QIIME2 exports (sr_amp)
if (is.null(data) && (module_name == "sr_amp" || is.null(module_name))) {
  qiime2_exports <- outputs$qiime2_exports
  if (!is.null(qiime2_exports)) {
    table_tsv <- qiime2_exports$table_tsv
    taxonomy_tsv <- qiime2_exports$taxonomy_tsv
    
    if (!is.null(table_tsv) && file.exists(table_tsv) &&
        !is.null(taxonomy_tsv) && file.exists(taxonomy_tsv)) {
      cat("[stacked_bar] Using QIIME2 exports\n")
      
      # Read feature table (skip comment lines)
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
        
        # Parse taxonomy to get genus/species
        parse_taxon <- function(taxon) {
          if (is.na(taxon) || taxon == "") return("Unassigned")
          parts <- strsplit(taxon, ";")[[1]]
          parts <- trimws(gsub("^[a-z]__", "", parts))
          parts <- parts[parts != "" & !is.na(parts)]
          if (length(parts) == 0) return("Unassigned")
          tail(parts, 1)
        }
        
        tax_df$taxon <- vapply(tax_df$Taxon, parse_taxon, character(1))
        
        # Merge and reshape
        merged <- merge(table_df, tax_df[, c("FeatureID", "taxon")], by = "FeatureID")
        sample_cols <- setdiff(colnames(table_df), "FeatureID")
        
        if (length(sample_cols) > 0) {
          long_df <- pivot_longer(
            merged,
            cols = all_of(sample_cols),
            names_to = "sample_id",
            values_to = "count"
          )
          
          # Aggregate by sample and taxon
          agg <- long_df %>%
            group_by(sample_id, taxon) %>%
            summarise(count = sum(count), .groups = "drop")
          
          # Calculate fractions per sample
          agg <- agg %>%
            group_by(sample_id) %>%
            mutate(fraction = count / sum(count)) %>%
            ungroup()
          
          data <- as.data.frame(agg)
          taxon_col <- "taxon"
          abundance_col <- "fraction"
        }
      }
    }
  }
}

if (is.null(data) || nrow(data) == 0) {
  cat("[stacked_bar] No data found for stacked bar chart\n")
  quit(status = 0)
}

# Get parameters
top_n <- if (!is.null(params$top_n)) params$top_n else 15
rank_level <- if (!is.null(params$rank)) params$rank else "auto"

# Aggregate top taxa
top_taxa <- data %>%
  group_by(!!sym(taxon_col)) %>%
  summarise(total = sum(!!sym(abundance_col)), .groups = "drop") %>%
  arrange(desc(total)) %>%
  head(top_n) %>%
  pull(!!sym(taxon_col))

# Label others
data <- data %>%
  mutate(taxon_grouped = ifelse(!!sym(taxon_col) %in% top_taxa,
                                !!sym(taxon_col), "Other"))

# Aggregate with grouped taxa
plot_data <- data %>%
  group_by(sample_id, taxon_grouped) %>%
  summarise(abundance = sum(!!sym(abundance_col)), .groups = "drop")

# Order taxa by total abundance (Other last)
taxa_order <- plot_data %>%
  filter(taxon_grouped != "Other") %>%
  group_by(taxon_grouped) %>%
  summarise(total = sum(abundance), .groups = "drop") %>%
  arrange(desc(total)) %>%
  pull(taxon_grouped)

taxa_order <- c(taxa_order, "Other")
plot_data$taxon_grouped <- factor(plot_data$taxon_grouped, levels = rev(taxa_order))

# Generate color palette
n_colors <- length(unique(plot_data$taxon_grouped))
if (n_colors <= 12) {
  colors <- RColorBrewer::brewer.pal(max(3, n_colors), "Set3")
} else {
  colors <- colorRampPalette(RColorBrewer::brewer.pal(12, "Set3"))(n_colors)
}

# ----------------------------
# Legend sizing controls
# Change these to make the whole legend smaller/larger
# ----------------------------
legend_title_size <- 7
legend_text_size <- 5
legend_key_cm <- 0.10
legend_spacing_y_cm <- 0.05
legend_columns <- 1
# ----------------------------

# Create stacked bar chart
p <- ggplot(plot_data, aes(x = sample_id, y = abundance, fill = taxon_grouped)) +
  geom_bar(stat = "identity", position = "stack") +
  scale_fill_manual(values = colors) +
  labs(
    title = paste("Relative Abundance (Top", top_n, "Taxa)"),
    x = "Sample",
    y = "Relative Abundance",
    fill = "Taxon"
  ) +
  theme_minimal() +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    
    legend.position = "right",
    legend.title = element_text(size = legend_title_size),
    legend.text = element_text(size = legend_text_size),
    
    # Smaller legend boxes + tighter spacing
    legend.key.size = grid::unit(legend_key_cm, "cm"),
    legend.key.height = grid::unit(legend_key_cm, "cm"),
    legend.key.width = grid::unit(legend_key_cm, "cm"),
    legend.spacing.y = grid::unit(legend_spacing_y_cm, "cm"),
    
    # Reduce padding around legend
    legend.margin = margin(0, 0, 0, 0),
    legend.box.margin = margin(0, 0, 0, 0)
  ) +
  guides(
    fill = guide_legend(
      ncol = legend_columns,
      reverse = TRUE,
      keyheight = grid::unit(legend_key_cm, "cm"),
      keywidth = grid::unit(legend_key_cm, "cm")
    )
  )

# Save plot
out_file <- file.path(out_dir, "stacked_bar.png")
ggsave(out_file, p, width = 10, height = 7, dpi = 150)
cat("[stacked_bar] Saved:", out_file, "\n")

# Also save as PDF for publication quality
pdf_file <- file.path(out_dir, "stacked_bar.pdf")
ggsave(pdf_file, p, width = 10, height = 7)
cat("[stacked_bar] Saved:", pdf_file, "\n")

cat("[stacked_bar] Complete\n")

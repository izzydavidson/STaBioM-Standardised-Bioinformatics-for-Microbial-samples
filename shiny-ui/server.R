library(shiny)

server <- function(input, output, session) {
  
  rv <- reactiveValues(
    files = data.frame(
      id = character(),
      name = character(),
      datapath = character(),
      size_bytes = numeric(),
      stringsAsFactors = FALSE
    ),
    bound_delete_ids = character()
  )
  
  message_text <- reactiveVal("No messages yet.")
  
  id_counter <- reactiveVal(0)
  next_id <- function() {
    n <- id_counter() + 1
    id_counter(n)
    paste0("f", n)
  }
  
  add_uploads <- function(df) {
    if (is.null(df) || nrow(df) == 0) return()
    
    df$name <- as.character(df$name)
    df$datapath <- as.character(df$datapath)
    df$size <- as.numeric(df$size)
    
    new_rows <- data.frame(
      id = vapply(seq_len(nrow(df)), function(i) next_id(), character(1)),
      name = df$name,
      datapath = df$datapath,
      size_bytes = df$size,
      stringsAsFactors = FALSE
    )
    
    rv$files <- rbind(rv$files, new_rows)
  }
  
  register_delete_observer <- function(file_id) {
    if (file_id %in% rv$bound_delete_ids) return()
    
    rv$bound_delete_ids <- c(rv$bound_delete_ids, file_id)
    
    observeEvent(input[[paste0("del_", file_id)]], {
      rv$files <- rv$files[rv$files$id != file_id, , drop = FALSE]
    }, ignoreInit = TRUE)
  }
  
  observeEvent(input$sample_files, {
    add_uploads(input$sample_files)
  }, ignoreInit = TRUE)
  
  observeEvent(input$sample_dir, {
    add_uploads(input$sample_dir)
  }, ignoreInit = TRUE)
  
  output$upload_table <- renderUI({
    df <- rv$files
    
    if (is.null(df) || nrow(df) == 0) {
      return(div(class = "text-muted", "No files added yet."))
    }
    
    size_mb <- df$size_bytes / 1024^2
    size_display <- sprintf("%.1f MB", size_mb)
    
    lapply(df$id, register_delete_observer)
    
    rows <- lapply(seq_len(nrow(df)), function(i) {
      fid <- df$id[i]
      tags$tr(
        tags$td(df$name[i]),
        tags$td(size_display[i]),
        tags$td(
          actionButton(
            inputId = paste0("del_", fid),
            label = NULL,
            icon = icon("trash"),
            class = "btn btn-outline-danger btn-sm"
          )
        )
      )
    })
    
    tags$table(
      class = "table table-sm align-middle",
      tags$thead(
        tags$tr(
          tags$th("NAME"),
          tags$th("SIZE"),
          tags$th("")
        )
      ),
      tags$tbody(rows)
    )
  })
  
  output$upload_messages <- renderText({
    message_text()
  })
  
  observeEvent(input$validate_uploads, {
    df <- rv$files
    
    if (is.null(df) || nrow(df) == 0) {
      message_text("No files uploaded yet.")
      return()
    }
    
    allowed_ext <- c(
      "fastq", "fq", "gz",
      "fast5",
      "tsv", "csv", "txt",
      "json", "yaml", "yml"
    )
    
    ext <- tolower(sub(".*\\.", "", df$name))
    
    is_ok <- ext %in% allowed_ext |
      grepl("\\.fastq\\.gz$|\\.fq\\.gz$", tolower(df$name)) |
      grepl("\\.fastq$|\\.fq$|\\.fast5$", tolower(df$name))
    
    bad_files <- df$name[!is_ok]
    
    total_bytes <- sum(as.numeric(df$size_bytes), na.rm = TRUE)
    total_mb <- total_bytes / 1024^2
    
    msg <- c(
      paste0("Run label: ", ifelse(nzchar(input$run_label), input$run_label, "(none)")),
      paste0("Files uploaded: ", nrow(df)),
      paste0("Total size: ", sprintf("%.1f MB", total_mb))
    )
    
    if (length(bad_files) > 0) {
      msg <- c(
        msg, "",
        "Potentially unsupported files detected:",
        paste0(" - ", bad_files)
      )
    } else {
      msg <- c(msg, "", "All uploaded files look compatible with the current rules.")
    }
    
    message_text(paste(msg, collapse = "\n"))
  })
  
  observeEvent(input$run_pipeline, {
    script_path <- "./script.sh"
    
    if (!file.exists(script_path)) {
      message_text("script.sh was not found in the app directory.")
      return()
    }
    
    out <- tryCatch(
      system2("bash", script_path, stdout = TRUE, stderr = TRUE),
      error = function(e) paste("Error running script:", conditionMessage(e))
    )
    
    if (length(out) == 0) {
      message_text("Script ran, but produced no output.")
    } else {
      message_text(paste(out, collapse = "\n"))
    }
  })
}


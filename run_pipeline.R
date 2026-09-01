#!/usr/bin/env Rscript
# -----------------------------------------------------------------------------
# run_pipeline.R — run the whole analysis end to end, in order.
# -----------------------------------------------------------------------------
# Usage
#   Rscript run_pipeline.R              run every step
#   Rscript run_pipeline.R 3 4 5        run only the steps listed
#   Rscript run_pipeline.R --check      check prerequisites and exit
#
# Steps
#   0  create_word_lists.R                  build the diet/nutrition lexicon
#   1  01_import_subreddit_archives.qmd     read the four Arctic Shift archives
#   2  02_lemmatize_text_and_lexicon.qmd    udpipe lemmatization (slowest step)
#   3  03_select_diet_posts.qmd             match the lexicon, score diet centrality
#   4  04_analyse_diet_terms.qmd            rates, top terms, per-term contrast
#   5  05_semantic_network_analysis.qmd     co-occurrence network + permutation test
#   6  06_check_disambiguation_effect.R       disambiguation sensitivity check
#
# Steps must run in this order: each reads the file the previous one writes.
# Every step runs in a fresh R process, exactly as if run on its own, and the run
# stops at the first failure.
#
# The notebooks declare html, pdf and docx in their headers; this runner renders
# HTML only, so reproducing the analysis needs no LaTeX toolchain. Render a
# notebook by hand if you want the other formats.
#
# Prerequisites are described in README.md and verified by --check below.
# -----------------------------------------------------------------------------

steps <- data.frame(
  id   = 0:6,
  file = c("create_word_lists.R",
           "01_import_subreddit_archives.qmd",
           "02_lemmatize_text_and_lexicon.qmd",
           "03_select_diet_posts.qmd",
           "04_analyse_diet_terms.qmd",
           "05_semantic_network_analysis.qmd",
           "06_check_disambiguation_effect.R"),
  what = c("Build the diet/nutrition lexicon",
           "Import the four subreddit archives",
           "Lemmatize post text and lexicon (slow)",
           "Select diet posts and score centrality",
           "Diet-term frequencies and disease contrast",
           "Semantic network and permutation test",
           "Disambiguation sensitivity check"),
  stringsAsFactors = FALSE
)

pkgs <- c("anonymizer", "arrow", "broom", "ggraph", "ggrepel", "here", "igraph",
          "jsonlite", "knitr", "readr", "rlang", "scales", "stringi", "tibble",
          "tidygraph", "tidytext", "tidyverse", "udpipe", "widyr")

args      <- commandArgs(trailingOnly = TRUE)
check_only <- "--check" %in% args
wanted     <- suppressWarnings(as.integer(args[args != "--check"]))
wanted     <- wanted[!is.na(wanted)]
if (length(wanted) == 0) wanted <- steps$id

rule <- function(ch = "-") cat(strrep(ch, 78), "\n", sep = "")
fail <- function(...) { cat("\n  FAILED: ", ..., "\n", sep = ""); quit(status = 1) }

# --- preflight ---------------------------------------------------------------
rule("=")
cat("Myositis & diet pipeline\n")
rule("=")

if (!file.exists("config.R")) {
  fail("config.R not found.\n",
       "  Copy config_template.R to config.R and set DATA_PATH and REDDIT_DATA_PATH.\n",
       "  config.R is gitignored: paths are local to your machine.")
}
source("config.R")

for (v in c("DATA_PATH", "REDDIT_DATA_PATH")) {
  if (!exists(v) || !nzchar(get(v))) fail(v, " is not set in config.R.")
  if (!dir.exists(get(v)))           fail(v, " points at a directory that does not exist:\n  ", get(v))
}

# The archives script 1 reads. Four subreddits, posts + comments for each.
archive_dirs <- file.path(REDDIT_DATA_PATH, "subreddits/data",
                          c("myositis", "muscular_dystrophy"))
n_archives <- sum(vapply(archive_dirs, function(d)
  length(list.files(d, pattern = "\\.jsonl$", recursive = TRUE)), integer(1)))
if (n_archives == 0) {
  fail("no .jsonl archives found under:\n  ", paste(archive_dirs, collapse = "\n  "),
       "\n  See README.md for how to obtain them from Arctic Shift.")
}

missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
  fail("missing R packages: ", paste(missing, collapse = ", "),
       "\n  install.packages(c(", paste0('"', missing, '"', collapse = ", "), "))")
}

if (!nzchar(Sys.which("quarto"))) {
  fail("quarto not found on PATH. See https://quarto.org/docs/get-started/")
}

cat("config.R           ok\n")
cat("DATA_PATH          ", DATA_PATH, "\n", sep = "")
cat("REDDIT_DATA_PATH   ", REDDIT_DATA_PATH, "\n", sep = "")
cat("archives found     ", n_archives, " .jsonl files\n", sep = "")
cat("R packages         all ", length(pkgs), " present\n", sep = "")
cat("quarto             ", trimws(system2("quarto", "--version", stdout = TRUE)), "\n", sep = "")

if (check_only) { cat("\nPrerequisites OK. Nothing was run (--check).\n"); quit(status = 0) }

# --- run ---------------------------------------------------------------------
todo <- steps[steps$id %in% wanted, ]
cat("\nRunning steps: ", paste(todo$id, collapse = ", "), "\n", sep = "")

timings <- numeric(0)
for (i in seq_len(nrow(todo))) {
  s <- todo[i, ]
  cat("\n"); rule()
  cat(sprintf("Step %d  %s\n        %s\n", s$id, s$file, s$what))
  rule()

  if (!file.exists(s$file)) fail("file not found: ", s$file)

  t0 <- Sys.time()
  status <- if (grepl("\\.qmd$", s$file)) {
    system2("quarto", c("render", shQuote(s$file), "--to", "html"))
  } else {
    system2("Rscript", shQuote(s$file))
  }
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

  if (!identical(status, 0L)) fail("step ", s$id, " (", s$file, ") exited with status ", status)
  timings[as.character(s$id)] <- elapsed
  cat(sprintf("\n  step %d done in %.0f s\n", s$id, elapsed))
}

cat("\n"); rule("=")
cat("All steps completed.\n")
for (id in names(timings)) {
  cat(sprintf("  step %-2s %6.0f s   %s\n", id, timings[[id]], steps$file[steps$id == as.integer(id)]))
}
cat(sprintf("  %-9s %6.0f s   total\n", "", sum(timings)))
rule("=")
cat("\nOutputs are written under DATA_PATH (data/, word_lists/, figures/);\n",
    "rendered notebooks stay next to the .qmd files. Both are gitignored.\n", sep = "")

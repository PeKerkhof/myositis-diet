# -----------------------------------------------------------------------------
# 06_check_disambiguation_effect.R
# -----------------------------------------------------------------------------
# Sensitivity check: what does disambiguate_diet_terms() actually remove from the
# corpus, and what does that do to the per-term MD-vs-Myositis contrast?
#
# This is check 1 of the three robustness checks reported in the manuscript. The
# other two — the focal-set repeat and the diet-focus cut-off ladder — live in
# 04_analyse_diet_terms.qmd, sections 6a and 6c, and regenerate on every render.
#
# Reports:
#   1. Non-dietary fraction per lexicon term, overall and by disease group
#   2. Per-term disease contrast before vs after disambiguation
#   3. Which terms change significance, and the headline terms side by side
#
# TWO DESIGN RULES KEEP THESE NUMBERS IN STEP WITH THE PIPELINE
#   - The normalization rules are SOURCED from 02_lemmatize_text_and_lexicon.qmd,
#     never copied, so this script cannot drift out of sync with them. Same for
#     the per-term test, sourced from 04_analyse_diet_terms.qmd.
#   - The non-dietary fraction is measured by DIFFING the text before and after
#     disambiguate_diet_terms(), not against a hardcoded list of clinical
#     neighbours. Every term the function touches is covered automatically, and
#     editing a rule updates these numbers on the next run. A hardcoded neighbour
#     list would silently keep reporting the fraction the OLD rules removed.
#
# Runs off the SAVED udpipe annotations (myo_dys_subreddits_udpipe_annotations
# .feather), so it takes ~1 minute rather than re-running the slow udpipe pass.
# Read-only: writes nothing back into the pipeline.
#
# Usage:  Rscript 06_check_disambiguation_effect.R
#         (or as step 6 of run_pipeline.R)
# -----------------------------------------------------------------------------

if (!isTRUE(l10n_info()[["UTF-8"]])) {
  invisible(suppressWarnings(Sys.setlocale("LC_CTYPE", "en_US.UTF-8")))
}

suppressMessages({
  library(tidyverse); library(arrow); library(tidytext); library(here); library(stringi)
})
source(here("config.R"))

# --- source a named chunk out of a .qmd, so nothing is duplicated here --------
source_qmd_chunk <- function(qmd_path, label, envir = parent.frame()) {
  lines  <- readLines(qmd_path, warn = FALSE)
  lab    <- grep(paste0("^#\\|\\s*label:\\s*", label, "\\s*$"), lines)
  if (length(lab) != 1L) {
    stop("chunk '", label, "' not found (or not unique) in ", basename(qmd_path),
         " — has the chunk been renamed?", call. = FALSE)
  }
  opens  <- grep("^```\\{r", lines)
  closes <- grep("^```\\s*$", lines)
  body   <- lines[(max(opens[opens < lab]) + 1L):(min(closes[closes > lab]) - 1L)]
  eval(parse(text = body), envir = envir)
  invisible(TRUE)
}

qmd_02 <- here("02_lemmatize_text_and_lexicon.qmd")
qmd_04 <- here("04_analyse_diet_terms.qmd")

# --- rebuild the lemmatized text, stopping short of disambiguation -----------
# Chunks 'define-term-normalization', 'postprocess-lemmas' and
# 'compound-term-merging' are script 02 verbatim; we simply do not run the
# 'disambiguate-polysemous-terms' chunk that normally follows, and we substitute
# the saved annotations for the live udpipe call.
df <- arrow::read_feather(
  file.path(DATA_PATH, "data/myo_dys_subreddits_2005_jul2026.feather")
)
x_df <- arrow::read_feather(
  file.path(DATA_PATH, "data/myo_dys_subreddits_udpipe_annotations.feather")
)
cat("Corpus:", scales::comma(nrow(df)), "posts |",
    scales::comma(nrow(x_df)), "annotated tokens\n\n")

source_qmd_chunk(qmd_02, "define-term-normalization")

# doc_id is assigned in script 02's 'lemmatize-text' chunk, which we cannot source
# because it also calls udpipe_annotate(). This is the one line copied from it; the
# sanity check below will fail loudly if the ids ever stop lining up.
if (!"doc_id" %in% names(df)) df$doc_id <- as.character(seq_len(nrow(df)))

source_qmd_chunk(qmd_02, "postprocess-lemmas")
source_qmd_chunk(qmd_02, "compound-term-merging")

stages <- df |>
  select(doc_id, disease_type, naive = lemmatized_text) |>
  mutate(disambiguated = disambiguate_diet_terms(naive))

# --- sanity check: does the rebuild reproduce the saved pipeline output? ------
saved <- arrow::read_feather(
    file.path(DATA_PATH, "data/myo_dys_subreddits_lemmatized_2005_jul2026.feather")
  ) |>
  select(doc_id, saved_text = lemmatized_text)

chk <- stages |> inner_join(saved, by = join_by(doc_id))
agree <- mean(chk$disambiguated == chk$saved_text, na.rm = TRUE)
cat(sprintf("== SANITY CHECK ==\n%s posts compared | identical to saved pipeline output: %.2f%%\n",
            scales::comma(nrow(chk)), 100 * agree))
if (agree < 1) {
  warning("Rebuild does not exactly reproduce the saved lemmatized feather. ",
          "Either the feather is stale, or script 02 changed after it was written. ",
          "Re-render 02 before trusting the numbers below.", call. = FALSE)
}

diet_terms_lemmatized <- readRDS(file.path(DATA_PATH, "word_lists/diet_terms_lemmatized.RDS"))

# --- 1. non-dietary fraction per term, measured as a before/after diff --------
# No hardcoded neighbour lists: whatever disambiguate_diet_terms() strips is what
# gets counted, so this stays correct when the rules change.
term_counts <- function(col) {
  stages |>
    select(doc_id, disease_type, text = all_of(col)) |>
    filter(!is.na(text)) |>
    unnest_tokens(word, text) |>
    inner_join(diet_terms_lemmatized, by = join_by(word)) |>
    summarise(n = n(), .by = c(word, disease_type))
}

removal <- full_join(
    term_counts("naive")         |> rename(n_before = n),
    term_counts("disambiguated") |> rename(n_after  = n),
    by = join_by(word, disease_type)
  ) |>
  mutate(across(c(n_before, n_after), \(x) replace_na(x, 0L))) |>
  summarise(
    before  = sum(n_before),
    after   = sum(n_after),
    removed = sum(n_before) - sum(n_after),
    md_before  = sum(n_before[disease_type == "Muscular Dystrophy"]),
    md_removed = sum(n_before[disease_type == "Muscular Dystrophy"]) -
                 sum(n_after[disease_type == "Muscular Dystrophy"]),
    myo_before  = sum(n_before[disease_type == "Myositis"]),
    myo_removed = sum(n_before[disease_type == "Myositis"]) -
                  sum(n_after[disease_type == "Myositis"]),
    .by = word
  ) |>
  filter(removed > 0) |>
  mutate(
    # a term with no occurrences in one group yields NA, not NaN, so the column
    # reads as "not applicable" rather than as a failed calculation
    pct_nondietary     = round(100 * removed / before, 1),
    pct_nondietary_md  = if_else(md_before  > 0, round(100 * md_removed  / md_before,  1), NA_real_),
    pct_nondietary_myo = if_else(myo_before > 0, round(100 * myo_removed / myo_before, 1), NA_real_)
  ) |>
  arrange(desc(pct_nondietary))

cat("\n== 1. NON-DIETARY FRACTION PER TERM ==\n")
cat("Occurrences removed by disambiguate_diet_terms(), i.e. matches sitting next to a\n",
    "clinical or idiomatic neighbour. Every term the function touches appears here.\n\n", sep = "")
removal |>
  select(word, occurrences = before, removed, `% non-dietary` = pct_nondietary,
         `% MD` = pct_nondietary_md, `% Myositis` = pct_nondietary_myo) |>
  print(n = Inf)

# --- 2. per-term disease contrast, before vs after ---------------------------
source_qmd_chunk(qmd_04, "signature-terms-helpers")  # custom_stop_words, term_disease_split()

diet_posts_at <- function(col) {
  txt <- stages |> select(doc_id, disease_type, lemmatized_text = all_of(col))
  hits <- txt |>
    select(doc_id, text = lemmatized_text) |>
    filter(!is.na(text)) |>
    unnest_tokens(word, text) |>
    inner_join(diet_terms_lemmatized, by = join_by(word))
  txt |> filter(doc_id %in% unique(hits$doc_id))
}

run_stage <- function(col, label) {
  posts <- diet_posts_at(col)
  res   <- term_disease_split(posts, diet_terms_lemmatized, custom_stop_words)
  cat(sprintf("%-34s diet posts: %5s | terms tested: %2d | baseline: %.1f%% MD | significant: %2d\n",
              label, scales::comma(nrow(posts)), nrow(res),
              100 * res$baseline_md[1], sum(res$sig)))
  res
}

cat("\n== 2. PER-TERM DISEASE CONTRAST, BEFORE vs AFTER ==\n")
r_naive <- run_stage("naive",         "Naive lexicon (no disambiguation)")
r_curr  <- run_stage("disambiguated", "Disambiguated (pipeline as run)")

# --- 3. what actually changed ------------------------------------------------
cmp <- full_join(
  r_naive |> select(word, md_n = MD, myo_n = Myositis, pct_n = pct_md, adjp_n = q_value, sig_n = sig),
  r_curr  |> select(word, md_c = MD, myo_c = Myositis, pct_c = pct_md, adjp_c = q_value, sig_c = sig),
  by = join_by(word)
)

cat("\n== 3. TERMS WHOSE SIGNIFICANCE CHANGED ==\n")
changed <- cmp |>
  filter(is.na(sig_n) | is.na(sig_c) | sig_n != sig_c) |>
  transmute(
    word,
    naive   = sprintf("%d/%d  adj.p=%.3g", md_n, myo_n, adjp_n),
    current = sprintf("%d/%d  adj.p=%.3g", md_c, myo_c, adjp_c),
    change  = case_when(
      is.na(sig_n) ~ "absent from naive set",
      is.na(sig_c) ~ "absent from disambiguated set",
      sig_n & !sig_c ~ "LOST significance",
      TRUE           ~ "GAINED significance"
    )
  )
if (nrow(changed) == 0) cat("(none)\n") else print(changed, n = Inf)

headline <- c("creatine", "antioxidant", "carb", "calorie",
              "folicacid", "gluten", "probiotic", "curcumin")
cat("\n== 4. HEADLINE TERMS, BEFORE vs AFTER ==\n")
cmp |>
  filter(word %in% headline) |>
  transmute(word,
            naive = sprintf("%d/%d  %.1f%%  adj.p=%.2g%s", md_n, myo_n, 100*pct_n, adjp_n, if_else(sig_n, " *", "")),
            current = sprintf("%d/%d  %.1f%%  adj.p=%.2g%s", md_c, myo_c, 100*pct_c, adjp_c, if_else(sig_c, " *", ""))) |>
  arrange(match(word, headline)) |>
  print(n = Inf)

cat(sprintf("\nAll %d headline terms significant before and after: %s\n",
            length(headline),
            all(cmp$sig_n[cmp$word %in% headline] & cmp$sig_c[cmp$word %in% headline])))

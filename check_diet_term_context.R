# -----------------------------------------------------------------------------
# check_diet_term_context.R
# -----------------------------------------------------------------------------
# Diagnostic for the diet/nutrition lexicon: how does each matched term actually
# appear in context, and which terms are polysemous (used in NON-nutrition senses
# in a muscle-disease corpus, e.g. "small fiber neuropathy", "fatty infiltration",
# "sodium channel", "grain of salt")?
#
# Two views:
#   collocates(term)  - words most often immediately before/after the term
#   kwic_term(term)   - keyword-in-context samples to eyeball usage
#   fp(term, ...)     - measured non-dietary fraction, overall and by disease
#
# The matching in the pipeline is on lemmatized_text, so that is the primary
# field here; set `field = "text"` to inspect the raw text instead. Findings from
# this script feed disambiguate_diet_terms() in 02_lemmatize_text_and_lexicon.qmd.
# -----------------------------------------------------------------------------

# Keep non-ASCII characters (>=, em-dash) intact in figures and printed output.
# Running from a bare terminal can start R in a non-UTF-8 locale, which silently
# turns them into "<U+2265>" in plot labels and console output. RStudio already
# sets a UTF-8 locale, so this is only a safety net for terminal/CI runs.
if (!isTRUE(l10n_info()[["UTF-8"]])) {
  invisible(suppressWarnings(Sys.setlocale("LC_CTYPE", "en_US.UTF-8")))
}

suppressMessages({
  library(tidyverse); library(arrow); library(tidytext); library(here)
})
source(here("config.R"))

df_diet <- read_feather(
  file.path(DATA_PATH, "data/myo_dys_subreddits_diet_posts_2005_jul2026.feather")
)
diet_terms <- readRDS(file.path(DATA_PATH, "word_lists/diet_terms_lemmatized.RDS"))$word

# Tokenise the chosen field WITH position, so neighbours can be recovered exactly
# as the matcher sees them.
build_neighbours <- function(field = c("lemmatized_text", "text")) {
  field <- match.arg(field)
  df_diet |>
    select(doc_id, disease_type, txt = all_of(field)) |>
    filter(!is.na(txt)) |>
    unnest_tokens(word, txt) |>
    mutate(prev = lag(word), nxt = lead(word), .by = doc_id)
}
nbr <- build_neighbours("lemmatized_text")

# --- collocates: top preceding / following words -----------------------------
collocates <- function(term, k = 10) {
  s <- nbr |> filter(word == term)
  cat(sprintf("\n== %s (n = %d) ==\n", term, nrow(s)))
  fmt <- \(col) s |> count({{ col }}, sort = TRUE) |> drop_na() |> head(k) |>
    (\(d) paste(sprintf("%s(%d)", d[[1]], d$n), collapse = ", "))()
  cat("  prev:", fmt(prev), "\n  next:", fmt(nxt), "\n")
}

# --- keyword-in-context (uses raw text for readable phrasing) -----------------
kwic_term <- function(term, window = 4, n = 15, disease_group = NULL) {
  requireNamespace("quanteda", quietly = TRUE)
  corp <- quanteda::corpus(df_diet$text, docvars = df_diet |> select(disease_type))
  toks <- quanteda::tokens(corp, remove_punct = TRUE)
  k <- quanteda::kwic(toks, pattern = term, window = window) |> as_tibble() |>
    left_join(tibble(docname = quanteda::docnames(corp),
                     disease = quanteda::docvars(corp)$disease_type), by = "docname")
  if (!is.null(disease_group)) k <- filter(k, disease == disease_group)
  k |> slice_sample(n = min(n, nrow(k))) |>
    transmute(disease, context = paste0("…", pre, "  [", keyword, "]  ", post, "…"))
}

# --- measured non-dietary fraction (define bad neighbours per term) -----------
fp <- function(term, bad_prev = character(), bad_next = character()) {
  s <- nbr |> filter(word == term) |>
    mutate(bad = (prev %in% bad_prev) | (nxt %in% bad_next))
  if (nrow(s) == 0) { cat(sprintf("%-10s : 0 occurrences\n", term)); return(invisible()) }
  by <- s |> summarise(n = n(), bad = sum(bad), .by = disease_type) |> arrange(disease_type)
  cat(sprintf("%-10s total=%3d non-diet=%3d (%4.1f%%) | %s\n",
              term, nrow(s), sum(s$bad), 100 * mean(s$bad),
              paste(sprintf("%s %d/%d(%.0f%%)", by$disease_type, by$bad, by$n,
                            100 * by$bad / by$n), collapse = "  ")))
}

# --- default report: scan the known-polysemous terms -------------------------
if (sys.nframe() == 0) {
  suspects <- c("fiber", "fast", "fat", "creatine", "protein", "calcium", "sodium",
                "potassium", "oil", "sugar", "salt", "raw", "seed", "plant", "chicken")
  walk(suspects, collocates)

  cat("\n---- non-dietary fraction on lemmatized_text ----\n")
  fp("fiber",  bad_prev = c("small","single","muscle","nerve","carbon","motor","sensory","atrophic","twitch","type","ii","iia","iib"),
               bad_next = c("neuropathy","emg","polyneuropathy","biopsy","density"))
  fp("fat",    bad_prev = c("edema","atrophy","fibrous","replace"),
               bad_next = c("infiltration","infiltrate","deposit","deposits","tissue","replacement","cell","cells","pad"))
  fp("calcium",bad_next = c("deposit","deposits","channel","channels","dysregulation"))
  fp("sodium", bad_next = c("channel","channels","channelopathy","channelopathies"))
  fp("oil",    bad_prev = c("snake","cbd","cb","essential","castor","cannabis","lavender","oregano"))
  fp("sugar",  bad_prev = c("blood"), bad_next = c("coat"))
  fp("salt",   bad_prev = c("epsom","bath","grain"), bad_next = c("bath","baths"))
}

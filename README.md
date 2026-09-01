# Patient perspectives on nutrition in idiopathic inflammatory myopathies

Analysis code for a study of how two patient communities discuss diet and nutrition on Reddit:
**myositis** (idiopathic inflammatory myopathies) and **muscular dystrophy**. The study uses a
bounded, subreddit-only corpus and compares the two groups on how prominent nutrition is in their
discussions and on which dietary terms distinguish them.

This repository contains **code only**. Reddit's terms of service do not permit redistribution of
the post data, so the corpus is not included here; the section on *Data* below describes how to
obtain it and reconstruct the exact sample.

## The comparison

| Group | Subreddits |
|---|---|
| Myositis | r/Myositis, r/dermatomyositis |
| Muscular dystrophy | r/MuscularDystrophy, r/FSHD |

r/polymyositis is not included: no Arctic Shift archive exists for it. The corpus is roughly 80%
muscular dystrophy, so the per-term disease baseline is ~81% MD — a diet term only "leans" toward a
group if it beats what corpus composition alone predicts.

## Quick start

```bash
cp config_template.R config.R     # then edit the two paths inside
Rscript run_pipeline.R --check    # verify prerequisites, run nothing
Rscript run_pipeline.R            # run everything, start to finish
```

`run_pipeline.R` runs each step in a fresh R process and stops at the first failure. A full run
takes about 10 minutes, almost all of it the udpipe lemmatization in step 2. Individual steps can be
run on their own, in order, with `Rscript run_pipeline.R 3 4 5`.

The notebooks declare `html`, `pdf` and `docx` output; the runner renders HTML only, so reproducing
the analysis needs no LaTeX toolchain.

## Pipeline

| Step | File | What it does |
|---|---|---|
| 0 | `create_word_lists.R` | Builds the diet/nutrition lexicon from a PICO intervention taxonomy |
| 1 | `01_import_subreddit_archives.qmd` | Reads the four Arctic Shift archives, groups them into `disease_type`, parses timestamps (UTC), classifies post types, anonymizes authors (CRC32) |
| 2 | `02_lemmatize_text_and_lexicon.qmd` | Lemmatizes post text and lexicon with udpipe (english-ewt); normalizes related lemmas; merges compound terms; strips polysemous clinical uses |
| 3 | `03_select_diet_posts.qmd` | Matches tokens against the lexicon, flags diet posts, computes length-adjusted diet centrality |
| 4 | `04_analyse_diet_terms.qmd` | Post- and thread-level prevalence, top terms by group, per-term disease contrast, robustness ladder |
| 5 | `05_semantic_network_analysis.qmd` | Diet-term co-occurrence network, Louvain communities, disease-composition permutation test |
| 6 | `06_check_disambiguation_effect.R` | Sensitivity check: what disambiguation removes, and its effect on the contrast |

Steps must run in this order — each reads what the previous one writes. Data files carry the
data-end date in their name (`..._2005_jul2026.feather`); **rename them when the archive is
refreshed**, or a later step will silently read an older file.

### Notes on two design choices

**Diet centrality** (step 3) separates posts where diet is the topic from posts that mention it in
passing. Diet density (diet-term occurrences / post length) is weighted by the log of the number of
distinct diet terms, then regressed on log post length; the residual is the length-adjusted score. A
positive residual defines the **focal set** used for the network and the sensitivity analyses.

**The semantic network is descriptive, not confirmatory.** Community structure is sensitive to the
edge and node thresholds and to Louvain's stochasticity, so the network shows how the vocabulary is
organized while the disease contrast rests on the term-level comparison in step 4. Community labels
are assigned from signature terms rather than from Louvain's community numbers, which are not stable
across runs.

## Outputs and where they appear in the manuscript

Everything is written under `DATA_PATH/figures/`.

| Output | Manuscript |
|---|---|
| `fig1_sub_diet_thread_rate_by_size.png` | Figure 1A |
| `fig2_sub_top20_diet_terms_by_disease.png` | Figure 1B |
| `fig4_sub_diet_term_frequency_md_vs_myo.png` | Figure 1C |
| `fig5_sub_semantic_network_diet_only_communities.png` | Figure 2A |
| `fig6_sub_semantic_network_diet_only.png` | Figure 2B |
| `fig3_sub_diet_terms_disease_split_all.png` | Supplementary Figure S1 |
| `sub_diet_terms_cutoff_robustness.csv` | Supplementary Table 3 |
| `sub_diet_community_nodes.csv`, `sub_diet_community_summary.csv` | Community partition behind Figure 2A |
| `figA1_sub_*` (2 files) | Focal-set sensitivity; not printed in the manuscript, but these back the reported sensitivity figures |

Supplementary Tables 1 and 2 are printed by step 4 (sections 4 and 6b) rather than exported.

## Sensitivity checks

The manuscript reports three. Two live inside step 4 and regenerate on every render: the focal-set
repeat (§6a) and the diet-focus cut-off ladder (§6c). The third is a standalone script:

- **`06_check_disambiguation_effect.R`** — measures how much of each lexicon term was non-dietary, and
  how the per-term contrast changes before and after disambiguation. It rebuilds the lemmatized text
  from the saved udpipe annotations, so it runs in about a minute without re-annotating, and it
  sources its rules from steps 2 and 4 rather than copying them.

There is also `check_diet_term_context.R`, a development diagnostic that inspects how each lexicon
term appears in context (collocates, keyword-in-context). Its findings shaped the disambiguation
rules in step 2. It reads the already-disambiguated corpus, so use
`06_check_disambiguation_effect.R` for before/after measurements.

## Requirements

- R ≥ 4.3 (for the native pipe `|>`)
- [Quarto](https://quarto.org/docs/get-started/)

```r
install.packages(c(
  "anonymizer", "arrow", "broom", "ggraph", "ggrepel", "here", "igraph",
  "jsonlite", "knitr", "readr", "rlang", "scales", "stringi", "tibble",
  "tidygraph", "tidytext", "tidyverse", "udpipe", "widyr"
))
```

`check_diet_term_context.R` additionally needs `quanteda`. `run_pipeline.R --check` verifies the
whole list and reports anything missing.

The udpipe english-ewt model is downloaded automatically on first run to `DATA_PATH/udpipe/`.

## Configuration

Copy `config_template.R` to `config.R` and set two paths. `config.R` is gitignored, so local paths
never reach the repository.

```r
REDDIT_DATA_PATH <- "/path/to/reddit-data-hub"          # where the subreddit archives live
DATA_PATH        <- "/path/to/myositis-diet-data"        # where outputs are written
```

Step 1 reads the archives from `REDDIT_DATA_PATH/subreddits/data/{myositis,muscular_dystrophy}/`,
as `.jsonl` files. Outputs are written under `DATA_PATH`:

```
myositis-diet-data/
├── data/          # feather files produced by steps 1-3
├── word_lists/    # the diet lexicon, built by step 0
├── figures/       # figures and exported tables
└── udpipe/        # udpipe model (downloaded on first run)
```

## Data

The corpus is the complete public post history of the four subreddits, retrieved from the
[Arctic Shift](https://github.com/ArthurHeitmann/arctic_shift) archives on **15 July 2026**. Posts
from the retrieval day itself were dropped, so the corpus ends on the last complete day,
**14 July 2026**. Submissions, comments and replies are all retained and distinguished by
`post_type`.

Reddit's terms of service do not permit redistribution of the raw data, so it is not included here.
The sample can be reconstructed exactly from the Arctic Shift archives using the four subreddits and
the cut-off date above.

### Reproduction check

A correct run against the 14 July 2026 corpus produces:

| | |
|---|---|
| Corpus | 39,027 posts, 5,348 author accounts, 2012-01-13 to 2026-07-14 |
| Diet posts | 2,985 (7.6%), from 6,878 term matches |
| Threads | 1,408 diet threads of 5,013 (28.1%) |
| Focal set | 891 posts |
| Per-term test | 65 terms tested, 81.6% MD baseline, 12 significant after BH |
| Network | 45 nodes, 103 edges, modularity 0.462, permutation p = 0.647 |

These will change if the archive is refreshed — the corpus grows over time. Read the numbers off
your own run rather than quoting them from here.

## Privacy and ethics

- Author names are anonymized by CRC32 hashing before analysis.
- The data are public, but are handled under research-ethics guidelines; verbatim post text is not
  reproduced in any output.
- No post data or personally identifying information is committed to version control.
- Ethics approval: Faculty of Social Sciences and Humanities, Vrije Universiteit Amsterdam.

## Citation

If you use this code, please cite the accompanying paper: Kerkhof P, Talreja T, Kobert L, Gupta L.
*Patient perspectives on nutrition in idiopathic inflammatory myopathies: an analysis of Reddit
discussions.*

## Contact

Questions about the analysis: open an issue, or contact the repository owner.

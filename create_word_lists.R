# =============================================================================
# create_word_lists.R — build the diet/nutrition lexicon for the myositis-diet
# pipeline.
#
# PROVENANCE (reconstructed 2026-07-21 — correct if the original derivation differed)
# -----------------------------------------------------------------------------
# The base list `dietary_intervention_terms` is the Intervention ("I") arm of a
# PICO question for diet & muscle health: a structured nutrition-intervention
# taxonomy grouped into macronutrients, carbohydrates, fats, micronutrients,
# supplements, probiotics, polyphenols, dietary patterns, fasting regimens, and
# lifestyle factors. It was drafted from that PICO intervention concept, expanded
# (the inline "# synonym / variant / full name" notes record that expansion,
# apparently LLM-assisted), and hand-curated. There is no separate protocol or
# search-strategy document — this script is the source of record for the lexicon.
#
# DERIVATION
# -----------------------------------------------------------------------------
#   dietary_intervention_terms   PICO intervention taxonomy (multi-word phrases)
#     -> single_diet_terms       decomposed into single words + inflections;
#                                this is what the token matcher actually uses
#     -> lemma_map               single terms grouped into ~80 semantic categories
#
# OUTPUTS (written to DATA_PATH/word_lists/):
#   diet_terms.RDS                  union of the two term lists
#   single_diet_terms.RDS           single-word terms
#   dietary_intervention_terms.RDS  the PICO intervention phrases
#   lemma_map_diet.RDS              semantic grouping
#
# DOWNSTREAM: script 02 lemmatizes single_diet_terms.RDS into
# diet_terms_lemmatized.RDS; script 03 matches that against post tokens to select
# diet posts. This lexicon is therefore the root of every diet result in the paper.
# =============================================================================

rm(list=ls());cat("\014")
library(tidyverse)
library(here)

# Write outputs to the external data hub (DATA_PATH/word_lists/), the same
# location every downstream script reads from. config.R is gitignored; copy
# config_template.R to config.R and set DATA_PATH before running.
source(here::here("config.R"))

dietary_intervention_terms <- c(
  # general terms
  "diet",
  "diets",
  "dieting",
  "food",
  "foods",
  "eat",
  "eating",
  "consume",
  "consuming",
  "meal",
  "meals",
  "snack",
  "snacks",
  "ingredient",
  "ingredients",
  "nutrition",
  "nutritional",
  "nutrients", # General term for both macro and micro
  "healthy eating",
  "unhealthy eating",
  "clean eating", # Common informal term
  "meal plan",
  "meal planning",
  "cook",
  "cooking",
  "recipe",
  "recipes",
  "calories",
  "carbs", # Common short form for carbohydrates
  "junk food", # Common informal term
  "whole foods", # Common term for a type of food approach
  
  # Macronutrients
  "Macronutrients",
  "protein",
  "Proteins",
  "High protein diets",
  "High protein diet",
  "Low protein diets",
  "Low protein diet",
  "Casein-free diet",
  "Protein supplements",
  "Whey",
  "Pea protein", # More specific than just "Pea"
  "Soy protein", # More specific than just "Soy"
  "Casein",
  "Amino acids",
  "Leucine",
  "BCAAs",
  "Branched-Chain Amino Acids",
  "Glutamine",
  "HMB",
  "beta-Hydroxy beta-Methylbutyrate", # Full name
  "Hydroxy Methylbutyrate", # Common alternative spelling
  "Creatine",
  
  # Carbohydrates
  "Carbohydrates",
  "Carbohydrate-restricted diet",
  "Carbohydrate-restricted diets",
  "High-carbohydrate diets",
  "High-carbohydrate diet",
  "FODMAP",
  "Lactose-free diet",
  "Lactose-free diets",
  "High fructose diet",
  "High sugar content food",
  "High sugar food", # Common variation
  "High sugar foods", # Common variation
  
  # Fats
  "Fats",
  "High saturated fat diet",
  "High saturated fat diets",
  "Trans-fat diet",
  "Trans-fat diets",
  "Ketogenic diet",
  "Ketogenic diets",
  "High-fat diet",
  "High-fat diets",
  "Omega-6 fatty acids",
  "Omega-3 fatty acids",
  "Fish oils",
  "Fish oil",
  
  # Micronutrients
  "Micronutrients",
  "Vitamin A",
  "Vitamin C",
  "Vitamin D",
  "Vitamin E",
  "Vitamin B9",
  "Folic Acid",
  "Calcium",
  "Zinc",
  "Magnesium",
  "Potassium",
  "Selenium",
  "Biotin",
  
  # Supplements / Other Nutritional Compounds
  "Anti-inflammatory Supplements",
  "Antioxidant Supplements",
  "Turmeric",
  "Curcumin",
  "Ginger",
  "Antioxidants",
  "CoQ10",
  "Green tea",
  "Black tea",
  "Dark chocolate",
  "Herbs",
  "Spices",
  "Herbs and spices",
  "Berries",
  "Citrus fruits",
  "Red wine",
  "Legumes",
  "Purple grapes",
  "Nuts",
  "Seeds",
  "Nuts and seeds",
  "Isoflavones",
  
  # Probiotic-Related
  "Prebiotics",
  "Probiotics",
  "Synbiotics",
  "Postbiotics",
  
  # Polyphenol-rich Foods & Extracts
  "Polyphenols", # Base term
  "Polyphenol-rich foods",
  "Polyphenol-rich juices",
  "Polyphenol-rich concentrates",
  
  # Miscellaneous Supplements
  "Red yeast rice",
  "Soy", # Included again as it appears under a different category
  "Oyster mushrooms",
  
  # Dietary Patterns / Other Diets
  "Plant-based diets",
  "Plant-based diet",
  "High-fiber diets",
  "High-fiber diet",
  "Mediterranean diet",
  "Mediterranean diets",
  "Nordic diet",
  "Nordic diets",
  "Gluten-free diet",
  "Gluten-free diets",
  "Anti-inflammatory diet",
  "Anti-inflammatory diets",
  "Calorie-restricted diets", # Added earlier, including again for clarity
  "Calorie-restricted diet", # Added earlier, including again for clarity
  "DASH diet",
  "DASH diets",
  "Immunonutrition diet",
  "Immunonutrition diets",
  
  # Alternative/Traditional Medicine Diets
  "Paleo diet",
  "Paleo diets",
  "Ayurvedic diet",
  "Ayurvedic diets",
  "Traditional Chinese medicine diet",
  "Traditional Chinese medicine diets",
  "Raw food diet",
  "Raw food diets",
  "Alkaline diet",
  "Alkaline diets",
  
  # Berry-based Diets for Muscle Health (Specific Berries)
  "Raspberries",
  "Blueberries",
  "Aronia",
  "Elderberry",
  "Mixed compound berry-based diet",
  "Mixed compound berry-based diets",
  
  # Processed or Unbalanced Diets
  "Processed food-based diets",
  "Processed food-based diet",
  "Processed foods", # Common term
  "Unbalanced vegetarian diets",
  "Unbalanced vegetarian diet",
  "Unbalanced vegan diets",
  "Unbalanced vegan diet",
  "Vegetarian diet", # Common variation
  "Vegetarian diets", # Common variation
  "Vegan diet", # Common variation
  "Vegan diets", # Common variation
  
  # Sodium/Caloric Restriction
  "Sodium-restricted diet",
  "Sodium-restricted diets",
  
  # Fasting Regimens
  "Intermittent fasting",
  "Alternate day fasting",
  "Alternate day", # Might appear without 'fasting'
  "5:2 regimen",
  "5 2 regimen", # Variation without colon
  "Time-restricted feeding",
  "B2 regimen",
  "Weekly 1-day fasting",
  "Intermittent VLCD therapy",
  "Very Low-Calorie Diet therapy",
  "VLCD", # Acronym
  
  # Lifestyle Factors
  "Caffeine intake",
  "Caffeine", # Base term
  "Alcohol",
  "Alcohol intake",
  "Smoking" # While a lifestyle factor, often discussed alongside diet/health interventions
)

dietary_intervention_terms <- tolower(dietary_intervention_terms)
dietary_intervention_terms <- unique(dietary_intervention_terms) # Remove any potential duplicates
dietary_intervention_terms <- sort(dietary_intervention_terms)
dietary_intervention_terms <- str_trim(dietary_intervention_terms)
length(dietary_intervention_terms)
print(dietary_intervention_terms)


single_diet_terms <- c(
  # ─── verbs & verb tenses ─────────────────────────────────
  "eat","ate","eaten","eating",
  "consume","consumed","consuming",
  "cook","cooked","cooking",
  "snack","snacked","snacking",
  "fasted","fasting",
  "feed","fed","feeding", "drink", "drank", "drinking","drinker", "nondrinker", "alcoholic",
  
  # ─── core food-words ─────────────────────────────────────
  "diet","diets","dieting", "dietary", "dietician", "dieticians",
  "food","foods",
  "meal","meals",
  "ingredient","ingredients",
  "nutrition","nutritional",
  "nutrient","nutrients",
  "calorie","calories",
  "carb","carbs",
  "fruit","fruits",
  "juice","juices",
  "junk",
  "processed",
  "plant","plants", "vegetables",
  "meat", "chicken",
  "milk", "cheese",
  
  # ─── macro & micronutrients ──────────────────────────────
  "protein","proteins","glycoprotein", "lipoprotein", "lipoproteins", "proteinaceous",
  "fat","fats",
  "carbohydrate","carbohydrates",
  "macronutrient","macronutrients",
  "micronutrient","micronutrients",
  "vitamin","vitamins","b9","folic","multivitamin", "multivitamins", "vitamine",
  "mineral","minerals",
  "calcium","zinc","magnesium",
  "potassium","selenium","biotin",
  "leucine","bcaa","bcaas","glutamine","hmb","creatine",
  "casein","whey","pea","soy",
  "amino","aminos",
  
  # ─── lipids & fatty acids ────────────────────────────────
  "omega","omega3","omega6","omega-3","omega-6",
  "saturated","transfat","ketogenic","keto","ketosis", "keto-friendly",
  "oil","oils","fish",
  
  # ─── carbohydrate specifics ──────────────────────────────
  "lactose","fructose","sugar","sugars","fodmap",
  
  # ─── plant/bio-actives & supplements ─────────────────────
  "turmeric","curcumin","ginger",
  "antioxidant","antioxidants",
  "polyphenol","polyphenols",
  "coq10",
  "prebiotic","prebiotics",
  "probiotic","probiotics",
  "synbiotic","synbiotics",
  "postbiotic","postbiotics",
  "isoflavone","isoflavones",
  "yeast","rice",
  "mushroom","mushrooms","oyster","oysters",
  
  # ─── everyday foods & plant parts ────────────────────────
  "herb","herbs","herbal",
  "spice","spices",
  "berry","berries","raspberry","raspberries",
  "blueberry","blueberries","aronia",
  "elderberry","elderberries",
  "grape","grapes",
  "legume","legumes",
  "nut","nuts",
  "seed","seeds",
  "tea","chocolate",
  "citrus",
  
  # ─── diet / pattern acronyms & descriptors ───────────────
  "vlcd","dash","fodmap",
  "paleo","mediterranean","nordic",
  "ayurvedic","raw","alkaline",
  "gluten","fiber","fibers",
  "vegetarian","vegetarians",
  "vegan","vegans",
  "immunonutrition",
  "sodium","salt",
  
  # ─── lifestyle consumables ───────────────────────────────
  "caffeine","alcohol","wine","coffee", "beer", "liquor"
  
  # (duplicates automatically removed)
) |> unique()

single_diet_terms <- tolower(single_diet_terms)
single_diet_terms <- unique(single_diet_terms) # Remove any potential duplicates
single_diet_terms <- sort(single_diet_terms)
single_diet_terms <- str_trim(single_diet_terms)
length(single_diet_terms)
print(single_diet_terms)


#combine word lists
diet_terms <- union(single_diet_terms, dietary_intervention_terms)
diet_terms <- tolower(diet_terms)
diet_terms <- unique(diet_terms) # Remove any potential duplicates
diet_terms <- sort(diet_terms)
length(diet_terms)
print(diet_terms)


saveRDS(diet_terms,                 file = file.path(DATA_PATH, "word_lists/diet_terms.RDS"))
saveRDS(single_diet_terms,          file = file.path(DATA_PATH, "word_lists/single_diet_terms.RDS"))
saveRDS(dietary_intervention_terms, file = file.path(DATA_PATH, "word_lists/dietary_intervention_terms.RDS"))

lemma_map <- list(
  alcohol         = c("alcohol", "wine", "beer", "liquor", "alcoholic", "drinker", "nondrinker"),
  amino_acid      = c("amino", "aminos", "bcaa", "bcaas", "leucine", "hmb"),
  antioxidant     = c("antioxidant", "antioxidants", "curcumin", "coq10"),
  aronia          = c("aronia"),
  ayurvedic       = c("ayurvedic"),
  berry           = c("berry", "berries", "blueberry", "blueberries", "raspberry", "raspberries", "elderberry", "elderberries", "grape", "grapes"),
  biotin          = c("biotin"),
  caffeine        = c("caffeine", "coffee"),
  calcium         = c("calcium"),
  calorie         = c("calorie", "calories"),
  carb            = c("carb", "carbs", "carbohydrate", "carbohydrates"),
  casein          = c("casein"),
  cheese          = c("cheese"),
  chicken         = c("chicken"),
  chocolate       = c("chocolate"),
  citrus          = c("citrus"),
  consume         = c("consume", "consumed", "consuming"),
  cook            = c("cook", "cooked", "cooking"),
  creatine        = c("creatine"),
  diet_general    = c("diet", "dieting", "diets", "dietary", "dietician", "dieticians"),
  specific_diet   = c("ketogenic", "keto", "ketosis", "keto-friendly", "dash", "paleo", "mediterranean", "nordic", "vegan", "vegans", "vegetarian", "vegetarians", "vlcd", "fodmap"),
  drank           = c("drank"),
  drink           = c("drink", "drinking"),
  eat             = c("eat", "eating", "eaten", "ate", "feeding", "fed", "feed"),
  fast            = c("fasting", "fasted"),
  fat             = c("fat", "fats", "saturated", "transfat"),
  fiber           = c("fiber", "fibers"),
  fish            = c("fish"),
  folic           = c("folic"),
  food            = c("food", "foods", "ingredient", "ingredients", "meal", "meals"),
  fructose        = c("fructose"),
  fruit           = c("fruit", "fruits"),
  ginger          = c("ginger"),
  glutamine       = c("glutamine"),
  gluten          = c("gluten"),
  herb            = c("herb", "herbs"),
  immunonutrition = c("immunonutrition"),
  ingredient_flag = c("ingredient", "ingredients"),  # included under food, redundant flag
  isoflavone      = c("isoflavone", "isoflavones"),
  juice           = c("juice", "juices"),
  junk_food       = c("junk"),
  lactose         = c("lactose"),
  legume          = c("legume", "legumes", "pea"),
  macronutrient   = c("macronutrient", "macronutrients"),
  magnesium       = c("magnesium"),
  meat            = c("meat"),
  milk            = c("milk"),
  micronutrient   = c("micronutrient", "micronutrients"),
  mineral         = c("mineral", "minerals"),
  mushroom        = c("mushroom", "mushrooms", "oyster", "oysters"),
  nut             = c("nut", "nuts", "seed", "seeds"),
  nutrient        = c("nutrient", "nutrients", "nutrition", "nutritional"),
  oil             = c("oil", "oils"),
  omega_fatty     = c("omega", "omega3", "omega-3", "omega6", "omega-6"),
  plant           = c("plant", "plants", "vegetables"),
  polyphenol      = c("polyphenol", "polyphenols"),
  postbiotic      = c("postbiotic", "postbiotics"),
  potassium       = c("potassium"),
  prebiotic       = c("prebiotic", "prebiotics"),
  probiotic       = c("probiotic", "probiotics"),
  processed       = c("processed"),
  protein         = c("protein", "proteins", "whey", "glycoprotein", "lipoprotein", "lipoproteins", "proteinaceous"),
  raw             = c("raw"),
  rice            = c("rice"),
  salt            = c("salt", "sodium"),
  selenium        = c("selenium"),
  snack           = c("snack", "snacked", "snacking"),
  soy             = c("soy"),
  spice           = c("spice", "spices"),
  sugar           = c("sugar", "sugars"),
  synbiotic       = c("synbiotic", "synbiotics"),
  tea             = c("tea"),
  turmeric        = c("turmeric"),
  vitamin         = c("vitamin", "vitamins","multivitamin", "multivitamins", "vitamine"),
  yeast           = c("yeast"),
  zinc            = c("zinc")
)

saveRDS(lemma_map, file = file.path(DATA_PATH, "word_lists/lemma_map_diet.RDS"))

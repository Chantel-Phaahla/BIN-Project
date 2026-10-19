# =============================================================================
# preprocess.R
# Shared cleaning, validation and scoring functions for the SDHSA food
# insecurity models (Milestone 3).
#
# Used by:
#   - Task1.Rmd  (modelling):   source("preprocess.R")
#   - Shiny app  (deployment):  source("preprocess.R")
#
# Only FIXED rules are in this file (no values learned from data), so applying
# them to train, test and new data cannot leak information. Learned steps
# (imputation, dummy coding, scaling, correlation filter) live in the recipe
# stored inside the fitted workflow (final_rf / final_lr).
# =============================================================================

library(tidyverse)
library(tidymodels)

TARGET <- "FoodInsecure_flag"

# ---- 1. Fixed cleaning rules -------------------------------------------------

# Survey codes that are categories, not quantities -> factors
nominal_codes <- c(
  "ProvinceCode", "HeadPopulationGroupCode", "HeadSexCode", "MainDwellingCode",
  "WallMaterialCode_clean", "RoofMaterialCode", "FloorMaterialCode",
  "TenureCode", "RDPHousingCode", "HousingSubsidyCode", "GeoTypeCode",
  "DrinkingWaterSourceCode", "MainToiletCode", "SharedToiletCode",
  "ToiletLocationCode", "WaterAlternativeSourceCode_clean",
  "MainIncomeSourceCode_clean"
)

# Ordinal / yes-no codes where 9 means "unknown" -> NA
unknown9_cols <- c(
  "RoofConditionCode", "WallConditionCode", "FloorConditionCode",
  "ComparativeIncomeCode", "NoIncomeCode",
  "VehicleAssetCode", "TVAssetCode", "PayTVAssetCode",
  "ComputerAssetCode", "WashingMachineAssetCode", "FreezerAssetCode",
  "FridgeAssetCode", "MicrowaveAssetCode", "GeyserAssetCode",
  "SolarPanelAssetCode", "RadioAssetCode"
)

# Columns removed inside the recipe (step_rm). Kept here so the Rmd and the app
# share one list. In Task1.Rmd use:  step_rm(any_of(drop_cols))
drop_cols <- c(
  "Province_source", "Province_source_D05", "Province_source_D07", "Province_source_D09",
  "ProvinceClean_D07", "ProvinceClean_D09", "ProvinceCode_D05", "ProvinceCode_D07",
  "ProvinceCode_D09", "GeoTypeCode_D05", "GeoTypeCode_D07",
  "HouseholdWeight", "HouseholdWeight_D05", "HouseholdWeight_D07", "HouseholdWeight_D09",
  "HouseholdSize", "HouseholdSize_D01",
  "RentRaw", "WallMaterialCode", "TotalRooms", "MainIncomeSourceCode",
  "DistanceToWaterCode", "PipedWaterCode", "PipedWaterCode_clean",
  "WaterInterruptionFrequencyCode", "WaterAlternativeSourceCode", "ToiletDistanceCode",
  "TotalVehicles", "TimeToWaterRaw", "RequiredIncomeRaw",
  "SurveyYear", "SurveyYear_D05", "SurveyYear_D07", "SurveyYear_D09"
)

#' Apply the fixed cleaning rules.
#' Works on training/test data (with the target) and on new data (without it).
clean_data <- function(df) {
  df <- df %>%
    mutate(
      across(any_of(unknown9_cols), ~ na_if(.x, 9)),
      across(any_of("ExpenditureBandCode"), ~ na_if(.x, 99)),
      across(any_of(nominal_codes), as.factor)
    )

  # Target only exists in labelled data. Positive class ("Insecure") FIRST.
  if (TARGET %in% names(df)) {
    df[[TARGET]] <- factor(df[[TARGET]],
                           levels = c(1, 0),
                           labels = c("Insecure", "Secure"))
  }
  df
}

# ---- 2. Validation of NEW data before scoring ---------------------------------

#' Check and prepare new household data for scoring.
#'
#' @param df    data frame of new households (e.g. an uploaded CSV)
#' @param model fitted workflow (readRDS("data/final_rf.rds"))
#' @return list(data = cleaned data ready for predict(),
#'              messages = character vector of warnings / fixes applied)
#' Stops with a clear error if essential columns are missing.
validate_new_data <- function(df, model) {
  msgs <- character()
  df <- as_tibble(df)

  # What the model was trained on (original predictor names and types)
  vi <- extract_recipe(model, estimated = TRUE)$var_info %>%
    filter(role == "predictor")
  needed <- vi$variable

  # 1. Missing columns
  missing_cols <- setdiff(needed, names(df))
  essential_missing <- setdiff(missing_cols, drop_cols)
  if (length(essential_missing) > 0) {
    stop("Required columns are missing: ",
         paste(essential_missing, collapse = ", "), call. = FALSE)
  }
  # Columns the recipe discards anyway can be absent: add as NA
  for (cn in intersect(missing_cols, drop_cols)) df[[cn]] <- NA
  if (length(intersect(missing_cols, drop_cols)) > 0) {
    msgs <- c(msgs, paste0(length(intersect(missing_cols, drop_cols)),
                           " unused columns were absent and filled with NA."))
  }

  # 2. Extra columns are ignored
  extra <- setdiff(names(df), c(needed, TARGET))
  if (length(extra) > 0) {
    msgs <- c(msgs, paste0(length(extra), " extra columns ignored."))
    df <- df %>% select(-all_of(extra))
  }

  # 3. Numeric columns must be numeric
  num_cols <- vi$variable[map_lgl(vi$type, ~ "numeric" %in% .x)]
  for (cn in intersect(num_cols, names(df))) {
    if (!is.numeric(df[[cn]])) {
      before_na <- sum(is.na(df[[cn]]))
      df[[cn]] <- suppressWarnings(as.numeric(df[[cn]]))
      msgs <- c(msgs, paste0("'", cn, "' converted to numeric (",
                             sum(is.na(df[[cn]])) - before_na, " new NAs)."))
    }
  }

  # 4. Fixed cleaning rules
  df <- clean_data(df)

  # 5. Data-quality warnings (missingness, unseen categories)
  miss_pct <- colMeans(is.na(df %>% select(all_of(intersect(needed, names(df))))))
  high_miss <- names(miss_pct)[miss_pct > 0.5 & !names(miss_pct) %in% drop_cols]
  if (length(high_miss) > 0) {
    msgs <- c(msgs, paste0("More than 50% missing in: ",
                           paste(high_miss, collapse = ", "),
                           ". Predictions are less reliable."))
  }

  list(data = df, messages = msgs)
}

# ---- 3. Scoring ----------------------------------------------------------------

#' Score households with a fitted workflow.
#'
#' @param df        raw new data
#' @param model     fitted workflow (final_rf or final_lr)
#' @param threshold probability cut-off for flagging "Insecure"
#'                  (choose it from the threshold analysis in Task 2)
#' @return list(scores = tibble with probability, flag and risk band,
#'              messages = validation messages)
score_households <- function(df, model, threshold = 0.5) {
  v <- validate_new_data(df, model)

  probs <- predict(model, v$data, type = "prob")

  scores <- bind_cols(df, probs %>% select(prob_insecure = .pred_Insecure)) %>%
    mutate(
      flagged_insecure = prob_insecure >= threshold,
      risk_band = cut(prob_insecure,
                      breaks = c(-Inf, threshold / 2, threshold, Inf),
                      labels = c("Lower", "Elevated", "High"))
    )

  list(scores = scores, messages = v$messages)
}

# ---- Example (deployment) ---------------------------------------------------------
# source("preprocess.R")
# final_rf <- readRDS("data/final_rf.rds")
# new_hh   <- read_csv("new_households.csv", guess_max = Inf)
# out      <- score_households(new_hh, final_rf, threshold = 0.25)
# out$messages
# out$scores

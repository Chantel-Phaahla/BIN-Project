-IN 381 (Business Intelligence), Belgium Campus iTversity. Group P4.
Authors: Chantel Phaahla (603086), Busisiwe Socatsha (602726), Paballo Masekela (602207)

## 1. What this project does
Uses Stats SA General Household Survey (GHS) data to identify households facing
food insecurity and overlapping deprivations, to support targeting decisions by
DPME and provincial departments. The modelling target is `FoodInsecure_flag`
(1 = household reported running out of food). Method: CRISP-DM.
Tools: R (cleaning, modelling, Shiny app) and Power BI (dashboard).

## 2. Repository structure

| Item | What it contains |
|---|---|
| 
|R_Scripts | R Markdown scripts for cleaning, integration, data preparation, modelling and evaluation [list the files and confirm] |
| R_Scripts | Milestone reports, final ethics report and responsible AI usage log [confirm] |
| Power BI.zip | The Power BI dashboard (`PowerBI_dashboards.pbix`) [confirm contents] |
| R_Shiny.zip| The deployed Shiny app: `app.R`, `preprocess.R`, `monitoring.R`, `run_monitoring.R`, `data/` (saved model, test data, threshold table) [confirm contents] |
| data (2).zip | The data files used by the scripts and dashboard [confirm: raw GHS files, processed files, or both] |


Unzip each archive into a folder of the same name before following section 5.

## 3. Requirements
- R version: [2026.08.2+200 ]  
- Power BI Desktop 
- R packages used in the cleaning and preparation scripts: tidyverse (dplyr, ggplot2,
  readr, stringr, tibble, tidyr), knitr, caret.
- Additional packages used in modelling and the app: [list from the modelling script
  and `app.R`, for example tidymodels, shiny]
- Install them with `install.packages(c(...))` using the lists above, or restore exact
  versions with `renv::restore()` if an `renv.lock` file is included [add one].

## 4. Data
- Source: Stats SA GHS, ISIbalo portal 
  
- Datasets used: D01 Population Profile, D04 Dwelling Conditions, D05 Basic Services,
  D07 Household Wellbeing, D09 Household Resources.


## 5. How to reproduce
Run from a fresh R session, in this order. The train/test split uses `set.seed(381)`.

| Step | Script (in `R_Scripts/`) | Reads | Writes |
|---|---|---|---|
| 1 | SDHSA_Milestone2_Person1_CleanRecode.Rmd | raw D01, D04, D05, D07, D09 | D0x_cleaned.csv and two flag files |
| 2 | SDHSA_Milestone2_Task3.Rmd | cleaned files | household_data_integrated.csv, data_dictionary.csv |
| 3 | Task_4.Rmd | household_data_integrated.csv | train and test data (stratified 80/20) |
| 4 | [modelling script, e.g. Task1.Rmd] | step 3 output | final_rf.rds, test_predictions.csv |
| 5 | [evaluation script, e.g. Task-2] | test_predictions.csv | threshold_table.csv and metrics [confirm] |

Set the working directory so the scripts find their input files. `Task_4.Rmd` reads
from a `data/` folder, so place the processed CSVs there [or update the paths].

Expected checkpoints: 20,940 households after integration; 130 columns;
FoodInsecure_flag 17,108 (0) and 3,832 (1); 4,136 test rows per model.

## 6. Power BI dashboard
- Unzip `Power BI.zip` and open `PowerBI_dashboards.pbix`.
- Pages: Overview, Who is affected, Overlap, Targeting.
- Data sources: `household_data_integrated.csv` (table HH, pages 1 to 3),
  `test_predictions.csv` (table Predictions) and `threshold_table.csv` (page 4).
- Power Query steps for Predictions: filter `model` to "Random forest" (4,136 rows),
  keep six columns, rename `.pred_Insecure` to `Pred_Insecure` and `ProvinceClean_D07`
  to `Province`, set `Pred_Insecure` to decimal using the US English locale.
- Pages 1 to 3 use survey-weighted measures. Page 4 is unweighted test-set data and
  must not be related to HH.
- If Power BI cannot find the files, update the paths under
  Transform data > Data source settings, then Refresh.

## 7. Shiny app
- Unzip `R_Shiny.zip`. Run `shiny::runApp()` from the app folder [confirm command].
- Needs the saved model `final_rf.rds` and the files in its `data/` folder.
- Input: a CSV with one row per household, the same fields as the Milestone 2 dataset,
  and an optional outcome column to enable performance checks.
- The default flagging threshold is 0.30. Real household data should only be hosted
  inside the organisation (POPIA).

## 8. Monitoring and maintenance
Full rules are in the Milestone 3 report (section 4.5). Summary:
- Every new batch: schema validation, data quality, feature drift (PSI) and share flagged.
- Each new survey year: AUC, recall, precision and province recall against the baseline
  (AUC 0.840, recall 63% and precision 49% at 0.30).
- Retrain if AUC is below 0.75, recall is below 50%, three or more key drivers have
  PSI of 0.25 or more, the survey questions or codes change, or a province falls
  below 40% recall.
- Retire if AUC cannot be restored above 0.75, the food insecurity definition changes,
  key inputs are discontinued, or a fairness review finds harm that cannot be mitigated.
- Roles: model owner (BI analyst), programme owner (confirms the threshold),
  data steward (access and privacy).

## 9. Handover notes and known issues
- Scores support analysts' prioritisation. They must not decide eligibility for
  individual households.
- Recall differs by province (about 73% in KwaZulu-Natal, 49% in Gauteng, 35% in
  Limpopo at 0.30, with only 20 cases in Limpopo).
- The GHS codebook is missing, so `RanOutOfFood_label` and the toilet and
  food-security codes are provisional.
- `SalaryEarnersInHousehold` and `TotalGrantRecipients` appear to hold rand amounts,
  not counts. [Confirm and document.]
- `Services_access_index` scores "not applicable" water as 0 and excludes electricity.
- `MainToiletCode` values 9 and 99 are treated as unknown in the dashboard.
- 22 households disagree on household size and 18 on income (flag files).
- 19 leakage variables were removed before modelling (some documents still say 18).
- The app has no range checks or sign-in.

## 10. Ethics and responsible AI
The final ethics report and the responsible AI usage log are in `Report/` [confirm].

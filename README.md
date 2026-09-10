# GLP-1-Database
# GLP-1 Drug Adverse Event Analytics & Machine Learning Pipeline

Predicts whether an FDA FAERS adverse event report for a GLP-1 drug
(semaglutide, tirzepatide, liraglutide, dulaglutide, exenatide,
lixisenatide, albiglutide) will be classified as **serious**, and explores
correlations between Medicaid drug utilization/cost and adverse event rates.

## Files

| File | Purpose |
|---|---|
| `Project_3.ipynb` | Main notebook: EDA, feature engineering, model training, evaluation |
| `adverse_events.csv` | FAERS adverse event reports (one row per reaction) |
| `adverse_events_summary.csv` | Pre-aggregated drug × reaction summary stats |
| `cleaned_combined_data.csv` | Medicaid drug utilization & reimbursement data |

## Setup

```bash
pip install pandas numpy matplotlib seaborn scikit-learn scipy
```

Place all three CSVs in the same folder as the notebook, then run all cells
top to bottom (Jupyter, Colab, or Kaggle — see note below on free hosting).

## What the notebook does

1. **Load data** — reads `adverse_events.csv`, parses report dates.
2. **Clean & engineer features** — normalizes patient age to years, extracts
   report year/month, computes reactions-per-report and unique-reaction
   counts per report.
3. **EDA** — class balance, seriousness rate by drug, age distribution,
   report volume over time, top reactions in serious cases
   (saved to `eda_overview.png`).
4. **Modeling setup** — collapses to one row per report, builds a
   preprocessing pipeline (median/mode imputation, scaling, one-hot
   encoding) over numeric and categorical features.
5. **Models** — trains and compares Logistic Regression, Random Forest, and
   Gradient Boosting classifiers on an 80/20 stratified split; picks the
   best by ROC-AUC.
6. **Evaluation** — confusion matrix, ROC curve, precision-recall curve for
   the best model (saved to `model_evaluation.png`).
7. **Feature importance** — top 20 features for tree-based models
   (saved to `feature_importance.png`).
8. **Hyperparameter tuning (optional)** — grid search over Random Forest
   params. **Off by default** (`RUN_GRID_SEARCH = False`) because it can
   take several minutes on the full ~54k-report dataset — flip to `True`
   only if you're willing to wait.

## Current results

Best model: **Random Forest**, ROC-AUC ≈ 0.86 on held-out test data.

## Known limitations

- Molecule names don't perfectly align between the utilization data and
  the FAERS data (e.g. combo drugs like "insulin glargine + lixisenatide"
  have no match), so cross-dataset correlation only covers the 7 single-
  ingredient molecules common to both files.
- FAERS reports are voluntary/spontaneous, not incidence rates — they
  reflect reporting patterns, not true population risk.

## Running for free

No paid resources are required. To run outside this environment:
- **Google Colab** — colab.research.google.com, upload the notebook and
  the three CSVs, Runtime → Run all.
- **Kaggle Notebooks** — kaggle.com → New Notebook, add the CSVs as a
  dataset, run.

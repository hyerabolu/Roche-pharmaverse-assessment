# Roche Pharmaverse Assessment

Solutions to the Analytical Data Science Programmer coding assessment, using open-source Pharmaverse R packages (Questions 1-3) and Python (Question 4).

## Repository structure

| Folder | Contents |
|---|---|
| `question_1_sdtm/` | SDTM DS domain script, `ds.csv`, run log |
| `question_2_adam/` | ADSL script, `adsl.csv`, `adsl.rds`, run log |
| `question_3_tlg/` | AE summary table (HTML), 2 plots (PNG), 2 scripts, 2 logs |
| `question_4_python/` | GenAI clinical data agent (Python), `adae.csv`, run log |

## Environment

- R 4.6.1: `sdtm.oak`, `admiral`, `pharmaverseraw`, `pharmaversesdtm`, `pharmaverseadam`, `dplyr`, `stringr`, `gtsummary`, `gt`, `cardx`, `ggplot2`
- Python 3.13.2: `pandas`

Open `Roche-pharmaverse-assessment.Rproj` first, so all R scripts run from the project root.

---

## Question 1: SDTM DS domain (`question_1_sdtm/`)

| File | Purpose |
|---|---|
| `01_create_ds_domain.R` | Program that creates the DS domain |
| `ds.csv` | Resulting DS dataset |
| `run_log.txt` | Log showing the program runs without errors |

**Inputs**

- Raw data: `pharmaverseraw::ds_raw`
- Study controlled terminology: `study_ct` (as given in the assessment)
- Mapping rules: `Subject_Disposition_aCRF.pdf` (yellow-box programming notes)
- `pharmaversesdtm::dm` for STUDYID, USUBJID and the first treatment date (RFXSTDTC)
- `pharmaversesdtm::sv` for VISITNUM

**Mapping rules (from the aCRF)**

| Variable | Rule |
|---|---|
| DSTERM | `IT.DSTERM` if `OTHERSP` is missing, otherwise `OTHERSP` |
| DSDECOD | `IT.DSDECOD` mapped with `study_ct` if `OTHERSP` is missing, otherwise `OTHERSP` |
| DSCAT | `OTHER EVENT` if `OTHERSP` is present; `PROTOCOL MILESTONE` if `IT.DSDECOD` = Randomized; otherwise `DISPOSITION EVENT` |
| DSSTDTC | `IT.DSSTDAT` in ISO 8601 |
| DSDTC | `DSDTCOL` + `DSTMCOL` in ISO 8601 |
| VISIT / VISITNUM | `INSTANCE` in upper case; VISITNUM looked up from SV |
| DSSTDY | Study day relative to DM.RFXSTDTC |
| DSSEQ | Sequence within subject |

**Notes**

- The aCRF names the start date `IT.DSSDAT`; in `ds_raw` the column is `IT.DSSTDAT`.
- Some collected values (for example "Completed", "Screen Failure", "Randomized") are spelled differently from `collected_value` in `study_ct`. `{sdtm.oak}` then returns them in upper case, which gives valid terms (COMPLETED, SCREEN FAILURE, RANDOMIZED). The message "These terms could not be mapped" is information only.
- DSSTDY is missing for 52 screen-failure records, as these subjects have no first treatment date.
- Final Lab Visit and Final Retrieval Visit come from `OTHERSP` and are kept as collected, following the aCRF rule, with DSCAT = OTHER EVENT.

**QC checks (printed at the end of the program)**

- 850 records in raw data and in DS
- No missing USUBJID, VISITNUM or DSSTDTC
- DSCAT counts agree with the source values: PROTOCOL MILESTONE = 254 Randomized records, OTHER EVENT = 290 records with OTHERSP, DISPOSITION EVENT = 306 other reasons

---

## Question 2: ADSL (`question_2_adam/create_adsl.R`)

Built from `pharmaversesdtm::dm` with {admiral} and dplyr. Outputs: `adsl.csv`, `adsl.rds`, `create_adsl_log.txt`.

| Variable | Derivation |
|---|---|
| AGEGR9 / AGEGR9N | `<18` = 1, `18 - 50` = 2, `>50` = 3 |
| TRTSDTM / TRTSTMF | First valid dose (EXDOSE > 0, or EXDOSE = 0 with PLACEBO in EXTRT) with a complete date. Missing time imputed as 00:00:00; no flag when only seconds are missing. |
| ITTFL | "Y" if ARM is populated, else "N" |
| LSTAVLDT | Latest complete date from VS (valid result), AE start, DS start and last valid dose (TRTEDTM) |

**Notes**

- ARM = "Screen Failure" is populated, so these 52 subjects get ITTFL = "Y" under the literal rule.

**Self-QC**

- 306 subjects, no duplicate USUBJID
- 52 missing TRTSDTM (screen failures, never dosed); TRTSTMF = "H" for 254 subjects (time not collected)
- 0 missing LSTAVLDT; 0 records with LSTAVLDT before TRTSDTM
- The first {admiral} version and the simplified version produced an identical `adsl.csv`

---

## Question 3: AE reporting (`question_3_tlg/`)

**Table** (`01_create_ae_summary_table.R` → `ae_summary_table.html`)

- TEAEs only (TRTEMFL = "Y"), rows by SOC and AE term, columns by ACTARM plus a Total column
- Cells are n (%) of subjects, sorted by descending frequency
- Denominator: safety population (N = 86 / 72 / 96)

**Plots** (`02_create_visualizations.R`)

- `plot1_ae_severity.png`: AE count by severity (AESEV) per treatment arm, stacked bar
- `plot2_top10_ae.png`: top 10 AE terms, % of subjects with 95% Clopper-Pearson CIs (`binom.test`)
- Plots use all ADAE records with N = 225 subjects in ADAE, to match the sample outputs

---

## Question 4: GenAI Clinical Data Agent (`question_4_python/`)

Flow: **Prompt → Parse → Execute**

1. **Prompt:** the column schema (AESEV, AETERM, AESOC) and the question are sent to the LLM, asking for JSON.
2. **Parse:** `json.loads` reads `target_column` and `filter_value`.
3. **Execute:** pandas filters the AE data and returns the unique USUBJID count and list.

No API key was available, so the LLM reply is mocked. If `OPENAI_API_KEY` is set (and `pip3 install openai` is done), the same code calls OpenAI.

**Run:** `python3 question_4_python/clinical_trial_data_agent.py`

**Test results** (`run_log.txt`)

| Question | Mapped to | Unique subjects |
|---|---|---|
| Subjects with Moderate severity AEs | AESEV = MODERATE | 136 |
| Which subjects had Headache? | AETERM = HEADACHE | 16 |
| Patients with cardiac problems | AESOC = CARDIAC | 44 |
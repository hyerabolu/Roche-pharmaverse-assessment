# Roche Pharmaverse Assessment

Solutions to the Analytical Data Science Programmer coding assessment, using open-source
Pharmaverse R packages.

## Repository structure

| Folder | Content |
|---|---|
| `question_1_sdtm/` | SDTM DS (Disposition) domain created with `{sdtm.oak}` |

## How to run

1. Clone the repository and open `Roche-pharmaverse-assessment.Rproj` in RStudio.
2. Install the packages (R >= 4.2.0):
   ```r
   install.packages(c("sdtm.oak", "pharmaverseraw", "pharmaversesdtm", "dplyr"))
   ```
3. Run a script from the project folder, for example:
   ```r
   source("question_1_sdtm/01_create_ds_domain.R")
   ```

---

## Question 1: SDTM DS domain

**Files**

| File | Description |
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
- Some collected values (for example "Completed", "Screen Failure", "Randomized") are spelled
  differently from `collected_value` in `study_ct`. `{sdtm.oak}` then returns them in upper case,
  which gives valid terms (COMPLETED, SCREEN FAILURE, RANDOMIZED). The message
  "These terms could not be mapped" is information only.
- DSSTDY is missing for 52 screen-failure records, as these subjects have no first treatment date.
- Final Lab Visit and Final Retrieval Visit come from `OTHERSP` and are kept as collected,
  following the aCRF rule, with DSCAT = OTHER EVENT.

**QC checks (printed at the end of the program)**

- 850 records in raw data and in DS
- No missing USUBJID, VISITNUM or DSSTDTC
- DSCAT counts agree with the source values: PROTOCOL MILESTONE = 254 Randomized records,
  OTHER EVENT = 290 records with OTHERSP, DISPOSITION EVENT = 306 other reasons

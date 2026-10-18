# Program: 01_create_ds_domain.R
# Purpose: Create the SDTM DS domain from pharmaverseraw::ds_raw
# Spec:    Subject_Disposition_aCRF.pdf

library(sdtm.oak)
library(pharmaverseraw)
library(pharmaversesdtm)
library(dplyr)

# Study controlled terminology (copied from the assessment)
study_ct <- data.frame(
  stringsAsFactors = FALSE,
  codelist_code = rep("C66727", 10),
  term_code = c("C41331", "C25250", "C28554", "C48226", "C48227", "C48250",
                "C142185", "C49628", "C49632", "C49634"),
  term_value = c("ADVERSE EVENT", "COMPLETED", "DEATH", "LACK OF EFFICACY",
                 "LOST TO FOLLOW-UP", "PHYSICIAN DECISION",
                 "PROTOCOL VIOLATION", "SCREEN FAILURE",
                 "STUDY TERMINATED BY SPONSOR", "WITHDRAWAL BY SUBJECT"),
  collected_value = c("Adverse Event", "Complete", "Dead", "Lack of Efficacy",
                      "Lost To Follow-Up", "Physician Decision",
                      "Protocol Violation", "Trial Screen Failure",
                      "Study Terminated By Sponsor", "Withdrawal by Subject"),
  term_preferred_term = c("AE", "Completed", "Died", NA, NA, NA, "Violation",
                          "Failure to Meet Inclusion/Exclusion Criteria", NA,
                          "Dropout"),
  term_synonyms = c("ADVERSE EVENT", "COMPLETE", "Death", NA, NA, NA, NA, NA,
                    NA, "Discontinued Participation")
)

dm <- pharmaversesdtm::dm
sv <- pharmaversesdtm::sv

# Read raw data, treat blank OTHERSP as missing, and add oak id variables
ds_raw <- pharmaverseraw::ds_raw %>%
  mutate(OTHERSP = ifelse(OTHERSP == "", NA, OTHERSP),
         VISIT   = toupper(INSTANCE)) %>%
  generate_oak_id_vars(pat_var = "PATNUM", raw_src = "ds_raw")

# Map variables as per the aCRF notes
ds <-
  # DSTERM: IT.DSTERM if OTHERSP is missing, otherwise OTHERSP
  assign_no_ct(raw_dat = condition_add(ds_raw, is.na(OTHERSP)),
               raw_var = "IT.DSTERM", tgt_var = "DSTERM") %>%
  assign_no_ct(raw_dat = condition_add(ds_raw, !is.na(OTHERSP)),
               raw_var = "OTHERSP", tgt_var = "DSTERM") %>%

  # DSDECOD: IT.DSDECOD (using CT) if OTHERSP is missing, otherwise OTHERSP
  assign_ct(raw_dat = condition_add(ds_raw, is.na(OTHERSP)),
            raw_var = "IT.DSDECOD", tgt_var = "DSDECOD",
            ct_spec = study_ct, ct_clst = "C66727") %>%
  assign_no_ct(raw_dat = condition_add(ds_raw, !is.na(OTHERSP)),
               raw_var = "OTHERSP", tgt_var = "DSDECOD") %>%

  # DSCAT
  hardcode_no_ct(raw_dat = condition_add(ds_raw, !is.na(OTHERSP)),
                 raw_var = "OTHERSP", tgt_var = "DSCAT",
                 tgt_val = "OTHER EVENT") %>%
  hardcode_no_ct(raw_dat = condition_add(ds_raw, is.na(OTHERSP) & IT.DSDECOD == "Randomized"),
                 raw_var = "IT.DSDECOD", tgt_var = "DSCAT",
                 tgt_val = "PROTOCOL MILESTONE") %>%
  hardcode_no_ct(raw_dat = condition_add(ds_raw, is.na(OTHERSP) & IT.DSDECOD != "Randomized"),
                 raw_var = "IT.DSDECOD", tgt_var = "DSCAT",
                 tgt_val = "DISPOSITION EVENT") %>%

  # VISIT
  assign_no_ct(raw_dat = ds_raw, raw_var = "VISIT", tgt_var = "VISIT") %>%

  # Dates in ISO 8601
  assign_datetime(raw_dat = ds_raw, raw_var = "IT.DSSTDAT",
                  tgt_var = "DSSTDTC", raw_fmt = "m-d-y") %>%
  assign_datetime(raw_dat = ds_raw, raw_var = c("DSDTCOL", "DSTMCOL"),
                  tgt_var = "DSDTC", raw_fmt = c("m-d-y", "H:M"))

# STUDYID and USUBJID from DM
dm_ids <- dm %>%
  select(STUDYID, USUBJID) %>%
  mutate(patient_number = sub("^[^-]+-", "", USUBJID))

# VISITNUM from SV
visits <- sv %>% distinct(VISIT, VISITNUM)

# Reference date for study day
dm_ref <- dm %>%
  mutate(RFXSTDT = as.Date(substr(RFXSTDTC, 1, 10))) %>%
  select(USUBJID, RFXSTDT)

ds <- ds %>%
  left_join(dm_ids, by = "patient_number") %>%
  left_join(visits, by = "VISIT") %>%
  # sdtm.oak keeps dates in its own iso8601 class, so convert to text first
  mutate(DOMAIN  = "DS",
         DSSTDTC = as.character(DSSTDTC),
         DSDTC   = as.character(DSDTC),
         DSSTDT  = as.Date(substr(DSSTDTC, 1, 10))) %>%
  derive_study_day(dm_domain = dm_ref, tgdt = "DSSTDT",
                   refdt = "RFXSTDT", study_day_var = "DSSTDY") %>%
  derive_seq(tgt_var = "DSSEQ",
             rec_vars = c("STUDYID", "USUBJID", "DSSTDTC", "DSTERM")) %>%
  select(STUDYID, DOMAIN, USUBJID, DSSEQ, DSTERM, DSDECOD, DSCAT,
         VISITNUM, VISIT, DSDTC, DSSTDTC, DSSTDY) %>%
  arrange(USUBJID, DSSEQ)

# Save output
dir.create("question_1_sdtm", showWarnings = FALSE)
write.csv(ds, "question_1_sdtm/ds.csv", row.names = FALSE, na = "")

# Quick checks
nrow(ds_raw)
nrow(ds)
sum(is.na(ds$USUBJID))
sum(is.na(ds$VISITNUM))
table(ds$DSCAT, useNA = "ifany")
table(ds$DSDECOD, useNA = "ifany")
head(ds)

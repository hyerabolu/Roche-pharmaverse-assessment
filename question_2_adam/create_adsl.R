# Program: create_adsl.R
# Purpose: Create the ADaM ADSL (subject level) dataset with {admiral}
# Input:   pharmaversesdtm::dm, ex, vs, ae, ds
# Output:  question_2_adam/adsl.csv

library(admiral)
library(pharmaversesdtm)
library(dplyr)

# Read SDTM data and turn blank text values into NA
dm <- convert_blanks_to_na(pharmaversesdtm::dm)
ex <- convert_blanks_to_na(pharmaversesdtm::ex)
vs <- convert_blanks_to_na(pharmaversesdtm::vs)
ae <- convert_blanks_to_na(pharmaversesdtm::ae)
ds <- convert_blanks_to_na(pharmaversesdtm::ds)

# DM is the basis of ADSL
adsl <- dm %>%
  select(-DOMAIN)


# AGEGR9 / AGEGR9N: age groups <18, 18 - 50, >50 ------------------------------
agegr9_def <- exprs(
  ~condition,               ~AGEGR9,   ~AGEGR9N,
  AGE < 18,                 "<18",     1,
  AGE >= 18 & AGE <= 50,    "18 - 50", 2,
  AGE > 50,                 ">50",     3
)

adsl <- adsl %>%
  derive_vars_cat(definition = agegr9_def)


# TRTSDTM / TRTSTMF: first valid dose date-time -------------------------------
# Convert EXSTDTC / EXENDTC to datetimes.
# - Missing hours and minutes are imputed with 00 (time_imputation = "first")
# - The date part must be complete (highest_imputation = "h")
# - If only seconds are missing, the flag is not set (ignore_seconds_flag = TRUE)
ex_dt <- ex %>%
  derive_vars_dtm(dtc = EXSTDTC, new_vars_prefix = "EXST",
                  highest_imputation = "h", time_imputation = "first",
                  ignore_seconds_flag = TRUE) %>%
  derive_vars_dtm(dtc = EXENDTC, new_vars_prefix = "EXEN",
                  highest_imputation = "h", time_imputation = "last",
                  ignore_seconds_flag = TRUE)

# Valid dose: EXDOSE > 0, or EXDOSE = 0 for placebo
ex_valid <- ex_dt %>%
  filter(EXDOSE > 0 | (EXDOSE == 0 & grepl("PLACEBO", toupper(EXTRT))))

adsl <- adsl %>%
  # first exposure record -> treatment start
  derive_vars_merged(
    dataset_add = ex_valid,
    filter_add  = !is.na(EXSTDTM),
    by_vars     = exprs(STUDYID, USUBJID),
    order       = exprs(EXSTDTM, EXSEQ),
    mode        = "first",
    new_vars    = exprs(TRTSDTM = EXSTDTM, TRTSTMF = EXSTTMF)
  ) %>%
  # last exposure record -> treatment end (needed for LSTAVLDT)
  derive_vars_merged(
    dataset_add = ex_valid,
    filter_add  = !is.na(EXENDTM),
    by_vars     = exprs(STUDYID, USUBJID),
    order       = exprs(EXENDTM, EXSEQ),
    mode        = "last",
    new_vars    = exprs(TRTEDTM = EXENDTM)
  )


# ITTFL: Y if the subject was randomized (ARM populated), else N --------------
adsl <- adsl %>%
  mutate(ITTFL = if_else(!is.na(ARM), "Y", "N"))


# LSTAVLDT: last known alive date ---------------------------------------------
# Only complete dates are used (convert_dtc_to_dt returns NA for partial dates)

# (1) vital signs with a valid result
vs_dt <- vs %>%
  filter(!(is.na(VSSTRESN) & is.na(VSSTRESC))) %>%
  mutate(VSDT = convert_dtc_to_dt(VSDTC))

# (2) AE onset dates
ae_dt <- ae %>%
  mutate(AESTDT = convert_dtc_to_dt(AESTDTC))

# (3) disposition dates
ds_dt <- ds %>%
  mutate(DSSTDT = convert_dtc_to_dt(DSSTDTC))

# (4) last valid treatment date = date part of TRTEDTM (already in ADSL)

adsl <- adsl %>%
  derive_vars_extreme_event(
    by_vars = exprs(STUDYID, USUBJID),
    events = list(
      event(dataset_name  = "vs",
            condition     = !is.na(VSDT),
            set_values_to = exprs(LSTAVLDT = VSDT, seq = VSSEQ)),
      event(dataset_name  = "ae",
            condition     = !is.na(AESTDT),
            set_values_to = exprs(LSTAVLDT = AESTDT, seq = AESEQ)),
      event(dataset_name  = "ds",
            condition     = !is.na(DSSTDT),
            set_values_to = exprs(LSTAVLDT = DSSTDT, seq = DSSEQ)),
      event(dataset_name  = "adsl",
            condition     = !is.na(TRTEDTM),
            set_values_to = exprs(LSTAVLDT = as.Date(TRTEDTM), seq = 0))
    ),
    source_datasets  = list(vs = vs_dt, ae = ae_dt, ds = ds_dt, adsl = adsl),
    tmp_event_nr_var = event_nr,
    order            = exprs(LSTAVLDT, seq, event_nr),
    mode             = "last",
    new_vars         = exprs(LSTAVLDT)
  )


# Save output -----------------------------------------------------------------
dir.create("question_2_adam", showWarnings = FALSE)
write.csv(adsl, "question_2_adam/adsl.csv", row.names = FALSE, na = "")


# Quick checks (printed to the console / log) ---------------------------------
cat("Subjects in DM   :", nrow(dm), "\n")
cat("Subjects in ADSL :", nrow(adsl), "\n")
cat("Missing TRTSDTM  :", sum(is.na(adsl$TRTSDTM)), "\n")
cat("Missing LSTAVLDT :", sum(is.na(adsl$LSTAVLDT)), "\n")
cat("LSTAVLDT before treatment end:",
    sum(adsl$LSTAVLDT < as.Date(adsl$TRTEDTM), na.rm = TRUE), "\n")

print(count(adsl, AGEGR9N, AGEGR9))
print(count(adsl, ARM, ITTFL))
print(count(adsl, TRTSTMF))
print(head(select(adsl, USUBJID, AGE, AGEGR9, AGEGR9N, ARM, ITTFL,
                  TRTSDTM, TRTSTMF, TRTEDTM, LSTAVLDT), 10))

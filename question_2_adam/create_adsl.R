# ADSL: AGEGR9/N, TRTSDTM/TRTSTMF, ITTFL, LSTAVLDT
library(admiral)
library(pharmaversesdtm)
library(dplyr)
library(lubridate)
library(stringr)

dir.create("question_2_adam", showWarnings = FALSE)
sink("question_2_adam/create_adsl_log.txt", split = TRUE)

# ---- Inputs (blanks -> NA) ----
dm <- convert_blanks_to_na(pharmaversesdtm::dm)
vs <- convert_blanks_to_na(pharmaversesdtm::vs)
ex <- convert_blanks_to_na(pharmaversesdtm::ex)
ds <- convert_blanks_to_na(pharmaversesdtm::ds)
ae <- convert_blanks_to_na(pharmaversesdtm::ae)

adsl <- dm %>% select(-DOMAIN)

# ---- Exposure: datetimes, valid-dose records only ----
# Date must be complete (highest_imputation = "h"); time imputed with 00;
# ignore_seconds_flag = TRUE -> no TRTSTMF if only seconds are missing
ex_ext <- ex %>%
  derive_vars_dtm(
    dtc                 = EXSTDTC,
    new_vars_prefix     = "EXST",
    highest_imputation  = "h",
    time_imputation     = "first",
    flag_imputation     = "auto",
    ignore_seconds_flag = TRUE
  ) %>%
  derive_vars_dtm(
    dtc                = EXENDTC,
    new_vars_prefix    = "EXEN",
    highest_imputation = "h",
    time_imputation    = "last"
  )

valid_dose <- expr(
  EXDOSE > 0 | (EXDOSE == 0 & str_detect(toupper(EXTRT), "PLACEBO"))
)

adsl <- adsl %>%
  derive_vars_merged(
    dataset_add = ex_ext,
    filter_add  = !!valid_dose & !is.na(EXSTDTM),
    new_vars    = exprs(TRTSDTM = EXSTDTM, TRTSTMF = EXSTTMF),
    order       = exprs(EXSTDTM, EXSEQ),
    mode        = "first",
    by_vars     = exprs(STUDYID, USUBJID)
  ) %>%
  derive_vars_merged(
    dataset_add = ex_ext,
    filter_add  = !!valid_dose & !is.na(EXENDTM),
    new_vars    = exprs(TRTEDTM = EXENDTM),
    order       = exprs(EXENDTM, EXSEQ),
    mode        = "last",
    by_vars     = exprs(STUDYID, USUBJID)
  )

# ---- Age groups ----
adsl <- adsl %>%
  mutate(
    AGEGR9 = case_when(
      AGE < 18               ~ "<18",
      AGE >= 18 & AGE <= 50  ~ "18 - 50",
      AGE > 50               ~ ">50",
      TRUE                   ~ NA_character_
    ),
    AGEGR9N = case_when(
      AGEGR9 == "<18"     ~ 1,
      AGEGR9 == "18 - 50" ~ 2,
      AGEGR9 == ">50"     ~ 3,
      TRUE                ~ NA_real_
    )
  )

# ---- ITTFL: Y if ARM populated ----
adsl <- adsl %>%
  mutate(ITTFL = if_else(!is.na(ARM), "Y", "N"))

# ---- LSTAVLDT: max of complete dates from VS, AE, DS, TRTEDTM ----
adsl <- adsl %>%
  derive_vars_extreme_event(
    by_vars = exprs(STUDYID, USUBJID),
    events = list(
      event(
        dataset_name = "vs",
        order        = exprs(VSDTC, VSSEQ),
        condition    = !is.na(convert_dtc_to_dt(VSDTC)) &
          !(is.na(VSSTRESN) & is.na(VSSTRESC)),
        set_values_to = exprs(LSTAVLDT = convert_dtc_to_dt(VSDTC), seq = VSSEQ)
      ),
      event(
        dataset_name = "ae",
        order        = exprs(AESTDTC, AESEQ),
        condition    = !is.na(convert_dtc_to_dt(AESTDTC)),
        set_values_to = exprs(LSTAVLDT = convert_dtc_to_dt(AESTDTC), seq = AESEQ)
      ),
      event(
        dataset_name = "ds",
        order        = exprs(DSSTDTC, DSSEQ),
        condition    = !is.na(convert_dtc_to_dt(DSSTDTC)),
        set_values_to = exprs(LSTAVLDT = convert_dtc_to_dt(DSSTDTC), seq = DSSEQ)
      ),
      event(
        dataset_name = "adsl",
        condition    = !is.na(TRTEDTM),
        set_values_to = exprs(LSTAVLDT = as_date(TRTEDTM), seq = 0)
      )
    ),
    source_datasets = list(vs = vs, ae = ae, ds = ds, adsl = adsl),
    tmp_event_nr_var = event_nr,
    order    = exprs(LSTAVLDT, seq, event_nr),
    mode     = "last",
    new_vars = exprs(LSTAVLDT)
  )

# ---- Self-QC ----
cat("\nN subjects:", n_distinct(adsl$USUBJID), "| dup USUBJID:",
    sum(duplicated(adsl$USUBJID)), "\n")
print(count(adsl, AGEGR9, AGEGR9N))
print(count(adsl, ARM, ITTFL))
print(count(adsl, TRTSTMF))
cat("Missing TRTSDTM:", sum(is.na(adsl$TRTSDTM)),
    "| Missing LSTAVLDT:", sum(is.na(adsl$LSTAVLDT)), "\n")
cat("LSTAVLDT < TRTSDTM date:",
    sum(adsl$LSTAVLDT < as_date(adsl$TRTSDTM), na.rm = TRUE), "\n")

# ---- Save ----
saveRDS(adsl, "question_2_adam/adsl.rds")
write.csv(adsl, "question_2_adam/adsl.csv", row.names = FALSE, na = "")
sink()
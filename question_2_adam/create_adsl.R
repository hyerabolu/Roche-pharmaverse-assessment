# ADSL: AGEGR9/N, TRTSDTM/TRTSTMF, ITTFL, LSTAVLDT
library(admiral)
library(pharmaversesdtm)
library(dplyr)
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

# ---- Exposure: keep valid doses only, then make datetimes ----
# Valid dose: EXDOSE > 0, or EXDOSE = 0 with PLACEBO in EXTRT
ex_valid <- ex %>%
  filter(EXDOSE > 0 | (EXDOSE == 0 & str_detect(toupper(EXTRT), "PLACEBO"))) %>%
  derive_vars_dtm(
    dtc                 = EXSTDTC,
    new_vars_prefix     = "EXST",
    highest_imputation  = "h",    # date must be complete
    time_imputation     = "first",# missing time -> 00:00:00
    flag_imputation     = "auto",
    ignore_seconds_flag = TRUE    # no flag if only seconds missing
  ) %>%
  derive_vars_dtm(
    dtc                = EXENDTC,
    new_vars_prefix    = "EXEN",
    highest_imputation = "h",
    time_imputation    = "last"
  )

# ---- TRTSDTM / TRTSTMF: first valid dose ----
adsl <- adsl %>%
  derive_vars_merged(
    dataset_add = ex_valid,
    filter_add  = !is.na(EXSTDTM),
    new_vars    = exprs(TRTSDTM = EXSTDTM, TRTSTMF = EXSTTMF),
    order       = exprs(EXSTDTM, EXSEQ),
    mode        = "first",
    by_vars     = exprs(STUDYID, USUBJID)
  ) %>%
  # ---- TRTEDTM: last valid dose (needed for LSTAVLDT) ----
derive_vars_merged(
  dataset_add = ex_valid,
  filter_add  = !is.na(EXENDTM),
  new_vars    = exprs(TRTEDTM = EXENDTM),
  order       = exprs(EXENDTM, EXSEQ),
  mode        = "last",
  by_vars     = exprs(STUDYID, USUBJID)
)

# ---- AGEGR9 / AGEGR9N ----
adsl <- adsl %>%
  mutate(
    AGEGR9 = case_when(
      AGE < 18              ~ "<18",
      AGE >= 18 & AGE <= 50 ~ "18 - 50",
      AGE > 50              ~ ">50"
    ),
    AGEGR9N = case_when(
      AGEGR9 == "<18"     ~ 1,
      AGEGR9 == "18 - 50" ~ 2,
      AGEGR9 == ">50"     ~ 3
    )
  )

# ---- ITTFL: Y if ARM is populated ----
adsl <- adsl %>%
  mutate(ITTFL = if_else(!is.na(ARM), "Y", "N"))

# ---- LSTAVLDT: latest complete date from VS, AE, DS, TRTEDTM ----
# "Complete" = full date YYYY-MM-DD (at least 10 characters)
vs_dt <- vs %>%
  filter(nchar(VSDTC) >= 10, !(is.na(VSSTRESN) & is.na(VSSTRESC))) %>%
  transmute(USUBJID, DT = as.Date(substr(VSDTC, 1, 10)))

ae_dt <- ae %>%
  filter(nchar(AESTDTC) >= 10) %>%
  transmute(USUBJID, DT = as.Date(substr(AESTDTC, 1, 10)))

ds_dt <- ds %>%
  filter(nchar(DSSTDTC) >= 10) %>%
  transmute(USUBJID, DT = as.Date(substr(DSSTDTC, 1, 10)))

trt_dt <- adsl %>%
  filter(!is.na(TRTEDTM)) %>%
  transmute(USUBJID, DT = as.Date(TRTEDTM))

last_alive <- bind_rows(vs_dt, ae_dt, ds_dt, trt_dt) %>%
  group_by(USUBJID) %>%
  summarise(LSTAVLDT = max(DT, na.rm = TRUE), .groups = "drop")

adsl <- adsl %>% left_join(last_alive, by = "USUBJID")

# ---- Self-QC ----
cat("\nN subjects:", n_distinct(adsl$USUBJID),
    "| dup USUBJID:", sum(duplicated(adsl$USUBJID)), "\n")
print(count(adsl, AGEGR9, AGEGR9N))
print(count(adsl, ARM, ITTFL))
print(count(adsl, TRTSTMF))
cat("Missing TRTSDTM:", sum(is.na(adsl$TRTSDTM)),
    "| Missing LSTAVLDT:", sum(is.na(adsl$LSTAVLDT)), "\n")
cat("LSTAVLDT < TRTSDTM date:",
    sum(adsl$LSTAVLDT < as.Date(adsl$TRTSDTM), na.rm = TRUE), "\n")

# ---- Save ----
saveRDS(adsl, "question_2_adam/adsl.rds")
write.csv(adsl, "question_2_adam/adsl.csv", row.names = FALSE, na = "")
sink()
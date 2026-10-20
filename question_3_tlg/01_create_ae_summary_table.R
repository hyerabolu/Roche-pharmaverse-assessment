# Q3.1 TEAE summary table with {gtsummary}
library(pharmaverseadam)
library(dplyr)
library(gtsummary)
library(gt)

dir.create("question_3_tlg", showWarnings = FALSE)
sink("question_3_tlg/01_create_ae_summary_table_log.txt", split = TRUE)

# Safety population = denominator for percentages
adsl <- pharmaverseadam::adsl %>% filter(SAFFL == "Y")

# Treatment-emergent AEs only, for subjects in the denominator
adae <- pharmaverseadam::adae %>%
  filter(TRTEMFL == "Y", USUBJID %in% adsl$USUBJID)

# Table: rows = SOC then AE term, columns = treatment arm, n (%) of subjects
tbl <- tbl_hierarchical(
  data        = adae,
  variables   = c(AESOC, AETERM),
  by          = ACTARM,
  denominator = adsl,
  id          = USUBJID,
  overall_row = TRUE,
  label       = list(
    "..ard_hierarchical_overall.." = "Treatment Emergent AEs",
    AESOC  = "Primary System Organ Class",
    AETERM = "Reported Term for the Adverse Event"
  )
) %>%
  add_overall(last = TRUE) %>%   # total column, all subjects
  sort_hierarchical()            # most frequent first

# Save as HTML
as_gt(tbl) %>% gtsave("question_3_tlg/ae_summary_table.html")

# Self-QC
cat("Safety N:", nrow(adsl), "\n")
print(count(adsl, ACTARM))
cat("Subjects with a TEAE:", n_distinct(adae$USUBJID), "\n")
sink()
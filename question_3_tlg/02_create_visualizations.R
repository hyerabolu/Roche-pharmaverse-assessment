# Q3.2 Plots with {ggplot2}
library(pharmaverseadam)
library(dplyr)
library(ggplot2)

dir.create("question_3_tlg", showWarnings = FALSE)
sink("question_3_tlg/02_create_visualizations_log.txt", split = TRUE)

# All AE records in ADAE
adae <- pharmaverseadam::adae

# ---- Plot 1: AE severity by treatment (stacked bar) ----
p1 <- ggplot(adae, aes(x = ACTARM, fill = AESEV)) +
  geom_bar() +
  labs(title = "AE severity distribution by treatment",
       x = "Treatment Arm", y = "Count of AEs", fill = "Severity/Intensity")
ggsave("question_3_tlg/plot1_ae_severity.png", p1, width = 8, height = 6, dpi = 300)

# ---- Plot 2: Top 10 AEs with 95% Clopper-Pearson CI ----
N <- n_distinct(adae$USUBJID)      # subjects in ADAE

top10 <- adae %>%
  distinct(USUBJID, AETERM) %>%    # count each subject once per AE
  count(AETERM) %>%
  arrange(desc(n)) %>%
  slice_head(n = 10) %>%
  rowwise() %>%
  mutate(pct = n / N * 100,
         lo  = binom.test(n, N)$conf.int[1] * 100,   # exact CI
         hi  = binom.test(n, N)$conf.int[2] * 100) %>%
  ungroup() %>%
  mutate(AETERM = reorder(AETERM, pct))

p2 <- ggplot(top10, aes(x = pct, y = AETERM)) +
  geom_errorbar(aes(xmin = lo, xmax = hi), orientation = "y", width = 0.3) +
  geom_point(size = 3) +
  labs(title = "Top 10 Most Frequent Adverse Events",
       subtitle = paste0("n = ", N, " subjects; 95% Clopper-Pearson CIs"),
       x = "Percentage of Patients (%)", y = NULL)
ggsave("question_3_tlg/plot2_top10_ae.png", p2, width = 9, height = 6, dpi = 300)

print(top10)
sink()
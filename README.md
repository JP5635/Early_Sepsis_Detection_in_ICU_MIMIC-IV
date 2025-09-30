# Early Sepsis Detection in ICU (MIMIC-IV)

### Project Overview

This project aims to develop a pipeline for early detection of sepsis in ICU patients using the MIMIC-IV database.
The focus is on deriving hourly SOFA (Sequential Organ Failure Assessment) scores and related clinical features to monitor patient deterioration and detect sepsis onset early.

---

### Objectives
- Extract a sepsis cohort from MIMIC-IV based on ICD-9/10 diagnosis codes and SOFA scores
- String matches with sepsis-related ICD-9/10 codes
    - The relvant ICD 10 codes can be found [here](https://icd.who.int/browse10/2019/en)
- Compute hourly SOFA scores across all six organ systems:
    - Respiratory (PaO₂/FiO₂, ventilation status)
    - Cardiovascular (MAP, vasopressor support)
    - Liver (bilirubin)
    - Coagulation (platelets)
    - Renal (creatinine, urine output)
    - CNS (GCS)
    - Build a feature set for early sepsis detection models.
    - Evaluate the potential of SOFA trajectory monitoring for predicting septic shock or ICU mortality.

---

### Data Source
- MIMIC-IV v3.1 (Published: Oct. 11, 2024. Version: 3.1 on PhysioNet)
    - Tables used include:
        - mimiciv_3_1_hosp.diagnoses_icd → identifying sepsis patients
        - mimiciv_3_1_icu.chartevents → vital signs, labs, scores
        - mimiciv_3_1_icu.inputevents → vasopressors and fluids
        - mimiciv_3_1_icu.outputevents → urine output
        - mimiciv_3_1_hosp.labevents → labs (bilirubin, platelets, creatinine, ABGs)
        - mimiciv_3_1_icu.icustays → ICU admission/discharge timestamps
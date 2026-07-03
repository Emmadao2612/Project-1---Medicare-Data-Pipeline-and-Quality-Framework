# Project 1 - Medicare Data Pipeline and Quality Framework

**CMS Medicare Part B 2023 | 9,660,647 rows | PostgreSQL**

Project 1 of 4 | **Data Pipeline and Quality Framework** | Billing Behavior | Geographic Equity | Anomaly Detection

---

## Table of Contents

- [Series Framework](#series-framework)
- [Overview](#overview)
- [The Dataset](#the-dataset)
  - [Source](#source)
  - [What this dataset is](#what-this-dataset-is)
  - [Size and scope](#size-and-scope-query-11)
  - [Column reference](#column-reference)
- [Key Terms Glossary](#key-terms-glossary)
- [Data Quality Framework](#data-quality-framework)
  - [Why this matters](#why-this-matters)
  - [The 7 phases of quality checks](#the-7-phases-of-quality-checks)
  - [Baseline exclusion filter](#baseline-exclusion-filter-query-126)
- [Database Design](#database-design)
- [Limitations](#limitations)
- [Files](#files)
- [Tools](#tools)
- [References](#references)

---

## Series Framework

This is Project 1 of a four-part analysis of Medicare Provider billing and payment patterns across the United States. Each project builds on the clean dataset produced here.

```
Project 1 - Medicare Data Pipeline and Quality Framework  
Project 2 - Medicare Billing Behavior Analysis
Project 3 - Medicare Geographic Equity Analysis
Project 4 - Medicare Anomaly Detection
```

The pipeline follows 8 stages from raw data to final key findings:

```
Stage 1: Data Acquisition        Download 9.66M row public file from CMS website
Stage 2: Database Setup          Create table, load data, build indexes
Stage 3: Data Quality            22 quality checks across 7 phases (Section A-G), impact verification queries (Section H)
Stage 4: Billing Analysis        Specialty-level markup ratios vs 2021 benchmarks - Project 2
Stage 5: Geographic Equity       Rural vs urban payment gaps after standardization - Project 3
Stage 6: Anomaly Detection       Z-score outliers within specialty peer groups - Project 4
Stage 7: Tableau Dashboards      Interactive visualizations for a policy audience
Stage 8: Key Findings            Policy recommendations with methodology notes
```

---

## Overview

Most analysts load a healthcare dataset and start querying. This project validates first.

The CMS Medicare dataset is one of the most widely used public healthcare datasets in the United States, and one of the most structurally complex. It is assembled from hundreds of millions of individual claims, pre-aggregated by CMS, and published as a single flat file. That process introduces artifacts that are invisible to surface inspection but corrupt analytical findings if not addressed. 

This project documents a quality check framework applied to the 2023 dataset. The framework produced a baseline exclusion filter that removes fewer than 6% of rows. Without it, the key findings in the downstream projects will be distorted. 

---

## The Dataset

### Source

**Centers for Medicare & Medicaid Services (CMS)**
Medicare Physician & Other Practitioners - By Provider and Service, 2023.

[Click to download the dataset here.](https://data.cms.gov/provider-summary-by-type-of-service/medicare-physician-other-practitioners/medicare-physician-other-practitioners-by-provider-and-service)

### What this dataset is

This is a **billing summary file**, not a claims file or a patient record file. CMS takes every Medicare Part B claim submitted in 2023, groups them by provider and procedure code, and publishes one summary row per group. This means:

- **One row** = one provider + one procedure code + all the services performed and paid in 2023
- **Not a patient encounter** - a provider who saw 500 patients for office visits appears once for that procedure code, with the total volume and average payment across all 500 visits
- **Not a financial record** - payment columns show what Medicare paid from its own funds; patient copays, Medigap payments, and supplemental insurance are not captured

This distinction matters for every calculation in the series. Summing total patients across rows double counts patients who received more than one service type. The correct volume measure is to use total services performed.

### Size and scope (Query 1.1)

| Dimension | Value |
|----|----|
| Total rows | 9,660,647 |
| Individual providers | 9,123,559 (94.4% of total rows) |
| Organizational providers | 537,088 (5.6% of total rows) |
| Distinct providers (NPIs) | 1,175,281 |
| Distinct procedure codes (HCPCS) | 6,405 |
| Distinct specialties | 104 |
| Geographic coverage | 62 jurisdictions (50 states + DC + 5 territories + 6 military/unresolvable codes) |

### Column reference

[Column_Reference_Guide.pdf](Column_Reference_Guide.pdf)

---

## Key Terms Glossary

[Key_Terms_Glossary.pdf](Key_Terms_Glossary.pdf)

---

## Data Quality Framework

### Why this matters

Skipping quality checks not only risks minor inaccuracies but also produces specific wrong numbers. The table below shows what might change with and without the filter:

| Quality check | Without filter | With filter | Impact on findings |
|----|----|----|----|
| COVID vaccine code exclusion (Query 1.7, 1.23) | Billed-to-allowed ratio:<br>Pharmacy: 3,438;<br> Emergency Medicine: 2,754;<br> Cardiology: 2,191 | Billed-to-allowed ratio:<br>Pharmacy: 1;<br> Emergency Medicine: 6;<br> Cardiology: 3 | Corrupts the specialty ratio analysis for some specialties |
| Drug procedure filter (Query 1.24) | Rural payment gap: +$0.21 (Negligible) | -$6.36 | With the drug filter applied, a real payment gap emerges<br> Without the filter, drugs dominate rural payment and mask the true urban-rural physician pay gap |
| Billing ceiling exclusion ($99,999.99) (Query 1.4, 1.6, 1.25) | Unknown true maximum value (12 rows) | $99,999.68 - a legitimate high-cost procedure | Prevents Z-score contamination in Project 4 |
| Logical violation exclusion (Query 1.6) | 7,861 rows with logical violations<br> (6,573 rows where allowed > billed + 1,288 rows paid > billed) | 0 such rows | Prevents ratios below 1.0 in billing analysis |
| Geographic exclusions (Query 1.1, 1.10, 1.11, 1.15, 1.16) | 62 distinct jurisdictions<br> (50 states + DC + territories + military codes) | 50 states + DC | Prevents military codes from distorting geographic analysis |

### The 7 phases of quality checks

**Phase 1: Understand the data (Queries 1.1, 1.2, 1.3, 1.4)**

Establish the data scope before writing any quality check. Full scope metrics were documented in the Dataset section above.

This phase provides key findings:
- Total rows, distinct providers, distinct procedure codes, entity type split
- Top specialty by volume is Clinical Laboratory (organizational), driven by routine test processing at scale
- Median Medicare payment is $53.10 with a long right tail: the 99th percentile is $654.92, and the maximum value is $42,059.52
- Average billed charge maximum is at $99,999.99, which is the billing ceiling artifact that will be investigated further in Phase 3

**Phase 2: Missing data audit (Query 1.5)**

Check key columns for null and zero values as they mean different things. Null means the value was not recorded. Zero value means it was explicitly recorded as zero, which is a meaningful distinction in financial columns.

- Zero true nulls across the key columns - exceptionally clean dataset
- 0 zero values in avg_billed_charge - every row has a nonzero billed amount
- 66 zero values in avg_medicare_payment could be a data entry error, not a real payment event
- 13 zero values in avg_allowed_amount could be a data entry error, experimental procedures, or non-covered services
- 234 zero values in avg_standardized_payment mean the geographic adjustment eliminated the entire payment, which is implausible

The avg_medicare_payment and avg_allowed_amount zero values above are excluded by the baseline filter. 
The avg_standardized_payment zero values are not. Any query using that column must filter them separately (see Baseline exclusion filter below).

**Phase 3: Validity checks (Queries 1.6, 1.7, 1.8, 1.9)**

Check for values that are present but logically impossible.

| Check | Rows flagged | Decision |
|----|----|----|
| avg_medicare_payment > avg_billed_charge | 1,288 (0.0133%) | Exclude - Medicare cannot pay more than billed |
| avg_medicare_payment > avg_allowed_amount | 0 | Clean - Medicare payment never exceeds the allowed amount |
| avg_allowed_amount > avg_billed_charge | 6,573 (0.068%) | Exclude - allowed cannot exceed billed |
| avg_standardized_payment > avg_medicare_payment x 3 | 6,383 (0.0661%) | Not excluded - concentrated in low-dollar primary care specialties, not a data error |
| avg_medicare_payment > avg_standardized_payment x 3 | 1,815 (0.0188%) | Not excluded - concentrated in Ambulance Service Provider, not a data error |
| total_services_performed < total_patients | 67 (0.0007%) | Exclude - cannot serve fewer times than patients seen |
| avg_billed_charge = $99,999.99 | 12 (0.0001%) | Exclude - system ceiling, true value unknown |
| avg_medicare_payment > $50,000 | 0 | Clean - no implausibly high payments |
| billed_to_allowed ratio above 100x | 12,600 rows with ratio > 100x | Exclude 6 COVID vaccine codes which account for 237 of the 12,600 flagged rows (out of 1,322 total rows billed under those 6 codes) |
| total_service_days > total_services_performed | 151 (0.0016%) | Exclude - more days than service events is impossible |
| total_patients between 1-10 | 0 | No CMS suppression rows where total_patients < 11 |

**Note:**
Base population differs by query. 
- Query 1.6 requires avg_medicare_payment, avg_billed_charge, and avg_allowed_amount > 0 (9,660,581 rows) - avg_billed_charge has no zero values, and the 13 zero-allowed-amount rows are a subset of the 66 zero-payment rows.
- Query 1.7 requires avg_billed_charge and avg_allowed_amount > 0. 
- Query 1.8 requires total_services_performed > 0. 
- Query 1.9 applies no filter (full 9,660,647 rows). Percentages are relative to each row's own base.

Drug procedures will be excluded by the drug filter in analytical queries as they follow different billing structures. The non-vaccine extreme ratio outliers identified:  
- J2001 (Lidocaine injection) at 35,586x with avg_allowed of $0.03
- J7613 (Albuterol inhalation) at 14,175.82x with avg_allowed of $0.04
- J0665 (Bupivacaine injection) at 14,000x with avg_allowed of $0.02

**Phase 4: Consistency checks (Queries 1.10, 1.11, 1.12, 1.13)**

Verify categorical columns contain only expected values and that related columns are internally consistent.

- provider_entity_type: only 'I' and 'O' found - No invalid values
- is_drug_procedure: only 'Y' and 'N' found - Clean
- service_location_type: only 'F' and 'O' found - Clean
- country: 23 distinct values with 9,660,252 US rows (99.99%). 395 non-US rows across 22 countries - Excluded by baseline filter
- state: 62 distinct values with 50 states + DC confirmed, plus military codes (AP, AE, AA), territories (PR, GU, VI, MP, AS), and unresolvable placeholders (ZZ, XX, FM) all of which are excluded by the geographic filter
- RUCA codes 10.1, 10.2, 10.3: appear invalid (above scale maximum of 10) but are legitimate USDA rural sub-codes - Retained and reclassified correctly
- RUCA code 99: CMS placeholder for unmappable zip codes - Excluded from urban/rural analysis
- 0 procedure codes with multiple descriptions. CMS description labels are consistent across all providers.
- Correlation is 0.9940, suggesting standardized and actual payments are highly correlated as expected. This confirms both columns measure the same underlying payment with standardized payment having the geographic component removed.
- avg_std_to_actual ratio is 1.0023, suggesting the geographic adjustments cancel out at the national average across the dataset. A near 1.0 average does not mean equal payments across regions, which is tested in Project 3. 
- stddev is 0.9634, which is nearly as large as the mean of 1.0023, meaning individual provider payments vary widely around the national average after geographic adjustment. Residual variation after the standardization is investigated in Project 3.

**Phase 5: Structural checks (Queries 1.15, 1.16)**

Check VARCHAR columns that should contain only numeric data to confirm no structural corruption occurred during CSV import. Query 1.14 confirms the implicit import check. All 7 NUMERIC columns were validated by PostgreSQL at \copy time.

- 9,660,610 rows with correct 5-digit zip codes
- 37 short zip codes found (under 5 digits), all in ZZ/XX states - Excluded by geographic filter
- NPI: all 10 digits, numeric only, no wrong length - Clean across all 1.18M providers 
- RUCA: 0 non-numeric - Confirms CAST in Query 1.11 is safe
- 96 non-numeric zip codes: Canadian postal codes in ZZ rows - Excluded
- 1,691 non-numeric FIPS codes (9A-9E): CMS placeholders for military/unresolvable addresses - Excluded

**Phase 6: Uniqueness checks (Queries 1.17, 1.18)**

Confirm the natural primary key and rule out true duplicates.

- Natural primary key: provider_id + procedure_code + service_location_type
- The same provider can bill the same procedure in both facility (F) and office (O) settings - these are two valid separate rows
- 0 duplicate rows found on the three-part key - No true duplicates in the dataset
- 9,318,769 distinct provider-procedure combinations vs 9,660,647 total rows
- The 341,878 difference is entirely explained by providers billing the same procedure in both facility and office settings
- Unexplained_difference = 0, reflecting zero true duplicates across all 9,660,647 rows

**Phase 7: Identity checks (Queries 1.19, 1.20, 1.21, 1.22)**

Verify that each provider (NPI) is represented consistently across all rows with the same specialty, entity type, state, and name.

All four checks returned zero rows:
- 0 providers with multiple specialties - every NPI maps to exactly one specialty. Specialty-level aggregation in Project 2 is unambiguous
- 0 providers with multiple entity types - no NPI appears as both individual and organization. Entity type is consistent with NPI registration
- 0 providers in multiple states - every NPI is tied to one state. Geographic assignment in Project 3 is unambiguous
- 0 providers with name variants - no name inconsistencies across rows for any NPI

These four checks collectively confirm that the NPI is a reliable, stable identifier across the entire dataset. 
Provider-level aggregation in Project 4 can be performed on NPI without risk of double-counting or misclassification.

### Baseline exclusion filter (Query 1.26)

Every analytical query in Projects 2, 3, and 4 applies this filter. Each condition traces directly to a numbered check above.

```sql
WHERE avg_medicare_payment      > 0                             -- Phase 2: zero payment rows
  AND avg_billed_charge         > 0                             -- Phase 2: zero billed rows      
  AND avg_allowed_amount        > 0                             -- Phase 2: zero allowed rows
  AND avg_medicare_payment      <= avg_billed_charge            -- Phase 3: logical violation
  AND avg_allowed_amount        <= avg_billed_charge            -- Phase 3: logical violation
  AND total_services_performed  >= total_patients               -- Phase 3: impossible value
  AND total_service_days        <= total_services_performed     -- Phase 3: impossible value
  AND avg_billed_charge         < 99999.99                      -- Phase 3: billing ceiling
  AND procedure_code            NOT IN (
      '91312','91313','91300','91301','91305','91309')          -- Phase 3: COVID vaccine artifact
  AND is_drug_procedure         = 'N'                           -- Analytical scope
  AND country                   = 'US'                          -- Phase 4: US providers only
  AND state NOT IN (
      'AP','AE','AA','ZZ','XX','FM',                            -- Phase 4: military and unresolvable
      'PR','GU','VI','MP','AS'                                  -- Phase 4: territories
  )
```

Note: This baseline does not exclude NULL/Blank/'99' RUCA codes, nor rows where avg_standardized_payment = 0. Any downstream query must apply these exclusions based on which columns it uses: 
- Queries using ruca_urban_code must exclude NULL, blank, and '99' values.
- Queries using avg_standardized_payment must exclude 0 values.

```sql
WHERE ruca_urban_code IS NOT NULL
    AND ruca_urban_code != ''
    AND ruca_urban_code != '99'
    AND avg_standardized_payment > 0;
```

**Rows excluded:** approximately 564,447 (<6% of 9,660,647)
**Rows retained for analysis:** 9,096,200 (> 94%)

---

## Database Design

### Schema

All objects live in the `hc` schema (healthcare), isolated from other databases on the same PostgreSQL instance.

```
hc.medicare_providers_raw - Raw table: CMS column names, never modified
hc.medicare_providers_view - Semantic view: readable aliases, used by all queries
```

### Why a raw table + semantic view

The raw table preserves the original CMS structure exactly. The semantic view provides readable aliases (e.g. `Rndrng_Prvdr_Type` as `provider_specialty`) used consistently across all downstream queries. If CMS changes column names in a future release, only the view needs updating, not every analytical query.

### Indexes

Five indexes built on the raw table after data loading. The view inherits them automatically.

| Index | Column | Used in |
|----|----|----|
| idx_specialty | Rndrng_Prvdr_Type | Project 2 - Specialty grouping |
| idx_hcpcs | HCPCS_Cd | Project 2 - Procedure analysis, Project 4 - Coefficient of Variation |
| idx_state | Rndrng_Prvdr_State_Abrvtn | Project 3 - Geographic analysis |
| idx_npi | Rndrng_NPI | Project 4 - Provider-level aggregation |
| idx_ruca | Rndrng_Prvdr_RUCA | Project 3 - Urban/rural classification |

**Note:** Indexes are built after loading all data, never before. Building indexes during a 9.66M row bulk import forces PostgreSQL to update the index structure for every row, which is 5x to 10x slower than indexing once on the completed dataset.

---

## Limitations

**CMS suppression bias:** CMS removes any record derived from 10 or fewer beneficiaries before publication, so these rows never appear in the dataset. Small rural providers and rare high-cost procedures are underrepresented. Geographic equity findings in Project 3 likely understate the rural provider shortage.

**Pre-aggregated averages:** This is not a claims file. CMS pre-aggregates payments to averages before publication. Multiplying avg_medicare_payment x total_services_performed produces an estimate of total spend, not an exact figure. All spend totals in this series are noted as estimated.

**Medicare Part B only:** This dataset covers outpatient physician services only. Hospital inpatient (Part A), retail pharmacy drugs (Part D), and Medicare Advantage (Part C) plans are separate programs not represented here. Even within Part B, the 80% statutory rate applies to the allowed amount per claim after the annual deductible is met, not to total annual costs. The gap between the statutory rate and the deductible-adjusted coverage rate is explored in Project 2.

**Non-participating providers absent:** Providers who do not accept Medicare assignment are excluded from the data. Some specialties such as concierge medicine and elective cosmetic surgery are underrepresented as a result.

**US territories excluded from geographic analysis:** Puerto Rico, Guam, Virgin Islands, American Samoa, and Northern Mariana Islands are valid Medicare jurisdictions present in the raw data (20,199 rows confirmed in Query 1.10) but excluded from all analysis in Projects 2, 3, and 4. All analytical queries in this series are scoped to 50 states and Washington DC only.

## Files

| File | Description |
|----|----|
| [0_create_table_medicare.sql](0_create_table_medicare.sql) | Schema setup, table creation, semantic view, indexes and verification queries |
| [1_data_quality.sql](1_data_quality.sql) | 22 quality checks across 7 phases (Section A-G), impact verification queries (Section H) |
| [Key_Terms_Glossary.pdf](Key_Terms_Glossary.pdf) | Glossary of Medicare billing terminology used throughout the series |
| [Column_Reference_Guide.pdf](Column_Reference_Guide.pdf) | CMS raw column to readable alias mapping reference |

---

## Tools

| Tool | Purpose |
|----|----|
| PostgreSQL 17 | Data storage, indexing, quality checks, analytical views |
| psql | Bulk data loading via `\copy` command |
| pgAdmin | Query execution and result inspection |
| VS Code | SQL and notebook editing, documentation |

---

## References

| Source | Used for | Link |
|----|----|----|
| CMS Medicare Physician & Other Practitioners by Provider and Service | 2023 Dataset - Part B (Medical Insurance) beneficiaries by physicians and other healthcare professionals | [cms.gov](https://data.cms.gov/provider-summary-by-type-of-service/medicare-physician-other-practitioners/medicare-physician-other-practitioners-by-provider-and-service/data/2023) |
| CMS Medicare Physician & Other Practitioners by Provider and Service Data Dictionary | Column Reference Guide | [cms.gov](https://data.cms.gov/resources/medicare-physician-other-practitioners-by-provider-and-service-data-dictionary) |
| Medicare Physician & Other Practitioners Methodology | Key Terms Glossary | [cms.gov](https://data.cms.gov/resources/medicare-physician-other-practitioners-methodology) |
| Health Resources & Services Administration (HRSA) | RUCA Code classification (Urban: 1-3, Rural: 4-10 including 10.1-10.3) | [hrsa.gov](https://www.hrsa.gov/rural-health/about-us/what-is-rural) |

---

*Part of the Medicare Provider Billing and Payment Analysis series. Projects 2, 3, and 4 build directly on the clean dataset produced here.*
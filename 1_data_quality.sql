-- Series: Medicare Provider Billing and Payment Analysis
-- Project 1: Medicare Data Pipeline and Quality Framework
-- Purpose: Implement 22 quality checks across 7 phases (Section A-G), plus 4 filter impact verification queries (Section H)
--          to establish baseline exclusion filter for downstream projects
-- Inputs:  hc.medicare_providers_view
-- Outputs: Baseline exclusion filter (Query 1.26) which is applied in Projects 2, 3, and 4

-- Section sequence:
-- Section A: Landscape Checks (Phase 1) - Understand the dataset before checking quality
-- Section B: Completeness Checks (Phase 2) - Check nulls and zero values in key columns to identify potential data quality issues
-- Section C: Validity Checks (Phase 3) - Check that values fall within expected ranges and adhere to logical constraints 
-- Section D: Consistency Checks (Phase 4) - Categorical values for valid rows to audit distinct values and relationships
-- Section E: Structural Checks (Phase 5) - Structural checks on VARCHAR columns
-- Section F: Uniqueness Checks (Phase 6) - Check for duplicates, establish the grain of the dataset
-- Section G: Identity Checks (Phase 7) - Provider-level consistency
-- Section H: Filter Impact Verification - Verify the impact of identified data quality issues


-- 1.The data quality and landscape checks for the Medicare Providers dataset

-- Section A: Landscape checks (Phase 1 - Queries 1.1 - 1.4)
-- Purpose: Establish the scope and the shape of the dataset before diving into any quality checks.

-- 1.1. Dataset scope - providers, procedures, volume, and geography

SELECT
    COUNT(*)                                        AS total_rows,
    COUNT(DISTINCT provider_id)                     AS distinct_providers,
    COUNT(DISTINCT procedure_code)                  AS distinct_hcpcs_codes,
    COUNT(DISTINCT provider_specialty)              AS distinct_specialties,
    COUNT(DISTINCT state)                           AS distinct_states,

    -- Entity type split
    SUM(CASE WHEN provider_entity_type = 'I' 
        THEN 1 ELSE 0 END)                          AS rows_individual_providers,
    SUM(CASE WHEN provider_entity_type = 'O' 
        THEN 1 ELSE 0 END)                          AS rows_org_providers,
    SUM(CASE WHEN provider_entity_type 
        NOT IN ('I','O') 
        OR provider_entity_type IS NULL 
        THEN 1 ELSE 0 END)                          AS rows_unknown_entity

FROM hc.medicare_providers_view;

-- 1.2. Top specialties by volume

SELECT
    provider_specialty,
    provider_entity_type,
    COUNT(DISTINCT provider_id)             AS distinct_providers,
    SUM(total_services_performed)           AS total_services,
    SUM(total_patients)                     AS total_patients_billed,
    ROUND(AVG(avg_medicare_payment), 2)     AS avg_pmt_unweighted,    -- unweighted average across rows - landscape check only
    ROUND(SUM(total_services_performed) /
        COUNT(DISTINCT provider_id), 0)     AS avg_services_per_provider

FROM hc.medicare_providers_view
WHERE provider_specialty IS NOT NULL
AND avg_medicare_payment > 0
GROUP BY provider_specialty, provider_entity_type
ORDER BY total_services DESC;

--1.3. Top procedures by volume

SELECT
    procedure_code,
    procedure_description,
    is_drug_procedure,
    COUNT(DISTINCT provider_id)             AS distinct_providers,
    SUM(total_services_performed)           AS total_services,
    SUM(total_patients)                     AS total_patient_events,
    ROUND(AVG(avg_medicare_payment), 2)     AS avg_pmt_unweighted,      -- unweighted average across rows - landscape check only
    ROUND(AVG(avg_billed_charge), 2)        AS avg_billed_unweighted,   -- unweighted average across rows - landscape check only
    ROUND(AVG(avg_allowed_amount), 2)       AS avg_allowed_unweighted,  -- unweighted average across rows - landscape check only
    ROUND(SUM(avg_billed_charge * total_services_performed) /
    NULLIF(SUM(avg_allowed_amount * total_services_performed), 0)
    , 2)                                    AS billed_to_allowed_ratio,
    ROUND(SUM(avg_billed_charge * total_services_performed) /
        NULLIF(SUM(avg_medicare_payment * total_services_performed), 0)
    , 2)                                    AS billed_to_paid_ratio

FROM hc.medicare_providers_view
WHERE procedure_code IS NOT NULL
AND avg_medicare_payment > 0
AND avg_billed_charge > 0
GROUP BY procedure_code, procedure_description, is_drug_procedure
ORDER BY total_services DESC
LIMIT 50;

-- 1.4. Payment distribution and outliers

SELECT
    'avg_medicare_payment'          AS metric,
    ROUND(MIN(avg_medicare_payment), 2)                                     AS min,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP 
        (ORDER BY avg_medicare_payment)::numeric, 2)                        AS p25,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP 
        (ORDER BY avg_medicare_payment)::numeric, 2)                        AS median,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP 
        (ORDER BY avg_medicare_payment)::numeric, 2)                        AS p75,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP 
        (ORDER BY avg_medicare_payment)::numeric, 2)                        AS p95,
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP 
        (ORDER BY avg_medicare_payment)::numeric, 2)                        AS p99,
    ROUND(MAX(avg_medicare_payment), 2)                                     AS max,
    ROUND(AVG(avg_medicare_payment), 2)                                     AS mean,
    ROUND(STDDEV(avg_medicare_payment)::numeric, 2)                         AS std_dev

FROM hc.medicare_providers_view
WHERE avg_medicare_payment > 0

UNION ALL

SELECT
    'avg_billed_charge',
    ROUND(MIN(avg_billed_charge), 2),
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP 
        (ORDER BY avg_billed_charge)::numeric, 2),
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP 
        (ORDER BY avg_billed_charge)::numeric, 2),
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP 
        (ORDER BY avg_billed_charge)::numeric, 2),
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP 
        (ORDER BY avg_billed_charge)::numeric, 2),
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP 
        (ORDER BY avg_billed_charge)::numeric, 2),
    ROUND(MAX(avg_billed_charge), 2),
    ROUND(AVG(avg_billed_charge), 2),
    ROUND(STDDEV(avg_billed_charge)::numeric, 2)

FROM hc.medicare_providers_view
WHERE avg_billed_charge > 0

UNION ALL

SELECT
    'avg_allowed_amount',
    ROUND(MIN(avg_allowed_amount), 2),
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP 
        (ORDER BY avg_allowed_amount)::numeric, 2),
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP 
        (ORDER BY avg_allowed_amount)::numeric, 2),
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP 
        (ORDER BY avg_allowed_amount)::numeric, 2),
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP 
        (ORDER BY avg_allowed_amount)::numeric, 2),
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP 
        (ORDER BY avg_allowed_amount)::numeric, 2),
    ROUND(MAX(avg_allowed_amount), 2),
    ROUND(AVG(avg_allowed_amount), 2),
    ROUND(STDDEV(avg_allowed_amount)::numeric, 2)

FROM hc.medicare_providers_view
WHERE avg_allowed_amount > 0;


-- Section B: Completeness Checks (Phase 2 - Query 1.5)
-- Purpose: Identify null and zero values in key columns to assess data completeness and potential quality issues.

-- 1.5. Null rates and zero rates per column

-- Checks both Null and zero separately because:
--   Null - Data was not recorded
--   Zero - Data was recorded as zero (different meaning in financial columns - 
--          a $0 payment may indicate a denied claim or data entry issue)
 
WITH base AS (
    SELECT
        -- Payment columns
        avg_medicare_payment,
        avg_billed_charge,
        avg_allowed_amount,
        avg_standardized_payment,

        -- Volume columns
        total_services_performed,
        total_patients,

        -- Identifier columns
        provider_id,
        provider_specialty,
        procedure_code,
        state,
        ruca_urban_code,
        provider_entity_type,
        is_drug_procedure,
        service_location_type,
        provider_credentials

    FROM hc.medicare_providers_view
), counts AS (
    SELECT
        COUNT(*) AS total_rows,

        -- Nulls
        SUM(CASE WHEN avg_medicare_payment    IS NULL THEN 1 ELSE 0 END) AS null_payment,
        SUM(CASE WHEN avg_billed_charge       IS NULL THEN 1 ELSE 0 END) AS null_billed,
        SUM(CASE WHEN avg_allowed_amount      IS NULL THEN 1 ELSE 0 END) AS null_allowed,
        SUM(CASE WHEN avg_standardized_payment IS NULL THEN 1 ELSE 0 END) AS null_standardized,
        SUM(CASE WHEN total_services_performed IS NULL THEN 1 ELSE 0 END) AS null_services,
        SUM(CASE WHEN total_patients           IS NULL THEN 1 ELSE 0 END) AS null_patients,
        SUM(CASE WHEN provider_id              IS NULL THEN 1 ELSE 0 END) AS null_provider_id,
        SUM(CASE WHEN provider_specialty       IS NULL THEN 1 ELSE 0 END) AS null_specialty,
        SUM(CASE WHEN procedure_code           IS NULL THEN 1 ELSE 0 END) AS null_procedure,
        SUM(CASE WHEN state                    IS NULL THEN 1 ELSE 0 END) AS null_state,
        SUM(CASE WHEN ruca_urban_code          IS NULL THEN 1 ELSE 0 END) AS null_ruca,
        SUM(CASE WHEN provider_credentials     IS NULL THEN 1 ELSE 0 END) AS null_credentials,

        -- Zeros on numeric columns only
        SUM(CASE WHEN avg_medicare_payment     = 0 THEN 1 ELSE 0 END) AS zero_payment,
        SUM(CASE WHEN avg_billed_charge        = 0 THEN 1 ELSE 0 END) AS zero_billed,
        SUM(CASE WHEN avg_allowed_amount       = 0 THEN 1 ELSE 0 END) AS zero_allowed,
        SUM(CASE WHEN avg_standardized_payment = 0 THEN 1 ELSE 0 END) AS zero_standardized,
        SUM(CASE WHEN total_services_performed = 0 THEN 1 ELSE 0 END) AS zero_services,
        SUM(CASE WHEN total_patients           = 0 THEN 1 ELSE 0 END) AS zero_patients

    FROM base
)

SELECT
    total_rows,

    -- Payment quality
    null_payment,
    ROUND(null_payment * 100.0 / total_rows, 2)         AS null_payment_pct,
    zero_payment,
    ROUND(zero_payment * 100.0 / total_rows, 2)         AS zero_payment_pct,

    null_billed,
    ROUND(null_billed * 100.0 / total_rows, 2)          AS null_billed_pct,
    zero_billed,
    ROUND(zero_billed * 100.0 / total_rows, 2)          AS zero_billed_pct,

    null_allowed,
    ROUND(null_allowed * 100.0 / total_rows, 2)         AS null_allowed_pct,
    zero_allowed,
    ROUND(zero_allowed * 100.0 / total_rows, 2)         AS zero_allowed_pct,

    null_standardized,
    ROUND(null_standardized * 100.0 / total_rows, 2)    AS null_standardized_pct,
    zero_standardized,
    ROUND(zero_standardized * 100.0 / total_rows, 2)    AS zero_standardized_pct,

    -- Volume quality
    null_services,
    ROUND(null_services * 100.0 / total_rows, 2)        AS null_services_pct,
    zero_services,
    ROUND(zero_services * 100.0 / total_rows, 2)        AS zero_services_pct,

    null_patients,
    ROUND(null_patients * 100.0 / total_rows, 2)        AS null_patients_pct,
    zero_patients,
    ROUND(zero_patients * 100.0 / total_rows, 2)        AS zero_patients_pct,

    -- Identifier quality
    null_provider_id,
    ROUND(null_provider_id * 100.0 / total_rows, 2)     AS null_provider_id_pct,
    null_specialty,
    ROUND(null_specialty * 100.0 / total_rows, 2)       AS null_specialty_pct,
    null_procedure,
    ROUND(null_procedure * 100.0 / total_rows, 2)       AS null_procedure_pct,
    null_state,
    ROUND(null_state * 100.0 / total_rows, 2)           AS null_state_pct,
    null_ruca,
    ROUND(null_ruca * 100.0 / total_rows, 2)            AS null_ruca_pct,
    null_credentials,
    ROUND(null_credentials * 100.0 / total_rows, 2)     AS null_credentials_pct

FROM counts;


-- Section C: Validity Checks (Phase 3 - Queries 1.6 - 1.9)
-- Purpose: Verify values fall within expected ranges and adhere to logical constraints, 
-- identifying potential data entry errors or anomalies.

-- 1.6. Logical constraint violations

WITH logical_checks AS (
    SELECT
        -- Check 1: Payment cannot exceed billed charge
        SUM(CASE 
            WHEN avg_medicare_payment > avg_billed_charge 
            THEN 1 ELSE 0 END)                  AS payment_exceeds_billed,

        -- Check 2: Payment cannot exceed allowed amount
        SUM(CASE 
            WHEN avg_medicare_payment > avg_allowed_amount 
            THEN 1 ELSE 0 END)                  AS payment_exceeds_allowed,

        -- Check 3: Allowed amount cannot exceed billed charge
        SUM(CASE 
            WHEN avg_allowed_amount > avg_billed_charge 
            THEN 1 ELSE 0 END)                  AS allowed_exceeds_billed,

        -- Check 4: Standardized payment should be in a reasonable range of actual payment (flag if >3x different)
        SUM(CASE 
            WHEN avg_standardized_payment > avg_medicare_payment * 3 
            THEN 1 ELSE 0 END)                  AS standardized_far_above_payment,
        SUM(CASE 
            WHEN avg_standardized_payment > 0 
            AND avg_medicare_payment > avg_standardized_payment * 3 
            THEN 1 ELSE 0 END)                  AS payment_far_above_standardized,

        -- Check 5: total services cannot be less than total patients
        -- (Can perform multiple services per patient but not fewer services than patients)
        SUM(CASE 
            WHEN total_services_performed < total_patients 
            THEN 1 ELSE 0 END)                  AS services_less_than_patients,

        -- Check 6: Billed charge at the $99,999.99 ceiling
        SUM(CASE 
            WHEN avg_billed_charge >= 99999.99 
            THEN 1 ELSE 0 END)                  AS at_billing_ceiling,

        -- Check 7: Implausibly high payment (>$50,000 avg)
        -- Flags potential unit errors or data anomalies
        SUM(CASE 
            WHEN avg_medicare_payment > 50000 
            THEN 1 ELSE 0 END)                  AS implausibly_high_payment,

        COUNT(*)                                AS total_rows

    FROM hc.medicare_providers_view
    WHERE avg_medicare_payment > 0
    AND avg_billed_charge > 0
    AND avg_allowed_amount > 0
)

SELECT
    total_rows,
    payment_exceeds_billed,
    ROUND(payment_exceeds_billed * 100.0 
        / total_rows, 4)                        AS pct_payment_exceeds_billed,

    payment_exceeds_allowed,
    ROUND(payment_exceeds_allowed * 100.0 
        / total_rows, 4)                        AS pct_payment_exceeds_allowed,

    allowed_exceeds_billed,
    ROUND(allowed_exceeds_billed * 100.0 
        / total_rows, 4)                        AS pct_allowed_exceeds_billed,

    standardized_far_above_payment,
    payment_far_above_standardized,

    services_less_than_patients,
    ROUND(services_less_than_patients * 100.0 
        / total_rows, 4)                        AS pct_services_less_than_patients,

    at_billing_ceiling,
    ROUND(at_billing_ceiling * 100.0 
        / total_rows, 4)                        AS pct_at_ceiling,

    implausibly_high_payment

FROM logical_checks;


-- What is driving standardized payment > 3x actual payment:

SELECT
    provider_specialty,
    is_drug_procedure,
    COUNT(*)                                    AS row_count,
    ROUND(AVG(avg_medicare_payment), 2)         AS avg_pmt_unweighted,          -- diagnostic check only
    ROUND(AVG(avg_standardized_payment), 2)     AS avg_standardized_unweighted, -- diagnostic check only
    ROUND(AVG(avg_standardized_payment /
        NULLIF(avg_medicare_payment, 0)), 2)    AS avg_ratio_unweighted         -- diagnostic check only
FROM hc.medicare_providers_view
WHERE avg_medicare_payment > 0
AND avg_standardized_payment > avg_medicare_payment * 3
GROUP BY provider_specialty, is_drug_procedure
ORDER BY row_count DESC
LIMIT 20;


-- What is driving actual payment > 3x standardized payment:

SELECT
    provider_specialty,
    is_drug_procedure,
    COUNT(*)                                    AS row_count,
    ROUND(AVG(avg_medicare_payment), 2)         AS avg_pmt_unweighted,          -- diagnostic check only
    ROUND(AVG(avg_standardized_payment), 2)     AS avg_standardized_unweighted, -- diagnostic check only
    ROUND(AVG(avg_medicare_payment /
        NULLIF(avg_standardized_payment, 0)), 2) AS avg_ratio_unweighted        -- diagnostic check only
FROM hc.medicare_providers_view
WHERE avg_standardized_payment > 0
AND avg_medicare_payment > avg_standardized_payment * 3
GROUP BY provider_specialty, is_drug_procedure
ORDER BY row_count DESC
LIMIT 20;

-- 1.7. Implausible avg_billed_charge to avg_allowed_amount ratio at extremes

-- Extreme ratio check - technically valid but implausible
SELECT
    COUNT(*)            AS total_analyzed_rows,
    MIN(avg_billed_charge / 
        NULLIF(avg_allowed_amount,0))   AS min_ratio,
    MAX(avg_billed_charge / 
        NULLIF(avg_allowed_amount,0))   AS max_ratio,
    SUM(CASE 
        WHEN avg_billed_charge / 
            NULLIF(avg_allowed_amount,0) > 100 
        THEN 1 ELSE 0 END)              AS ratio_above_100x,
    SUM(CASE 
        WHEN avg_billed_charge / 
            NULLIF(avg_allowed_amount,0) > 50 
        THEN 1 ELSE 0 END)              AS ratio_above_50x
FROM hc.medicare_providers_view
WHERE avg_billed_charge > 0
AND avg_allowed_amount > 0;

-- What is driving the 100x extreme ratio rows

SELECT
    procedure_code,
    procedure_description,
    is_drug_procedure,
    provider_specialty,
    ROUND(avg_billed_charge, 2)         AS row_avg_billed_charge,
    ROUND(avg_allowed_amount, 2)        AS row_avg_allowed_amount,
    ROUND(avg_medicare_payment, 2)      AS row_avg_medicare_payment,
    ROUND(avg_billed_charge /
        NULLIF(avg_allowed_amount,0),2) AS row_billed_to_allowed_ratio
FROM hc.medicare_providers_view
WHERE avg_billed_charge /
    NULLIF(avg_allowed_amount,0) > 100
AND avg_allowed_amount > 0
ORDER BY row_billed_to_allowed_ratio DESC;

-- Categorize by allowed amount pattern and drug indicator

SELECT
    procedure_code,
    procedure_description,
    is_drug_procedure,
    COUNT(*)                                    AS row_count,
    ROUND(AVG(avg_allowed_amount), 2)           AS avg_allowed_unweighted,  -- diagnostic check only
    ROUND(AVG(avg_billed_charge), 2)            AS avg_billed_unweighted,   -- diagnostic check only
    ROUND(SUM(avg_billed_charge * total_services_performed) /
        NULLIF(SUM(avg_allowed_amount * total_services_performed), 0), 0) AS billed_to_allowed_ratio
FROM hc.medicare_providers_view
WHERE avg_billed_charge /
    NULLIF(avg_allowed_amount, 0) > 100
AND avg_allowed_amount > 0
AND avg_billed_charge > 0
GROUP BY procedure_code, procedure_description, is_drug_procedure
ORDER BY avg_allowed_unweighted ASC, billed_to_allowed_ratio DESC;

-- Row counts for 6 COVID vaccine codes which will be removed in the dataset 
SELECT COUNT(*)
FROM hc.medicare_providers_view
WHERE procedure_code IN ('91312','91313','91300','91301','91305','91309');

--1.8. Total services vs total service days 

SELECT
    SUM(CASE 
        WHEN total_service_days > total_services_performed 
        THEN 1 ELSE 0 END)      AS days_exceed_services,
    COUNT(*)                    AS total_rows
FROM hc.medicare_providers_view
WHERE total_services_performed > 0;

-- 1.9. Minimum patient threshold 
-- Check for rows below CMS suppression threshold
-- CMS suppresses provider-procedure combinations from 10 or fewer beneficiaries
-- Records with 11 or more beneficiaries are published
-- Any rows with total_patients between 1-10 would indicate a suppression-rule violation
-- Expectation: 0 rows

SELECT
    total_patients,
    COUNT(*)        AS row_count
FROM hc.medicare_providers_view
WHERE total_patients BETWEEN 1 AND 10
GROUP BY total_patients
ORDER BY total_patients;


-- Section D: Consistency checks (Phase 4 - Queries 1.10 - 1.13)
-- Purpose: Verify that categorical columns contain expected values 
-- and that related columns are internally consistent.

-- 1.10. Distinct values audit on categorical columns

SELECT 
    'provider_entity_type'      AS column_name,
    provider_entity_type        AS distinct_value,
    COUNT(*)                    AS row_count,
    ROUND(COUNT(*) * 100.0 
        / SUM(COUNT(*)) OVER(), 2) AS pct_of_total
FROM hc.medicare_providers_view
GROUP BY provider_entity_type

UNION ALL

SELECT 
    'is_drug_procedure',
    is_drug_procedure,
    COUNT(*),
    ROUND(COUNT(*) * 100.0 
        / SUM(COUNT(*)) OVER(), 2)
FROM hc.medicare_providers_view
GROUP BY is_drug_procedure

UNION ALL

SELECT 
    'service_location_type',
    service_location_type,
    COUNT(*),
    ROUND(COUNT(*) * 100.0 
        / SUM(COUNT(*)) OVER(), 2)
FROM hc.medicare_providers_view
GROUP BY service_location_type

UNION ALL

SELECT 
    'country',
    country,
    COUNT(*),
    ROUND(COUNT(*) * 100.0 
        / SUM(COUNT(*)) OVER(), 2)
FROM hc.medicare_providers_view
GROUP BY country

UNION ALL

SELECT 
    'state',
    state,
    COUNT(*),
    ROUND(COUNT(*) * 100.0 
        / SUM(COUNT(*)) OVER(), 2)
FROM hc.medicare_providers_view
GROUP BY state

ORDER BY column_name, row_count DESC;

--1.11. Consistency checks across related columns

WITH consistency_checks AS (
    SELECT
        -- Check 1: Valid entity types
        SUM(CASE 
            WHEN provider_entity_type NOT IN ('I','O') 
            THEN 1 ELSE 0 END)                  AS invalid_entity_type,

        -- Check 2: Valid place of service
        SUM(CASE 
            WHEN service_location_type NOT IN ('O','F') 
            THEN 1 ELSE 0 END)                  AS invalid_service_location,

        -- Check 3: Valid drug indicator
        SUM(CASE 
            WHEN is_drug_procedure NOT IN ('Y','N') 
            THEN 1 ELSE 0 END)                  AS invalid_drug_indicator,

        -- Check 4: Non-US country codes
        SUM(CASE 
            WHEN country != 'US' 
            THEN 1 ELSE 0 END)                  AS non_us_providers,

        -- Check 5: Unresolvable state codes
        SUM(CASE 
            WHEN state IN ('AP','AE','AA','ZZ','XX','FM') 
            THEN 1 ELSE 0 END)                  AS unresolvable_state_codes,

        -- Check 6: Territory rows
        SUM(CASE 
            WHEN state IN ('PR','GU','VI','MP','AS') 
            THEN 1 ELSE 0 END)                  AS territory_rows,

        -- Check 7: Individual provider missing first name
        SUM(CASE 
            WHEN provider_entity_type = 'I' 
            AND provider_first_name IS NULL 
            THEN 1 ELSE 0 END)                  AS individual_missing_firstname,

        -- Check 8: Empty string RUCA 
        SUM(CASE 
            WHEN ruca_urban_code = '' 
            THEN 1 ELSE 0 END)                  AS ruca_empty_string,

        -- Check 9: RUCA codes outside valid range 1-10
        -- Only cast rows that are non-null and non-empty
        SUM(CASE 
            WHEN ruca_urban_code IS NOT NULL
            AND ruca_urban_code != ''
            AND ruca_urban_code ~ '^[0-9]+\.?[0-9]*$'
            AND CAST(ruca_urban_code AS NUMERIC) 
                NOT BETWEEN 1 AND 10 
            THEN 1 ELSE 0 END)                  AS invalid_ruca_code,

        COUNT(*)                                AS total_rows

    FROM hc.medicare_providers_view
)

SELECT
    total_rows,
    invalid_entity_type,
    invalid_service_location,
    invalid_drug_indicator,
    non_us_providers,
    ROUND(non_us_providers * 100.0 
        / total_rows, 4)                        AS pct_non_us,
    unresolvable_state_codes,
    territory_rows,
    individual_missing_firstname,
    ruca_empty_string,
    ROUND(ruca_empty_string * 100.0 
        / total_rows, 4)                        AS pct_ruca_empty,
    invalid_ruca_code

FROM consistency_checks;

-- Invalid RUCA codes check - RUCA extended codes with detail breakdown
-- Confirms the 14,723 invalid_ruca_code count

SELECT
    ruca_urban_code,
    COUNT(*)            AS row_count
FROM hc.medicare_providers_view
WHERE ruca_urban_code != ''
AND ruca_urban_code IS NOT NULL
AND ruca_urban_code ~ '^[0-9]+\.?[0-9]*$'
AND CAST(ruca_urban_code AS NUMERIC) NOT BETWEEN 1 AND 10
GROUP BY ruca_urban_code
ORDER BY row_count DESC;

-- Empty strings in provider_first_name check
-- Confirms if the 537,088 empty strings all belong to organizational providers, zero individual providers affected

SELECT
    provider_entity_type,
    COUNT(*)                                        AS total_rows,
    SUM(CASE WHEN provider_first_name IS NULL
        THEN 1 ELSE 0 END)                          AS null_count,
    SUM(CASE WHEN provider_first_name = ''
        THEN 1 ELSE 0 END)                          AS empty_string_count,
    SUM(CASE WHEN provider_first_name = 'None'
        THEN 1 ELSE 0 END)                          AS string_none_count
FROM hc.medicare_providers_view
GROUP BY provider_entity_type
ORDER BY provider_entity_type;

--1.12. HCPCS description consistency

-- HCPCS codes with more than one description
SELECT
    procedure_code,
    COUNT(DISTINCT procedure_description)   AS description_count,
    MIN(procedure_description)              AS description_1,
    MAX(procedure_description)              AS description_2
FROM hc.medicare_providers_view
GROUP BY procedure_code
HAVING COUNT(DISTINCT procedure_description) > 1
ORDER BY description_count DESC
LIMIT 20;

--1.13. Standardized payment vs actual payment relationship

-- Correlation check between actual and standardized payment
SELECT
    ROUND(CORR(avg_medicare_payment, 
        avg_standardized_payment)::numeric, 4)  AS correlation,
    ROUND(AVG(avg_standardized_payment / 
        NULLIF(avg_medicare_payment,0))::numeric, 4) AS avg_std_to_actual_ratio,
    ROUND(STDDEV(avg_standardized_payment / 
        NULLIF(avg_medicare_payment,0))::numeric, 4) AS stddev_std_to_actual_ratio
FROM hc.medicare_providers_view
WHERE avg_medicare_payment > 0
AND avg_standardized_payment > 0;


-- Section E: Structural Checks (Phase 5 - Queries 1.14 - 1.16)
-- Purpose: Verify that VARCHAR columns holding numeric-looking data have not been corrupted by the CSV import process.

-- 1.14. Special characters in numeric fields
-- Check if any numeric columns contain non-numeric artifacts in payment and volume columns
-- This check is implicit in the import step, not a query
-- All 7 NUMERIC columns (Tot_Benes, Tot_Srvcs, Tot_Bene_Day_Srvcs, Avg_Sbmtd_Chrg, Avg_Mdcr_Alowd_Amt, Avg_Mdcr_Pymt_Amt, Avg_Mdcr_Stdzd_Amt)
-- are defined as NUMERIC in the raw table, so PostgreSQL rejects any non-numeric value at \copy time with a type error
-- The fact that 9,660,647 rows imported successfully confirms that all payment and volume columns contain valid numeric data only
-- No query required

-- 1.15. Leading zero loss in zip codes

-- Check zip code formatting
SELECT
    -- How many zip codes are less than 5 characters
    -- These have lost their leading zeros
    SUM(CASE 
        WHEN LENGTH(zip_code) < 5 
        THEN 1 ELSE 0 END)              AS short_zip_codes,

    -- How many are exactly 5 characters (correct)
    SUM(CASE 
        WHEN LENGTH(zip_code) = 5 
        THEN 1 ELSE 0 END)              AS correct_zip_codes,

    -- How many are longer than 5 (zip+4 or other format)
    SUM(CASE 
        WHEN LENGTH(zip_code) > 5 
        THEN 1 ELSE 0 END)              AS long_zip_codes,

    -- Show the shortest zip codes to see what they look like
    MIN(LENGTH(zip_code))               AS min_zip_length,
    MAX(LENGTH(zip_code))               AS max_zip_length,

    COUNT(*)                            AS total_rows

FROM hc.medicare_providers_view
WHERE zip_code IS NOT NULL
AND zip_code != '';


-- Show examples of short zip codes to understand the problem
SELECT
    zip_code,
    state,
    LENGTH(zip_code)        AS zip_length,
    COUNT(*)                AS row_count
FROM hc.medicare_providers_view
WHERE LENGTH(zip_code) < 5
AND zip_code != ''
GROUP BY zip_code, state, LENGTH(zip_code)
ORDER BY zip_length ASC, row_count DESC
LIMIT 20;

-- 1.16. Non-numeric characters in numeric fields

-- Check for any non-numeric content in payment columns
-- These are stored as NUMERIC so Postgres already validated them
-- But let's verify for VARCHAR columns that hold numeric-looking data

SELECT
    -- Check zip codes for non-numeric characters
    -- Zip should be all digits
    SUM(CASE 
        WHEN zip_code ~ '[^0-9]' 
        THEN 1 ELSE 0 END)              AS zip_non_numeric,

    -- Check RUCA for unexpected characters
    -- Should be digits and at most one decimal point
    SUM(CASE 
        WHEN ruca_urban_code ~ '[^0-9.]' 
        AND ruca_urban_code != ''
        THEN 1 ELSE 0 END)              AS ruca_non_numeric,

    -- Check state FIPS for unexpected characters
    -- Should be numeric codes like '01', '02'
    SUM(CASE 
        WHEN state_fips_code ~ '[^0-9]'
        AND state_fips_code != ''
        THEN 1 ELSE 0 END)              AS fips_non_numeric,

    -- Check provider NPI for non-numeric characters
    -- NPI should be a 10-digit number
    SUM(CASE 
        WHEN provider_id ~ '[^0-9]' 
        THEN 1 ELSE 0 END)              AS npi_non_numeric,

    -- Check NPI length - should always be 10 digits
    SUM(CASE 
        WHEN LENGTH(provider_id) != 10 
        THEN 1 ELSE 0 END)              AS npi_wrong_length,

    COUNT(*)                            AS total_rows

FROM hc.medicare_providers_view
WHERE provider_id IS NOT NULL;


-- What non-numeric zip codes look like
SELECT
    zip_code,
    state,
    COUNT(*)        AS row_count
FROM hc.medicare_providers_view
WHERE zip_code ~ '[^0-9]'
AND zip_code != ''
GROUP BY zip_code, state
ORDER BY row_count DESC
LIMIT 10;

-- What non-numeric FIPS codes look like
SELECT
    state_fips_code,
    state,
    COUNT(*)        AS row_count
FROM hc.medicare_providers_view
WHERE state_fips_code ~ '[^0-9]'
AND state_fips_code != ''
GROUP BY state_fips_code, state
ORDER BY row_count DESC
LIMIT 10;

 
-- Section F: Uniqueness Checks (Phase 6 - Queries 1.17 - 1.18)
-- Purpose: Establish the correct analytical grain of the dataset and confirm there are no true duplicates.

-- 1.17. Duplicate rows 

-- Check for duplicate provider-procedure combinations
SELECT
    provider_id,
    procedure_code,
    service_location_type,
    COUNT(*)            AS row_count
FROM hc.medicare_providers_view
GROUP BY
    provider_id,
    procedure_code,
    service_location_type
HAVING COUNT(*) > 1
ORDER BY row_count DESC
LIMIT 20;

-- 1.18. The sanity check for duplicates

-- Confirm duplicates query ran against full dataset
-- Returns distinct provider-procedure pairs without location type
-- Expected to be less than total rows because the same provider can bill the same procedure in different locations (office vs facility)

SELECT COUNT(DISTINCT provider_id || '|' || procedure_code)    -- Pipe separator used because COUNT(DISTINCT) does not support composite values
FROM hc.medicare_providers_view;

-- Result: 9,318,769 distinct provider-procedure combinations, which is about 3.5% fewer than total rows
-- This is expected because providers can bill the same procedure in both office and facility settings

-- Confirm the difference is explained by facility vs office split
SELECT
    COUNT(*)                                                AS total_rows,
    COUNT(DISTINCT provider_id || '|' || 
          procedure_code)                                   AS distinct_npi_hcpcs,
    COUNT(DISTINCT provider_id || '|' || 
          procedure_code || '|' || 
          service_location_type)                            AS distinct_npi_hcpcs_location,
    COUNT(*) - COUNT(DISTINCT provider_id || '|' || 
          procedure_code || '|' || 
          service_location_type)                            AS unexplained_difference

FROM hc.medicare_providers_view;

-- Confirms the 341,878 gap is fully explained by F/O location split
-- If this equals the gap, the explanation is confirmed

WITH both_locations AS (
    SELECT
        provider_id,
        procedure_code
    FROM hc.medicare_providers_view
    GROUP BY provider_id, procedure_code
    HAVING COUNT(DISTINCT service_location_type) = 2
)
SELECT COUNT(*) AS rows_with_both_locations
FROM both_locations;

-- Section G: Identity Checks (Phase 7 - Queries 1.19 - 1.22)
-- Purpose: Check whether providers appear consistently across rows - same name,
-- specialty, entity type and state.

--1.19. Provider appearing under multiple specialties

-- Check providers with more than one specialty
SELECT
    provider_id,
    COUNT(DISTINCT provider_specialty)  AS specialty_count,
    STRING_AGG(DISTINCT provider_specialty, ' | ') AS specialties
FROM hc.medicare_providers_view
GROUP BY provider_id
HAVING COUNT(DISTINCT provider_specialty) > 1
ORDER BY specialty_count DESC
LIMIT 20;

--1.20. Provider appearing under multiple entity types

-- Check providers with more than one entity type
SELECT
    provider_id,
    COUNT(DISTINCT provider_entity_type)    AS entity_type_count,
    STRING_AGG(DISTINCT provider_entity_type, ' | ') AS entity_types
FROM hc.medicare_providers_view
GROUP BY provider_id
HAVING COUNT(DISTINCT provider_entity_type) > 1
ORDER BY entity_type_count DESC
LIMIT 20;

--1.21. Provider appearing in multiple states

-- Check providers appearing in multiple states
SELECT
    provider_id,
    COUNT(DISTINCT state)               AS state_count,
    STRING_AGG(DISTINCT state, ' | ')   AS states
FROM hc.medicare_providers_view
GROUP BY provider_id
HAVING COUNT(DISTINCT state) > 1
ORDER BY state_count DESC
LIMIT 20;

-- 1.22. Provider name consistency across rows

-- Providers with inconsistent names
SELECT
    provider_id,
    COUNT(DISTINCT provider_last_name)          AS name_variants,
    STRING_AGG(DISTINCT provider_last_name, ' | ') AS names
FROM hc.medicare_providers_view
GROUP BY provider_id
HAVING COUNT(DISTINCT provider_last_name) > 1
ORDER BY name_variants DESC
LIMIT 20;

-- Section H: Filter Impact Verification (Queries 1.23 - 1.26)
-- Purpose: Quantify the impact of identified data quality issues on key findings on Projects 2, 3, and 4.
--          These are not quality checks. They quantify how much each identified issue would have distorted the downstream findings.
--          Results are documented in the README - "Why it matters" table

-- 1.23. COVID vaccine codes - what they look like before exclusion
-- Procedure codes 91312, 91313, 91300, 91301, 91305, 91309 (SARS-CoV-2 vaccines). CMS set allowed amount at $0.01 during public health emergency
-- This diagnostic check is used to identify which rows have extreme ratios and confirm if they are driven by Covid vaccine codes
-- Unweighted averages are used intentionally as this is row-inspection, not for producing a finding

-- Check specialty-level metrics for Covid codes vs all other procedure codes to see how much they skew the results

-- Specialty-level metrics for COVID vaccine codes
SELECT
    provider_specialty,
    COUNT(DISTINCT provider_id)                     AS distinct_providers,
    SUM(total_services_performed)                   AS total_services,
    ROUND(AVG(avg_billed_charge), 2)                AS avg_billed_unweighted,   -- diagnostic check only
    ROUND(AVG(avg_allowed_amount), 2)               AS avg_allowed_unweighted,  -- diagnostic check only
    ROUND(AVG(avg_medicare_payment), 2)             AS avg_paid_unweighted,     -- diagnostic check only
    ROUND(SUM(avg_billed_charge * total_services_performed) /
        NULLIF(SUM(avg_allowed_amount * total_services_performed), 0), 0)      AS billed_to_allowed_ratio
FROM hc.medicare_providers_view
WHERE procedure_code IN ('91300','91301','91305','91309','91312','91313')
GROUP BY provider_specialty
ORDER BY billed_to_allowed_ratio DESC;

-- Specialty-level metrics for all other procedure codes (COVID vaccine codes excluded)
SELECT
    provider_specialty,
    COUNT(DISTINCT provider_id)                     AS distinct_providers,
    SUM(total_services_performed)                   AS total_services,
    ROUND(AVG(avg_billed_charge), 2)                AS avg_billed_unweighted,    -- diagnostic check only
    ROUND(AVG(avg_allowed_amount), 2)               AS avg_allowed_unweighted,   -- diagnostic check only
    ROUND(AVG(avg_medicare_payment), 2)             AS avg_paid_unweighted,      -- diagnostic check only
    ROUND(SUM(avg_billed_charge * total_services_performed) /
        NULLIF(SUM(avg_allowed_amount * total_services_performed), 0), 0)      AS billed_to_allowed_ratio
FROM hc.medicare_providers_view
WHERE procedure_code NOT IN ('91312','91313','91300','91301','91305','91309')
GROUP BY provider_specialty
ORDER BY billed_to_allowed_ratio DESC;

-- 1.24. Impact of drug filter on rural payment gap
-- Shows how a single filter decision changes the headline equity finding in Project 3
-- Volume-weighted averages are required because high-volume providers contribute proportionally more to the specialty average
-- RUCA codes are grouped into two category following Health Resources & Services Administration (HRSA) standard

WITH drug_filter_impact AS (
    SELECT
        *,
        CASE
            WHEN ruca_urban_code IN ('1','2','3')        THEN 'Urban'
            WHEN ruca_urban_code IN ('4','5','6','7','8','9','10',
                                    '10.1','10.2','10.3') THEN 'Rural'
        END                                             AS ruca_category
    FROM hc.medicare_providers_view
    WHERE avg_medicare_payment > 0
    AND avg_billed_charge > 0
    AND avg_allowed_amount > 0
    AND avg_medicare_payment <= avg_billed_charge
    AND avg_allowed_amount   <= avg_billed_charge
    AND total_services_performed >= total_patients
    AND total_service_days <= total_services_performed
    AND avg_billed_charge < 99999.99
    AND procedure_code NOT IN ('91312','91313','91300','91301','91305','91309')
    AND country = 'US'
    AND state NOT IN ('AP','AE','AA','ZZ','XX','FM','PR','GU','VI','MP','AS')
    AND ruca_urban_code IS NOT NULL
    AND ruca_urban_code != ''
    AND ruca_urban_code != '99'
)
-- Rural gap without drug filter (what Project 3 would show without it)
SELECT
    'Without drug filter'                  AS scenario,
    ruca_category,                         
    ROUND(SUM(avg_medicare_payment * total_services_performed) /
        NULLIF(SUM(total_services_performed), 0), 2) AS avg_pmt_weighted
FROM drug_filter_impact
GROUP BY ruca_category
HAVING ruca_category IS NOT NULL

UNION ALL

-- Rural gap with drug filter 
SELECT
    'With drug filter'                     AS scenario,
    ruca_category,
    ROUND(SUM(avg_medicare_payment * total_services_performed) /
        NULLIF(SUM(total_services_performed), 0), 2) AS avg_pmt_weighted
FROM drug_filter_impact
WHERE is_drug_procedure = 'N'
GROUP BY ruca_category
HAVING ruca_category IS NOT NULL
ORDER BY scenario, ruca_category;

-- 1.25. Impact of billing ceiling filter on avg_billed_charge distribution (Removing the 99999.99 artifact)

SELECT
    'avg_billed_charge'          AS metric,
    ROUND(MIN(avg_billed_charge), 2)                                     AS min,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP 
        (ORDER BY avg_billed_charge)::numeric, 2)                        AS p25,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP 
        (ORDER BY avg_billed_charge)::numeric, 2)                        AS median,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP 
        (ORDER BY avg_billed_charge)::numeric, 2)                        AS p75,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP 
        (ORDER BY avg_billed_charge)::numeric, 2)                        AS p95,
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP 
        (ORDER BY avg_billed_charge)::numeric, 2)                        AS p99,
    ROUND(MAX(avg_billed_charge), 2)                                     AS max,
    ROUND(AVG(avg_billed_charge), 2)                                     AS mean,
    ROUND(STDDEV(avg_billed_charge)::numeric, 2)                         AS std_dev
FROM hc.medicare_providers_view
WHERE avg_billed_charge > 0
AND avg_billed_charge < 99999.99;

-- 1.26. Impact of filters on analytical scope and data quality

SELECT
    COUNT(*)            AS total_rows
FROM hc.medicare_providers_view
WHERE avg_medicare_payment      > 0                             
  AND avg_billed_charge         > 0                                  
  AND avg_allowed_amount        > 0                             
  AND avg_medicare_payment      <= avg_billed_charge           
  AND avg_allowed_amount        <= avg_billed_charge            
  AND total_services_performed  >= total_patients               
  AND total_service_days        <= total_services_performed     
  AND avg_billed_charge         < 99999.99                      
  AND procedure_code            NOT IN ('91312','91313','91300','91301','91305','91309')        
  AND is_drug_procedure         = 'N'                           
  AND country                   = 'US'                          
  AND state NOT IN (
      'AP','AE','AA','ZZ','XX','FM',                                 
      'PR','GU','VI','MP','AS');                            



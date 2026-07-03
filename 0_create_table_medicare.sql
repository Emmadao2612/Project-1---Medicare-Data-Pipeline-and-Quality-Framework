-- Series: Medicare Provider Billing and Payment Analysis
-- Project 1: Medicare Data Pipeline and Quality Framework
-- Purpose: Create raw table, load data, build semantic view and indexes
-- Inputs:  CMS Medicare Part B 2023 CSV file (9,660,647 rows)
-- Outputs: hc.medicare_providers_raw (raw table)
--          hc.medicare_providers_view (semantic view - used in all downstream projects)

-- 1. Create and select a dedicated project schema
CREATE SCHEMA IF NOT EXISTS hc;
SET search_path TO hc;

-- 2. Drop the table if it already exists
DROP TABLE IF EXISTS medicare_providers_raw CASCADE;

-- 3. Create the table with clean columns

-- All columns stored as VARCHAR / TEXT except the seven numeric payment and volume columns
-- Using VARCHAR for all identifier and categorical columns avoids import failures and preserves leading zeros in zip codes and FIPS codes
-- Payment and volume columns are stored as NUMERIC (not FLOAT) to avoid floating-point precision errors


CREATE TABLE medicare_providers_raw (
    Rndrng_NPI VARCHAR(50),
    Rndrng_Prvdr_Last_Org_Name VARCHAR(255),
    Rndrng_Prvdr_First_Name VARCHAR(255),
    Rndrng_Prvdr_MI VARCHAR(10),
    Rndrng_Prvdr_Crdntls VARCHAR(255),
    Rndrng_Prvdr_Ent_Cd VARCHAR(10),
    Rndrng_Prvdr_St1 VARCHAR(255),
    Rndrng_Prvdr_St2 VARCHAR(255),
    Rndrng_Prvdr_City VARCHAR(150),
    Rndrng_Prvdr_State_Abrvtn VARCHAR(10),
    Rndrng_Prvdr_State_FIPS VARCHAR(10),
    Rndrng_Prvdr_Zip5 VARCHAR(20),
    Rndrng_Prvdr_RUCA VARCHAR(20),
    Rndrng_Prvdr_RUCA_Desc TEXT,
    Rndrng_Prvdr_Cntry VARCHAR(50),
    Rndrng_Prvdr_Type VARCHAR(255),
    Rndrng_Prvdr_Mdcr_Prtcptg_Ind VARCHAR(10),
    HCPCS_Cd VARCHAR(50),
    HCPCS_Desc TEXT,
    HCPCS_Drug_Ind VARCHAR(10),
    Place_Of_Srvc VARCHAR(10),
    Tot_Benes NUMERIC,
    Tot_Srvcs NUMERIC,
    Tot_Bene_Day_Srvcs NUMERIC,
    Avg_Sbmtd_Chrg NUMERIC,
    Avg_Mdcr_Alowd_Amt NUMERIC,
    Avg_Mdcr_Pymt_Amt NUMERIC,
    Avg_Mdcr_Stdzd_Amt NUMERIC
);


-- 4. Upload the data via psql command line
-- \copy hc.medicare_providers_raw FROM 'path/to/Medicare_Physician_Other_Practitioners_2023.csv' CSV HEADER ENCODING 'UTF8';

-- 5. Verify the import

SELECT COUNT(*) AS total_rows 
FROM hc.medicare_providers_raw;

SELECT * 
FROM hc.medicare_providers_raw 
LIMIT 10;

SELECT 
    COUNT(*) AS total_rows, 
    COUNT(rndrng_npi) AS rows_with_npi, 
    COUNT(hcpcs_cd) AS rows_with_hcpcs, 
    COUNT(tot_bene_day_srvcs) AS rows_with_service_days,
    COUNT(avg_mdcr_pymt_amt) AS rows_with_payment
FROM hc.medicare_providers_raw;

-- Note: The raw table stores all rows including non-US providers and military codes.
-- Geographic filtering will be applied at the view and query level, not at import time.
-- This preserves the ability to audit excluded rows in Project 1 Quality Checks.

-- 6. Create a view for easier querying and analysis

-- CMS column names (e.g. Rndrng_Prvdr_Type) are replaced with readable aliases (e.g. provider_specialty) that are used consistently across
-- all analytical queries in Projects 2, 3, and 4.
-- The raw table preserves the original CMS structure unchanged. All analytical queries run against the view, not the raw table.


CREATE OR REPLACE VIEW hc.medicare_providers_view AS
SELECT
    rndrng_npi                    AS provider_id,
    rndrng_prvdr_last_org_name    AS provider_last_name,
    rndrng_prvdr_first_name       AS provider_first_name,
    rndrng_prvdr_mi               AS provider_middle_initial,
    rndrng_prvdr_crdntls          AS provider_credentials,
    rndrng_prvdr_ent_cd           AS provider_entity_type,
    rndrng_prvdr_st1              AS street_address_1,
    rndrng_prvdr_st2              AS street_address_2,
    rndrng_prvdr_city             AS city,
    rndrng_prvdr_state_abrvtn     AS state,
    rndrng_prvdr_state_fips       AS state_fips_code,
    rndrng_prvdr_zip5             AS zip_code,
    rndrng_prvdr_ruca             AS ruca_urban_code,
    rndrng_prvdr_ruca_desc        AS ruca_description,
    rndrng_prvdr_cntry            AS country,
    rndrng_prvdr_type             AS provider_specialty,
    rndrng_prvdr_mdcr_prtcptg_ind AS is_medicare_participant,
    hcpcs_cd                      AS procedure_code,
    hcpcs_desc                    AS procedure_description,
    hcpcs_drug_ind                AS is_drug_procedure,
    place_of_srvc                 AS service_location_type,
    tot_benes                     AS total_patients,
    tot_srvcs                     AS total_services_performed,
    tot_bene_day_srvcs            AS total_service_days,
    avg_sbmtd_chrg                AS avg_billed_charge,
    avg_mdcr_alowd_amt            AS avg_allowed_amount,
    avg_mdcr_pymt_amt             AS avg_medicare_payment,
    avg_mdcr_stdzd_amt            AS avg_standardized_payment
FROM hc.medicare_providers_raw;

-- 7. Verify the view

SELECT *
FROM hc.medicare_providers_view
LIMIT 20;

SELECT 
    COUNT(*) AS total_rows, 
    COUNT(provider_id) AS rows_with_npi, 
    COUNT(procedure_code) AS rows_with_hcpcs, 
    COUNT(total_service_days) AS rows_with_service_days,
    COUNT(avg_medicare_payment) AS rows_with_payment
FROM hc.medicare_providers_view;

-- 8. Build indexes for faster querying on commonly used columns

-- These five columns appear in WHERE, GROUP BY, or JOIN clauses across every analytical query in this project.
-- Indexing them reduces query time significantly on a 9.66M row table.


CREATE INDEX idx_specialty ON hc.medicare_providers_raw (Rndrng_Prvdr_Type);
CREATE INDEX idx_hcpcs     ON hc.medicare_providers_raw (HCPCS_Cd);
CREATE INDEX idx_state     ON hc.medicare_providers_raw (Rndrng_Prvdr_State_Abrvtn);
CREATE INDEX idx_npi       ON hc.medicare_providers_raw (Rndrng_NPI);
CREATE INDEX idx_ruca      ON hc.medicare_providers_raw (Rndrng_Prvdr_RUCA);

-- 9. Update statistics
ANALYZE hc.medicare_providers_raw;

-- ANALYZE updates PostgreSQL's internal statistics about column value distributions. 
-- The query planner uses these statistics to choose the most efficient execution plan.

-- 10. Verify the indexes

SELECT 
    schemaname, 
    tablename, 
    indexname, 
    indexdef
FROM pg_indexes
WHERE schemaname = 'hc' AND tablename = 'medicare_providers_raw';



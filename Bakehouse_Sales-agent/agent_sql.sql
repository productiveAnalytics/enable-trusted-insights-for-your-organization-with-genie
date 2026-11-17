-- Genie Agent: lalitstar - Bakehouse Sales (space_id 01f1e205aec91588a33bf2e242c332a6)
-- SQL code extracted from the agent's knowledge store (version as of 2026-11-16T23:30:56Z)

-- =========================================================
-- Example SQL: "Who are our best customers?"
-- Usage guidance: When users ask for the best customers make sure you aggregate by
-- total price and return the top 10 customers.
-- =========================================================
SELECT
  c.customerID,
  c.first_name,
  c.last_name,
  SUM(t.totalPrice) AS total_spend
FROM
  labuser18456042_1794852728.genie_course_bakehouse.sales_transactions_gold AS t
    JOIN labuser18456042_1794852728.genie_course_bakehouse.sales_customers_gold AS c
      ON t.customerID = c.customerID
GROUP BY
  c.customerID,
  c.first_name,
  c.last_name
ORDER BY
  total_spend DESC
LIMIT 10;

-- =========================================================
-- Join spec (MANY_TO_ONE): sales_franchises_gold f -> sales_suppliers_gold s
--   `f`.`supplierID` = `s`.`supplierID`
-- Instruction: Many rows in sales_franchises_gold have a supplierID with no match in
-- sales_suppliers_gold. Make sure to display the orphaned rows.
-- =========================================================

-- =========================================================
-- SQL expression: region (synonyms: franchise region, region sales)
-- =========================================================
-- CASE
--     WHEN sales_franchises_gold.country IN ('Japan', 'Australia') THEN 'APJ'
--     WHEN sales_franchises_gold.country IN ('US', 'Canada') THEN 'AMER'
--     WHEN sales_franchises_gold.country IN ('Netherlands', 'France', 'Germany', 'Italy', 'Sweden') THEN 'EMEA'
--     ELSE 'Other'
-- END

-- =========================================================
-- Benchmark: "What are total sales by region?"
-- Evaluation note: Map the country to appropriate region like APJ, AMER, EMEA
-- =========================================================
SELECT
    CASE
        WHEN f.country IN ('Japan', 'Australia') THEN 'APJ'
        WHEN f.country IN ('US', 'Canada') THEN 'AMER'
        WHEN f.country IN ('Netherlands', 'France', 'Germany', 'Italy', 'Sweden') THEN 'EMEA'
        ELSE 'Other'
    END AS region,
    SUM(t.totalPrice) AS total_sales
FROM labuser18456042_1794852728.genie_course_bakehouse.sales_franchises_gold AS f
JOIN labuser18456042_1794852728.genie_course_bakehouse.sales_transactions_gold AS t
    ON f.franchiseID = t.franchiseID
GROUP BY region
ORDER BY total_sales DESC;

-- =========================================================
-- Benchmark: "How many customers do we have?"
-- =========================================================
SELECT
  COUNT(DISTINCT `customerID`) AS `customer_count`
FROM
  `labuser18456042_1794852728`.`genie_course_bakehouse`.`sales_customers_gold`;

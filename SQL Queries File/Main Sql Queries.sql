SELECT * FROM personal_spending;

-- 1. What is the total amount spent each month in 2023?
SELECT year, month, SUM(value) AS total_monthly_spend
FROM personal_spending
WHERE type = 'Expense' AND year = 2023
GROUP BY year, month
ORDER BY year, month;

-- 2. How many transactions are marked as ‘Non-Essential’ each month in 2024
--    for the first 6 months?
SELECT month, COUNT(*) AS non_essential_count
FROM personal_spending
WHERE Is_Necessary = 'No' AND year = 2023
GROUP BY year, month
ORDER BY year, month
LIMIT 6;

-- 3. What are the top 5 most frequent expense categories?
SELECT category, COUNT(*) AS transaction_count
FROM personal_spending
GROUP BY category
ORDER BY transaction_count DESC
LIMIT 5;

-- 4. Which payment mode is most commonly used for micro spends?
SELECT payment_mode, COUNT(*) AS micro_spend_count
FROM personal_spending
WHERE is_micro_spend = 1
GROUP BY payment_mode
ORDER BY micro_spend_count DESC;

-- 5. Compare average expense value for recurring vs non-recurring transactions.
SELECT is_recurring, AVG(value) AS avg_spend
FROM personal_spending
WHERE type = 'Expense'
GROUP BY is_recurring;

-- 6. Which day of the week has the highest average daily spend?
SELECT day_of_week, AVG(daily_spend) AS avg_spend
FROM personal_spending
GROUP BY day_of_week
ORDER BY avg_spend DESC;

-- 7. Which three time blocks see the most leakage-prone transactions?
SELECT time_block, COUNT(*) AS leakage_count
FROM personal_spending
WHERE is_leakage = 1
GROUP BY time_block
ORDER BY leakage_count DESC
LIMIT 3;

-- 8. Which contexts contribute most to high leakage scores 
--    (above 75th percentile)?
-- MySQL does not have PERCENTILE_CONT, so we use NTILE to approximate the top 25%
WITH ranked_scores AS (
    SELECT 
        context,
        NTILE(4) OVER (ORDER BY leakage_score ASC) AS quartile
    FROM personal_spending
)
SELECT context, COUNT(*) AS high_leak_count
FROM ranked_scores
WHERE quartile = 4
GROUP BY context
ORDER BY high_leak_count DESC;

-- 9. Estimate monthly savings by cutting top 10% leakage-scored 
--    expenses in half.
WITH ranked AS (
    SELECT *, NTILE(10) OVER (ORDER BY leakage_score DESC) AS score_decile
    FROM personal_spending
)
SELECT month, ROUND(SUM(value) * 0.5) AS potential_savings
FROM ranked
WHERE score_decile = 1 
GROUP BY month
ORDER BY month;

-- 10. Find users’ top 3 non-essential categories 
--     that most frequently appear in salary weeks.
-- Changed TRUE to 1
SELECT category, COUNT(*) AS count
FROM personal_spending
WHERE is_salary_week = 1 AND Is_Necessary = 'No'
GROUP BY category
ORDER BY count DESC
LIMIT 3;

-- 11. Track average leakage score by payment mode to assess risky channels.
SELECT payment_mode, AVG(leakage_score) AS avg_leakage_score
FROM personal_spending
GROUP BY payment_mode
ORDER BY avg_leakage_score DESC;

-- 12. Identify Top Leakage Contexts by Month with Running Rank
WITH monthly_leakage AS (
  SELECT
    month,
    context,
    SUM(value) AS leakage_sum
  FROM personal_spending
  WHERE is_leakage = 1
  GROUP BY month, context
),
ranked_leaks AS (
  SELECT
    month,
    context,
    leakage_sum,
    RANK() OVER (
      PARTITION BY month
      ORDER BY leakage_sum DESC
    ) AS leakage_rank
  FROM monthly_leakage
)
SELECT *
FROM ranked_leaks
WHERE leakage_rank <= 3
ORDER BY month, leakage_rank
LIMIT 18; -- for just first 6 months

-- 13. Flag months where leakage significantly jumps right after salary arrives.
-- Replaced FILTER (WHERE...) with a CASE statement for MySQL compatibility
WITH monthly_stats AS (
  SELECT
    month,
    is_salary_week,
    SUM(CASE WHEN is_leakage = 1 THEN value ELSE 0 END) AS total_leakage
  FROM personal_spending
  GROUP BY month, is_salary_week
),
leak_jump AS (
  SELECT
    month,
    total_leakage,
    LAG(total_leakage) OVER (ORDER BY month) AS prev_leakage
  FROM monthly_stats
  WHERE is_salary_week = 1
)
SELECT
  month,
  total_leakage,
  prev_leakage,
  ROUND((total_leakage - prev_leakage) * 100.0 / prev_leakage, 2) AS pct_jump
FROM leak_jump
WHERE prev_leakage IS NOT NULL
  AND total_leakage > prev_leakage;

-- 14. Find which payment channels have highest leakage rate per transaction.
WITH mode_counts AS (
  SELECT
    payment_mode,
    COUNT(*) AS total_txn,
    SUM(CASE WHEN is_leakage = 1 THEN 1 ELSE 0 END) AS leakage_txn
  FROM personal_spending
  GROUP BY payment_mode
),
mode_rate AS (
  SELECT
    payment_mode,
    leakage_txn,
    total_txn,
    ROUND(leakage_txn * 100.0 / total_txn, 2) AS leakage_rate_pct
  FROM mode_counts
)
SELECT *
FROM mode_rate
ORDER BY leakage_rate_pct DESC;
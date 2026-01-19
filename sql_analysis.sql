/* ============================================================
   1. Monthly Revenue Trend
   ------------------------------------------------------------
   Question:
   - What is total revenue by month?

   Output:
   - order_month (YYYY-MM)
   - total_revenue

   Logic:
   - Revenue = quantity * unit_price * (1 - discount)
   - Grouped by month
   - Sorted chronologically
   ============================================================ */

SELECT
    strftime('%Y-%m', o.order_date) AS Month,
    SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct)) AS revenue
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
GROUP BY month
ORDER BY month;


/* ============================================================
   2. Repeat Customer Rate
   ------------------------------------------------------------
   Question:
   - What percentage of customers place more than one order?
   ============================================================ */

WITH repeat_c AS (
    SELECT
        customer_id
    FROM orders
    GROUP BY customer_id
    HAVING COUNT(*) > 1
)
SELECT
    (SELECT COUNT(DISTINCT customer_id) FROM orders) AS total_ordering_customers,
    (SELECT COUNT(*) FROM repeat_c) AS repeat_c,
    ROUND(
        100.0 * (SELECT COUNT(*) FROM repeat_c) /
        (SELECT COUNT(DISTINCT customer_id) FROM orders),
        2
    ) AS repeat_c_pc;


/* ============================================================
   3. Top Products by Revenue
   ------------------------------------------------------------
   Question:
   - Which products generate the most revenue?
   ============================================================ */

SELECT
    oi.product_id,
    ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct)), 2) AS rev_per_item
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
GROUP BY oi.product_id
ORDER BY rev_per_item DESC
LIMIT 10;


/* ============================================================
   4. Average Order Value (AOV) Over Time
   ------------------------------------------------------------
   Question:
   - How has Average Order Value changed month over month?

   AOV Formula:
   - Total Revenue ÷ Number of Orders
   ============================================================ */

SELECT
    strftime('%Y-%m', o.order_date) AS Month,
    ROUND(SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct)), 2) AS revenue,
    COUNT(DISTINCT oi.order_id) AS num_ord,
    ROUND(
        SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct)) /
        COUNT(DISTINCT oi.order_id),
        2
    ) AS AOV
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
GROUP BY month
ORDER BY month;


/* ============================================================
   5. Revenue Concentration (Top 10 Customers)
   ------------------------------------------------------------
   Question:
   - What percent of total revenue comes from the top 10 customers?
   ============================================================ */

WITH top_cus_rev AS (
    SELECT
        o.customer_id,
        SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct)) AS revenue
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    GROUP BY o.customer_id
    ORDER BY revenue DESC
    LIMIT 10
),
total_rev AS (
    SELECT
        SUM(oi.quantity * oi.unit_price * (1 - oi.discount_pct)) AS total_revenue
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
)
SELECT
    (SELECT COUNT(*) FROM top_cus_rev) AS top_customer_count,
    ROUND((SELECT SUM(revenue) FROM top_cus_rev), 2) AS top_10_rev,
    ROUND((SELECT total_revenue FROM total_rev), 2) AS total_revenue,
    ROUND(
        100.0 * (SELECT SUM(revenue) FROM top_cus_rev) /
        (SELECT total_revenue FROM total_rev),
        2
    ) AS percentage_top_10;


/* ============================================================
   6. Customer Revenue Ranking
   ------------------------------------------------------------
   Question:
   - Rank customers by total revenue contribution
   ============================================================ */

WITH customer_revenue AS (
    SELECT
        o.customer_id,
        SUM(oi.quantity + oi.unit_price * (1 - oi.discount_pct)) AS total_revenue
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    GROUP BY o.customer_id
)
SELECT
    customer_id,
    ROUND(total_revenue, 2) AS total_revenue,
    RANK() OVER (ORDER BY total_revenue DESC) AS revenue_rank
FROM customer_revenue
ORDER BY revenue_rank, customer_id;


/* ============================================================
   7. Time Between First and Second Order
   ------------------------------------------------------------
   Question:
   - For customers with at least two purchases, how many days
     passed between their first and second order?
   ============================================================ */

WITH ranked_orders AS (
    SELECT 
        customer_id,
        order_id,
        order_date,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY order_date, order_id
        ) AS rn
    FROM orders
)
SELECT
    customer_id,
    MAX(CASE WHEN rn = 1 THEN order_date END) AS first_order_date,
    MAX(CASE WHEN rn = 2 THEN order_date END) AS second_order_date,
    ROUND(
        julianday(MAX(CASE WHEN rn = 2 THEN order_date END)) -
        julianday(MAX(CASE WHEN rn = 1 THEN order_date END)),
        0
    ) AS days_to_second_order
FROM ranked_orders
WHERE rn IN (1, 2)
GROUP BY customer_id
HAVING COUNT(*) = 2
ORDER BY days_to_second_order ASC, customer_id;


/* ============================================================
   8. Cohort-Based Repeat Purchase Rate
   ------------------------------------------------------------
   Question:
   - For each customer’s first order month, what % of customers
     placed a second order (ever)?
   ============================================================ */

WITH ranked_orders AS (
    SELECT 
        customer_id,
        order_id,
        order_date,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY order_date, order_id
        ) AS rn
    FROM orders
),
customer_orders AS (
    SELECT
        customer_id,
        COUNT(*) AS customer_orders,
        MIN(order_date) AS first_order_date,
        MIN(CASE WHEN rn = 2 THEN order_date END) AS second_order_date
    FROM ranked_orders
    GROUP BY customer_id
),
cohorts AS (
    SELECT 
        customer_id,
        customer_orders,
        strftime('%Y-%m', first_order_date) AS cohort_month,
        CASE
            WHEN second_order_date IS NOT NULL
            THEN strftime('%Y-%m', second_order_date)
        END AS second_order_month
    FROM customer_orders
)
SELECT 
    cohort_month,
    COUNT(*) AS new_customers,
    SUM(CASE WHEN customer_orders >= 2 THEN 1 ELSE 0 END) AS repeat_customers,
    ROUND(
        100.0 *
        SUM(CASE WHEN customer_orders >= 2 THEN 1 ELSE 0 END) /
        COUNT(*),
        2
    ) AS repeat_rate
FROM cohorts
GROUP BY cohort_month
ORDER BY cohort_month;

-- ============================================================================
-- PROJECT: Advanced Business Intelligence & Analytical SQL Queries
-- DESCRIPTION: Implementation of CTEs, Window Functions, and Multi-Table Joins
-- ============================================================================


-- ============================================================================
-- QUERY 1: Customer Lifetime Value (LTV) Segmentation & Ranking using CTEs & DENSE_RANK()
-- Business Question: How do we rank customers within their respective geographic regions 
-- based on their total historical spend, and categorize them into value tiers?
-- ============================================================================
WITH CustomerSpend AS (
    SELECT 
        c.customer_id,
        c.customer_name,
        c.region,
        SUM(oi.quantity * p.unit_price * (1 - COALESCE(oi.discount_pct, 0))) AS total_spend
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    JOIN products p ON oi.product_id = p.product_id
    WHERE o.status = 'Completed'
    GROUP BY c.customer_id, c.customer_name, c.region
),
RegionalRanking AS (
    SELECT 
        customer_id,
        customer_name,
        region,
        total_spend,
        DENSE_RANK() OVER (PARTITION BY region ORDER BY total_spend DESC) as regional_rank
    FROM CustomerSpend
)
SELECT 
    customer_id,
    customer_name,
    region,
    ROUND(total_spend, 2) AS total_spend,
    regional_rank,
    CASE 
        WHEN regional_rank <= 3 THEN 'Tier 1 - Elite'
        WHEN regional_rank <= 10 THEN 'Tier 2 - Growth'
        ELSE 'Tier 3 - Standard'
    END AS customer_tier
FROM RegionalRanking
ORDER BY region, regional_rank;


-- ============================================================================
-- QUERY 2: Month-over-Month (MoM) Growth using LAG() & CTEs
-- Business Question: What is the monthly revenue growth rate and absolute revenue change 
-- compared to the previous month across the entire business?
-- ============================================================================
WITH MonthlyRevenue AS (
    SELECT 
        DATE_TRUNC('month', o.order_date) AS order_month,
        SUM(oi.quantity * p.unit_price) AS monthly_revenue
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    JOIN products p ON oi.product_id = p.product_id
    GROUP BY DATE_TRUNC('month', o.order_date)
),
RevenueLag AS (
    SELECT 
        order_month,
        monthly_revenue,
        LAG(monthly_revenue, 1) OVER (ORDER BY order_month) AS prev_month_revenue
    FROM MonthlyRevenue
)
SELECT 
    TO_CHAR(order_month, 'YYYY-MM') AS revenue_month,
    ROUND(monthly_revenue, 2) AS current_revenue,
    ROUND(prev_month_revenue, 2) AS previous_revenue,
    ROUND(monthly_revenue - COALESCE(prev_month_revenue, 0), 2) AS absolute_change,
    ROUND(
        ((monthly_revenue - prev_month_revenue) / NULLIF(prev_month_revenue, 0)) * 100, 2
    ) AS mom_growth_percentage
FROM RevenueLag
ORDER BY order_month;


-- ============================================================================
-- QUERY 3: Running Totals & Moving Averages using Window Frames (ROWS BETWEEN)
-- Business Question: What is the running total of daily revenue and a 7-day 
-- moving average of sales to smooth out volatility?
-- ============================================================================
WITH DailySales AS (
    SELECT 
        CAST(o.order_date AS DATE) AS sale_date,
        SUM(oi.quantity * p.unit_price) AS daily_revenue
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    JOIN products p ON oi.product_id = p.product_id
    GROUP BY CAST(o.order_date AS DATE)
)
SELECT 
    sale_date,
    ROUND(daily_revenue, 2) AS daily_revenue,
    ROUND(SUM(daily_revenue) OVER (ORDER BY sale_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2) AS running_total_revenue,
    ROUND(AVG(daily_revenue) OVER (ORDER BY sale_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS moving_avg_7day
FROM DailySales
ORDER BY sale_date;


-- ============================================================================
-- QUERY 4: Identifying Top Product per Category using ROW_NUMBER()
-- Business Question: Which single product generates the highest total revenue 
-- within each product category?
-- ============================================================================
WITH ProductSales AS (
    SELECT 
        p.category,
        p.product_id,
        p.product_name,
        SUM(oi.quantity) AS total_units_sold,
        SUM(oi.quantity * p.unit_price) AS total_revenue
    FROM products p
    JOIN order_items oi ON p.product_id = oi.product_id
    GROUP BY p.category, p.product_id, p.product_name
),
RankedProducts AS (
    SELECT 
        category,
        product_id,
        product_name,
        total_units_sold,
        total_revenue,
        ROW_NUMBER() OVER (PARTITION BY category ORDER BY total_revenue DESC) as product_rank
    FROM ProductSales
)
SELECT 
    category,
    product_name,
    total_units_sold,
    ROUND(total_revenue, 2) AS total_revenue
FROM RankedProducts
WHERE product_rank = 1
ORDER BY total_revenue DESC;


-- ============================================================================
-- QUERY 5: Customer Retention & Purchase Gaps using LEAD()
-- Business Question: What is the time gap (in days) between a customer's 
-- consecutive orders to analyze customer purchasing cadence?
-- ============================================================================
WITH CustomerOrderSequence AS (
    SELECT 
        customer_id,
        order_id,
        order_date,
        LEAD(order_date, 1) OVER (PARTITION BY customer_id ORDER BY order_date) AS next_order_date
    FROM orders
)
SELECT 
    customer_id,
    order_id,
    order_date,
    next_order_date,
    EXTRACT(DAY FROM (next_order_date - order_date)) AS days_until_next_order
FROM CustomerOrderSequence
WHERE next_order_date IS NOT NULL
ORDER BY customer_id, order_date;


-- ============================================================================
-- QUERY 6: Recursive CTE for Organizational Hierarchy / Management Tree
-- Business Question: What is the complete management reporting chain and depth 
-- level for every employee in the company?
-- ============================================================================
WITH RECURSIVE EmployeeHierarchy AS (
    -- Anchor member: Top-level managers (no manager)
    SELECT 
        employee_id,
        employee_name,
        manager_id,
        department,
        1 AS hierarchy_level,
        CAST(employee_name AS VARCHAR(500)) AS reporting_path
    FROM employees
    WHERE manager_id IS NULL
    
    UNION ALL
    
    -- Recursive member: Subordinates
    SELECT 
        e.employee_id,
        e.employee_name,
        e.manager_id,
        e.department,
        eh.hierarchy_level + 1,
        CAST(eh.reporting_path || ' -> ' || e.employee_name AS VARCHAR(500))
    FROM employees e
    JOIN EmployeeHierarchy eh ON e.manager_id = eh.employee_id
)
SELECT 
    employee_id,
    employee_name,
    department,
    hierarchy_level,
    reporting_path
FROM EmployeeHierarchy
ORDER BY hierarchy_level, department;


-- ============================================================================
-- QUERY 7: Multi-Table Joins & Full Outer Join Gap Analysis
-- Business Question: Which products have never been ordered, and conversely, 
-- which categories have no active products? (Full coverage reconciliation)
-- ============================================================================
SELECT 
    p.product_id AS catalog_product_id,
    p.product_name,
    p.category,
    COALESCE(SUM(oi.quantity), 0) AS units_ordered,
    CASE 
        WHEN oi.product_id IS NULL THEN 'Unsold Product'
        ELSE 'Active Product'
    END AS product_status
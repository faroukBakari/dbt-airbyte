-- Gold layer: Final analytics-ready user purchase summary
-- Materialized as table in gold schema for BI/reporting consumption
{{ config(schema='gold') }}

WITH user_purchases AS (
    SELECT * FROM {{ ref('dim_users') }}
),

products AS (
    SELECT * FROM {{ ref('dim_products') }}
),

purchases AS (
    SELECT * FROM {{ ref('stg_purchases') }}
),

-- Get last purchased product per user using Postgres-specific DISTINCT ON.
-- This picks the first row per user_id after ORDER BY … DESC, giving us the
-- most recent purchase. Not portable to other SQL engines — see README Known Limitations.
user_last_purchase AS (
    SELECT DISTINCT ON (p.user_id)
        p.user_id,
        pr.make || ' ' || pr.model AS last_product,
        pr.price AS last_product_price
    FROM purchases AS p
    JOIN products AS pr ON p.product_id = pr.product_id
    ORDER BY p.user_id, p.purchased_at DESC
)

SELECT
    up.user_id,
    up.full_name,
    up.email,
    up.occupation,
    up.city,
    up.state,
    up.country_code,
    up.age,
    up.total_purchases,
    up.total_spent,
    up.total_returns,
    ROUND(up.total_spent / NULLIF(up.total_purchases, 0), 2) AS avg_purchase_value,
    ROUND(up.total_returns::numeric / NULLIF(up.total_purchases, 0) * 100, 1) AS return_rate_pct,
    ulp.last_product AS last_purchased_product,
    ulp.last_product_price AS last_purchased_price,
    up.first_purchase_at,
    up.last_purchase_at,
    up.created_at AS user_created_at,
    CURRENT_TIMESTAMP AS refreshed_at
FROM user_purchases AS up
LEFT JOIN user_last_purchase AS ulp ON up.user_id = ulp.user_id
WHERE up.total_purchases > 0

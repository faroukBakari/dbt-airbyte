-- Mart: Product dimension with sales metrics
WITH products AS (
    SELECT * FROM {{ ref('stg_products') }}
),

purchases AS (
    SELECT * FROM {{ ref('stg_purchases') }}
),

product_sales AS (
    SELECT
        product_id,
        COUNT(*) AS times_sold,
        COUNT(CASE WHEN returned_at IS NOT NULL THEN 1 END) AS times_returned
    FROM purchases
    GROUP BY product_id
)

SELECT
    p.product_id,
    p.make,
    p.model,
    p.year,
    p.price,
    p.created_at,
    p.loaded_at,
    COALESCE(ps.times_sold, 0) AS times_sold,
    COALESCE(ps.times_returned, 0) AS times_returned
FROM products AS p
LEFT JOIN product_sales AS ps ON p.product_id = ps.product_id

-- Fact table: Individual purchase transactions enriched with product data
-- Sits at the mart layer between staging and gold, preventing gold from
-- reaching down into staging directly.
{{ config(schema='marts') }}

SELECT
    p.purchase_id,
    p.user_id,
    p.product_id,
    pr.make AS product_make,
    pr.model AS product_model,
    pr.price AS product_price,
    p.purchased_at,
    p.added_to_cart_at,
    p.returned_at,
    p.returned_at IS NOT NULL AS is_returned,
    p.loaded_at
FROM {{ ref('stg_purchases') }} AS p
LEFT JOIN {{ ref('stg_products') }} AS pr ON p.product_id = pr.product_id

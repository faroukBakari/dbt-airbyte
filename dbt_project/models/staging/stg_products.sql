-- Staging model: Clean and normalize raw product data from Airbyte Sample Data
WITH raw_products AS (
    SELECT
        _airbyte_data::jsonb AS data,
        _airbyte_emitted_at AS loaded_at
    FROM {{ source('airbyte_raw', '_airbyte_raw_products') }}
)

SELECT
    (data ->> 'id')::bigint AS product_id,
    data ->> 'make' AS make,
    data ->> 'model' AS model,
    (data ->> 'year')::int AS year,
    (data ->> 'price')::decimal(10, 2) AS price,
    (data ->> 'created_at')::timestamptz AS created_at,
    loaded_at
FROM raw_products

-- Staging model: Clean and normalize raw purchase data from Airbyte Sample Data
WITH raw_purchases AS (
    SELECT
        _airbyte_data::jsonb AS data,
        _airbyte_emitted_at AS loaded_at
    FROM {{ source('airbyte_raw', '_airbyte_raw_purchases') }}
)

SELECT
    (data ->> 'id')::bigint AS purchase_id,
    (data ->> 'user_id')::bigint AS user_id,
    (data ->> 'product_id')::bigint AS product_id,
    (data ->> 'purchased_at')::timestamptz AS purchased_at,
    (data ->> 'added_to_cart_at')::timestamptz AS added_to_cart_at,
    (data ->> 'returned_at')::timestamptz AS returned_at,
    loaded_at
FROM raw_purchases

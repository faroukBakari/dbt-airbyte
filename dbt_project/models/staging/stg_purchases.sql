-- Staging model: Clean and normalize raw purchase data from Airbyte Sample Data
with raw_purchases as (
    select
        _airbyte_data::jsonb as data,
        _airbyte_emitted_at as loaded_at
    from {{ source('airbyte_raw', '_airbyte_raw_purchases') }}
)

select
    (data->>'id')::bigint as purchase_id,
    (data->>'user_id')::bigint as user_id,
    (data->>'product_id')::bigint as product_id,
    (data->>'purchased_at')::timestamptz as purchased_at,
    (data->>'added_to_cart_at')::timestamptz as added_to_cart_at,
    (data->>'returned_at')::timestamptz as returned_at,
    loaded_at
from raw_purchases

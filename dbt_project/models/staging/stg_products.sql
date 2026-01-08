-- Staging model: Clean and normalize raw product data from Airbyte Sample Data
with raw_products as (
    select
        _airbyte_data::jsonb as data,
        _airbyte_extracted_at as loaded_at
    from {{ source('airbyte_raw', '_airbyte_raw_products') }}
)

select
    (data->>'id')::bigint as product_id,
    data->>'make' as make,
    data->>'model' as model,
    (data->>'year')::int as year,
    (data->>'price')::decimal(10,2) as price,
    (data->>'created_at')::timestamptz as created_at,
    loaded_at
from raw_products

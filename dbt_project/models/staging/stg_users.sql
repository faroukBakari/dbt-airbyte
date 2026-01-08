-- Staging model: Clean and normalize raw user data from Airbyte Sample Data
with raw_users as (
    select
        _airbyte_data::jsonb as data,
        _airbyte_extracted_at as loaded_at
    from {{ source('airbyte_raw', '_airbyte_raw_users') }}
)

select
    (data->>'id')::bigint as user_id,
    data->>'name' as full_name,
    data->>'email' as email,
    data->>'gender' as gender,
    data->>'title' as title,
    data->>'occupation' as occupation,
    data->>'nationality' as nationality,
    data->>'language' as language,
    data->>'academic_degree' as academic_degree,
    (data->>'age')::int as age,
    data->>'blood_type' as blood_type,
    (data->'address'->>'city') as city,
    (data->'address'->>'state') as state,
    (data->'address'->>'country_code') as country_code,
    (data->'address'->>'postal_code') as postal_code,
    (data->>'created_at')::timestamptz as created_at,
    (data->>'updated_at')::timestamptz as updated_at,
    loaded_at
from raw_users

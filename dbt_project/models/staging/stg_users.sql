-- Staging model: Clean and normalize raw user data from Airbyte Sample Data
-- Airbyte stores all source fields as JSON inside _airbyte_data.
-- We extract each field with ->> (text) then cast to the target type.
-- Nested objects (e.g. address) use chained -> / ->> accessors.
WITH raw_users AS (
    SELECT
        _airbyte_data::jsonb AS data,
        _airbyte_emitted_at AS loaded_at
    FROM {{ source('airbyte_raw', '_airbyte_raw_users') }}
)

SELECT
    (data ->> 'id')::bigint AS user_id,
    data ->> 'name' AS full_name,
    data ->> 'email' AS email,
    data ->> 'gender' AS gender,
    data ->> 'title' AS title,
    data ->> 'occupation' AS occupation,
    data ->> 'nationality' AS nationality,
    data ->> 'language' AS language,
    data ->> 'academic_degree' AS academic_degree,
    (data ->> 'age')::int AS age,
    data ->> 'blood_type' AS blood_type,
    (data -> 'address' ->> 'city') AS city,
    (data -> 'address' ->> 'state') AS state,
    (data -> 'address' ->> 'country_code') AS country_code,
    (data -> 'address' ->> 'postal_code') AS postal_code,
    (data ->> 'created_at')::timestamptz AS created_at,
    (data ->> 'updated_at')::timestamptz AS updated_at,
    loaded_at
FROM raw_users

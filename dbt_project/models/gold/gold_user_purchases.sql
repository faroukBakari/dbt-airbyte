-- Gold layer: Final analytics-ready user purchase summary
-- Materialized as table in gold schema for BI/reporting consumption
{{ config(schema='gold') }}

with user_purchases as (
    select * from {{ ref('dim_users') }}
),

products as (
    select * from {{ ref('dim_products') }}
),

purchases as (
    select * from {{ ref('stg_purchases') }}
),

-- Get last purchased product per user using Postgres-specific DISTINCT ON.
-- This picks the first row per user_id after ORDER BY … DESC, giving us the
-- most recent purchase. Not portable to other SQL engines — see README Known Limitations.
user_last_purchase as (
    select distinct on (p.user_id)
        p.user_id,
        pr.make || ' ' || pr.model as last_product,
        pr.price as last_product_price
    from purchases p
    join products pr on p.product_id = pr.product_id
    order by p.user_id, p.purchased_at desc
)

select
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
    round(up.total_spent / nullif(up.total_purchases, 0), 2) as avg_purchase_value,
    round(up.total_returns::numeric / nullif(up.total_purchases, 0) * 100, 1) as return_rate_pct,
    ulp.last_product as last_purchased_product,
    ulp.last_product_price as last_purchased_price,
    up.first_purchase_at,
    up.last_purchase_at,
    up.created_at as user_created_at,
    current_timestamp as refreshed_at
from user_purchases up
left join user_last_purchase ulp on up.user_id = ulp.user_id
where up.total_purchases > 0

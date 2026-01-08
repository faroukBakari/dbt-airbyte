-- Mart: User dimension with purchase activity summary
with users as (
    select * from {{ ref('stg_users') }}
),

purchases as (
    select * from {{ ref('stg_purchases') }}
),

products as (
    select * from {{ ref('stg_products') }}
),

user_purchases as (
    select
        p.user_id,
        count(*) as total_purchases,
        sum(pr.price) as total_spent,
        count(case when p.returned_at is not null then 1 end) as total_returns,
        min(p.purchased_at) as first_purchase_at,
        max(p.purchased_at) as last_purchase_at
    from purchases p
    left join products pr on p.product_id = pr.product_id
    group by p.user_id
)

select
    u.user_id,
    u.full_name,
    u.email,
    u.occupation,
    u.city,
    u.state,
    u.country_code,
    u.age,
    u.created_at,
    coalesce(up.total_purchases, 0) as total_purchases,
    coalesce(up.total_spent, 0) as total_spent,
    coalesce(up.total_returns, 0) as total_returns,
    up.first_purchase_at,
    up.last_purchase_at
from users u
left join user_purchases up on u.user_id = up.user_id

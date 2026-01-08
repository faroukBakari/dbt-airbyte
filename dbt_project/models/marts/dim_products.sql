-- Mart: Product dimension with sales metrics
with products as (
    select * from {{ ref('stg_products') }}
),

purchases as (
    select * from {{ ref('stg_purchases') }}
),

product_sales as (
    select
        product_id,
        count(*) as times_sold,
        count(case when returned_at is not null then 1 end) as times_returned
    from purchases
    group by product_id
)

select
    p.product_id,
    p.make,
    p.model,
    p.year,
    p.price,
    p.created_at,
    p.loaded_at,
    coalesce(ps.times_sold, 0) as times_sold,
    coalesce(ps.times_returned, 0) as times_returned
from products p
left join product_sales ps on p.product_id = ps.product_id

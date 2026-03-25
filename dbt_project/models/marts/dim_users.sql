-- Mart: User dimension with purchase activity summary
WITH users AS (
    SELECT
        user_id,
        full_name,
        email,
        occupation,
        city,
        state,
        country_code,
        age,
        created_at
    FROM {{ ref('stg_users') }}
),

purchases AS (
    SELECT
        purchase_id,
        user_id,
        product_id,
        purchased_at,
        returned_at
    FROM {{ ref('stg_purchases') }}
),

products AS (
    SELECT
        product_id,
        price
    FROM {{ ref('stg_products') }}
),

user_purchases AS (
    SELECT
        p.user_id,
        COUNT(*) AS total_purchases,
        SUM(pr.price) AS total_spent,
        COUNT(CASE WHEN p.returned_at IS NOT NULL THEN 1 END) AS total_returns,
        MIN(p.purchased_at) AS first_purchase_at,
        MAX(p.purchased_at) AS last_purchase_at
    FROM purchases AS p
    LEFT JOIN products AS pr ON p.product_id = pr.product_id
    GROUP BY p.user_id
)

SELECT
    u.user_id,
    u.full_name,
    u.email,
    u.occupation,
    u.city,
    u.state,
    u.country_code,
    u.age,
    u.created_at,
    COALESCE(up.total_purchases, 0) AS total_purchases,
    COALESCE(up.total_spent, 0) AS total_spent,
    COALESCE(up.total_returns, 0) AS total_returns,
    up.first_purchase_at,
    up.last_purchase_at
FROM users AS u
LEFT JOIN user_purchases AS up ON u.user_id = up.user_id

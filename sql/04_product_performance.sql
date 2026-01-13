--1. Top Converting Products
-- Which products have the highest view-to-purchase conversion rate?
WITH product_funnel AS (
    SELECT
        product_name,
        COUNT(DISTINCT CASE WHEN event_name = 'view_item' THEN user_id END) AS viewers,
        COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN user_id END) AS purchasers
    FROM events_clean
    WHERE event_name IN ('view_item', 'purchase')
      AND product_name IS NOT NULL
    GROUP BY product_name
)

SELECT TOP 10
    product_name,
    viewers,
    purchasers,
    ROUND(
        100.0 * purchasers / NULLIF(viewers, 0),
        2
    ) AS conversion_rate_percentage
FROM product_funnel
WHERE viewers >= 20        -- removes noise from rarely viewed products
ORDER BY conversion_rate_percentage DESC;

--2. Cart Abandonment by Product
-- Which products are most frequently added to cart but not purchased?
WITH cart_products AS (
    SELECT DISTINCT
        user_id,
        product_name
    FROM events_clean
    WHERE event_name = 'add_to_cart'
      AND product_name IS NOT NULL
),

purchase_products AS (
    SELECT DISTINCT
        user_id,
        product_name
    FROM events_clean
    WHERE event_name = 'purchase'
      AND product_name IS NOT NULL
)

SELECT TOP 10
    c.product_name,
    COUNT(DISTINCT c.user_id) AS users_added_to_cart,
    COUNT(DISTINCT p.user_id) AS users_purchased,
    COUNT(DISTINCT c.user_id) - COUNT(DISTINCT p.user_id) AS users_abandoned,
    ROUND(
        100.0 * 
        (COUNT(DISTINCT c.user_id) - COUNT(DISTINCT p.user_id)) /
        COUNT(DISTINCT c.user_id),
        2
    ) AS abandonment_rate_percentage
FROM cart_products c
LEFT JOIN purchase_products p
    ON c.user_id = p.user_id
   AND c.product_name = p.product_name
GROUP BY c.product_name
HAVING COUNT(DISTINCT c.user_id) >= 20   -- remove noise
ORDER BY abandonment_rate_percentage DESC;

--3. Product Affinity
-- What products are frequently purchased together in the same transaction?
WITH purchase_items AS (
    SELECT
        session_id,
        product_name
    FROM events_clean
    WHERE event_name = 'purchase'
      AND product_name IS NOT NULL
),

pairs AS (
    SELECT
        p1.product_name AS product_a,
        p2.product_name AS product_b
    FROM purchase_items p1
    JOIN purchase_items p2
        ON p1.session_id = p2.session_id
       AND p1.product_name < p2.product_name   -- avoids duplicates and self-pairs
)

SELECT TOP 10
    product_a,
    product_b,
    COUNT(*) AS times_bought_together
FROM pairs
GROUP BY product_a, product_b
ORDER BY times_bought_together DESC;

--1. Cart Abandonment Rate
-- What percentage of users who add items to cart never complete a purchase?
WITH add_to_cart_users AS (
    SELECT DISTINCT user_id
    FROM events_clean
    WHERE event_name = 'add_to_cart'
),

purchase_users AS (
    SELECT DISTINCT user_id
    FROM events_clean
    WHERE event_name = 'purchase'
)

SELECT
    COUNT(DISTINCT a.user_id) AS users_added_to_cart,
    COUNT(DISTINCT p.user_id) AS users_who_purchased,
    COUNT(DISTINCT a.user_id) - COUNT(DISTINCT p.user_id) AS users_who_abandoned,
    ROUND(
        100.0 * 
        (COUNT(DISTINCT a.user_id) - COUNT(DISTINCT p.user_id)) 
        / COUNT(DISTINCT a.user_id),
        2
    ) AS cart_abandonment_rate_percentage
FROM add_to_cart_users a
LEFT JOIN purchase_users p
    ON a.user_id = p.user_id;

--2. Average Cart Value
-- What's the average number of items added to cart per session? How does this compare to actual purchased items?
-- Cart Size
WITH cart_sessions AS (
    SELECT
        session_id,
        COUNT(DISTINCT product_name) AS cart_size
    FROM events_clean
    WHERE event_name = 'add_to_cart'
      AND product_name IS NOT NULL
    GROUP BY session_id
)

SELECT
    COUNT(*) AS total_cart_sessions,
    ROUND(AVG(CAST(cart_size AS FLOAT)), 2) AS avg_cart_size,
    MIN(cart_size) AS min_cart_size,
    MAX(cart_size) AS max_cart_size
FROM cart_sessions;

-- Purchase Size
WITH purchase_sessions AS (
    SELECT
        session_id,
        COUNT(DISTINCT product_name) AS purchase_size
    FROM events_clean
    WHERE event_name = 'purchase'
      AND product_name IS NOT NULL
    GROUP BY session_id
)

SELECT
    COUNT(*) AS total_purchase_sessions,
    ROUND(AVG(CAST(purchase_size AS FLOAT)), 2) AS avg_purchase_size,
    MIN(purchase_size) AS min_purchase_size,
    MAX(purchase_size) AS max_purchase_size
FROM purchase_sessions;

--3. Time Between Add-to-Cart and Purchase
-- For users who purchase, what's the median time between adding to cart and completing purchase?
WITH cart_times AS (
    SELECT
        user_id,
        session_id,
        MIN(event_time) AS first_cart_time
    FROM events_clean
    WHERE event_name = 'add_to_cart'
    GROUP BY user_id, session_id
),

purchase_times AS (
    SELECT
        user_id,
        session_id,
        MIN(event_time) AS first_purchase_time
    FROM events_clean
    WHERE event_name = 'purchase'
    GROUP BY user_id, session_id
),

cart_to_purchase AS (
    SELECT
        DATEDIFF(
            MINUTE,
            c.first_cart_time,
            p.first_purchase_time
        ) AS minutes_to_purchase
    FROM cart_times c
    JOIN purchase_times p
        ON c.user_id = p.user_id
       AND c.session_id = p.session_id
    WHERE p.first_purchase_time >= c.first_cart_time
),

agg_stats AS (
    SELECT
        COUNT(*) AS total_purchases_after_cart,
        ROUND(AVG(CAST(minutes_to_purchase AS FLOAT)), 2) AS avg_minutes_to_purchase,
        MIN(minutes_to_purchase) AS min_minutes_to_purchase,
        MAX(minutes_to_purchase) AS max_minutes_to_purchase
    FROM cart_to_purchase
),

median_stats AS (
    SELECT DISTINCT
        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY minutes_to_purchase)
            OVER () AS median_minutes_to_purchase
    FROM cart_to_purchase
)

SELECT
    a.total_purchases_after_cart,
    a.avg_minutes_to_purchase,
    a.min_minutes_to_purchase,
    a.max_minutes_to_purchase,
    m.median_minutes_to_purchase
FROM agg_stats a
CROSS JOIN median_stats m;

--4. Checkout Abandonment Point
-- Of users who begin checkout, what percentage complete the purchase? Where exactly do they drop off?
WITH checkout_users AS (
    SELECT DISTINCT user_id
    FROM events_clean
    WHERE event_name = 'begin_checkout'
),

purchase_users AS (
    SELECT DISTINCT user_id
    FROM events_clean
    WHERE event_name = 'purchase'
)

SELECT
    COUNT(DISTINCT c.user_id) AS users_started_checkout,
    COUNT(DISTINCT p.user_id) AS users_completed_purchase,
    COUNT(DISTINCT c.user_id) - COUNT(DISTINCT p.user_id) AS users_abandoned_checkout,
    ROUND(
        100.0 * COUNT(DISTINCT p.user_id) / COUNT(DISTINCT c.user_id),
        2
    ) AS checkout_completion_rate_percentage,
    ROUND(
        100.0 * 
        (COUNT(DISTINCT c.user_id) - COUNT(DISTINCT p.user_id)) 
        / COUNT(DISTINCT c.user_id),
        2
    ) AS checkout_abandonment_rate_percentage
FROM checkout_users c
LEFT JOIN purchase_users p
    ON c.user_id = p.user_id;

--5. Multiple Cart Additions
-- How many times does the average user add items to cart before purchasing? Do multiple additions correlate with higher purchase value?
WITH first_purchase AS (
    SELECT
        user_id,
        MIN(event_time) AS first_purchase_time
    FROM events_clean
    WHERE event_name = 'purchase'
    GROUP BY user_id
),

cart_additions AS (
    SELECT
        e.user_id,
        COUNT(*) AS add_to_cart_events
    FROM events_clean e
    JOIN first_purchase p
        ON e.user_id = p.user_id
       AND e.event_time <= p.first_purchase_time
    WHERE e.event_name = 'add_to_cart'
    GROUP BY e.user_id
),

purchase_revenue AS (
    SELECT
        user_id,
        SUM(COALESCE(revenue, 0)) AS total_revenue
    FROM events_clean
    WHERE event_name = 'purchase'
    GROUP BY user_id
)

SELECT
    ROUND(AVG(CAST(c.add_to_cart_events AS FLOAT)), 2) AS avg_add_to_cart_events_before_purchase,
    ROUND(AVG(CAST(r.total_revenue AS FLOAT)), 2) AS avg_purchase_revenue
FROM cart_additions c
JOIN purchase_revenue r
    ON c.user_id = r.user_id;

-- Does multiple purchase equals high purchase value
WITH first_purchase AS (
    SELECT
        user_id,
        MIN(event_time) AS first_purchase_time
    FROM events_clean
    WHERE event_name = 'purchase'
    GROUP BY user_id
),

cart_additions AS (
    SELECT
        e.user_id,
        COUNT(*) AS add_to_cart_events
    FROM events_clean e
    JOIN first_purchase p
        ON e.user_id = p.user_id
       AND e.event_time <= p.first_purchase_time
    WHERE e.event_name = 'add_to_cart'
    GROUP BY e.user_id
),

purchase_revenue AS (
    SELECT
        user_id,
        SUM(COALESCE(revenue, 0)) AS total_revenue
    FROM events_clean
    WHERE event_name = 'purchase'
    GROUP BY user_id
)

SELECT
    CASE
        WHEN c.add_to_cart_events = 1 THEN '1 add'
        WHEN c.add_to_cart_events BETWEEN 2 AND 3 THEN '2–3 adds'
        WHEN c.add_to_cart_events BETWEEN 4 AND 6 THEN '4–6 adds'
        ELSE '7+ adds'
    END AS cart_activity_group,
    COUNT(*) AS users,
    ROUND(AVG(CAST(r.total_revenue AS FLOAT)), 2) AS avg_revenue
FROM cart_additions c
JOIN purchase_revenue r
    ON c.user_id = r.user_id
GROUP BY
    CASE
        WHEN c.add_to_cart_events = 1 THEN '1 add'
        WHEN c.add_to_cart_events BETWEEN 2 AND 3 THEN '2–3 adds'
        WHEN c.add_to_cart_events BETWEEN 4 AND 6 THEN '4–6 adds'
        ELSE '7+ adds'
    END
ORDER BY users DESC;



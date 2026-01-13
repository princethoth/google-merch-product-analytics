--1. Conversion by Traffic Source
-- Which traffic source has the highest conversion rate?
WITH funnel AS (
    SELECT
        traffic_source,
        COUNT(DISTINCT CASE WHEN event_name = 'view_item' THEN user_id END) AS viewers,
        COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN user_id END) AS purchasers
    FROM events_clean
    WHERE event_name IN ('view_item', 'purchase')
      AND traffic_source IS NOT NULL
    GROUP BY traffic_source
)

SELECT
    traffic_source,
    viewers,
    purchasers,
    ROUND(
        100.0 * purchasers / NULLIF(viewers, 0),
        2
    ) AS conversion_rate_percentage
FROM funnel
ORDER BY conversion_rate_percentage DESC;

--2. Traffic Source Journey Length
-- Do users from different traffic sources take more/fewer sessions to purchase?
WITH first_purchase AS (
    SELECT
        user_id,
        MIN(event_time) AS first_purchase_time
    FROM events_clean
    WHERE event_name = 'purchase'
    GROUP BY user_id
),

sessions_before_purchase AS (
    SELECT
        e.user_id,
        e.traffic_source,
        COUNT(DISTINCT e.session_id) AS sessions_to_purchase
    FROM events_clean e
    JOIN first_purchase p
        ON e.user_id = p.user_id
       AND e.event_time <= p.first_purchase_time
    GROUP BY e.user_id, e.traffic_source
)

SELECT
    traffic_source,
    COUNT(*) AS users,
    ROUND(AVG(CAST(sessions_to_purchase AS FLOAT)), 2) AS avg_sessions_to_purchase,
    MIN(sessions_to_purchase) AS min_sessions,
    MAX(sessions_to_purchase) AS max_sessions
FROM sessions_before_purchase
GROUP BY traffic_source
ORDER BY avg_sessions_to_purchase;

--3. Revenue by Traffic Source
-- Which traffic source generates the most revenue? What's the average order value per source?
WITH purchases AS (
    SELECT
        traffic_source,
        session_id,
        SUM(COALESCE(revenue, 0)) AS order_revenue
    FROM events_clean
    WHERE event_name = 'purchase'
      AND traffic_source IS NOT NULL
    GROUP BY traffic_source, session_id
)

SELECT
    traffic_source,
    COUNT(*) AS total_orders,
    ROUND(SUM(order_revenue), 2) AS total_revenue,
    ROUND(AVG(order_revenue), 2) AS avg_order_value
FROM purchases
GROUP BY traffic_source
ORDER BY total_revenue DESC;

--4. New vs Returning User Behavior
-- How do new users' funnel metrics compare to returning users?
WITH first_seen AS (
    SELECT
        user_id,
        MIN(event_time) AS first_seen_time
    FROM events_clean
    GROUP BY user_id
),

user_type AS (
    SELECT
        e.user_id,
        CASE 
            WHEN e.event_time = f.first_seen_time THEN 'New User'
            ELSE 'Returning User'
        END AS user_type,
        e.event_name
    FROM events_clean e
    JOIN first_seen f
        ON e.user_id = f.user_id
),

funnel AS (
    SELECT
        user_type,
        COUNT(DISTINCT CASE WHEN event_name = 'view_item' THEN user_id END) AS viewers,
        COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN user_id END) AS purchasers
    FROM user_type
    GROUP BY user_type
)

SELECT
    user_type,
    viewers,
    purchasers,
    ROUND(
        100.0 * purchasers / NULLIF(viewers, 0),
        2
    ) AS conversion_rate_percentage
FROM funnel;

--5. Mobile vs Desktop Conversion
-- Does device category affect conversion rates?
WITH funnel AS (
    SELECT
        device_category,
        COUNT(DISTINCT CASE WHEN event_name = 'view_item' THEN user_id END) AS viewers,
        COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN user_id END) AS purchasers
    FROM events_clean
    WHERE event_name IN ('view_item', 'purchase')
      AND device_category IS NOT NULL
    GROUP BY device_category
)

SELECT
    device_category,
    viewers,
    purchasers,
    ROUND(
        100.0 * purchasers / NULLIF(viewers, 0),
        2
    ) AS conversion_rate_percentage
FROM funnel
ORDER BY conversion_rate_percentage DESC;

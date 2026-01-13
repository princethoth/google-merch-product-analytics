--1. Funnel Overview
SELECT 
    event_name AS funnel_stage,
    COUNT(DISTINCT user_id) AS unique_users
FROM events_clean
WHERE event_name IN (
    'view_item',
    'add_to_cart',
    'begin_checkout',
    'purchase'
)
GROUP BY event_name
ORDER BY 
    CASE event_name
        WHEN 'view_item' THEN 1
        WHEN 'add_to_cart' THEN 2
        WHEN 'begin_checkout' THEN 3
        WHEN 'purchase' THEN 4
    END;

-- Overall conversion rate from landing to purchase
WITH funnel AS (
    SELECT 
        event_name,
        COUNT(DISTINCT user_id) AS users
    FROM events_clean
    WHERE event_name IN (
        'view_item',
        'add_to_cart',
        'begin_checkout',
        'purchase'
    )
    GROUP BY event_name
)
SELECT 
    CAST(
        100.0 *
        (SELECT users FROM funnel WHERE event_name = 'purchase') /
        (SELECT users FROM funnel WHERE event_name = 'view_item')
        AS DECIMAL(5,2)
    ) AS product_conversion_rate_percentage;

--2. Funnel Drop-off Rates
-- What percentage of users drop off between each consecutive funnel stage?
WITH funnel AS (
    SELECT 
        event_name AS funnel_stage,
        COUNT(DISTINCT user_id) AS users,
        CASE event_name
            WHEN 'view_item' THEN 1
            WHEN 'add_to_cart' THEN 2
            WHEN 'begin_checkout' THEN 3
            WHEN 'purchase' THEN 4
        END AS stage_order
    FROM events_clean
    WHERE event_name IN (
        'view_item',
        'add_to_cart',
        'begin_checkout',
        'purchase'
    )
    GROUP BY event_name
),

ordered_funnel AS (
    SELECT
        funnel_stage,
        users,
        stage_order,
        LAG(users) OVER (ORDER BY stage_order) AS previous_stage_users
    FROM funnel
)

SELECT
    funnel_stage,
    users,
    previous_stage_users,
    CASE 
        WHEN previous_stage_users IS NULL THEN NULL
        ELSE ROUND(
            (previous_stage_users - users) * 100.0 / previous_stage_users,
            2
        )
    END AS dropoff_percentage
FROM ordered_funnel
ORDER BY stage_order;

--3. Time to Purchase
-- What's the average time (in days/hours) between a user's first session and their first purchase?
WITH first_events AS (
    SELECT
        user_id,
        MIN(CASE WHEN event_name = 'view_item' THEN event_time END) AS first_view_time,
        MIN(CASE WHEN event_name = 'purchase' THEN event_time END) AS first_purchase_time
    FROM events_clean
    GROUP BY user_id
),
cleaned AS (
    SELECT
        user_id,
        DATEDIFF(
            HOUR,
            first_view_time,
            first_purchase_time
        ) AS hours_to_purchase
    FROM first_events
    WHERE first_view_time IS NOT NULL
      AND first_purchase_time IS NOT NULL
      AND first_purchase_time >= first_view_time
),

agg_stats AS (
    SELECT
        COUNT(*) AS total_purchasers,
        ROUND(AVG(CAST(hours_to_purchase AS FLOAT)), 2) AS avg_hours_to_purchase,
        MIN(hours_to_purchase) AS min_hours_to_purchase,
        MAX(hours_to_purchase) AS max_hours_to_purchase
    FROM cleaned
),

median_stats AS (
    SELECT DISTINCT
        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY hours_to_purchase)
            OVER () AS median_hours_to_purchase
    FROM cleaned
)

SELECT
    a.total_purchasers,
    a.avg_hours_to_purchase,
    a.min_hours_to_purchase,
    a.max_hours_to_purchase,
    m.median_hours_to_purchase
FROM agg_stats a
CROSS JOIN median_stats m;

--4. Multi-Touch vs Single-Session Purchases
-- How many users purchase in their first session vs. returning multiple times before purchasing?
WITH first_view AS (
    SELECT
        user_id,
        MIN(event_time) AS first_view_time
    FROM events_clean
    WHERE event_name = 'view_item'
    GROUP BY user_id
),

first_purchase AS (
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
        COUNT(DISTINCT e.session_id) AS sessions_count
    FROM events_clean e
    JOIN first_view fv
        ON e.user_id = fv.user_id
    JOIN first_purchase fp
        ON e.user_id = fp.user_id
    WHERE e.event_time >= fv.first_view_time
      AND e.event_time <= fp.first_purchase_time
    GROUP BY e.user_id
)

SELECT
    CASE 
        WHEN sessions_count = 1 THEN 'Single-session purchase'
        ELSE 'Multi-session purchase'
    END AS purchase_type,
    COUNT(*) AS users,
    ROUND(
        COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (),
        2
    ) AS percentage
FROM sessions_before_purchase
GROUP BY
    CASE 
        WHEN sessions_count = 1 THEN 'Single-session purchase'
        ELSE 'Multi-session purchase'
    END;

--5. Daily Funnel Trends
-- How does the conversion rate vary by day of the week? Which day has the highest conversion?
WITH daily_funnel AS (
    SELECT
        CAST(event_time AS DATE) AS event_day,
        DATENAME(WEEKDAY, event_time) AS day_name,
        COUNT(DISTINCT CASE WHEN event_name = 'view_item' THEN user_id END) AS viewers,
        COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN user_id END) AS purchasers
    FROM events_clean
    WHERE event_name IN ('view_item', 'purchase')
    GROUP BY
        CAST(event_time AS DATE),
        DATENAME(WEEKDAY, event_time)
)

SELECT
    day_name,
    SUM(viewers) AS total_viewers,
    SUM(purchasers) AS total_purchasers,
    ROUND(
        100.0 * SUM(purchasers) / NULLIF(SUM(viewers), 0),
        2
    ) AS conversion_rate_percentage
FROM daily_funnel
GROUP BY day_name
ORDER BY conversion_rate_percentage DESC;








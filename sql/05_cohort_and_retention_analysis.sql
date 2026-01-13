--1. Cohort Conversion Rates
-- Weekly user cohorts (by first visit date). How does conversion rate differ across cohorts?
WITH first_seen AS (
    SELECT
        user_id,
        MIN(event_time) AS first_seen_time
    FROM events_clean
    GROUP BY user_id
),

cohorts AS (
    SELECT
        user_id,
        DATEADD(WEEK, DATEDIFF(WEEK, 0, first_seen_time), 0) AS cohort_week
    FROM first_seen
),

cohort_funnel AS (
    SELECT
        c.cohort_week,
        COUNT(DISTINCT CASE WHEN e.event_name = 'view_item' THEN e.user_id END) AS viewers,
        COUNT(DISTINCT CASE WHEN e.event_name = 'purchase' THEN e.user_id END) AS purchasers
    FROM cohorts c
    JOIN events_clean e
        ON c.user_id = e.user_id
    GROUP BY c.cohort_week
)

SELECT
    cohort_week,
    viewers,
    purchasers,
    ROUND(
        100.0 * purchasers / NULLIF(viewers, 0),
        2
    ) AS conversion_rate_percentage
FROM cohort_funnel
ORDER BY cohort_week;

--2. Time-to-Value Analysis
-- For users who eventually purchase, what actions in their first session predict faster conversion?
WITH first_session AS (
    SELECT
        user_id,
        MIN(event_time) AS first_session_time
    FROM events_clean
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

time_to_purchase AS (
    SELECT
        f.user_id,
        DATEDIFF(HOUR, f.first_session_time, p.first_purchase_time) AS hours_to_purchase
    FROM first_session f
    JOIN first_purchase p
        ON f.user_id = p.user_id
),

first_session_actions AS (
    SELECT
        e.user_id,
        COUNT(CASE WHEN e.event_name = 'view_item' THEN 1 END) AS views,
        COUNT(CASE WHEN e.event_name = 'add_to_cart' THEN 1 END) AS adds_to_cart
    FROM events_clean e
    JOIN first_session f
        ON e.user_id = f.user_id
       AND e.event_time >= f.first_session_time
       AND e.event_time < DATEADD(HOUR, 24, f.first_session_time)
    GROUP BY e.user_id
),

combined AS (
    SELECT
        t.user_id,
        t.hours_to_purchase,
        a.views,
        a.adds_to_cart,
        CASE
            WHEN a.views >= 3 AND a.adds_to_cart >= 1 THEN 'High Intent'
            WHEN a.views >= 1 AND a.adds_to_cart = 0 THEN 'Browsing'
            ELSE 'Low Activity'
        END AS user_segment
    FROM time_to_purchase t
    JOIN first_session_actions a
        ON t.user_id = a.user_id
)

SELECT
    user_segment,
    COUNT(*) AS users,
    ROUND(AVG(CAST(hours_to_purchase AS FLOAT)), 2) AS avg_hours_to_purchase,
    MIN(hours_to_purchase) AS min_hours,
    MAX(hours_to_purchase) AS max_hours
FROM combined
GROUP BY user_segment
ORDER BY avg_hours_to_purchase;

--3. Calculate Customer Lifetime Value (CLV)
-- CLV = total revenue a user generated
WITH user_revenue AS (
    SELECT
        user_id,
        COUNT(DISTINCT session_id) AS total_orders,
        ROUND(SUM(COALESCE(revenue, 0)), 2) AS total_revenue
    FROM events_clean
    WHERE event_name = 'purchase'
    GROUP BY user_id
)

SELECT
    COUNT(*) AS total_customers,
    ROUND(AVG(total_orders * 1.0), 2) AS avg_orders_per_customer,
    ROUND(AVG(total_revenue), 2) AS avg_clv,
    MIN(total_revenue) AS min_clv,
    MAX(total_revenue) AS max_clv
FROM user_revenue;

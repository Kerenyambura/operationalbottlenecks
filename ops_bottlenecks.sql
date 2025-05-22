-- 1. **Which ticket categories are driving the highest SLA breach rates?** (What types of issues are taking too long to resolve?) SLA is 5 days
SELECT 
    category,
    COUNT(*) AS total_tickets,
    SUM(CASE 
            WHEN resolved_at IS NOT NULL 
                 AND resolved_at > created_at + INTERVAL 5 DAY 
            THEN 1 
            ELSE 0 
        END) AS sla_breaches,
    ROUND(
        100.0 * SUM(CASE 
                        WHEN resolved_at IS NOT NULL 
                             AND resolved_at > created_at + INTERVAL 5 DAY 
                        THEN 1 
                        ELSE 0 
                    END) / COUNT(*), 
        2
    ) AS breach_rate_percent
FROM tickets
WHERE status = 'Closed'  -- Only count resolved tickets
GROUP BY category
ORDER BY breach_rate_percent DESC;

-- 2. **How does resolution time vary across teams, regions, and issue categories?** (Where are the delays, and who’s handling issues efficiently?)
SELECT 
	a.team, 
    a.region, 
    t.category,
    ROUND(AVG(TIMESTAMPDIFF(HOUR, t.created_at, t.resolved_at)), 2) AS avg_resolution_hours,
    COUNT(*) AS ticket_count
FROM agents a
JOIN tickets t ON t.agent_id = a.agent_id
WHERE t. status = 'Closed' AND t.resolved_at IS NOT NULL
GROUP BY a.team, a.region, t.category
ORDER BY avg_resolution_hours DESC;


-- 3. **Which agents consistently close the most tickets—and who’s lagging behind?** (Who are the top performers, and who may need support?)
SELECT 
	a.name,
    count(*) as tickets_closed
FROM agents a
JOIN tickets t ON t.agent_id = a.agent_id
WHERE t. status = 'Closed'
group by a.name
order by tickets_closed;

-- 4. **What percentage of tickets are unresolved or open beyond SLA thresholds?** (How big is our backlog risk?)
SELECT 
    COUNT(*) AS total_open_tickets,
    SUM(CASE 
            WHEN created_at < NOW() - INTERVAL 14 DAY THEN 1
            ELSE 0 
        END) AS overdue_tickets,
    ROUND(
        100.0 * SUM(CASE 
                        WHEN created_at < NOW() - INTERVAL 14 DAY THEN 1
                        ELSE 0 
                   END) / COUNT(*), 
        2
    ) AS overdue_percent
FROM tickets
WHERE status IN ('Open', 'In Progress');

-- 5. **How many tickets are bouncing between multiple agents before being resolved?** (Are we losing time due to poor handoffs or ownership?)

SELECT 
    tu.ticket_id,
    COUNT(DISTINCT tu.updated_by) AS distinct_agents
FROM tickets t
JOIN ticket_updates tu ON t.ticket_id = tu.ticket_id
WHERE t.status = 'Closed'
GROUP BY tu.ticket_id
HAVING COUNT(DISTINCT tu.updated_by) > 1;

-- 6.  **Which tickets have the highest number of status changes?
SELECT 
    t.category,
    COUNT(tu.status_change) AS status_change_count
FROM tickets t
JOIN ticket_updates tu ON t.ticket_id = tu.ticket_id
WHERE t.status = 'Closed'
GROUP BY  t.category
ORDER BY status_change_count DESC;

-- 7. **What is the average time to first response, and how consistent is it across agents?** (Early response is critical—where are we falling short?)

WITH first_responses AS (
	    SELECT 
        t.ticket_id,
        t.agent_id,
        MIN(tu.timestamp) AS first_response_time,
        t.created_at
		FROM tickets t
		JOIN ticket_updates tu ON t.ticket_id = tu.ticket_id
		GROUP BY t.ticket_id, t.agent_id, t.created_at
)
SELECT 
    a.agent_id,
    a.name,
    a.team,
    a.region,
    ROUND(AVG(TIMESTAMPDIFF(MINUTE, fr.created_at, fr.first_response_time)), 2) AS avg_first_response_minutes,
	COUNT(*) AS tickets_handled
FROM first_responses fr
JOIN agents a ON fr.agent_id = a.agent_id
GROUP BY a.agent_id, a.name, a.team, a.region
ORDER BY avg_first_response_minutes DESC;

-- 8. **How has support ticket volume trended weekly/monthly over the last year?** (Is the workload increasing, and do we need to scale?)

SELECT 
	DATE_FORMAT(created_at, '%Y-%m') AS month,
	count(*) AS tickets_opened
FROM tickets
GROUP BY month
order by month;

-- 9. **Which regions or subscription plans are generating the most support tickets?** (Are certain customer segments more resource-intensive?)

SELECT c.region, c.subscription_plan, count(t.ticket_id) as total_tickets
FROM customers c
JOIN tickets t ON c.customer_id = t.customer_id
GROUP BY c.region, c.subscription_plan
ORDER BY total_tickets;

-- 10.How many customers have submitted more than 3 tickets overall?
SELECT 
    c.customer_id,
    c.name,
    COUNT(t.ticket_id) AS ticket_count,
    c.region,
    c.subscription_plan
FROM tickets t
JOIN customers c ON t.customer_id = c.customer_id
GROUP BY c.customer_id, c.name, c.region, c.subscription_plan
HAVING COUNT(t.ticket_id) > 3
ORDER BY ticket_count DESC;

-- 11.**What portion of ticket volume is driven by repeat customers or re-opened tickets?** (Is poor resolution quality increasing load?)
WITH customer_ticket_counts AS (
    SELECT 
        customer_id,
        COUNT(ticket_id) AS ticket_count
    FROM tickets
    GROUP BY customer_id
),
repeat_customers AS (
    SELECT customer_id
    FROM customer_ticket_counts
    WHERE ticket_count > 1
)
SELECT 
    (SELECT COUNT(*) FROM tickets WHERE customer_id IN (SELECT customer_id FROM repeat_customers)) AS repeat_customer_tickets,
    COUNT(*) AS total_tickets,
    ROUND(
        100.0 * (SELECT COUNT(*) FROM tickets WHERE customer_id IN (SELECT customer_id FROM repeat_customers)) / COUNT(*),
        2
    ) AS percent_repeat_volume
FROM tickets;

-- 12  **What percentage of tickets are still unresolved/open after 14 days?** (Measures backlog and aging tickets)


SELECT 
    COUNT(*) AS total_open_tickets,
    SUM(CASE 
            WHEN created_at < NOW() - INTERVAL 14 DAY THEN 1 
            ELSE 0 
        END) AS aged_open_tickets,
    ROUND(
        100.0 * SUM(CASE 
                        WHEN created_at < NOW() - INTERVAL 14 DAY THEN 1 
                        ELSE 0 
                   END) / COUNT(*), 
        2
    ) AS percent_aged_open_tickets
FROM tickets
WHERE status IN ('Open', 'In Progress');


-- 13 5. **What’s the average time between ticket creation and first update?** (Used as a proxy for initial response time)

WITH first_updates AS (
    SELECT 
        t.ticket_id,
        t.created_at,
        MIN(tu.timestamp) AS first_update_time
    FROM tickets t
    JOIN ticket_updates tu ON t.ticket_id = tu.ticket_id
    GROUP BY t.ticket_id, t.created_at
)
SELECT 
    ROUND(AVG(TIMESTAMPDIFF(MINUTE, created_at, first_update_time)), 2) AS avg_time_to_first_update_minutes,
    COUNT(*) AS total_tickets_analyzed
FROM first_updates;

-- bonus question : If we had to reduce workload by 20%, which categories or regions should we automate or outsource?
SELECT 
    t.category,
    c.region,
    COUNT(*) AS ticket_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM tickets), 2) AS percent_of_total
FROM tickets t
JOIN customers c ON t.customer_id = c.customer_id
GROUP BY t.category, c.region
ORDER BY ticket_count DESC;

-- bonus : What if we restructured the teams based on regional performance—would efficiency improve?
SELECT 
    a.agent_id,
    a.name,
    a.team,
    a.region AS agent_region,
    c.region AS customer_region,
    COUNT(*) AS tickets_handled,
    ROUND(AVG(TIMESTAMPDIFF(HOUR, t.created_at, t.resolved_at)), 2) AS avg_resolution_hours
FROM tickets t
JOIN agents a ON t.agent_id = a.agent_id
JOIN customers c ON t.customer_id = c.customer_id
WHERE t.status = 'Closed'
GROUP BY a.agent_id, a.name, a.team, a.region, c.region
ORDER BY customer_region, avg_resolution_hours;



# 📊 Support Operations Audit – SQL Query Journal

This page documents the full SQL audit performed on a fictional support ticket system. Each query was designed to answer a specific operational question and uncover bottlenecks, inefficiencies, or opportunities for support optimization.

---

## 🔎 1. Which ticket categories are driving the highest SLA breach rates?

```sql
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
WHERE status = 'Closed'
GROUP BY category
ORDER BY breach_rate_percent DESC;
```

**Insight:** Identifies which issue categories (e.g., Billing, Account Access) are consistently breaching SLA and contributing to customer dissatisfaction.

---

## 🔍 2. How does resolution time vary across teams, regions, and issue categories?

```sql
SELECT 
    a.team, 
    a.region, 
    t.category,
    ROUND(AVG(TIMESTAMPDIFF(HOUR, t.created_at, t.resolved_at)), 2) AS avg_resolution_hours,
    COUNT(*) AS ticket_count
FROM agents a
JOIN tickets t ON t.agent_id = a.agent_id
WHERE t.status = 'Closed' AND t.resolved_at IS NOT NULL
GROUP BY a.team, a.region, t.category
ORDER BY avg_resolution_hours DESC;
```

**Insight:** Surfaces delays by region, team, and issue type to target training or workflow improvements.

---

## 📈 3. Which agents consistently close the most tickets?

```sql
SELECT 
    a.name,
    COUNT(*) AS tickets_closed
FROM agents a
JOIN tickets t ON t.agent_id = a.agent_id
WHERE t.status = 'Closed'
GROUP BY a.name
ORDER BY tickets_closed DESC;
```

**Insight:** Identifies top performers and those who may need support or redistribution of workload.

---

## 📦 4. What percentage of tickets are unresolved beyond SLA thresholds?

```sql
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
```

**Insight:** Aged tickets beyond 14 days are red flags for backlogs and SLA non-compliance.

---


---

## 🔄 5. How many tickets are bouncing between multiple agents?

```sql
SELECT 
    tu.ticket_id,
    COUNT(DISTINCT tu.updated_by) AS distinct_agents
FROM tickets t
JOIN ticket_updates tu ON t.ticket_id = tu.ticket_id
WHERE t.status = 'Closed'
GROUP BY tu.ticket_id
HAVING COUNT(DISTINCT tu.updated_by) > 1;
```

**Insight:** Helps flag poor ownership or collaboration breakdowns that waste time and slow resolution.

---

## 🔁 6. Which tickets have the highest number of status changes?

```sql
SELECT 
    t.category,
    COUNT(tu.status_change) AS status_change_count
FROM tickets t
JOIN ticket_updates tu ON t.ticket_id = tu.ticket_id
WHERE t.status = 'Closed'
GROUP BY t.category
ORDER BY status_change_count DESC;
```

**Insight:** Highlights issue types that are hard to resolve or involve too much internal churn.

---

## ⏱️ 7. What is the average time to first response, and how consistent is it across agents?

```sql
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
```

**Insight:** Early response is critical. This query reveals inconsistencies that can be fixed with training or SOP changes.

---

## 📅 8. How has support ticket volume trended monthly?

```sql
SELECT 
    DATE_FORMAT(created_at, '%Y-%m') AS month,
    COUNT(*) AS tickets_opened
FROM tickets
GROUP BY month
ORDER BY month;
```

**Insight:** Helps leadership visualize workload trends and plan resourcing.

---

## 🌍 9. Which regions or subscription plans are generating the most tickets?

```sql
SELECT 
    c.region, 
    c.subscription_plan, 
    COUNT(t.ticket_id) AS total_tickets
FROM customers c
JOIN tickets t ON c.customer_id = t.customer_id
GROUP BY c.region, c.subscription_plan
ORDER BY total_tickets DESC;
```

**Insight:** Certain regions or customer tiers may require dedicated resources or self-service tools.

---

## 👥 10. How many customers have submitted more than 3 tickets?

```sql
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
```

**Insight:** Identifies high-frequency users—useful for targeted feedback or account reviews.

---

## 🔁 11. What portion of tickets are from repeat customers?

```sql
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
```

**Insight:** Repeat volume can signal poor resolution quality or deeper service issues.

---

## 🧓 12. What percentage of open tickets are older than 14 days?

```sql
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
```

**Insight:** Aged tickets = neglected issues = churn risk.

---

## 🕒 13. What’s the average time between ticket creation and first update?

```sql
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
```

**Insight:** Proxy for first response time. Can help define support KPIs.

---

## 🎯 Bonus: Where should we automate to reduce workload by 20%?

```sql
SELECT 
    t.category,
    c.region,
    COUNT(*) AS ticket_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM tickets), 2) AS percent_of_total
FROM tickets t
JOIN customers c ON t.customer_id = c.customer_id
GROUP BY t.category, c.region
ORDER BY ticket_count DESC;
```

**Insight:** Target high-volume regions/categories for automation or tiered support.

---

## ⚙️ Bonus: What if we restructured teams based on regional performance?

```sql
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
```

**Insight:** Cross-region misalignment increases resolution time. Better team matching may improve efficiency.

USE mini_upwork;

-- Q1. Top freelancer
SELECT freelancer_id, full_name, avg_rating, review_count, total_earned
FROM vw_top_freelancers
ORDER BY avg_rating DESC, review_count DESC, total_earned DESC
LIMIT 20;

-- Q2. Số proposal chờ theo job đang mở
SELECT j.job_id, j.title, COUNT(p.proposal_id) AS pending_proposals
FROM jobs j
LEFT JOIN proposals p ON p.job_id = j.job_id AND p.status = 'PENDING'
WHERE j.status = 'OPEN'
GROUP BY j.job_id, j.title
ORDER BY pending_proposals DESC, j.job_id
LIMIT 20;

-- Q3. Xếp hạng bid trong từng job
SELECT job_id, proposal_id, freelancer_id, bid_amount,
       RANK() OVER (PARTITION BY job_id ORDER BY bid_amount, estimated_days) AS bid_rank
FROM proposals
WHERE status = 'PENDING' AND job_id <= 1000
LIMIT 20;

-- Q4. Doanh thu và phí sàn theo tháng
SELECT DATE_FORMAT(created_at, '%Y-%m') AS month_key,
       SUM(gross_amount) AS gross, SUM(platform_fee) AS fees, SUM(net_amount) AS freelancer_net
FROM transactions
WHERE tx_type = 'MILESTONE_RELEASE' AND status = 'COMPLETED'
GROUP BY month_key
ORDER BY month_key DESC
LIMIT 20;

-- Q5. Milestone quá hạn
SELECT c.contract_id, j.title, m.milestone_id, m.due_date, m.status, m.amount
FROM milestones m
JOIN contracts c ON c.contract_id = m.contract_id
JOIN jobs j      ON j.job_id = c.job_id
WHERE m.due_date < CURRENT_DATE AND m.status <> 'RELEASED'
ORDER BY m.due_date
LIMIT 20;

-- Q6. Bid cao hơn mức trung bình của job
SELECT p.job_id, p.proposal_id, p.freelancer_id, p.bid_amount
FROM proposals p
WHERE p.job_id <= 1000
  AND p.bid_amount > (SELECT AVG(p2.bid_amount) FROM proposals p2
                      WHERE p2.job_id = p.job_id)
ORDER BY p.job_id, p.bid_amount DESC
LIMIT 20;

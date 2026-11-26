-- Nạp dữ liệu hiệu năng vào bản sao schema mini_upwork_perf:
--   sed "s/mini_upwork/mini_upwork_perf/g" mini_upwork.sql | mysql -u root -p
--   mysql -u root -p < perf_seed.sql      (50k jobs, 100k proposals, 10k contracts, 30k milestones, 20k reviews, 20k transactions)
--   python perf_run.py                     (đo p50/p95 có index vs quét toàn bảng)
USE mini_upwork_perf;

-- Bản sao chỉ dùng đo index: bỏ toàn bộ trigger để nạp hàng loạt (không đo chi phí trigger).
DROP TRIGGER trg_after_contract_insert;
DROP TRIGGER trg_after_contract_update;
DROP TRIGGER trg_after_milestone_update;
DROP TRIGGER trg_after_review_delete;
DROP TRIGGER trg_after_review_insert;
DROP TRIGGER trg_after_review_update;
DROP TRIGGER trg_after_transaction_insert;
DROP TRIGGER trg_before_client_insert;
DROP TRIGGER trg_before_client_update;
DROP TRIGGER trg_before_contract_insert;
DROP TRIGGER trg_before_contract_update;
DROP TRIGGER trg_before_freelancer_insert;
DROP TRIGGER trg_before_freelancer_update;
DROP TRIGGER trg_before_job_insert;
DROP TRIGGER trg_before_job_update;
DROP TRIGGER trg_before_ledger_delete;
DROP TRIGGER trg_before_ledger_update;
DROP TRIGGER trg_before_milestone_insert;
DROP TRIGGER trg_before_milestone_update;
DROP TRIGGER trg_before_proposal_insert;
DROP TRIGGER trg_before_proposal_update;
DROP TRIGGER trg_before_review_insert;
DROP TRIGGER trg_before_review_update;
DROP TRIGGER trg_before_transaction_delete;
DROP TRIGGER trg_before_transaction_insert;
DROP TRIGGER trg_before_transaction_update;
DROP TRIGGER trg_before_user_delete;
DROP TRIGGER trg_before_user_role_update;


SET SESSION cte_max_recursion_depth = 200000;
CREATE TABLE seq (n INT PRIMARY KEY);
INSERT INTO seq WITH RECURSIVE r AS (SELECT 1 AS n UNION ALL SELECT n + 1 FROM r WHERE n < 100000) SELECT n FROM r;

INSERT INTO users (email, password_hash, full_name, role)
SELECT CONCAT('pc', n, '@x.vn'), 'h', CONCAT('PC', n), 'CLIENT' FROM seq WHERE n <= 100;
INSERT INTO users (email, password_hash, full_name, role)
SELECT CONCAT('pf', n, '@x.vn'), 'h', CONCAT('PF', n), 'FREELANCER' FROM seq WHERE n <= 200;
INSERT INTO clients (client_id) SELECT user_id FROM users WHERE email LIKE 'pc%@x.vn';
INSERT INTO freelancers (freelancer_id, headline, hourly_rate)
SELECT user_id, 'h', 20 FROM users WHERE email LIKE 'pf%@x.vn';

-- Tra ID that (auto-increment co the nhay so khi INSERT ... SELECT)
CREATE TABLE cl (rk INT PRIMARY KEY, id INT);
CREATE TABLE fr (rk INT PRIMARY KEY, id INT);
INSERT INTO cl SELECT ROW_NUMBER() OVER (ORDER BY client_id) - 1, client_id FROM clients WHERE client_id > 3;
INSERT INTO fr SELECT ROW_NUMBER() OVER (ORDER BY freelancer_id) - 1, freelancer_id FROM freelancers WHERE freelancer_id > 5;
CREATE TABLE ur (rk INT PRIMARY KEY, id INT);
INSERT INTO ur SELECT rk, id FROM cl UNION ALL SELECT 100 + rk, id FROM fr;

INSERT INTO jobs (client_id, title, description, budget_min, budget_max, status, created_at)
SELECT cl.id, CONCAT('Job ', n), 'd', 100, 500,
       ELT(1 + MOD(n, 4), 'OPEN', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'),
       TIMESTAMP('2026-01-01') + INTERVAL n MINUTE
FROM seq JOIN cl ON cl.rk = MOD(seq.n, 100) WHERE n <= 50000;

INSERT INTO proposals (job_id, freelancer_id, bid_amount, estimated_days, cover_letter, status)
SELECT 1 + n, fr.id, 100 + MOD(n, 400), 5, 'c', IF(n <= 10000, 'ACCEPTED', 'PENDING')
FROM seq JOIN fr ON fr.rk = MOD(seq.n, 200) WHERE n <= 50000
UNION ALL
SELECT 1 + n, fr.id, 120 + MOD(n, 300), 7, 'c', 'PENDING'
FROM seq JOIN fr ON fr.rk = MOD(seq.n + 1, 200) WHERE n <= 50000;

INSERT INTO contracts (job_id, proposal_id, client_id, freelancer_id, total_amount, start_date, status)
SELECT p.job_id, p.proposal_id, j.client_id, p.freelancer_id, 300, '2026-02-01', 'COMPLETED'
FROM proposals p JOIN jobs j ON j.job_id = p.job_id
WHERE p.status = 'ACCEPTED' AND p.job_id BETWEEN 2 AND 10001;

INSERT INTO milestones (contract_id, sequence_no, title, amount, due_date)
SELECT c.contract_id, s.n, 'm', 100, '2026-03-01'
FROM contracts c JOIN seq s ON s.n <= 3 WHERE c.contract_id > 1;

INSERT INTO reviews (contract_id, reviewer_id, reviewee_id, rating)
SELECT contract_id, client_id, freelancer_id, 1 + MOD(contract_id, 5) FROM contracts WHERE contract_id > 1
UNION ALL
SELECT contract_id, freelancer_id, client_id, 1 + MOD(contract_id, 5) FROM contracts WHERE contract_id > 1;

INSERT INTO transactions (payee_id, gross_amount, platform_fee, net_amount, tx_type, status, external_ref, created_at)
SELECT ur.id, 10, 0, 10, 'DEPOSIT', 'COMPLETED', CONCAT('P-', n),
       TIMESTAMP('2026-01-01') + INTERVAL n MINUTE
FROM seq JOIN ur ON ur.rk = MOD(seq.n, 300) WHERE n <= 20000;

ANALYZE TABLE jobs, proposals, contracts, milestones, reviews, transactions;
SELECT 'jobs' t, COUNT(*) FROM jobs UNION ALL SELECT 'proposals', COUNT(*) FROM proposals
UNION ALL SELECT 'contracts', COUNT(*) FROM contracts UNION ALL SELECT 'milestones', COUNT(*) FROM milestones
UNION ALL SELECT 'reviews', COUNT(*) FROM reviews UNION ALL SELECT 'transactions', COUNT(*) FROM transactions;

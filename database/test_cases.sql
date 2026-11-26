-- ============================================================================
-- TEST CASES - MINI-UPWORK (Muc 5.1)
-- Chay SAU khi nap moi mini_upwork.sql (du lieu seed nguyen ban, chua chay rbac_test.sh).
-- Cach chay:  mysql -u root -p < test_cases.sql
-- Moi test am (TC-xx) phai bi tu choi voi dung ten constraint/thong bao.
-- Toan bo du lieu test nam trong 1 transaction va duoc ROLLBACK cuoi script.
-- ============================================================================
USE mini_upwork;

DROP TEMPORARY TABLE IF EXISTS t_results;
CREATE TEMPORARY TABLE t_results (
    seq         INT AUTO_INCREMENT PRIMARY KEY,
    test_id     VARCHAR(10)  NOT NULL,
    description VARCHAR(120) NOT NULL,
    expected    VARCHAR(80)  NOT NULL,
    actual      VARCHAR(200) NOT NULL,
    result      VARCHAR(4)   NOT NULL
) ENGINE=MEMORY;   -- MEMORY khong bi ROLLBACK nen ket qua duoc giu lai

DROP PROCEDURE IF EXISTS sp_t_fail;
DROP PROCEDURE IF EXISTS sp_t_assert;
DELIMITER //

-- Chay 1 cau lenh; PASS neu bi loi va thong bao loi chua p_expect.
CREATE PROCEDURE sp_t_fail(IN p_id VARCHAR(10), IN p_desc VARCHAR(120),
                           IN p_sql TEXT, IN p_expect VARCHAR(80))
BEGIN
    DECLARE v_msg TEXT DEFAULT NULL;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT; END;
    SET @t_sql = p_sql;
    PREPARE t_stmt FROM @t_sql;
    EXECUTE t_stmt;
    DEALLOCATE PREPARE t_stmt;
    INSERT INTO t_results (test_id, description, expected, actual, result)
    VALUES (p_id, p_desc, p_expect, LEFT(COALESCE(v_msg, '(khong loi - du lieu xau lot qua)'), 200),
            IF(v_msg LIKE CONCAT('%', p_expect, '%'), 'PASS', 'FAIL'));
END //

-- Tinh 1 gia tri vo huong; PASS neu bang p_expected.
CREATE PROCEDURE sp_t_assert(IN p_id VARCHAR(10), IN p_desc VARCHAR(120),
                             IN p_query TEXT, IN p_expected VARCHAR(80))
BEGIN
    SET @t_val = NULL;
    SET @t_sql = CONCAT('SELECT CAST((', p_query, ') AS CHAR) INTO @t_val');
    PREPARE t_stmt FROM @t_sql;
    EXECUTE t_stmt;
    DEALLOCATE PREPARE t_stmt;
    INSERT INTO t_results (test_id, description, expected, actual, result)
    VALUES (p_id, p_desc, p_expected, COALESCE(@t_val, 'NULL'),
            IF(@t_val = p_expected, 'PASS', 'FAIL'));
END //
DELIMITER ;

-- ---------------------------------------------------------------------------
-- SETUP: job 2 (client 3) + 2 proposal (ACCEPTED/PENDING) + contract 2 + 3 milestone; job 3 + proposal ACCEPTED
-- ---------------------------------------------------------------------------
START TRANSACTION;

INSERT INTO jobs (client_id, title, description, budget_min, budget_max)
VALUES (3, 'Test job', 'Test', 100.00, 500.00);
SET @j2 = LAST_INSERT_ID();
INSERT INTO proposals (job_id, freelancer_id, bid_amount, estimated_days, cover_letter, status)
VALUES (@j2, 5, 300.00, 7, 'cl', 'ACCEPTED');
SET @p_acc = LAST_INSERT_ID();
INSERT INTO proposals (job_id, freelancer_id, bid_amount, estimated_days, cover_letter, status)
VALUES (@j2, 4, 350.00, 5, 'cl', 'PENDING');
SET @p_pen = LAST_INSERT_ID();
INSERT INTO contracts (job_id, proposal_id, client_id, freelancer_id, total_amount, start_date)
VALUES (@j2, @p_acc, 3, 5, 9400.00, '2026-12-01');   -- 9400 >= 100 + 200 + 9000 (trigger: tong milestone <= total)
SET @c2 = LAST_INSERT_ID();
INSERT INTO milestones (contract_id, sequence_no, title, amount, due_date)
VALUES (@c2, 1, 'M1', 100.00, '2026-12-10');
SET @m1 = LAST_INSERT_ID();
INSERT INTO milestones (contract_id, sequence_no, title, amount, due_date)
VALUES (@c2, 2, 'M2', 200.00, '2026-12-20');
INSERT INTO milestones (contract_id, sequence_no, title, amount, due_date)
VALUES (@c2, 3, 'M3 vuot so du', 9000.00, '2026-12-30');
SET @m3 = LAST_INSERT_ID();
-- job 3 (client 3) co proposal ACCEPTED nhung chua co contract: dung cho TC-16
INSERT INTO jobs (client_id, title, description, budget_min, budget_max)
VALUES (3, 'Test job 3', 'Test', 100.00, 500.00);
SET @j3 = LAST_INSERT_ID();
INSERT INTO proposals (job_id, freelancer_id, bid_amount, estimated_days, cover_letter, status)
VALUES (@j3, 4, 200.00, 5, 'cl', 'ACCEPTED');
SET @p3 = LAST_INSERT_ID();

-- ---------------------------------------------------------------------------
-- A. DU LIEU XAU PHAI BI TU CHOI (UNIQUE / CHECK / FK)
-- ---------------------------------------------------------------------------
CALL sp_t_fail('TC-01', 'Email USERS trung',
  'INSERT INTO users (email,password_hash,full_name,role) VALUES ("hr@techcorp.vn","x","Dup","CLIENT")',
  'uk_users_email');
CALL sp_t_fail('TC-02', 'wallet_balance am',
  'INSERT INTO users (email,password_hash,full_name,role,wallet_balance) VALUES ("neg@x.vn","x","Neg","CLIENT",-1)',
  'ck_users_wallet_non_negative');
CALL sp_t_fail('TC-03', 'budget_max < budget_min',
  'INSERT INTO jobs (client_id,title,description,budget_min,budget_max) VALUES (2,"t","d",500,100)',
  'ck_jobs_budget_range');
CALL sp_t_fail('TC-04', 'Proposal trung (job, freelancer)',
  'INSERT INTO proposals (job_id,freelancer_id,bid_amount,estimated_days,cover_letter) VALUES (@j3,4,10,1,"x")',
  'uk_proposals_job_freelancer');
CALL sp_t_fail('TC-05', 'bid_amount = 0',
  'INSERT INTO proposals (job_id,freelancer_id,bid_amount,estimated_days,cover_letter) VALUES (@j3,5,0,1,"x")',
  'ck_proposals_bid');
CALL sp_t_fail('TC-06', 'Phi san 60% (ngoai 0-50%)',
  'INSERT INTO contracts (job_id,proposal_id,client_id,freelancer_id,total_amount,platform_fee_rate,start_date) VALUES (@j3,@p3,3,4,10,0.60,"2026-12-01")',
  'ck_contracts_fee_rate');
CALL sp_t_fail('TC-07', 'Contract end_date < start_date',
  'INSERT INTO contracts (job_id,proposal_id,client_id,freelancer_id,total_amount,start_date,end_date) VALUES (@j3,@p3,3,4,10,"2026-12-10","2026-12-01")',
  'ck_contracts_dates');
CALL sp_t_fail('TC-08', 'Milestone trung sequence_no',
  'INSERT INTO milestones (contract_id,sequence_no,title,amount,due_date) VALUES (@c2,1,"dup",10,"2026-12-31")',
  'uk_milestones_contract_seq');
CALL sp_t_fail('TC-09', 'Milestone amount = 0',
  'INSERT INTO milestones (contract_id,sequence_no,title,amount,due_date) VALUES (@c2,9,"zero",0,"2026-12-31")',
  'ck_milestones_amount');
CALL sp_t_fail('TC-10', 'Transaction gross <> fee + net',
  'INSERT INTO transactions (payee_id,gross_amount,platform_fee,net_amount,tx_type,external_ref) VALUES (3,100,5,50,"DEPOSIT","BAD-SUM-1")',
  'ck_tx_accounting_balance');
CALL sp_t_fail('TC-11', 'DEPOSIT sai hinh dang (co payer_id)',
  'INSERT INTO transactions (payer_id,payee_id,gross_amount,net_amount,tx_type,external_ref) VALUES (2,3,100,100,"DEPOSIT","BAD-SHAPE-1")',
  'ck_tx_party_shape');
CALL sp_t_fail('TC-12', 'Rating = 6',
  'INSERT INTO reviews (contract_id,reviewer_id,reviewee_id,rating) VALUES (1,2,4,6)',
  'ck_reviews_rating');
CALL sp_t_fail('TC-13', 'Reviewer danh gia contract 2 lan',
  'INSERT INTO reviews (contract_id,reviewer_id,reviewee_id,rating) VALUES (1,2,4,4)',
  'uk_reviews_contract_reviewer');
CALL sp_t_fail('TC-14', 'Ky nang cho freelancer khong ton tai (FK)',
  'INSERT INTO freelancer_skills (freelancer_id,skill_id) VALUES (9999,1)',
  'fk_fskills_freelancer');
CALL sp_t_fail('TC-15', 'Xoa client dang co job (RESTRICT)',
  'DELETE FROM clients WHERE client_id = 2',
  'foreign key constraint fails');
CALL sp_t_fail('TC-16', 'Contract: client khong phai chu cua job (composite FK)',
  'INSERT INTO contracts (job_id,proposal_id,client_id,freelancer_id,total_amount,start_date) VALUES (@j3,@p3,2,4,10,"2026-12-01")',
  'fk_contracts_job_client');

-- ---------------------------------------------------------------------------
-- B. TRIGGER NGHIEP VU
-- ---------------------------------------------------------------------------
CALL sp_t_fail('TC-17', 'Contract dung proposal chua ACCEPTED',
  'INSERT INTO contracts (job_id,proposal_id,client_id,freelancer_id,total_amount,start_date) VALUES (@j2,@p_pen,3,4,10,"2026-12-01")',
  'ACCEPTED proposal');
CALL sp_t_fail('TC-18', 'Subtype freelancer gan cho user role CLIENT',
  'INSERT INTO freelancers (freelancer_id,headline,hourly_rate) VALUES (2,"x",10)',
  'Freelancer subtype must reference');
CALL sp_t_fail('TC-19', 'Doi role khi con ho so subtype',
  'UPDATE users SET role = "ADMIN" WHERE user_id = 4',
  'Cannot change role');
CALL sp_t_fail('TC-20', 'Milestone nhay trang thai PENDING -> RELEASED',
  'UPDATE milestones SET status = "RELEASED" WHERE milestone_id = @m1',
  'Invalid milestone status transition');
CALL sp_t_fail('TC-21', 'Hoan tat contract khi milestone chua release',
  'UPDATE contracts SET status = "COMPLETED" WHERE contract_id = @c2',
  'Completion requires all milestones released');
CALL sp_t_fail('TC-22', 'Contract COMPLETED quay lai ACTIVE',
  'UPDATE contracts SET status = "ACTIVE" WHERE contract_id = 1',
  'Invalid contract status transition');
CALL sp_t_fail('TC-23', 'Review boi user ngoai contract',
  'INSERT INTO reviews (contract_id,reviewer_id,reviewee_id,rating) VALUES (1,3,4,5)',
  'Reviews require a completed contract');
CALL sp_t_fail('TC-24', 'Review contract chua COMPLETED',
  'INSERT INTO reviews (contract_id,reviewer_id,reviewee_id,rating) VALUES (@c2,3,5,5)',
  'Reviews require a completed contract');

-- ---------------------------------------------------------------------------
-- C. VI / SO CAI / BAT BIEN
-- ---------------------------------------------------------------------------
CALL sp_t_fail('TC-30', 'Dang job boi user khong phai CLIENT',
  'INSERT INTO jobs (client_id,title,description,budget_min,budget_max) VALUES (4,"t","d",10,20)',
  'Only an active CLIENT can post a job');
CALL sp_t_fail('TC-31', 'Job OPEN nhay thang COMPLETED',
  'UPDATE jobs SET status = "COMPLETED" WHERE job_id = @j3',
  'Invalid job status transition');
CALL sp_t_fail('TC-32', 'Nop proposal vao job khong OPEN',
  'INSERT INTO proposals (job_id,freelancer_id,bid_amount,estimated_days,cover_letter) VALUES (1,5,10,1,"x")',
  'Proposals can only be submitted to OPEN jobs');
CALL sp_t_fail('TC-33', 'Tong milestone vuot total_amount cua contract',
  'INSERT INTO milestones (contract_id,sequence_no,title,amount,due_date) VALUES (@c2,4,"over",101,"2026-12-31")',
  'Total milestone amount cannot exceed');
CALL sp_t_fail('TC-34', 'Xoa user con so du vi',
  'DELETE FROM users WHERE user_id = 4',
  'remaining wallet balance');
CALL sp_t_fail('TC-25', 'Ky quy vuot so du vi client',
  'UPDATE milestones SET status = "FUNDED" WHERE milestone_id = @m3',
  'Insufficient client wallet balance');
CALL sp_t_assert('TC-25b', 'Milestone van PENDING sau khi ky quy that bai',
  'SELECT status FROM milestones WHERE milestone_id = @m3', 'PENDING');
CALL sp_t_fail('TC-26', 'Rut tien vuot so du',
  'CALL sp_post_confirmed_withdrawal(5, 9999.00, 0.00, "W-OVER-1")',
  'Insufficient wallet balance for withdrawal');
CALL sp_t_fail('TC-27', 'Dung lai external_ref cua giao dich nap',
  'CALL sp_post_confirmed_deposit(3, 10.00, 0.00, "SEED-DEP-CLIENT-2")',
  'uk_transactions_external_ref');
CALL sp_t_fail('TC-28', 'Sua giao dich da ghi so',
  'UPDATE transactions SET status = "FAILED" WHERE transaction_id = 1',
  'immutable');
CALL sp_t_fail('TC-29', 'Xoa dong but toan',
  'DELETE FROM ledger_entries WHERE entry_id = 1',
  'append-only');

-- ---------------------------------------------------------------------------
-- D. LUONG NGHIEP VU HOP LE (gia tri ky vong tinh tu seed)
-- ---------------------------------------------------------------------------
CALL sp_t_assert('TW-01', 'Vi client 2 sau khi tra 1200 (5000 - 1200)',
  'SELECT wallet_balance FROM users WHERE user_id = 2', '3800.00');
CALL sp_t_assert('TW-02', 'Vi freelancer 4 (100 + 1080 rong)',
  'SELECT wallet_balance FROM users WHERE user_id = 4', '1180.00');
CALL sp_t_assert('TW-03', 'total_earned cua freelancer 4',
  'SELECT total_earned FROM freelancers WHERE freelancer_id = 4', '1080.00');
CALL sp_t_assert('TW-04', 'total_spent cua client 2',
  'SELECT total_spent FROM clients WHERE client_id = 2', '1200.00');
CALL sp_t_assert('TW-05', 'Tong phi san thu duoc (ledger PLATFORM_FEE)',
  'SELECT SUM(amount) FROM ledger_entries WHERE account_type = "PLATFORM_FEE"', '120.00');

UPDATE milestones SET status = 'FUNDED' WHERE milestone_id = @m1;
CALL sp_t_assert('TW-06', 'Ky quy milestone 100: vi client 3 giam 2000 -> 1900',
  'SELECT wallet_balance FROM users WHERE user_id = 3', '1900.00');
CALL sp_refund_milestone(@m1);
CALL sp_t_assert('TW-07', 'Hoan tien milestone: vi client 3 tro lai 2000',
  'SELECT wallet_balance FROM users WHERE user_id = 3', '2000.00');

CALL sp_t_assert('TW-08', 'View doi soat vi: 0 dong lech',
  'SELECT COUNT(*) FROM vw_user_wallet_reconciliation WHERE difference <> 0', '0');
CALL sp_t_assert('TW-09', 'View can No/Co: 0 giao dich lech',
  'SELECT COUNT(*) FROM vw_transaction_trial_balance WHERE status = "COMPLETED" AND difference <> 0', '0');
CALL sp_t_assert('TW-10', 'View doi soat escrow: 0 milestone lech',
  'SELECT COUNT(*) FROM vw_milestone_escrow_reconciliation WHERE difference <> 0', '0');

UPDATE reviews SET rating = 3 WHERE review_id = 1;
CALL sp_t_assert('TW-11', 'Sua review 5 -> 3: avg_rating freelancer 4 = 3.00',
  'SELECT avg_rating FROM freelancers WHERE freelancer_id = 4', '3.00');
DELETE FROM reviews WHERE review_id = 1;
CALL sp_t_assert('TW-12', 'Xoa review: review_count freelancer 4 = 0',
  'SELECT review_count FROM freelancers WHERE freelancer_id = 4', '0');

CALL sp_t_assert('TW-13', 'View ISA: 0 user vi pham phan cap Disjoint/Total',
  'SELECT COUNT(*) FROM vw_user_isa_reconciliation WHERE isa_status <> "OK"', '0');

-- ---------------------------------------------------------------------------
-- KET QUA
-- ---------------------------------------------------------------------------
SELECT test_id, description, result, actual FROM t_results ORDER BY seq;
SELECT SUM(result = 'PASS') AS passed, SUM(result = 'FAIL') AS failed, COUNT(*) AS total FROM t_results;

ROLLBACK;                               -- huy toan bo du lieu test
DROP PROCEDURE sp_t_fail;
DROP PROCEDURE sp_t_assert;
DROP TEMPORARY TABLE t_results;

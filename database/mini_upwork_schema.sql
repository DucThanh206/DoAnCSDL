-- ============================================================================
-- HỆ CƠ SỞ DỮ LIỆU: FREELANCE MARKETPLACE ECOSYSTEM (MINI-UPWORK)
-- DBMS: MySQL 8.0.16+ (enforced CHECK) | Engine: InnoDB | Charset: utf8mb4
-- ============================================================================

DROP DATABASE IF EXISTS mini_upwork;
CREATE DATABASE mini_upwork
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE mini_upwork;

-- ============================================================================
-- 1. NHÓM BẢNG NGƯỜI DÙNG & KỸ NĂNG (EER SUPERTYPE)
-- ============================================================================

-- 1.1 Bảng cha (Supertype): USERS
CREATE TABLE users (
    user_id        INT AUTO_INCREMENT,
    email          VARCHAR(150) NOT NULL,
    password_hash  VARCHAR(255) NOT NULL,
    full_name      VARCHAR(100) NOT NULL,
    role           ENUM('CLIENT', 'FREELANCER', 'ADMIN') NOT NULL,
    wallet_balance DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    status         ENUM('ACTIVE', 'SUSPENDED', 'INACTIVE') NOT NULL DEFAULT 'ACTIVE',
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT pk_users PRIMARY KEY (user_id),
    CONSTRAINT uk_users_email UNIQUE (email),
    CONSTRAINT ck_users_email_not_empty CHECK (CHAR_LENGTH(TRIM(email)) > 0),
    CONSTRAINT ck_users_full_name_not_empty CHECK (CHAR_LENGTH(TRIM(full_name)) > 0),
    CONSTRAINT ck_users_wallet_non_negative CHECK (wallet_balance >= 0.00)
) ENGINE=InnoDB;

-- 1.2 Bảng con (Subtype Client): CLIENTS
CREATE TABLE clients (
    client_id    INT,
    company_name VARCHAR(150) NULL,
    industry     VARCHAR(100) NULL,
    total_spent  DECIMAL(14, 2) NOT NULL DEFAULT 0.00,
    avg_rating   DECIMAL(3, 2) NOT NULL DEFAULT 0.00,
    review_count INT NOT NULL DEFAULT 0,

    CONSTRAINT pk_clients PRIMARY KEY (client_id),
    CONSTRAINT fk_clients_users FOREIGN KEY (client_id)
        REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT ck_clients_company_not_empty CHECK (company_name IS NULL OR CHAR_LENGTH(TRIM(company_name)) > 0),
    CONSTRAINT ck_clients_total_spent CHECK (total_spent >= 0.00),
    CONSTRAINT ck_clients_avg_rating CHECK (avg_rating BETWEEN 0.00 AND 5.00),
    CONSTRAINT ck_clients_review_count CHECK (review_count >= 0)
) ENGINE=InnoDB;

-- 1.3 Bảng con (Subtype Freelancer): FREELANCERS
CREATE TABLE freelancers (
    freelancer_id INT,
    headline      VARCHAR(200) NOT NULL,
    hourly_rate   DECIMAL(10, 2) NOT NULL,
    bio           TEXT NULL,
    total_earned  DECIMAL(14, 2) NOT NULL DEFAULT 0.00,
    avg_rating    DECIMAL(3, 2) NOT NULL DEFAULT 0.00,
    review_count  INT NOT NULL DEFAULT 0,

    CONSTRAINT pk_freelancers PRIMARY KEY (freelancer_id),
    CONSTRAINT fk_freelancers_users FOREIGN KEY (freelancer_id)
        REFERENCES users(user_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT ck_freelancers_headline_not_empty CHECK (CHAR_LENGTH(TRIM(headline)) > 0),
    CONSTRAINT ck_freelancers_hourly_rate CHECK (hourly_rate > 0.00),
    CONSTRAINT ck_freelancers_total_earned CHECK (total_earned >= 0.00),
    CONSTRAINT ck_freelancers_avg_rating CHECK (avg_rating BETWEEN 0.00 AND 5.00),
    CONSTRAINT ck_freelancers_review_count CHECK (review_count >= 0)
) ENGINE=InnoDB;

-- 1.4 Danh mục kỹ năng: SKILLS
CREATE TABLE skills (
    skill_id   INT AUTO_INCREMENT,
    skill_name VARCHAR(80) NOT NULL,
    category   VARCHAR(80) NOT NULL,

    CONSTRAINT pk_skills PRIMARY KEY (skill_id),
    CONSTRAINT uk_skills_name UNIQUE (skill_name),
    CONSTRAINT ck_skills_name_not_empty CHECK (CHAR_LENGTH(TRIM(skill_name)) > 0),
    CONSTRAINT ck_skills_category_not_empty CHECK (CHAR_LENGTH(TRIM(category)) > 0)
) ENGINE=InnoDB;

-- 1.5 Bảng trung gian N-M (Quan hệ POSSESSES): FREELANCER_SKILLS
CREATE TABLE freelancer_skills (
    freelancer_id     INT NOT NULL,
    skill_id          INT NOT NULL,
    proficiency_level TINYINT NOT NULL DEFAULT 3,

    CONSTRAINT pk_freelancer_skills PRIMARY KEY (freelancer_id, skill_id),
    CONSTRAINT fk_fskills_freelancer FOREIGN KEY (freelancer_id)
        REFERENCES freelancers(freelancer_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_fskills_skill FOREIGN KEY (skill_id)
        REFERENCES skills(skill_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT ck_fskills_proficiency CHECK (proficiency_level BETWEEN 1 AND 5)
) ENGINE=InnoDB;

-- ============================================================================
-- 2. NHÓM BẢNG ĐĂNG VIỆC & ỨNG TUYỂN (QUAN HỆ POSTS, SUBMITS, RECEIVES_PROPOSAL)
-- ============================================================================

-- 2.1 Tin tuyển dụng: JOBS (Quan hệ POSTS 1:N, tham gia toàn phần ở JOBS — BR-10)
CREATE TABLE jobs (
    job_id      INT AUTO_INCREMENT,
    client_id   INT NOT NULL,
    title       VARCHAR(200) NOT NULL,
    description TEXT NOT NULL,
    budget_min  DECIMAL(12, 2) NOT NULL,
    budget_max  DECIMAL(12, 2) NOT NULL,
    status      ENUM('OPEN', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED') NOT NULL DEFAULT 'OPEN',
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_jobs PRIMARY KEY (job_id),
    CONSTRAINT uk_jobs_id_client UNIQUE (job_id, client_id),
    CONSTRAINT fk_jobs_clients FOREIGN KEY (client_id)
        REFERENCES clients(client_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_jobs_title_not_empty CHECK (CHAR_LENGTH(TRIM(title)) > 0),
    CONSTRAINT ck_jobs_description_not_empty CHECK (CHAR_LENGTH(TRIM(description)) > 0),
    CONSTRAINT ck_jobs_budget_min CHECK (budget_min > 0.00),
    CONSTRAINT ck_jobs_budget_range CHECK (budget_max >= budget_min)
) ENGINE=InnoDB;

-- 2.2 Hồ sơ ứng tuyển: PROPOSALS (Tối đa 1 đề xuất / Freelancer / Job — BR-12)
CREATE TABLE proposals (
    proposal_id    INT AUTO_INCREMENT,
    job_id         INT NOT NULL,
    freelancer_id  INT NOT NULL,
    bid_amount     DECIMAL(12, 2) NOT NULL,
    estimated_days INT NOT NULL,
    cover_letter   TEXT NOT NULL,
    status         ENUM('PENDING', 'ACCEPTED', 'REJECTED', 'WITHDRAWN') NOT NULL DEFAULT 'PENDING',
    submitted_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_proposals PRIMARY KEY (proposal_id),
    CONSTRAINT uk_proposals_job_freelancer UNIQUE (job_id, freelancer_id),
    CONSTRAINT uk_proposals_id_parties UNIQUE (proposal_id, job_id, freelancer_id),
    CONSTRAINT fk_proposals_jobs FOREIGN KEY (job_id)
        REFERENCES jobs(job_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_proposals_freelancers FOREIGN KEY (freelancer_id)
        REFERENCES freelancers(freelancer_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT ck_proposals_bid CHECK (bid_amount > 0.00),
    CONSTRAINT ck_proposals_days CHECK (estimated_days >= 1)
) ENGINE=InnoDB;

-- ============================================================================
-- 3. NHÓM BẢNG HỢP ĐỒNG & TIẾN ĐỘ GIAI ĐOẠN
-- ============================================================================

-- 3.1 Hợp đồng: CONTRACTS
CREATE TABLE contracts (
    contract_id       INT AUTO_INCREMENT,
    job_id            INT NOT NULL,
    proposal_id       INT NOT NULL,
    client_id         INT NOT NULL,
    freelancer_id     INT NOT NULL,
    total_amount      DECIMAL(12, 2) NOT NULL,
    platform_fee_rate DECIMAL(4, 2) NOT NULL DEFAULT 0.10,
    start_date        DATE NOT NULL,
    end_date          DATE NULL,
    status            ENUM('ACTIVE', 'COMPLETED', 'DISPUTED', 'CANCELLED') NOT NULL DEFAULT 'ACTIVE',
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_contracts PRIMARY KEY (contract_id),
    CONSTRAINT uk_contracts_job UNIQUE (job_id),
    CONSTRAINT uk_contracts_proposal UNIQUE (proposal_id),
    CONSTRAINT fk_contracts_job_client FOREIGN KEY (job_id, client_id)
        REFERENCES jobs(job_id, client_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_contracts_proposal_parties FOREIGN KEY (proposal_id, job_id, freelancer_id)
        REFERENCES proposals(proposal_id, job_id, freelancer_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_contracts_clients FOREIGN KEY (client_id)
        REFERENCES clients(client_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_contracts_freelancers FOREIGN KEY (freelancer_id)
        REFERENCES freelancers(freelancer_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT ck_contracts_total_amount CHECK (total_amount > 0.00),
    CONSTRAINT ck_contracts_fee_rate CHECK (platform_fee_rate BETWEEN 0.00 AND 0.50),
    CONSTRAINT ck_contracts_dates CHECK (end_date IS NULL OR end_date >= start_date)
) ENGINE=InnoDB;

-- 3.2 Các giai đoạn bàn giao: MILESTONES
CREATE TABLE milestones (
    milestone_id    INT AUTO_INCREMENT,
    contract_id     INT NOT NULL,
    sequence_no     INT NOT NULL,
    title           VARCHAR(200) NOT NULL,
    amount          DECIMAL(12, 2) NOT NULL,
    due_date        DATE NOT NULL,
    deliverable_url VARCHAR(500) NULL,
    status          ENUM('PENDING', 'FUNDED', 'SUBMITTED', 'APPROVED', 'RELEASED', 'REFUNDED') NOT NULL DEFAULT 'PENDING',
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT pk_milestones PRIMARY KEY (milestone_id),
    CONSTRAINT uk_milestones_contract_seq UNIQUE (contract_id, sequence_no),
    CONSTRAINT fk_milestones_contracts FOREIGN KEY (contract_id)
        REFERENCES contracts(contract_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT ck_milestones_seq CHECK (sequence_no >= 1),
    CONSTRAINT ck_milestones_amount CHECK (amount > 0.00)
) ENGINE=InnoDB;

-- ============================================================================
-- 4. NHÓM BẢNG SỔ CÁI TÀI CHÍNH ĐA BÊN & ĐÁNH GIÁ HAI CHIỀU
-- ============================================================================

-- 4.1 Sổ cái giao dịch: TRANSACTIONS
CREATE TABLE transactions (
    transaction_id INT AUTO_INCREMENT,
    milestone_id   INT NULL,
    payer_id       INT NULL,
    payee_id       INT NULL,
    gross_amount   DECIMAL(12, 2) NOT NULL,
    platform_fee   DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    net_amount     DECIMAL(12, 2) NOT NULL,
    tx_type        ENUM('DEPOSIT', 'ESCROW_HOLD', 'MILESTONE_RELEASE', 'REFUND', 'WITHDRAWAL') NOT NULL,
    status         ENUM('PENDING', 'COMPLETED', 'FAILED') NOT NULL DEFAULT 'COMPLETED',
    external_ref   VARCHAR(120) NULL,
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_transactions PRIMARY KEY (transaction_id),
    CONSTRAINT uk_transactions_milestone_type UNIQUE (milestone_id, tx_type),
    CONSTRAINT uk_transactions_external_ref UNIQUE (external_ref),
    CONSTRAINT fk_tx_milestones FOREIGN KEY (milestone_id)
        REFERENCES milestones(milestone_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_tx_payer FOREIGN KEY (payer_id)
        REFERENCES users(user_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_tx_payee FOREIGN KEY (payee_id)
        REFERENCES users(user_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT ck_tx_gross CHECK (gross_amount > 0.00),
    CONSTRAINT ck_tx_fee CHECK (platform_fee >= 0.00),
    CONSTRAINT ck_tx_net CHECK (net_amount >= 0.00),
    CONSTRAINT ck_tx_accounting_balance CHECK (ROUND(gross_amount, 2) = ROUND(platform_fee + net_amount, 2)),
    CONSTRAINT ck_tx_party_shape CHECK (
        (tx_type = 'DEPOSIT' AND milestone_id IS NULL AND payer_id IS NULL AND payee_id IS NOT NULL) OR
        (tx_type = 'ESCROW_HOLD' AND milestone_id IS NOT NULL AND payer_id IS NOT NULL AND payee_id IS NULL AND platform_fee = 0.00) OR
        (tx_type = 'MILESTONE_RELEASE' AND milestone_id IS NOT NULL AND payer_id IS NOT NULL AND payee_id IS NOT NULL) OR
        (tx_type = 'REFUND' AND milestone_id IS NOT NULL AND payer_id IS NULL AND payee_id IS NOT NULL AND platform_fee = 0.00) OR
        (tx_type = 'WITHDRAWAL' AND milestone_id IS NULL AND payer_id IS NOT NULL AND payee_id IS NULL)
    ),
    CONSTRAINT ck_tx_external_ref CHECK (
        (tx_type NOT IN ('DEPOSIT', 'WITHDRAWAL')) OR
        (external_ref IS NOT NULL AND CHAR_LENGTH(TRIM(external_ref)) > 0)
    )
) ENGINE=InnoDB;

-- 4.1.1 Sổ cái bút toán kép: mỗi giao dịch hoàn tất có tổng Nợ = tổng Có.
CREATE TABLE ledger_entries (
    entry_id       BIGINT AUTO_INCREMENT,
    transaction_id INT NOT NULL,
    account_type   ENUM('USER_WALLET', 'ESCROW', 'PLATFORM_FEE', 'EXTERNAL_CLEARING') NOT NULL,
    user_id        INT NULL,
    entry_side     ENUM('DEBIT', 'CREDIT') NOT NULL,
    amount         DECIMAL(12, 2) NOT NULL,
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_ledger_entries PRIMARY KEY (entry_id),
    CONSTRAINT fk_ledger_transaction FOREIGN KEY (transaction_id)
        REFERENCES transactions(transaction_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_ledger_user FOREIGN KEY (user_id)
        REFERENCES users(user_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT ck_ledger_amount CHECK (amount > 0.00),
    CONSTRAINT ck_ledger_account_owner CHECK (
        (account_type = 'USER_WALLET' AND user_id IS NOT NULL) OR
        (account_type <> 'USER_WALLET' AND user_id IS NULL)
    ),
    INDEX idx_ledger_transaction (transaction_id),
    INDEX idx_ledger_user (user_id, account_type)
) ENGINE=InnoDB;

-- 4.2 Đánh giá chất lượng: REVIEWS
CREATE TABLE reviews (
    review_id   INT AUTO_INCREMENT,
    contract_id INT NOT NULL,
    reviewer_id INT NOT NULL,
    reviewee_id INT NOT NULL,
    rating      TINYINT NOT NULL,
    comment     TEXT NULL,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_reviews PRIMARY KEY (review_id),
    CONSTRAINT uk_reviews_contract_reviewer UNIQUE (contract_id, reviewer_id),
    CONSTRAINT fk_reviews_contracts FOREIGN KEY (contract_id)
        REFERENCES contracts(contract_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_reviews_reviewer FOREIGN KEY (reviewer_id)
        REFERENCES users(user_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_reviews_reviewee FOREIGN KEY (reviewee_id)
        REFERENCES users(user_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT ck_reviews_rating CHECK (rating BETWEEN 1 AND 5),
    CONSTRAINT ck_reviews_no_self CHECK (reviewer_id <> reviewee_id)
) ENGINE=InnoDB;

-- ============================================================================
-- 5. INDEXES PHỤC VỤ TỐI ƯU HIỆU NĂNG TRUY VẤN (MỤC 4.1 & 4.2)
-- ============================================================================
CREATE INDEX idx_jobs_status_created ON jobs (status, created_at DESC);
CREATE INDEX idx_proposals_job_status ON proposals (job_id, status);
CREATE INDEX idx_milestones_contract_status ON milestones (contract_id, status);
CREATE INDEX idx_tx_payer_created ON transactions (payer_id, created_at DESC);
CREATE INDEX idx_tx_payee_created ON transactions (payee_id, created_at DESC);
CREATE INDEX idx_reviews_reviewee ON reviews (reviewee_id);

-- ============================================================================
-- 6. RÀNG BUỘC NGHIỆP VỤ, SỔ CÁI BÚT TOÁN KÉP & LUỒNG VÍ
-- ============================================================================
DELIMITER //

-- 6.1 Ràng buộc ISA Disjoint (d) + Total Participation (BR-01) & Bảo vệ xóa USER (BR-03)
CREATE TRIGGER trg_before_client_insert
BEFORE INSERT ON clients
FOR EACH ROW
BEGIN
    DECLARE v_role VARCHAR(20) DEFAULT NULL;
    SELECT role INTO v_role FROM users WHERE user_id = NEW.client_id;
    IF v_role IS NULL OR v_role <> 'CLIENT' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Client subtype must reference a CLIENT user.';
    END IF;
END //

CREATE TRIGGER trg_before_freelancer_insert
BEFORE INSERT ON freelancers
FOR EACH ROW
BEGIN
    DECLARE v_role VARCHAR(20) DEFAULT NULL;
    SELECT role INTO v_role FROM users WHERE user_id = NEW.freelancer_id;
    IF v_role IS NULL OR v_role <> 'FREELANCER' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Freelancer subtype must reference a FREELANCER user.';
    END IF;
END //

CREATE TRIGGER trg_before_client_update
BEFORE UPDATE ON clients
FOR EACH ROW
BEGIN
    DECLARE v_role VARCHAR(20) DEFAULT NULL;
    SELECT role INTO v_role FROM users WHERE user_id = NEW.client_id;
    IF v_role IS NULL OR v_role <> 'CLIENT' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Client subtype must reference a CLIENT user.';
    END IF;
END //

CREATE TRIGGER trg_before_freelancer_update
BEFORE UPDATE ON freelancers
FOR EACH ROW
BEGIN
    DECLARE v_role VARCHAR(20) DEFAULT NULL;
    SELECT role INTO v_role FROM users WHERE user_id = NEW.freelancer_id;
    IF v_role IS NULL OR v_role <> 'FREELANCER' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Freelancer subtype must reference a FREELANCER user.';
    END IF;
END //

CREATE TRIGGER trg_before_user_role_update
BEFORE UPDATE ON users
FOR EACH ROW
BEGIN
    IF NEW.role <> OLD.role AND
       ((NEW.role <> 'CLIENT' AND EXISTS (SELECT 1 FROM clients WHERE client_id = OLD.user_id)) OR
        (NEW.role <> 'FREELANCER' AND EXISTS (SELECT 1 FROM freelancers WHERE freelancer_id = OLD.user_id))) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot change role while an incompatible subtype profile exists.';
    END IF;
END //

CREATE TRIGGER trg_before_user_delete
BEFORE DELETE ON users
FOR EACH ROW
BEGIN
    IF OLD.wallet_balance > 0.00 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot delete a user with remaining wallet balance.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM contracts
         WHERE (client_id = OLD.user_id OR freelancer_id = OLD.user_id)
           AND status IN ('ACTIVE', 'DISPUTED')
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot delete a user with active or disputed contracts.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM transactions
         WHERE (payer_id = OLD.user_id OR payee_id = OLD.user_id)
           AND status = 'PENDING'
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot delete a user with pending transactions.';
    END IF;
END //

-- 6.2 Ràng buộc đăng việc (JOBS - POSTS) & nộp đề xuất (PROPOSALS - SUBMITS)
CREATE TRIGGER trg_before_job_insert
BEFORE INSERT ON jobs
FOR EACH ROW
BEGIN
    DECLARE v_user_status VARCHAR(20) DEFAULT NULL;
    DECLARE v_user_role VARCHAR(20) DEFAULT NULL;
    SELECT status, role INTO v_user_status, v_user_role
      FROM users
     WHERE user_id = NEW.client_id;
    IF v_user_role IS NULL OR v_user_role <> 'CLIENT' OR v_user_status <> 'ACTIVE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only an active CLIENT can post a job.';
    END IF;
END //

CREATE TRIGGER trg_before_job_update
BEFORE UPDATE ON jobs
FOR EACH ROW
BEGIN
    IF NEW.client_id <> OLD.client_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Job owner (client_id) is immutable.';
    END IF;
    IF NEW.status <> OLD.status AND NOT (
        (OLD.status = 'OPEN' AND NEW.status IN ('IN_PROGRESS', 'CANCELLED')) OR
        (OLD.status = 'IN_PROGRESS' AND NEW.status IN ('COMPLETED', 'CANCELLED'))
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid job status transition.';
    END IF;
END //

CREATE TRIGGER trg_before_proposal_insert
BEFORE INSERT ON proposals
FOR EACH ROW
BEGIN
    DECLARE v_job_status VARCHAR(20) DEFAULT NULL;
    DECLARE v_user_status VARCHAR(20) DEFAULT NULL;
    SELECT status INTO v_job_status FROM jobs WHERE job_id = NEW.job_id;
    IF v_job_status IS NULL OR v_job_status <> 'OPEN' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Proposals can only be submitted to OPEN jobs.';
    END IF;
    SELECT status INTO v_user_status FROM users WHERE user_id = NEW.freelancer_id;
    IF v_user_status IS NULL OR v_user_status <> 'ACTIVE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only an active FREELANCER can submit a proposal.';
    END IF;
END //

CREATE TRIGGER trg_before_proposal_update
BEFORE UPDATE ON proposals
FOR EACH ROW
BEGIN
    IF NEW.job_id <> OLD.job_id OR NEW.freelancer_id <> OLD.freelancer_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Proposal job and freelancer are immutable.';
    END IF;
    IF NEW.status <> OLD.status AND EXISTS (
        SELECT 1 FROM contracts WHERE proposal_id = OLD.proposal_id
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot change proposal status after a contract has been created.';
    END IF;
END //

-- 6.3 Ràng buộc hợp đồng & luồng tự động hóa (BR-02, BR-05, BR-15)
CREATE TRIGGER trg_before_contract_insert
BEFORE INSERT ON contracts
FOR EACH ROW
BEGIN
    DECLARE v_proposal_status VARCHAR(20) DEFAULT NULL;
    DECLARE v_job_status VARCHAR(20) DEFAULT NULL;
    SELECT status INTO v_proposal_status
      FROM proposals
     WHERE proposal_id = NEW.proposal_id;
    IF v_proposal_status IS NULL OR v_proposal_status <> 'ACCEPTED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A contract can only use an ACCEPTED proposal.';
    END IF;
    SELECT status INTO v_job_status
      FROM jobs
     WHERE job_id = NEW.job_id;
    IF v_job_status IS NULL OR v_job_status <> 'OPEN' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A contract can only be created for an OPEN job.';
    END IF;
END //

CREATE TRIGGER trg_after_contract_insert
AFTER INSERT ON contracts
FOR EACH ROW
BEGIN
    -- BR-15: Khi tạo CONTRACT, tự động cập nhật JOB sang IN_PROGRESS và từ chối các đề xuất khác.
    UPDATE jobs
       SET status = 'IN_PROGRESS'
     WHERE job_id = NEW.job_id
       AND status = 'OPEN';

    UPDATE proposals
       SET status = 'REJECTED'
     WHERE job_id = NEW.job_id
       AND proposal_id <> NEW.proposal_id
       AND status = 'PENDING';
END //

CREATE TRIGGER trg_before_contract_update
BEFORE UPDATE ON contracts
FOR EACH ROW
BEGIN
    DECLARE v_milestone_total DECIMAL(14, 2) DEFAULT 0.00;
    DECLARE v_milestone_count INT DEFAULT 0;
    DECLARE v_released_count INT DEFAULT 0;
    DECLARE v_open_milestone_count INT DEFAULT 0;

    IF NEW.total_amount <> OLD.total_amount THEN
        SELECT COALESCE(SUM(amount), 0.00)
          INTO v_milestone_total
          FROM milestones
         WHERE contract_id = OLD.contract_id;
        IF v_milestone_total > NEW.total_amount THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Contract value cannot be lower than its milestone schedule.';
        END IF;
    END IF;

    IF NEW.status <> OLD.status AND NOT (
        (OLD.status = 'ACTIVE' AND NEW.status IN ('COMPLETED', 'DISPUTED', 'CANCELLED')) OR
        (OLD.status = 'DISPUTED' AND NEW.status IN ('ACTIVE', 'COMPLETED', 'CANCELLED'))
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid contract status transition.';
    END IF;

    IF NEW.status = 'COMPLETED' AND OLD.status <> 'COMPLETED' THEN
        SELECT COALESCE(SUM(amount), 0.00), COUNT(*),
               COALESCE(SUM(status = 'RELEASED'), 0)
          INTO v_milestone_total, v_milestone_count, v_released_count
          FROM milestones
         WHERE contract_id = OLD.contract_id;
        IF v_milestone_count = 0 OR v_milestone_total <> NEW.total_amount OR
           v_released_count <> v_milestone_count THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Completion requires all milestones released and their sum equal to contract value.';
        END IF;
    END IF;

    IF NEW.status = 'CANCELLED' AND OLD.status <> 'CANCELLED' THEN
        SELECT COUNT(*)
          INTO v_open_milestone_count
          FROM milestones
         WHERE contract_id = OLD.contract_id
           AND status IN ('FUNDED', 'SUBMITTED', 'APPROVED', 'RELEASED');
        IF v_open_milestone_count > 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot cancel a contract with funded, active, or released milestones.';
        END IF;
    END IF;
END //

CREATE TRIGGER trg_after_contract_update
AFTER UPDATE ON contracts
FOR EACH ROW
BEGIN
    IF NEW.status = 'COMPLETED' AND OLD.status <> 'COMPLETED' THEN
        UPDATE jobs
           SET status = 'COMPLETED'
         WHERE job_id = NEW.job_id
           AND status = 'IN_PROGRESS';
    END IF;
END //

-- 6.4 Ràng buộc phân bổ & máy trạng thái giai đoạn (MILESTONES - BR-04, BR-06, BR-11)
CREATE TRIGGER trg_before_milestone_insert
BEFORE INSERT ON milestones
FOR EACH ROW
BEGIN
    DECLARE v_contract_total DECIMAL(14, 2) DEFAULT NULL;
    DECLARE v_contract_status VARCHAR(20) DEFAULT NULL;
    DECLARE v_current_sum DECIMAL(14, 2) DEFAULT 0.00;

    SELECT total_amount, status
      INTO v_contract_total, v_contract_status
      FROM contracts
     WHERE contract_id = NEW.contract_id;

    IF v_contract_status IS NULL OR v_contract_status NOT IN ('ACTIVE', 'DISPUTED') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Milestones can only be added to ACTIVE or DISPUTED contracts.';
    END IF;

    SELECT COALESCE(SUM(amount), 0.00)
      INTO v_current_sum
      FROM milestones
     WHERE contract_id = NEW.contract_id;

    IF ROUND(v_current_sum + NEW.amount, 2) > ROUND(v_contract_total, 2) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Total milestone amount cannot exceed contract total_amount.';
    END IF;
END //

CREATE TRIGGER trg_before_milestone_update
BEFORE UPDATE ON milestones
FOR EACH ROW
BEGIN
    DECLARE v_contract_total DECIMAL(14, 2) DEFAULT NULL;
    DECLARE v_current_sum DECIMAL(14, 2) DEFAULT 0.00;

    IF NEW.contract_id <> OLD.contract_id OR NEW.sequence_no <> OLD.sequence_no THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Milestone contract and sequence are immutable.';
    END IF;
    IF NEW.amount <> OLD.amount THEN
        IF OLD.status <> 'PENDING' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Milestone amount can only change while PENDING.';
        END IF;
        SELECT total_amount INTO v_contract_total FROM contracts WHERE contract_id = OLD.contract_id;
        SELECT COALESCE(SUM(amount), 0.00) INTO v_current_sum FROM milestones WHERE contract_id = OLD.contract_id;
        IF ROUND(v_current_sum - OLD.amount + NEW.amount, 2) > ROUND(v_contract_total, 2) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Total milestone amount cannot exceed contract total_amount.';
        END IF;
    END IF;
    IF NEW.status <> OLD.status AND NOT (
        (OLD.status = 'PENDING' AND NEW.status = 'FUNDED') OR
        (OLD.status = 'FUNDED' AND NEW.status IN ('SUBMITTED', 'REFUNDED')) OR
        (OLD.status = 'SUBMITTED' AND NEW.status IN ('APPROVED', 'REFUNDED')) OR
        (OLD.status = 'APPROVED' AND NEW.status IN ('RELEASED', 'REFUNDED'))
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid milestone status transition.';
    END IF;
END //

-- 6.5 Ràng buộc đánh giá hai chiều (REVIEWS - BR-09, BR-13, BR-14)
CREATE TRIGGER trg_before_review_insert
BEFORE INSERT ON reviews
FOR EACH ROW
BEGIN
    DECLARE v_client_id INT;
    DECLARE v_freelancer_id INT;
    DECLARE v_contract_status VARCHAR(20);
    SELECT client_id, freelancer_id, status
      INTO v_client_id, v_freelancer_id, v_contract_status
      FROM contracts
     WHERE contract_id = NEW.contract_id;
    IF v_contract_status IS NULL OR v_contract_status <> 'COMPLETED' OR NOT (
        (NEW.reviewer_id = v_client_id AND NEW.reviewee_id = v_freelancer_id) OR
        (NEW.reviewer_id = v_freelancer_id AND NEW.reviewee_id = v_client_id)
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Reviews require a completed contract and must be between its client and freelancer.';
    END IF;
END //

CREATE TRIGGER trg_before_review_update
BEFORE UPDATE ON reviews
FOR EACH ROW
BEGIN
    DECLARE v_client_id INT;
    DECLARE v_freelancer_id INT;
    DECLARE v_contract_status VARCHAR(20);
    SELECT client_id, freelancer_id, status
      INTO v_client_id, v_freelancer_id, v_contract_status
      FROM contracts
     WHERE contract_id = NEW.contract_id;
    IF v_contract_status IS NULL OR v_contract_status <> 'COMPLETED' OR NOT (
        (NEW.reviewer_id = v_client_id AND NEW.reviewee_id = v_freelancer_id) OR
        (NEW.reviewer_id = v_freelancer_id AND NEW.reviewee_id = v_client_id)
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Review parties must be the two parties of a completed contract.';
    END IF;
END //

-- Tổng hợp rating được làm mới cho cả insert/update/delete review.
CREATE PROCEDURE sp_refresh_user_rating(IN p_user_id INT)
BEGIN
    DECLARE v_role VARCHAR(20) DEFAULT NULL;
    DECLARE v_avg DECIMAL(3, 2);
    DECLARE v_cnt INT;

    SELECT role INTO v_role FROM users WHERE user_id = p_user_id;

    SELECT COALESCE(ROUND(AVG(rating), 2), 0.00), COUNT(*)
      INTO v_avg, v_cnt
      FROM reviews
     WHERE reviewee_id = p_user_id;

    IF v_role = 'FREELANCER' THEN
        UPDATE freelancers
           SET avg_rating = v_avg,
               review_count = v_cnt
         WHERE freelancer_id = p_user_id;
    ELSEIF v_role = 'CLIENT' THEN
        UPDATE clients
           SET avg_rating = v_avg,
               review_count = v_cnt
         WHERE client_id = p_user_id;
    END IF;
END //

CREATE TRIGGER trg_after_review_insert
AFTER INSERT ON reviews
FOR EACH ROW
BEGIN
    CALL sp_refresh_user_rating(NEW.reviewee_id);
END //

CREATE TRIGGER trg_after_review_update
AFTER UPDATE ON reviews
FOR EACH ROW
BEGIN
    CALL sp_refresh_user_rating(OLD.reviewee_id);
    IF NEW.reviewee_id <> OLD.reviewee_id THEN
        CALL sp_refresh_user_rating(NEW.reviewee_id);
    END IF;
END //

CREATE TRIGGER trg_after_review_delete
AFTER DELETE ON reviews
FOR EACH ROW
BEGIN
    CALL sp_refresh_user_rating(OLD.reviewee_id);
END //

-- 6.6 Sổ cái tài chính bút toán kép & luồng ví (BR-04, BR-07, BR-08, BR-16)
CREATE TRIGGER trg_after_milestone_update
AFTER UPDATE ON milestones
FOR EACH ROW
BEGIN
    DECLARE v_client_id INT;
    DECLARE v_freelancer_id INT;
    DECLARE v_fee_rate DECIMAL(4, 2);
    DECLARE v_fee DECIMAL(12, 2);
    DECLARE v_net DECIMAL(12, 2);

    SELECT client_id, freelancer_id, platform_fee_rate
      INTO v_client_id, v_freelancer_id, v_fee_rate
      FROM contracts
     WHERE contract_id = NEW.contract_id;

    -- Ký quỹ: bút toán kép và cập nhật ví được xử lý tập trung bởi transaction trigger.
    IF OLD.status = 'PENDING' AND NEW.status = 'FUNDED' THEN
        INSERT INTO transactions (
            milestone_id, payer_id, payee_id,
            gross_amount, platform_fee, net_amount,
            tx_type, status
        ) VALUES (
            NEW.milestone_id, v_client_id, NULL,
            NEW.amount, 0.00, NEW.amount,
            'ESCROW_HOLD', 'COMPLETED'
        );

    -- Chỉ giải ngân sau khi APPROVED.
    ELSEIF OLD.status = 'APPROVED' AND NEW.status = 'RELEASED' THEN
        SET v_fee = ROUND(NEW.amount * v_fee_rate, 2);
        SET v_net = NEW.amount - v_fee;

        INSERT INTO transactions (
            milestone_id, payer_id, payee_id,
            gross_amount, platform_fee, net_amount,
            tx_type, status
        ) VALUES (
            NEW.milestone_id, v_client_id, v_freelancer_id,
            NEW.amount, v_fee, v_net,
            'MILESTONE_RELEASE', 'COMPLETED'
        );
    ELSEIF OLD.status IN ('FUNDED', 'SUBMITTED', 'APPROVED') AND NEW.status = 'REFUNDED' THEN
        INSERT INTO transactions (
            milestone_id, payer_id, payee_id,
            gross_amount, platform_fee, net_amount,
            tx_type, status
        ) VALUES (
            NEW.milestone_id, NULL, v_client_id,
            NEW.amount, 0.00, NEW.amount,
            'REFUND', 'COMPLETED'
        );
    END IF;
END //

CREATE TRIGGER trg_before_transaction_insert
BEFORE INSERT ON transactions
FOR EACH ROW
BEGIN
    DECLARE v_ms_status VARCHAR(20) DEFAULT NULL;
    IF NEW.milestone_id IS NOT NULL THEN
        SELECT status INTO v_ms_status FROM milestones WHERE milestone_id = NEW.milestone_id;
        IF (NEW.tx_type = 'ESCROW_HOLD' AND v_ms_status <> 'FUNDED') OR
           (NEW.tx_type = 'MILESTONE_RELEASE' AND v_ms_status <> 'RELEASED') OR
           (NEW.tx_type = 'REFUND' AND v_ms_status <> 'REFUNDED') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transaction type does not match current milestone status.';
        END IF;
    END IF;
END //

-- Chỉ giao dịch COMPLETED làm thay đổi ví; mọi thay đổi và journal entries nằm trong cùng statement.
CREATE TRIGGER trg_after_transaction_insert
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
    DECLARE v_rows INT DEFAULT 0;
    DECLARE v_net_debit DECIMAL(14, 2) DEFAULT 0.00;

    IF NEW.status = 'COMPLETED' THEN
        IF NEW.tx_type = 'DEPOSIT' THEN
            UPDATE users
               SET wallet_balance = wallet_balance + NEW.net_amount
             WHERE user_id = NEW.payee_id;
            INSERT INTO ledger_entries (transaction_id, account_type, user_id, entry_side, amount)
            VALUES (NEW.transaction_id, 'EXTERNAL_CLEARING', NULL, 'DEBIT', NEW.gross_amount);
            IF NEW.platform_fee > 0.00 THEN
                INSERT INTO ledger_entries (transaction_id, account_type, user_id, entry_side, amount)
                VALUES (NEW.transaction_id, 'PLATFORM_FEE', NULL, 'CREDIT', NEW.platform_fee);
            END IF;
            INSERT INTO ledger_entries (transaction_id, account_type, user_id, entry_side, amount)
            VALUES (NEW.transaction_id, 'USER_WALLET', NEW.payee_id, 'CREDIT', NEW.net_amount);

        ELSEIF NEW.tx_type = 'ESCROW_HOLD' THEN
            UPDATE users
               SET wallet_balance = wallet_balance - NEW.gross_amount
             WHERE user_id = NEW.payer_id
               AND wallet_balance >= NEW.gross_amount;
            SET v_rows = ROW_COUNT();
            IF v_rows <> 1 THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient client wallet balance for escrow funding.';
            END IF;
            INSERT INTO ledger_entries (transaction_id, account_type, user_id, entry_side, amount)
            VALUES (NEW.transaction_id, 'USER_WALLET', NEW.payer_id, 'DEBIT', NEW.gross_amount),
                   (NEW.transaction_id, 'ESCROW', NULL, 'CREDIT', NEW.gross_amount);

        ELSEIF NEW.tx_type = 'MILESTONE_RELEASE' THEN
            UPDATE users
               SET wallet_balance = wallet_balance + NEW.net_amount
             WHERE user_id = NEW.payee_id;
            UPDATE freelancers
               SET total_earned = total_earned + NEW.net_amount
             WHERE freelancer_id = NEW.payee_id;
            UPDATE clients
               SET total_spent = total_spent + NEW.gross_amount
             WHERE client_id = NEW.payer_id;
            INSERT INTO ledger_entries (transaction_id, account_type, user_id, entry_side, amount)
            VALUES (NEW.transaction_id, 'ESCROW', NULL, 'DEBIT', NEW.gross_amount);
            IF NEW.platform_fee > 0.00 THEN
                INSERT INTO ledger_entries (transaction_id, account_type, user_id, entry_side, amount)
                VALUES (NEW.transaction_id, 'PLATFORM_FEE', NULL, 'CREDIT', NEW.platform_fee);
            END IF;
            INSERT INTO ledger_entries (transaction_id, account_type, user_id, entry_side, amount)
            VALUES (NEW.transaction_id, 'USER_WALLET', NEW.payee_id, 'CREDIT', NEW.net_amount);

        ELSEIF NEW.tx_type = 'REFUND' THEN
            UPDATE users
               SET wallet_balance = wallet_balance + NEW.net_amount
             WHERE user_id = NEW.payee_id;
            INSERT INTO ledger_entries (transaction_id, account_type, user_id, entry_side, amount)
            VALUES (NEW.transaction_id, 'ESCROW', NULL, 'DEBIT', NEW.gross_amount),
                   (NEW.transaction_id, 'USER_WALLET', NEW.payee_id, 'CREDIT', NEW.net_amount);

        ELSEIF NEW.tx_type = 'WITHDRAWAL' THEN
            UPDATE users
               SET wallet_balance = wallet_balance - NEW.gross_amount
             WHERE user_id = NEW.payer_id
               AND wallet_balance >= NEW.gross_amount;
            SET v_rows = ROW_COUNT();
            IF v_rows <> 1 THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient wallet balance for withdrawal.';
            END IF;
            INSERT INTO ledger_entries (transaction_id, account_type, user_id, entry_side, amount)
            VALUES (NEW.transaction_id, 'USER_WALLET', NEW.payer_id, 'DEBIT', NEW.gross_amount),
                   (NEW.transaction_id, 'EXTERNAL_CLEARING', NULL, 'CREDIT', NEW.net_amount);
            IF NEW.platform_fee > 0.00 THEN
                INSERT INTO ledger_entries (transaction_id, account_type, user_id, entry_side, amount)
                VALUES (NEW.transaction_id, 'PLATFORM_FEE', NULL, 'CREDIT', NEW.platform_fee);
            END IF;
        END IF;

        SELECT COALESCE(SUM(CASE WHEN entry_side = 'DEBIT' THEN amount ELSE -amount END), 0.00)
          INTO v_net_debit
          FROM ledger_entries
         WHERE transaction_id = NEW.transaction_id;
        IF ROUND(v_net_debit, 2) <> 0.00 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ledger transaction is not balanced: debits must equal credits.';
        END IF;
    END IF;
END //

CREATE TRIGGER trg_before_transaction_update
BEFORE UPDATE ON transactions
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Posted transaction records are immutable; post a compensating transaction instead.';
END //

CREATE TRIGGER trg_before_transaction_delete
BEFORE DELETE ON transactions
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Posted transaction records cannot be deleted.';
END //

CREATE TRIGGER trg_before_ledger_update
BEFORE UPDATE ON ledger_entries
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ledger entries are append-only.';
END //

CREATE TRIGGER trg_before_ledger_delete
BEFORE DELETE ON ledger_entries
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ledger entries are append-only.';
END //

-- 6.7 Stored Procedures đăng ký ISA nguyên tử & giao dịch thanh toán
CREATE PROCEDURE sp_register_client(
    IN p_email VARCHAR(150),
    IN p_password_hash VARCHAR(255),
    IN p_full_name VARCHAR(100),
    IN p_company_name VARCHAR(150),
    IN p_industry VARCHAR(100),
    OUT p_user_id INT
)
BEGIN
    INSERT INTO users (email, password_hash, full_name, role)
    VALUES (p_email, p_password_hash, p_full_name, 'CLIENT');
    SET p_user_id = LAST_INSERT_ID();
    INSERT INTO clients (client_id, company_name, industry)
    VALUES (p_user_id, p_company_name, p_industry);
END //

CREATE PROCEDURE sp_register_freelancer(
    IN p_email VARCHAR(150),
    IN p_password_hash VARCHAR(255),
    IN p_full_name VARCHAR(100),
    IN p_headline VARCHAR(200),
    IN p_hourly_rate DECIMAL(10, 2),
    IN p_bio TEXT,
    OUT p_user_id INT
)
BEGIN
    INSERT INTO users (email, password_hash, full_name, role)
    VALUES (p_email, p_password_hash, p_full_name, 'FREELANCER');
    SET p_user_id = LAST_INSERT_ID();
    INSERT INTO freelancers (freelancer_id, headline, hourly_rate, bio)
    VALUES (p_user_id, p_headline, p_hourly_rate, p_bio);
END //

-- Gọi các procedure này sau khi cổng thanh toán xác nhận giao dịch ngoài sàn.
CREATE PROCEDURE sp_post_confirmed_deposit(
    IN p_user_id INT,
    IN p_gross_amount DECIMAL(12, 2),
    IN p_platform_fee DECIMAL(12, 2),
    IN p_external_ref VARCHAR(120)
)
BEGIN
    DECLARE v_status VARCHAR(20) DEFAULT NULL;
    IF p_gross_amount <= 0.00 OR p_platform_fee < 0.00 OR p_platform_fee > p_gross_amount OR
       p_external_ref IS NULL OR CHAR_LENGTH(TRIM(p_external_ref)) = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid confirmed deposit parameters.';
    END IF;
    SELECT status INTO v_status FROM users WHERE user_id = p_user_id;
    IF v_status IS NULL OR v_status <> 'ACTIVE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Deposit beneficiary must be an active user.';
    END IF;
    INSERT INTO transactions (
        milestone_id, payer_id, payee_id, gross_amount, platform_fee, net_amount,
        tx_type, status, external_ref
    ) VALUES (
        NULL, NULL, p_user_id, p_gross_amount, p_platform_fee,
        p_gross_amount - p_platform_fee, 'DEPOSIT', 'COMPLETED', p_external_ref
    );
END //

CREATE PROCEDURE sp_post_confirmed_withdrawal(
    IN p_user_id INT,
    IN p_gross_amount DECIMAL(12, 2),
    IN p_platform_fee DECIMAL(12, 2),
    IN p_external_ref VARCHAR(120)
)
BEGIN
    DECLARE v_status VARCHAR(20) DEFAULT NULL;
    IF p_gross_amount <= 0.00 OR p_platform_fee < 0.00 OR p_platform_fee > p_gross_amount OR
       p_external_ref IS NULL OR CHAR_LENGTH(TRIM(p_external_ref)) = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid confirmed withdrawal parameters.';
    END IF;
    SELECT status INTO v_status FROM users WHERE user_id = p_user_id;
    IF v_status IS NULL OR v_status <> 'ACTIVE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Withdrawal owner must be an active user.';
    END IF;
    INSERT INTO transactions (
        milestone_id, payer_id, payee_id, gross_amount, platform_fee, net_amount,
        tx_type, status, external_ref
    ) VALUES (
        NULL, p_user_id, NULL, p_gross_amount, p_platform_fee,
        p_gross_amount - p_platform_fee, 'WITHDRAWAL', 'COMPLETED', p_external_ref
    );
END //

-- Chỉ hoàn lại toàn bộ milestone còn đang giữ trong escrow.
CREATE PROCEDURE sp_refund_milestone(IN p_milestone_id INT)
BEGIN
    DECLARE v_status VARCHAR(20) DEFAULT NULL;
    SELECT status INTO v_status FROM milestones WHERE milestone_id = p_milestone_id;
    IF v_status IS NULL OR v_status NOT IN ('FUNDED', 'SUBMITTED', 'APPROVED') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only a funded, unreleased milestone can be refunded.';
    END IF;
    UPDATE milestones
       SET status = 'REFUNDED'
     WHERE milestone_id = p_milestone_id
       AND status IN ('FUNDED', 'SUBMITTED', 'APPROVED');
    IF ROW_COUNT() <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Milestone refund lost a concurrent status update.';
    END IF;
END //

DELIMITER ;

-- Ví dụ gọi trong môi trường tích hợp:
-- CALL sp_refund_milestone(1); -- chỉ trước khi milestone được release.
-- CALL sp_post_confirmed_withdrawal(4, 100.00, 2.00, 'PSP-PAYOUT-REF-001');
-- Procedure withdrawal chỉ ghi nhận sau khi cổng chi trả xác nhận và external_ref phải idempotent.

-- ============================================================================
-- 7. VIEWS BÁO CÁO & CHE GIẤU DỮ LIỆU NHẠY CẢM (MỤC 4.1)
-- ============================================================================

-- View 1: Danh sách Freelancer công khai kèm kỹ năng (ẩn password_hash & wallet_balance)
CREATE VIEW vw_top_freelancers AS
SELECT
    u.user_id AS freelancer_id,
    u.full_name,
    f.headline,
    f.hourly_rate,
    f.avg_rating,
    f.review_count,
    f.total_earned,
    GROUP_CONCAT(CONCAT(s.skill_name, ' (Lv.', fs.proficiency_level, ')') ORDER BY fs.proficiency_level DESC SEPARATOR ', ') AS skills_list
FROM users u
JOIN freelancers f ON u.user_id = f.freelancer_id
LEFT JOIN freelancer_skills fs ON f.freelancer_id = fs.freelancer_id
LEFT JOIN skills s ON fs.skill_id = s.skill_id
WHERE u.status = 'ACTIVE'
GROUP BY u.user_id, u.full_name, f.headline, f.hourly_rate, f.avg_rating, f.review_count, f.total_earned;

-- View 2: Tổng hợp tài chính theo từng Hợp đồng
CREATE VIEW vw_contract_financial_summary AS
SELECT
    c.contract_id,
    j.title AS job_title,
    uc.full_name AS client_name,
    uf.full_name AS freelancer_name,
    c.total_amount AS contract_value,
    COALESCE(SUM(CASE WHEN m.status = 'RELEASED' THEN m.amount ELSE 0 END), 0.00) AS released_gross,
    COALESCE(SUM(CASE WHEN m.status IN ('FUNDED', 'SUBMITTED', 'APPROVED') THEN m.amount ELSE 0 END), 0.00) AS held_in_escrow,
    COALESCE(SUM(CASE WHEN m.status = 'PENDING' THEN m.amount ELSE 0 END), 0.00) AS unfunded_remaining,
    COALESCE(SUM(CASE WHEN m.status = 'REFUNDED' THEN m.amount ELSE 0 END), 0.00) AS refunded_gross,
    c.status AS contract_status
FROM contracts c
JOIN jobs j ON c.job_id = j.job_id
JOIN users uc ON c.client_id = uc.user_id
JOIN users uf ON c.freelancer_id = uf.user_id
LEFT JOIN milestones m ON c.contract_id = m.contract_id
GROUP BY c.contract_id, j.title, uc.full_name, uf.full_name, c.total_amount, c.status;

-- View 3: Đối soát số dư ví cache với tổng phát sinh sổ cái của từng user.
CREATE VIEW vw_user_wallet_reconciliation AS
SELECT
    u.user_id,
    u.full_name,
    u.wallet_balance AS cached_wallet_balance,
    COALESCE(SUM(CASE WHEN le.entry_side = 'CREDIT' THEN le.amount ELSE -le.amount END), 0.00) AS ledger_wallet_balance,
    ROUND(u.wallet_balance - COALESCE(SUM(CASE WHEN le.entry_side = 'CREDIT' THEN le.amount ELSE -le.amount END), 0.00), 2) AS difference
FROM users u
LEFT JOIN ledger_entries le
       ON le.user_id = u.user_id
      AND le.account_type = 'USER_WALLET'
GROUP BY u.user_id, u.full_name, u.wallet_balance;

-- View 4: Đối soát Nợ/Có cho từng giao dịch đã ghi sổ.
CREATE VIEW vw_transaction_trial_balance AS
SELECT
    t.transaction_id,
    t.tx_type,
    t.status,
    COALESCE(SUM(CASE WHEN le.entry_side = 'DEBIT' THEN le.amount ELSE 0 END), 0.00) AS debit_total,
    COALESCE(SUM(CASE WHEN le.entry_side = 'CREDIT' THEN le.amount ELSE 0 END), 0.00) AS credit_total,
    ROUND(COALESCE(SUM(CASE WHEN le.entry_side = 'DEBIT' THEN le.amount ELSE 0 END), 0.00) -
          COALESCE(SUM(CASE WHEN le.entry_side = 'CREDIT' THEN le.amount ELSE 0 END), 0.00), 2) AS difference
FROM transactions t
LEFT JOIN ledger_entries le ON le.transaction_id = t.transaction_id
GROUP BY t.transaction_id, t.tx_type, t.status;

-- View 5: Đối soát tiền còn giữ trong escrow với trạng thái milestone.
CREATE VIEW vw_milestone_escrow_reconciliation AS
SELECT
    m.milestone_id,
    m.contract_id,
    m.status,
    CASE WHEN m.status IN ('FUNDED', 'SUBMITTED', 'APPROVED') THEN m.amount ELSE 0.00 END AS expected_escrow_balance,
    COALESCE(SUM(CASE WHEN le.entry_side = 'CREDIT' THEN le.amount ELSE -le.amount END), 0.00) AS ledger_escrow_balance,
    ROUND(CASE WHEN m.status IN ('FUNDED', 'SUBMITTED', 'APPROVED') THEN m.amount ELSE 0.00 END -
          COALESCE(SUM(CASE WHEN le.entry_side = 'CREDIT' THEN le.amount ELSE -le.amount END), 0.00), 2) AS difference
FROM milestones m
LEFT JOIN transactions t
       ON t.milestone_id = m.milestone_id
      AND t.status = 'COMPLETED'
LEFT JOIN ledger_entries le
       ON le.transaction_id = t.transaction_id
      AND le.account_type = 'ESCROW'
GROUP BY m.milestone_id, m.contract_id, m.status, m.amount;

-- View 6: Kiểm tra toàn vẹn phân cấp ISA Disjoint + Total Participation (BR-01).
CREATE VIEW vw_user_isa_reconciliation AS
SELECT
    u.user_id,
    u.email,
    u.role,
    CASE WHEN c.client_id IS NOT NULL THEN 1 ELSE 0 END AS in_clients,
    CASE WHEN f.freelancer_id IS NOT NULL THEN 1 ELSE 0 END AS in_freelancers,
    CASE
        WHEN u.role = 'CLIENT' AND c.client_id IS NOT NULL AND f.freelancer_id IS NULL THEN 'OK'
        WHEN u.role = 'FREELANCER' AND f.freelancer_id IS NOT NULL AND c.client_id IS NULL THEN 'OK'
        WHEN u.role = 'ADMIN' AND c.client_id IS NULL AND f.freelancer_id IS NULL THEN 'OK'
        ELSE 'ISA_VIOLATION'
    END AS isa_status
FROM users u
LEFT JOIN clients c ON c.client_id = u.user_id
LEFT JOIN freelancers f ON f.freelancer_id = u.user_id;

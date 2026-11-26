-- ============================================================================
-- RBAC - MINI-UPWORK (Mục 5.2). Chạy bằng tài khoản có quyền CREATE ROLE / GRANT.
-- Nguyên tắc: ứng dụng không ghi trực tiếp users.wallet_balance, transactions,
-- ledger_entries; ví và sổ cái chỉ thay đổi qua trigger/stored procedure
-- (SQL SECURITY DEFINER nên chạy bằng quyền người tạo, không cần cấp quyền bảng).
-- ============================================================================
USE mini_upwork;

CREATE ROLE IF NOT EXISTS 'mu_client_app', 'mu_freelancer_app',
                          'mu_payment_service', 'mu_onboarding_service', 'mu_admin';

-- Client: đăng job, chọn proposal, lập contract/milestone, ký quỹ/nghiệm thu, đánh giá
GRANT SELECT ON vw_top_freelancers                TO 'mu_client_app';
GRANT SELECT ON vw_contract_financial_summary     TO 'mu_client_app';
GRANT SELECT, INSERT, UPDATE ON jobs              TO 'mu_client_app';
GRANT SELECT, UPDATE (status) ON proposals        TO 'mu_client_app';
GRANT SELECT, INSERT ON contracts                 TO 'mu_client_app';
GRANT SELECT, INSERT, UPDATE (status) ON milestones TO 'mu_client_app';
GRANT SELECT, INSERT ON reviews                   TO 'mu_client_app';

-- Freelancer: hồ sơ/kỹ năng, gửi proposal, bàn giao milestone, đánh giá
GRANT SELECT ON vw_top_freelancers                TO 'mu_freelancer_app';
GRANT SELECT ON jobs                              TO 'mu_freelancer_app';
GRANT SELECT ON skills                            TO 'mu_freelancer_app';
GRANT SELECT, INSERT, UPDATE, DELETE ON freelancer_skills TO 'mu_freelancer_app';
GRANT SELECT, INSERT, UPDATE, DELETE ON proposals TO 'mu_freelancer_app';
GRANT SELECT ON contracts                         TO 'mu_freelancer_app';
GRANT SELECT, UPDATE (status, deliverable_url) ON milestones TO 'mu_freelancer_app';
GRANT SELECT, INSERT ON reviews                   TO 'mu_freelancer_app';
REVOKE DELETE ON proposals FROM 'mu_freelancer_app';  -- rút proposal bằng status = 'WITHDRAWN'

-- Payment service: chỉ ghi nhận nạp/rút đã được cổng thanh toán xác nhận
GRANT EXECUTE ON PROCEDURE sp_post_confirmed_deposit    TO 'mu_payment_service';
GRANT EXECUTE ON PROCEDURE sp_post_confirmed_withdrawal TO 'mu_payment_service';

-- Onboarding service: đăng ký tài khoản nguyên tử (users + subtype) qua procedure
GRANT EXECUTE ON PROCEDURE sp_register_client     TO 'mu_onboarding_service';
GRANT EXECUTE ON PROCEDURE sp_register_freelancer  TO 'mu_onboarding_service';

-- Admin: đối soát (chỉ đọc, không đọc password_hash), hoàn tiền, khóa tài khoản
GRANT SELECT ON vw_user_wallet_reconciliation      TO 'mu_admin';
GRANT SELECT ON vw_transaction_trial_balance       TO 'mu_admin';
GRANT SELECT ON vw_milestone_escrow_reconciliation TO 'mu_admin';
GRANT SELECT ON vw_user_isa_reconciliation         TO 'mu_admin';
GRANT SELECT ON vw_contract_financial_summary      TO 'mu_admin';
GRANT SELECT ON transactions                       TO 'mu_admin';
GRANT SELECT ON ledger_entries                     TO 'mu_admin';
GRANT UPDATE (status) ON users                     TO 'mu_admin';
GRANT EXECUTE ON PROCEDURE sp_refund_milestone     TO 'mu_admin';

-- Tài khoản demo (đổi mật khẩu khi triển khai thật)
CREATE USER IF NOT EXISTS 'mu_demo_client'@'localhost'     IDENTIFIED BY 'Demo#12345';
CREATE USER IF NOT EXISTS 'mu_demo_freelancer'@'localhost' IDENTIFIED BY 'Demo#12345';
CREATE USER IF NOT EXISTS 'mu_demo_payment'@'localhost'    IDENTIFIED BY 'Demo#12345';
CREATE USER IF NOT EXISTS 'mu_demo_onboarding'@'localhost' IDENTIFIED BY 'Demo#12345';
CREATE USER IF NOT EXISTS 'mu_demo_admin'@'localhost'      IDENTIFIED BY 'Demo#12345';
GRANT 'mu_client_app'      TO 'mu_demo_client'@'localhost';
GRANT 'mu_freelancer_app'  TO 'mu_demo_freelancer'@'localhost';
GRANT 'mu_payment_service' TO 'mu_demo_payment'@'localhost';
GRANT 'mu_onboarding_service' TO 'mu_demo_onboarding'@'localhost';
GRANT 'mu_admin'           TO 'mu_demo_admin'@'localhost';
SET DEFAULT ROLE ALL TO 'mu_demo_client'@'localhost', 'mu_demo_freelancer'@'localhost',
                        'mu_demo_payment'@'localhost', 'mu_demo_onboarding'@'localhost',
                        'mu_demo_admin'@'localhost';

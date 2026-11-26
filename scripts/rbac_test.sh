#!/usr/bin/env bash
# Kiem thu RBAC: chay tung cau lenh bang tai khoan demo, doi chieu ma loi MySQL.
# Dung sau khi nap mini_upwork.sql va rbac.sql.   ./rbac_test.sh
PW='Demo#12345'; pass=0; fail=0
t() {  # t <id> <user> <expected: OK | errno> <sql>
  out=$(mysql -u"$2" -p"$PW" mini_upwork -e "$4" 2>&1); rc=$?
  if [ "$3" = OK ]; then [ $rc -eq 0 ] && r=PASS || r=FAIL
  else echo "$out" | grep -q "ERROR $3 " && r=PASS || r=FAIL; fi
  [ $r = PASS ] && pass=$((pass+1)) || fail=$((fail+1))
  printf '%-6s %-4s %-5s %s\n' "$1" "$r" "$3" "$(echo "$4" | cut -c1-70)"
}
C=mu_demo_client; F=mu_demo_freelancer; P=mu_demo_payment; O=mu_demo_onboarding; A=mu_demo_admin
# --- Duoc phep (OK) ---
t RB-01 $C OK    "SELECT full_name, avg_rating FROM vw_top_freelancers"
t RB-02 $C OK    "INSERT INTO jobs (client_id,title,description,budget_min,budget_max) VALUES (2,'t','d',10,20)"
t RB-03 $F OK    "UPDATE proposals SET status='WITHDRAWN' WHERE proposal_id=2"
t RB-04 $P OK    "CALL sp_post_confirmed_deposit(3, 10.00, 0.00, 'RBAC-DEP-1')"
t RB-05 $A OK    "SELECT COUNT(*) FROM vw_user_wallet_reconciliation WHERE difference<>0"
t RB-05b $O OK   "CALL sp_register_client('rb@x.vn','h','RB Client','Co','IT',@id)"
# --- Bi chan (1142 = thieu quyen bang, 1143 = thieu quyen cot, 1370 = thieu quyen EXECUTE) ---
t RB-06 $C 1142  "SELECT password_hash FROM users"
t RB-07 $C 1142  "UPDATE users SET wallet_balance = 999999 WHERE user_id = 2"
t RB-08 $C 1142  "INSERT INTO transactions (payee_id,gross_amount,net_amount,tx_type,external_ref) VALUES (2,1,1,'DEPOSIT','HACK-1')"
t RB-09 $C 1143  "UPDATE milestones SET amount = 1 WHERE milestone_id = 1"
t RB-10 $C 1370  "CALL sp_post_confirmed_deposit(2, 1.00, 0.00, 'HACK-2')"
t RB-11 $F 1142  "DELETE FROM proposals WHERE proposal_id = 2"
t RB-12 $F 1142  "SELECT * FROM transactions"
t RB-13 $F 1142  "UPDATE freelancers SET total_earned = 999999 WHERE freelancer_id = 4"
t RB-14 $P 1142  "SELECT * FROM users"
t RB-15 $P 1370  "CALL sp_refund_milestone(1)"
t RB-16 $A 1142  "SELECT password_hash FROM users"
t RB-17 $A 1142  "DELETE FROM ledger_entries"
t RB-18 $A 1143  "UPDATE users SET wallet_balance = 0 WHERE user_id = 2"
t RB-19 $O 1142  "SELECT * FROM users"
t RB-20 $O 1370  "CALL sp_post_confirmed_deposit(2, 1.00, 0.00, 'HACK-3')"
echo "PASS=$pass FAIL=$fail"

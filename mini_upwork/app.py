"""Flask web application for the Mini-Upwork MySQL schema."""
import os
import secrets
import hmac
from datetime import date
from decimal import Decimal, InvalidOperation
from functools import wraps

import pymysql
from pymysql.cursors import DictCursor
from flask import Flask, flash, redirect, render_template, request, session, url_for
from werkzeug.security import check_password_hash, generate_password_hash

app = Flask(__name__)
app.secret_key = os.getenv("FLASK_SECRET_KEY", secrets.token_hex(32))
app.config.update(SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SAMESITE="Lax")


@app.before_request
def protect_post_forms():
    token = session.setdefault("csrf_token", secrets.token_urlsafe(32))
    if request.method == "POST":
        supplied = request.form.get("csrf_token", "")
        if not supplied or not hmac.compare_digest(token, supplied):
            return "Yêu cầu không hợp lệ. Hãy tải lại trang và thử lại.", 400


def db():
    return pymysql.connect(
        host=os.getenv("DB_HOST", "127.0.0.1"),
        port=int(os.getenv("DB_PORT", "3306")),
        user=os.getenv("DB_USER", "root"),
        password=os.getenv("DB_PASSWORD", ""),
        database=os.getenv("DB_NAME", "mini_upwork"),
        charset="utf8mb4", cursorclass=DictCursor, autocommit=False,
    )


def query(sql, args=(), one=False):
    conn = db()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, args)
            result = cur.fetchone() if one else cur.fetchall()
        conn.commit()
        return result
    finally:
        conn.close()


def current_user():
    return session.get("user")


def login_required(role=None):
    def decorate(fn):
        @wraps(fn)
        def wrapped(*args, **kwargs):
            user = current_user()
            if not user:
                return redirect(url_for("login", next=request.path))
            if role and user["role"] not in (role if isinstance(role, tuple) else (role,)):
                flash("Bạn không có quyền truy cập chức năng này.", "error")
                return redirect(url_for("dashboard"))
            return fn(*args, **kwargs)
        return wrapped
    return decorate


def own_job(job_id):
    return query("SELECT * FROM jobs WHERE job_id=%s AND client_id=%s", (job_id, current_user()["user_id"]), True)


def money(value):
    try:
        amount = Decimal(str(value))
        if not amount.is_finite() or amount <= 0:
            raise ValueError
        return amount
    except (InvalidOperation, TypeError, ValueError):
        raise ValueError("Vui lòng nhập số tiền hợp lệ lớn hơn 0.")


@app.context_processor
def inject_user():
    return {"user": current_user(), "today": date.today().isoformat(), "csrf_token": session.get("csrf_token", "")}


@app.route("/")
def index():
    if current_user():
        return redirect(url_for("dashboard"))
    jobs = query("""SELECT j.job_id,j.title,j.description,j.budget_min,j.budget_max,j.created_at,
        u.full_name AS client_name, COUNT(p.proposal_id) AS proposal_count
        FROM jobs j JOIN users u ON u.user_id=j.client_id
        LEFT JOIN proposals p ON p.job_id=j.job_id AND p.status='PENDING'
        WHERE j.status='OPEN' GROUP BY j.job_id ORDER BY j.created_at DESC LIMIT 6""")
    return render_template("home.html", jobs=jobs)


@app.route("/register", methods=["GET", "POST"])
def register():
    if request.method == "POST":
        role = request.form.get("role")
        email = request.form.get("email", "").strip().lower()
        full_name = request.form.get("full_name", "").strip()
        password = request.form.get("password", "")
        if role not in ("CLIENT", "FREELANCER") or not email or not full_name or len(password) < 8:
            flash("Hãy điền đầy đủ thông tin. Mật khẩu cần ít nhất 8 ký tự.", "error")
            return render_template("register.html")
        conn = db()
        try:
            with conn.cursor() as cur:
                if role == "CLIENT":
                    cur.execute("CALL sp_register_client(%s,%s,%s,%s,%s,@new_user_id)", (
                        email, generate_password_hash(password), full_name,
                        request.form.get("company_name", "").strip() or None,
                        request.form.get("industry", "").strip() or None))
                else:
                    headline = request.form.get("headline", "").strip()
                    rate = money(request.form.get("hourly_rate"))
                    cur.execute("CALL sp_register_freelancer(%s,%s,%s,%s,%s,%s,@new_user_id)", (
                        email, generate_password_hash(password), full_name, headline, rate,
                        request.form.get("bio", "").strip() or None))
                cur.execute("SELECT @new_user_id AS user_id")
                new_id = cur.fetchone()["user_id"]
            conn.commit()
            session["user"] = {"user_id": new_id, "email": email, "full_name": full_name, "role": role}
            flash("Tài khoản đã được tạo.", "success")
            return redirect(url_for("dashboard"))
        except (pymysql.MySQLError, ValueError) as exc:
            conn.rollback()
            flash(f"Không thể đăng ký: {exc}", "error")
        finally:
            conn.close()
    return render_template("register.html")


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        email = request.form.get("email", "").strip().lower()
        row = query("SELECT user_id,email,password_hash,full_name,role,status FROM users WHERE email=%s", (email,), True)
        if row and row["status"] == "ACTIVE" and check_password_hash(row["password_hash"], request.form.get("password", "")):
            session.clear()
            session["user"] = {key: row[key] for key in ("user_id", "email", "full_name", "role")}
            return redirect(request.args.get("next") or url_for("dashboard"))
        flash("Email hoặc mật khẩu không đúng, hoặc tài khoản chưa hoạt động.", "error")
    return render_template("login.html")


@app.post("/logout")
def logout():
    session.clear()
    return redirect(url_for("index"))


@app.route("/dashboard")
@login_required()
def dashboard():
    u = current_user()
    if u["role"] == "CLIENT":
        stats = query("""SELECT COUNT(j.job_id) jobs, COALESCE(SUM(j.status='OPEN'),0) open_jobs,
            c.total_spent FROM clients c LEFT JOIN jobs j ON j.client_id=c.client_id
            WHERE c.client_id=%s GROUP BY c.client_id""", (u["user_id"],), True)
        jobs = query("SELECT job_id,title,status,created_at FROM jobs WHERE client_id=%s ORDER BY created_at DESC LIMIT 5", (u["user_id"],))
        contracts = query("SELECT c.contract_id,c.status,c.total_amount,j.title FROM contracts c JOIN jobs j ON j.job_id=c.job_id WHERE c.client_id=%s ORDER BY c.created_at DESC LIMIT 5", (u["user_id"],))
        return render_template("dashboard.html", stats=stats, jobs=jobs, contracts=contracts)
    if u["role"] == "FREELANCER":
        stats = query("SELECT f.avg_rating,f.review_count,f.total_earned,COUNT(p.proposal_id) proposals FROM freelancers f LEFT JOIN proposals p ON p.freelancer_id=f.freelancer_id WHERE f.freelancer_id=%s GROUP BY f.freelancer_id", (u["user_id"],), True)
        contracts = query("SELECT c.contract_id,c.status,c.total_amount,j.title FROM contracts c JOIN jobs j ON j.job_id=c.job_id WHERE c.freelancer_id=%s ORDER BY c.created_at DESC LIMIT 5", (u["user_id"],))
        proposals = query("SELECT p.proposal_id,p.status,p.bid_amount,j.title FROM proposals p JOIN jobs j ON j.job_id=p.job_id WHERE p.freelancer_id=%s ORDER BY p.submitted_at DESC LIMIT 5", (u["user_id"],))
        return render_template("dashboard.html", stats=stats, contracts=contracts, proposals=proposals)
    reports = query("SELECT 'Ví' AS label, COUNT(*) AS issue_count FROM vw_user_wallet_reconciliation WHERE difference<>0 UNION ALL SELECT 'Sổ cái',COUNT(*) FROM vw_transaction_trial_balance WHERE status='COMPLETED' AND difference<>0 UNION ALL SELECT 'Ký quỹ',COUNT(*) FROM vw_milestone_escrow_reconciliation WHERE difference<>0 UNION ALL SELECT 'Phân loại user',COUNT(*) FROM vw_user_isa_reconciliation WHERE isa_status<>'OK'")
    return render_template("dashboard.html", reports=reports)


@app.route("/jobs")
def jobs():
    term = request.args.get("q", "").strip()
    pattern = f"%{term}%"
    rows = query("""SELECT j.job_id,j.title,j.description,j.budget_min,j.budget_max,j.status,j.created_at,
      u.full_name client_name,COUNT(p.proposal_id) proposal_count
      FROM jobs j JOIN users u ON u.user_id=j.client_id LEFT JOIN proposals p ON p.job_id=j.job_id AND p.status='PENDING'
      WHERE j.status='OPEN' AND (%s='' OR j.title LIKE %s OR j.description LIKE %s)
      GROUP BY j.job_id ORDER BY j.created_at DESC""", (term, pattern, pattern))
    return render_template("jobs.html", jobs=rows, term=term)


@app.route("/jobs/new", methods=["GET", "POST"])
@login_required("CLIENT")
def new_job():
    if request.method == "POST":
        try:
            low, high = money(request.form.get("budget_min")), money(request.form.get("budget_max"))
            if high < low:
                raise ValueError("Ngân sách tối đa phải bằng hoặc lớn hơn tối thiểu.")
            query("INSERT INTO jobs(client_id,title,description,budget_min,budget_max) VALUES(%s,%s,%s,%s,%s)", (
                current_user()["user_id"], request.form["title"].strip(), request.form["description"].strip(), low, high))
            flash("Tin tuyển dụng đã được đăng.", "success")
            return redirect(url_for("my_jobs"))
        except (ValueError, pymysql.MySQLError) as exc:
            flash(f"Không thể đăng tin: {exc}", "error")
    return render_template("job_form.html")


@app.route("/jobs/mine")
@login_required("CLIENT")
def my_jobs():
    rows = query("""SELECT j.*,COUNT(p.proposal_id) proposal_count FROM jobs j
      LEFT JOIN proposals p ON p.job_id=j.job_id WHERE j.client_id=%s GROUP BY j.job_id ORDER BY j.created_at DESC""", (current_user()["user_id"],))
    return render_template("my_jobs.html", jobs=rows)


@app.route("/jobs/<int:job_id>", methods=["GET", "POST"])
def job_detail(job_id):
    job = query("SELECT j.*,u.full_name client_name FROM jobs j JOIN users u ON u.user_id=j.client_id WHERE j.job_id=%s", (job_id,), True)
    if not job:
        flash("Tin tuyển dụng không tồn tại.", "error")
        return redirect(url_for("jobs"))
    u = current_user()
    if request.method == "POST" and (not u or u["role"] != "FREELANCER"):
        flash("Hãy đăng nhập bằng tài khoản freelancer để ứng tuyển.", "error")
        return redirect(url_for("login", next=request.path))
    if request.method == "POST" and u["role"] == "FREELANCER":
        try:
            bid = money(request.form.get("bid_amount"))
            days = int(request.form.get("estimated_days", "0"))
            if days < 1:
                raise ValueError("Thời gian dự kiến cần ít nhất 1 ngày.")
            query("INSERT INTO proposals(job_id,freelancer_id,bid_amount,estimated_days,cover_letter) VALUES(%s,%s,%s,%s,%s)", (job_id,u["user_id"],bid,days,request.form.get("cover_letter", "").strip()))
            flash("Đề xuất đã được gửi.", "success")
            return redirect(url_for("job_detail", job_id=job_id))
        except (ValueError, pymysql.MySQLError) as exc:
            flash(f"Không thể gửi đề xuất: {exc}", "error")
    proposals = []
    if u and u["role"] == "CLIENT" and job["client_id"] == u["user_id"]:
        proposals = query("""SELECT p.*,u.full_name,f.headline,f.avg_rating,f.hourly_rate FROM proposals p
            JOIN users u ON u.user_id=p.freelancer_id JOIN freelancers f ON f.freelancer_id=p.freelancer_id
            WHERE p.job_id=%s ORDER BY p.submitted_at DESC""", (job_id,))
    own = query("SELECT proposal_id,status FROM proposals WHERE job_id=%s AND freelancer_id=%s", (job_id,u["user_id"]), True) if u and u["role"] == "FREELANCER" else None
    return render_template("job_detail.html", job=job, proposals=proposals, own_proposal=own)


@app.post("/proposals/<int:proposal_id>/accept")
@login_required("CLIENT")
def accept_proposal(proposal_id):
    row = query("SELECT p.*,j.client_id,j.title FROM proposals p JOIN jobs j ON j.job_id=p.job_id WHERE p.proposal_id=%s", (proposal_id,), True)
    if not row or row["client_id"] != current_user()["user_id"] or row["status"] != "PENDING":
        flash("Đề xuất không còn khả dụng.", "error")
        return redirect(url_for("dashboard"))
    conn = db()
    try:
        with conn.cursor() as cur:
            cur.execute("UPDATE proposals SET status='ACCEPTED' WHERE proposal_id=%s AND status='PENDING'", (proposal_id,))
            cur.execute("INSERT INTO contracts(job_id,proposal_id,client_id,freelancer_id,total_amount,start_date) VALUES(%s,%s,%s,%s,%s,%s)", (row["job_id"],proposal_id,row["client_id"],row["freelancer_id"],row["bid_amount"],date.today()))
            contract_id = cur.lastrowid
        conn.commit()
        flash("Đề xuất được chọn và hợp đồng đã tạo. Hãy thêm các milestone.", "success")
        return redirect(url_for("contract_detail", contract_id=contract_id))
    except pymysql.MySQLError as exc:
        conn.rollback()
        flash(f"Không thể tạo hợp đồng: {exc}", "error")
        return redirect(url_for("job_detail", job_id=row["job_id"]))
    finally:
        conn.close()


def contract_for_user(contract_id):
    return query("SELECT c.*,j.title AS job_title,uc.full_name AS client_name,uf.full_name AS freelancer_name FROM contracts c JOIN jobs j ON j.job_id=c.job_id JOIN users uc ON uc.user_id=c.client_id JOIN users uf ON uf.user_id=c.freelancer_id WHERE c.contract_id=%s AND (c.client_id=%s OR c.freelancer_id=%s)", (contract_id,current_user()["user_id"],current_user()["user_id"]), True)


@app.route("/contracts")
@login_required()
def contracts():
    u=current_user()
    rows=query("SELECT c.*,j.title,uc.full_name client_name,uf.full_name freelancer_name FROM contracts c JOIN jobs j ON j.job_id=c.job_id JOIN users uc ON uc.user_id=c.client_id JOIN users uf ON uf.user_id=c.freelancer_id WHERE c.client_id=%s OR c.freelancer_id=%s ORDER BY c.created_at DESC", (u["user_id"],u["user_id"]))
    return render_template("contracts.html", contracts=rows)


@app.route("/contracts/<int:contract_id>", methods=["GET", "POST"])
@login_required()
def contract_detail(contract_id):
    contract=contract_for_user(contract_id)
    if not contract:
        flash("Bạn không thể xem hợp đồng này.", "error")
        return redirect(url_for("contracts"))
    if request.method == "POST":
        try:
            if request.form.get("action") == "add_milestone" and current_user()["role"] == "CLIENT":
                amount=money(request.form.get("amount"))
                query("INSERT INTO milestones(contract_id,sequence_no,title,amount,due_date) SELECT %s,COALESCE(MAX(sequence_no),0)+1,%s,%s,%s FROM milestones WHERE contract_id=%s", (contract_id,request.form["title"].strip(),amount,request.form["due_date"],contract_id))
                flash("Milestone đã được thêm.", "success")
            elif request.form.get("action") == "deliver" and current_user()["role"] == "FREELANCER":
                query("UPDATE milestones SET deliverable_url=%s,status='SUBMITTED' WHERE milestone_id=%s AND contract_id=%s AND status='FUNDED'", (request.form.get("deliverable_url", "").strip(),request.form["milestone_id"],contract_id))
                flash("Bàn giao đã được gửi để nghiệm thu.", "success")
            elif request.form.get("action") == "fund" and current_user()["role"] == "CLIENT":
                query("UPDATE milestones SET status='FUNDED' WHERE milestone_id=%s AND contract_id=%s AND status='PENDING'", (request.form["milestone_id"],contract_id))
                flash("Milestone đã được cấp vốn vào escrow.", "success")
            elif request.form.get("action") == "approve" and current_user()["role"] == "CLIENT":
                query("UPDATE milestones SET status='APPROVED' WHERE milestone_id=%s AND contract_id=%s AND status='SUBMITTED'", (request.form["milestone_id"],contract_id))
                flash("Bàn giao đã được nghiệm thu. Có thể giải ngân ở bước tiếp theo.", "success")
            elif request.form.get("action") == "release" and current_user()["role"] == "CLIENT":
                query("UPDATE milestones SET status='RELEASED' WHERE milestone_id=%s AND contract_id=%s AND status='APPROVED'", (request.form["milestone_id"],contract_id))
                flash("Milestone đã được giải ngân.", "success")
            elif request.form.get("action") == "complete" and current_user()["role"] == "CLIENT":
                query("UPDATE contracts SET status='COMPLETED',end_date=%s WHERE contract_id=%s AND client_id=%s AND status='ACTIVE'", (date.today(),contract_id,current_user()["user_id"]))
                flash("Hợp đồng đã hoàn tất.", "success")
            elif request.form.get("action") == "review" and contract["status"] == "COMPLETED":
                reviewee = contract["freelancer_id"] if current_user()["user_id"] == contract["client_id"] else contract["client_id"]
                rating = int(request.form.get("rating", "0"))
                if rating not in range(1, 6):
                    raise ValueError("Điểm đánh giá phải từ 1 đến 5.")
                query("INSERT INTO reviews(contract_id,reviewer_id,reviewee_id,rating,comment) VALUES(%s,%s,%s,%s,%s)", (contract_id,current_user()["user_id"],reviewee,rating,request.form.get("comment", "").strip() or None))
                flash("Đánh giá của bạn đã được lưu.", "success")
            else:
                flash("Thao tác không hợp lệ.", "error")
        except (ValueError,pymysql.MySQLError) as exc:
            flash(f"Không thể cập nhật hợp đồng: {exc}", "error")
        return redirect(url_for("contract_detail",contract_id=contract_id))
    milestones=query("SELECT * FROM milestones WHERE contract_id=%s ORDER BY sequence_no",(contract_id,))
    summary=query("SELECT * FROM vw_contract_financial_summary WHERE contract_id=%s",(contract_id,),True)
    reviews=query("SELECT r.*,u.full_name AS reviewer_name FROM reviews r JOIN users u ON u.user_id=r.reviewer_id WHERE r.contract_id=%s",(contract_id,))
    reviewed=any(r["reviewer_id"]==current_user()["user_id"] for r in reviews)
    return render_template("contract_detail.html", contract=contract, milestones=milestones, summary=summary, reviews=reviews, reviewed=reviewed)


@app.route("/freelancers")
def freelancers():
    rows=query("SELECT * FROM vw_top_freelancers ORDER BY avg_rating DESC,review_count DESC,total_earned DESC LIMIT 100")
    return render_template("freelancers.html",freelancers=rows)


@app.route("/profile", methods=["GET", "POST"])
@login_required("FREELANCER")
def profile():
    uid=current_user()["user_id"]
    if request.method == "POST":
        try:
            rate=money(request.form.get("hourly_rate"))
            query("UPDATE freelancers SET headline=%s,hourly_rate=%s,bio=%s WHERE freelancer_id=%s",(
                request.form.get("headline", "").strip(),rate,request.form.get("bio", "").strip() or None,uid))
            flash("Hồ sơ đã được cập nhật.","success")
            return redirect(url_for("profile"))
        except (ValueError,pymysql.MySQLError) as exc:
            flash(f"Không thể cập nhật hồ sơ: {exc}","error")
    freelancer=query("SELECT u.full_name,u.email,f.headline,f.hourly_rate,f.bio,f.avg_rating,f.review_count,f.total_earned FROM users u JOIN freelancers f ON f.freelancer_id=u.user_id WHERE u.user_id=%s",(uid,),True)
    skills=query("SELECT s.skill_id,s.skill_name,s.category,fs.proficiency_level FROM freelancer_skills fs JOIN skills s ON s.skill_id=fs.skill_id WHERE fs.freelancer_id=%s ORDER BY s.category,s.skill_name",(uid,))
    available=query("SELECT s.skill_id,s.skill_name,s.category FROM skills s LEFT JOIN freelancer_skills fs ON fs.skill_id=s.skill_id AND fs.freelancer_id=%s WHERE fs.skill_id IS NULL ORDER BY s.category,s.skill_name",(uid,))
    return render_template("profile.html",freelancer=freelancer,skills=skills,available_skills=available)


@app.post("/profile/skills")
@login_required("FREELANCER")
def add_profile_skill():
    try:
        level=int(request.form.get("proficiency_level","0"))
        if level not in range(1,6):
            raise ValueError("Mức thành thạo cần từ 1 đến 5.")
        query("INSERT INTO freelancer_skills(freelancer_id,skill_id,proficiency_level) VALUES(%s,%s,%s)",(current_user()["user_id"],int(request.form["skill_id"]),level))
        flash("Kỹ năng đã được thêm.","success")
    except (ValueError,pymysql.MySQLError,KeyError) as exc:
        flash(f"Không thể thêm kỹ năng: {exc}","error")
    return redirect(url_for("profile"))


@app.post("/profile/skills/<int:skill_id>/remove")
@login_required("FREELANCER")
def remove_profile_skill(skill_id):
    query("DELETE FROM freelancer_skills WHERE freelancer_id=%s AND skill_id=%s",(current_user()["user_id"],skill_id))
    flash("Kỹ năng đã được gỡ khỏi hồ sơ.","success")
    return redirect(url_for("profile"))


@app.route("/wallet")
@login_required()
def wallet():
    u=current_user()
    row=query("SELECT wallet_balance FROM users WHERE user_id=%s",(u["user_id"],),True)
    tx=query("SELECT transaction_id,tx_type,status,gross_amount,platform_fee,net_amount,created_at,external_ref FROM transactions WHERE payer_id=%s OR payee_id=%s ORDER BY created_at DESC LIMIT 30",(u["user_id"],u["user_id"]))
    return render_template("wallet.html",balance=row["wallet_balance"],transactions=tx)


@app.route("/admin/reports")
@login_required("ADMIN")
def admin_reports():
    keys={"wallet":"vw_user_wallet_reconciliation","ledger":"vw_transaction_trial_balance","escrow":"vw_milestone_escrow_reconciliation","isa":"vw_user_isa_reconciliation"}
    kind=request.args.get("view","wallet")
    if kind not in keys: kind="wallet"
    rows=query(f"SELECT * FROM {keys[kind]} LIMIT 200")
    return render_template("admin_reports.html",rows=rows,kind=kind)


@app.errorhandler(pymysql.MySQLError)
def db_error(error):
    app.logger.exception("Database error", exc_info=error)
    return render_template("error.html",message="Không thể kết nối hoặc truy vấn cơ sở dữ liệu. Hãy kiểm tra cấu hình MySQL và schema."), 500


if __name__ == "__main__":
    app.run(debug=os.getenv("FLASK_DEBUG", "0") == "1")

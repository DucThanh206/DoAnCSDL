"""Flask web application (bản demo tối giản) cho schema MySQL Mini-Upwork."""
import os
import secrets
import hmac
import uuid
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


# ---------------------------------------------------------------------------
# Hạ tầng: CSRF, kết nối DB, tiện ích
# ---------------------------------------------------------------------------
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
    """Chạy câu SELECT và trả về một dòng hoặc danh sách dòng."""
    conn = db()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, args)
            result = cur.fetchone() if one else cur.fetchall()
        conn.commit()
        return result
    finally:
        conn.close()


def execute(sql, args=()):
    """Chạy câu INSERT/UPDATE/DELETE/CALL, trả về số dòng bị ảnh hưởng."""
    conn = db()
    try:
        with conn.cursor() as cur:
            affected = cur.execute(sql, args)
        conn.commit()
        return affected
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def db_message(exc):
    """Lấy thông điệp dễ đọc từ lỗi MySQL (ví dụ thông điệp SIGNAL của trigger)."""
    if isinstance(exc, pymysql.MySQLError) and len(exc.args) > 1:
        return str(exc.args[1])
    return str(exc)


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


def money(value):
    try:
        amount = Decimal(str(value).strip())
        if not amount.is_finite() or amount <= 0:
            raise ValueError
        return amount.quantize(Decimal("0.01"))
    except (InvalidOperation, TypeError, ValueError):
        raise ValueError("Vui lòng nhập số tiền hợp lệ lớn hơn 0.")


def password_matches(stored, supplied):
    """Bản demo: chấp nhận nhập thẳng chuỗi password_hash lưu trong DB.

    Dữ liệu mẫu chỉ có hash bcrypt (không biết mật khẩu gốc), nên để demo được
    người dùng có thể dán nguyên giá trị cột password_hash vào ô mật khẩu.
    Tài khoản tự đăng ký qua web vẫn đăng nhập bằng mật khẩu thường.
    """
    if not stored or not supplied:
        return False
    if hmac.compare_digest(stored.encode(), supplied.encode()):
        return True
    try:
        return check_password_hash(stored, supplied)
    except (ValueError, TypeError):
        # Hash không phải định dạng của Werkzeug (ví dụ $2b$ bcrypt)
        return False


def safe_next(target):
    if target and target.startswith("/") and not target.startswith("//"):
        return target
    return url_for("dashboard")


@app.context_processor
def inject_user():
    return {"user": current_user(), "today": date.today().isoformat(),
            "csrf_token": session.get("csrf_token", "")}


@app.template_filter("vnd")
def format_money(value):
    if value is None:
        return "—"
    return f"${Decimal(value):,.2f}"


# ---------------------------------------------------------------------------
# Trang chủ, đăng ký, đăng nhập
# ---------------------------------------------------------------------------
@app.route("/")
def index():
    if current_user():
        return redirect(url_for("dashboard"))
    return redirect(url_for("login"))


@app.route("/register", methods=["GET", "POST"])
def register():
    if request.method == "POST":
        role = request.form.get("role")
        email = request.form.get("email", "").strip().lower()
        full_name = request.form.get("full_name", "").strip()
        password = request.form.get("password", "")
        if role not in ("CLIENT", "FREELANCER") or not email or not full_name or len(password) < 8:
            flash("Hãy điền đầy đủ thông tin. Mật khẩu cần ít nhất 8 ký tự.", "error")
            return render_template("register.html", form=request.form)
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
                    if not headline:
                        raise ValueError("Freelancer cần nhập tiêu đề hồ sơ.")
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
            flash(f"Không thể đăng ký: {db_message(exc)}", "error")
        finally:
            conn.close()
    return render_template("register.html", form=request.form)


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        email = request.form.get("email", "").strip().lower()
        row = query("SELECT user_id,email,password_hash,full_name,role,status FROM users WHERE email=%s", (email,), True)
        if row and row["status"] == "ACTIVE" and password_matches(row["password_hash"], request.form.get("password", "").strip()):
            session.clear()
            session["user"] = {key: row[key] for key in ("user_id", "email", "full_name", "role")}
            return redirect(safe_next(request.args.get("next")))
        flash("Email hoặc mật khẩu không đúng, hoặc tài khoản chưa hoạt động.", "error")
    # Một vài tài khoản mẫu mỗi vai trò để bấm "Dùng" khi demo
    demo = query("""(SELECT email,password_hash,full_name,role FROM users WHERE role='ADMIN' AND status='ACTIVE' ORDER BY user_id LIMIT 2)
        UNION ALL (SELECT email,password_hash,full_name,role FROM users WHERE role='CLIENT' AND status='ACTIVE' ORDER BY user_id LIMIT 3)
        UNION ALL (SELECT email,password_hash,full_name,role FROM users WHERE role='FREELANCER' AND status='ACTIVE' ORDER BY user_id LIMIT 3)""")
    return render_template("login.html", demo_accounts=demo)


@app.post("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


# ---------------------------------------------------------------------------
# Tổng quan
# ---------------------------------------------------------------------------
@app.route("/dashboard")
@login_required()
def dashboard():
    u = current_user()
    uid = u["user_id"]
    balance = query("SELECT wallet_balance FROM users WHERE user_id=%s", (uid,), True)
    ctx = {"balance": balance["wallet_balance"] if balance else 0}
    if u["role"] == "CLIENT":
        ctx["stats"] = query("""SELECT (SELECT COUNT(*) FROM jobs WHERE client_id=%s) AS jobs,
            (SELECT COUNT(*) FROM jobs WHERE client_id=%s AND status='OPEN') AS open_jobs,
            (SELECT total_spent FROM clients WHERE client_id=%s) AS total_spent""", (uid, uid, uid), True)
        ctx["contracts"] = query("""SELECT c.contract_id,c.status,c.total_amount,j.title FROM contracts c
            JOIN jobs j ON j.job_id=c.job_id WHERE c.client_id=%s ORDER BY c.created_at DESC LIMIT 5""", (uid,))
    elif u["role"] == "FREELANCER":
        ctx["stats"] = query("""SELECT f.avg_rating,f.review_count,f.total_earned,
            (SELECT COUNT(*) FROM proposals p WHERE p.freelancer_id=f.freelancer_id) AS proposals
            FROM freelancers f WHERE f.freelancer_id=%s""", (uid,), True)
        ctx["contracts"] = query("""SELECT c.contract_id,c.status,c.total_amount,j.title FROM contracts c
            JOIN jobs j ON j.job_id=c.job_id WHERE c.freelancer_id=%s ORDER BY c.created_at DESC LIMIT 5""", (uid,))
        ctx["proposals"] = query("""SELECT p.proposal_id,p.job_id,p.status,p.bid_amount,j.title FROM proposals p
            JOIN jobs j ON j.job_id=p.job_id WHERE p.freelancer_id=%s ORDER BY p.submitted_at DESC LIMIT 5""", (uid,))
    else:
        ctx["reports"] = query("""SELECT 'Ví' AS label, COUNT(*) AS issue_count FROM vw_user_wallet_reconciliation WHERE difference<>0
            UNION ALL SELECT 'Sổ cái', COUNT(*) FROM vw_transaction_trial_balance WHERE status='COMPLETED' AND difference<>0
            UNION ALL SELECT 'Ký quỹ', COUNT(*) FROM vw_milestone_escrow_reconciliation WHERE difference<>0
            UNION ALL SELECT 'Phân loại user', COUNT(*) FROM vw_user_isa_reconciliation WHERE isa_status<>'OK'""")
    return render_template("dashboard.html", **ctx)


# ---------------------------------------------------------------------------
# Công việc & đề xuất
# ---------------------------------------------------------------------------
@app.route("/jobs")
def jobs():
    term = request.args.get("q", "").strip()
    pattern = f"%{term}%"
    rows = query("""SELECT j.job_id,j.title,j.budget_min,j.budget_max,j.created_at,u.full_name AS client_name,
        (SELECT COUNT(*) FROM proposals p WHERE p.job_id=j.job_id AND p.status='PENDING') AS proposal_count
        FROM jobs j JOIN users u ON u.user_id=j.client_id
        WHERE j.status='OPEN' AND (%s='' OR j.title LIKE %s OR j.description LIKE %s)
        ORDER BY j.created_at DESC""", (term, pattern, pattern))
    return render_template("jobs.html", jobs=rows, term=term)


@app.route("/jobs/new", methods=["GET", "POST"])
@login_required("CLIENT")
def new_job():
    if request.method == "POST":
        try:
            title = request.form.get("title", "").strip()
            description = request.form.get("description", "").strip()
            if not title or not description:
                raise ValueError("Hãy nhập tiêu đề và mô tả.")
            low, high = money(request.form.get("budget_min")), money(request.form.get("budget_max"))
            if high < low:
                raise ValueError("Ngân sách tối đa phải bằng hoặc lớn hơn tối thiểu.")
            execute("INSERT INTO jobs(client_id,title,description,budget_min,budget_max) VALUES(%s,%s,%s,%s,%s)",
                    (current_user()["user_id"], title, description, low, high))
            flash("Tin tuyển dụng đã được đăng.", "success")
            return redirect(url_for("my_jobs"))
        except (ValueError, pymysql.MySQLError) as exc:
            flash(f"Không thể đăng tin: {db_message(exc)}", "error")
    return render_template("job_form.html", form=request.form)


@app.route("/jobs/mine")
@login_required("CLIENT")
def my_jobs():
    rows = query("""SELECT j.job_id,j.title,j.status,j.budget_min,j.budget_max,j.created_at,
        (SELECT COUNT(*) FROM proposals p WHERE p.job_id=j.job_id) AS proposal_count
        FROM jobs j WHERE j.client_id=%s ORDER BY j.created_at DESC""", (current_user()["user_id"],))
    return render_template("my_jobs.html", jobs=rows)


@app.route("/jobs/<int:job_id>", methods=["GET", "POST"])
def job_detail(job_id):
    job = query("""SELECT j.*,u.full_name AS client_name FROM jobs j JOIN users u ON u.user_id=j.client_id
        WHERE j.job_id=%s""", (job_id,), True)
    if not job:
        flash("Tin tuyển dụng không tồn tại.", "error")
        return redirect(url_for("jobs"))
    u = current_user()
    if request.method == "POST":
        if not u or u["role"] != "FREELANCER":
            flash("Hãy đăng nhập bằng tài khoản freelancer để ứng tuyển.", "error")
            return redirect(url_for("login", next=request.path))
        try:
            bid = money(request.form.get("bid_amount"))
            try:
                days = int(request.form.get("estimated_days", "0"))
            except ValueError:
                days = 0
            if days < 1:
                raise ValueError("Thời gian dự kiến cần ít nhất 1 ngày.")
            cover = request.form.get("cover_letter", "").strip()
            if not cover:
                raise ValueError("Hãy viết thư giới thiệu.")
            execute("INSERT INTO proposals(job_id,freelancer_id,bid_amount,estimated_days,cover_letter) VALUES(%s,%s,%s,%s,%s)",
                    (job_id, u["user_id"], bid, days, cover))
            flash("Đề xuất đã được gửi.", "success")
        except (ValueError, pymysql.MySQLError) as exc:
            flash(f"Không thể gửi đề xuất: {db_message(exc)}", "error")
        return redirect(url_for("job_detail", job_id=job_id))
    is_owner = bool(u and u["role"] == "CLIENT" and job["client_id"] == u["user_id"])
    proposals = []
    if is_owner:
        proposals = query("""SELECT p.*,u.full_name,f.headline,f.avg_rating FROM proposals p
            JOIN users u ON u.user_id=p.freelancer_id JOIN freelancers f ON f.freelancer_id=p.freelancer_id
            WHERE p.job_id=%s ORDER BY p.submitted_at DESC""", (job_id,))
    own = None
    if u and u["role"] == "FREELANCER":
        own = query("SELECT proposal_id,status,bid_amount FROM proposals WHERE job_id=%s AND freelancer_id=%s",
                    (job_id, u["user_id"]), True)
    contract = query("SELECT contract_id,client_id,freelancer_id FROM contracts WHERE job_id=%s", (job_id,), True)
    can_see_contract = bool(contract and u and u["user_id"] in (contract["client_id"], contract["freelancer_id"]))
    return render_template("job_detail.html", job=job, proposals=proposals, own_proposal=own,
                           is_owner=is_owner, contract=contract if can_see_contract else None)


@app.post("/jobs/<int:job_id>/cancel")
@login_required("CLIENT")
def cancel_job(job_id):
    try:
        n = execute("UPDATE jobs SET status='CANCELLED' WHERE job_id=%s AND client_id=%s AND status='OPEN'",
                    (job_id, current_user()["user_id"]))
        flash("Đã hủy tin tuyển dụng." if n else "Chỉ hủy được tin đang mở của bạn.", "success" if n else "error")
    except pymysql.MySQLError as exc:
        flash(f"Không thể hủy tin: {db_message(exc)}", "error")
    return redirect(url_for("my_jobs"))


@app.post("/proposals/<int:proposal_id>/accept")
@login_required("CLIENT")
def accept_proposal(proposal_id):
    row = query("""SELECT p.*,j.client_id FROM proposals p JOIN jobs j ON j.job_id=p.job_id
        WHERE p.proposal_id=%s""", (proposal_id,), True)
    if not row or row["client_id"] != current_user()["user_id"] or row["status"] != "PENDING":
        flash("Đề xuất không còn khả dụng.", "error")
        return redirect(url_for("dashboard"))
    conn = db()
    try:
        with conn.cursor() as cur:
            cur.execute("UPDATE proposals SET status='ACCEPTED' WHERE proposal_id=%s AND status='PENDING'", (proposal_id,))
            cur.execute("""INSERT INTO contracts(job_id,proposal_id,client_id,freelancer_id,total_amount,start_date)
                VALUES(%s,%s,%s,%s,%s,%s)""",
                        (row["job_id"], proposal_id, row["client_id"], row["freelancer_id"], row["bid_amount"], date.today()))
            contract_id = cur.lastrowid
        conn.commit()
        flash("Đã chọn đề xuất và tạo hợp đồng. Hãy thêm milestone.", "success")
        return redirect(url_for("contract_detail", contract_id=contract_id))
    except pymysql.MySQLError as exc:
        conn.rollback()
        flash(f"Không thể tạo hợp đồng: {db_message(exc)}", "error")
        return redirect(url_for("job_detail", job_id=row["job_id"]))
    finally:
        conn.close()


@app.post("/proposals/<int:proposal_id>/withdraw")
@login_required("FREELANCER")
def withdraw_proposal(proposal_id):
    row = query("SELECT job_id FROM proposals WHERE proposal_id=%s AND freelancer_id=%s",
                (proposal_id, current_user()["user_id"]), True)
    try:
        n = execute("UPDATE proposals SET status='WITHDRAWN' WHERE proposal_id=%s AND freelancer_id=%s AND status='PENDING'",
                    (proposal_id, current_user()["user_id"]))
        flash("Đã rút đề xuất." if n else "Chỉ rút được đề xuất đang chờ.", "success" if n else "error")
    except pymysql.MySQLError as exc:
        flash(f"Không thể rút đề xuất: {db_message(exc)}", "error")
    return redirect(url_for("job_detail", job_id=row["job_id"]) if row else url_for("dashboard"))


# ---------------------------------------------------------------------------
# Hợp đồng & milestone
# ---------------------------------------------------------------------------
def contract_for_user(contract_id):
    uid = current_user()["user_id"]
    return query("""SELECT c.*,j.title AS job_title,uc.full_name AS client_name,uf.full_name AS freelancer_name
        FROM contracts c JOIN jobs j ON j.job_id=c.job_id
        JOIN users uc ON uc.user_id=c.client_id JOIN users uf ON uf.user_id=c.freelancer_id
        WHERE c.contract_id=%s AND (c.client_id=%s OR c.freelancer_id=%s)""", (contract_id, uid, uid), True)


@app.route("/contracts")
@login_required()
def contracts():
    uid = current_user()["user_id"]
    rows = query("""SELECT c.contract_id,c.status,c.total_amount,c.start_date,j.title,
        uc.full_name AS client_name,uf.full_name AS freelancer_name
        FROM contracts c JOIN jobs j ON j.job_id=c.job_id
        JOIN users uc ON uc.user_id=c.client_id JOIN users uf ON uf.user_id=c.freelancer_id
        WHERE c.client_id=%s OR c.freelancer_id=%s ORDER BY c.created_at DESC""", (uid, uid))
    return render_template("contracts.html", contracts=rows)


# action -> (vai trò được phép, trạng thái cũ, trạng thái mới, thông báo)
MILESTONE_STEPS = {
    "fund": ("client", "PENDING", "FUNDED", "Đã cấp vốn milestone vào escrow."),
    "deliver": ("freelancer", "FUNDED", "SUBMITTED", "Đã gửi bàn giao để khách hàng nghiệm thu."),
    "approve": ("client", "SUBMITTED", "APPROVED", "Đã nghiệm thu. Bấm Giải ngân để trả tiền."),
    "release": ("client", "APPROVED", "RELEASED", "Đã giải ngân milestone cho freelancer."),
}


@app.route("/contracts/<int:contract_id>", methods=["GET", "POST"])
@login_required()
def contract_detail(contract_id):
    contract = contract_for_user(contract_id)
    if not contract:
        flash("Bạn không thể xem hợp đồng này.", "error")
        return redirect(url_for("contracts"))
    uid = current_user()["user_id"]
    side = "client" if uid == contract["client_id"] else "freelancer"

    if request.method == "POST":
        action = request.form.get("action")
        try:
            if action == "add_milestone" and side == "client":
                title = request.form.get("title", "").strip()
                due = request.form.get("due_date", "").strip()
                if not title or not due:
                    raise ValueError("Hãy nhập tên và hạn của milestone.")
                amount = money(request.form.get("amount"))
                execute("""INSERT INTO milestones(contract_id,sequence_no,title,amount,due_date)
                    SELECT %s,COALESCE(MAX(sequence_no),0)+1,%s,%s,%s FROM milestones WHERE contract_id=%s""",
                        (contract_id, title, amount, due, contract_id))
                flash("Đã thêm milestone.", "success")
            elif action in MILESTONE_STEPS and MILESTONE_STEPS[action][0] == side:
                _, old, new, msg = MILESTONE_STEPS[action]
                mid = int(request.form.get("milestone_id", "0"))
                if action == "deliver":
                    n = execute("""UPDATE milestones SET deliverable_url=%s,status=%s
                        WHERE milestone_id=%s AND contract_id=%s AND status=%s""",
                                (request.form.get("deliverable_url", "").strip() or None, new, mid, contract_id, old))
                else:
                    n = execute("UPDATE milestones SET status=%s WHERE milestone_id=%s AND contract_id=%s AND status=%s",
                                (new, mid, contract_id, old))
                flash(msg if n else "Milestone không ở trạng thái phù hợp.", "success" if n else "error")
            elif action == "refund" and side == "client":
                mid = int(request.form.get("milestone_id", "0"))
                if not query("SELECT 1 AS ok FROM milestones WHERE milestone_id=%s AND contract_id=%s", (mid, contract_id), True):
                    raise ValueError("Milestone không thuộc hợp đồng này.")
                execute("CALL sp_refund_milestone(%s)", (mid,))
                flash("Đã hoàn tiền milestone về ví khách hàng.", "success")
            elif action == "complete" and side == "client":
                n = execute("UPDATE contracts SET status='COMPLETED',end_date=%s WHERE contract_id=%s AND status='ACTIVE'",
                            (max(date.today(), contract["start_date"]), contract_id))
                flash("Hợp đồng đã hoàn tất." if n else "Hợp đồng không còn ở trạng thái ACTIVE.", "success" if n else "error")
            elif action == "review" and contract["status"] == "COMPLETED":
                reviewee = contract["freelancer_id"] if side == "client" else contract["client_id"]
                try:
                    rating = int(request.form.get("rating", "0"))
                except ValueError:
                    rating = 0
                if rating not in range(1, 6):
                    raise ValueError("Điểm đánh giá phải từ 1 đến 5.")
                execute("INSERT INTO reviews(contract_id,reviewer_id,reviewee_id,rating,comment) VALUES(%s,%s,%s,%s,%s)",
                        (contract_id, uid, reviewee, rating, request.form.get("comment", "").strip() or None))
                flash("Đã lưu đánh giá.", "success")
            else:
                flash("Thao tác không hợp lệ.", "error")
        except (ValueError, pymysql.MySQLError) as exc:
            flash(f"Không thể cập nhật: {db_message(exc)}", "error")
        return redirect(url_for("contract_detail", contract_id=contract_id))

    milestones = query("SELECT * FROM milestones WHERE contract_id=%s ORDER BY sequence_no", (contract_id,))
    summary = query("SELECT * FROM vw_contract_financial_summary WHERE contract_id=%s", (contract_id,), True)
    reviews = query("""SELECT r.*,u.full_name AS reviewer_name FROM reviews r JOIN users u ON u.user_id=r.reviewer_id
        WHERE r.contract_id=%s ORDER BY r.created_at""", (contract_id,))
    reviewed = any(r["reviewer_id"] == uid for r in reviews)
    scheduled = sum((m["amount"] for m in milestones), Decimal("0"))
    remaining = contract["total_amount"] - scheduled
    all_released = bool(milestones) and all(m["status"] == "RELEASED" for m in milestones) and remaining == 0
    balance = query("SELECT wallet_balance FROM users WHERE user_id=%s", (uid,), True)["wallet_balance"]
    return render_template("contract_detail.html", contract=contract, milestones=milestones, summary=summary,
                           reviews=reviews, reviewed=reviewed, side=side, remaining=remaining,
                           all_released=all_released, balance=balance)


# ---------------------------------------------------------------------------
# Freelancer & hồ sơ
# ---------------------------------------------------------------------------
@app.route("/freelancers")
def freelancers():
    rows = query("SELECT * FROM vw_top_freelancers ORDER BY avg_rating DESC,review_count DESC,total_earned DESC LIMIT 100")
    return render_template("freelancers.html", freelancers=rows)


@app.route("/profile", methods=["GET", "POST"])
@login_required("FREELANCER")
def profile():
    uid = current_user()["user_id"]
    if request.method == "POST":
        try:
            headline = request.form.get("headline", "").strip()
            if not headline:
                raise ValueError("Tiêu đề hồ sơ không được để trống.")
            rate = money(request.form.get("hourly_rate"))
            execute("UPDATE freelancers SET headline=%s,hourly_rate=%s,bio=%s WHERE freelancer_id=%s",
                    (headline, rate, request.form.get("bio", "").strip() or None, uid))
            flash("Hồ sơ đã được cập nhật.", "success")
        except (ValueError, pymysql.MySQLError) as exc:
            flash(f"Không thể cập nhật hồ sơ: {db_message(exc)}", "error")
        return redirect(url_for("profile"))
    freelancer = query("""SELECT u.full_name,u.email,f.headline,f.hourly_rate,f.bio,f.avg_rating,f.review_count,f.total_earned
        FROM users u JOIN freelancers f ON f.freelancer_id=u.user_id WHERE u.user_id=%s""", (uid,), True)
    skills = query("""SELECT s.skill_id,s.skill_name,s.category,fs.proficiency_level FROM freelancer_skills fs
        JOIN skills s ON s.skill_id=fs.skill_id WHERE fs.freelancer_id=%s ORDER BY s.category,s.skill_name""", (uid,))
    available = query("""SELECT s.skill_id,s.skill_name,s.category FROM skills s
        LEFT JOIN freelancer_skills fs ON fs.skill_id=s.skill_id AND fs.freelancer_id=%s
        WHERE fs.skill_id IS NULL ORDER BY s.category,s.skill_name""", (uid,))
    return render_template("profile.html", freelancer=freelancer, skills=skills, available_skills=available)


@app.post("/profile/skills")
@login_required("FREELANCER")
def add_profile_skill():
    try:
        level = int(request.form.get("proficiency_level", "0"))
        if level not in range(1, 6):
            raise ValueError("Mức thành thạo cần từ 1 đến 5.")
        execute("INSERT INTO freelancer_skills(freelancer_id,skill_id,proficiency_level) VALUES(%s,%s,%s)",
                (current_user()["user_id"], int(request.form.get("skill_id", "0")), level))
        flash("Đã thêm kỹ năng.", "success")
    except (ValueError, pymysql.MySQLError) as exc:
        flash(f"Không thể thêm kỹ năng: {db_message(exc)}", "error")
    return redirect(url_for("profile"))


@app.post("/profile/skills/<int:skill_id>/remove")
@login_required("FREELANCER")
def remove_profile_skill(skill_id):
    execute("DELETE FROM freelancer_skills WHERE freelancer_id=%s AND skill_id=%s", (current_user()["user_id"], skill_id))
    flash("Đã gỡ kỹ năng.", "success")
    return redirect(url_for("profile"))


# ---------------------------------------------------------------------------
# Ví
# ---------------------------------------------------------------------------
@app.route("/wallet", methods=["GET", "POST"])
@login_required()
def wallet():
    u = current_user()
    if request.method == "POST":
        # Demo: giả lập cổng thanh toán đã xác nhận rồi gọi stored procedure có sẵn.
        action = request.form.get("action")
        try:
            amount = money(request.form.get("amount"))
            ref = f"DEMO-{action.upper() if action else 'X'}-{uuid.uuid4().hex[:12]}"
            if action == "deposit":
                execute("CALL sp_post_confirmed_deposit(%s,%s,0.00,%s)", (u["user_id"], amount, ref))
                flash(f"Đã nạp {format_money(amount)} (demo).", "success")
            elif action == "withdraw":
                execute("CALL sp_post_confirmed_withdrawal(%s,%s,0.00,%s)", (u["user_id"], amount, ref))
                flash(f"Đã rút {format_money(amount)} (demo).", "success")
            else:
                flash("Thao tác không hợp lệ.", "error")
        except (ValueError, pymysql.MySQLError) as exc:
            flash(f"Không thể thực hiện: {db_message(exc)}", "error")
        return redirect(url_for("wallet"))
    row = query("SELECT wallet_balance FROM users WHERE user_id=%s", (u["user_id"],), True)
    tx = query("""SELECT transaction_id,milestone_id,payer_id,payee_id,tx_type,status,gross_amount,platform_fee,net_amount,created_at
        FROM transactions WHERE payer_id=%s OR payee_id=%s ORDER BY created_at DESC, transaction_id DESC LIMIT 50""",
               (u["user_id"], u["user_id"]))
    return render_template("wallet.html", balance=row["wallet_balance"], transactions=tx)


# ---------------------------------------------------------------------------
# Admin
# ---------------------------------------------------------------------------
ADMIN_VIEWS = {
    "wallet": ("Ví", "vw_user_wallet_reconciliation", "difference<>0"),
    "ledger": ("Sổ cái", "vw_transaction_trial_balance", "difference<>0"),
    "escrow": ("Ký quỹ", "vw_milestone_escrow_reconciliation", "difference<>0"),
    "isa": ("Phân loại user", "vw_user_isa_reconciliation", "isa_status<>'OK'"),
}


@app.route("/admin/reports")
@login_required("ADMIN")
def admin_reports():
    kind = request.args.get("view", "wallet")
    if kind not in ADMIN_VIEWS:
        kind = "wallet"
    show_all = request.args.get("all") == "1"
    _, view, condition = ADMIN_VIEWS[kind]
    where = "" if show_all else f" WHERE {condition}"
    rows = query(f"SELECT * FROM {view}{where} LIMIT 200")
    return render_template("admin_reports.html", rows=rows, kind=kind, views=ADMIN_VIEWS, show_all=show_all)


@app.errorhandler(pymysql.MySQLError)
def db_error(error):
    app.logger.exception("Database error", exc_info=error)
    return render_template("error.html", message=f"Lỗi cơ sở dữ liệu: {db_message(error)}. "
                           "Hãy kiểm tra cấu hình MySQL và đã nạp schema chưa."), 500


if __name__ == "__main__":
    app.run(debug=os.getenv("FLASK_DEBUG", "0") == "1")

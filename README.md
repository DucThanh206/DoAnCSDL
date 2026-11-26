# MiniUpwork

Báo cáo Dự án Cơ sở dữ liệu 
Môn học: INT1313 - Cơ sở dữ liệu 
Học kỳ : 1, 2026-2027
Mã dự án & Tên: #3 - Freelance Marketplace Ecosystem (Mini-Upwork)
    •	Tên nhóm: TTU
    
    •	Thành viên: 3
    1.	Trần Đức Thành (n24dccn166@student.ptithcm.edu.vn)
    2.	Đoàn Minh Trí (n24dccn175@student.ptithcm.edu.vn)
    3.	Nguyễn Thành Uy (n24dccn180@student.ptithcm.edu.vn)

    •	Tên đề tài: Freelance Marketplace Ecosystem (Mini-Upwork) — Cơ sở dữ liệu kết nối   khách hàng và freelancer, quản lý hợp đồng, milestone và thanh toán.

Ứng dụng web marketplace freelance dùng Flask, Jinja và MySQL. MySQL lưu dữ liệu và thực thi các quy tắc nghiệp vụ về tài khoản, hợp đồng, milestone, ví, escrow, sổ cái và đánh giá thông qua stored procedure, trigger và view.

## Yêu cầu

- Python 3
- MySQL 8.0.16 trở lên
- MySQL command-line client nếu cần nạp dữ liệu hoặc chạy kiểm thử SQL

## Cài đặt và chạy

### 1. Chuẩn bị database

Tạo database `mini_upwork` và nạp schema gồm các bảng, trigger, stored procedure và view trước khi chạy ứng dụng. **Schema DDL hiện không có trong checkout này.**

`database/mini_upwork_datatest.sql` dùng để nạp dữ liệu mẫu vào schema đã có. Script chọn `mini_upwork`, xóa dữ liệu cũ rồi nạp lại dữ liệu mẫu; không chạy trên database có dữ liệu cần giữ. **File này hiện đang rỗng trong checkout**, vì vậy cần đưa các câu lệnh nạp dữ liệu vào file trước khi chạy.

Trên Windows, từ PowerShell chạy lệnh qua `cmd` để dùng cú pháp chuyển hướng đầu vào:

```cmd
cmd /c "mysql -u root -p < database\mini_upwork_datatest.sql"
```

### 2. Cấu hình môi trường

Các giá trị mặc định của ứng dụng là `DB_HOST=127.0.0.1`, `DB_PORT=3306`, `DB_NAME=mini_upwork`, `DB_USER=root` và `DB_PASSWORD` rỗng. Trên Windows, có thể lưu cấu hình cho tài khoản hiện tại bằng PowerShell:

```powershell
[Environment]::SetEnvironmentVariable("DB_HOST", "127.0.0.1", "User")
[Environment]::SetEnvironmentVariable("DB_PORT", "3306", "User")
[Environment]::SetEnvironmentVariable("DB_NAME", "mini_upwork", "User")
[Environment]::SetEnvironmentVariable("DB_USER", "root", "User")
[Environment]::SetEnvironmentVariable("DB_PASSWORD", "your-mysql-password", "User")
$secret = py -c "import secrets; print(secrets.token_hex(32))"
[Environment]::SetEnvironmentVariable("FLASK_SECRET_KEY", $secret, "User")
Remove-Variable secret
```

Thay `your-mysql-password` bằng mật khẩu MySQL; nếu tài khoản không có mật khẩu, dùng `""`. Các lệnh trên chỉ cần chạy một lần. Mở terminal mới để các biến có hiệu lực. Giữ nguyên `FLASK_SECRET_KEY` giữa các lần chạy để phiên đăng nhập không bị vô hiệu hóa. Không chia sẻ thông tin đăng nhập hoặc lưu bí mật vào mã nguồn.

### 3. Cài thư viện và khởi động

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
py app.py
```

## Chức năng

- Đăng ký và đăng nhập bằng vai trò khách hàng hoặc freelancer; biểu mẫu POST có kiểm tra CSRF.
- Tìm kiếm công việc, đăng tin, gửi đề xuất và chọn đề xuất để tạo hợp đồng.
- Freelancer quản lý hồ sơ và kỹ năng; hai bên theo dõi hợp đồng và milestone.
- Luồng milestone gồm cấp vốn vào escrow, bàn giao, nghiệm thu và giải ngân; trạng thái tài chính và sổ cái được xử lý ở MySQL.
- Ví hiển thị số dư và lịch sử giao dịch; người dùng có thể đánh giá đối tác sau khi hợp đồng hoàn tất.
- Tài khoản admin xem báo cáo đối soát ví, sổ cái, escrow và phân loại người dùng.

Nạp/rút tiền qua cổng thanh toán thật chưa được tích hợp vào giao diện. Các giao dịch nạp/rút chỉ được ghi nhận qua stored procedure sau khi dịch vụ thanh toán xác nhận.

## Kiểm thử database

Chạy các script sau sau khi đã nạp schema và dữ liệu mẫu:

- Test nghiệp vụ: `mysql -u root -p < database/test_cases.sql` (trên PowerShell: `cmd /c "mysql -u root -p < database\test_cases.sql"`). Các kiểm tra chạy trong transaction và rollback dữ liệu thử nghiệm.
- Test phân quyền: nạp `database/rbac.sql`, sau đó chạy `bash scripts/rbac_test.sh` trong môi trường có Bash. Script RBAC tạo role và tài khoản demo với mật khẩu mặc định; chỉ dùng để kiểm thử cục bộ, không dùng các thông tin đó khi triển khai thật.
- `database/perf_seed.sql` và `scripts/perf_run.py` dùng cho benchmark riêng trên Linux; script Python kết nối qua Unix socket và database `mini_upwork_perf`.

## Cấu trúc dự án

- `mini_upwork/app.py`: cấu hình Flask, route và truy vấn database
- `mini_upwork/templates/`: giao diện Jinja
- `mini_upwork/static/`: CSS và tài nguyên tĩnh
- `database/`: dữ liệu mẫu, script RBAC, test nghiệp vụ và dữ liệu benchmark
- `scripts/`: kiểm thử RBAC và benchmark
- `app.py`: entry point tương thích
- `run.py`: entry point phát triển

## Cấu hình môi trường

| Biến | Mặc định | Mục đích |
| --- | --- | --- |
| `DB_HOST` | `127.0.0.1` | Máy chủ MySQL |
| `DB_PORT` | `3306` | Cổng MySQL |
| `DB_NAME` | `mini_upwork` | Database ứng dụng |
| `DB_USER` | `root` | Tài khoản kết nối MySQL |
| `DB_PASSWORD` | rỗng | Mật khẩu MySQL |
| `FLASK_SECRET_KEY` | Tạo ngẫu nhiên khi khởi động | Khóa ký session; nên đặt cố định |
| `FLASK_DEBUG` | `0` | Bật debug khi đặt thành `1` trong môi trường phát triển |

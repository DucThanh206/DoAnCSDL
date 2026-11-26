# MiniUpwork · Flask UI

Ứng dụng web Flask cho hệ thống freelance marketplace trong `mini_upwork (1).sql`. Backend sử dụng MySQL và giữ các luồng ví, ký quỹ, phí, sổ cái, trạng thái milestone và đánh giá trong trigger/stored procedure của schema.

## Chạy ứng dụng

1. Cài MySQL 8.0.16 trở lên, tạo schema bằng cách chạy toàn bộ `database/mini_upwork (1).sql` trong MySQL Workbench hoặc CLI. File này có `DROP DATABASE IF EXISTS mini_upwork`; chỉ chạy khi bạn muốn khởi tạo lại database.
2. Tạo môi trường Python và cài thư viện:

   ```powershell
   py -m venv .venv
   .\.venv\Scripts\Activate.ps1
   pip install -r requirements.txt
   ```

3. Cấu hình các biến môi trường cố định cho tài khoản Windows hiện tại trong PowerShell:

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

   Thay `your-mysql-password` bằng mật khẩu MySQL của bạn; nếu tài khoản không có mật khẩu, dùng `""`. Các lệnh trên lưu giá trị ở phạm vi người dùng Windows. Chỉ cần chạy cấu hình một lần. Đóng và mở lại terminal (hoặc VS Code) để các biến có hiệu lực; sau đó mỗi lần chạy ứng dụng chỉ cần kích hoạt môi trường ảo và chạy `py app.py`. Không tạo khóa phiên mới ở mỗi lần chạy, vì khi đó các phiên đăng nhập hiện tại sẽ mất hiệu lực. Mật khẩu database và khóa phiên được lưu dưới dạng giá trị môi trường của tài khoản Windows này; không chia sẻ tài khoản Windows và không ghi các giá trị đó vào mã nguồn.

4. Khởi động web:

   ```powershell
   py app.py
   ```

   Mở `http://127.0.0.1:5000`.

## Cấu trúc thư mục

- `mini_upwork/`: mã và tài nguyên Flask
  - `app.py`: khởi tạo ứng dụng và các route
  - `templates/`: template Jinja
  - `static/`: CSS và tài nguyên tĩnh
- `database/`: schema, seed và test case SQL
- `scripts/`: script kiểm thử RBAC và đo hiệu năng
- `docs/`: tài liệu dự án
- `app.py`: entry point tương thích khi chạy `py app.py`
- `run.py`: entry point phát triển bổ sung

## Chức năng

- Đăng ký khách hàng/freelancer qua `sp_register_client` và `sp_register_freelancer`; đăng nhập lưu phiên Flask.
- Khám phá việc, đăng tin, gửi đề xuất và chấp nhận đề xuất để tạo hợp đồng.
- Tạo milestone và đi qua luồng cấp vốn, bàn giao, nghiệm thu, giải ngân. Trigger MySQL chịu trách nhiệm kiểm tra trạng thái và ghi sổ cái.
- Tổng quan hợp đồng, ví và giao dịch; đánh giá hai chiều sau khi hoàn tất.
- Trang quản trị đọc các view đối soát đã khai báo trong schema.

Nạp/rút tiền qua cổng thanh toán thật chưa nằm trong phạm vi ứng dụng; giao diện chỉ đọc ví và lịch sử. Cần tích hợp adapter thanh toán trước khi cho phép tạo các giao dịch đó.

## Cấu hình

`DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `FLASK_SECRET_KEY` là biến môi trường tùy chọn. Mặc định database là `mini_upwork`, host `127.0.0.1`, port `3306`, user `root`. Không bật `FLASK_DEBUG` ngoài môi trường phát triển.

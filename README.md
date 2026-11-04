# Adobe Toolkit v0.2

Công cụ chẩn đoán, sửa lỗi đăng nhập, khử dấu vết patch và dọn dữ liệu Adobe cho kỹ thuật viên / máy khách.

- **File chạy độc lập (1 file duy nhất):** `dist\AdobeToolkit.exe` (94 KB) — đã nhúng toàn bộ phần lõi vào trong `.exe`, không cần kèm file `.psm1`.
- **An toàn:** Không đụng vào file giấy phép gốc của Adobe, không vượt kiểm tra bản quyền. Mọi thao tác dọn/khôi phục đều tạo bản sao lưu trong `C:\ProgramData\AdobeToolkit\<ngày-giờ>` kèm `restore-manifest.json` để hoàn tác 1 chạm.

## 5 Tab chức năng trên giao diện
1. **1. Chẩn đoán máy:**
   - Kiểm tra giờ máy, quyền Admin, dòng chặn trong `hosts`, rule chặn trong Windows Firewall, Proxy, kết nối tới máy chủ đăng nhập Adobe (`ims-na1.adobelogin.com:443`), chữ ký số Authenticode của các file Adobe (`.bak` / `HashMismatch`), số lượng `device_token` và danh sách app đã cài.
   - Nút **Lưu báo cáo (JSON):** Xuất file `report.json` ngay tại thư mục chứa `AdobeToolkit.exe`.
2. **2. Sửa lỗi đăng nhập (Theo từng ứng dụng):**
   - Gom nhóm thông tin đăng nhập (Credential Manager) và thư mục `OOBE` / `Caches` theo từng app (`Lightroom Classic`, `Photoshop`, `Creative Cloud`, `Media Encoder`...).
   - Có nút chọn nhanh **Chỉ Lightroom** để chỉ đăng xuất và làm mới token của Lightroom mà giữ nguyên đăng nhập của các app khác.
3. **3. Khôi phục nguyên bản (Khử Patch & Mở chặn mạng):**
   - Phát hiện các file `.bak` do công cụ patch để lại, kiểm tra chữ ký số của file `.bak` và khôi phục đè lại thành file `.exe`/`.dll` nguyên bản của Adobe mà không cần cài lại.
   - Tự động xoá các dòng chặn máy chủ Adobe trong file `hosts` (có sao lưu) và tắt các rule `Block` chặn Adobe trong Windows Firewall.
   - Các file đã bị sửa byte (`HashMismatch`) nhưng mất file `.bak` được đánh dấu rõ để kỹ thuật viên biết cần cài lại qua Creative Cloud.
4. **4. Dọn dữ liệu còn sót (Nâng cao):**
   - Đọc danh sách từ file `AdobeCreativeCloudCleanerTool.exe` chính hãng trên máy khách, tự động khoá bảo vệ các mục **ĐANG DÙNG** của những app còn cài trên máy.
5. **5. Hoàn tác / Sao lưu:**
   - Xem danh sách các phiên sao lưu trước đó và bấm **Hoàn tác phiên đã chọn** để trả lại thư mục `OOBE`, `Caches`, khoá Registry, file `hosts` hoặc bật lại rule tường lửa như cũ.
   - Nút **Mở thư mục sao lưu** mở trực tiếp cửa sổ File Explorer tại thư mục sao lưu.

## Nút tiện ích luôn hiển thị
- **⏹ Đóng tiến trình Adobe** (nằm góc dưới thanh menu trái & trên tab Chẩn đoán): Tự động tắt toàn bộ tiến trình Adobe đang chạy ngầm (`Creative Cloud`, `CCXProcess`, `CoreSync`, `Lightroom`, `Photoshop`...) trước khi dọn.

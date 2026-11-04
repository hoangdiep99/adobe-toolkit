# Adobe Toolkit v0.4.0

Công cụ chẩn đoán, sửa lỗi đăng nhập, khử dấu vết patch, dọn dữ liệu rác và **gỡ cài đặt tận gốc (Deep Uninstall / Full Wipe)** ứng dụng Adobe dành cho kỹ thuật viên & người dùng Windows.

- **File chạy độc lập (1 file duy nhất):** [`dist/AdobeToolkit.exe`](dist/AdobeToolkit.exe) — đã nhúng toàn bộ phần lõi, danh mục 588 sản phẩm Adobe và icon chuẩn Windows 11 vào duy nhất 1 file `.exe`.
- **Chống đơ giao diện 100%:** Toàn bộ tác vụ quét/gỡ chạy ngầm trên Background Runspace kết hợp DoubleBuffered ListView.
- **Tự động đóng tiến trình ngầm:** Tự động dừng các dịch vụ và tiến trình Adobe trước khi dọn/khôi phục/gỡ cài đặt mà không cần tắt thủ công.

## 6 Tab chức năng trên giao diện

1. **1. Chẩn đoán máy:**
   - Kiểm tra giờ máy, quyền Admin, dòng chặn trong `hosts`, rule chặn trong Windows Firewall (qua COM tốc độ cao), Proxy, kết nối tới máy chủ đăng nhập Adobe (`ims-na1.adobelogin.com:443`), chữ ký số Authenticode của các file Adobe (`.bak` / `HashMismatch`), số lượng `device_token` và danh sách app đã cài.
   - Nút **Lưu báo cáo (JSON):** Xuất file `report.json` ngay tại thư mục chứa `AdobeToolkit.exe`.
2. **2. Sửa lỗi đăng nhập (Theo từng ứng dụng):**
   - Gom nhóm thông tin đăng nhập (Windows Credential Manager) và thư mục `OOBE` / `Caches` theo từng app (`Lightroom Classic`, `Photoshop`, `Creative Cloud`, `Media Encoder`...).
   - Xoá trực tiếp các khoá `LegacyGeneric:target=` qua Win32 API (`advapi32.dll` `CredDeleteW`) và sao lưu toàn bộ `CredentialBlob` (`CredReadW`/`CredWriteW`) để có thể hoàn tác.
   - Có nút chọn nhanh **Chỉ Lightroom** để chỉ làm mới phiên đăng nhập của Lightroom Classic mà giữ nguyên đăng nhập của các app khác.
3. **3. Khôi phục nguyên bản (Khử Patch & Mở chặn mạng):**
   - Phát hiện các file `.bak` do công cụ patch để lại, kiểm tra chữ ký số của file `.bak` và khôi phục đè lại thành file `.exe`/`.dll` nguyên bản của Adobe.
   - Tự động xoá các dòng chặn máy chủ Adobe trong file `hosts` (có sao lưu) và tắt các rule `Block` chặn Adobe trong Windows Firewall.
4. **4. Dọn dữ liệu còn sót (Nâng cao):**
   - Tích hợp sẵn danh mục 588 sản phẩm Adobe (2.069 thư mục & 67 khoá Registry HKCU) mà không cần tải thêm `AdobeCreativeCloudCleanerTool.exe`.
   - Tự động khoá bảo vệ các mục **ĐANG DÙNG** của những app còn cài trên máy.
5. **5. Gỡ cài đặt tận gốc (Force Clean / Deep Uninstall):**
   - **Gỡ tận gốc app đã chọn:** Kích hoạt trình gỡ cài đặt gốc của Adobe ở chế độ ngầm, sau đó tự động quét và xoá cưỡng bức toàn bộ thư mục cài đặt, cache `AppData` và giấy phép đăng nhập của riêng app đó.
   - **⚠ GỠ TẤT CẢ & XOÁ SẠCH ADOBE:** Gỡ toàn bộ app Adobe + Creative Cloud, dừng và xoá toàn bộ Windows Services + Scheduled Tasks của Adobe, xoá sạch 100% thư mục Adobe (`Program Files`, `Common Files`, `ProgramData`, `AppData`, `Temp`), xoá sạch nhánh Registry Adobe (`HKCU` & `HKLM`), xoá toàn bộ giấy phép Credential Manager và mở chặn `hosts` / Firewall.
6. **6. Hoàn tác / Sao lưu:**
   - Nút **Tạo bản sao lưu ngay** giúp chụp nhanh trạng thái đăng nhập (Credential Manager + OOBE + cấu hình Lightroom + Registry Adobe + file `hosts`) bất cứ lúc nào.
   - Xem danh sách các phiên sao lưu trước đó và bấm **Khôi phục phiên đã chọn** để hoàn tác chỉ với 1 cú nhấp chuột.

## Đóng gói lại từ mã nguồn
```powershell
powershell -ExecutionPolicy Bypass -File .\Build-Exe.ps1
```

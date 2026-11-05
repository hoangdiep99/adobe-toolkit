# Adobe Toolkit v0.5.0

[![Phiên bản mới nhất](https://img.shields.io/github/v/release/hoangdiep99/adobe-toolkit?label=Phi%C3%AAn%20b%E1%BA%A3n&color=2563eb&style=for-the-badge&logo=github)](https://github.com/hoangdiep99/adobe-toolkit/releases/latest)
[![Tổng lượt tải](https://img.shields.io/github/downloads/hoangdiep99/adobe-toolkit/total?label=T%E1%BB%95ng%20l%C6%B0%E1%BB%A3t%20t%E1%BA%A3i&color=16a34a&style=for-the-badge&logo=windows)](https://github.com/hoangdiep99/adobe-toolkit/releases)
[![Lượt tải bản mới nhất](https://img.shields.io/github/downloads/hoangdiep99/adobe-toolkit/latest/total?label=L%C6%B0%E1%BB%A3t%20t%E1%BA%A3i%20b%E1%BA%A3n%20m%E1%BB%9Bi%20nh%E1%BA%A5t&color=ea580c&style=for-the-badge)](https://github.com/hoangdiep99/adobe-toolkit/releases/latest)
[![Kích thước Bản Clean](https://img.shields.io/github/size/hoangdiep99/adobe-toolkit/dist/AdobeToolkit_Clean.exe?label=B%E1%BA%A3n%20Clean%20(.NET)&color=059669&style=for-the-badge)](https://github.com/hoangdiep99/adobe-toolkit/releases/latest/download/AdobeToolkit_Clean.exe)

Công cụ chẩn đoán, đánh giá kỹ thuật tự động, sửa lỗi đăng nhập, khử dấu vết patch, dọn dữ liệu rác và **gỡ cài đặt tận gốc (Deep Uninstall / Full Wipe)** ứng dụng Adobe dành cho kỹ thuật viên & người dùng Windows.

### 📥 Tải xuống nhanh (2 Phiên bản đóng gói độc lập):
- 🛡️ **Bản chuẩn sạch Native .NET (Khuyên dùng – Thân thiện với Antivirus / Bitdefender / Kaspersky):**
  👉 [**Tải xuống `AdobeToolkit_Clean.exe` (144 KB)**](https://github.com/hoangdiep99/adobe-toolkit/releases/latest/download/AdobeToolkit_Clean.exe) — Biên dịch trực tiếp bằng C# `.NET Framework` (`csc.exe`) + ký chữ ký số `Authenticode SHA256`.
- 📦 **Bản tiêu chuẩn (`ps2exe` truyền thống):**
  👉 [**Tải xuống `AdobeToolkit.exe` (242 KB)**](https://github.com/hoangdiep99/adobe-toolkit/releases/latest/download/AdobeToolkit.exe)

---

## 📊 Thống kê lượt tải (Download Statistics)

| Hạng mục / Phiên bản | Thống kê trực tiếp | Link tải trực tiếp |
| :--- | :---: | :--- |
| **Tổng tất cả phiên bản** | ![Total Downloads](https://img.shields.io/github/downloads/hoangdiep99/adobe-toolkit/total?label=T%E1%BB%95ng%20c%E1%BB%99ng&color=16a34a&style=flat-square) | [Xem tất cả bản phát hành](https://github.com/hoangdiep99/adobe-toolkit/releases) |
| **🛡️ `AdobeToolkit_Clean.exe` (Native .NET - Chuẩn sạch)** | ![Clean Downloads](https://img.shields.io/github/downloads/hoangdiep99/adobe-toolkit/latest/AdobeToolkit_Clean.exe?label=L%C6%B0%E1%BB%A3t%20t%E1%BA%A3i%20Clean&color=059669&style=flat-square) | [**Tải `AdobeToolkit_Clean.exe`**](https://github.com/hoangdiep99/adobe-toolkit/releases/latest/download/AdobeToolkit_Clean.exe) |
| **📦 `AdobeToolkit.exe` (Bản `ps2exe` truyền thống)** | ![Standard Downloads](https://img.shields.io/github/downloads/hoangdiep99/adobe-toolkit/latest/AdobeToolkit.exe?label=L%C6%B0%E1%BB%A3t%20t%E1%BA%A3i%20EXE&color=2563eb&style=flat-square) | [**Tải `AdobeToolkit.exe`**](https://github.com/hoangdiep99/adobe-toolkit/releases/latest/download/AdobeToolkit.exe) |
| **Tổng lượt tải bản `v0.4.0`** | ![v0.4.0 Downloads](https://img.shields.io/github/downloads/hoangdiep99/adobe-toolkit/v0.4.0/total?label=v0.4.0&color=6b7280&style=flat-square) | [Release v0.4.0](https://github.com/hoangdiep99/adobe-toolkit/releases/tag/v0.4.0) |
| **Tổng lượt tải bản `v0.3.0`** | ![v0.3.0 Downloads](https://img.shields.io/github/downloads/hoangdiep99/adobe-toolkit/v0.3.0/total?label=v0.3.0&color=6b7280&style=flat-square) | [Release v0.3.0](https://github.com/hoangdiep99/adobe-toolkit/releases/tag/v0.3.0) |

---

## 🛠️ 6 Tab chức năng trên giao diện

1. **1. Chẩn đoán máy & Đánh giá kỹ thuật tự động:**
   - Kiểm tra giờ máy, quyền Admin, dòng chặn trong `hosts`, rule chặn trong Windows Firewall (qua COM tốc độ cao), Proxy, kết nối tới máy chủ đăng nhập Adobe (`ims-na1.adobelogin.com:443`), chữ ký số Authenticode của các file Adobe (`.bak` / `HashMismatch`), số lượng `device_token` và danh sách app đã cài.
   - **Khung `📊 Phân tích kỹ thuật & Khuyến nghị xử lý (Offline 100%)`:** Tự động chấm điểm sức khoẻ môi trường Adobe trên thang `100/100` và chỉ rõ từng bước cần vào Tab nào để xử lý.
   - Nút **Lưu báo cáo (JSON):** Xuất file `report.json` ngay tại thư mục chứa file `.exe`.
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

## 📦 Đóng gói lại cả 2 phiên bản từ mã nguồn
```powershell
powershell -ExecutionPolicy Bypass -File .\Build-Exe.ps1
```

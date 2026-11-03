# Nợ Bạn Social — bản local-first (không cần server)

## Dữ liệu được lưu ở đâu?
Ứng dụng dùng SQLite (`sqflite`) và lưu trong vùng dữ liệu riêng của ứng dụng Android trên chính điện thoại:
- Danh sách khoản cho vay / đi vay
- Số tiền đã thanh toán và số dư còn lại
- Lịch sử thanh toán
- Bài viết demo trong bảng tin cục bộ

Không cần tài khoản, không cần mạng và không gửi dữ liệu lên máy chủ.

## Giới hạn cần biết
- Dữ liệu chỉ có trên chiếc điện thoại đã nhập.
- Bài đăng không được chia sẻ tới người khác; bạn bè và bình luận chưa kết nối đa thiết bị.
- Gỡ ứng dụng hoặc xóa dữ liệu ứng dụng có thể làm mất dữ liệu. Bản demo chưa có chức năng sao lưu/khôi phục.
- Màn hình Premium chỉ minh họa, chưa thu tiền thật.
- Đây là bản thử nghiệm, không nên dùng làm sổ kế toán chính thức hoặc lưu thông tin nhạy cảm của người khác.

## Tạo APK bằng GitHub Actions
Máy tạo mã nguồn không có Android SDK/Flutter nên không thể biên dịch APK trực tiếp ở đây. Bộ mã nguồn có sẵn workflow build tự động:
1. Tải ZIP và giải nén.
2. Tạo repository mới trên GitHub, upload các file bên trong thư mục vào repository.
3. Mở tab **Actions**. Nếu GitHub hỏi, chọn **I understand my workflows, go ahead and enable them**.
4. Chọn workflow **Build Nợ Bạn Social APK** → **Run workflow**.
5. Khi trạng thái có dấu tick xanh, mở lần chạy đó và tải artifact `no-ban-social-local-apk`.
6. Giải nén artifact để lấy `app-release.apk`, chuyển sang điện thoại Android và cài đặt.

## Build trên máy có Flutter
Chạy:
```bash
flutter create --platforms=android --org com.duy.nobansocial .
flutter pub get
flutter build apk --release
```
APK được tạo tại `build/app/outputs/flutter-apk/app-release.apk`.

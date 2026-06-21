# Network Conditioner

Mô phỏng điều kiện mạng kém (delay + packet loss theo %) cho mục đích dev/QA,
chạy qua một VPN cục bộ (`NETransparentProxyProvider`) trên thiết bị thật.
Traffic vẫn đi ra Internet thật — chỉ bị chèn delay/loss ở tầng relay,
không phải giả lập rỗng.

**Phạm vi cố ý giới hạn:** profile (loss %, delay ms) áp dụng đồng đều cho
toàn bộ traffic qua VPN, không phân biệt loại gói, kích thước, hay hướng.
Không có cơ chế lọc/chặn chọn lọc theo nội dung gói tin.

## 1. Cài XcodeGen (một lần)

```bash
brew install xcodegen
```

## 2. Generate project

```bash
cd NetworkConditioner
xcodegen generate
open NetworkConditioner.xcodeproj
```

XcodeGen tạo `.xcodeproj` từ `project.yml` — đáng tin cậy hơn nhiều so với
sửa tay file `pbxproj`, đặc biệt với setup 2 target (app + extension) + embed
+ app group như project này.

## 3. Build (không cần tài khoản Developer trả phí)

Trong `project.yml`, code signing của Xcode đã tắt
(`CODE_SIGNING_ALLOWED: NO`) vì bạn sẽ tự ký bằng `ldid` ở bước sau. Build
thẳng bằng `xcodebuild`:

```bash
xcodebuild -project NetworkConditioner.xcodeproj \
  -scheme NetworkConditioner -configuration Release \
  -sdk iphoneos -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
```

Kết quả nằm ở:
`build/Build/Products/Release-iphoneos/NetworkConditioner.app`

## 4. Tự ký bằng ldid (TrollStore)

Ký **cả hai** binary — app chính và extension bên trong `PlugIns/` — với
đúng entitlements tương ứng:

```bash
APP="build/Build/Products/Release-iphoneos/NetworkConditioner.app"

ldid -S"NetworkConditionerApp/NetworkConditionerApp.entitlements" \
  "$APP/NetworkConditioner"

ldid -S"ConditionerExtension/ConditionerExtension.entitlements" \
  "$APP/PlugIns/ConditionerExtension.appex/ConditionerExtension"
```

Đóng gói `.ipa` và cài bằng TrollStore như bạn đã làm với PacketBlocker
trước đó:

```bash
mkdir -p Payload
cp -R "$APP" Payload/
zip -r NetworkConditioner.ipa Payload
```

## 5. Dùng

1. Mở app, bấm **Bắt đầu** → iOS hỏi xác nhận VPN lần đầu (bình thường, vì
   là local network extension, không phải VPN từ xa).
2. Bật **"Bật giả lập điều kiện mạng"**, kéo 2 slider loss% / delay ms.
3. Mọi thay đổi áp dụng ngay cho kết nối đang chạy — không cần ngắt VPN,
   không có "làn" ẩn nào để chuyển qua lại.

## CI: build qua GitHub Actions (không cần Mac)

Repo có sẵn `.github/workflows/build.yml`. Sau khi push code lên GitHub
(repo có thể private):

1. Vào tab **Actions** → chọn workflow **Build IPA** → **Run workflow**
   (hoặc tự chạy mỗi khi push thay đổi vào file `.swift`/`project.yml`).
2. Runner `macos-14` của GitHub tự: cài XcodeGen + `ldid` → generate
   project → build bằng `xcodebuild` (không ký) → tự ký cả app lẫn
   extension bằng `ldid` với đúng entitlements → đóng gói `NetworkConditioner.ipa`.
3. Sau khi job xanh, vào trang kết quả của run đó, tải artifact
   **NetworkConditioner-ipa** ở cuối trang → giải nén ra file `.ipa`,
   cài bằng TrollStore như bình thường.

File `.xcodeproj` không commit vào repo (đã thêm `.gitignore`) — CI tự
generate lại từ `project.yml` mỗi lần chạy, tránh project file bị lệch
giữa máy bạn và máy CI.

## Vì sao tránh được lỗi "Extension không phản hồi sau nhiều lần thử"

Lỗi đó thường do một (hoặc nhiều) trong các nguyên nhân sau — project này
xử lý từng cái:

- **App Group không khớp giữa 2 target** → `sendProviderMessage` gửi vào
  hư không vì extension chưa từng đọc được cấu hình ban đầu, hoặc app
  không đợi tunnel `.connected` mà đã gửi message. `ConditionerManager`
  chỉ gọi `sendProviderMessage` khi `connection.status == .connected`,
  và cache profile vào App Group để extension tự đọc lại nếu khởi động
  lại từ đầu (reboot, on-demand reconnect).
- **`startProxy` không gọi `completionHandler` trên mọi nhánh** (kể cả
  lỗi) → hệ thống coi extension "treo" rồi timeout. Mọi nhánh trong
  `ProxyProvider.startProxy` đều gọi completion handler.
- **Block đồng bộ trong `handleNewFlow`** (ví dụ mở socket đồng bộ chờ
  kết nối xong mới return) → đây chính là nguyên nhân phổ biến nhất.
  `handleNewFlow` ở đây return `true` ngay lập tức và relay chạy hoàn
  toàn bất đồng bộ qua closure/callback, không block.
- **Force-unwrap crash khi parse `remoteEndpoint`** làm process extension
  chết âm thầm giữa chừng → toàn bộ code dùng `guard let`, không force
  unwrap, fail gracefully bằng `closeReadAndWrite()`.

Lưu ý: đây là nguyên nhân *thường gặp nhất* dựa trên kiến trúc — nếu bạn
build và vẫn gặp lỗi tương tự, gửi log Console.app lọc theo
`com.networkconditioner.app.extension` để debug tiếp, vì có thể là vấn đề
riêng của môi trường TrollStore (ví dụ entitlement chưa được áp đúng khi
ký).

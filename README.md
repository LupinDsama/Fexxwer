# Fexxwer TheDev — Portfolio

Portfolio cá nhân của Fexxwer TheDev: Roblox scripter / gameplay programmer.
Code tay bằng HTML + CSS + JS thuần, không dùng template, 2 theme sáng/tối.

## Chạy local

Mở trực tiếp file `html/index.html` bằng trình duyệt,
hoặc chạy static server từ thư mục gốc:

```bash
cd Porfolio
npx serve .
# hoặc
python -m http.server 8000
```

Sau đó mở `http://localhost:8000/html/`.

## Cấu trúc

```text
Porfolio/
├── html/index.html   # toàn bộ các tab (SPA, chuyển tab bằng data-nav)
├── css/style.css     # design system: 1 accent, dark/light qua [data-theme]
├── js/index.js       # nav, theme, reveal, shop, game chip ảo, chart Status, copy code
├── img/              # avatar, thumbnail sản phẩm, model
└── README.md
```

## Các tab hiện tại

| Tab | Nội dung |
|---|---|
| Home | Giới thiệu, commission, góc làm việc |
| Shop | Source bán 1 lần: Discord bot, Dashboard UI, GUI template, Portfolio template, script auto farm |
| VFX / GFX | Hiệu ứng edit, thiết kế |
| Showcase | Sky Land (Roblox) + GUI chống lag + model Blender |
| Tutorials | DataStore, GUI chống spam, Remote gọn, portfolio 1 trang, model 5k tris, profiling |
| Projects | Dự án đã lên sóng, có link chơi được |
| Models | Model Blender: súng AK, dao găm, sạp chợ |
| Games | Blackjack + Texas Holdem heads-up vs bot, chip ảo lưu localStorage |
| **Coding** | Backend senior: handler registry, kho dữ liệu, debug, thuật toán, packages riêng |
| Status | Kinh nghiệm, chart kỹ năng / hoạt động / phân bổ thời gian |

> Tab **Trading** (giá Binance) đã xóa hoàn toàn: HTML, JS `fetchKlines/renderCard`, CSS trading.

## Tab Coding — điểm nhấn backend

- **Handler registry** (`Server/HandlerRegistry.lua`): 1 Remote dispatcher duy nhất
  cho shop / quest / save. Validate + rate-limit + `pcall` isolate từng lệnh,
  thêm chức năng mới không sửa file cũ.
- **Kho dữ liệu** (`Server/DataStore.lua`): session lock chống ghi đè khi player
  nhảy server, `UpdateAsync` + version migrate (v1–v4), autosave 60s,
  queue retry theo cấp số nhân 1s / 2s / 4s.
- **Debug theo quy trình**: mỗi warn kèm traceId → tra log trong 1 phút;
  MicroProfiler + memory tag trước khi đoán; TestEZ cho inventory/sort/path,
  fail thì không merge.
- **Thuật toán**: inventory stack O(1) lookup, sort O(n log n), đánh bài 5 lá
  qua liệt kê tổ hợp 21 combo 7-chọn-5.
- **Packages riêng tái dùng qua 3 game**: Net (packet/queue/retry), DataKit
  (defaults/migrate/lock), Logger (traceId), InvAlgo, Promise (thay spawn/wait),
  Config (constant 1 chỗ). Quản lý bằng Wally/Pesde + Semver, lint Stylua + Selene.

## Ghi chú kỹ thuật

- SPA: `.tab-content` + `showSection(id)`, nhớ tab đang mở qua `localStorage`.
- Theme: `[data-theme]`, ưu tiên hệ điều hành, nhớ lựa chọn người dùng.
- Reveal on scroll bằng `IntersectionObserver`, có fallback an toàn.
- Chart Status dùng Chart.js (lazy init 1 lần). Game zone không phụ thuộc mạng.
- Nút Copy trong tab Coding dùng `navigator.clipboard` + fallback `execCommand`.

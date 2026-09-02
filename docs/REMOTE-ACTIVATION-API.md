# API kích hoạt services từ bên ngoài — Cheat sheet

> Lưu ý bảo mật: URL thật (preview domain + webhook) KHÔNG được public trên repo này.
> Xem URL hiện tại bằng `get_all_domains_ports()` trong phiên CodeBanana, hoặc trong
> `.codebanana/.agent/MEMORY.md` (không được commit).

## 1. Khi container CÒN SỐNG (service chết / cần start)

Control API công khai qua gateway CodeBanana (domain preview tổng quát — ổn định qua restart):

```
BASE=<app-preview-domain cho port 8002>   # lấy từ get_all_domains_ports()
```

| Mục đích | Lệnh |
|---|---|
| Kiểm tra còn sống | `curl $BASE/health` |
| **Start tất cả** (APIs 9102+8002 + DC Remote) | `curl -X POST $BASE/api/dc/keepalive` |
| Start DC Remote | `curl -X POST $BASE/api/dc/start` |
| Restart DC Remote | `curl -X POST $BASE/api/dc/restart` |
| Xem trạng thái | `curl $BASE/api/dc/status` |
| Xem logs | `curl "$BASE/api/dc/logs?lines=50"` |
| Backup session | `curl -X POST $BASE/api/dc/backup` |

Lưu ý: các endpoint POST có thể mất tới ~2 phút (start/keepalive chờ "Device ready").

## 2. Khi container CHẾT (API không trả lời được)

Không có API nào trong container trả lời được lúc này — dùng webhook của CodeBanana
(đi qua server nền tảng, đánh thức phiên agent → agent chạy keepalive):

```sh
# URL webhook + bt_id lấy từ get_webhook_info của task "Wake container & start all services"
curl -X POST "<webhook-url>" \
  -H "Content-Type: application/json" \
  -d '{"bt_id": "<bt_id>", "data": {"reason": "wake up"}}'
```

- Trả `202 Accepted` ngay; agent chạy nền trong ~1-2 phút.
- Task tự động tương đương đã được lập lịch: **"Auto keepalive: APIs + DC Remote"** chạy mỗi 15 phút.

### 2.1 Cơ chế hoạt động

```text
Bạn (điện thoại / cron / script)
        |  POST <webhook-url>  {"bt_id": "...", "data": {...}}
        v
CodeBanana platform server (prd-chat-socket-api...)  ← luôn online
        |  202 Accepted (async)
        v
Platform đánh thức phiên agent của project
        |  agent đọc "message" của task
        v
Agent chạy: sh keepalive-apis.sh  →  verify ss/ss + dc-remote.sh status
        |
        v
Báo cáo kết quả vào log .codebanana/.runs/<task-name>/
```

Điểm mấu chốt: request KHÔNG đi vào container (container đang chết) mà đi vào
server nền tảng. Platform chịu trách nhiệm wake phiên agent; agent khi chạy sẽ
kích hoạt container + mọi service. Vì vậy webhook vẫn hoạt động cả khi container
đã thoát.

### 2.2 Cách tạo webhook task (trong chat CodeBanana)

Webhook task được tạo bằng công cụ `create_webhook_task` của agent. Cách làm:
mở chat project và yêu cầu agent tạo, ví dụ:

> "Tạo một webhook task tên 'Wake container & start all services'. Khi được gọi,
> chạy `sh keepalive-apis.sh` trong workspace, verify port 9102 + 8002 đang nghe
> và báo cáo kết quả."

Agent sẽ gọi tool với các tham số:

| Tham số | Bắt buộc | Ý nghĩa |
|---|---|---|
| `name` | ✅ | Tên ngắn gọn của task (hiện trong danh sách task và log) |
| `message` | ✅ | Lệnh agent sẽ thực thi khi webhook được gọi — **mệnh lệnh, tự chứa đầy đủ** (đường dẫn tuyệt đối, không dùng đại từ), không chứa từ ngữ lập lịch ("mỗi 15 phút", "hàng ngày"...) |
| `emoji_icon` | ✅ | 1 emoji đại diện (VD 🚀) |
| `context` | ➖ | JSON metadata thêm (workspace path, ghi chú...) |

Quy tắc viết `message` (agent thực thi là một phiên MỚI, không có lịch sử hội thoại):

- Bắt đầu bằng động từ hành động: "Run...", "Check...", "Report..."
- Tự chứa mọi thứ: đường dẫn workspace tuyệt đối, tên script, điều cần verify
- Nói rõ hình thức báo cáo lại (output cuối của agent là thông báo trả về cho bạn)
- Truy cập dữ liệu từ request body webhook bằng `{{payload.data.xxx}}`
  (VD: `"If payload.data.reason is provided, include it in the report."`)

Sau khi tạo, agent trả về `id` dạng `bt_xxxxxxxx` — đây là `bt_id` dùng khi gọi.

### 2.3 Lấy URL webhook

Yêu cầu agent chạy tool `get_webhook_info` với `task_id` = `bt_id` vừa tạo.
Kết quả trả về gồm:

- `webhook_url` — URL công khai để POST (format:
  `https://prd-chat-socket-api.codebanana.com/cb-trigger-server/api/v1/banana_tasks/webhook/whk_.../receive`)
- `method`: `POST`, `headers`: `Content-Type: application/json`
- `request_body`: `bt_id` (bắt buộc) + `data` (tùy chọn — payload tùy ý)
- `curl_example` — lệnh mẫu sẵn sàng copy

### 2.4 Gọi webhook

```sh
curl -X POST "<webhook-url>" \
  -H "Content-Type: application/json" \
  -d '{"bt_id": "<bt_id>", "data": {"reason": "wake up"}}'
```

Response thành công: `202 Accepted` với body `{"accepted":true,"event_id":"evt_..."}`.
Việc thực thi là **bất đồng bộ** — không đợi kết quả trong response này.

Trường `data` là tùy chọn và được chuyển thẳng cho agent (đọc bằng
`{{payload.data.xxx}}`). Hữu ích để gắn nhãn nguồn gọi: `{"reason":"manual"}`,
`{"reason":"cron-external"}`...

### 2.5 Kiểm tra kết quả thực thi

Mỗi lần chạy ghi một log file:

```text
.codebanana/.runs/<task-name>/<YYYY-MM-DD>_<HH-MM-SS>.md
```

Nội dung gồm: trạng thái (✅/❌), model, thời gian, kết quả thực thi (phần đầu)
và toàn bộ tiến trình kèm timestamp (phần cuối). File mới nhất (sort theo tên)
= lần chạy gần nhất.

### 2.6 Quản lý task

- Liệt kê mọi task: agent chạy `list_schedule_task`
- Webhook task không có lịch — chỉ được kích hoạt qua POST; muốn tắt thì yêu
  cầu agent xóa task
- Task lịch (interval/daily...) tạo tương tự bằng tool `schedule_task`
  (`schedule_type: "interval"`, `schedule_value: "15m"`) — task
  "Auto keepalive: APIs + DC Remote" trong dự án này được tạo đúng cách đó

### 2.7 Hành vi đã quan sát (lưu ý)

- Nếu project đang có một phiên khác chiếm giữ (VD: bạn đang chat), lần chạy đó
  bị hoãn với thông báo "project is occupied by another session" — không mất
  mát gì, chỉ cần chạy lại khi rảnh hoặc chờ task interval kế tiếp.
- Webhook URL trông như một secret: ai có URL + bt_id đều gọi được. Không đăng
  công khai; nếu lộ, yêu cầu agent xóa và tạo task mới (URL mới sẽ khác).


## 3. Cơ chế tự phục hồi trong container

- `keepalive-apis.sh` — idempotent: đảm bảo node API nghe trên 9102 + 8002, chạy `dc-remote.sh start`.
- `dc-remote.sh keepalive` — gọi keepalive-apis.sh từ wrapper.
- `.codebanana/.agent/HEARTBEAT.md` — chỉ dẫn heartbeat chạy keepalive mỗi chu kỳ.

## 4. Về domain ngrok `m-*.ngrok.app`

- Mapping platform: kiểm tra bằng get_all_domains_ports().
- Tunnel do platform quản lý; sau khi container restart có thể offline (ERR_NGROK_3200)
  và KHÔNG thể gắn lại từ trong container (ERR_NGROK_4018 — không có authtoken).
- Không hard-code; luôn verify trạng thái từ bên ngoài trước khi dùng.

## 5. Khuyến nghị bảo mật

- Bật auth: đặt `DC_API_TOKEN=<secret>` trong `.env`, bỏ `DC_API_AUTH_REQUIRED=false`
  → mọi `/api/dc/*` yêu cầu header `Authorization: Bearer <token>`.
- Không commit `.env`, `.dc-api-token`, session files.

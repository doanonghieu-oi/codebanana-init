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

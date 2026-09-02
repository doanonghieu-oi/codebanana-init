# CodeBanana Desktop Commander Control API

Authenticated HTTP control surface for dc-remote.sh.

Configuration:

DC_API_TOKEN=<long-random-secret>
DC_API_PORT=8000

Start:

sh start-control-api.sh

Endpoints:

GET  /health
GET  /api/dc/status
GET  /api/dc/logs?lines=80
POST /api/dc/start
POST /api/dc/stop
POST /api/dc/restart
POST /api/dc/backup

All /api/dc/* endpoints require:

Authorization: Bearer <DC_API_TOKEN>

Use CodeBanana get_all_domains_ports() to obtain the current public domain for the selected port.
Do not hard-code an ngrok URL. Desktop Commander itself remains an outbound WebSocket client.

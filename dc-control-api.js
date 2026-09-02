const http = require('node:http');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = process.env.WORKSPACE_PATH || __dirname;
const SCRIPT = path.join(ROOT, 'dc-remote.sh');
const PORT = Number(process.env.DC_API_PORT || process.env.PORT || 9102);
const HOST = process.env.DC_API_HOST || '0.0.0.0';
const AUTH_REQUIRED = !['0', 'false', 'no', 'off'].includes(String(process.env.DC_API_AUTH_REQUIRED || 'true').toLowerCase());
const TOKEN = process.env.DC_API_TOKEN || '';

if (AUTH_REQUIRED && !TOKEN) {
  console.error('ERROR: DC_API_TOKEN is required when DC_API_AUTH_REQUIRED is enabled.');
  process.exit(1);
}
if (!fs.existsSync(SCRIPT)) {
  console.error(`ERROR: dc-remote.sh not found: ${SCRIPT}`);
  process.exit(1);
}

function json(res, status, data) {
  const body = JSON.stringify(data);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
  });
  res.end(body);
}

function authorized(req) {
  if (!AUTH_REQUIRED) return true;
  return (req.headers.authorization || '') === `Bearer ${TOKEN}`;
}

function run(command, waitMs) {
  return new Promise((resolve) => {
    const child = spawn('sh', [SCRIPT, command], {
      cwd: ROOT,
      env: process.env,
    });
    let stdout = '';
    let stderr = '';
    let done = false;
    const finish = (result) => {
      if (done) return;
      done = true;
      resolve(result);
    };
    child.stdout.on('data', (d) => { stdout += d; });
    child.stderr.on('data', (d) => { stderr += d; });
    child.on('error', (err) => finish({ ok: false, code: null, stdout, stderr: `${stderr}${err.message}` }));
    child.on('close', (code) => finish({ ok: code === 0, code, stdout, stderr }));
    setTimeout(() => finish({ ok: true, accepted: true, timeout: true, code: null, stdout, stderr }), waitMs);
  });
}

function readLogs(lines) {
  const file = path.join(ROOT, 'logs', 'desktop-commander.log');
  if (!fs.existsSync(file)) return '';
  const count = Math.max(1, Math.min(Number(lines) || 80, 500));
  return fs.readFileSync(file, 'utf8').split('\n').slice(-count).join('\n');
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    return json(res, 200, { ok: true, service: 'dc-control-api', authRequired: AUTH_REQUIRED, port: PORT });
  }
  if (!authorized(req)) return json(res, 401, { ok: false, error: 'unauthorized' });

  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  if (req.method === 'GET' && url.pathname === '/api/dc/status') {
    const result = await run('status', 5000);
    return json(res, result.ok ? 200 : 500, result);
  }
  if (req.method === 'GET' && url.pathname === '/api/dc/logs') {
    return json(res, 200, { ok: true, logs: readLogs(url.searchParams.get('lines')) });
  }

  const allowed = ['/api/dc/start', '/api/dc/stop', '/api/dc/restart', '/api/dc/backup', '/api/dc/keepalive'];
  if (req.method === 'POST' && allowed.includes(url.pathname)) {
    const command = url.pathname.split('/').pop();
    const waitMs = ['start', 'restart', 'keepalive'].includes(command) ? 120000 : 30000;
    const result = await run(command, waitMs);
    return json(res, result.ok ? 200 : 500, result);
  }
  return json(res, 404, { ok: false, error: 'not_found' });
});

server.listen(PORT, HOST, () => {
  console.log(`DC control API listening on ${HOST}:${PORT} (authRequired=${AUTH_REQUIRED})`);
});

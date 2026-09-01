import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawn } from 'node:child_process';

const repoDir = path.resolve(path.dirname(new URL(import.meta.url).pathname));
const stateDir = process.env.DESKTOP_COMMANDER_STATE_DIR || path.join(os.homedir(), '.desktop-commander-device');
const stateFile = path.join(stateDir, 'device.json');
const backupDir = path.join(repoDir, '.desktop-commander-backup');
const backupFile = path.join(backupDir, 'device.json');

function copySecure(src, dst) {
  fs.mkdirSync(path.dirname(dst), { recursive: true, mode: 0o700 });
  const tmp = `${dst}.tmp-${process.pid}`;
  fs.copyFileSync(src, tmp);
  fs.chmodSync(tmp, 0o600);
  fs.renameSync(tmp, dst);
}

function backup() {
  if (!fs.existsSync(stateFile)) throw new Error(`Desktop Commander state not found: ${stateFile}`);
  copySecure(stateFile, backupFile);
  console.log(`Backed up session state to ${backupFile}`);
}

function restore() {
  if (!fs.existsSync(backupFile)) {
    console.log('No backup exists yet; starting with current/local auth state.');
    return;
  }
  copySecure(backupFile, stateFile);
  console.log(`Restored session state from ${backupFile}`);
}

function start() {
  restore();
  const child = spawn('npx', ['-y', '@wonderwhy-er/desktop-commander@latest', 'remote', '--persist-session'], {
    cwd: repoDir,
    stdio: 'inherit',
    env: process.env,
  });
  child.on('exit', code => process.exit(code ?? 1));
  child.on('error', err => { console.error(err); process.exit(1); });
}

const command = process.argv[2] || 'start';
if (command === 'backup') backup();
else if (command === 'restore') restore();
else if (command === 'start') start();
else {
  console.error('Usage: node backup-remote-session.js {start|backup|restore}');
  process.exit(2);
}

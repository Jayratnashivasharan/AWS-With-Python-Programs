/* ═══════════════════════════════════════════════════════════════
   app.js — Dashboard JavaScript
   Fetches live data from the API and updates the UI
═══════════════════════════════════════════════════════════════ */

'use strict';

// ─── Utilities ───────────────────────────────────────────────
const $ = (id) => document.getElementById(id);
const logTerminal = $('log-terminal');

function log(msg, type = 'info') {
  const entry = document.createElement('div');
  entry.className = `log-entry log-${type}`;
  const ts = new Date().toLocaleTimeString();
  entry.textContent = `[${ts}] ${msg}`;
  logTerminal.appendChild(entry);
  logTerminal.scrollTop = logTerminal.scrollHeight;
}

function setText(id, val) {
  const el = $(id);
  if (el) el.textContent = val || '—';
}

function truncate(str, n = 40) {
  if (!str || str === 'N/A') return str;
  return str.length > n ? str.slice(0, n) + '…' : str;
}

function formatUptime(seconds) {
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (d > 0) return `${d}d ${h}h ${m}m`;
  if (h > 0) return `${h}h ${m}m ${s}s`;
  return `${m}m ${s}s`;
}

// ─── Fetch App Info ──────────────────────────────────────────
async function fetchInfo() {
  try {
    log('Fetching application info...');
    const res = await fetch('/api/v1/info');
    const { data } = await res.json();

    // Hero
    setText('app-version', data.app.version);
    setText('commit-hash', data.aws.commitHash !== 'N/A'
      ? data.aws.commitHash.slice(0, 8)
      : 'local-dev');
    $('status-text').textContent = 'All systems operational';

    // Cards
    setText('info-env', data.app.environment.toUpperCase());
    setText('info-uptime', formatUptime(data.server.uptime));
    setText('info-region', data.aws.region);

    // Footer
    setText('node-ver', `Node ${data.server.nodeVersion}`);

    // Build/Deploy meta
    setText('build-id', `Build: ${data.aws.buildId !== 'local' ? data.aws.buildId.split(':').pop()?.slice(0,12) : 'local'}`);
    setText('deploy-id', `Deployment: ${data.aws.deploymentId}`);

    log(`App: ${data.app.name} v${data.app.version} on ${data.app.environment}`, 'ok');
  } catch (e) {
    log(`Failed to fetch app info: ${e.message}`, 'error');
  }
}

// ─── Fetch Deployment Info ───────────────────────────────────
async function fetchDeployment() {
  try {
    log('Fetching deployment details...');
    const res = await fetch('/api/v1/deployment');
    const { data } = await res.json();

    setText('docker-image', truncate(data.container.image, 42));
    setText('image-tag', data.container.tag);
    setText('ecr-registry', truncate(data.container.registry, 42));
    setText('codedeploy-app', data.codedeploy.applicationName);
    setText('deploy-group', data.codedeploy.deploymentGroup);

    log('Deployment info loaded.', 'ok');
  } catch (e) {
    log(`Failed to fetch deployment info: ${e.message}`, 'error');
  }
}

// ─── Fetch Metrics ───────────────────────────────────────────
async function fetchMetrics() {
  try {
    const res = await fetch('/api/v1/metrics');
    const { data } = await res.json();
    setText('info-memory', `${data.memory.heapUsed} MB`);
    setText('info-uptime', formatUptime(data.uptime));
  } catch (e) { /* silent */ }
}

// ─── Fetch Deploy Time ───────────────────────────────────────
async function fetchDeployTime() {
  try {
    const res = await fetch('/api/v1/pipeline');
    const { data } = await res.json();
    if (data.lastDeploy) {
      const dt = new Date(data.lastDeploy);
      setText('deploy-time', dt.toLocaleString());
    }
  } catch (e) { /* silent */ }
}

// ─── Health Checks ───────────────────────────────────────────
async function runHealthChecks() {
  log('Running health checks...', 'info');
  const rows = document.querySelectorAll('.health-row[data-endpoint]');

  for (const row of rows) {
    const endpoint = row.dataset.endpoint;
    const badge = row.querySelector('.health-badge');
    badge.className = 'health-badge loading';
    badge.textContent = 'CHECKING';

    try {
      const res = await fetch(endpoint);
      if (res.ok) {
        badge.className = 'health-badge ok';
        badge.textContent = `${res.status} OK`;
        log(`✓ ${endpoint} → ${res.status}`, 'ok');
      } else {
        badge.className = 'health-badge fail';
        badge.textContent = `${res.status} FAIL`;
        log(`✗ ${endpoint} → ${res.status}`, 'warn');
      }
    } catch (e) {
      badge.className = 'health-badge fail';
      badge.textContent = 'ERROR';
      log(`✗ ${endpoint} → ${e.message}`, 'error');
    }

    await new Promise(r => setTimeout(r, 200));
  }

  log('Health checks complete.', 'ok');
}

// ─── API Explorer ────────────────────────────────────────────
async function callApi(path) {
  const label = $('response-label');
  const status = $('response-status');
  const body = $('response-body');
  const copyBtn = $('copy-btn');

  label.textContent = `GET ${path}`;
  status.className = 'response-status loading';
  status.textContent = 'Loading...';
  body.textContent = '// Fetching...';
  copyBtn.style.display = 'none';

  log(`→ GET ${path}`);

  try {
    const start = Date.now();
    const res = await fetch(path);
    const duration = Date.now() - start;
    const json = await res.json();

    status.className = `response-status ${res.ok ? 'ok' : 'fail'}`;
    status.textContent = `${res.status} · ${duration}ms`;

    body.textContent = JSON.stringify(json, null, 2);
    copyBtn.style.display = 'block';

    log(`← ${path} → ${res.status} (${duration}ms)`, res.ok ? 'ok' : 'warn');
  } catch (e) {
    status.className = 'response-status fail';
    status.textContent = 'ERROR';
    body.textContent = `// Error: ${e.message}`;
    log(`← ${path} → ERROR: ${e.message}`, 'error');
  }
}

// ─── Copy Response ────────────────────────────────────────────
function copyResponse() {
  const text = $('response-body').textContent;
  navigator.clipboard.writeText(text).then(() => {
    const btn = $('copy-btn');
    btn.textContent = 'Copied!';
    setTimeout(() => { btn.textContent = 'Copy'; }, 1500);
  });
}

// ─── Clear Logs ───────────────────────────────────────────────
function clearLogs() {
  logTerminal.innerHTML = '';
  log('Log cleared.', 'info');
}

// ─── Footer Clock ────────────────────────────────────────────
function updateClock() {
  setText('footer-time', new Date().toLocaleTimeString());
}

// ─── Nav Active State ─────────────────────────────────────────
function setupNav() {
  const links = document.querySelectorAll('.nav-link');
  const sections = ['overview', 'pipeline', 'metrics', 'logs'];
  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        links.forEach(l => l.classList.remove('active'));
        const match = document.querySelector(`.nav-link[href="#${entry.target.id}"]`);
        if (match) match.classList.add('active');
      }
    });
  }, { threshold: 0.5 });

  sections.forEach(id => {
    const el = document.getElementById(id);
    if (el) observer.observe(el);
  });
}

// ─── Init ─────────────────────────────────────────────────────
async function init() {
  log('Dashboard starting up...');
  setupNav();
  updateClock();
  setInterval(updateClock, 1000);

  await fetchInfo();
  await fetchDeployment();
  await fetchDeployTime();
  await fetchMetrics();
  await runHealthChecks();

  // Auto-refresh metrics every 30s
  setInterval(fetchMetrics, 30000);

  log('Dashboard ready. 🚀', 'ok');
}

document.addEventListener('DOMContentLoaded', init);

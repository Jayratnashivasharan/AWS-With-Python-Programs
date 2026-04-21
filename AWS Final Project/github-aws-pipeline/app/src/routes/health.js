/**
 * routes/health.js - Health Check Endpoints
 * Used by AWS CodeDeploy, Load Balancer, and monitoring tools
 */

'use strict';

const express = require('express');
const router = express.Router();
const os = require('os');

const startTime = Date.now();

/**
 * GET /health
 * Basic health check - returns 200 if app is running
 * Used by AWS ALB target group health checks
 */
router.get('/', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: Math.floor((Date.now() - startTime) / 1000),
  });
});

/**
 * GET /health/detailed
 * Detailed health check with system metrics
 * Used for monitoring and debugging
 */
router.get('/detailed', (req, res) => {
  const uptimeSeconds = Math.floor((Date.now() - startTime) / 1000);
  const memUsage = process.memoryUsage();
  const cpuLoad = os.loadavg();

  res.status(200).json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'development',
    version: process.env.APP_VERSION || 'unknown',
    uptime: {
      seconds: uptimeSeconds,
      human: formatUptime(uptimeSeconds),
    },
    memory: {
      heapUsed: `${Math.round(memUsage.heapUsed / 1024 / 1024)} MB`,
      heapTotal: `${Math.round(memUsage.heapTotal / 1024 / 1024)} MB`,
      rss: `${Math.round(memUsage.rss / 1024 / 1024)} MB`,
      external: `${Math.round(memUsage.external / 1024 / 1024)} MB`,
    },
    system: {
      platform: os.platform(),
      arch: os.arch(),
      cpus: os.cpus().length,
      loadAvg: {
        '1m': cpuLoad[0].toFixed(2),
        '5m': cpuLoad[1].toFixed(2),
        '15m': cpuLoad[2].toFixed(2),
      },
      totalMemory: `${Math.round(os.totalmem() / 1024 / 1024)} MB`,
      freeMemory: `${Math.round(os.freemem() / 1024 / 1024)} MB`,
    },
    process: {
      pid: process.pid,
      nodeVersion: process.version,
    },
  });
});

/**
 * GET /health/ready
 * Readiness probe - checks if app is ready to serve traffic
 * Used by Kubernetes/ECS readiness checks
 */
router.get('/ready', (req, res) => {
  // Add any dependency checks here (DB, cache, etc.)
  const isReady = true;

  if (isReady) {
    res.status(200).json({ status: 'ready', timestamp: new Date().toISOString() });
  } else {
    res.status(503).json({ status: 'not ready', timestamp: new Date().toISOString() });
  }
});

/**
 * GET /health/live
 * Liveness probe - checks if app process is alive
 */
router.get('/live', (req, res) => {
  res.status(200).json({ status: 'alive', timestamp: new Date().toISOString() });
});

// Helper: format uptime as human-readable string
function formatUptime(seconds) {
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const secs = seconds % 60;
  return `${days}d ${hours}h ${minutes}m ${secs}s`;
}

module.exports = router;

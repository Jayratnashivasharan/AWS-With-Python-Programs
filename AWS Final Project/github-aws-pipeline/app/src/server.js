/**
 * server.js - Main Express Application Entry Point
 * GitHub to AWS Deployment Pipeline - Production Ready
 */

'use strict';

const express = require('express');
const path = require('path');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');
const compression = require('compression');

// Load environment variables
require('dotenv').config();

// Import routes
const apiRoutes = require('./routes/api');
const healthRoutes = require('./routes/health');

// Import middleware
const errorHandler = require('./middleware/errorHandler');
const requestLogger = require('./middleware/requestLogger');

// Import config
const config = require('./config/app');

// Initialize Express app
const app = express();

// ─── Security Middleware ────────────────────────────────────────────────────
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'", "'unsafe-inline'"],
      styleSrc: ["'self'", "'unsafe-inline'", "https://fonts.googleapis.com"],
      fontSrc: ["'self'", "https://fonts.gstatic.com"],
      imgSrc: ["'self'", "data:", "https:"],
    },
  },
}));

// ─── General Middleware ─────────────────────────────────────────────────────
app.use(cors({
  origin: config.cors.allowedOrigins,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

app.use(compression());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// ─── Logging ────────────────────────────────────────────────────────────────
if (config.env !== 'test') {
  app.use(morgan(config.env === 'production' ? 'combined' : 'dev'));
}
app.use(requestLogger);

// ─── Static Files ───────────────────────────────────────────────────────────
app.use(express.static(path.join(__dirname, '../public'), {
  maxAge: config.env === 'production' ? '1d' : '0',
  etag: true,
}));

// ─── Routes ─────────────────────────────────────────────────────────────────
app.use('/health', healthRoutes);
app.use('/api/v1', apiRoutes);

// Serve SPA for all other routes
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, '../public/index.html'));
});

// ─── Error Handling ──────────────────────────────────────────────────────────
app.use(errorHandler);

// ─── Start Server ───────────────────────────────────────────────────────────
const PORT = config.port;
const HOST = config.host;

const server = app.listen(PORT, HOST, () => {
  console.log('═══════════════════════════════════════════════════');
  console.log(`  🚀 Server running on http://${HOST}:${PORT}`);
  console.log(`  🌍 Environment: ${config.env}`);
  console.log(`  📦 Version: ${config.version}`);
  console.log(`  ⏰ Started: ${new Date().toISOString()}`);
  console.log('═══════════════════════════════════════════════════');
});

// ─── Graceful Shutdown ───────────────────────────────────────────────────────
const gracefulShutdown = (signal) => {
  console.log(`\n[${signal}] Graceful shutdown initiated...`);
  server.close((err) => {
    if (err) {
      console.error('Error during shutdown:', err);
      process.exit(1);
    }
    console.log('Server closed. Goodbye! 👋');
    process.exit(0);
  });

  // Force shutdown after 10 seconds
  setTimeout(() => {
    console.error('Forced shutdown after timeout');
    process.exit(1);
  }, 10000);
};

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

// Handle unhandled promise rejections
process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
});

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
  console.error('Uncaught Exception:', error);
  process.exit(1);
});

module.exports = app;

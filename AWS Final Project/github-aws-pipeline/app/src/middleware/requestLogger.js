/**
 * middleware/requestLogger.js - Request Logging Middleware
 * Logs all incoming requests with timing information
 */

'use strict';

const requestLogger = (req, res, next) => {
  const startTime = Date.now();
  const requestId = generateRequestId();

  // Attach request ID
  req.requestId = requestId;
  res.setHeader('X-Request-ID', requestId);

  // Log on response finish
  res.on('finish', () => {
    const duration = Date.now() - startTime;
    const logLevel = res.statusCode >= 500 ? 'ERROR' :
                     res.statusCode >= 400 ? 'WARN' : 'INFO';

    console.log(`[${logLevel}] ${new Date().toISOString()} | ` +
      `${req.method} ${req.originalUrl} | ` +
      `${res.statusCode} | ${duration}ms | ` +
      `IP: ${req.ip || req.connection.remoteAddress} | ` +
      `ReqID: ${requestId}`);
  });

  next();
};

function generateRequestId() {
  return `req_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
}

module.exports = requestLogger;

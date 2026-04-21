/**
 * middleware/errorHandler.js - Centralized Error Handler
 * Handles all errors thrown in the application
 */

'use strict';

/**
 * Custom API Error class
 */
class ApiError extends Error {
  constructor(statusCode, message, details = null) {
    super(message);
    this.statusCode = statusCode;
    this.details = details;
    this.isOperational = true;
    Error.captureStackTrace(this, this.constructor);
  }
}

/**
 * Global error handling middleware
 * Must have 4 params for Express to recognize it as error handler
 */
const errorHandler = (err, req, res, next) => {
  let statusCode = err.statusCode || 500;
  let message = err.message || 'Internal Server Error';

  // Log the error
  if (statusCode >= 500) {
    console.error('[ERROR]', {
      timestamp: new Date().toISOString(),
      method: req.method,
      url: req.url,
      statusCode,
      message,
      stack: process.env.NODE_ENV !== 'production' ? err.stack : undefined,
    });
  } else {
    console.warn('[WARN]', {
      timestamp: new Date().toISOString(),
      method: req.method,
      url: req.url,
      statusCode,
      message,
    });
  }

  // Handle specific error types
  if (err.name === 'ValidationError') {
    statusCode = 400;
    message = 'Validation Error';
  }

  if (err.name === 'UnauthorizedError') {
    statusCode = 401;
    message = 'Unauthorized';
  }

  if (err.code === 'ENOENT') {
    statusCode = 404;
    message = 'Resource not found';
  }

  // Send error response
  const errorResponse = {
    success: false,
    error: {
      statusCode,
      message,
      timestamp: new Date().toISOString(),
    },
  };

  // Include stack trace only in development
  if (process.env.NODE_ENV !== 'production' && err.stack) {
    errorResponse.error.stack = err.stack;
  }

  // Include details if available
  if (err.details) {
    errorResponse.error.details = err.details;
  }

  res.status(statusCode).json(errorResponse);
};

module.exports = errorHandler;
module.exports.ApiError = ApiError;

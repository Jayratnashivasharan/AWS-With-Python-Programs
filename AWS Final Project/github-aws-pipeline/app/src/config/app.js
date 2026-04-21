/**
 * config/app.js - Application Configuration
 * Centralizes all environment-based configuration
 */

'use strict';

const config = {
  env: process.env.NODE_ENV || 'development',
  port: parseInt(process.env.PORT, 10) || 3000,
  host: process.env.HOST || '0.0.0.0',
  version: process.env.APP_VERSION || require('../../../package.json').version,

  cors: {
    allowedOrigins: process.env.ALLOWED_ORIGINS
      ? process.env.ALLOWED_ORIGINS.split(',')
      : ['*'],
  },

  aws: {
    region: process.env.AWS_REGION || 'us-east-1',
    accountId: process.env.AWS_ACCOUNT_ID || '',
    ecrRepository: process.env.ECR_REPOSITORY || '',
  },

  logging: {
    level: process.env.LOG_LEVEL || 'info',
  },

  app: {
    name: process.env.APP_NAME || 'AWS Pipeline Demo App',
    description: 'Production-ready Node.js app deployed via AWS CodePipeline',
  },
};

module.exports = config;

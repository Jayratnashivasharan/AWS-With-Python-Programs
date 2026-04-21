/**
 * routes/api.js - Main API Routes
 * RESTful API endpoints for the application
 */

'use strict';

const express = require('express');
const router = express.Router();
const config = require('../config/app');

/**
 * GET /api/v1/
 * API root - returns API info
 */
router.get('/', (req, res) => {
  res.json({
    success: true,
    message: 'Welcome to the AWS Pipeline Demo API',
    version: 'v1',
    timestamp: new Date().toISOString(),
    endpoints: {
      health: '/health',
      info: '/api/v1/info',
      deployment: '/api/v1/deployment',
      pipeline: '/api/v1/pipeline',
    },
  });
});

/**
 * GET /api/v1/info
 * Returns application and deployment information
 */
router.get('/info', (req, res) => {
  res.json({
    success: true,
    data: {
      app: {
        name: config.app.name,
        version: config.version,
        description: config.app.description,
        environment: config.env,
      },
      aws: {
        region: config.aws.region,
        deployedAt: process.env.DEPLOY_TIMESTAMP || 'N/A',
        commitHash: process.env.CODEBUILD_RESOLVED_SOURCE_VERSION || process.env.GIT_COMMIT || 'N/A',
        buildId: process.env.CODEBUILD_BUILD_ID || 'local',
        deploymentId: process.env.DEPLOYMENT_ID || 'local',
      },
      server: {
        nodeVersion: process.version,
        platform: process.platform,
        uptime: Math.floor(process.uptime()),
      },
    },
  });
});

/**
 * GET /api/v1/deployment
 * Returns current deployment details
 */
router.get('/deployment', (req, res) => {
  res.json({
    success: true,
    data: {
      pipeline: {
        name: process.env.PIPELINE_NAME || 'github-aws-pipeline',
        stage: process.env.DEPLOYMENT_STAGE || 'production',
        status: 'active',
      },
      container: {
        image: process.env.DOCKER_IMAGE || 'N/A',
        tag: process.env.IMAGE_TAG || 'latest',
        registry: process.env.ECR_REGISTRY || 'N/A',
      },
      codedeploy: {
        applicationName: process.env.CODEDEPLOY_APP || 'N/A',
        deploymentGroup: process.env.CODEDEPLOY_GROUP || 'N/A',
      },
    },
  });
});

/**
 * GET /api/v1/pipeline
 * Returns CI/CD pipeline stage information
 */
router.get('/pipeline', (req, res) => {
  const stages = [
    {
      name: 'Source',
      provider: 'GitHub',
      status: 'completed',
      description: 'Pull source code from GitHub repository',
    },
    {
      name: 'Build',
      provider: 'AWS CodeBuild',
      status: 'completed',
      description: 'Build Docker image and push to ECR',
    },
    {
      name: 'Deploy',
      provider: 'AWS CodeDeploy',
      status: 'completed',
      description: 'Deploy container to EC2 instances',
    },
  ];

  res.json({
    success: true,
    data: {
      pipeline: stages,
      lastDeploy: process.env.DEPLOY_TIMESTAMP || new Date().toISOString(),
      buildNumber: process.env.CODEBUILD_BUILD_NUMBER || '1',
    },
  });
});

/**
 * POST /api/v1/echo
 * Echo endpoint for testing
 */
router.post('/echo', (req, res) => {
  res.json({
    success: true,
    echo: req.body,
    timestamp: new Date().toISOString(),
  });
});

/**
 * GET /api/v1/metrics
 * Application metrics endpoint
 */
router.get('/metrics', (req, res) => {
  const memUsage = process.memoryUsage();

  res.json({
    success: true,
    data: {
      timestamp: new Date().toISOString(),
      uptime: Math.floor(process.uptime()),
      memory: {
        heapUsed: Math.round(memUsage.heapUsed / 1024 / 1024),
        heapTotal: Math.round(memUsage.heapTotal / 1024 / 1024),
        rss: Math.round(memUsage.rss / 1024 / 1024),
        unit: 'MB',
      },
      cpu: process.cpuUsage(),
    },
  });
});

module.exports = router;

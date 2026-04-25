const path = require('path');

// Load environment variables early
require('dotenv').config({ path: path.join(__dirname, '../../.env') });

const regionMap = {
  0: 'us-east-1',
  1: 'us-east-2',
  2: 'us-west-1',
  3: 'us-west-2',
  4: 'eu-west-1',
  5: 'ap-southeast-1',
  11: 'ap-south-1',
  13: 'eu-central-1',
  16: 'eu-north-1',
};

const config = {
  // Server Config
  port: process.env.PORT || 5000,
  publicUrl: process.env.PUBLIC_URL || 'https://v0c4kk0o0w440k4sk8cwwgs4.admarktech.cloud',
  jwtSecret: process.env.JWT_SECRET || 'your-super-secret-jwt-key',
  jwtExpiry: process.env.JWT_EXPIRY || '1d',
  mongodbUri: process.env.MONGODB_URI,

  // Agora Config
  agora: {
    appId: process.env.AGORA_APP_ID,
    appCertificate: process.env.AGORA_APP_CERTIFICATE,
    customerId: process.env.AGORA_CUSTOMER_ID,
    customerSecret: process.env.AGORA_CUSTOMER_SECRET,
    tokenTtl: 3600
  },

  // S3 / Storage Config
  storage: {
    vendor: Number(process.env.RECORDING_VENDOR || 2),
    region: Number(process.env.RECORDING_REGION || 16),
    bucket: process.env.RECORDING_BUCKET,
    accessKey: process.env.RECORDING_ACCESS_KEY,
    secretKey: process.env.RECORDING_SECRET_KEY,
    awsRegion: regionMap[process.env.RECORDING_REGION] || process.env.AWS_REGION || 'eu-north-1'
  }
};

module.exports = config;

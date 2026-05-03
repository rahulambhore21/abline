const path = require('path');

// Load environment variables early
require('dotenv').config({ path: path.join(__dirname, '../../.env'), override: true });

const regionMap = {
  0: 'us-east-1',
  1: 'us-east-2',
  2: 'us-west-1',
  3: 'us-west-2',
  4: 'eu-west-1',
  5: 'eu-west-2',
  6: 'eu-west-3',
  7: 'eu-central-1',
  8: 'ap-southeast-1',
  9: 'ap-southeast-2',
  10: 'ap-northeast-1',
  11: 'ap-northeast-2',
  12: 'sa-east-1',
  13: 'ca-central-1',
  14: 'ap-south-1',
  15: 'cn-north-1',
  16: 'cn-northwest-1',
  18: 'af-south-1',
  19: 'ap-east-1',
  20: 'ap-northeast-3',
  21: 'eu-north-1',
};

const config = {
  // Server Config
  port: process.env.PORT || 5000,
  publicUrl: process.env.PUBLIC_URL || 'https://v0c4kk0o0w440k4sk8cwwgs4.admarktech.cloud',
  jwtSecret: process.env.JWT_SECRET,
  jwtExpiry: process.env.JWT_EXPIRY || '1d',
  mongodbUri: process.env.MONGODB_URI,

  // Agora Config
  agora: {
    appId: process.env.AGORA_APP_ID,
    appCertificate: process.env.AGORA_APP_CERTIFICATE,
    customerId: process.env.AGORA_CUSTOMER_ID,
    customerSecret: process.env.AGORA_CUSTOMER_SECRET,
    tokenTtl: 3600,
  },

  // S3 / Storage Config
  storage: {
    vendor: Number(process.env.RECORDING_VENDOR || 2),
    region: Number(process.env.RECORDING_REGION || 16),
    bucket: process.env.RECORDING_BUCKET,
    accessKey: process.env.RECORDING_ACCESS_KEY,
    secretKey: process.env.RECORDING_SECRET_KEY,
    // Prioritize explicit AWS_REGION from .env, then map from Agora region number, fallback to eu-north-1
    awsRegion: (
      process.env.AWS_REGION ||
      regionMap[String(process.env.RECORDING_REGION || '').trim()] ||
      'eu-north-1'
    ).trim(),
  },
};

console.log('✅ Config Loaded: Storage Region =', config.storage.awsRegion);

module.exports = config;

#!/usr/bin/env node

/**
 * Recording Test Script
 * Run: node test-recording.js
 *
 * Tests all recording prerequisites:
 * ✓ Agora credentials
 * ✓ AWS storage config
 * ✓ Resource acquisition
 * ✓ Recording start capability
 */

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

const axios = require('axios');
const { RtcTokenBuilder, RtcRole } = require('agora-access-token');

const COLORS = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m',
};

const log = {
  header: (msg) => console.log(`\n${COLORS.cyan}${COLORS.bright}${'='.repeat(70)}${COLORS.reset}\n${COLORS.bright}${msg}${COLORS.reset}\n${COLORS.cyan}${'='.repeat(70)}${COLORS.reset}\n`),
  success: (msg) => console.log(`${COLORS.green}✅ ${msg}${COLORS.reset}`),
  error: (msg) => console.log(`${COLORS.red}❌ ${msg}${COLORS.reset}`),
  warning: (msg) => console.log(`${COLORS.yellow}⚠️  ${msg}${COLORS.reset}`),
  info: (msg) => console.log(`${COLORS.blue}ℹ️  ${msg}${COLORS.reset}`),
  test: (msg) => console.log(`${COLORS.cyan}🧪 ${msg}${COLORS.reset}`),
  detail: (msg) => console.log(`   ${msg}`),
};

async function runTests() {
  log.header('🎬 AGORA RECORDING TEST SUITE');

  const results = {
    passed: 0,
    failed: 0,
    tests: [],
  };

  // ====== TEST 1: Agora Credentials ======
  log.test('TEST 1: Checking Agora Credentials');
  const agoraAppId = process.env.AGORA_APP_ID;
  const agoraAppCert = process.env.AGORA_APP_CERTIFICATE;
  const agoraCustomerId = process.env.AGORA_CUSTOMER_ID;
  const agoraCustomerSecret = process.env.AGORA_CUSTOMER_SECRET;

  if (!agoraAppId || !agoraAppCert || !agoraCustomerId || !agoraCustomerSecret) {
    log.error('Missing Agora credentials');
    if (!agoraAppId) log.detail('AGORA_APP_ID is missing');
    if (!agoraAppCert) log.detail('AGORA_APP_CERTIFICATE is missing');
    if (!agoraCustomerId) log.detail('AGORA_CUSTOMER_ID is missing');
    if (!agoraCustomerSecret) log.detail('AGORA_CUSTOMER_SECRET is missing');
    results.failed++;
    results.tests.push({ name: 'Agora Credentials', status: 'FAILED', reason: 'Missing values in .env' });
  } else {
    log.success('All Agora credentials found');
    log.detail(`App ID: ${agoraAppId.substring(0, 10)}...`);
    log.detail(`Certificate: ${agoraAppCert.substring(0, 10)}...`);
    log.detail(`Customer ID: ${agoraCustomerId.substring(0, 10)}...`);
    results.passed++;
    results.tests.push({ name: 'Agora Credentials', status: 'PASSED' });
  }

  // ====== TEST 2: AWS Storage Config ======
  log.test('\nTEST 2: Checking AWS Storage Configuration');
  const recordingVendor = process.env.RECORDING_VENDOR;
  const recordingRegion = process.env.RECORDING_REGION;
  const recordingBucket = process.env.RECORDING_BUCKET;
  const recordingAccessKey = process.env.RECORDING_ACCESS_KEY;
  const recordingSecretKey = process.env.RECORDING_SECRET_KEY;

  if (!recordingVendor || !recordingRegion === undefined || !recordingBucket || !recordingAccessKey || !recordingSecretKey) {
    log.error('Missing AWS storage configuration');
    if (!recordingVendor) log.detail('RECORDING_VENDOR is missing');
    if (!recordingBucket) log.detail('RECORDING_BUCKET is missing');
    if (!recordingAccessKey) log.detail('RECORDING_ACCESS_KEY is missing');
    if (!recordingSecretKey) log.detail('RECORDING_SECRET_KEY is missing');
    results.failed++;
    results.tests.push({ name: 'AWS Storage Config', status: 'FAILED', reason: 'Missing values in .env' });
  } else {
    log.success('AWS storage configuration found');
    log.detail(`Vendor: ${recordingVendor} (2=AWS S3, 3=Alibaba, 4=Tencent, etc.)`);
    log.detail(`Region: ${recordingRegion}`);
    log.detail(`Bucket: ${recordingBucket}`);
    log.detail(`Access Key: ${recordingAccessKey.substring(0, 12)}...`);
    log.detail(`Secret Key: ${recordingSecretKey.substring(0, 12)}...`);
    results.passed++;
    results.tests.push({ name: 'AWS Storage Config', status: 'PASSED' });
  }

  // ====== TEST 3: Generate Agora Token ======
  log.test('\nTEST 3: Generating Agora RTC Token');
  try {
    const channelName = 'test_room';
    const uid = 12345;
    const currentTimestamp = Math.floor(Date.now() / 1000);
    const privilegeExpire = currentTimestamp + 3600;

    const token = RtcTokenBuilder.buildTokenWithUid(
      agoraAppId,
      agoraAppCert,
      channelName,
      uid,
      RtcRole.PUBLISHER,
      privilegeExpire
    );

    if (!token || token.length === 0) {
      throw new Error('Token generation returned empty');
    }

    log.success('Agora RTC token generated successfully');
    log.detail(`Token: ${token.substring(0, 30)}...${token.substring(token.length - 10)}`);
    log.detail(`Length: ${token.length} characters`);
    results.passed++;
    results.tests.push({ name: 'Agora Token Generation', status: 'PASSED' });
  } catch (error) {
    log.error(`Failed to generate token: ${error.message}`);
    results.failed++;
    results.tests.push({ name: 'Agora Token Generation', status: 'FAILED', reason: error.message });
  }

  // ====== TEST 4: Test Agora Acquire Recording ======
  log.test('\nTEST 4: Testing Agora Cloud Recording Acquire');
  try {
    const channelName = 'test_room';
    const AGORA_RECORDING_API = 'https://api.agora.io/v1/apps';
    const credentials = `${agoraCustomerId}:${agoraCustomerSecret}`;
    const encodedCredentials = Buffer.from(credentials).toString('base64');
    const auth = `Basic ${encodedCredentials}`;

    const url = `${AGORA_RECORDING_API}/${agoraAppId}/cloud_recording/acquire`;
    const payload = {
      cname: channelName,
      uid: '0',
      clientRequest: {},
    };

    log.detail(`Making request to: ${url}`);
    const response = await axios.post(url, payload, {
      headers: {
        Authorization: auth,
        'Content-Type': 'application/json',
      },
      timeout: 10000,
    });

    if (response.status === 200 && response.data.resourceId) {
      log.success('Recording resource acquired successfully');
      log.detail(`Resource ID: ${response.data.resourceId.substring(0, 30)}...`);
      results.passed++;
      results.tests.push({ name: 'Acquire Recording', status: 'PASSED' });
    } else {
      throw new Error(`Unexpected response: ${response.status}`);
    }
  } catch (error) {
    log.error(`Failed to acquire recording: ${error.message}`);
    if (error.response?.data) {
      log.detail(`Response: ${JSON.stringify(error.response.data)}`);
    }
    results.failed++;
    results.tests.push({
      name: 'Acquire Recording',
      status: 'FAILED',
      reason: error.response?.data?.reason || error.message,
      httpStatus: error.response?.status,
    });
  }

  // ====== TEST 5: MongoDB Connection ======
  log.test('\nTEST 5: Checking MongoDB Configuration');
  const mongoUri = process.env.MONGODB_URI;
  if (!mongoUri) {
    log.warning('MongoDB not configured');
    log.detail('Speaking events will be stored in-memory');
    results.tests.push({ name: 'MongoDB Config', status: 'SKIPPED', reason: 'Not configured' });
  } else {
    log.success('MongoDB URI configured');
    log.detail(`URI: ${mongoUri.substring(0, 40)}...`);
    results.tests.push({ name: 'MongoDB Config', status: 'CONFIGURED' });
  }

  // ====== SUMMARY ======
  log.header('📊 TEST SUMMARY');

  console.log(`${COLORS.bright}Test Results:${COLORS.reset}`);
  results.tests.forEach((test, i) => {
    const statusColor =
      test.status === 'PASSED' ? COLORS.green :
      test.status === 'FAILED' ? COLORS.red :
      test.status === 'SKIPPED' ? COLORS.yellow :
      COLORS.cyan;

    console.log(`  ${i + 1}. ${test.name.padEnd(25)} ${statusColor}${test.status.padEnd(10)}${COLORS.reset}`);
    if (test.reason) {
      console.log(`     └─ ${test.reason}`);
    }
  });

  console.log(`\n${COLORS.bright}Summary:${COLORS.reset}`);
  console.log(`  Passed: ${COLORS.green}${results.passed}${COLORS.reset}`);
  console.log(`  Failed: ${COLORS.red}${results.failed}${COLORS.reset}`);

  if (results.failed === 0) {
    log.success('All tests passed! ✨ Recording should work.');
    console.log('\n💡 Next steps:');
    console.log('   1. Start the server: npm start');
    console.log('   2. Login to the admin dashboard');
    console.log('   3. Start a call and click "Start Recording"');
  } else {
    log.error(`${results.failed} test(s) failed.`);
    console.log('\n🔧 Troubleshooting:');
    results.tests.forEach((test) => {
      if (test.status === 'FAILED') {
        console.log(`\n   For "${test.name}": ${test.reason}`);
      }
    });
    console.log('\n💡 Common fixes:');
    console.log('   - Verify backend/.env has all required values');
    console.log('   - Check AWS S3 bucket exists and credentials are valid');
    console.log('   - Confirm Agora account has Cloud Recording enabled');
    console.log('   - Ensure IAM user has S3 full access permissions');
  }

  console.log(`\n${COLORS.cyan}${'='.repeat(70)}${COLORS.reset}\n`);

  process.exit(results.failed > 0 ? 1 : 0);
}

// Run tests
runTests().catch((error) => {
  log.error(`Fatal error: ${error.message}`);
  process.exit(1);
});

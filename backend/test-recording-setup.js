#!/usr/bin/env node
/**
 * Recording Setup Diagnostic Test
 * Run: node test-recording-setup.js
 *
 * This script tests your recording configuration without needing to run the full server.
 */

require('dotenv').config();

console.log('\n' + '='.repeat(70));
console.log('🧪 RECORDING SETUP DIAGNOSTIC TEST');
console.log('='.repeat(70) + '\n');

// Test 1: Check environment variables
console.log('📋 TEST 1: Environment Variables');
console.log('-'.repeat(70));

const requiredVars = {
  'Agora': ['AGORA_APP_ID', 'AGORA_APP_CERTIFICATE', 'AGORA_CUSTOMER_ID', 'AGORA_CUSTOMER_SECRET'],
  'AWS S3': ['RECORDING_VENDOR', 'RECORDING_REGION', 'RECORDING_BUCKET', 'RECORDING_ACCESS_KEY', 'RECORDING_SECRET_KEY'],
  'Database': ['MONGODB_URI']
};

let allVarsPresent = true;

for (const [category, vars] of Object.entries(requiredVars)) {
  console.log(`\n${category}:`);
  for (const varName of vars) {
    const value = process.env[varName];
    if (!value) {
      console.log(`  ❌ ${varName}: NOT SET`);
      allVarsPresent = false;
    } else {
      // Show partial value for security
      const display = value.length > 10
        ? value.substring(0, 5) + '...' + value.substring(value.length - 5)
        : '***';
      console.log(`  ✅ ${varName}: ${display}`);
    }
  }
}

// Test 2: Validate credential values
console.log('\n\n📋 TEST 2: Credential Validation');
console.log('-'.repeat(70));

const placeholders = {
  'your_app_id': 'AGORA_APP_ID',
  'your_app_certificate': 'AGORA_APP_CERTIFICATE',
  'your_customer_id': 'AGORA_CUSTOMER_ID',
  'your_customer_secret': 'AGORA_CUSTOMER_SECRET',
  'your_bucket': 'RECORDING_BUCKET',
  'your_access_key': 'RECORDING_ACCESS_KEY',
  'your_secret_key': 'RECORDING_SECRET_KEY',
};

for (const [placeholder, varName] of Object.entries(placeholders)) {
  const value = process.env[varName];
  if (value && value.toLowerCase().includes(placeholder)) {
    console.log(`  ❌ ${varName}: Still contains placeholder "${placeholder}"`);
    allVarsPresent = false;
  }
}

console.log('  ✅ No placeholder values detected\n');

// Test 3: AWS S3 Configuration
console.log('📋 TEST 3: AWS S3 Configuration');
console.log('-'.repeat(70));

const vendor = Number(process.env.RECORDING_VENDOR);
const region = Number(process.env.RECORDING_REGION);
const bucket = process.env.RECORDING_BUCKET;

console.log(`  Vendor: ${vendor} (2 = AWS S3)`);
console.log(`  Region: ${region}`);
console.log(`  Bucket: ${bucket}`);

if (vendor !== 2) {
  console.log(`  ⚠️  WARNING: Vendor is set to ${vendor}, but code expects 2 (AWS S3)`);
}

if (!bucket || bucket === 'your_bucket') {
  console.log(`  ❌ ERROR: S3 bucket not properly configured`);
  allVarsPresent = false;
} else {
  console.log(`  ✅ Bucket name looks valid`);
}

// Test 4: Check if dependencies are installed
console.log('\n📋 TEST 4: Dependencies');
console.log('-'.repeat(70));

const dependencies = ['axios', 'agora-access-token', 'express-fileupload'];
for (const dep of dependencies) {
  try {
    require.resolve(dep);
    console.log(`  ✅ ${dep}: Installed`);
  } catch (e) {
    console.log(`  ❌ ${dep}: NOT INSTALLED - Run: npm install ${dep}`);
    allVarsPresent = false;
  }
}

// Test 5: Generate test token
console.log('\n📋 TEST 5: Agora Token Generation');
console.log('-'.repeat(70));

try {
  const { RtcTokenBuilder, RtcRole } = require('agora-access-token');

  const appId = process.env.AGORA_APP_ID;
  const cert = process.env.AGORA_APP_CERTIFICATE;
  const channel = 'test_channel';
  const uid = 0;

  const expireTime = Math.floor(Date.now() / 1000) + 3600;

  const token = RtcTokenBuilder.buildTokenWithUid(
    appId,
    cert,
    channel,
    uid,
    RtcRole.PUBLISHER,
    expireTime
  );

  console.log(`  ✅ Token generated successfully`);
  console.log(`     Length: ${token.length} chars`);
} catch (e) {
  console.log(`  ❌ Token generation failed: ${e.message}`);
  allVarsPresent = false;
}

// Summary
console.log('\n' + '='.repeat(70));
if (allVarsPresent) {
  console.log('✅ ALL CHECKS PASSED!');
  console.log('\nNext steps:');
  console.log('1. Make sure your Agora account has CLOUD RECORDING ENABLED');
  console.log('2. Verify AWS S3 bucket exists and is accessible');
  console.log('3. Test recording with: npm run start');
  console.log('4. Then call POST http://localhost:5000/test/recording');
} else {
  console.log('❌ SOME CHECKS FAILED!');
  console.log('\nPlease fix the issues above before testing recordings.');
}
console.log('='.repeat(70) + '\n');

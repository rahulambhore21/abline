require('dotenv').config();
const { uploadToS3 } = require('./src/services/S3Service');
const fs = require('fs');
const path = require('path');

async function testS3() {
  console.log('🧪 Testing S3 Upload...');
  
  const testContent = Buffer.from('This is a test recording file content');
  const testFilename = `test_${Date.now()}.txt`;
  
  try {
    console.log(`📤 Uploading ${testFilename} to S3...`);
    const url = await uploadToS3(testContent, testFilename, 'text/plain');
    console.log(`✅ Upload successful! URL: ${url}`);
    
    // In a real scenario, you'd try to fetch the URL to verify public access,
    // but for now, successful upload is enough to verify credentials.
    
    process.exit(0);
  } catch (error) {
    console.error('❌ S3 Upload failed:');
    console.error(error);
    process.exit(1);
  }
}

testS3();

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });
const { uploadToS3 } = require('./src/services/S3Service');
const fs = require('fs');

async function testS3() {
  console.log('🧪 Testing S3 Upload...');
  
  const testContent = Buffer.from('This is a test recording file content');
  const filename = `test_${Date.now()}.txt`;
  
  try {
    console.log(`📤 Uploading ${filename} to S3...`);
    const url = await uploadToS3(testContent, filename, 'text/plain');
    console.log(`✅ Upload successful! URL: ${url}`);
  } catch (error) {
    console.error('❌ S3 Upload failed:');
    console.error(error);
  }
}

testS3();

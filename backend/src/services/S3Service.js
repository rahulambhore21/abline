const { S3Client, PutObjectCommand, GetObjectCommand } = require('@aws-sdk/client-s3');
const path = require('path');

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

// Prioritize AWS_REGION, then map RECORDING_REGION, then default to us-east-1
const regionCode = process.env.RECORDING_REGION || '0';
const awsRegion = process.env.AWS_REGION || regionMap[regionCode] || 'us-east-1';

const s3Client = new S3Client({
  region: awsRegion,
  credentials: {
    accessKeyId: process.env.RECORDING_ACCESS_KEY,
    secretAccessKey: process.env.RECORDING_SECRET_KEY,
  },
});



/**
 * Uploads a file to S3
 * @param {Buffer|ReadableStream} fileContent 
 * @param {string} filename 
 * @param {string} contentType 
 * @returns {Promise<string>} The public URL of the uploaded file
 */
async function uploadToS3(fileContent, filename, contentType = 'audio/mpeg') {
  const bucket = process.env.RECORDING_BUCKET;
  if (!bucket) {
    throw new Error('RECORDING_BUCKET is not defined in .env');
  }

  console.log(`📡 Preparing S3 upload: Bucket=${bucket}, Region=${awsRegion}, File=${filename}`);

  const command = new PutObjectCommand({
    Bucket: bucket,
    Key: filename,
    Body: fileContent,
    ContentType: contentType,
  });

  try {
    await s3Client.send(command);
    
    // Construct the global S3 URL. 
    // Regional format is more reliable across different AWS regions:
    // https://bucket.s3.region.amazonaws.com/filename
    const url = `https://${bucket}.s3.${awsRegion}.amazonaws.com/${filename}`;
    console.log(`✅ S3 Upload successful: ${url}`);
    return url;
  } catch (error) {
    console.error(`❌ S3 client.send failed: ${error.message}`);
    throw error;
  }
}

/**
 * Gets a file from S3 as a stream
 * @param {string} filename 
 * @returns {Promise<ReadableStream>}
 */
async function getS3FileStream(filename) {
  const bucket = process.env.RECORDING_BUCKET;
  if (!bucket) {
    throw new Error('RECORDING_BUCKET is not defined in .env');
  }

  const command = new GetObjectCommand({
    Bucket: bucket,
    Key: filename,
  });

  const response = await s3Client.send(command);
  return response.Body;
}

module.exports = {
  uploadToS3,
  getS3FileStream,
};


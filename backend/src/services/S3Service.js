const { S3Client, PutObjectCommand, GetObjectCommand } = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const path = require('path');


const config = require('../config');

let _s3Client = null;

function getS3Client() {
  if (_s3Client) return _s3Client;

  const { region, accessKey, secretKey, awsRegion } = config.storage;
  
  console.log(`🛠️  Initializing S3 Client: Region=${awsRegion}`);

  _s3Client = new S3Client({
    region: awsRegion,
    credentials: {
      accessKeyId: accessKey,
      secretAccessKey: secretKey,
    },
  });
  
  return _s3Client;
}



/**
 * Uploads a file to S3
 * @param {Buffer|ReadableStream} fileContent 
 * @param {string} filename 
 * @param {string} contentType 
 * @returns {Promise<string>} The public URL of the uploaded file
 */
async function uploadToS3(fileContent, filename, contentType = 'audio/mpeg') {
  const bucket = process.env.RECORDING_BUCKET;
  if (!bucket) throw new Error('RECORDING_BUCKET is not defined in .env');
  
  const client = getS3Client();
  console.log(`📡 Preparing S3 upload: Bucket=${bucket}, File=${filename}`);

  const command = new PutObjectCommand({
    Bucket: bucket,
    Key: filename,
    Body: fileContent,
    ContentType: contentType,
  });

  try {
    await client.send(command);
    
    const { bucket, awsRegion } = config.storage;
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

  const response = await getS3Client().send(command);
  return response.Body;
}

/**
 * Generates a pre-signed URL for direct upload to S3
 * @param {string} filename 
 * @param {string} contentType 
 * @returns {Promise<string>}
 */
async function getPresignedUrl(filename, contentType = 'audio/mp4') {
  const bucket = process.env.RECORDING_BUCKET;
  const client = getS3Client();

  const command = new PutObjectCommand({
    Bucket: bucket,
    Key: filename,
    ContentType: contentType,
  });

  // URL expires in 15 minutes
  return await getSignedUrl(client, command, { expiresIn: 900 });
}

module.exports = {
  uploadToS3,
  getS3FileStream,
  getPresignedUrl,
};



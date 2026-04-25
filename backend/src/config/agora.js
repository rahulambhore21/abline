const { RtcTokenBuilder, RtcRole } = require('agora-access-token');

const AGORA_APP_ID = process.env.AGORA_APP_ID;
const AGORA_APP_CERTIFICATE = process.env.AGORA_APP_CERTIFICATE;
const AGORA_CUSTOMER_ID = process.env.AGORA_CUSTOMER_ID;
const AGORA_CUSTOMER_SECRET = process.env.AGORA_CUSTOMER_SECRET;

const TOKEN_TTL = 3600;

function createRecordingAuthHeader() {
  const credentials = `${AGORA_CUSTOMER_ID}:${AGORA_CUSTOMER_SECRET}`;
  const encodedCredentials = Buffer.from(credentials).toString('base64');
  return `Basic ${encodedCredentials}`;
}

function validateRecordingCredentials() {
  if (!AGORA_APP_ID || !AGORA_CUSTOMER_ID || !AGORA_CUSTOMER_SECRET) {
    throw new Error(
      'Missing Agora Cloud Recording credentials. Set AGORA_CUSTOMER_ID and AGORA_CUSTOMER_SECRET in backend/.env'
    );
  }

  const placeholderValues = new Set(['your_customer_id', 'your_customer_secret']);
  if (placeholderValues.has(AGORA_CUSTOMER_ID) || placeholderValues.has(AGORA_CUSTOMER_SECRET)) {
    throw new Error(
      'Invalid Agora Cloud Recording credentials: backend/.env still contains placeholder values.'
    );
  }
}

function generateRtcToken(channelName, uid, role = RtcRole.PUBLISHER) {
  const currentTimestamp = Math.floor(Date.now() / 1000);
  const privilegeExpire = currentTimestamp + TOKEN_TTL;
  
  return RtcTokenBuilder.buildTokenWithUid(
    AGORA_APP_ID,
    AGORA_APP_CERTIFICATE,
    channelName,
    uid,
    role,
    privilegeExpire
  );
}

module.exports = {
  AGORA_APP_ID,
  AGORA_APP_CERTIFICATE,
  AGORA_CUSTOMER_ID,
  AGORA_CUSTOMER_SECRET,
  TOKEN_TTL,
  createRecordingAuthHeader,
  validateRecordingCredentials,
  generateRtcToken,
};

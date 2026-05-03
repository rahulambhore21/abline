const axios = require('axios');
const {
  AGORA_APP_ID,
  createRecordingAuthHeader,
  validateRecordingCredentials,
  generateRtcToken,
} = require('../config/agora');
const { RtcRole } = require('agora-access-token');

const ActiveRecording = require('../models/ActiveRecording');
const AGORA_RECORDING_API = 'https://api.agora.io/v1/apps';

// Keep the Map for fast access, but we'll sync it with DB
const activeRecordings = new Map();

/**
 * Initializes active recordings from database on startup
 */
async function initializeActiveRecordings() {
  try {
    const actives = await ActiveRecording.find();
    actives.forEach((a) => {
      activeRecordings.set(a.channelName, {
        resourceId: a.resourceId,
        sid: a.sid,
        channelName: a.channelName,
        userId: a.userId,
        username: a.username,
        mode: a.mode,
        startedAt: a.startedAt,
      });
    });
    console.log(`✅ Loaded ${activeRecordings.size} active recording sessions from database`);

    // Cleanup stale recordings (older than 24h)
    const staleThreshold = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const result = await ActiveRecording.deleteMany({ startedAt: { $lt: staleThreshold } });
    if (result.deletedCount > 0) {
      console.log(`🧹 Cleaned up ${result.deletedCount} stale recording sessions older than 24h`);
    }
  } catch (err) {
    console.error('⚠️ Failed to load active recordings:', err.message);
  }
}

async function acquireRecording(channelName) {
  try {
    validateRecordingCredentials();
    const url = `${AGORA_RECORDING_API}/${AGORA_APP_ID}/cloud_recording/acquire`;
    const payload = {
      cname: channelName,
      uid: '0',
      clientRequest: {},
    };

    console.log(`📤 Acquiring recording for channel: ${channelName}`);

    const response = await axios.post(url, payload, {
      headers: {
        Authorization: createRecordingAuthHeader(),
        'Content-Type': 'application/json',
      },
    });

    if (response.status === 200 && response.data.resourceId) {
      console.log(`✅ Recording acquired. ResourceId: ${response.data.resourceId}`);
      return response.data.resourceId;
    }

    throw new Error('No resourceId returned from acquire API');
  } catch (error) {
    console.error('❌ Acquire recording failed:', error.response?.data || error.message);
    throw new Error(`Failed to acquire recording: ${error.message}`);
  }
}

async function startRecording(channelName, resourceId, userId, username) {
  try {
    validateRecordingCredentials();
    const mode = 'mix';
    const url = `${AGORA_RECORDING_API}/${AGORA_APP_ID}/cloud_recording/resourceid/${resourceId}/mode/${mode}/start`;

    const vendorRaw = process.env.RECORDING_VENDOR;
    const regionRaw = process.env.RECORDING_REGION;
    const vendor = Number(vendorRaw);
    const region = Number(regionRaw);
    const bucket = process.env.RECORDING_BUCKET;
    const accessKey = process.env.RECORDING_ACCESS_KEY;
    const secretKey = process.env.RECORDING_SECRET_KEY;

    if (!bucket || !accessKey || !secretKey) {
      throw new Error('Cloud Recording storage is not configured.');
    }

    const recorderUid = 0;
    const token = generateRtcToken(channelName, recorderUid, RtcRole.PUBLISHER);

    const payload = {
      cname: channelName,
      uid: String(recorderUid),
      clientRequest: {
        token,
        recordingConfig: {
          maxIdleTime: 30,
          streamTypes: 0,
          channelType: 0,
          subscribeUidGroup: 0,
        },
        storageConfig: {
          vendor,
          region,
          bucket,
          accessKey,
          secretKey,
        },
      },
    };

    console.log(`📤 Starting ${mode.toUpperCase()} recording for channel: ${channelName}`);
    console.log(`📦 Storage Config: Bucket=${bucket}, Region=${region}, Vendor=${vendor}`);

    try {
      const response = await axios.post(url, payload, {
        headers: {
          Authorization: createRecordingAuthHeader(),
          'Content-Type': 'application/json',
        },
      });

      if (response.status === 200 && response.data.sid) {
        console.log(`✅ Recording started successfully. SessionId: ${response.data.sid}`);

        const recordingData = {
          resourceId,
          sid: response.data.sid,
          channelName,
          userId,
          username,
          mode,
          startedAt: new Date(),
        };

        activeRecordings.set(channelName, recordingData);

        // Persist to DB
        await ActiveRecording.findOneAndUpdate({ channelName }, recordingData, {
          upsert: true,
          new: true,
        });

        return { resourceId, sid: response.data.sid };
      }

      console.error('⚠️ Agora Start API returned non-200 status:', response.status, response.data);
      throw new Error('No sid returned from start API');
    } catch (apiError) {
      console.error('❌ Agora Start API Call failed:', apiError.response?.data || apiError.message);
      throw apiError;
    }
  } catch (error) {
    console.error('❌ startRecording service error:', error.message);
    throw new Error(`Failed to start recording: ${error.message}`);
  }
}

async function stopRecording(channelName, resourceId, sid, mode = 'mix') {
  try {
    validateRecordingCredentials();
    const url = `${AGORA_RECORDING_API}/${AGORA_APP_ID}/cloud_recording/resourceid/${resourceId}/sid/${sid}/mode/${mode}/stop`;

    const payload = {
      cname: channelName,
      uid: '0',
      clientRequest: {},
    };

    console.log(`📤 Stopping recording for channel: ${channelName}`);

    const response = await axios.post(url, payload, {
      headers: {
        Authorization: createRecordingAuthHeader(),
        'Content-Type': 'application/json',
      },
    });

    if (response.status === 200) {
      console.log(`✅ Recording stopped command sent. Session: ${sid}`);
      // Metadata is kept in DB/Map until webhook confirms file arrival
      return;
    }
  } catch (error) {
    console.error('❌ Stop recording failed:', error.response?.data || error.message);
    throw new Error(`Failed to stop recording: ${error.message}`);
  }
}

module.exports = {
  acquireRecording,
  startRecording,
  stopRecording,
  activeRecordings,
  initializeActiveRecordings,
};

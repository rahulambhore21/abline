require('dotenv').config();
const express = require('express');
const cors = require('cors');
const mongoose = require('mongoose');
const { RtcTokenBuilder, RtcRole } = require('agora-access-token');
const axios = require('axios');

const app = express();
const PORT = process.env.PORT || 5000;

// Middleware
app.use(cors());
app.use(express.json());

// Environment variables
const AGORA_APP_ID = process.env.AGORA_APP_ID;
const AGORA_APP_CERTIFICATE = process.env.AGORA_APP_CERTIFICATE;
const AGORA_CUSTOMER_ID = process.env.AGORA_CUSTOMER_ID;
const AGORA_CUSTOMER_SECRET = process.env.AGORA_CUSTOMER_SECRET;
const MONGODB_URI = process.env.MONGODB_URI;

// Token TTL in seconds (1 hour)
const TOKEN_TTL = 3600;

/**
 * MongoDB (Mongoose)
 *
 * If MONGODB_URI is provided, speaking events are persisted to MongoDB.
 * Otherwise, the server falls back to in-memory storage (useful for local demos).
 */
let mongoReady = false;

const SpeakingEventSchema = new mongoose.Schema(
  {
    userId: { type: Number, required: true, index: true },
    sessionId: { type: Number, required: true, index: true },
    start: { type: Date, required: true },
    end: { type: Date, required: true },
    durationMs: { type: Number, required: true },
  },
  { timestamps: true }
);

const SpeakingEventModel = mongoose.model('SpeakingEvent', SpeakingEventSchema);

/**
 * ============================================================================
 * Agora Cloud Recording Service
 * ============================================================================
 *
 * Manages the complete recording lifecycle:
 * 1. Acquire → Get resourceId for a recording session
 * 2. Start → Begin recording with individual mode and audio-only config
 * 3. Stop → End the recording session
 *
 * Documentation: https://docs.agora.io/en/cloud-recording/reference/rest-api
 */

const AGORA_RECORDING_API = 'https://api.agora.io/v1/apps';
const activeRecordings = new Map(); // Store active recordings in memory

/**
 * Create basic auth header for Agora Cloud Recording API
 * Agora uses HTTP Basic Auth with customerID and customerSecret
 */
function createRecordingAuthHeader() {
  const credentials = `${AGORA_CUSTOMER_ID}:${AGORA_CUSTOMER_SECRET}`;
  const encodedCredentials = Buffer.from(credentials).toString('base64');
  return `Basic ${encodedCredentials}`;
}

/**
 * Validate Agora Cloud Recording credentials
 */
function validateRecordingCredentials() {
  if (!AGORA_APP_ID || !AGORA_CUSTOMER_ID || !AGORA_CUSTOMER_SECRET) {
    throw new Error(
      'Missing Agora Cloud Recording credentials. Ensure AGORA_CUSTOMER_ID and AGORA_CUSTOMER_SECRET are set in .env'
    );
  }
}

/**
 * Step 1: Acquire - Get resourceId for a recording session
 * Must be called before starting a recording.
 */
async function acquireRecording(channelName) {
  try {
    validateRecordingCredentials();
    const url = `${AGORA_RECORDING_API}/${AGORA_APP_ID}/cloud_recording/acquire`;
    const payload = {
      cname: channelName,
      uid: '0', // recorder as anonymous user
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

/**
 * Step 2: Start - Begin recording with INDIVIDUAL mode (audio-only)
 * Each user's audio is recorded separately.
 */
async function startRecording(channelName, resourceId) {
  try {
    validateRecordingCredentials();

    const url = `${AGORA_RECORDING_API}/${AGORA_APP_ID}/cloud_recording/resourceid/${resourceId}/start`;

    // INDIVIDUAL mode = each user's audio recorded separately
    const payload = {
      cname: channelName,
      uid: '0',
      clientRequest: {
        recordingMode: 'individual', // CRITICAL: Use INDIVIDUAL not COMPOSITE
        recordingConfig: {
          maxIdleTime: 30, // Stop after 30s of silence
          streamTypes: 0, // 0 = audio-only (1 = video-only, 2 = audio+video)
          channelType: 0, // 0 = channel mode (default)
          audioProfile: 1, // 1 = 48kHz mono (high quality)
        },
        recordingFileConfig: {
          avFileType: ['hls', 'mp4'],
        },
        // Storage configuration (configure with your actual storage)
        storageConfig: {
          vendor: 0, // 0 = Agora's cloud storage
          region: 0,
          bucket: 'agora-bucket',
          accessKey: 'your-access-key',
          secretKey: 'your-secret-key',
        },
      },
    };

    console.log(`📤 Starting INDIVIDUAL recording for channel: ${channelName}`);

    const response = await axios.post(url, payload, {
      headers: {
        Authorization: createRecordingAuthHeader(),
        'Content-Type': 'application/json',
      },
    });

    if (response.status === 200 && response.data.sid) {
      console.log(`✅ Recording started. SessionId: ${response.data.sid}`);

      // Store active recording
      const recordingKey = `${channelName}`;
      activeRecordings.set(recordingKey, {
        resourceId,
        sid: response.data.sid,
        channelName,
        startedAt: new Date(),
      });

      return {
        resourceId,
        sid: response.data.sid,
      };
    }

    throw new Error('No sessionId returned from start API');
  } catch (error) {
    console.error('❌ Start recording failed:', error.response?.data || error.message);
    throw new Error(`Failed to start recording: ${error.message}`);
  }
}

/**
 * Step 3: Stop - End the recording session
 * Agora will send a webhook callback when files are ready.
 */
async function stopRecording(channelName, resourceId, sid) {
  try {
    validateRecordingCredentials();

    const url = `${AGORA_RECORDING_API}/${AGORA_APP_ID}/cloud_recording/resourceid/${resourceId}/sid/${sid}/stop`;

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
      console.log(`✅ Recording stopped. Session: ${sid}`);
      activeRecordings.delete(channelName);
    }
  } catch (error) {
    console.error('❌ Stop recording failed:', error.response?.data || error.message);
    throw new Error(`Failed to stop recording: ${error.message}`);
  }
}

/**
 * Get active recording info
 */
function getActiveRecording(channelName) {
  return activeRecordings.get(channelName) || null;
}

/**
 * Get all active recordings
 */
function getAllActiveRecordings() {
  return Array.from(activeRecordings.values());
}

async function connectMongo() {
  if (!MONGODB_URI) {
    console.warn('⚠️ MONGODB_URI not set. Speaking events will be stored in-memory.');
    return;
  }

  try {
    await mongoose.connect(MONGODB_URI, {
      serverSelectionTimeoutMS: 5000,
    });
    mongoReady = true;
    console.log('✅ MongoDB connected. Speaking events will be persisted.');
  } catch (err) {
    mongoReady = false;
    console.error('❌ MongoDB connection failed. Falling back to in-memory events.', err);
  }
}


/**
 * Health check endpoint
 */
app.get('/health', (req, res) => {
  res.json({ status: 'ok', message: 'Server is running' });
});

/**
 * GET /agora/token
 * Generate Agora RTC token
 * Query params:
 *   - channelName (required): Channel to join
 *   - uid (required): User ID
 * Response:
 *   {
 *     token: "...",
 *     appId: "...",
 *     channelName: "...",
 *     uid: ...
 *   }
 */
app.get('/',(req, res) => {
  res.send("backend is running");
})

app.get('/agora/token', (req, res) => {
  try {
    const { channelName, uid } = req.query;

    // Validate required parameters
    if (!channelName) {
      return res.status(400).json({
        error: 'Missing required parameter: channelName',
      });
    }

    if (!uid) {
      return res.status(400).json({
        error: 'Missing required parameter: uid',
      });
    }

    // Validate uid is a valid number
    const uidNumber = parseInt(uid, 10);
    if (isNaN(uidNumber) || uidNumber < 0) {
      return res.status(400).json({
        error: 'uid must be a valid non-negative number',
      });
    }

    // Validate environment variables
    if (!AGORA_APP_ID || !AGORA_APP_CERTIFICATE) {
      console.error('Missing Agora credentials in environment variables');
      return res.status(500).json({
        error: 'Server misconfiguration: Missing Agora credentials',
      });
    }

    // Generate token
    // NOTE: The Agora SDK expects an absolute expiry timestamp (in seconds), not a TTL.
    const currentTimestamp = Math.floor(Date.now() / 1000);
    const privilegeExpire = currentTimestamp + TOKEN_TTL;

    const token = RtcTokenBuilder.buildTokenWithUid(
      AGORA_APP_ID,
      AGORA_APP_CERTIFICATE,
      channelName,
      uidNumber,
      RtcRole.PUBLISHER,
      privilegeExpire
    );

    // Return token and metadata
    res.json({
      token,
      appId: AGORA_APP_ID,
      channelName,
      uid: uidNumber,
      expireAt: privilegeExpire,
      ttl: TOKEN_TTL,
    });
  } catch (error) {
    console.error('Error generating Agora token:', error);
    res.status(500).json({
      error: 'Failed to generate token',
    });
  }
});

/**
 * ============================================================================
 * Recording Endpoints
 * ============================================================================
 */

/**
 * POST /recording/start
 * Initiates a recording session (acquire → start flow)
 *
 * Request body:
 * {
 *   channelName: string,
 *   uid: number
 * }
 *
 * Response:
 * {
 *   resourceId: string,
 *   sid: string
 * }
 */
app.post('/recording/start', async (req, res) => {
  try {
    const { channelName, uid } = req.body;

    // Validate input
    if (!channelName || uid === undefined) {
      return res.status(400).json({
        error: 'Missing required fields: channelName, uid',
      });
    }

    console.log(`🎬 Starting recording for channel: ${channelName}, uid: ${uid}`);

    // Step 1: Acquire resourceId
    const resourceId = await acquireRecording(channelName);

    // Step 2: Start recording (INDIVIDUAL mode, audio-only)
    const { sid } = await startRecording(channelName, resourceId);

    // Return both IDs for later reference
    res.status(201).json({
      resourceId,
      sid,
      message: 'Recording started successfully',
    });
  } catch (error) {
    console.error('Error starting recording:', error);
    res.status(500).json({
      error: error.message || 'Failed to start recording',
    });
  }
});

/**
 * POST /recording/stop
 * Stops an active recording session
 *
 * Request body:
 * {
 *   channelName: string,
 *   uid: number,
 *   resourceId: string,
 *   sid: string
 * }
 *
 * Response:
 * {
 *   success: boolean
 * }
 */
app.post('/recording/stop', async (req, res) => {
  try {
    const { channelName, uid, resourceId, sid } = req.body;

    // Validate input
    if (!channelName || !resourceId || !sid) {
      return res.status(400).json({
        error: 'Missing required fields: channelName, resourceId, sid',
      });
    }

    console.log(`⏹️  Stopping recording for channel: ${channelName}, uid: ${uid}`);

    // Call Agora stop API
    await stopRecording(channelName, resourceId, sid);

    res.status(200).json({
      success: true,
      message: 'Recording stopped successfully',
    });
  } catch (error) {
    console.error('Error stopping recording:', error);
    res.status(500).json({
      error: error.message || 'Failed to stop recording',
    });
  }
});

/**
 * POST /recording/webhook
 * Receives recording completion callbacks from Agora
 *
 * This endpoint is called by Agora when:
 * - Recording is complete
 * - Files are ready for download
 * - Errors occur during recording
 *
 * Callback payload contains:
 * {
 *   resourceId: string,
 *   sid: string,
 *   cname: string,
 *   fileList: [{
 *     filename: string,     // e.g., "uid_123_audio.m4a"
 *     trackType: string,    // "audio", "video", etc.
 *     uid: number,
 *     mixedAllUser: boolean,
 *     isPlayable: boolean,
 *     sliceStartTime: number
 *   }],
 *   ...
 * }
 */
app.post('/recording/webhook', async (req, res) => {
  try {
    const payload = req.body;

    console.log('📡 Received recording webhook callback');
    console.log('Payload:', JSON.stringify(payload, null, 2));

    // Extract key information from webhook
    const { resourceId, sid, cname, fileList } = payload;

    if (!fileList || fileList.length === 0) {
      console.warn('⚠️  No files in webhook payload');
      return res.status(200).json({ status: 'processed' });
    }

    // Process each recorded file
    for (const file of fileList) {
      const { filename, trackType, uid } = file;

      // Extract user ID from filename if available
      // Typical format: "uid_<uid>_<stream_type>.m4a" or "uid_<uid>_audio.m4a"
      const uidMatch = filename.match(/uid_(\d+)/);
      const userId = uidMatch ? uidMatch[1] : uid;

      console.log(`✅ Recording file ready: ${filename}`);
      console.log(`   - User ID: ${userId}`);
      console.log(`   - Track Type: ${trackType}`);
      console.log(`   - Channel: ${cname}`);

      // TODO: Store recording metadata in MongoDB
      // Example schema for RecordingFile:
      // {
      //   userId,
      //   sessionId: cname, // channel name
      //   filename,
      //   trackType,
      //   fileUrl: `https://cdn.agora.io/${filename}`,
      //   resourceId,
      //   sid,
      //   recordedAt: new Date(),
      // }
    }

    // Acknowledge receipt of webhook
    res.status(200).json({
      status: 'processed',
      message: 'Recording webhook processed successfully',
    });
  } catch (error) {
    console.error('Error processing webhook:', error);
    // Always return 200 to acknowledge receipt
    res.status(200).json({
      status: 'processed',
      error: error.message,
    });
  }
});

/**
 * GET /recording/active
 * Get all active recordings (for debugging)
 */
app.get('/recording/active', (req, res) => {
  try {
    const recordings = getAllActiveRecordings();
    res.json({
      count: recordings.length,
      recordings,
    });
  } catch (error) {
    console.error('Error fetching active recordings:', error);
    res.status(500).json({
      error: 'Failed to fetch active recordings',
    });
  }
});

/**
 * Error handling middleware
 */
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({
    error: 'Internal server error',
  });
});

/**
 * Speaking events storage (fallback when MongoDB is not configured)
 */

/**
 * POST /events/speaking
 * Record a completed speaking event
 * Body:
 *   {
 *     userId: number,
 *     sessionId: number,
 *     start: ISO8601 timestamp,
 *     end: ISO8601 timestamp
 *   }
 * Response:
 *   {
 *     success: true,
 *     eventId: string,
 *     message: string
 *   }
 */
app.post('/events/speaking', async (req, res) => {
  try {
    const { userId, sessionId, start, end } = req.body;

    // Validate required fields
    if (!userId || !sessionId || !start || !end) {
      return res.status(400).json({
        error: 'Missing required fields: userId, sessionId, start, end',
      });
    }

    // Validate timestamp format (Date() never throws; must check for Invalid Date)
    const startMs = Date.parse(start);
    const endMs = Date.parse(end);
    if (Number.isNaN(startMs) || Number.isNaN(endMs)) {
      return res.status(400).json({
        error: 'Invalid timestamp format. Use ISO8601 format.',
      });
    }

    // Create event object
    const event = {
      id: `evt_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      userId,
      sessionId,
      start: new Date(start),
      end: new Date(end),
      duration: new Date(end) - new Date(start),
      recordedAt: new Date(),
    };

    let persistedId = event.id;

    if (mongoReady) {
      const saved = await SpeakingEventModel.create({
        userId: Number(userId),
        sessionId: Number(sessionId),
        start: new Date(start),
        end: new Date(end),
        durationMs: new Date(end) - new Date(start),
      });
      persistedId = saved._id.toString();
    } else {
      // Fallback: store in-memory
      speakingEvents.push(event);
    }

    console.log(
      `📝 Speaking event recorded: User ${userId} spoke for ${Math.round(event.duration / 1000)}s` +
          (mongoReady ? ' (MongoDB)' : ' (memory)')
    );

    res.status(201).json({
      success: true,
      eventId: persistedId,
      message: `Speaking event recorded for user ${userId}`,
      event: {
        userId: Number(userId),
        sessionId: Number(sessionId),
        duration: Math.round(event.duration / 1000), // in seconds
      },
    });
  } catch (error) {
    console.error('Error recording speaking event:', error);
    res.status(500).json({
      error: 'Failed to record speaking event',
    });
  }
});

/**
 * GET /events/speaking
 * Retrieve all speaking events (for debugging/analytics)
 * Query params:
 *   - userId (optional): Filter by user ID
 *   - sessionId (optional): Filter by session ID
 * Response:
 *   {
 *     total: number,
 *     events: [...]
 *   }
 */
app.get('/events/speaking', async (req, res) => {
  try {
    const { userId, sessionId } = req.query;

    if (mongoReady) {
      const filter = {};
      if (userId) filter.userId = Number(userId);
      if (sessionId) filter.sessionId = Number(sessionId);

      const docs = await SpeakingEventModel.find(filter)
        .sort({ start: 1 })
        .lean();

      return res.json({
        total: docs.length,
        events: docs.map((d) => ({
          id: d._id.toString(),
          userId: d.userId,
          sessionId: d.sessionId,
          start: new Date(d.start).toISOString(),
          end: new Date(d.end).toISOString(),
          duration: Math.round((d.durationMs ?? 0) / 1000),
          recordedAt: d.createdAt ? new Date(d.createdAt).toISOString() : undefined,
        })),
        source: 'mongodb',
      });
    }

    // Fallback: in-memory events
    let events = speakingEvents;

    if (userId) {
      events = events.filter((e) => Number(e.userId) === Number(userId));
    }

    if (sessionId) {
      events = events.filter((e) => Number(e.sessionId) === Number(sessionId));
    }

    return res.json({
      total: events.length,
      events: events.map((e) => ({
        id: e.id,
        userId: Number(e.userId),
        sessionId: Number(e.sessionId),
        start: new Date(e.start).toISOString(),
        end: new Date(e.end).toISOString(),
        duration: Math.round((e.duration ?? 0) / 1000),
        recordedAt: e.recordedAt ? new Date(e.recordedAt).toISOString() : undefined,
      })),
      source: 'memory',
    });
  } catch (error) {
    console.error('Error retrieving speaking events:', error);
    return res.status(500).json({
      error: 'Failed to retrieve speaking events',
    });
  }
});

/**
 * 404 handler
 */
app.use((req, res) => {
  res.status(404).json({
    error: 'Endpoint not found',
  });
});

// Start server (connect to Mongo first, then listen)
connectMongo().finally(() => {
  app.listen(PORT, () => {
    console.log(`✅ Agora RTC Token Server running on http://localhost:${PORT}`);
    console.log(`📍 Token endpoint: GET /agora/token?channelName=<name>&uid=<id>`);
    console.log(`📍 Speaking events: POST /events/speaking`);
    console.log(`📍 Speaking events: GET /events/speaking`);
    console.log(`📍 Recording endpoints:`);
    console.log(`   - POST /recording/start (start INDIVIDUAL mode recording)`);
    console.log(`   - POST /recording/stop (stop recording)`);
    console.log(`   - POST /recording/webhook (Agora callback)`);
    console.log(`   - GET /recording/active (list active recordings)`);
  });
});

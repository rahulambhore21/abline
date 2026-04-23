require('dotenv').config();
const express = require('express');
const cors = require('cors');
const mongoose = require('mongoose');
const { RtcTokenBuilder, RtcRole } = require('agora-access-token');
const axios = require('axios');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const fileUpload = require('express-fileupload');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 5000;

// Middleware
app.use(cors());
app.use(express.json());
app.use(fileUpload()); // ✅ NEW: Enable file upload for recording save endpoint

// Environment variables
const AGORA_APP_ID = process.env.AGORA_APP_ID;
const AGORA_APP_CERTIFICATE = process.env.AGORA_APP_CERTIFICATE;
const AGORA_CUSTOMER_ID = process.env.AGORA_CUSTOMER_ID;
const AGORA_CUSTOMER_SECRET = process.env.AGORA_CUSTOMER_SECRET;
const MONGODB_URI = process.env.MONGODB_URI;
const JWT_SECRET = process.env.JWT_SECRET || 'your-super-secret-key-change-in-production';
const JWT_EXPIRY = process.env.JWT_EXPIRY || '1d';
const PUBLIC_URL = process.env.PUBLIC_URL || `http://localhost:${PORT}`; // ✅ NEW: Public URL for deployed backend

// Fail fast when MongoDB is not connected instead of buffering queries for ~10s.
// This prevents confusing timeouts like: "Operation users.findOne() buffering timed out".
mongoose.set('bufferCommands', false);

function ensureMongoForAuth(res) {
  const isConfigured = Boolean(MONGODB_URI && String(MONGODB_URI).trim());
  const isConnected = mongoose.connection?.readyState === 1;

  if (!isConfigured) {
    res.status(503).json({
      error: 'MongoDB not configured',
      message:
        'Authentication requires MongoDB. Set MONGODB_URI in backend/.env (e.g. mongodb://127.0.0.1:27017/agora) and restart the server.',
    });
    return false;
  }

  if (!isConnected) {
    res.status(503).json({
      error: 'MongoDB not connected',
      message:
        'MongoDB is configured but not reachable. Start MongoDB (or fix MONGODB_URI) and restart the server.',
    });
    return false;
  }

  return true;
}

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
    sessionId: { type: String, required: true, index: true },
    start: { type: Date, required: true, index: true }, // ✅ OPTIMIZATION: Index for date queries
    end: { type: Date, required: true },
    durationMs: { type: Number, required: true },
  },
  { timestamps: true }
);

// ✅ OPTIMIZATION: Compound index for efficient querying by session and user
SpeakingEventSchema.index({ sessionId: 1, userId: 1, start: -1 });

const SpeakingEventModel = mongoose.model('SpeakingEvent', SpeakingEventSchema);

/**
 * ============================================================================
 * User Model for Authentication & Role-Based Access Control
 * ============================================================================
 *
 * Supports two roles:
 * - "host": Can create users, start/stop recordings, view dashboards
 * - "user": Normal participants in voice calls
 *
 * Passwords are hashed using bcryptjs before storage.
 */
const UserSchema = new mongoose.Schema(
  {
    username: {
      type: String,
      required: [true, 'Username is required'],
      unique: true,
      trim: true,
      minlength: [3, 'Username must be at least 3 characters'],
      index: true, // ✅ OPTIMIZATION: Index for faster lookups
    },
    password: {
      type: String,
      required: [true, 'Password is required'],
      minlength: [6, 'Password must be at least 6 characters'],
      select: false, // Don't return password in queries
    },
    role: {
      type: String,
      enum: ['host', 'user'],
      default: 'user',
      required: true,
      index: true, // ✅ OPTIMIZATION: Index for role-based queries
    },
  },
  { timestamps: true }
);

// ✅ OPTIMIZATION: Compound index for username + role queries
UserSchema.index({ username: 1, role: 1 });

// Hash password before saving
UserSchema.pre('save', async function (next) {
  if (!this.isModified('password')) {
    return next();
  }
  try {
    const salt = await bcrypt.genSalt(10);
    this.password = await bcrypt.hash(this.password, salt);
    next();
  } catch (error) {
    next(error);
  }
});

// Method to compare passwords during login
UserSchema.methods.comparePassword = async function (plainPassword) {
  return await bcrypt.compare(plainPassword, this.password);
};

const UserModel = mongoose.model('User', UserSchema);

/**
 * ============================================================================
 * Recording Model for MongoDB Persistence
 * ============================================================================
 * Stores recording metadata so recordings survive server restarts
 */
const RecordingSchema = new mongoose.Schema(
  {
    recordingId: { type: String, required: true, unique: true, index: true },
    userId: { type: Number, required: true, index: true },
    sessionId: { type: String, required: true, index: true },
    filename: { type: String, required: true },
    recordedAt: { type: Date, default: Date.now, index: true },
    durationMs: { type: Number, default: 0 },
    url: { type: String }, // Public URL for downloading
  },
  { timestamps: true }
);

// ✅ OPTIMIZATION: Compound index for efficient querying by session and user
RecordingSchema.index({ sessionId: 1, userId: 1, recordedAt: -1 });

const RecordingModel = mongoose.model('Recording', RecordingSchema);

/**
 * ============================================================================
 * Authentication Middleware
 * ============================================================================
 *
 * JWT Authentication Flow:
 * 1. Client logs in with username/password → Server issues JWT
 * 2. JWT contains: userId, username, role, expiry
 * 3. Client includes JWT in "Authorization: Bearer <token>" header
 * 4. authMiddleware extracts & verifies JWT
 * 5. If valid, attaches user info to req.user and proceeds
 * 6. If invalid/expired, returns 401 Unauthorized
 */
const authMiddleware = (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({
        error: 'Missing or invalid Authorization header',
        message: 'Expected format: Authorization: Bearer <token>',
      });
    }

    const token = authHeader.slice(7);
    const decoded = jwt.verify(token, JWT_SECRET);

    req.user = {
      userId: decoded.userId,
      username: decoded.username,
      role: decoded.role,
    };

    next();
  } catch (error) {
    if (error.name === 'JsonWebTokenError') {
      return res.status(401).json({
        error: 'Invalid token',
        message: 'JWT verification failed',
      });
    }

    if (error.name === 'TokenExpiredError') {
      return res.status(401).json({
        error: 'Token expired',
        message: 'Please login again',
      });
    }

    res.status(401).json({
      error: 'Authentication failed',
      message: error.message,
    });
  }
};

/**
 * Role-Based Access Control Middleware
 *
 * Restricts access based on user role.
 * Usage: app.post('/protected', authMiddleware, allowRole('host'), handler)
 *
 * Only allows users with specified roles.
 */
const allowRole = (...allowedRoles) => {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({
        error: 'Not authenticated',
        message: 'Please login first',
      });
    }

    if (!allowedRoles.includes(req.user.role)) {
      return res.status(403).json({
        error: 'Forbidden',
        message: `This action requires one of these roles: ${allowedRoles.join(', ')}`,
        yourRole: req.user.role,
      });
    }

    next();
  };
};


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
 * In-memory session storage for demo purposes
 * Structure: Map<sessionId, { sessionId, users: Map<userId, {userId, username, isSpeaking}> }>
 * ✅ OPTIMIZATION: Added cleanup mechanism for inactive sessions
 */
const activeSessions = new Map();
const SESSION_TIMEOUT_MS = 24 * 60 * 60 * 1000; // 24 hours

/**
 * ✅ OPTIMIZATION: Cleanup inactive sessions to prevent memory leak
 */
function cleanupInactiveSessions() {
  const now = Date.now();
  const sessionsToDelete = [];

  for (const [sessionId, session] of activeSessions.entries()) {
    // Remove sessions that have been stopped for > 24 hours
    if (session.stoppedAt) {
      const timeSinceStopped = now - new Date(session.stoppedAt).getTime();
      if (timeSinceStopped > SESSION_TIMEOUT_MS) {
        sessionsToDelete.push(sessionId);
      }
    }
    // Remove sessions with 0 users that haven't been active
    else if (session.users.size === 0 && !session.isActive) {
      sessionsToDelete.push(sessionId);
    }
  }

  for (const sessionId of sessionsToDelete) {
    activeSessions.delete(sessionId);
  }

  if (sessionsToDelete.length > 0) {
    console.log(`🧹 Cleaned up ${sessionsToDelete.length} inactive sessions`);
  }
}

// ✅ OPTIMIZATION: Run cleanup every hour
setInterval(cleanupInactiveSessions, 60 * 60 * 1000);

/**
 * ✅ NEW: In-memory recordings storage with disk persistence
 * Structure: Map<recordingId, { id, userId, sessionId, url, recordedAt, filename }>
 * ✅ OPTIMIZATION: Added file-based persistence for server restarts
 */
const recordingsStorage = new Map();
const MAX_RECORDINGS = 500; // Limit to 500 recordings in memory
const RECORDINGS_METADATA_FILE = path.join(__dirname, '.recordings-metadata.json');

/**
 * ✅ NEW: Load recordings from MongoDB on startup
 */
async function loadRecordingsFromDatabase() {
  if (!mongoReady) {
    console.warn('⚠️ MongoDB not ready - skipping database recording load');
    return;
  }

  try {
    const count = await RecordingModel.countDocuments();
    if (count > 0) {
      console.log(`📂 Found ${count} recordings in MongoDB`);

      // Load into memory cache for fast access
      const recordings = await RecordingModel.find().lean();
      for (const rec of recordings) {
        recordingsStorage.set(rec.recordingId, {
          recordingId: rec.recordingId,
          userId: rec.userId,
          sessionId: rec.sessionId,
          filename: rec.filename,
          url: rec.url || `${PUBLIC_URL}/recordings/download/${rec.recordingId}`,
          recordedAt: rec.recordedAt,
          durationMs: rec.durationMs,
        });
      }
      console.log(`✅ Loaded ${recordings.length} recordings into memory cache`);
    }
  } catch (error) {
    console.error('⚠️ Error loading recordings from MongoDB:', error.message);
  }
}

/**
 * ✅ NEW: Load recordings metadata from disk on startup
 */
function loadRecordingsFromDisk() {
  try {
    if (fs.existsSync(RECORDINGS_METADATA_FILE)) {
      const data = JSON.parse(fs.readFileSync(RECORDINGS_METADATA_FILE, 'utf8'));
      console.log(`📂 Loaded ${data.length} recordings from disk`);
      for (const recording of data) {
        // ✅ FIXED: Ensure URLs are absolute when loading from disk
        if (recording.url && !recording.url.startsWith('http')) {
          recording.url = `${PUBLIC_URL}/recordings/download/${recording.id}`;
        }
        recordingsStorage.set(recording.id, recording);
      }
    }
  } catch (e) {
    console.error('⚠️ Error loading recordings from disk:', e.message);
  }
}

/**
 * ✅ NEW: Save recordings metadata to disk for persistence
 */
function saveRecordingsToDisk() {
  try {
    const data = Array.from(recordingsStorage.values());
    fs.writeFileSync(RECORDINGS_METADATA_FILE, JSON.stringify(data, null, 2), 'utf8');
  } catch (e) {
    console.error('⚠️ Error saving recordings to disk:', e.message);
  }
}

/**
 * ✅ OPTIMIZATION: Cleanup old recordings to prevent memory leak
 */
function cleanupOldRecordings() {
  if (recordingsStorage.size > MAX_RECORDINGS) {
    // Convert to array, sort by date, keep most recent
    const recordings = Array.from(recordingsStorage.entries());
    recordings.sort((a, b) => new Date(b[1].recordedAt) - new Date(a[1].recordedAt));

    recordingsStorage.clear();
    recordings.slice(0, MAX_RECORDINGS).forEach(([id, rec]) => {
      recordingsStorage.set(id, rec);
    });

    saveRecordingsToDisk(); // ✅ NEW: Persist after cleanup
    console.log(`🧹 Cleaned up old recordings. Kept ${recordingsStorage.size} most recent.`);
  }
}

/**
 * In-memory speaking events (fallback when MongoDB is not configured)
 * ✅ OPTIMIZATION: Added size limit to prevent unbounded growth
 */
let speakingEvents = [];
const MAX_SPEAKING_EVENTS = 1000; // Limit to 1000 events in memory

/**
 * ✅ OPTIMIZATION: Cleanup old speaking events to prevent memory leak
 */
function cleanupOldSpeakingEvents() {
  if (speakingEvents.length > MAX_SPEAKING_EVENTS) {
    // Keep only the most recent events
    speakingEvents = speakingEvents.slice(-MAX_SPEAKING_EVENTS);
    console.log(`🧹 Cleaned up old speaking events. Kept ${speakingEvents.length} most recent.`);
  }
}

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
      'Missing Agora Cloud Recording credentials. Set AGORA_CUSTOMER_ID and AGORA_CUSTOMER_SECRET in backend/.env'
    );
  }

  // Catch the common case where .env contains placeholders.
  const placeholderValues = new Set(['your_customer_id', 'your_customer_secret']);
  if (placeholderValues.has(AGORA_CUSTOMER_ID) || placeholderValues.has(AGORA_CUSTOMER_SECRET)) {
    throw new Error(
      'Invalid Agora Cloud Recording credentials: backend/.env still contains placeholder values. ' +
        'Replace AGORA_CUSTOMER_ID / AGORA_CUSTOMER_SECRET with real values from the Agora Console.'
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

    // Agora Cloud Recording start route MUST include /mode/{mode}/start
    // Common modes: "individual" (separate tracks per user) and "mix".
    const mode = 'mix';  // ✅ Changed to MIX mode - simpler, all audio combined
    const url = `${AGORA_RECORDING_API}/${AGORA_APP_ID}/cloud_recording/resourceid/${resourceId}/mode/${mode}/start`;

    // Cloud Recording generally requires uploading to your own cloud storage.
    // Configure these in backend/.env (do NOT hardcode secrets).
    const vendorRaw = process.env.RECORDING_VENDOR;
    const regionRaw = process.env.RECORDING_REGION;

    const vendor = Number(vendorRaw);
    const region = Number(regionRaw);
    const bucket = process.env.RECORDING_BUCKET;
    const accessKey = process.env.RECORDING_ACCESS_KEY;
    const secretKey = process.env.RECORDING_SECRET_KEY;

    const missingStorage =
      vendorRaw === undefined ||
      regionRaw === undefined ||
      bucket === undefined ||
      accessKey === undefined ||
      secretKey === undefined;

    const invalidStorage =
      Number.isNaN(vendor) ||
      vendor <= 0 ||
      Number.isNaN(region) ||
      region < 0 ||
      bucket.trim().length === 0 ||
      accessKey.trim().length === 0 ||
      secretKey.trim().length === 0;

    const placeholderStorage =
      bucket === 'your_bucket' ||
      accessKey === 'your_access_key' ||
      secretKey === 'your_secret_key';

    if (missingStorage || invalidStorage || placeholderStorage) {
      throw new Error(
        'Cloud Recording storage is not configured. Set valid values for RECORDING_VENDOR, RECORDING_REGION, RECORDING_BUCKET, RECORDING_ACCESS_KEY, RECORDING_SECRET_KEY in backend/.env'
      );
    }

    // If your channel uses tokens (this app does), Cloud Recording should also join with a valid RTC token.
    const currentTimestamp = Math.floor(Date.now() / 1000);
    const privilegeExpire = currentTimestamp + TOKEN_TTL;
    const recorderUid = 0;
    const token = RtcTokenBuilder.buildTokenWithUid(
      AGORA_APP_ID,
      AGORA_APP_CERTIFICATE,
      channelName,
      recorderUid,
      RtcRole.PUBLISHER,
      privilegeExpire
    );

    const payload = {
      cname: channelName,
      uid: String(recorderUid),
      clientRequest: {
        token,
        recordingConfig: {
          maxIdleTime: 30,
          streamTypes: 0, // audio-only
          channelType: 0,
          subscribeUidGroup: 0, // 0 = subscribe all
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
    console.log('📋 Recording payload:', JSON.stringify(payload, null, 2));

    const response = await axios.post(url, payload, {
      headers: {
        Authorization: createRecordingAuthHeader(),
        'Content-Type': 'application/json',
      },
    });

    if (response.status === 200 && response.data.sid) {
      console.log(`✅ Recording started. SessionId: ${response.data.sid}`);

      // Store active recording so /recording/stop can work with channelName only.
      activeRecordings.set(channelName, {
        resourceId,
        sid: response.data.sid,
        channelName,
        mode,
        startedAt: new Date(),
      });

      return {
        resourceId,
        sid: response.data.sid,
      };
    }

    throw new Error('No sid returned from start API');
  } catch (error) {
    console.error('❌ Start recording failed:', error.response?.data || error.message);
    console.error('🔍 Full error details:', {
      status: error.response?.status,
      statusText: error.response?.statusText,
      data: error.response?.data,
      message: error.message,
    });
    throw new Error(`Failed to start recording: ${error.message}`);
  }
}

/**
 * Stop an active recording (mode-aware route)
 */
async function stopRecording(channelName, resourceId, sid, mode = 'individual') {
  try {
    validateRecordingCredentials();

    // Stop route MUST include /mode/{mode}/stop
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
      console.log(`✅ Recording stopped. Session: ${sid}`);
      activeRecordings.delete(channelName);
      return;
    }
  } catch (error) {
    console.error('❌ Stop recording failed:', error.response?.data || error.message);
    console.error('🔍 Error details:', {
      status: error.response?.status,
      errorCode: error.response?.data?.code,
      reason: error.response?.data?.reason,
      channelName,
      sid,
      resourceId,
      mode: mode || 'N/A',
    });
    throw new Error(`Failed to stop recording: ${error.message}`);
  }
}

/**
 * Step 3: Stop - End the recording session
 * Agora will send a webhook callback when files are ready.
 */
// stopRecording is implemented above (mode-aware)

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
    console.warn(
      '⚠️ MONGODB_URI not set. Speaking events will be stored in-memory. Authentication endpoints will return 503 until MongoDB is configured.'
    );
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
 * ============================================================================
 * Authentication & Authorization Routes
 * ============================================================================
 */

/**
 * POST /auth/register-host
 * Create the first host user (should only work if no host exists)
 * 
 * Body:
 *   {
 *     username: string,
 *     password: string
 *   }
 *
 * Response:
 *   {
 *     success: true,
 *     userId: string,
 *     message: string
 *   }
 */
app.post('/auth/register-host', async (req, res) => {
  try {
    if (!ensureMongoForAuth(res)) return;

    const { username, password } = req.body;

    if (!username || !password) {
      return res.status(400).json({
        error: 'Missing required fields: username, password',
      });
    }

    // Check if a host already exists
    const existingHost = await UserModel.findOne({ role: 'host' });
    if (existingHost) {
      return res.status(400).json({
        error: 'Host user already exists',
        message: 'A host user has already been registered',
      });
    }

    // Create new host user (password will be hashed by pre-save middleware)
    const host = new UserModel({
      username,
      password,
      role: 'host',
    });

    await host.save();

    console.log(`✅ Host user created: ${username}`);

    res.status(201).json({
      success: true,
      userId: host._id,
      message: `Host '${username}' created successfully`,
    });
  } catch (error) {
    console.error('Error registering host:', error);

    // Handle duplicate username error from MongoDB
    if (error.code === 11000) {
      return res.status(400).json({
        error: 'Username already taken',
      });
    }

    res.status(500).json({
      error: error.message || 'Failed to register host',
    });
  }
});

/**
 * POST /auth/create-user
 * Create a normal user (host only)
 *
 * Protected: Requires host role via allowRole middleware
 *
 * Body:
 *   {
 *     username: string,
 *     password: string
 *   }
 *
 * Response:
 *   {
 *     success: true,
 *     userId: string,
 *     message: string
 *   }
 */
app.post('/auth/create-user', authMiddleware, allowRole('host'), async (req, res) => {
  try {
    if (!ensureMongoForAuth(res)) return;

    const { username, password } = req.body;

    if (!username || !password) {
      return res.status(400).json({
        error: 'Missing required fields: username, password',
      });
    }

    // Create new user with "user" role
    const user = new UserModel({
      username,
      password,
      role: 'user',
    });

    await user.save();

    console.log(`✅ User created by host ${req.user.username}: ${username}`);

    res.status(201).json({
      success: true,
      userId: user._id,
      message: `User '${username}' created successfully`,
    });
  } catch (error) {
    console.error('Error creating user:', error);

    if (error.code === 11000) {
      return res.status(400).json({
        error: 'Username already taken',
      });
    }

    res.status(500).json({
      error: error.message || 'Failed to create user',
    });
  }
});

/**
 * GET /users
 * List all users (host-only)
 * 
 * Returns:
 *   {
 *     success: true,
 *     users: [
 *       { id, username, role, createdAt },
 *       ...
 *     ]
 *   }
 */
app.get('/users', authMiddleware, allowRole('host'), async (req, res) => {
  try {
    if (!ensureMongoForAuth(res)) return;

    // ✅ OPTIMIZATION: Use lean() for faster queries (returns plain JS objects)
    const users = await UserModel.find().select('_id username role createdAt').lean();

    res.json({
      success: true,
      users: users.map(u => ({
        id: u._id,
        username: u.username,
        role: u.role,
        createdAt: u.createdAt,
      })),
      count: users.length,
    });
  } catch (error) {
    console.error('Error fetching users:', error);
    res.status(500).json({
      error: 'Failed to fetch users',
      message: error.message,
    });
  }
});

/**
 * POST /auth/login
 * Authenticate user and return JWT token
 *
 * JWT Token Contents (payload):
 *   - userId: User's MongoDB ID
 *   - username: Username for display
 *   - role: "host" or "user" (used for authorization)
 *   - exp: Expiration time (1 day from now)
 *
 * Token is signed with JWT_SECRET from .env
 * Client stores token and includes it in "Authorization: Bearer <token>"
 *
 * Body:
 *   {
 *     username: string,
 *     password: string
 *   }
 *
 * Response:
 *   {
 *     token: string,
 *     role: string,
 *     userId: string,
 *     username: string,
 *     expiresIn: string
 *   }
 */
app.post('/auth/login', async (req, res) => {
  try {
    if (!ensureMongoForAuth(res)) return;

    const { username, password } = req.body;

    if (!username || !password) {
      return res.status(400).json({
        error: 'Missing required fields: username, password',
      });
    }

    // Find user by username; include password field (normally excluded)
    const user = await UserModel.findOne({ username }).select('+password');

    if (!user) {
      return res.status(401).json({
        error: 'Invalid credentials',
        message: 'Username not found',
      });
    }

    // Use comparePassword method to safely verify password
    const isPasswordValid = await user.comparePassword(password);

    if (!isPasswordValid) {
      return res.status(401).json({
        error: 'Invalid credentials',
        message: 'Incorrect password',
      });
    }

    // Generate JWT token
    // Payload: user info that will be verified later
    // Secret: JWT_SECRET from .env
    // Expiry: JWT_EXPIRY (default 1 day)
    const token = jwt.sign(
      {
        userId: user._id,
        username: user.username,
        role: user.role,
      },
      JWT_SECRET,
      { expiresIn: JWT_EXPIRY }
    );

    console.log(`✅ User logged in: ${username} (role: ${user.role})`);

    res.json({
      success: true,
      token,
      role: user.role,
      userId: user._id.toString(), // ✅ FIXED: Convert ObjectId to string
      username: user.username,
      expiresIn: JWT_EXPIRY,
      message: 'Login successful',
    });
  } catch (error) {
    console.error('Error during login:', error);
    res.status(500).json({
      error: error.message || 'Login failed',
    });
  }
});

/**
 * Health check endpoint
 */
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    message: 'Server is running',
    mongo: {
      configured: Boolean(MONGODB_URI && String(MONGODB_URI).trim()),
      readyState: mongoose.connection?.readyState ?? 0,
      connected: mongoose.connection?.readyState === 1,
    },
  });
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
 * Protected: Requires host role (via authMiddleware + allowRole)
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
 *   sid: string,
 *   message: string
 * }
 */
app.post('/recording/start', authMiddleware, allowRole('host'), async (req, res) => {
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

    // If Agora returns 401, surface it as an auth/config error.
    const status = error.response?.status;
    if (status === 401) {
      return res.status(401).json({
        error:
          'Agora Cloud Recording authentication failed (401). Check AGORA_CUSTOMER_ID / AGORA_CUSTOMER_SECRET in backend/.env.',
        details: error.response?.data,
      });
    }

    // Storage misconfig is a client/config error.
    if ((error.message || '').includes('Cloud Recording storage is not configured')) {
      return res.status(400).json({
        error: error.message,
      });
    }

    // Bubble Agora HTTP status when available (helps debugging 404 route mismatches, 400 payload issues, etc.)
    if (status) {
      return res.status(status).json({
        error: error.message || 'Failed to start recording',
        details: error.response?.data,
      });
    }

    res.status(500).json({
      error: error.message || 'Failed to start recording',
      details: error.response?.data,
    });
  }
});

/**
 * POST /recording/stop
 * Stops an active recording session
 * 
 * Protected: Requires host role
 *
 * Request body:
 * {
 *   channelName: string,
 *   uid?: number,
 *   resourceId?: string,
 *   sid?: string
 * }
 *
 * Response:
 * {
 *   success: boolean,
 *   message: string
 * }
 */
app.post('/recording/stop', authMiddleware, allowRole('host'), async (req, res) => {
  try {
    const { channelName, uid, resourceId, sid } = req.body;

    if (!channelName) {
      return res.status(400).json({
        error: 'Missing required field: channelName',
      });
    }

    console.log(`⏹️  Stopping recording for channel: ${channelName}, uid: ${uid}`);

    // Allow stopping with only channelName by looking up the active recording.
    let resolvedResourceId = resourceId;
    let resolvedSid = sid;
    let resolvedMode = 'mix'; // ✅ Changed from 'individual' to match recording mode

    if (!resolvedResourceId || !resolvedSid) {
      const active = getActiveRecording(channelName);
      if (!active) {
        return res.status(400).json({
          error: `No active recording found for channel: ${channelName}`,
        });
      }
      resolvedResourceId = active.resourceId;
      resolvedSid = active.sid;
      resolvedMode = active.mode || 'mix'; // ✅ Default to 'mix'
    }

    await stopRecording(channelName, resolvedResourceId, resolvedSid, resolvedMode);

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

    // ✅ FIXED: Use proper null/undefined checks instead of falsy checks
    // (userId can be 0, which is falsy but valid)
    if (userId === null || userId === undefined) {
      return res.status(400).json({
        error: 'Missing required field: userId',
        received: { userId, sessionId, start, end },
      });
    }
    if (!sessionId) {
      return res.status(400).json({
        error: 'Missing required field: sessionId',
        received: { userId, sessionId, start, end },
      });
    }
    if (!start) {
      return res.status(400).json({
        error: 'Missing required field: start',
        received: { userId, sessionId, start, end },
      });
    }
    if (!end) {
      return res.status(400).json({
        error: 'Missing required field: end',
        received: { userId, sessionId, start, end },
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
        sessionId: String(sessionId),
        start: new Date(start),
        end: new Date(end),
        durationMs: new Date(end) - new Date(start),
      });
      persistedId = saved._id.toString();
    } else {
      // Fallback: store in-memory
      speakingEvents.push(event);
      cleanupOldSpeakingEvents(); // ✅ OPTIMIZATION: Cleanup to prevent memory leak
    }

    console.log(
      `✅ Speaking event recorded: User ${userId} spoke for ${Math.round(event.duration / 1000)}s` +
          (mongoReady ? ' (MongoDB)' : ' (memory)')
    );

    res.status(201).json({
      success: true,
      eventId: persistedId,
      message: `Speaking event recorded for user ${userId}`,
      event: {
        userId: Number(userId),
        sessionId: String(sessionId),
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
      if (sessionId) filter.sessionId = String(sessionId);

      const docs = await SpeakingEventModel.find(filter)
        .sort({ start: 1 })
        .lean();

      return res.json({
        total: docs.length,
        events: docs.map((d) => ({
          id: d._id.toString(),
          userId: d.userId,
          sessionId: String(d.sessionId),
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
      events = events.filter((e) => String(e.sessionId) === String(sessionId));
    }

    return res.json({
      total: events.length,
      events: events.map((e) => ({
        id: e.id,
        userId: Number(e.userId),
        sessionId: String(e.sessionId),
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
 * ============================================================================
 * Session & Users Endpoints
 * ============================================================================
 */

/**
 * POST /session/:id/users/add
 * Register a user as joining a session
 * Body:
 *   {
 *     userId: number,
 *     username: string,
 *     role: string (optional: 'host' or 'user')
 *   }
 */
app.post('/session/:id/users/add', (req, res) => {
  try {
    const { id: sessionId } = req.params;
    const { userId, username, role } = req.body;

    // ✅ FIXED: Use proper null/undefined checks (userId can be 0)
    if (userId === null || userId === undefined || !username) {
      return res.status(400).json({
        error: 'Missing required fields: userId, username',
      });
    }

    // Get or create session
    if (!activeSessions.has(sessionId)) {
      activeSessions.set(sessionId, {
        sessionId,
        users: new Map(),
        isActive: false,
        startedAt: null,
        stoppedAt: null,
        hostUid: null, // ✅ Track host UID for selective audio subscription
      });
    }

    const session = activeSessions.get(sessionId);

    // ✅ Track host UID if this user is a host
    if (role === 'host') {
      session.hostUid = userId;
      console.log(`👑 Host joined session ${sessionId} with UID: ${userId}`);
    }

    session.users.set(userId, {
      userId,
      username,
      isSpeaking: false,
      role: role || 'user', // ✅ Store user role
    });

    res.status(200).json({
      success: true,
      message: `User ${userId} added to session ${sessionId}`,
      hostUid: session.hostUid, // ✅ Return host UID for client-side filtering
    });
  } catch (error) {
    console.error('Error adding user to session:', error);
    res.status(500).json({
      error: 'Failed to add user to session',
    });
  }
});

/**
 * GET /session/:id/users
 * Fetch all users in a session with their speaking status
 */
app.get('/session/:id/users', (req, res) => {
  try {
    const { id: sessionId } = req.params;
    const session = activeSessions.get(sessionId);

    if (!session) {
      return res.json({
        sessionId,
        users: [],
        total: 0,
        hostUid: null, // ✅ Return null if no session
      });
    }

    const users = Array.from(session.users.values()).map((user) => ({
      userId: user.userId,
      username: user.username,
      isSpeaking: user.isSpeaking,
      role: user.role || 'user', // ✅ Include role information
    }));

    res.json({
      sessionId,
      users,
      total: users.length,
      hostUid: session.hostUid, // ✅ Return host UID for client-side audio filtering
    });
  } catch (error) {
    console.error('Error fetching session users:', error);
    res.status(500).json({
      error: 'Failed to fetch session users',
    });
  }
});

/**
 * POST /session/:id/start
 * Start a session (host marks session as live)
 * 
 * Protected: Requires host role
 */
app.post('/session/:id/start', authMiddleware, allowRole('host'), async (req, res) => {
  try {
    const { id: sessionId } = req.params;

    console.log(`🔍 Session start request:`, {
      sessionId,
      user: req.user?.username,
      role: req.user?.role,
    });

    // Get or create session
    if (!activeSessions.has(sessionId)) {
      activeSessions.set(sessionId, {
        sessionId,
        users: new Map(),
        startedAt: new Date(),
        isActive: true,
        recordingResourceId: null,
        recordingSid: null,
        recordingActive: false,
      });
    } else {
      const session = activeSessions.get(sessionId);
      session.isActive = true;
      session.startedAt = new Date();
    }

    console.log(`✅ Session ${sessionId} started by host ${req.user.username}`);

    // ✅ NEW: Automatically start Agora Cloud Recording
    try {
      const session = activeSessions.get(sessionId);
      console.log(`🎬 Starting automatic Cloud Recording for session ${sessionId}...`);

      // Step 1: Acquire resource ID
      const resourceId = await acquireRecording(sessionId);
      session.recordingResourceId = resourceId;

      // Step 2: Start recording
      const recordingData = await startRecording(sessionId, resourceId);
      session.recordingSid = recordingData.sid;
      session.recordingActive = true;

      console.log(`✅ Automatic Cloud Recording started! SID: ${recordingData.sid}`);
    } catch (recordingError) {
      console.error('⚠️ Failed to start automatic recording (continuing without it):', recordingError.message);
      // Don't fail the session start if recording fails - just log it
    }

    res.status(200).json({
      success: true,
      sessionId,
      message: 'Session started successfully (automatic recording enabled)',
      startedAt: activeSessions.get(sessionId).startedAt,
      recordingActive: activeSessions.get(sessionId).recordingActive,
    });
  } catch (error) {
    console.error('Error starting session:', error);
    res.status(500).json({
      error: 'Failed to start session',
      message: error.message,
    });
  }
});

/**
 * POST /session/:id/stop
 * Stop a session (host marks session as no longer live)
 * 
 * Protected: Requires host role
 */
app.post('/session/:id/stop', authMiddleware, allowRole('host'), async (req, res) => {
  try {
    const { id: sessionId } = req.params;

    if (!activeSessions.has(sessionId)) {
      return res.status(404).json({
        error: 'Session not found',
        sessionId,
      });
    }

    const session = activeSessions.get(sessionId);
    session.isActive = false;
    session.stoppedAt = new Date();

    console.log(`⏹️ Session ${sessionId} stopped by host ${req.user.username}`);

    // ✅ NEW: Automatically stop Agora Cloud Recording
    if (session.recordingActive && session.recordingSid) {
      try {
        console.log(`🎬 Stopping automatic Cloud Recording for session ${sessionId}...`);
        await stopRecording(sessionId, session.recordingResourceId, session.recordingSid, 'mix');
        session.recordingActive = false;
        console.log(`✅ Cloud Recording stopped!`);
      } catch (recordingError) {
        console.error('⚠️ Error stopping recording (continuing anyway):', recordingError.message);
        // Don't fail session stop even if recording stop fails
      }
    }

    res.status(200).json({
      success: true,
      sessionId,
      message: 'Session stopped successfully',
      stoppedAt: session.stoppedAt,
    });
  } catch (error) {
    console.error('Error stopping session:', error);
    res.status(500).json({
      error: 'Failed to stop session',
      message: error.message,
    });
  }
});

/**
 * GET /session/:id/status
 * Get the current status of a session (active or not)
 */
app.get('/session/:id/status', (req, res) => {
  try {
    const { id: sessionId } = req.params;
    const session = activeSessions.get(sessionId);

    if (!session) {
      return res.json({
        sessionId,
        isActive: false,
        users: 0,
      });
    }

    res.json({
      sessionId,
      isActive: session.isActive || false,
      startedAt: session.startedAt,
      stoppedAt: session.stoppedAt,
      users: session.users.size,
    });
  } catch (error) {
    console.error('Error fetching session status:', error);
    res.status(500).json({
      error: 'Failed to fetch session status',
    });
  }
});

/**
 * ============================================================================
 * Recordings Endpoints
 * ============================================================================
 */

/**
 * GET /recordings
 * Fetch recordings for a session
 * Query params:
 *   - sessionId (optional): Filter by session ID
 *   - userId (optional): Filter by user ID
 */
app.get('/recordings', async (req, res) => {
  try {
    let { sessionId, userId } = req.query;

    if (mongoReady) {
      // ✅ NEW: Query from MongoDB for persistent storage
      const filter = {};
      if (sessionId) filter.sessionId = sessionId;

      // ✅ FIXED: Only filter by userId if it's a valid number (not NaN)
      if (userId && !isNaN(parseInt(userId))) {
        filter.userId = Number(userId);
      }

      const recordings = await RecordingModel.find(filter)
        .sort({ recordedAt: -1 })
        .lean();

      return res.json({
        total: recordings.length,
        recordings: recordings.map((r) => ({
          id: r.recordingId,
          userId: r.userId,
          sessionId: r.sessionId,
          filename: r.filename,
          url: r.url || `${PUBLIC_URL}/recordings/download/${r.recordingId}`,
          recordedAt: r.recordedAt,
          durationMs: r.durationMs,
        })),
      });
    }

    // Fallback: Use in-memory storage
    let recordings = Array.from(recordingsStorage.values());
    if (sessionId) {
      recordings = recordings.filter((r) => r.sessionId === sessionId);
    }
    if (userId && !isNaN(parseInt(userId))) {
      recordings = recordings.filter((r) => r.userId === Number(userId));
    }

    recordings.sort((a, b) => new Date(b.recordedAt) - new Date(a.recordedAt));

    res.json({
      total: recordings.length,
      recordings: recordings.map((r) => ({
        id: r.recordingId,
        userId: r.userId,
        sessionId: r.sessionId,
        filename: r.filename,
        url: r.url || `${PUBLIC_URL}/recordings/download/${r.recordingId}`,
        recordedAt: r.recordedAt,
        durationMs: r.durationMs,
      })),
    });
  } catch (error) {
    console.error('Error fetching recordings:', error);
    res.status(500).json({
      error: 'Failed to fetch recordings',
    });
  }
});

/**
 * ✅ NEW: POST /recordings/save
 * Save audio file uploaded from Flutter app (hold-to-speak recording)
 * Multipart FormData:
 *   - audioFile: binary audio file
 *   - userId: number
 *   - sessionId: string
 *   - durationMs: number
 */
app.post('/recordings/save', async (req, res) => {
  try {
    console.log('📥 Recording upload request received');
    console.log('   Body:', req.body);
    console.log('   Files:', req.files ? Object.keys(req.files) : 'NONE');

    const { userId, sessionId, durationMs } = req.body;
    const audioFile = req.files?.audioFile;

    // Detailed validation logging
    // ✅ FIXED: Use proper null/undefined checks (userId can be 0)
    if (userId === null || userId === undefined) {
      console.error('❌ Missing: userId');
      return res.status(400).json({
        error: 'Missing required fields: userId',
        received: { userId, sessionId, hasFile: !!audioFile },
      });
    }
    if (!sessionId) {
      console.error('❌ Missing: sessionId');
      return res.status(400).json({
        error: 'Missing required fields: sessionId',
        received: { userId, sessionId, hasFile: !!audioFile },
      });
    }
    if (!audioFile) {
      console.error('❌ Missing: audioFile');
      console.error('   Available files:', req.files ? Object.keys(req.files) : 'NONE');
      return res.status(400).json({
        error: 'Missing required fields: audioFile',
        received: { userId, sessionId, hasFile: !!audioFile },
        availableFiles: req.files ? Object.keys(req.files) : [],
      });
    }

    console.log(`✅ All fields received - Starting save process`);
    console.log(`   User: ${userId}, Session: ${sessionId}, Duration: ${durationMs}ms`);
    console.log(`   File size: ${audioFile.size} bytes`);

    // Generate unique filename
    const recordingId = `rec_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const filename = `${recordingId}.m4a`;

    // For now, store locally in a recordings folder (in production, use S3)
    const recordingsDir = path.join(__dirname, 'recordings');
    if (!fs.existsSync(recordingsDir)) {
      console.log(`📁 Creating recordings directory: ${recordingsDir}`);
      fs.mkdirSync(recordingsDir, { recursive: true });
    }

    const filePath = path.join(recordingsDir, filename);

    // Save file locally
    console.log(`💾 Saving file to: ${filePath}`);
    await audioFile.mv(filePath);
    console.log(`✅ File saved successfully`);

    // Verify file exists
    if (!fs.existsSync(filePath)) {
      throw new Error('File was not saved to disk');
    }
    const fileSize = fs.statSync(filePath).size;
    console.log(`✓ File verified - Size: ${fileSize} bytes`);

    // Store recording metadata in MongoDB
    const recording = {
      recordingId,
      userId: Number(userId),
      sessionId,
      filename,
      url: `${PUBLIC_URL}/recordings/download/${recordingId}`, // ✅ FIXED: Use PUBLIC_URL
      recordedAt: new Date(),
      durationMs: Number(durationMs) || 0,
    };

    try {
      // ✅ NEW: Save to MongoDB for persistence across server restarts
      if (mongoReady) {
        await RecordingModel.create(recording);
        console.log(`✅ Recording metadata saved to MongoDB`);
      } else {
        // Fallback: Store in memory if MongoDB is not ready
        recordingsStorage.set(recordingId, recording);
        saveRecordingsToDisk();
        console.log(`⚠️  MongoDB not ready - storing in memory`);
      }
    } catch (dbError) {
      console.error('⚠️  Error saving to MongoDB, falling back to memory:', dbError.message);
      recordingsStorage.set(recordingId, recording);
      saveRecordingsToDisk();
    }

    // Also keep in-memory cache for fast access
    recordingsStorage.set(recordingId, recording);
    cleanupOldRecordings(); // ✅ OPTIMIZATION: Cleanup to prevent memory leak

    console.log(`✅ Recording saved: User ${userId}, Session ${sessionId}, Duration ${durationMs}ms, ID: ${recordingId}`);

    res.status(201).json({
      success: true,
      recordingId,
      url: recording.url,
      message: `Recording saved for user ${userId}`,
    });
  } catch (error) {
    console.error('❌ Error saving recording:', error.message);
    console.error('   Stack:', error.stack);
    res.status(500).json({
      error: 'Failed to save recording',
      message: error.message,
    });
  }
});

/**
 * ✅ NEW: GET /recordings/user/:userId
 * Get all recordings for a specific user in a session
 * Query params: ?sessionId=test_room
 *
 * ✅ FIXED: Now reads from MongoDB to survive server restarts
 */
app.get('/recordings/user/:userId', async (req, res) => {
  try {
    const userIdParam = req.params.userId;
    const { sessionId } = req.query;

    // ✅ FIXED: Validate userId is a valid number
    const userId = Number(userIdParam);
    if (isNaN(userId)) {
      console.warn(`⚠️  Invalid userId: ${userIdParam} (NaN)`);
      return res.json({
        total: 0,
        recordings: [],
        warning: `Invalid user ID: ${userIdParam}`,
      });
    }

    console.log(`📋 Fetching recordings for userId: ${userId}, sessionId: ${sessionId}`);

    let recordings = [];

    if (mongoReady) {
      // ✅ NEW: Query from MongoDB for persistent storage
      const filter = { userId };
      if (sessionId) {
        filter.sessionId = sessionId;
      }

      const dbRecordings = await RecordingModel.find(filter)
        .sort({ recordedAt: -1 })
        .lean();

      recordings = dbRecordings.map(r => ({
        id: r.recordingId,
        userId: r.userId,
        sessionId: r.sessionId,
        filename: r.filename,
        url: r.url || `${PUBLIC_URL}/recordings/download/${r.recordingId}`,
        recordedAt: r.recordedAt,
        durationMs: r.durationMs,
      }));

      console.log(`✅ Found ${recordings.length} recordings from MongoDB`);
    } else {
      // Fallback: Use in-memory storage if MongoDB is not ready
      let storageRecordings = Array.from(recordingsStorage.values());
      storageRecordings = storageRecordings.filter(r => r.userId === userId);
      if (sessionId) {
        storageRecordings = storageRecordings.filter(r => r.sessionId === sessionId);
      }
      storageRecordings.sort((a, b) => new Date(b.recordedAt) - new Date(a.recordedAt));

      recordings = storageRecordings.map(r => ({
        id: r.recordingId,
        userId: r.userId,
        sessionId: r.sessionId,
        filename: r.filename,
        url: r.url || `${PUBLIC_URL}/recordings/download/${r.recordingId}`,
        recordedAt: r.recordedAt,
        durationMs: r.durationMs,
      }));

      console.log(`⚠️  Using in-memory storage - Found ${recordings.length} recordings`);
    }

    res.json({
      total: recordings.length,
      recordings,
    });
  } catch (error) {
    console.error('Error fetching user recordings:', error);
    res.status(500).json({
      error: 'Failed to fetch user recordings',
    });
  }
});

/**
 * ✅ NEW: GET /recordings/session/:sessionId
 * Get all recordings for a session, organized by user (admin view)
 * Requires: host role
 */
app.get('/recordings/session/:sessionId', authMiddleware, allowRole('host'), async (req, res) => {
  try {
    const sessionId = req.params.sessionId;

    let recordings = [];

    if (mongoReady) {
      // ✅ NEW: Query from MongoDB for persistent storage
      const dbRecordings = await RecordingModel.find({ sessionId })
        .sort({ recordedAt: -1 })
        .lean();

      recordings = dbRecordings.map(r => ({
        id: r.recordingId,
        userId: r.userId,
        sessionId: r.sessionId,
        filename: r.filename,
        url: r.url || `${PUBLIC_URL}/recordings/download/${r.recordingId}`,
        recordedAt: r.recordedAt,
        durationMs: r.durationMs,
      }));
    } else {
      // Fallback: Use in-memory storage
      let storageRecordings = Array.from(recordingsStorage.values());
      storageRecordings = storageRecordings.filter(r => r.sessionId === sessionId);
      storageRecordings.sort((a, b) => new Date(b.recordedAt) - new Date(a.recordedAt));

      // Map to consistent format
      recordings = storageRecordings.map(r => ({
        id: r.recordingId,
        userId: r.userId,
        sessionId: r.sessionId,
        filename: r.filename,
        url: r.url || `${PUBLIC_URL}/recordings/download/${r.recordingId}`,
        recordedAt: r.recordedAt,
        durationMs: r.durationMs,
      }));
    }

    // Group by userId
    const byUser = {};
    recordings.forEach(r => {
      if (!byUser[r.userId]) {
        byUser[r.userId] = [];
      }
      byUser[r.userId].push(r);
    });

    console.log(`📋 Fetched ${recordings.length} recordings for session ${sessionId}`);

    res.json({
      total: recordings.length,
      recordings,
      byUser,
    });
  } catch (error) {
    console.error('Error fetching session recordings:', error);
    res.status(500).json({
      error: 'Failed to fetch session recordings',
    });
  }
});

/**
 * ✅ NEW: GET /recordings/download/:recordingId
 * Download a specific recording file
 * Supports auth via header or query parameter for compatibility with audio players
 * Handles both local files and S3 URLs
 */
app.get('/recordings/download/:recordingId', (req, res) => {
  try {
    // Check authentication - via header or query param
    let token = req.headers.authorization?.split(' ')[1];
    if (!token && req.query.token) {
      token = req.query.token;
    }

    if (!token) {
      console.warn('⚠️ No authentication token provided for recording download');
      return res.status(401).json({ error: 'Unauthorized' });
    }

    // Verify token validity (simple check)
    if (!token || token.length < 10) {
      console.warn('⚠️ Invalid token for recording download');
      return res.status(401).json({ error: 'Invalid token' });
    }

    const recording = recordingsStorage.get(req.params.recordingId);
    console.log(`🔍 Looking for recording: ${req.params.recordingId}`);
    console.log(`📊 Total recordings in storage: ${recordingsStorage.size}`);

    if (!recording) {
      console.warn(`❌ Recording not found in memory: ${req.params.recordingId}`);
      return res.status(404).json({
        error: 'Recording not found',
        recordingId: req.params.recordingId,
      });
    }

    // Check if recording has an S3 URL (cloud recording)
    if (recording.url && recording.url.includes('s3') || recording.url.includes('amazonaws')) {
      console.log(`☁️  Redirecting to S3 URL for recording: ${recording.filename}`);
      // Redirect to S3 URL for cloud recordings
      return res.redirect(recording.url);
    }

    // Otherwise, try to serve local file
    const filePath = path.join(__dirname, 'recordings', recording.filename);
    console.log(`📁 Checking file path: ${filePath}`);

    if (!fs.existsSync(filePath)) {
      console.error(`❌ Recording file not found on disk: ${filePath}`);
      console.log(`📝 Recording URL: ${recording.url}`);
      console.log(`📝 Recording filename: ${recording.filename}`);

      // If local file doesn't exist but we have a URL, try redirecting to it
      if (recording.url) {
        console.log(`🔄 Attempting to redirect to URL: ${recording.url}`);
        return res.redirect(recording.url);
      }

      return res.status(404).json({
        error: 'Recording file not found',
        filename: recording.filename,
        recordingId: req.params.recordingId,
      });
    }

    // Send file with appropriate headers for streaming
    res.setHeader('Content-Type', 'audio/mp4');
    res.setHeader('Accept-Ranges', 'bytes');
    res.setHeader('Cache-Control', 'public, max-age=3600');
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.sendFile(filePath);

    console.log(`✅ Streaming local recording: ${recording.filename}`);
  } catch (error) {
    console.error('Error downloading recording:', error);
    res.status(500).json({
      error: 'Failed to download recording',
      message: error.message,
    });
  }
});

/**
 * POST /recordings/add
 * Manually add a recording (useful for testing)
 * Body:
 *   {
 *     userId: number,
 *     sessionId: string,
 *     filename: string,
 *     url: string (can be mock URL for testing)
 *   }
 */
app.post('/recordings/add', async (req, res) => {
  try {
    const { userId, sessionId, filename, url } = req.body;

    if (!userId || !sessionId || !filename || !url) {
      return res.status(400).json({
        error: 'Missing required fields: userId, sessionId, filename, url',
      });
    }

    const recordingId = `rec_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const recording = {
      recordingId,
      userId,
      sessionId,
      filename,
      url,
      recordedAt: new Date(),
      durationMs: 0,
    };

    try {
      // ✅ NEW: Save to MongoDB
      if (mongoReady) {
        await RecordingModel.create(recording);
        console.log(`✅ Recording saved to MongoDB`);
      }
    } catch (dbError) {
      console.error('⚠️  Error saving to MongoDB, falling back to memory:', dbError.message);
    }

    // Keep in-memory cache
    recordingsStorage.set(recordingId, recording);
    saveRecordingsToDisk();
    cleanupOldRecordings();

    res.status(201).json({
      success: true,
      recording,
      message: `Recording added for user ${userId}`,
    });
  } catch (error) {
    console.error('Error adding recording:', error);
    res.status(500).json({
      error: 'Failed to add recording',
    });
  }
});

/**
 * ============================================================================
 * Testing & Debug Endpoints
 * ============================================================================
 */

/**
 * POST /test/recording
 * Quick test endpoint to verify recording works (no UI needed)
 *
 * Usage: curl -X POST http://localhost:5000/test/recording \
 *   -H "Authorization: Bearer <token>" \
 *   -H "Content-Type: application/json" \
 *   -d '{"channelName":"test_room"}'
 */
app.post('/test/recording', authMiddleware, allowRole('host'), async (req, res) => {
  try {
    const { channelName = 'test_room' } = req.body;

    console.log(`\n${'='.repeat(60)}`);
    console.log(`🧪 RECORDING TEST - Channel: ${channelName}`);
    console.log(`${'='.repeat(60)}\n`);

    // Test 1: Verify credentials are set
    console.log('📋 Test 1: Checking credentials...');
    if (!AGORA_APP_ID || !AGORA_APP_CERTIFICATE || !AGORA_CUSTOMER_ID || !AGORA_CUSTOMER_SECRET) {
      return res.status(400).json({
        error: 'Missing Agora credentials in .env',
        missing: {
          AGORA_APP_ID: !AGORA_APP_ID,
          AGORA_APP_CERTIFICATE: !AGORA_APP_CERTIFICATE,
          AGORA_CUSTOMER_ID: !AGORA_CUSTOMER_ID,
          AGORA_CUSTOMER_SECRET: !AGORA_CUSTOMER_SECRET,
        },
      });
    }
    console.log('✅ Agora credentials found\n');

    // Test 2: Verify storage config
    console.log('📋 Test 2: Checking storage config...');
    const vendor = Number(process.env.RECORDING_VENDOR);
    const region = Number(process.env.RECORDING_REGION);
    const bucket = process.env.RECORDING_BUCKET;
    const accessKey = process.env.RECORDING_ACCESS_KEY;
    const secretKey = process.env.RECORDING_SECRET_KEY;

    if (!bucket || !accessKey || !secretKey) {
      return res.status(400).json({
        error: 'Missing AWS storage config in .env',
        missing: {
          bucket: !bucket,
          accessKey: !accessKey,
          secretKey: !secretKey,
        },
      });
    }
    console.log('✅ AWS storage config found');
    console.log(`   - Vendor: ${vendor} (2=S3), Region: ${region}`);
    console.log(`   - Bucket: ${bucket}`);
    console.log(`   - AccessKey: ${accessKey.substring(0, 10)}...`);
    console.log('');

    // Test 3: Try to acquire recording
    console.log('📋 Test 3: Acquiring recording resource...');
    const resourceId = await acquireRecording(channelName);
    console.log(`✅ Resource acquired: ${resourceId.substring(0, 30)}...\n`);

    // Test 4: Try to start recording
    console.log('📋 Test 4: Starting MIX mode recording...');
    const mode = 'mix';
    const url = `${AGORA_RECORDING_API}/${AGORA_APP_ID}/cloud_recording/resourceid/${resourceId}/mode/${mode}/start`;

    const currentTimestamp = Math.floor(Date.now() / 1000);
    const privilegeExpire = currentTimestamp + TOKEN_TTL;
    const recorderUid = 0;
    const token = RtcTokenBuilder.buildTokenWithUid(
      AGORA_APP_ID,
      AGORA_APP_CERTIFICATE,
      channelName,
      recorderUid,
      RtcRole.PUBLISHER,
      privilegeExpire
    );

    const payload = {
      cname: channelName,
      uid: String(recorderUid),
      clientRequest: {
        token,
        recordingConfig: {
          maxIdleTime: 30,
          streamTypes: 0,
          channelType: 0,
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

    const response = await axios.post(url, payload, {
      headers: {
        Authorization: createRecordingAuthHeader(),
        'Content-Type': 'application/json',
      },
    });

    if (response.status === 200 && response.data.sid) {
      console.log(`✅ Recording STARTED! SessionId: ${response.data.sid}\n`);
      console.log(`${'='.repeat(60)}`);
      console.log('🎉 SUCCESS - Recording is working!');
      console.log(`${'='.repeat(60)}\n`);

      return res.status(201).json({
        success: true,
        resourceId,
        sid: response.data.sid,
        message: 'Recording test successful!',
      });
    }

    throw new Error('No sid returned from API');
  } catch (error) {
    console.error('\n❌ TEST FAILED');
    console.error('Error:', error.response?.data || error.message);
    console.log(`${'='.repeat(60)}\n`);

    res.status(400).json({
      error: 'Recording test failed',
      details: error.response?.data || error.message,
      troubleshooting: {
        message: 'Possible causes:',
        causes: [
          '1. AWS S3 credentials invalid or expired',
          '2. S3 bucket does not exist or not accessible',
          '3. IAM user lacks S3 permissions',
          '4. Agora account Cloud Recording not enabled',
          '5. Channel name or configuration mismatch',
        ],
        next_steps: [
          'Verify AWS credentials in backend/.env',
          'Check S3 bucket exists and is accessible',
          'Confirm Agora account has Cloud Recording enabled',
          'Check IAM user has S3 full access permissions',
        ],
      },
    });
  }
});

/**
 * 🔍 DEBUG: GET /debug/recordings
 * Show all recordings in memory and database
 */
app.get('/debug/recordings', (req, res) => {
  try {
    const inMemory = Array.from(recordingsStorage.values());
    res.json({
      inMemoryCount: recordingsStorage.size,
      inMemory: inMemory.slice(0, 10), // Show first 10
      storageSize: recordingsStorage.size,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * 🔍 DEBUG: GET /debug/recording/:recordingId
 * Check if a specific recording exists
 */
app.get('/debug/recording/:recordingId', (req, res) => {
  try {
    const recording = recordingsStorage.get(req.params.recordingId);
    if (!recording) {
      return res.status(404).json({
        found: false,
        recordingId: req.params.recordingId,
        message: 'Recording not found in storage',
      });
    }

    const filePath = path.join(__dirname, 'recordings', recording.filename);
    const fileExists = fs.existsSync(filePath);

    res.json({
      found: true,
      recordingId: req.params.recordingId,
      recording,
      fileExists,
      filePath: fileExists ? filePath : 'N/A',
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
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
  // ✅ NEW: Load recordings from MongoDB on startup
  loadRecordingsFromDatabase();

  // ✅ Load recordings metadata from disk on startup (fallback)
  loadRecordingsFromDisk();

  app.listen(PORT, () => {
    console.log(`✅ Agora RTC Token Server running on http://localhost:${PORT}`);
    console.log(`📍 Authentication & Authorization:`);
    console.log(`   - POST /auth/register-host (create first host user)`);
    console.log(`   - POST /auth/login (login and get JWT token)`);
    console.log(`   - POST /auth/create-user (create users, host-only)`);
    console.log(`📍 Token endpoint: GET /agora/token?channelName=<name>&uid=<id>`);
    console.log(`📍 Speaking events: POST /events/speaking`);
    console.log(`📍 Speaking events: GET /events/speaking`);
    console.log(`📍 Session endpoints:`);
    console.log(`   - POST /session/:id/users/add (register user in session)`);
    console.log(`   - GET /session/:id/users (list users in session)`);
    console.log(`📍 Recording endpoints (host-only):`);
    console.log(`   - POST /recording/start (start INDIVIDUAL mode recording)`);
    console.log(`   - POST /recording/stop (stop recording)`);
    console.log(`   - POST /recording/webhook (Agora callback)`);
    console.log(`   - GET /recording/active (list active recordings)`);
    console.log(`   - GET /recordings (fetch recordings with filters)`);
    console.log(`   - POST /recordings/add (manually add recording)`);
  });
});

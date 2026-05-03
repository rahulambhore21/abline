const {
  acquireRecording,
  startRecording,
  stopRecording,
  activeRecordings,
} = require('../services/RecordingService');
const Recording = require('../models/Recording');
const { uploadToS3, getPresignedUrl } = require('../services/S3Service');

const config = require('../config');

const PUBLIC_URL = config.publicUrl;

// Removed in-memory recordingsStorage Map as MongoDB is the source of truth

async function initializeRecordingsStorage() {
  try {
    console.log('🔄 Initializing recordings storage from database...');
    const recordings = await Recording.find().lean();

    // Also initialize active recording sessions
    const recordingService = require('../services/RecordingService');
    await recordingService.initializeActiveRecordings();

    console.log(`✅ Recording system initialized. Database has ${recordings.length} records.`);

    // Log a few IDs for verification
    if (recordings.length > 0) {
      const sampleIds = recordings.slice(0, 3).map((r) => r.recordingId);
      console.log('📋 Sample recording IDs:', sampleIds);
    }
  } catch (err) {
    console.error('⚠️ Failed to initialize recordings storage:', err.message);
  }
}

// Redundant functions removed (saveRecordingsToDisk)

function recordingExists(recording) {
  if (!recording) return false;
  const url = recording.url || '';
  // Recordings are now strictly cloud-based (S3)
  if (url.includes('s3') || url.includes('amazonaws') || url.startsWith('http')) {
    return true;
  }
  return false;
}

exports.startRecording = async (req, res, next) => {
  try {
    const { channelName, uid } = req.body;
    if (!channelName || uid === undefined) {
      return res.status(400).json({ error: 'Missing required fields: channelName, uid' });
    }
    // Check if already active
    const active = activeRecordings.get(channelName);
    if (active) {
      return res.status(200).json({
        resourceId: active.resourceId,
        sid: active.sid,
        message: 'Recording is already active',
      });
    }

    const resourceId = await acquireRecording(channelName);
    const userId = req.body.userId || req.user?.id;
    const username = req.body.username || req.user?.username;

    const { sid } = await startRecording(channelName, resourceId, userId, username);
    res.status(201).json({ resourceId, sid, message: 'Recording started successfully' });
  } catch (error) {
    next(error);
  }
};

exports.stopRecording = async (req, res, next) => {
  try {
    const { channelName, resourceId, sid } = req.body;
    if (!channelName) return res.status(400).json({ error: 'Missing required field: channelName' });

    let resolvedResourceId = resourceId;
    let resolvedSid = sid;
    let resolvedMode = 'mix';

    if (!resolvedResourceId || !resolvedSid) {
      const active = activeRecordings.get(channelName);
      if (!active)
        return res
          .status(400)
          .json({ error: `No active recording found for channel: ${channelName}` });
      resolvedResourceId = active.resourceId;
      resolvedSid = active.sid;
      resolvedMode = active.mode || 'mix';
    }

    await stopRecording(channelName, resolvedResourceId, resolvedSid, resolvedMode);
    res.status(200).json({ success: true, message: 'Recording stopped successfully' });
  } catch (error) {
    next(error);
  }
};

exports.listRecordings = async (req, res, next) => {
  try {
    const { userId, verify, page = 1, limit = 50 } = req.query;
    // sessionId can come from query (?sessionId=...) or path params (/session/:sessionId)
    const sessionId = req.query.sessionId || req.params.sessionId;
    const shouldVerify = verify !== 'false';
    const filter = {};

    if (sessionId) filter.sessionId = sessionId;

    if (req.user.role !== 'host') {
      // Users only see their own recordings, matched by username (case-insensitive)
      filter.username = { $regex: new RegExp(`^${req.user.username}$`, 'i') };
    } else {
      // Admins can filter by userId (Agora UID) or username
      if (userId) {
        const numericUid = Number(userId);
        if (!isNaN(numericUid)) {
          filter.userId = numericUid;
        } else {
          filter.username = { $regex: new RegExp(`^${userId}$`, 'i') };
        }
      }
    }

    const skip = (Number(page) - 1) * Number(limit);
    const totalCount = await Recording.countDocuments(filter);

    let recordings = await Recording.find(filter)
      .sort({ recordedAt: -1 })
      .skip(skip)
      .limit(Number(limit))
      .lean();

    if (shouldVerify) {
      const verified = [];
      for (const r of recordings) {
        const exists = recordingExists(r);
        verified.push({
          ...r,
          exists, // Add a flag instead of deleting
        });
      }
      recordings = verified;
    }

    // Group by user for the admin dashboard
    const byUser = {};
    const formattedRecordings = recordings.map((r) => {
      const formatted = {
        id: r.recordingId,
        userId: r.userId,
        username: r.username || 'Unknown',
        sessionId: r.sessionId,
        filename: r.filename,
        // Always use our proxy URL so we can handle authentication and S3 fetching
        url: `${PUBLIC_URL}/recordings/download/${r.recordingId}`,
        recordedAt: r.recordedAt,
        durationMs: r.durationMs,
        exists: r.exists, // Pass existence flag
      };

      const userKey = r.username || 'Unknown';
      if (!byUser[userKey]) byUser[userKey] = [];
      byUser[userKey].push(formatted);

      return formatted;
    });

    res.json({
      total: totalCount,
      page: Number(page),
      limit: Number(limit),
      totalPages: Math.ceil(totalCount / Number(limit)),
      recordings: formattedRecordings,
      byUser, // ✅ REQUIRED for Admin Dashboard
    });
  } catch (error) {
    next(error);
  }
};


const crypto = require('crypto');

exports.saveRecording = async (req, res, next) => {
  try {
    const { userId, sessionId, durationMs, url, filename: providedFilename } = req.body;
    const audioFile = req.files?.audioFile;

    if (!sessionId) return res.status(400).json({ error: 'Missing sessionId' });

    // SECURITY: Use authenticated identity as source of truth
    const authenticatedUserId = req.user.userId;
    const authenticatedUsername = req.user.username;

    // Reject spoofed userId
    if (userId !== undefined && String(userId) !== String(authenticatedUserId)) {
      console.warn(
        `🔐 Security Alert: User ${authenticatedUsername} tried to save recording for userId ${userId}`
      );
      return res
        .status(403)
        .json({ error: 'Forbidden', message: 'You can only save recordings for yourself.' });
    }

    let finalUrl = url;
    let recordingId = `rec_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

    // SECURITY: Sanitize filename to prevent directory traversal or malicious characters
    let sanitizedFilename = (providedFilename || `${recordingId}.m4a`).replace(
      /[^a-zA-Z0-9.\-_]/g,
      ''
    ); // Only allow alphanumeric, dots, dashes, underscores

    if (audioFile) {
      finalUrl = await uploadToS3(audioFile.data, sanitizedFilename, audioFile.mimetype);
    } else if (!url) {
      return res.status(400).json({ error: 'Missing audioFile or direct S3 url' });
    }

    const recordingData = {
      recordingId,
      userId: Number(authenticatedUserId),
      username: authenticatedUsername,
      sessionId,
      filename: sanitizedFilename,
      url: finalUrl,
      recordedAt: new Date(),
      durationMs: Number(durationMs) || 0,
    };

    const recording = await Recording.create(recordingData);
    res
      .status(201)
      .json({ success: true, recordingId, url: recording.url, recordedAt: recording.recordedAt });
  } catch (error) {
    next(error);
  }
};

exports.requestUploadUrl = async (req, res, next) => {
  try {
    const { filename, contentType } = req.body;
    if (!filename) return res.status(400).json({ error: 'Missing filename' });

    // SECURITY: Sanitize filename to prevent S3 path injection or manipulation
    const sanitizedFilename = filename
      .split('/')
      .pop()
      .replace(/[^a-zA-Z0-9.\-_]/g, '');
    const finalFilename = `user_${req.user.userId}/${Date.now()}_${sanitizedFilename}`;

    const uploadUrl = await getPresignedUrl(finalFilename, contentType);
    res.json({ uploadUrl, filename: finalFilename });
  } catch (error) {
    next(error);
  }
};

exports.downloadRecording = async (req, res) => {
  try {
    const { recordingId } = req.params;
    const recording = await Recording.findOne({ recordingId }).lean();

    if (!recording) return res.status(404).json({ error: 'Recording not found' });

    // --- AUTHORIZATION CHECK ---
    // Only allow the owner or a host to download the recording
    const isOwner =
      req.user.username &&
      recording.username &&
      req.user.username.toLowerCase() === recording.username.toLowerCase();
    const isHost = req.user.role === 'host';

    if (!isOwner && !isHost) {
      console.warn(
        `🔐 Unauthorized download attempt: User ${req.user.username} tried to access recording ${recordingId} owned by ${recording.username}`
      );
      return res.status(403).json({
        error: 'Forbidden',
        message: 'You do not have permission to download this recording',
      });
    }
    // ----------------------------

    // Handle S3 Streaming (Primary Global Method)
    if (recording.url && (recording.url.includes('s3') || recording.url.includes('amazonaws'))) {
      try {
        const { getS3FileStream } = require('../services/S3Service');
        const stream = await getS3FileStream(recording.filename);

        res.setHeader('Content-Type', 'audio/mp4');
        res.setHeader('Accept-Ranges', 'bytes');
        return stream.pipe(res);
      } catch (s3Error) {
        console.error('❌ S3 Streaming failed, attempting direct redirect:', s3Error.message);
        // Fallback to redirect if streaming fails
        return res.redirect(recording.url);
      }
    }

    res.status(404).json({ error: 'Recording file not available on cloud storage' });
  } catch (error) {
    console.error('❌ Download error:', error.message);
    res.status(500).json({ error: 'Failed to download recording', message: error.message });
  }
};

exports.activeRecordings = (req, res) => {
  const recordings = Array.from(activeRecordings.values());
  res.json({
    success: true,
    count: recordings.length,
    recordings,
  });
};

exports.webhook = async (req, res) => {
  try {
    // SECURITY: Verify Agora Webhook Signature
    const signature = req.headers['agora-signature'];
    const secret = process.env.AGORA_WEBHOOK_SECRET;

    if (secret && signature) {
      // For Agora, the signature is typically a hash of the body
      const computeSignature = crypto
        .createHmac('sha256', secret)
        .update(JSON.stringify(req.body))
        .digest('hex');

      if (computeSignature !== signature) {
        console.warn('🔐 Security Alert: Invalid Agora Webhook Signature received');
        return res.status(401).json({ status: 'unauthorized', message: 'Invalid signature' });
      }
    } else if (process.env.NODE_ENV === 'production' && !secret) {
      console.warn(
        '🛑 SECURITY WARNING: AGORA_WEBHOOK_SECRET not set in production. Webhooks are vulnerable to spoofing.'
      );
    }

    const { sid, cname, fileList } = req.body;
    console.log(`🔔 Agora Webhook received for session: ${cname}, SID: ${sid}`);

    if (!fileList || fileList.length === 0) {
      console.log('ℹ️ Webhook contained no files.');
      return res.status(200).json({ status: 'processed' });
    }

    const ActiveRecording = require('../models/ActiveRecording');
    const activeRec =
      (await ActiveRecording.findOne({ sid }).lean()) ||
      (await ActiveRecording.findOne({ channelName: cname }).lean());

    if (activeRec) {
      console.log(
        `ℹ️ Found metadata for session: User=${activeRec.username}, ID=${activeRec.userId}`
      );
    } else {
      console.warn(
        `⚠️ No active recording metadata found for SID: ${sid}. Recording will have default metadata.`
      );
    }

    for (const file of fileList) {
      const { filename, uid } = file;
      console.log(`   - Processing file: ${filename} for UID: ${uid}`);

      const uidMatch = filename.match(/uid_(\d+)/);
      const userId = activeRec?.userId || (uidMatch ? Number(uidMatch[1]) : Number(uid));
      const username = activeRec?.username || 'Unknown';
      const recordingId = sid ? `${sid}_${filename}` : `rec_${Date.now()}_${filename}`;
      const { bucket, awsRegion } = config.storage;
      const s3Url = bucket ? `https://${bucket}.s3.${awsRegion}.amazonaws.com/${filename}` : '';

      await Recording.create({
        recordingId,
        userId,
        username,
        sessionId: cname,
        filename,
        recordedAt: activeRec?.startedAt || new Date(),
        url: s3Url,
      });
      console.log(`   ✅ Record created for ${recordingId}`);
    }

    // Note: We no longer delete ActiveRecording here to allow for multi-part webhooks.
    // Stale sessions are cleaned up automatically on backend restart (24h threshold).
    console.log(`   ✅ Metadata preserved for potential multi-part webhook for ${cname}`);

    res.status(200).json({ status: 'processed' });
  } catch (error) {
    console.error('❌ Webhook processing error:', error.message);
    res.status(200).json({ status: 'processed', error: error.message });
  }
};

exports.initializeRecordingsStorage = initializeRecordingsStorage;

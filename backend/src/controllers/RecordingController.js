const { acquireRecording, startRecording, stopRecording, activeRecordings } = require('../services/RecordingService');
const Recording = require('../models/Recording');
const User = require('../models/User');
const path = require('path');
const fs = require('fs');
const { uploadToS3 } = require('../services/S3Service');


const PUBLIC_URL = process.env.PUBLIC_URL || 'https://v0c4kk0o0w440k4sk8cwwgs4.admarktech.cloud';

// In-memory storage with disk persistence helpers (moved from app.js)
const recordingsStorage = new Map();
const RECORDINGS_METADATA_FILE = path.join(__dirname, '../../.recordings-metadata.json');

async function initializeRecordingsStorage() {
  try {
    console.log('🔄 Initializing recordings storage from database...');
    const recordings = await Recording.find().lean();
    recordingsStorage.clear(); // Ensure we start fresh
    recordings.forEach(r => {
      recordingsStorage.set(r.recordingId, r);
    });

    // Also initialize active recording sessions
    const recordingService = require('../services/RecordingService');
    await recordingService.initializeActiveRecordings();

    
    console.log(`✅ Loaded ${recordingsStorage.size} recordings from database into memory storage`);

    
    // Log a few IDs for verification
    if (recordings.length > 0) {
      const sampleIds = recordings.slice(0, 3).map(r => r.recordingId);
      console.log('📋 Sample recording IDs:', sampleIds);
    }
  } catch (err) {
    console.error('⚠️ Failed to initialize recordings storage:', err.message);
  }
}


function saveRecordingsToDisk() {
  try {
    const data = Array.from(recordingsStorage.values());
    fs.writeFileSync(RECORDINGS_METADATA_FILE, JSON.stringify(data, null, 2), 'utf8');
  } catch (e) {
    console.error('⚠️ Error saving recordings to disk:', e.message);
  }
}

function recordingExists(recording) {
  if (!recording) return false;
  const url = recording.url || '';
  const isInternalUrl = url.includes(PUBLIC_URL) || url.includes('/recordings/download/');
  if (!isInternalUrl && (url.includes('s3') || url.includes('amazonaws') || url.startsWith('http'))) {
    return true;
  }
  const filename = recording.filename;
  if (!filename) return false;
  const filePath = path.join(__dirname, '../../recordings', filename);
  return fs.existsSync(filePath);
}

exports.startRecording = async (req, res, next) => {
  try {
    const { channelName, uid } = req.body;
    if (!channelName || uid === undefined) {
      return res.status(400).json({ error: 'Missing required fields: channelName, uid' });
    }
    const resourceId = await acquireRecording(channelName);
    const { sid } = await startRecording(channelName, resourceId);
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
      if (!active) return res.status(400).json({ error: `No active recording found for channel: ${channelName}` });
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
    const { userId, verify } = req.query;
    // sessionId can come from query (?sessionId=...) or path params (/session/:sessionId)
    const sessionId = req.query.sessionId || req.params.sessionId;
    const shouldVerify = verify !== 'false';
    const filter = {};
    
    if (sessionId) filter.sessionId = sessionId;

    if (req.user.role !== 'host') {
      filter.username = req.user.username;
    } else if (userId) {
      const numericUid = Number(userId);
      if (!isNaN(numericUid)) filter.userId = numericUid;
      else filter.username = userId;
    }

    console.log(`🔍 Listing recordings with filter:`, JSON.stringify(filter));

    let recordings = await Recording.find(filter).sort({ recordedAt: -1 }).lean();

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
    const formattedRecordings = recordings.map(r => {
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



      const uId = String(r.userId);
      if (!byUser[uId]) byUser[uId] = [];
      byUser[uId].push(formatted);
      
      return formatted;
    });

    res.json({
      total: formattedRecordings.length,
      recordings: formattedRecordings,
      byUser, // ✅ REQUIRED for Admin Dashboard
    });
  } catch (error) {
    next(error);
  }
};


exports.saveRecording = async (req, res, next) => {
  try {
    const { userId, sessionId, durationMs, username } = req.body;
    const audioFile = req.files?.audioFile;
    if (!userId || !sessionId || !audioFile) return res.status(400).json({ error: 'Missing required fields' });

    const recordingId = `rec_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const filename = `${recordingId}.m4a`;
    
    // Upload to S3 instead of saving locally
    let s3Url;
    try {
      s3Url = await uploadToS3(audioFile.data, filename, audioFile.mimetype);
      console.log(`✅ Recording uploaded to S3: ${s3Url}`);
    } catch (uploadError) {
      console.error('❌ S3 Upload failed, falling back to local storage:', uploadError.message);
      
      // Fallback to local storage if S3 fails
      const recordingsDir = path.join(__dirname, '../../recordings');
      if (!fs.existsSync(recordingsDir)) fs.mkdirSync(recordingsDir, { recursive: true });
      const filePath = path.join(recordingsDir, filename);
      await audioFile.mv(filePath);
      s3Url = `${PUBLIC_URL}/recordings/download/${recordingId}`;
    }

    const recordingData = {
      recordingId,
      userId: Number(userId),
      username: username || 'Unknown',
      sessionId,
      filename,
      url: s3Url,
      recordedAt: new Date(),
      durationMs: Number(durationMs) || 0,
    };

    const recording = await Recording.create(recordingData);
    recordingsStorage.set(recordingId, recordingData);
    saveRecordingsToDisk();

    res.status(201).json({ success: true, recordingId, url: recording.url, recordedAt: recording.recordedAt });
  } catch (error) {
    next(error);
  }
};


exports.downloadRecording = async (req, res) => {
  try {
    const { recordingId } = req.params;
    let recording = recordingsStorage.get(recordingId);
    
    if (!recording) {
      console.log(`🔍 Recording ${recordingId} not in cache, checking database...`);
      recording = await Recording.findOne({ recordingId }).lean();
      if (recording) {
        recordingsStorage.set(recordingId, recording);
      }
    }

    if (!recording) return res.status(404).json({ error: 'Recording not found' });

    // Handle S3 Streaming
    if (recording.url && (recording.url.includes('s3') || recording.url.includes('amazonaws'))) {
      try {
        const { getS3FileStream } = require('../services/S3Service');
        const stream = await getS3FileStream(recording.filename);
        
        res.setHeader('Content-Type', 'audio/mp4');
        res.setHeader('Accept-Ranges', 'bytes');
        return stream.pipe(res);
      } catch (s3Error) {
        console.error('❌ S3 Streaming failed:', s3Error.message);
        // Fallback to redirect if streaming fails
        return res.redirect(recording.url);
      }
    }

    const filePath = path.join(__dirname, '../../recordings', recording.filename);
    if (fs.existsSync(filePath)) {
      res.setHeader('Content-Type', 'audio/mp4');
      res.setHeader('Accept-Ranges', 'bytes');
      return res.sendFile(filePath);
    }
    res.status(404).json({ error: 'Recording file not available' });
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
    recordings 
  });
};

exports.webhook = async (req, res) => {
  try {
    const { sid, cname, fileList } = req.body;
    console.log(`🔔 Agora Webhook received for session: ${cname}, SID: ${sid}`);
    
    if (!fileList || fileList.length === 0) {
      console.log('ℹ️ Webhook contained no files.');
      return res.status(200).json({ status: 'processed' });
    }

    console.log(`📄 Webhook contains ${fileList.length} files.`);

    for (const file of fileList) {
      const { filename, uid } = file;
      console.log(`   - Processing file: ${filename} for UID: ${uid}`);
      
      const uidMatch = filename.match(/uid_(\d+)/);
      const userId = uidMatch ? uidMatch[1] : uid;
      const recordingId = sid ? `${sid}_${filename}` : `rec_${Date.now()}_${filename}`;
      const bucket = process.env.RECORDING_BUCKET;
      const s3Url = bucket ? `https://${bucket}.s3.amazonaws.com/${filename}` : '';

      await Recording.create({
        recordingId,
        userId: Number(userId) || 0,
        sessionId: cname,
        filename,
        recordedAt: new Date(),
        url: s3Url,
      });
      console.log(`   ✅ Record created for ${recordingId}`);
    }
    res.status(200).json({ status: 'processed' });
  } catch (error) {
    console.error('❌ Webhook processing error:', error.message);
    res.status(200).json({ status: 'processed', error: error.message });
  }
};


exports.recordingsStorage = recordingsStorage;
exports.initializeRecordingsStorage = initializeRecordingsStorage;

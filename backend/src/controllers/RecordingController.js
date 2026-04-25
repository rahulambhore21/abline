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
    const recordings = await Recording.find().lean();
    recordings.forEach(r => {
      recordingsStorage.set(r.recordingId, r);
    });
    console.log(`✅ Loaded ${recordingsStorage.size} recordings from database into memory storage`);
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
        url: r.url || `${PUBLIC_URL}/recordings/download/${r.recordingId}`,
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


exports.downloadRecording = (req, res) => {
  try {
    const { recordingId } = req.params;
    const recording = recordingsStorage.get(recordingId);
    if (!recording) return res.status(404).json({ error: 'Recording not found' });

    if (recording.url && (recording.url.includes('s3') || recording.url.includes('amazonaws'))) {
      return res.redirect(recording.url);
    }

    const filePath = path.join(__dirname, '../../recordings', recording.filename);
    if (fs.existsSync(filePath)) {
      res.setHeader('Content-Type', 'audio/mp4');
      return res.sendFile(filePath);
    }
    res.status(404).json({ error: 'Recording file not available' });
  } catch (error) {
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
    if (!fileList || fileList.length === 0) return res.status(200).json({ status: 'processed' });

    for (const file of fileList) {
      const { filename, uid } = file;
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
    }
    res.status(200).json({ status: 'processed' });
  } catch (error) {
    res.status(200).json({ status: 'processed', error: error.message });
  }
};

exports.recordingsStorage = recordingsStorage;
exports.initializeRecordingsStorage = initializeRecordingsStorage;

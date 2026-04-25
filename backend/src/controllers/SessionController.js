const Session = require('../models/Session');
const SpeakingEvent = require('../models/SpeakingEvent');
const User = require('../models/User');
const mongoose = require('mongoose');
const { acquireRecording, startRecording, stopRecording } = require('../services/RecordingService');

// activeSessions Map removed in favor of MongoDB persistence
const SESSION_TIMEOUT_MS = 24 * 60 * 60 * 1000;

exports.addUserToSession = async (req, res, next) => {
  try {
    const { id: sessionId } = req.params;
    const { userId, username, role } = req.body;

    if (userId === null || userId === undefined || !username) {
      return res.status(400).json({ error: 'Missing required fields: userId, username' });
    }

    // Use findOneAndUpdate with upsert to manage session state in DB
    const session = await Session.findOneAndUpdate(
      { sessionId },
      { 
        $set: { isActive: true }, // Ensure session is active if someone is joining
        $addToSet: { 
          users: { userId, username, role: role || 'user', isSpeaking: false } 
        } 
      },
      { upsert: true, new: true }
    );

    // If host is joining, update hostUid
    if (role === 'host') {
      await Session.updateOne({ sessionId }, { $set: { hostUid: userId } });
    }

    // Handle user re-join logic in DB (remove old UIDs for same username if needed)
    // For simplicity, we'll keep the current implementation's spirit but in MongoDB
    await Session.updateOne(
      { sessionId },
      { $pull: { users: { username, userId: { $ne: userId } } } }
    );

    const updatedSession = await Session.findOne({ sessionId });

    res.status(200).json({ 
      success: true, 
      message: `User ${userId} added`, 
      hostUid: updatedSession.hostUid 
    });

    User.findOneAndUpdate({ username }, { lastKnownUid: userId }).catch(err => console.error(err));
  } catch (error) {
    next(error);
  }
};

exports.getSessionUsers = async (req, res) => {
  const { id: sessionId } = req.params;
  const session = await Session.findOne({ sessionId }).lean();
  
  if (!session) return res.json({ sessionId, users: [], total: 0, hostUid: null });

  res.json({ 
    sessionId, 
    users: session.users, 
    total: session.users.length, 
    hostUid: session.hostUid 
  });
};

exports.startSession = async (req, res, next) => {
  try {
    const { id: sessionId } = req.params;
    
    let session = await Session.findOneAndUpdate(
      { sessionId },
      { $set: { isActive: true, startedAt: new Date() } },
      { upsert: true, new: true }
    );

    let recordingActive = false;
    try {
      const resourceId = await acquireRecording(sessionId);
      const recordingData = await startRecording(sessionId, resourceId);
      
      await Session.updateOne(
        { sessionId },
        { $set: { recordingResourceId: resourceId, recordingSid: recordingData.sid, recordingActive: true } }
      );
      recordingActive = true;
    } catch (err) {
      console.warn('⚠️ Auto-recording failed:', err.message);
    }

    res.status(200).json({ 
      success: true, 
      sessionId, 
      startedAt: session.startedAt, 
      recordingActive 
    });
  } catch (error) {
    next(error);
  }
};

exports.stopSession = async (req, res, next) => {
  try {
    const { id: sessionId } = req.params;
    const session = await Session.findOne({ sessionId });
    if (!session) return res.status(404).json({ error: 'Session not found' });

    await Session.updateOne(
      { sessionId },
      { $set: { isActive: false, stoppedAt: new Date(), recordingActive: false } }
    );

    if (session.recordingActive && session.recordingSid) {
      try {
        await stopRecording(sessionId, session.recordingResourceId, session.recordingSid, 'mix');
      } catch (err) {
        console.warn('⚠️ Auto-recording stop failed:', err.message);
      }
    }

    res.status(200).json({ success: true, sessionId, stoppedAt: new Date() });
  } catch (error) {
    next(error);
  }
};

exports.getSessionStatus = async (req, res) => {
  const { id: sessionId } = req.params;
  const session = await Session.findOne({ sessionId }).lean();
  if (!session) return res.json({ sessionId, isActive: false, users: 0 });
  res.json({ 
    sessionId, 
    isActive: session.isActive, 
    startedAt: session.startedAt, 
    users: session.users.length 
  });
};

exports.recordSpeakingEvent = async (req, res, next) => {
  try {
    const { userId, sessionId, start, end } = req.body;
    if (userId === null || userId === undefined || !sessionId || !start || !end) {
      return res.status(400).json({ error: 'Missing required fields' });
    }
    const event = await SpeakingEvent.create({
      userId: Number(userId),
      sessionId: String(sessionId),
      start: new Date(start),
      end: new Date(end),
      durationMs: Date.parse(end) - Date.parse(start),
    });
    res.status(201).json({ success: true, eventId: event._id });
  } catch (error) {
    next(error);
  }
};

exports.listSpeakingEvents = async (req, res, next) => {
  try {
    const { userId, sessionId } = req.query;
    const filter = {};
    if (userId) filter.userId = Number(userId);
    if (sessionId) filter.sessionId = String(sessionId);
    const docs = await SpeakingEvent.find(filter).sort({ start: 1 }).lean();
    res.json({ total: docs.length, events: docs });
  } catch (error) {
    next(error);
  }
};

exports.healthCheck = (req, res) => {
  res.json({ status: 'ok', mongo: { connected: mongoose.connection.readyState === 1 } });
};

// State is now managed via Session model in MongoDB

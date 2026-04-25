const SpeakingEvent = require('../models/SpeakingEvent');
const User = require('../models/User');
const mongoose = require('mongoose');
const { acquireRecording, startRecording, stopRecording } = require('../services/RecordingService');

const activeSessions = new Map();
const SESSION_TIMEOUT_MS = 24 * 60 * 60 * 1000;

exports.addUserToSession = async (req, res, next) => {
  try {
    const { id: sessionId } = req.params;
    const { userId, username, role } = req.body;

    if (userId === null || userId === undefined || !username) {
      return res.status(400).json({ error: 'Missing required fields: userId, username' });
    }

    if (!activeSessions.has(sessionId)) {
      activeSessions.set(sessionId, {
        sessionId,
        users: new Map(),
        isActive: false,
        hostUid: null,
      });
    }

    const session = activeSessions.get(sessionId);

    for (const [uid, uData] of session.users.entries()) {
      if (uData.username === username && uid !== userId) {
        return res.status(409).json({ error: 'Duplicate username' });
      }
    }

    if (role === 'host') session.hostUid = userId;

    session.users.set(userId, { userId, username, isSpeaking: false, role: role || 'user' });

    res.status(200).json({ success: true, message: `User ${userId} added`, hostUid: session.hostUid });

    User.findOneAndUpdate({ username }, { lastKnownUid: userId }).catch(err => console.error(err));
  } catch (error) {
    next(error);
  }
};

exports.getSessionUsers = (req, res) => {
  const { id: sessionId } = req.params;
  const session = activeSessions.get(sessionId);
  if (!session) return res.json({ sessionId, users: [], total: 0, hostUid: null });

  const users = Array.from(session.users.values()).map(u => ({
    userId: u.userId,
    username: u.username,
    isSpeaking: u.isSpeaking,
    role: u.role,
  }));

  res.json({ sessionId, users, total: users.length, hostUid: session.hostUid });
};

exports.startSession = async (req, res, next) => {
  try {
    const { id: sessionId } = req.params;
    if (!activeSessions.has(sessionId)) {
      activeSessions.set(sessionId, { sessionId, users: new Map(), startedAt: new Date(), isActive: true });
    } else {
      const session = activeSessions.get(sessionId);
      session.isActive = true;
      session.startedAt = new Date();
    }

    const session = activeSessions.get(sessionId);
    try {
      const resourceId = await acquireRecording(sessionId);
      session.recordingResourceId = resourceId;
      const recordingData = await startRecording(sessionId, resourceId);
      session.recordingSid = recordingData.sid;
      session.recordingActive = true;
    } catch (err) {
      console.warn('⚠️ Auto-recording failed:', err.message);
    }

    res.status(200).json({ success: true, sessionId, startedAt: session.startedAt, recordingActive: session.recordingActive });
  } catch (error) {
    next(error);
  }
};

exports.stopSession = async (req, res, next) => {
  try {
    const { id: sessionId } = req.params;
    const session = activeSessions.get(sessionId);
    if (!session) return res.status(404).json({ error: 'Session not found' });

    session.isActive = false;
    session.stoppedAt = new Date();

    if (session.recordingActive && session.recordingSid) {
      try {
        await stopRecording(sessionId, session.recordingResourceId, session.recordingSid, 'mix');
        session.recordingActive = false;
      } catch (err) {
        console.warn('⚠️ Auto-recording stop failed:', err.message);
      }
    }

    res.status(200).json({ success: true, sessionId, stoppedAt: session.stoppedAt });
  } catch (error) {
    next(error);
  }
};

exports.getSessionStatus = (req, res) => {
  const { id: sessionId } = req.params;
  const session = activeSessions.get(sessionId);
  if (!session) return res.json({ sessionId, isActive: false, users: 0 });
  res.json({ sessionId, isActive: session.isActive, startedAt: session.startedAt, users: session.users.size });
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

exports.activeSessions = activeSessions;

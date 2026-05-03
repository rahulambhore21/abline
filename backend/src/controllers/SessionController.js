const Session = require('../models/Session');
const SpeakingEvent = require('../models/SpeakingEvent');
const User = require('../models/User');
const mongoose = require('mongoose');
const { acquireRecording, startRecording, stopRecording } = require('../services/RecordingService');

// State is now managed via Session model in MongoDB

exports.addUserToSession = async (req, res, next) => {
  try {
    const { id: sessionId } = req.params;
    const { userId, username, role } = req.body;

    if (userId === null || userId === undefined || !username) {
      return res.status(400).json({ error: 'Missing required fields: userId, username' });
    }

    // Find current session status
    let session = await Session.findOne({ sessionId });

    // ✅ ENFORCEMENT: Only allow joining if session is active or if the joiner is the host
    const isHost = role === 'host';

    if (isHost) {
      // If host joins, ensure the session is marked active and recording starts
      // Only start if not already active to avoid redundant Agora calls
      if (!session || !session.isActive) {
        const result = await startSessionInternal(sessionId);
        session = result.session;
        console.log(`🎙️ Session ${sessionId} activated by Host join.`);
      } else {
        console.log(`🎙️ Host joined existing active session ${sessionId}.`);
      }
    } else if (!session || !session.isActive) {
      return res.status(403).json({
        error: 'Session not active',
        message: 'The admin has not joined the call yet.',
      });
    }

    // Use findOneAndUpdate with upsert to manage session state in DB
    session = await Session.findOneAndUpdate(
      { sessionId },
      {
        $addToSet: {
          users: { userId, username, role: role || 'user', isSpeaking: false },
        },
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
      hostUid: updatedSession.hostUid,
    });

    User.findOneAndUpdate({ username }, { lastKnownUid: userId }).catch((err) =>
      console.error(err)
    );
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
    hostUid: session.hostUid,
  });
};

/**
 * Internal logic to start a session and its associated recording
 */
async function startSessionInternal(sessionId) {
  let session = await Session.findOne({ sessionId });
  
  // If session is already active and recording is on, don't re-start
  if (session && session.isActive && session.recordingActive) {
    console.log(`ℹ️ Session ${sessionId} is already active with recording.`);
    return { session, recordingActive: true };
  }

  // Atomic update to mark session as active
  session = await Session.findOneAndUpdate(
    { sessionId },
    { $set: { isActive: true, startedAt: session?.startedAt || new Date() } },
    { upsert: true, new: true }
  );

  let recordingActive = !!session.recordingActive;
  try {
    // Only acquire and start if recording is not already marked as active in DB
    if (!session.recordingActive) {
      const resourceId = await acquireRecording(sessionId);
      const recordingData = await startRecording(sessionId, resourceId);

      await Session.updateOne(
        { sessionId },
        {
          $set: {
            recordingResourceId: resourceId,
            recordingSid: recordingData.sid,
            recordingActive: true,
          },
        }
      );
      recordingActive = true;
    } else {
      recordingActive = true;
    }
  } catch (err) {
    console.warn(`⚠️ Auto-recording failed for session ${sessionId}:`, err.message);
  }
  return { session, recordingActive };
}

exports.startSession = async (req, res, next) => {
  try {
    const { id: sessionId } = req.params;
    const { session, recordingActive } = await startSessionInternal(sessionId);

    res.status(200).json({
      success: true,
      sessionId,
      startedAt: session.startedAt,
      recordingActive,
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
    users: session.users.length,
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

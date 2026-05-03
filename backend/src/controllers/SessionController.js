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
        const result = await startSessionInternal(sessionId, userId, username);
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
async function startSessionInternal(sessionId, userId, username) {
  let session = await Session.findOne({ sessionId });

  // If session is already active and recording is on, don't re-start
  if (session && session.isActive && session.recordingActive) {
    console.log(`ℹ️ Session ${sessionId} is already active with recording.`);
    return { session, recordingActive: true };
  }

  // Atomic update to mark session as active
  session = await Session.findOneAndUpdate(
    { sessionId },
    {
      $set: {
        isActive: true,
        startedAt: session?.startedAt || new Date(),
        lastHeartbeat: new Date(),
        hostLastHeartbeat: new Date(),
      },
    },
    { upsert: true, new: true }
  );

  let recordingActive = !!session.recordingActive;
  try {
    // Only acquire and start if recording is not already marked as active in DB
    if (!session.recordingActive) {
      const resourceId = await acquireRecording(sessionId);
      const recordingData = await startRecording(sessionId, resourceId, userId, username);

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
    const { userId, username } = req.user;

    // ✅ FIX: userId from JWT is the Mongo ID (string).
    // Agora and our Recording schema expect a numeric UID.
    const numericUid = parseInt(userId, 10) || 1000;

    const { session, recordingActive } = await startSessionInternal(
      sessionId,
      numericUid,
      username
    );

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

/**
 * Internal logic to stop a session and its associated recording
 */
async function stopSessionInternal(sessionId) {
  const session = await Session.findOne({ sessionId });
  if (!session || !session.isActive) return { success: true, message: 'Already inactive' };

  await Session.updateOne(
    { sessionId },
    { $set: { isActive: false, stoppedAt: new Date(), recordingActive: false } }
  );

  if (session.recordingActive && session.recordingSid) {
    try {
      await stopRecording(sessionId, session.recordingResourceId, session.recordingSid, 'mix');
      console.log(`⏹️ Session ${sessionId} stopped (recording ended).`);
    } catch (err) {
      console.warn('⚠️ Auto-recording stop failed:', err.message);
    }
  }

  return { success: true, sessionId, stoppedAt: new Date() };
}

exports.stopSession = async (req, res, next) => {
  try {
    const { id: sessionId } = req.params;
    const result = await stopSessionInternal(sessionId);
    res.status(200).json(result);
  } catch (error) {
    next(error);
  }
};

const HEARTBEAT_TIMEOUT_MS = 30000; // 30 seconds

exports.sendHeartbeat = async (req, res, next) => {
  try {
    const { id: sessionId } = req.params;
    const now = new Date();

    const update = { $set: { lastHeartbeat: now } };

    // SECURITY: Only the authenticated host can update the host presence flag
    if (req.user && req.user.role === 'host') {
      update.$set.hostLastHeartbeat = now;
    }

    const session = await Session.findOneAndUpdate({ sessionId, isActive: true }, update, {
      new: true,
    });

    if (!session) {
      return res.status(404).json({ error: 'Active session not found' });
    }

    res.status(200).json({
      success: true,
      lastHeartbeat: now,
      isHost: req.user.role === 'host',
    });
  } catch (error) {
    next(error);
  }
};

/**
 * Explicitly marks the host as offline (e.g. on graceful exit)
 */
exports.setHostOffline = async (req, res, next) => {
  try {
    const { id: sessionId } = req.params;

    // Set hostLastHeartbeat to a very old date to trigger immediate "Offline" status
    await Session.updateOne({ sessionId }, { $set: { hostLastHeartbeat: new Date(0) } });

    console.log(`👤 Host ${req.user.username} manually marked offline for ${sessionId}`);
    res.status(200).json({ success: true, message: 'Host marked offline' });
  } catch (error) {
    next(error);
  }
};

exports.getSessionStatus = async (req, res) => {
  const { id: sessionId } = req.params;
  let session = await Session.findOne({ sessionId }).lean();

  if (!session) return res.json({ sessionId, isActive: false, users: 0, isJoinable: false });

  // ✅ AUTHORITATIVE CHECK: If session is active but heartbeat is stale, auto-stop it
  if (session.isActive && session.lastHeartbeat) {
    const timeSinceLastHeartbeat = Date.now() - new Date(session.lastHeartbeat).getTime();
    if (timeSinceLastHeartbeat > HEARTBEAT_TIMEOUT_MS) {
      console.warn(`🕒 Heartbeat timeout for ${sessionId}. Marking offline.`);
      await stopSessionInternal(sessionId);
      session.isActive = false; // Reflect in current response
    }
  }

  // Calculate Host Presence
  let hostOnline = false;
  if (session.isActive && session.hostLastHeartbeat) {
    const timeSinceHostHeartbeat = Date.now() - new Date(session.hostLastHeartbeat).getTime();
    hostOnline = timeSinceHostHeartbeat < HEARTBEAT_TIMEOUT_MS;
  }

  // Filter out stale users from the list (users who haven't heartbeated in 60s)
  const activeUsers = (session.users || []).filter((_) => {
    // If we had a lastHeartbeat per user we would check it here.
    // For now, we return all users registered in the session.
    return true;
  });

  res.json({
    sessionId,
    isActive: session.isActive,
    hostOnline,
    isJoinable: session.isActive && hostOnline,
    isRecording: session.isActive && !!session.recordingActive,
    participantCount: activeUsers.length,
    participants: activeUsers.map((u) => ({
      userId: u.userId,
      username: u.username,
      role: u.role,
      isSpeaking: u.isSpeaking,
    })),
    startedAt: session.startedAt,
    lastHeartbeat: session.lastHeartbeat,
  });
};

exports.recordSpeakingEvent = async (req, res, next) => {
  try {
    const { userId, sessionId, start, end } = req.body;
    if (!sessionId || !start || !end) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // SECURITY: Source of truth for identity is the authenticated user in the JWT
    const authenticatedUserId = req.user.userId;

    // Reject if the payload userId doesn't match the authenticated userId (unless host is logging for someone else, which isn't a current use case)
    if (userId !== undefined && String(userId) !== String(authenticatedUserId)) {
      console.warn(
        `🔐 Security Alert: User ${req.user.username} tried to log speaking event for user ID ${userId}`
      );
      return res.status(403).json({
        error: 'Forbidden',
        message: 'You can only log events for your own user identity.',
      });
    }

    const event = await SpeakingEvent.create({
      userId: Number(authenticatedUserId), // Use authenticated ID
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

    // SECURITY: Users can only see their own events. Hosts can see everything.
    if (req.user.role !== 'host') {
      filter.userId = req.user.userId;
    } else if (userId) {
      filter.userId = Number(userId);
    }

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

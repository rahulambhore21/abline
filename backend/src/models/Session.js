const mongoose = require('mongoose');

const SessionSchema = new mongoose.Schema(
  {
    sessionId: { type: String, required: true, unique: true },
    isActive: { type: Boolean, default: false },
    hostUid: { type: Number },
    startedAt: { type: Date },
    stoppedAt: { type: Date },
    lastHeartbeat: { type: Date },
    hostLastHeartbeat: { type: Date },
    users: [
      {
        userId: { type: Number },
        username: { type: String },
        isSpeaking: { type: Boolean, default: false },
        role: { type: String },
      },
    ],
  },
  { timestamps: true }
);

module.exports = mongoose.model('Session', SessionSchema);

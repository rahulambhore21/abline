const mongoose = require('mongoose');

const RecordingSchema = new mongoose.Schema(
  {
    recordingId: { type: String, required: true, unique: true, index: true },
    userId: { type: Number, required: true, index: true },
    username: { type: String, index: true },
    sessionId: { type: String, required: true, index: true },
    filename: { type: String, required: true },
    recordedAt: { type: Date, default: Date.now, index: true },
    durationMs: { type: Number, default: 0 },
    url: { type: String },
  },
  { timestamps: true }
);

RecordingSchema.index({ sessionId: 1, userId: 1, recordedAt: -1 });

module.exports = mongoose.model('Recording', RecordingSchema);

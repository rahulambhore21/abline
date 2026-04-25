const mongoose = require('mongoose');

const SpeakingEventSchema = new mongoose.Schema(
  {
    userId: { type: Number, required: true, index: true },
    sessionId: { type: String, required: true, index: true },
    start: { type: Date, required: true, index: true },
    end: { type: Date, required: true },
    durationMs: { type: Number, required: true },
  },
  { timestamps: true }
);

SpeakingEventSchema.index({ sessionId: 1, userId: 1, start: -1 });

module.exports = mongoose.model('SpeakingEvent', SpeakingEventSchema);

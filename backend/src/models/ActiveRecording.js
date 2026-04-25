const mongoose = require('mongoose');

const ActiveRecordingSchema = new mongoose.Schema({
  channelName: { type: String, required: true, unique: true },
  resourceId: { type: String, required: true },
  sid: { type: String, required: true },
  mode: { type: String, default: 'mix' },
  startedAt: { type: Date, default: Date.now }
});

module.exports = mongoose.model('ActiveRecording', ActiveRecordingSchema);

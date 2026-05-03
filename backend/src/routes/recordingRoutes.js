const express = require('express');
const router = express.Router();
const recordingController = require('../controllers/RecordingController');
const { authMiddleware, allowRole } = require('../middleware/auth');
const validate = require('../middleware/validate');
const schemas = require('../utils/schemas');

router.post(
  '/start',
  authMiddleware,
  allowRole('host'),
  validate(schemas.recording.start),
  recordingController.startRecording
);

router.post(
  '/stop',
  authMiddleware,
  allowRole('host'),
  validate(schemas.recording.stop),
  recordingController.stopRecording
);

router.post(
  '/save',
  authMiddleware,
  validate(schemas.recording.save),
  recordingController.saveRecording
); // Flutter app uploads

router.post(
  '/request-upload-url',
  authMiddleware,
  validate(schemas.recording.requestUrl),
  recordingController.requestUploadUrl
);

router.post('/webhook', recordingController.webhook);

router.get(
  '/',
  authMiddleware,
  validate(schemas.recording.list, 'query'),
  recordingController.listRecordings
);

router.get('/active', authMiddleware, recordingController.activeRecordings);

router.get(
  '/session/:sessionId',
  authMiddleware,
  validate(schemas.recording.list, 'query'),
  recordingController.listRecordings
);

router.get('/download/:recordingId', authMiddleware, recordingController.downloadRecording);

module.exports = router;

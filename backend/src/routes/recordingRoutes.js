const express = require('express');
const router = express.Router();
const recordingController = require('../controllers/RecordingController');
const { authMiddleware, allowRole } = require('../middleware/auth');

router.post('/start', authMiddleware, allowRole('host'), recordingController.startRecording);
router.post('/stop', authMiddleware, allowRole('host'), recordingController.stopRecording);
router.post('/save', recordingController.saveRecording); // Flutter app uploads
router.post('/webhook', recordingController.webhook);
router.get('/', authMiddleware, recordingController.listRecordings);
router.get('/active', authMiddleware, recordingController.activeRecordings);
router.get('/session/:sessionId', authMiddleware, recordingController.listRecordings);
router.get('/download/:recordingId', recordingController.downloadRecording);

module.exports = router;

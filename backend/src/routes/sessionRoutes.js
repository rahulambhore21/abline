const express = require('express');
const router = express.Router();
const sessionController = require('../controllers/SessionController');
const { authMiddleware, allowRole } = require('../middleware/auth');

router.post('/:id/users/add', sessionController.addUserToSession);
router.get('/:id/users', sessionController.getSessionUsers);
router.post('/:id/start', authMiddleware, allowRole('host'), sessionController.startSession);
router.post('/:id/stop', authMiddleware, allowRole('host'), sessionController.stopSession);
router.get('/:id/status', sessionController.getSessionStatus);
router.post('/:id/heartbeat', authMiddleware, allowRole('host'), sessionController.sendHeartbeat);

router.post('/events/speaking', authMiddleware, sessionController.recordSpeakingEvent);
router.get('/events/speaking', authMiddleware, sessionController.listSpeakingEvents);

router.get('/health', sessionController.healthCheck);

module.exports = router;

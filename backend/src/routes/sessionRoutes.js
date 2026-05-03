const express = require('express');
const router = express.Router();
const sessionController = require('../controllers/SessionController');
const { authMiddleware, allowRole } = require('../middleware/auth');
const validate = require('../middleware/validate');
const schemas = require('../utils/schemas');

router.post('/:id/users/add', validate(schemas.session.addUser), sessionController.addUserToSession);
router.get('/:id/users', sessionController.getSessionUsers);
router.post(
  '/:id/start',
  authMiddleware,
  allowRole('host'),
  validate(schemas.session.start, 'params'),
  sessionController.startSession
);
router.post(
  '/:id/stop',
  authMiddleware,
  allowRole('host'),
  validate(schemas.session.start, 'params'),
  sessionController.stopSession
);
router.get('/:id/status', sessionController.getSessionStatus);
router.post('/:id/heartbeat', authMiddleware, sessionController.sendHeartbeat);
router.post(
  '/:id/host/offline',
  authMiddleware,
  allowRole('host'),
  sessionController.setHostOffline
);

router.post(
  '/events/speaking',
  authMiddleware,
  validate(schemas.session.speakingEvent),
  sessionController.recordSpeakingEvent
);


router.get('/events/speaking', authMiddleware, sessionController.listSpeakingEvents);

router.get('/health', sessionController.healthCheck);

module.exports = router;


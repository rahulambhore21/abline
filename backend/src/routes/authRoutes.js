const express = require('express');
const router = express.Router();
const authController = require('../controllers/AuthController');
const { authMiddleware, allowRole } = require('../middleware/auth');

router.post('/register-host', authController.registerHost);
router.post('/login', authController.login);
router.post('/create-user', authMiddleware, allowRole('host'), authController.createUser);
router.get('/users', authMiddleware, allowRole('host'), authController.listUsers);
router.get('/host', authController.getHost);

module.exports = router;

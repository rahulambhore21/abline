const express = require('express');
const router = express.Router();
const authController = require('../controllers/AuthController');
const { authMiddleware, allowRole } = require('../middleware/auth');

router.post('/register-host', authController.registerHost);
router.post('/login', authController.login);
router.post('/create-user', authMiddleware, allowRole('host'), authController.createUser);
router.get('/users', authMiddleware, allowRole('host'), authController.listUsers);
router.delete('/users/:id', authMiddleware, allowRole('host'), authController.deleteUser);
router.get('/host', authController.getHost);

// SECURITY: Backend PIN verification for destructive actions
router.post('/verify-pin', authMiddleware, allowRole('host'), authController.verifyAdminPin);

module.exports = router;

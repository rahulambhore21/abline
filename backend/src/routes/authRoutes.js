const express = require('express');
const router = express.Router();
const authController = require('../controllers/AuthController');
const { authMiddleware, allowRole } = require('../middleware/auth');
const validate = require('../middleware/validate');
const schemas = require('../utils/schemas');

router.post('/register-host', validate(schemas.auth.register), authController.registerHost);
router.post('/login', validate(schemas.auth.login), authController.login);
router.post(
  '/create-user',
  authMiddleware,
  allowRole('host'),
  validate(schemas.auth.register),
  authController.createUser
);
router.get('/users', authMiddleware, allowRole('host'), authController.listUsers);
router.delete('/users/:id', authMiddleware, allowRole('host'), authController.deleteUser);
router.get('/host', authController.getHost);

// SECURITY: Backend PIN verification for destructive actions
router.post(
  '/verify-pin',
  authMiddleware,
  allowRole('host'),
  validate(schemas.auth.deleteUser),
  authController.verifyAdminPin
);

module.exports = router;


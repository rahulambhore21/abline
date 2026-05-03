const User = require('../models/User');
const jwt = require('jsonwebtoken');
const { ensureMongoForAuth } = require('../utils/dbHelpers');

const JWT_SECRET = process.env.JWT_SECRET;
const JWT_EXPIRY = process.env.JWT_EXPIRY || '1d';

exports.registerHost = async (req, res, next) => {
  try {
    if (!ensureMongoForAuth(res)) return;

    const { username, password } = req.body;

    if (!username || !password) {
      return res.status(400).json({ error: 'Missing required fields: username, password' });
    }

    const existingHost = await User.findOne({ role: 'host' });
    if (existingHost) {
      return res.status(400).json({
        error: 'Host user already exists',
        message: 'A host user has already been registered',
      });
    }

    const host = new User({ username, password, role: 'host' });
    await host.save();

    console.log(`✅ Host user created: ${username}`);

    res.status(201).json({
      success: true,
      userId: host._id,
      message: `Host '${username}' created successfully`,
    });
  } catch (error) {
    if (error.code === 11000) {
      return res.status(400).json({ error: 'Username already taken' });
    }
    next(error);
  }
};

exports.createUser = async (req, res, next) => {
  try {
    if (!ensureMongoForAuth(res)) return;

    const { username, password } = req.body;

    if (!username || !password) {
      return res.status(400).json({ error: 'Missing required fields: username, password' });
    }

    const user = new User({ username, password, role: 'user' });
    await user.save();

    console.log(`✅ User created by host ${req.user.username}: ${username}`);

    res.status(201).json({
      success: true,
      userId: user._id,
      message: `User '${username}' created successfully`,
    });
  } catch (error) {
    if (error.code === 11000) {
      return res.status(400).json({ error: 'Username already taken' });
    }
    next(error);
  }
};

exports.login = async (req, res, next) => {
  try {
    if (!ensureMongoForAuth(res)) return;

    if (!JWT_SECRET) {
      console.error('FATAL: JWT_SECRET environment variable is not set.');
      return res.status(500).json({ error: 'Configuration Error' });
    }

    const { username, password } = req.body;

    if (!username || !password) {
      return res.status(400).json({ error: 'Missing required fields: username, password' });
    }

    const user = await User.findOne({ username }).select('+password');

    // SECURITY: Use generic error message to prevent username enumeration
    if (!user) {
      return res.status(401).json({
        error: 'Invalid credentials',
        message: 'Invalid username or password',
      });
    }

    const isPasswordValid = await user.comparePassword(password);

    if (!isPasswordValid) {
      return res.status(401).json({
        error: 'Invalid credentials',
        message: 'Invalid username or password',
      });
    }

    const token = jwt.sign(
      { userId: user._id, username: user.username, role: user.role },
      JWT_SECRET,
      { expiresIn: JWT_EXPIRY }
    );

    console.log(`✅ User logged in: ${username} (role: ${user.role})`);

    res.json({
      success: true,
      token,
      role: user.role,
      userId: user._id.toString(),
      username: user.username,
      expiresIn: JWT_EXPIRY,
      message: 'Login successful',
    });
  } catch (error) {
    next(error);
  }
};

exports.listUsers = async (req, res, next) => {
  try {
    if (!ensureMongoForAuth(res)) return;

    const users = await User.find().select('_id username role createdAt').lean();

    res.json({
      success: true,
      users: users.map((u) => ({
        id: u._id,
        username: u.username,
        role: u.role,
        createdAt: u.createdAt,
      })),
      count: users.length,
    });
  } catch (error) {
    next(error);
  }
};

exports.deleteUser = async (req, res, next) => {
  try {
    if (!ensureMongoForAuth(res)) return;

    const { id } = req.params;

    const user = await User.findById(id);

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    if (user.role === 'host') {
      return res.status(403).json({ error: 'Cannot delete the host user' });
    }

    await User.findByIdAndDelete(id);

    console.log(`🗑️ User deleted by host ${req.user.username}: ${user.username}`);

    res.json({
      success: true,
      message: `User '${user.username}' deleted successfully`,
    });
  } catch (error) {
    next(error);
  }
};

exports.getHost = async (req, res, next) => {
  try {
    const host = await User.findOne({ role: 'host' }).select('username').lean();
    res.json({ username: host ? host.username : null });
  } catch (error) {
    next(error);
  }
};

/**
 * Verifies the administrative PIN for destructive actions
 */
exports.verifyAdminPin = async (req, res) => {
  try {
    const { pin } = req.body;
    
    // In production, this should be fetched from environment variables.
    // If not set, we use a default but log a severe warning.
    const systemPin = process.env.ADMIN_DELETE_PIN;
    
    if (!systemPin) {
      console.error('🛑 SECURITY WARNING: ADMIN_DELETE_PIN not set in environment.');
      return res.status(500).json({ 
        error: 'Configuration Error', 
        message: 'Administrative actions are currently disabled for security reasons.' 
      });
    }

    if (String(pin) === String(systemPin)) {
      return res.json({ success: true, message: 'PIN verified' });
    } else {
      console.warn(`🔐 Failed PIN attempt by ${req.user.username}`);
      return res.status(401).json({ success: false, message: 'Invalid administrative PIN' });
    }
  } catch (error) {
    res.status(500).json({ error: 'Verification failed', message: error.message });
  }
};

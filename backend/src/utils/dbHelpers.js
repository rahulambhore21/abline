const mongoose = require('mongoose');

function ensureMongoForAuth(res) {
  const MONGODB_URI = process.env.MONGODB_URI;
  const isConfigured = Boolean(MONGODB_URI && String(MONGODB_URI).trim());
  const isConnected = mongoose.connection?.readyState === 1;

  if (!isConfigured) {
    res.status(503).json({
      error: 'MongoDB not configured',
      message:
        'Authentication requires MongoDB. Set MONGODB_URI in backend/.env and restart the server.',
    });
    return false;
  }

  if (!isConnected) {
    res.status(503).json({
      error: 'MongoDB not connected',
      message: 'MongoDB is configured but not reachable. Start MongoDB and restart the server.',
    });
    return false;
  }

  return true;
}

module.exports = { ensureMongoForAuth };

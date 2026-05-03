const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env'), override: true });
const mongoose = require('mongoose');

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const morgan = require('morgan');
const fileUpload = require('express-fileupload');
const logger = require('./src/utils/logger');
const connectDB = require('./src/config/db');
const errorHandler = require('./src/middleware/error');
const { authMiddleware } = require('./src/middleware/auth');

const authRoutes = require('./src/routes/authRoutes');
const recordingRoutes = require('./src/routes/recordingRoutes');
const sessionRoutes = require('./src/routes/sessionRoutes');
const agoraController = require('./src/controllers/AgoraController');

const recordingController = require('./src/controllers/RecordingController');

const app = express();
const PORT = process.env.PORT || 5000;

// --- ENVIRONMENT VALIDATION ---
const requiredEnv = [
  'JWT_SECRET',
  'AGORA_APP_ID',
  'AGORA_APP_CERTIFICATE',
  'MONGODB_URI',
  'ADMIN_DELETE_PIN',
];
const missingEnv = requiredEnv.filter((env) => !process.env[env]);

if (missingEnv.length > 0) {
  logger.error(`❌ FATAL: Missing required environment variables: ${missingEnv.join(', ')}`);
  if (process.env.NODE_ENV === 'production') {
    process.exit(1);
  } else {
    logger.warn('⚠️ Server will likely fail in production mode.');
  }
}

// Middleware
app.use(helmet());

// --- RESTRICTED CORS ---
const corsOptions = {
  origin: process.env.ALLOWED_ORIGINS ? process.env.ALLOWED_ORIGINS.split(',') : '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization'],
};

if (
  process.env.NODE_ENV === 'production' &&
  (!process.env.ALLOWED_ORIGINS || process.env.ALLOWED_ORIGINS === '*')
) {
  logger.warn('⚠️ SECURITY WARNING: CORS is wide open in production. Set ALLOWED_ORIGINS.');
}
app.use(cors(corsOptions));

app.use(compression());
app.use(
  morgan(process.env.NODE_ENV === 'production' ? 'combined' : 'dev', { stream: logger.stream })
);
app.use(express.json());
app.use(fileUpload());

// --- HEALTH CHECK (Hardened) ---
app.get('/health', async (req, res) => {
  const health = {
    status: 'UP',
    timestamp: new Date(),
    uptime: process.uptime(),
    dependencies: {
      mongodb: 'DOWN',
      storage: 'UNKNOWN',
    },
    config: {
      node_env: process.env.NODE_ENV,
    },
  };

  try {
    // Check DB
    if (mongoose.connection.readyState === 1) {
      health.dependencies.mongodb = 'UP';
    }

    // Check S3/Storage config
    const hasS3 = !!(process.env.RECORDING_BUCKET && process.env.RECORDING_ACCESS_KEY);
    health.dependencies.storage = hasS3 ? 'CONFIGURED' : 'MISSING';

    const status = health.dependencies.mongodb === 'UP' ? 200 : 503;
    res.status(status).json(health);
  } catch (error) {
    health.status = 'DOWN';
    health.error = error.message;
    res.status(500).json(health);
  }
});

// --- MODULAR ROUTES ---
app.use('/auth', authRoutes);
app.use('/recording', recordingRoutes);
app.use('/session', sessionRoutes);

// --- AGORA ROUTES (Now Secured) ---
app.get('/agora/token', authMiddleware, agoraController.getToken);

// --- LEGACY COMPATIBILITY ROUTES REMOVED FOR SECURITY ---
// (Previously unprotected root-level paths)
// -----------------------------------------------------------------

// Global Error Handler
app.use(errorHandler);

// Start Server
const start = async () => {
  try {
    const connected = await connectDB();
    if (!connected) {
      logger.warn('⚠️ Starting server without MongoDB...');
    } else {
      const dbName = mongoose.connection.name;
      const dbHost = mongoose.connection.host;
      logger.info(`📡 Connected to MongoDB: ${dbName} on ${dbHost}`);
    }

    // Initialize recording storage after DB attempt
    logger.info('📦 S3 Configuration Status', {
      bucket: process.env.RECORDING_BUCKET ? '✅ Set' : '❌ MISSING',
      region: process.env.RECORDING_REGION ? '✅ Set' : '❌ MISSING',
      accessKey: process.env.RECORDING_ACCESS_KEY ? '✅ Set' : '❌ MISSING',
    });

    try {
      await recordingController.initializeRecordingsStorage();
    } catch (err) {
      logger.warn(`⚠️ Could not initialize recordings storage: ${err.message}`);
    }

    // Initialize automatic cleanup
    try {
      const { initCleanupTask } = require('./src/services/CleanupService');
      initCleanupTask();
    } catch (err) {
      logger.warn(`⚠️ Could not initialize cleanup task: ${err.message}`);
    }

    app.listen(PORT, () => {
      logger.info(`🚀 Server running on port ${PORT}`);
    });
  } catch (error) {
    logger.error(`❌ Failed to start server: ${error.message}`, { stack: error.stack });
    process.exit(1);
  }
};

if (require.main === module) {
  start();
}

module.exports = app;

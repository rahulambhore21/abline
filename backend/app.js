const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env'), override: true });
const mongoose = require('mongoose');

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const morgan = require('morgan');
const fileUpload = require('express-fileupload');
const connectDB = require('./src/config/db');
const errorHandler = require('./src/middleware/error');
const { authMiddleware, allowRole } = require('./src/middleware/auth');

const authRoutes = require('./src/routes/authRoutes');
const recordingRoutes = require('./src/routes/recordingRoutes');
const sessionRoutes = require('./src/routes/sessionRoutes');
const agoraController = require('./src/controllers/AgoraController');
const authController = require('./src/controllers/AuthController');
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
  console.error(`❌ FATAL: Missing required environment variables: ${missingEnv.join(', ')}`);
  if (process.env.NODE_ENV === 'production') {
    process.exit(1);
  } else {
    console.warn('⚠️ Server will likely fail in production mode.');
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

if (process.env.NODE_ENV === 'production' && (!process.env.ALLOWED_ORIGINS || process.env.ALLOWED_ORIGINS === '*')) {
  console.warn('⚠️ SECURITY WARNING: CORS is wide open in production. Set ALLOWED_ORIGINS.');
}
app.use(cors(corsOptions));

app.use(compression());
app.use(morgan(process.env.NODE_ENV === 'production' ? 'combined' : 'dev'));
app.use(express.json());
app.use(fileUpload());

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
      console.warn('⚠️ Starting server without MongoDB...');
    } else {
      const dbName = mongoose.connection.name;
      const dbHost = mongoose.connection.host;
      console.log(`📡 Connected to MongoDB: ${dbName} on ${dbHost}`);
    }

    // Initialize recording storage after DB attempt
    console.log('📦 S3 Configuration Status:', {
      bucket: process.env.RECORDING_BUCKET ? '✅ Set' : '❌ MISSING',
      region: process.env.RECORDING_REGION ? '✅ Set' : '❌ MISSING',
      accessKey: process.env.RECORDING_ACCESS_KEY ? '✅ Set' : '❌ MISSING',
    });

    try {
      await recordingController.initializeRecordingsStorage();
    } catch (err) {
      console.warn('⚠️ Could not initialize recordings storage:', err.message);
    }

    // Initialize automatic cleanup
    try {
      const { initCleanupTask } = require('./src/services/CleanupService');
      initCleanupTask();
    } catch (err) {
      console.warn('⚠️ Could not initialize cleanup task:', err.message);
    }

    app.listen(PORT, () => {
      console.log(`🚀 Server running on port ${PORT}`);
    });
  } catch (error) {
    console.error('❌ Failed to start server:', error.message);
    process.exit(1);
  }
};

if (require.main === module) {
  start();
}

module.exports = app;

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
const { apiLimiter, authLimiter } = require('./src/middleware/rateLimiter');

const authRoutes = require('./src/routes/authRoutes');
const recordingRoutes = require('./src/routes/recordingRoutes');
const sessionRoutes = require('./src/routes/sessionRoutes');
const agoraController = require('./src/controllers/AgoraController');
const authController = require('./src/controllers/AuthController');
const recordingController = require('./src/controllers/RecordingController');

const app = express();
const PORT = process.env.PORT || 5000;

// Middleware
app.use(helmet());
app.use(cors());
app.use(compression());
app.use(morgan('dev'));
app.use(express.json());
app.use(fileUpload());

// --- MODULAR ROUTES ---
app.use('/auth', authLimiter, authRoutes);
app.use('/recording', apiLimiter, recordingRoutes);
app.use('/session', apiLimiter, sessionRoutes);

// --- AGORA ROUTES ---
app.get('/agora/token', apiLimiter, agoraController.getToken);

// --- LEGACY COMPATIBILITY ROUTES (Root level paths used by older frontend) ---
// Session/Speaking events
app.use('/', apiLimiter, sessionRoutes); 

// Auth compatibility (Secure them same as modular routes)
app.get('/users', apiLimiter, authMiddleware, allowRole('host'), authController.listUsers);
app.get('/host', apiLimiter, authController.getHost);

// Recording compatibility
app.use('/recordings', apiLimiter, recordingRoutes); 
app.post('/start-recording', apiLimiter, authMiddleware, allowRole('host'), recordingController.startRecording);
app.post('/stop-recording', apiLimiter, authMiddleware, allowRole('host'), recordingController.stopRecording);
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

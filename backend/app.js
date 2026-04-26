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

// Middleware
app.use(helmet());
app.use(cors());
app.use(compression());
app.use(morgan('dev'));
app.use(express.json());
app.use(fileUpload());

// --- MODULAR ROUTES ---
app.use('/auth', authRoutes);
app.use('/recording', recordingRoutes);
app.use('/session', sessionRoutes);

// --- AGORA ROUTES ---
app.get('/agora/token', agoraController.getToken);

// --- LEGACY COMPATIBILITY ROUTES (Root level paths used by older frontend) ---
// Session/Speaking events
app.use('/', sessionRoutes); 

// Auth compatibility (Secure them same as modular routes)
app.get('/users', authMiddleware, allowRole('host'), authController.listUsers);
app.get('/host', authController.getHost);

// Recording compatibility
app.use('/recordings', recordingRoutes); 
app.post('/start-recording', authMiddleware, allowRole('host'), recordingController.startRecording);
app.post('/stop-recording', authMiddleware, allowRole('host'), recordingController.stopRecording);
// -----------------------------------------------------------------

// Global Error Handler
app.use(errorHandler);

// Start Server
const start = async () => {
  try {
    await connectDB();
    const dbName = mongoose.connection.name;
    const dbHost = mongoose.connection.host;
    console.log(`📡 Connected to MongoDB: ${dbName} on ${dbHost}`);
    
    // Initialize recording storage after DB is connected

    console.log('📦 S3 Configuration Status:', {
      bucket: process.env.RECORDING_BUCKET ? '✅ Set' : '❌ MISSING',
      region: process.env.RECORDING_REGION ? '✅ Set' : '❌ MISSING',
      accessKey: process.env.RECORDING_ACCESS_KEY ? '✅ Set' : '❌ MISSING',
    });

    await recordingController.initializeRecordingsStorage();

    // Perform a startup S3 connectivity test
    try {
      const { uploadToS3 } = require('./src/services/S3Service');
      const testFilename = `startup_test_${Date.now()}.txt`;
      await uploadToS3(Buffer.from('connectivity test'), testFilename, 'text/plain');
      console.log('✅ Global Persistence Test: S3 Connectivity Verified');
    } catch (s3Error) {
      console.error('⚠️ Global Persistence Test: S3 Connectivity Failed!', s3Error.message);
    }
    app.listen(PORT, () => {
      console.log(`🚀 Server running on port ${PORT}`);
    });
  } catch (error) {
    console.error('❌ Failed to start server:', error.message);
    process.exit(1);
  }
};

start();

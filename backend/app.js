require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const morgan = require('morgan');
const fileUpload = require('express-fileupload');
const connectDB = require('./src/config/db');
const errorHandler = require('./src/middleware/error');

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

// Auth compatibility
app.get('/users', authController.listUsers);
app.get('/host', authController.getHost);

// Recording compatibility
app.use('/recordings', recordingRoutes); 
app.post('/start-recording', recordingController.startRecording);
app.post('/stop-recording', recordingController.stopRecording);
// -----------------------------------------------------------------

// Global Error Handler
app.use(errorHandler);

// Start Server
const start = async () => {
  try {
    await connectDB();
    app.listen(PORT, () => {
      console.log(`🚀 Server running on port ${PORT}`);
    });
  } catch (error) {
    console.error('❌ Failed to start server:', error.message);
    process.exit(1);
  }
};

start();

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

const app = express();
const PORT = process.env.PORT || 5000;

// Middleware
app.use(helmet());
app.use(cors());
app.use(compression());
app.use(morgan('dev'));
app.use(express.json());
app.use(fileUpload());

// Routes
app.use('/auth', authRoutes);
app.use('/recording', recordingRoutes);
app.use('/session', sessionRoutes);
// Compatibility for old paths
app.use('/', sessionRoutes); 

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

const mongoose = require('mongoose');

const connectDB = async () => {
  const MONGODB_URI = process.env.MONGODB_URI;

  if (!MONGODB_URI) {
    console.warn(
      '⚠️ MONGODB_URI not set. Speaking events will be stored in-memory. Authentication endpoints will return 503 until MongoDB is configured.'
    );
    return false;
  }

  try {
    // Fail fast when MongoDB is not connected instead of buffering queries.
    mongoose.set('bufferCommands', false);

    await mongoose.connect(MONGODB_URI, {
      serverSelectionTimeoutMS: 5000,
    });
    console.log('✅ MongoDB connected.');
    return true;
  } catch (err) {
    console.error('❌ MongoDB connection failed:', err.message);
    return false;
  }
};

module.exports = connectDB;

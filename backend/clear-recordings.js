/**
 * Clear all old recordings - disk, database, and metadata
 * Run with: node backend/clear-recordings.js
 */

require('dotenv').config();
const mongoose = require('mongoose');
const path = require('path');
const fs = require('fs');

const MONGODB_URI = process.env.MONGODB_URI;
const RECORDINGS_METADATA_FILE = path.join(__dirname, '.recordings-metadata.json');
const RECORDINGS_DIR = path.join(__dirname, 'recordings');

// Define Recording Model
const RecordingSchema = new mongoose.Schema(
  {
    recordingId: { type: String, required: true, unique: true, index: true },
    userId: { type: Number, required: true, index: true },
    sessionId: { type: String, required: true, index: true },
    filename: { type: String, required: true },
    recordedAt: { type: Date, default: Date.now, index: true },
    durationMs: { type: Number, default: 0 },
    url: { type: String },
  },
  { timestamps: true }
);

const RecordingModel = mongoose.model('Recording', RecordingSchema);

async function clearAllRecordings() {
  try {
    console.log('🗑️  Starting to clear all recordings...\n');

    // Step 1: Delete recording files from disk
    console.log('📁 Deleting recording files from disk...');
    if (fs.existsSync(RECORDINGS_DIR)) {
      const files = fs.readdirSync(RECORDINGS_DIR);
      let deletedCount = 0;

      for (const file of files) {
        const filePath = path.join(RECORDINGS_DIR, file);
        try {
          fs.unlinkSync(filePath);
          deletedCount++;
          console.log(`   ✅ Deleted: ${file}`);
        } catch (error) {
          console.error(`   ❌ Error deleting ${file}:`, error.message);
        }
      }

      console.log(`✅ Deleted ${deletedCount} recording files from disk\n`);
    } else {
      console.log('⚠️  Recordings directory does not exist\n');
    }

    // Step 2: Delete metadata file from disk
    console.log('📄 Deleting metadata file...');
    if (fs.existsSync(RECORDINGS_METADATA_FILE)) {
      fs.unlinkSync(RECORDINGS_METADATA_FILE);
      console.log(`✅ Deleted metadata file: ${RECORDINGS_METADATA_FILE}\n`);
    } else {
      console.log('⚠️  Metadata file does not exist\n');
    }

    // Step 3: Delete all recordings from MongoDB (if connected)
    if (MONGODB_URI && String(MONGODB_URI).trim()) {
      console.log('📚 Connecting to MongoDB...');
      await mongoose.connect(MONGODB_URI, {
        serverSelectionTimeoutMS: 5000,
      });

      console.log('✅ Connected to MongoDB\n');

      console.log('🗑️  Deleting all recordings from MongoDB...');
      const result = await RecordingModel.deleteMany({});
      console.log(`✅ Deleted ${result.deletedCount} recordings from MongoDB\n`);

      await mongoose.disconnect();
      console.log('✅ Disconnected from MongoDB\n');
    } else {
      console.log('⚠️  MongoDB not configured - skipping database cleanup\n');
    }

    console.log('=' * 60);
    console.log('🎉 All recordings have been cleared successfully!');
    console.log('   • Disk files: Deleted ✅');
    console.log('   • Metadata file: Deleted ✅');
    if (MONGODB_URI) {
      console.log('   • Database: Cleared ✅');
    }
    console.log('=' * 60);
    console.log('\nYou can now start fresh with new recordings.\n');

    process.exit(0);
  } catch (error) {
    console.error('❌ Error clearing recordings:', error.message);
    console.error(error);
    process.exit(1);
  }
}

clearAllRecordings();

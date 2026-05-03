const Recording = require('../models/Recording');
const { deleteFromS3 } = require('./S3Service');

/**
 * Deletes recordings older than 7 days from S3 and MongoDB
 */
/**
 * Deletes recordings older than 7 days from S3 and MongoDB
 * SCALE-SAFE: Uses cursors to avoid loading all documents into memory
 */
async function cleanupOldRecordings() {
  try {
    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

    console.log(`🧹 Starting cleanup for recordings older than: ${sevenDaysAgo.toISOString()}`);

    // Use .cursor() to stream documents one by one (Memory Efficient)
    const cursor = Recording.find({
      recordedAt: { $lt: sevenDaysAgo },
    }).cursor();

    let successCount = 0;
    let errorCount = 0;

    for (let recording = await cursor.next(); recording != null; recording = await cursor.next()) {
      try {
        // Delete from S3
        if (recording.filename) {
          await deleteFromS3(recording.filename);
        }

        // Delete from MongoDB
        await Recording.deleteOne({ _id: recording._id });

        successCount++;
        if (successCount % 50 === 0) {
          console.log(`   ... processed ${successCount} deletions`);
        }
      } catch (err) {
        errorCount++;
        console.error(`   ❌ Failed to delete recording ${recording.recordingId}: ${err.message}`);
      }
    }

    console.log(`📊 Cleanup Summary: ${successCount} deleted, ${errorCount} failed.`);
  } catch (error) {
    console.error('❌ Error during recordings cleanup:', error.message);
  }
}

/**
 * Initializes the cleanup task to run at a predictable off-peak time (3 AM)
 */
function initCleanupTask() {
  // Check every minute if it's 3:00 AM
  setInterval(() => {
    const now = new Date();
    if (now.getHours() === 3 && now.getMinutes() === 0) {
      cleanupOldRecordings();
    }
  }, 60 * 1000);

  // Also run once on startup for safety (optional, but good for visibility)
  console.log('⏰ Recordings cleanup task scheduled for 3:00 AM daily.');
}

module.exports = {
  cleanupOldRecordings,
  initCleanupTask,
};

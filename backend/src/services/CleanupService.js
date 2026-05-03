const Recording = require('../models/Recording');
const { deleteFromS3 } = require('./S3Service');

/**
 * Deletes recordings older than 7 days from S3 and MongoDB
 */
async function cleanupOldRecordings() {
  try {
    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

    console.log(`🧹 Starting cleanup for recordings older than: ${sevenDaysAgo.toISOString()}`);

    const oldRecordings = await Recording.find({
      recordedAt: { $lt: sevenDaysAgo },
    });

    if (oldRecordings.length === 0) {
      console.log('✅ No old recordings found for cleanup.');
      return;
    }

    console.log(`🗑️ Found ${oldRecordings.length} recordings to delete.`);

    let successCount = 0;
    let errorCount = 0;

    for (const recording of oldRecordings) {
      try {
        // Delete from S3
        if (recording.filename) {
          await deleteFromS3(recording.filename);
        }

        // Delete from MongoDB
        await Recording.deleteOne({ _id: recording._id });

        successCount++;
        console.log(`   ✅ Deleted recording: ${recording.recordingId}`);
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
 * Initializes the daily cleanup task
 */
function initCleanupTask() {
  // Run once on startup
  cleanupOldRecordings();

  // Schedule to run every 24 hours
  const TWENTY_FOUR_HOURS = 24 * 60 * 60 * 1000;
  setInterval(cleanupOldRecordings, TWENTY_FOUR_HOURS);

  console.log('⏰ Recordings cleanup task scheduled to run every 24 hours.');
}

module.exports = {
  cleanupOldRecordings,
  initCleanupTask,
};

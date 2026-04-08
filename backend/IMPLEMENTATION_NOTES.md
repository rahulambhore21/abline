# Implementation Notes: Agora Cloud Recording

## Overview

This document describes the implementation of Agora Cloud Recording in INDIVIDUAL mode for the Express.js backend.

## What Was Implemented

### 1. **Recording Service Functions** (in app.js)

#### Core Functions

```javascript
acquireRecording(channelName)
  └─ Calls Agora /cloud_recording/acquire API
  └─ Returns: resourceId (used in subsequent calls)

startRecording(channelName, resourceId)
  └─ Calls Agora /cloud_recording/resourceid/{resourceId}/start API
  └─ Configuration: INDIVIDUAL mode, audio-only
  └─ Returns: {resourceId, sid}

stopRecording(channelName, resourceId, sid)
  └─ Calls Agora /cloud_recording/resourceid/{resourceId}/sid/{sid}/stop API
  └─ Removes from activeRecordings map

getActiveRecording(channelName)
  └─ Returns info about an active recording (for debugging)

getAllActiveRecordings()
  └─ Returns all active recordings
```

### 2. **API Endpoints** (in app.js)

#### POST /recording/start
- Initiates a new recording session
- Calls acquire → start (2-step flow)
- Returns resourceId and sid for later reference
- Error handling for missing credentials or API failures

#### POST /recording/stop
- Stops an active recording
- Requires resourceId and sid from start response
- Removes recording from activeRecordings map

#### POST /recording/webhook
- Receives callbacks from Agora when files are ready
- Extracts user ID from filename
- Logs file information for debugging
- TODO: Extend to save recording metadata to MongoDB

#### GET /recording/active
- Returns all active recordings (for debugging/monitoring)
- Shows resourceId, sid, channelName, startedAt time

### 3. **Configuration**

All recording calls use:

```javascript
{
  recordingMode: 'individual',      // ✅ CRITICAL: Each user separately
  recordingConfig: {
    maxIdleTime: 30,                // Stop after 30s silence
    streamTypes: 0,                 // 0=audio-only, 1=video, 2=both
    channelType: 0,                 // 0=channel mode
    audioProfile: 1,                // 1=48kHz mono (high quality)
  },
  recordingFileConfig: {
    avFileType: ['hls', 'mp4'],     // Output formats
  },
  storageConfig: {...}              // Placeholder for cloud storage
}
```

### 4. **Authentication**

Uses HTTP Basic Auth with Agora credentials:

```javascript
Authorization: Basic <base64(CUSTOMER_ID:CUSTOMER_SECRET)>
```

This is different from RTC token generation:
- **RTC Token:** Uses APP_ID + APP_CERTIFICATE (for clients)
- **Cloud Recording:** Uses CUSTOMER_ID + CUSTOMER_SECRET (for server)

### 5. **Error Handling**

- Validates all credentials before making API calls
- Catches and logs API errors from Agora
- Returns meaningful error messages to client
- Always returns 200 for webhook (Agora requirement)

### 6. **In-Memory Recording Tracking**

Uses a Map to store active recordings:

```javascript
activeRecordings = Map{
  "channel-name" → {
    resourceId,
    sid,
    channelName,
    startedAt
  }
}
```

This helps with:
- Preventing duplicate recordings
- Tracking recording duration
- Debugging stuck recordings

---

## Key Design Decisions

### 1. INDIVIDUAL Mode (Not COMPOSITE)

**Why:** Each user's audio is recorded to a separate file
- More flexible (can delete individual recordings)
- Better quality control
- Easier to store per-user
- Can apply per-user processing

**Alternative (Not used):**
- COMPOSITE mode records all users mixed into one file

### 2. Audio-Only (streamTypes: 0)

**Why:** Per requirements, focus on audio for voice calls
- Smaller file sizes
- Faster processing
- Sufficient for voice-only features

**If video needed later:**
```javascript
streamTypes: 2,  // Both audio and video
```

### 3. HTTP Basic Auth

**Why:** Agora Cloud Recording uses HTTP Basic Auth (not tokens)
- Simpler than OAuth for server-to-server
- Credentials in .env (not exposed to clients)
- Standard HTTP authentication

### 4. In-Memory Recording Map

**Why:** Track active recordings without database
- Fast lookups
- Easy debugging with GET /recording/active
- Can be moved to MongoDB later for persistence

**For production:**
```javascript
// Replace Map with database
async function startRecording(...) {
  // ... Agora call ...
  await RecordingSession.create({
    channelName,
    resourceId,
    sid,
    startedAt: new Date()
  });
}
```

### 5. Webhook Returns 200 Always

**Why:** Agora expects 200 even on processing errors
- Prevents Agora from retrying indefinitely
- Error details logged for debugging
- Client can query status separately if needed

---

## Integration Points

### Frontend (Flutter App)

1. **Get recording IDs when starting call:**
```dart
POST /recording/start → {resourceId, sid}
```

2. **Pass to stop API when ending call:**
```dart
POST /recording/stop + {resourceId, sid}
```

3. **Receive webhook notifications** (backend → Firebase Cloud Messaging or polling)

4. **Query recordings:**
```dart
GET /api/recordings?userId=123&sessionId=session-123
```

### Storage Integration

Currently has placeholder storageConfig. To use real storage:

**AWS S3:**
```javascript
storageConfig: {
  vendor: 1,
  region: 0,  // us-east-1
  bucket: 'my-agora-recordings',
  accessKey: 'AWS_ACCESS_KEY_ID',
  secretKey: 'AWS_SECRET_ACCESS_KEY'
}
```

**Alibaba OSS:**
```javascript
storageConfig: {
  vendor: 2,
  region: 0,
  bucket: 'oss-bucket-name',
  accessKey: 'OSS_ACCESS_KEY',
  secretKey: 'OSS_SECRET_KEY'
}
```

### MongoDB Integration

TODO: Implement RecordingFile schema

```javascript
const RecordingFileSchema = new Schema({
  userId: String,
  sessionId: String,
  filename: String,
  trackType: String,
  fileUrl: String,
  resourceId: String,
  sid: String,
  recordedAt: Date,
  duration: Number,  // calculated after webhook
  size: Number,      // from storage
  status: String,    // 'pending', 'ready', 'archived'
}, {timestamps: true});
```

Use in webhook handler:
```javascript
app.post('/recording/webhook', async (req, res) => {
  // ... existing code ...
  
  for (const file of fileList) {
    const userId = uidMatch ? uidMatch[1] : uid;
    await RecordingFile.create({
      userId,
      sessionId: cname,
      filename,
      trackType,
      fileUrl: `${AGORA_CDN_URL}/${filename}`,
      recordedAt: new Date()
    });
  }
});
```

---

## Testing Checklist

### Local Testing

- [ ] npm install axios (if not already installed)
- [ ] Set AGORA_CUSTOMER_ID and AGORA_CUSTOMER_SECRET in .env
- [ ] Start server: npm run dev
- [ ] Check logs show recording endpoints registered
- [ ] POST /recording/start → should return resourceId + sid (or error with credentials)
- [ ] GET /recording/active → should show active recordings
- [ ] POST /recording/stop → should remove from active recordings

### Integration Testing

- [ ] Create test channel with multiple users
- [ ] Call /recording/start
- [ ] Users join and speak
- [ ] Call /recording/stop
- [ ] Wait for webhook callback (may take minutes in real scenario)
- [ ] Verify files in storage (S3, OSS, etc.)
- [ ] Check MongoDB for recording metadata

### Error Testing

- [ ] Missing AGORA_CUSTOMER_ID → should return error
- [ ] Missing AGORA_CUSTOMER_SECRET → should return error
- [ ] Invalid resourceId → should return error from Agora
- [ ] Invalid sid → should return error from Agora
- [ ] Network failure → should catch and report

---

## Production Deployment Checklist

### Security

- [ ] Credentials in environment variables (never hardcoded)
- [ ] Webhook URL uses HTTPS
- [ ] Webhook authentication implemented
- [ ] API endpoints behind authentication
- [ ] Rate limiting implemented
- [ ] Input validation for all endpoints

### Configuration

- [ ] Storage configured (AWS S3, Alibaba OSS, or Agora cloud)
- [ ] Storage credentials secure (env vars or IAM roles)
- [ ] Webhook URL set in Agora console
- [ ] Webhook authentication token set if needed

### Monitoring

- [ ] Error logging to external service (Sentry, LogRocket)
- [ ] Recording metrics (count, duration, size)
- [ ] Webhook delivery monitoring
- [ ] Failed recording alerts

### Database

- [ ] RecordingFile schema created
- [ ] Indexes on userId, sessionId for queries
- [ ] Data retention policy set
- [ ] Backup strategy for recording metadata

### Documentation

- [ ] API documentation (included: RECORDING_API.md)
- [ ] Setup guide (included: SETUP_RECORDING.md)
- [ ] Runbook for common issues
- [ ] Disaster recovery procedures

---

## Future Enhancements

### 1. Transcription

```javascript
// After webhook, send to speech-to-text service
async function transcribeRecording(filename) {
  const audioBuffer = await downloadFromStorage(filename);
  const transcript = await googleSpeechToText(audioBuffer);
  await RecordingFile.updateOne({filename}, {transcript});
}
```

### 2. Diarization

Identify which user was speaking using speaker identification:
```javascript
// In webhook, after receiving file
const speakers = await identifySpeakers(filename);
// speakers = [{uid: 123, start: 0, end: 60}, ...]
```

### 3. Real-time Transcription

Use Agora's real-time transcription APIs instead of post-recording:
```javascript
// Not cloud recording, but separate API
// Pros: Real-time results
// Cons: Different API, separate credentials
```

### 4. Quality Metrics

Track recording quality:
```javascript
const metrics = {
  bitrate: 128,  // kbps
  sampleRate: 48000,  // Hz
  channels: 1,  // mono
  duration: 3600,  // seconds
  fileSize: 57600000,  // bytes
};
```

### 5. Automatic Cleanup

Remove old recordings:
```javascript
// Cron job
app.post('/recording/cleanup', async (req, res) => {
  const thirtyDaysAgo = new Date(Date.now() - 30*24*60*60*1000);
  const old = await RecordingFile.find({recordedAt: {$lt: thirtyDaysAgo}});
  
  for (const recording of old) {
    await deleteFromStorage(recording.filename);
    await RecordingFile.deleteOne({_id: recording._id});
  }
});
```

---

## Troubleshooting Guide

### Issue: "Missing Agora Cloud Recording credentials"

**Symptoms:** Error on any recording request

**Root Cause:** Missing AGORA_CUSTOMER_ID or AGORA_CUSTOMER_SECRET

**Solution:**
1. Check `.env` file
2. Verify they're the Cloud Recording credentials (not RTC)
3. Test with: `echo $AGORA_CUSTOMER_ID` (bash) or `echo %AGORA_CUSTOMER_ID%` (cmd)
4. Restart server after changing .env

### Issue: Webhook Not Received

**Symptoms:** Recording starts/stops but no webhook callback

**Root Cause:** Webhook URL not configured in Agora console

**Solution:**
1. Go to Agora console → Cloud Recording
2. Set Webhook URL: `https://your-domain.com/recording/webhook`
3. Whitelist your IP (if required)
4. Test with: `curl -X POST http://localhost:5000/recording/webhook ...`

### Issue: Files Not in Storage

**Symptoms:** Webhook shows files but can't access them

**Root Cause:** Storage not configured properly

**Solution:**
1. Check storageConfig in app.js
2. Verify credentials for AWS S3 / Alibaba OSS
3. Check Agora console logs for storage errors
4. Test storage credentials manually

### Issue: Recording Stops Immediately

**Symptoms:** /recording/start succeeds but recording ends in seconds

**Root Cause:** maxIdleTime too short or channel has no activity

**Solution:**
1. Increase maxIdleTime: `maxIdleTime: 60` (test with 60s)
2. Ensure users are actually in channel
3. Check that users have audio permission
4. Verify recordingMode is 'individual' not 'composite'

---

## Code References

### Core Functions Location
- `app.js` line 46-235: Agora recording service functions
- `app.js` line 237-235: Active recordings management

### Endpoint Handlers Location
- `app.js` line 351-398: POST /recording/start
- `app.js` line 400-437: POST /recording/stop
- `app.js` line 442-526: POST /recording/webhook
- `app.js` line 532-545: GET /recording/active

### Configuration Location
- `.env`: Environment variables
- `app.js` line 130-152: Recording config object
- `app.js` line 144-150: Storage config (placeholder)

---

## References

- **Agora Cloud Recording:** https://docs.agora.io/en/cloud-recording/overview
- **API Reference:** https://docs.agora.io/en/cloud-recording/reference/rest-api
- **Individual Mode:** https://docs.agora.io/en/cloud-recording/concepts/individual-mode
- **Webhook Events:** https://docs.agora.io/en/cloud-recording/reference/cloud-recording-webhook

# Agora Cloud Recording API

This document explains the Cloud Recording APIs implemented in the backend for individual audio recording.

## Overview

The recording system uses Agora's Cloud Recording REST API to record audio from channels in **INDIVIDUAL mode**, meaning each user's audio is recorded separately into individual files.

### Key Concepts

- **Acquire**: Get a resourceId for a recording session (must be called first)
- **Start**: Begin recording with specific configuration (INDIVIDUAL mode, audio-only)
- **Stop**: End the recording and trigger file processing
- **Webhook**: Agora sends a callback when files are ready

### Architecture

```
Client App                Backend                    Agora Cloud Recording
    |                        |                              |
    +-- GET /agora/token --> |                              |
    |                        |                              |
    +-- POST /recording/start                              |
    |                        +-- POST acquire ---------> |
    |                        | <-- resourceId --------+ |
    |                        | +-- POST start ---------> |
    |                        | <-- sid ---------------+ |
    | <-- {resourceId, sid} -+                              |
    |                        |                              |
    | [user joins channel and speaks]                      |
    |                        |                              |
    +-- POST /recording/stop                               |
    |                        +-- POST stop ---------> |
    |                        | <-- success -------+ |
    |                        |                              |
    |                        | <-- POST /recording/webhook (when ready)
    |                        |  {fileList, ...}            |
    | [fetch recordings] --> |                              |
```

---

## API Endpoints

### 1. POST /recording/start

**Starts a recording session** by calling Agora's acquire and start APIs.

#### Request

```json
{
  "channelName": "my-channel-name",
  "uid": 123
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `channelName` | string | ✅ | The channel to record |
| `uid` | number | ✅ | The user ID (for reference only) |

#### Response

**Status: 201 Created**

```json
{
  "resourceId": "EJrteTBXjkE1Z2VsdGhlcnM...",
  "sid": "12f8r2f8yrjh23f23f2f23f2",
  "message": "Recording started successfully"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `resourceId` | string | Used for subsequent stop/update operations |
| `sid` | string | Session ID, identifies this recording |

#### Error Response

**Status: 400/500**

```json
{
  "error": "Missing required fields: channelName, uid"
}
```

#### Example (cURL)

```bash
curl -X POST http://localhost:5000/recording/start \
  -H "Content-Type: application/json" \
  -d '{
    "channelName": "voice-channel-01",
    "uid": 123
  }'
```

#### Configuration

The start recording call automatically applies:

```javascript
{
  recordingMode: 'individual',  // Each user's audio separately
  recordingConfig: {
    maxIdleTime: 30,            // Stop after 30s of silence
    streamTypes: 0,             // 0 = audio-only
    channelType: 0,             // 0 = channel mode
    audioProfile: 1             // 48kHz mono (high quality)
  },
  recordingFileConfig: {
    avFileType: ['hls', 'mp4']  // Generate both formats
  }
}
```

---

### 2. POST /recording/stop

**Stops an active recording session.**

#### Request

```json
{
  "channelName": "my-channel-name",
  "uid": 123,
  "resourceId": "EJrteTBXjkE1Z2VsdGhlcnM...",
  "sid": "12f8r2f8yrjh23f23f2f23f2"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `channelName` | string | ✅ | The channel being recorded |
| `uid` | number | ❌ | User ID (for reference) |
| `resourceId` | string | ✅ | From start response |
| `sid` | string | ✅ | From start response |

#### Response

**Status: 200 OK**

```json
{
  "success": true,
  "message": "Recording stopped successfully"
}
```

#### Error Response

```json
{
  "error": "Missing required fields: channelName, resourceId, sid"
}
```

#### Example (cURL)

```bash
curl -X POST http://localhost:5000/recording/stop \
  -H "Content-Type: application/json" \
  -d '{
    "channelName": "voice-channel-01",
    "uid": 123,
    "resourceId": "EJrteTBXjkE1Z2VsdGhlcnM...",
    "sid": "12f8r2f8yrjh23f23f2f23f2"
  }'
```

---

### 3. POST /recording/webhook

**Receives recording callbacks from Agora** when files are ready.

This endpoint is called by Agora's servers after recording completes and files are processed.

#### Incoming Payload (from Agora)

```json
{
  "resourceId": "EJrteTBXjkE1Z2VsdGhlcnM...",
  "sid": "12f8r2f8yrjh23f23f2f23f2",
  "cname": "voice-channel-01",
  "fileList": [
    {
      "filename": "uid_123_audio.m4a",
      "trackType": "audio",
      "uid": 123,
      "mixedAllUser": false,
      "isPlayable": true,
      "sliceStartTime": 1234567890000
    },
    {
      "filename": "uid_456_audio.m4a",
      "trackType": "audio",
      "uid": 456,
      "mixedAllUser": false,
      "isPlayable": true,
      "sliceStartTime": 1234567890000
    }
  ]
}
```

#### Response

**Status: 200 OK**

```json
{
  "status": "processed",
  "message": "Recording webhook processed successfully"
}
```

#### What the Webhook Processor Does

1. Extracts user ID from filename (e.g., `uid_123_audio.m4a` → `123`)
2. Logs file information for debugging
3. Can be extended to store metadata in MongoDB

#### Example Implementation (MongoDB)

```javascript
// TODO: Implement this in the webhook handler
const recordingMetadata = {
  userId: 123,
  sessionId: 'voice-channel-01',
  filename: 'uid_123_audio.m4a',
  trackType: 'audio',
  fileUrl: 'https://cdn.agora.io/uid_123_audio.m4a',
  resourceId: 'EJrteTBXjkE1Z2VsdGhlcnM...',
  sid: '12f8r2f8yrjh23f23f2f23f2',
  recordedAt: new Date()
};
// await RecordingFile.create(recordingMetadata);
```

---

### 4. GET /recording/active

**Lists all active recordings** (for debugging).

#### Response

```json
{
  "count": 2,
  "recordings": [
    {
      "resourceId": "EJrteTBXjkE1Z2VsdGhlcnM...",
      "sid": "12f8r2f8yrjh23f23f2f23f2",
      "channelName": "voice-channel-01",
      "startedAt": "2024-04-08T15:30:45.123Z"
    }
  ]
}
```

---

## Configuration

### Environment Variables

Set these in `.env`:

```env
# Agora App credentials
AGORA_APP_ID=your_app_id
AGORA_APP_CERTIFICATE=your_app_certificate

# Agora Cloud Recording credentials
AGORA_CUSTOMER_ID=your_customer_id
AGORA_CUSTOMER_SECRET=your_customer_secret

# MongoDB (optional, for storing recording metadata)
MONGODB_URI=mongodb://localhost:27017/agora

# Server
PORT=5000
```

### Recording Configuration

The recording is configured with:

| Setting | Value | Description |
|---------|-------|-------------|
| **Mode** | `individual` | Each user's audio in separate file |
| **Audio Profile** | `1` (48kHz) | High-quality audio |
| **Stream Type** | `0` (audio-only) | No video, just audio |
| **Max Idle Time** | `30s` | Stop if no one speaks for 30s |
| **File Format** | `HLS + MP4` | Both formats for compatibility |

### Storage Configuration

The current implementation includes a placeholder storage config. To use actual cloud storage, update:

```javascript
storageConfig: {
  vendor: 0,           // 0=Agora, 1=AWS S3, 2=Alibaba OSS, 3=Azure
  region: 0,
  bucket: 'your-bucket-name',
  accessKey: 'your-access-key',
  secretKey: 'your-secret-key',
  // For AWS S3:
  // vendor: 1,
  // region: 0, // AWS region code
  // bucket: 'your-s3-bucket'
  // accessKey: 'AWS_ACCESS_KEY_ID'
  // secretKey: 'AWS_SECRET_ACCESS_KEY'
}
```

---

## Flow Diagrams

### Complete Recording Flow

```
1. Start Recording
   ├─ POST /recording/start
   ├─ Backend calls Agora acquire API
   │  └─ Returns resourceId
   ├─ Backend calls Agora start API
   │  └─ Returns sid
   └─ Client receives {resourceId, sid}

2. Recording Active
   ├─ Users join channel and speak
   ├─ Agora records each user's audio separately
   └─ Files stored in cloud storage

3. Stop Recording
   ├─ POST /recording/stop
   ├─ Backend calls Agora stop API
   └─ Agora triggers file processing

4. Webhook Callback
   ├─ Agora POST /recording/webhook
   ├─ Backend receives file list
   └─ Store recording metadata in DB
```

### Error Handling

```
Error Cases:

1. Missing credentials
   └─ Error: "Missing Agora Cloud Recording credentials"

2. API call fails
   └─ Error: "Failed to acquire/start/stop recording"

3. Invalid request
   └─ 400 Bad Request with error details

4. Server error
   └─ 500 Internal Server Error
```

---

## Testing

### Manual Testing with cURL

#### 1. Start Recording

```bash
curl -X POST http://localhost:5000/recording/start \
  -H "Content-Type: application/json" \
  -d '{
    "channelName": "test-channel",
    "uid": 1
  }'
```

Save the `resourceId` and `sid` from response.

#### 2. Check Active Recordings

```bash
curl http://localhost:5000/recording/active
```

#### 3. Stop Recording

```bash
curl -X POST http://localhost:5000/recording/stop \
  -H "Content-Type: application/json" \
  -d '{
    "channelName": "test-channel",
    "uid": 1,
    "resourceId": "YOUR_RESOURCE_ID",
    "sid": "YOUR_SID"
  }'
```

#### 4. Simulate Webhook

```bash
curl -X POST http://localhost:5000/recording/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "resourceId": "YOUR_RESOURCE_ID",
    "sid": "YOUR_SID",
    "cname": "test-channel",
    "fileList": [
      {
        "filename": "uid_1_audio.m4a",
        "trackType": "audio",
        "uid": 1,
        "isPlayable": true
      }
    ]
  }'
```

---

## Production Checklist

- [ ] Set all environment variables in `.env`
- [ ] Whitelist webhook IP in Agora console
- [ ] Configure storage (AWS S3, Alibaba OSS, etc.)
- [ ] Implement MongoDB schema for recording metadata
- [ ] Add authentication to API endpoints
- [ ] Add request validation and sanitization
- [ ] Implement rate limiting
- [ ] Add monitoring/alerting
- [ ] Test webhook delivery and retry logic
- [ ] Document API for frontend team

---

## Support

For Agora Cloud Recording documentation:
- https://docs.agora.io/en/cloud-recording/overview
- https://docs.agora.io/en/cloud-recording/reference/rest-api

For this implementation, check the comments in `app.js`.

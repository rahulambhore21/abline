# Agora Cloud Recording Setup Guide

This guide helps you set up Agora Cloud Recording for individual audio recording.

## Quick Start

### 1. Install Dependencies

```bash
npm install
npm install axios
```

### 2. Configure Environment Variables

Update `.env`:

```env
# Agora RTC Credentials (for token generation)
AGORA_APP_ID=your_app_id
AGORA_APP_CERTIFICATE=your_app_certificate

# Agora Cloud Recording Credentials (from https://console.agora.io)
AGORA_CUSTOMER_ID=your_customer_id
AGORA_CUSTOMER_SECRET=your_customer_secret

# Server
PORT=5000

# MongoDB (optional)
# MONGODB_URI=mongodb://localhost:27017/agora
```

### 3. Get Agora Credentials

1. Go to https://console.agora.io
2. Create/select your project
3. For **AGORA_APP_ID** and **AGORA_APP_CERTIFICATE**:
   - Copy from the dashboard
4. For **AGORA_CUSTOMER_ID** and **AGORA_CUSTOMER_SECRET**:
   - Go to RESTful API tab
   - Enable Cloud Recording API
   - Copy credentials

### 4. Start the Server

```bash
npm start
# or with auto-reload
npm run dev
```

You should see:
```
✅ Agora RTC Token Server running on http://localhost:5000
📍 Recording endpoints:
   - POST /recording/start (start INDIVIDUAL mode recording)
   - POST /recording/stop (stop recording)
   - POST /recording/webhook (Agora callback)
   - GET /recording/active (list active recordings)
```

---

## Testing Recording APIs

### Test Start Recording

```bash
curl -X POST http://localhost:5000/recording/start \
  -H "Content-Type: application/json" \
  -d '{
    "channelName": "test-channel",
    "uid": 1
  }'
```

**Expected Response:**
```json
{
  "resourceId": "EJrteTBXjkE1Z2VsdGhlcnM...",
  "sid": "12f8r2f8yrjh23f23f2f23f2",
  "message": "Recording started successfully"
}
```

### Test Stop Recording

```bash
curl -X POST http://localhost:5000/recording/stop \
  -H "Content-Type: application/json" \
  -d '{
    "channelName": "test-channel",
    "uid": 1,
    "resourceId": "EJrteTBXjkE1Z2VsdGhlcnM...",
    "sid": "12f8r2f8yrjh23f23f2f23f2"
  }'
```

### Test Webhook

```bash
curl -X POST http://localhost:5000/recording/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "resourceId": "EJrteTBXjkE1Z2VsdGhlcnM...",
    "sid": "12f8r2f8yrjh23f23f2f23f2",
    "cname": "test-channel",
    "fileList": [
      {
        "filename": "uid_1_audio.m4a",
        "trackType": "audio",
        "uid": 1
      }
    ]
  }'
```

---

## Recording Configuration

The recording automatically uses:

```javascript
{
  recordingMode: 'individual',  // ✅ Each user's audio separately
  recordingConfig: {
    maxIdleTime: 30,            // Stop after 30s of silence
    streamTypes: 0,             // 0 = audio-only (no video)
    channelType: 0,             // Channel mode
    audioProfile: 1             // 48kHz mono (high quality)
  },
  recordingFileConfig: {
    avFileType: ['hls', 'mp4']  // Generate both formats
  }
}
```

### Important Notes

- **INDIVIDUAL mode** = Each user's audio in a separate file ✅
- NOT "composite" mode = Don't mix all users into one file
- **Audio-only** = streamTypes: 0 (no video)
- High-quality audio = audioProfile: 1

---

## Webhook Configuration

For production, you need to configure Agora to send webhooks to your backend.

### In Agora Console

1. Go to Console → Project → RESTful API
2. Cloud Recording → Webhook URL
3. Set: `https://your-domain.com/recording/webhook`
4. Configure HTTP authentication if needed

### Webhook Flow

```
User speaks in channel
         ↓
Agora records audio
         ↓
Recording ends (or timeout)
         ↓
Files processed and uploaded
         ↓
Agora POST /recording/webhook
         ↓
Backend stores file metadata
```

### Webhook Security

Add authentication in production:

```javascript
// In /recording/webhook endpoint
const webhookSecret = process.env.AGORA_WEBHOOK_SECRET;
const signature = req.headers['x-agora-signature'];

if (!verifySignature(req.body, signature, webhookSecret)) {
  return res.status(401).json({ error: 'Unauthorized' });
}
```

---

## Integration with Flutter App

### From Your Flutter App

1. **Get Recording Session IDs**

```dart
// Call backend to start recording
final response = await http.post(
  Uri.parse('http://your-backend.com/recording/start'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({
    'channelName': channelName,
    'uid': uid,
  }),
);

final data = jsonDecode(response.body);
String resourceId = data['resourceId'];
String sid = data['sid'];

// Store these for later
```

2. **Notify When Call Ends**

```dart
// When user leaves channel or call ends
await http.post(
  Uri.parse('http://your-backend.com/recording/stop'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({
    'channelName': channelName,
    'uid': uid,
    'resourceId': resourceId,
    'sid': sid,
  }),
);
```

3. **Retrieve Recordings**

```dart
// After webhook callback, fetch from your DB
// GET /api/recordings?userId=123&sessionId=session-id
```

---

## Troubleshooting

### "Missing Agora Cloud Recording credentials"

**Cause:** AGORA_CUSTOMER_ID or AGORA_CUSTOMER_SECRET not set

**Fix:**
1. Check `.env` file has these values
2. Make sure they're for Cloud Recording, not RTC token generation
3. Restart the server

### "Failed to acquire recording"

**Cause:** Invalid credentials or Agora API issue

**Fix:**
1. Verify credentials in Agora console
2. Check if Cloud Recording is enabled for your project
3. Check Agora status page (https://status.agora.io)

### Webhook Not Received

**Cause:** Webhook URL not configured or network issue

**Fix:**
1. Configure webhook URL in Agora console
2. Make sure backend is publicly accessible
3. Check firewall/NAT settings
4. Use ngrok for local testing: `ngrok http 5000`

### "Recording started but no files"

**Cause:** Storage not configured properly

**Fix:**
1. Configure storageConfig with valid credentials
2. Test cloud storage access (AWS S3, Alibaba OSS, etc.)
3. Check Agora console logs for storage errors

---

## Next Steps

1. ✅ Set environment variables
2. ✅ Start backend server
3. ✅ Test with cURL
4. ⬜ Configure storage (AWS S3, etc.)
5. ⬜ Set webhook URL in Agora console
6. ⬜ Create MongoDB schema for recording metadata
7. ⬜ Integrate with Flutter app
8. ⬜ Deploy to production

---

## Code Structure

```
backend/
├── app.js                 # Main server with recording endpoints
├── .env                   # Configuration (credentials)
├── RECORDING_API.md       # API documentation
├── SETUP_RECORDING.md     # This file
└── package.json
```

### Recording Functions in app.js

- `createRecordingAuthHeader()` - Create auth for Agora API
- `validateRecordingCredentials()` - Check credentials set
- `acquireRecording()` - Step 1: Get resourceId
- `startRecording()` - Step 2: Start INDIVIDUAL recording
- `stopRecording()` - Step 3: Stop recording
- `getActiveRecording()` - Query active recordings
- `getAllActiveRecordings()` - List all active recordings

### Endpoints

- `POST /recording/start` - Initiate recording
- `POST /recording/stop` - End recording
- `POST /recording/webhook` - Receive callbacks
- `GET /recording/active` - Debug endpoint

---

## Additional Resources

- **Agora Cloud Recording Docs:** https://docs.agora.io/en/cloud-recording/overview
- **REST API Reference:** https://docs.agora.io/en/cloud-recording/reference/rest-api
- **Individual Recording Mode:** https://docs.agora.io/en/cloud-recording/concepts/individual-mode
- **Webhook Docs:** https://docs.agora.io/en/cloud-recording/reference/cloud-recording-webhook

---

## Support

For issues or questions:
1. Check the RECORDING_API.md documentation
2. Review app.js comments
3. Consult Agora documentation links above
4. Check server logs for error details

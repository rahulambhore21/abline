# Agora RTC Token Server with Cloud Recording

An Express.js backend that provides:
1. **RTC Token Generation** - for Agora voice/video calls
2. **Speaking Events Tracking** - logs when users speak
3. **Cloud Recording** - records user audio in INDIVIDUAL mode (separate files per user)

## Features

- ✅ Secure token generation using Agora Access Token SDK
- ✅ Environment variable configuration via dotenv
- ✅ 1-hour token expiry
- ✅ Input validation and error handling
- ✅ CORS support
- ✅ Health check endpoint
- ✅ **Cloud Recording in INDIVIDUAL mode** - each user's audio recorded separately
- ✅ **Webhook support** - receive callbacks when recordings are complete
- ✅ Speaking events tracking and storage

## Prerequisites

- Node.js 14+
- npm or yarn
- Agora App ID and App Certificate from [Agora Console](https://console.agora.io)
- Agora Customer ID and Customer Secret (for Cloud Recording) from [Agora Console](https://console.agora.io)

## Installation

1. Install dependencies:
```bash
npm install
npm install axios
```

2. Copy `.env.example` to `.env` and add your Agora credentials:
```bash
cp .env.example .env
```

3. Edit `.env` with your credentials:
```
# Agora RTC Token Generation Credentials
AGORA_APP_ID=your_app_id_here
AGORA_APP_CERTIFICATE=your_app_certificate_here

# Agora Cloud Recording Credentials (from RESTful API tab)
AGORA_CUSTOMER_ID=your_customer_id
AGORA_CUSTOMER_SECRET=your_customer_secret

PORT=5000

# Optional (persist speaking events to MongoDB)
# MONGODB_URI=mongodb://127.0.0.1:27017/agora
```

## Usage

### Start the server

**Development mode (with auto-reload):**
```bash
npm run dev
```

**Production mode:**
```bash
npm start
```

The server will start on `http://localhost:5000`

### API Endpoints

#### Health Check
```
GET /health
```

Response:
```json
{
  "status": "ok",
  "message": "Server is running"
}
```

#### Generate Agora RTC Token
```
GET /agora/token?channelName=<channel>&uid=<user_id>
```

**Query Parameters:**
- `channelName` (required): The name of the channel to join
- `uid` (required): Numeric user ID (non-negative integer)

**Example Request:**
```bash
curl "http://localhost:5000/agora/token?channelName=my-channel&uid=123"
```

**Success Response (200):**
```json
{
  "token": "00...",
  "appId": "your_app_id",
  "channelName": "my-channel",
  "uid": 123
}
```

**Error Response (400):**
```json
{
  "error": "Missing required parameter: channelName"
}
```

**Error Response (500):**
```json
{
  "error": "Server misconfiguration: Missing Agora credentials"
}
```

#### Speaking Events

Store a completed speaking segment (sent when a user stops speaking):
```
POST /events/speaking
```

Body:
```json
{
  "userId": 123,
  "sessionId": 456,
  "start": "2026-01-01T10:00:00.000Z",
  "end": "2026-01-01T10:00:02.500Z"
}
```

List events:
```
GET /events/speaking?userId=123&sessionId=456
```

If `MONGODB_URI` is set and MongoDB is reachable, events are persisted to MongoDB; otherwise the server falls back to in-memory storage.

#### Cloud Recording

**Start Recording:**
```
POST /recording/start
```

Body:
```json
{
  "channelName": "my-channel",
  "uid": 123
}
```

Response:
```json
{
  "resourceId": "EJrteTBXjkE1Z2VsdGhlcnM...",
  "sid": "12f8r2f8yrjh23f23f2f23f2",
  "message": "Recording started successfully"
}
```

**Stop Recording:**
```
POST /recording/stop
```

Body:
```json
{
  "channelName": "my-channel",
  "uid": 123,
  "resourceId": "EJrteTBXjkE1Z2VsdGhlcnM...",
  "sid": "12f8r2f8yrjh23f23f2f23f2"
}
```

**Webhook Callback:**
```
POST /recording/webhook
```
Agora sends this when recording is complete and files are ready.

**List Active Recordings:**
```
GET /recording/active
```

For detailed API documentation, see [RECORDING_API.md](./RECORDING_API.md)

## Flutter Integration Example

### RTC Token
```dart
Future<String> getAgoraToken(String channelName, int uid) async {
  final response = await http.get(
    Uri.parse('http://your-server:5000/agora/token')
        .replace(queryParameters: {
      'channelName': channelName,
      'uid': uid.toString(),
    }),
  );

  if (response.statusCode == 200) {
    final json = jsonDecode(response.body);
    return json['token'];
  } else {
    throw Exception('Failed to get token');
  }
}
```

### Cloud Recording
```dart
// Start recording when user joins channel
Future<Map<String, dynamic>> startRecording(String channelName, int uid) async {
  final response = await http.post(
    Uri.parse('http://your-server:5000/recording/start'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'channelName': channelName,
      'uid': uid,
    }),
  );

  if (response.statusCode == 201) {
    return jsonDecode(response.body);
  } else {
    throw Exception('Failed to start recording');
  }
}

// Stop recording when user leaves channel
Future<void> stopRecording(String channelName, int uid, String resourceId, String sid) async {
  await http.post(
    Uri.parse('http://your-server:5000/recording/stop'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'channelName': channelName,
      'uid': uid,
      'resourceId': resourceId,
      'sid': sid,
    }),
  );
}
```

For complete Flutter integration, see [FLUTTER_INTEGRATION.md](./FLUTTER_INTEGRATION.md)

## Security Notes

- **Never commit `.env` file** - It's in `.gitignore`
- **Use `.env.example`** as a template and commit it instead
- **Keep your App Certificate secret** - Don't expose it in frontend code
- **Token expiry** is set to 1 hour (3600 seconds)
- **Role is set to PUBLISHER** for all tokens

## Project Structure

```
backend/
├── app.js                      # Main Express application (with recording)
├── package.json                # Dependencies
├── .env                        # Environment variables (not committed)
├── .env.example                # Example environment variables
├── .gitignore                  # Git ignore rules
├── README.md                   # This file
├── RECORDING_API.md            # Cloud Recording API documentation
├── SETUP_RECORDING.md          # Cloud Recording setup guide
├── FLUTTER_INTEGRATION.md      # Flutter integration examples
└── IMPLEMENTATION_NOTES.md     # Technical implementation details
```

## Error Handling

The server handles various error cases:

- **400 Bad Request**: Missing or invalid query parameters
- **500 Internal Server Error**: Server misconfiguration or token generation failure
- **404 Not Found**: Invalid endpoint

All responses are in JSON format with an error message.

## Development

The project uses:
- **Express.js** - Web framework
- **dotenv** - Environment variable management
- **agora-access-token** - Agora token generation
- **axios** - HTTP requests (Cloud Recording API)
- **cors** - CORS middleware
- **mongoose** - MongoDB driver (optional)
- **nodemon** - Development auto-reload (dev dependency)

## License

ISC

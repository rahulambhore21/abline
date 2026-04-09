# Dashboard Quick Start

## What Was Built

A complete Host Dashboard screen for viewing and managing voice communication sessions with:
- **Real-time user list** with speaking status indicators
- **Speaking timeline visualization** showing when each user spoke
- **Audio recording playback** with controls (play/pause/stop)
- **Recording management** (start/stop session recording)

## Files Created/Modified

### Backend (Express.js)
- ✅ Added `/session/:id/users` endpoints (register and fetch)
- ✅ Added `/recordings` endpoints (fetch and add recordings)
- ✅ Updated startup logs with new endpoints

### Flutter
- ✅ `dashboard_screen.dart` - Main dashboard component
- ✅ `user_list_widget.dart` - Users display
- ✅ `timeline_widget.dart` - Speaking timeline visualization
- ✅ `recording_list_widget.dart` - Audio playback
- ✅ `user.dart` - User data model
- ✅ `recording.dart` - Recording data model
- ✅ Updated `speaking_event.dart` - Enhanced model
- ✅ Updated `main.dart` - Added navigation
- ✅ Updated `pubspec.yaml` - Added `just_audio` package

## How to Run

### 1. Install Dependencies
```bash
cd app
flutter pub get
```

### 2. Run the App
```bash
flutter run
```

### 3. Access Dashboard
- Tap "View Dashboard" on the home screen
- Or navigate programmatically:
```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => DashboardScreen(
      sessionId: 'test_room',
      backendUrl: 'https://your-backend-url',
      currentUserId: 1,
      currentUsername: 'HostName',
    ),
  ),
);
```

## API Integration Points

### Fetch Users
```
GET /session/{sessionId}/users
Response: { sessionId, users: [...], total: number }
```

### Fetch Speaking Events
```
GET /events/speaking?sessionId={sessionId}
Response: { total, events: [...], source: 'mongodb'|'memory' }
```

### Fetch Recordings
```
GET /recordings?sessionId={sessionId}
Response: { total, recordings: [...] }
```

### Control Recording
```
POST /recording/start
Body: { channelName, uid }

POST /recording/stop
Body: { channelName, uid }
```

## Testing with Mock Data

### Add Test Users
```bash
curl -X POST http://localhost:5000/session/test_room/users/add \
  -H "Content-Type: application/json" \
  -d '{"userId": 1, "username": "Alice"}'

curl -X POST http://localhost:5000/session/test_room/users/add \
  -H "Content-Type: application/json" \
  -d '{"userId": 2, "username": "Bob"}'
```

### Add Test Speaking Events
```bash
curl -X POST http://localhost:5000/events/speaking \
  -H "Content-Type: application/json" \
  -d '{
    "userId": 1,
    "sessionId": "test_room",
    "start": "2024-01-15T10:00:00Z",
    "end": "2024-01-15T10:00:30Z"
  }'
```

### Add Test Recording
```bash
curl -X POST http://localhost:5000/recordings/add \
  -H "Content-Type: application/json" \
  -d '{
    "userId": 1,
    "sessionId": "test_room",
    "filename": "alice_rec.m4a",
    "url": "https://example.com/recordings/alice.m4a"
  }'
```

## Key Features

### User List
- Green dot = currently speaking
- Grey dot = silent
- Shows user ID and name

### Timeline
- Horizontal scrollable view
- Each user gets a row
- Speaking events shown as blue bars
- Duration labeled on each bar
- Hover for exact timing

### Playback
- Click play button to start audio
- Only one audio plays at a time
- Progress bar shows current position
- Play/Pause/Stop controls
- Auto-resets when finished

### Recording Control
- "Start Recording" button to begin session recording
- "Stop Recording" button to end recording
- Recording status indicator when active

## State Management

Dashboard uses StatefulWidget with 2-second polling:
- Fetches users every 2 seconds
- Fetches speaking events every 2 seconds
- Fetches recordings every 2 seconds
- Automatically stops polling when screen closes

## Error Handling

- All API errors show in a red error container
- Network timeouts handled gracefully
- Invalid audio URLs show SnackBar notification
- Mounted checks prevent memory leaks

## Customization

### Change Polling Interval
In `dashboard_screen.dart`, update `_startDataPolling()`:
```dart
Future.delayed(const Duration(seconds: 5), () {  // Change from 2 to 5
```

### Modify Timeline Width
In `timeline_widget.dart`, update the `SizedBox` width:
```dart
SizedBox(
  width: 1500,  // Change from 1200
  child: ...
```

### Adjust Colors
Each widget uses Material colors (Colors.blue, Colors.green, etc.)
Search for `Colors.` in each widget file to customize

## Troubleshooting

**Q: Dashboard shows "No users in session"**
- A: Call `POST /session/{sessionId}/users/add` first

**Q: Timeline doesn't show any events**
- A: Add speaking events via `POST /events/speaking`
- Check that timestamps are in ISO8601 format

**Q: Audio won't play**
- A: Verify the recording URL is accessible from the device
- Check network connectivity
- Try a public audio URL for testing

**Q: Data not updating**
- A: Polling should refresh every 2 seconds
- Check browser console for errors
- Verify backend is returning data

## Architecture Overview

```
DashboardScreen (main container)
├── UserListWidget
│   └── displays User list with status
├── TimelineWidget
│   ├── calculates timeline scale
│   ├── maps events to pixel positions
│   └── renders event bars
└── RecordingListWidget
    ├── AudioPlayer instance
    ├── plays/pauses/stops audio
    └── shows progress tracking
```

## Next Steps

1. **Production Backend**: Replace mock recording URLs with real Agora Cloud Recording URLs
2. **Real-time Updates**: Upgrade from polling to WebSocket/SSE for instant updates
3. **Authentication**: Add user session verification
4. **Persistence**: Store dashboard settings in local storage
5. **Export**: Add download timeline as JSON/CSV
6. **Analytics**: Track speaker statistics (total time, frequency)

## Support

See `DASHBOARD_IMPLEMENTATION.md` for detailed technical documentation.

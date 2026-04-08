# Speaker Detection - Quick Reference

## Files Modified/Created

✅ **NEW FILES**:
- `app/lib/speaker_tracker.dart` - Core speaker detection logic
- `app/lib/speaking_event.dart` - Data models
- `SPEAKER_DETECTION_IMPLEMENTATION.md` - Full documentation

✅ **MODIFIED FILES**:
- `app/lib/voice_call_screen.dart` - Integrated SpeakerTracker + UI
- `backend/app.js` - Added /events/speaking endpoints

## How to Use

### 1. Start the Backend
```bash
cd backend
npm install  # if not done
node app.js
```

### 2. Run Flutter App
```bash
cd app
flutter pub get
flutter run
```

### 3. Test Speaker Detection
1. Join channel
2. Start speaking
3. Watch for green indicator on your user card
4. Stop speaking
5. Check console for "📊 Event: SpeakingEvent(...)"
6. Check backend for received event

## Architecture Overview

```
Agora SDK (200ms intervals)
    ↓
onAudioVolumeIndication
    ↓
SpeakerTracker.processAudioVolume()
    ↓
Apply 300ms Debounce
    ↓
Detect State Transition
    ↓
Create SpeakingEvent
    ↓
POST to Backend
    ↓
Backend Stores Event
```

## Key Settings

| Setting | Value | Purpose |
|---------|-------|---------|
| Volume Threshold | 50 | Determines if user is "speaking" |
| Debounce Duration | 300ms | Prevents noise-triggered events |
| Report Interval | 200ms | How often Agora sends volume data |
| Report VAD | true | Enable voice activity detection |

## API Endpoints

### POST /events/speaking
```bash
curl -X POST https://your-backend/events/speaking \
  -H "Content-Type: application/json" \
  -d '{
    "userId": 12345,
    "sessionId": 987654,
    "start": "2026-04-08T20:43:50.471Z",
    "end": "2026-04-08T20:43:55.123Z"
  }'
```

### GET /events/speaking
```bash
# Get all events
curl https://your-backend/events/speaking

# Filter by user
curl "https://your-backend/events/speaking?userId=12345"

# Filter by session
curl "https://your-backend/events/speaking?sessionId=987654"
```

## Core Classes

### SpeakerTracker
Main service class handling all speaker detection logic.

**Constructor**:
```dart
SpeakerTracker(
  backendUrl: 'https://your-backend',
  sessionId: hashCode,
  onSpeakingEventComplete: (event) { /* handle */ }
)
```

**Key Methods**:
```dart
processAudioVolume(uid, volume)        // Called on each volume report
isUserSpeaking(uid) -> bool            // Check if user is speaking
getUserState(uid) -> UserSpeakingState // Get detailed user state
getAllUserStates() -> Map               // Get all users
removeUser(uid)                        // Remove user from tracking
reset()                                // Reset all tracking
dispose()                              // Cleanup resources
```

**Reactive Updates**:
```dart
// UI automatically updates when speaking state changes
ValueListenable<Map<int, UserSpeakingState>> speakingStatesNotifier
```

### UserSpeakingState
Current state of a user.

```dart
{
  uid: int,                    // User ID
  isSpeaking: bool,           // Currently speaking?
  lastStartTime: DateTime?,   // When started current speaking turn
  lastEndTime: DateTime?,     // When ended previous speaking turn
}
```

### SpeakingEvent
Completed speaking event.

```dart
{
  userId: int,       // Who was speaking
  sessionId: int,    // Which session/channel
  startTime: DateTime // When they started
  endTime: DateTime   // When they stopped
}
```

**To JSON** (for backend):
```json
{
  "userId": 12345,
  "sessionId": 987654,
  "start": "2026-04-08T20:43:50.471Z",
  "end": "2026-04-08T20:43:55.123Z"
}
```

## UI Components

### User Indicator with Speaking Status
```dart
// Shows green indicator when user is speaking
// Updates in real-time via ValueListenable
_buildUserIndicator(uid, label, isLocal)
```

Features:
- ✅ Green circle = speaking
- ✅ Gray circle = silent
- ✅ "🎤 Speaking..." label when active
- ✅ Real-time reactive updates

### Speaking Events History
```dart
// Scrollable list of recent speaking events
// Shows: User ID + duration (in seconds)
if (_speakingEvents.isNotEmpty)
  // Display events
```

## Detection Logic Explained

### Volume Threshold Decision
```
if (volume > 50) {
  isSpeakingNow = true   // Speaking
} else {
  isSpeakingNow = false  // Silent
}
```

### Debounce Pattern
```
User speaks:
  t=0ms    - Volume jumps to 70
           - Start 300ms debounce timer
  t=300ms  - Timer expires, confirmed > 300ms stable
           - Record startTime, set isSpeaking=true
           
User stops:
  t=500ms  - Volume drops to 30
           - Cancel old timer, start new 300ms timer
  t=800ms  - Timer expires, confirmed > 300ms silent
           - Record endTime, create event
           - Send to backend
```

### State Transitions
```
Silent (isSpeaking=false)
  ↓ [volume > 50 for 300ms]
Speaking (isSpeaking=true, lastStartTime=now)
  ↓ [volume ≤ 50 for 300ms]
Event Created → Backend POST
Silent (isSpeaking=false, lastEndTime=now)
```

## Debugging

### Check if SpeakerTracker is working
```dart
// Print current states
final states = _speakerTracker.getAllUserStates();
states.forEach((uid, state) {
  print('User $uid: ${state.isSpeaking ? "Speaking" : "Silent"}');
});
```

### Check backend received events
```bash
# SSH into backend server
curl http://localhost:5000/events/speaking

# Should return:
# {
#   "total": 3,
#   "events": [...]
# }
```

### Enable Debug Logging
Look for these console messages:
```
🎤 User 12345 started speaking at 2026-04-08T20:43:50.471Z
🛑 User 12345 stopped speaking at 2026-04-08T20:43:55.123Z
📊 Event: SpeakingEvent(userId: 12345, ...)
✅ Event sent successfully: 12345
```

## Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| No speaking detected | Increase volume threshold or check mic permission |
| Too many false events | Increase debounce to 500ms or raise threshold to 60 |
| Backend not receiving | Check network, CORS, and backend URL in code |
| Events sent but not stored | Backend endpoint returning error (check logs) |
| App crashes on volume event | Ensure SpeakerTracker initialized before Agora events |

## Next Steps for Production

1. **Database**: Replace in-memory `speakingEvents` array with MongoDB/PostgreSQL
2. **Authentication**: Add API key validation to `/events/speaking`
3. **Retry Logic**: Add exponential backoff for failed backend requests
4. **Analytics**: Create dashboard to visualize speaking patterns
5. **Notifications**: Alert when specific users start/stop speaking
6. **Recording**: Integrate with audio recording to save speaking segments
7. **Transcription**: Add speech-to-text for meeting notes
8. **Testing**: Run load tests with 50+ concurrent users

## API Response Examples

### Successful Event Recording
```json
HTTP 201
{
  "success": true,
  "eventId": "evt_1712698830471_abc123def",
  "message": "Speaking event recorded for user 12345",
  "event": {
    "userId": 12345,
    "sessionId": 987654,
    "duration": 5
  }
}
```

### Get All Events
```json
HTTP 200
{
  "total": 2,
  "events": [
    {
      "id": "evt_1712698830471_abc123",
      "userId": 12345,
      "sessionId": 987654,
      "start": "2026-04-08T20:43:50.471Z",
      "end": "2026-04-08T20:43:55.123Z",
      "duration": 5,
      "recordedAt": "2026-04-08T20:43:55.200Z"
    },
    {
      "id": "evt_1712698835200_def456",
      "userId": 67890,
      "sessionId": 987654,
      "start": "2026-04-08T20:44:00.000Z",
      "end": "2026-04-08T20:44:08.500Z",
      "duration": 8,
      "recordedAt": "2026-04-08T20:44:08.600Z"
    }
  ]
}
```

## Code Snippets for Common Tasks

### Listen to speaking state changes
```dart
_speakerTracker.speakingStatesNotifier.addListener(() {
  final states = _speakerTracker.getAllUserStates();
  // React to changes
});
```

### Check if specific user is speaking
```dart
bool isUserSpeaking = _speakerTracker.isUserSpeaking(12345);
```

### Get detailed state for user
```dart
UserSpeakingState? state = _speakerTracker.getUserState(12345);
if (state != null) {
  print('Speaking: ${state.isSpeaking}');
  print('Started: ${state.lastStartTime}');
}
```

### Remove user from tracking
```dart
_speakerTracker.removeUser(12345);
```

### Full reset on channel leave
```dart
_speakerTracker.reset();
```

## Performance Tips

- ✅ Debouncing prevents excessive state changes
- ✅ Backend events sent only on completion (not per volume report)
- ✅ ValueNotifier updates only UI listeners (not entire app)
- ✅ Timers are properly cleaned up to prevent memory leaks
- ✅ Single HTTP request per speaking turn (optimized network usage)

---

**Status**: ✅ Complete Implementation Ready
**Last Updated**: 2026-04-08
**Version**: 1.0.0

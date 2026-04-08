# Speaker Detection System - Implementation Guide

## Overview

This implementation provides real-time speaker detection for your Flutter Agora RTC app. It tracks which users are speaking, records start/end times, and sends events to the backend for analytics.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Voice Call Screen (UI)                     │
├─────────────────────────────────────────────────────────────┤
│  • Displays user list with speaking indicators               │
│  • Shows speaking events history                             │
│  • Manages channel connection                                │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              Agora RTC Engine Events                         │
├─────────────────────────────────────────────────────────────┤
│  onAudioVolumeIndication (every 200ms)                      │
│  └─► Volume data with VAD (Voice Activity Detection)        │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│            SpeakerTracker Service (Core Logic)              │
├─────────────────────────────────────────────────────────────┤
│  • Monitors volume per user                                  │
│  • Applies 300ms debounce filter                            │
│  • Detects speaking transitions                             │
│  • Tracks start/end times                                   │
│  • Sends events via HTTP to backend                         │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              Backend API (/events/speaking)                 │
├─────────────────────────────────────────────────────────────┤
│  • Receives speaking events                                  │
│  • Stores in in-memory list (ready for DB)                  │
│  • Provides GET endpoint for analytics                      │
└─────────────────────────────────────────────────────────────┘
```

## File Structure

```
app/lib/
├── main.dart                    # App entry point (unchanged)
├── voice_call_screen.dart       # ✅ Updated: UI + SpeakerTracker integration
├── speaker_tracker.dart         # ✅ NEW: Core speaker detection logic
└── speaking_event.dart          # ✅ NEW: Data models

backend/
└── app.js                       # ✅ Updated: Added /events/speaking endpoints
```

## Key Components

### 1. SpeakerTracker (`speaker_tracker.dart`)

**Purpose**: Core logic for detecting and tracking speakers

**Key Features**:
- **Volume Monitoring**: Processes audio volume from Agora's `onAudioVolumeIndication` callback
- **Debouncing**: 300ms delay to ignore rapid noise fluctuations (prevents false positives)
- **State Management**: Tracks speaking/silent state per user with timestamps
- **Transitions**: Detects silent→speaking and speaking→silent transitions
- **Event Generation**: Creates `SpeakingEvent` objects when speaking ends
- **Backend Integration**: Sends events via HTTP POST

**Configuration Constants**:
```dart
static const int volumeThreshold = 50;        // Volume > 50 = speaking
static const int debounceMs = 300;            // Ignore rapid changes
static const int volumeCheckInterval = 200;   // Agora reporting interval
```

**Main Methods**:
- `processAudioVolume(uid, volume)` - Called on each volume report from Agora
- `_handleStateTransition(uid, isSpeakingNow)` - Internal: processes state changes after debounce
- `_sendEventToBackend(event)` - POST to backend when speaking ends
- `removeUser(uid)` - Clean up when user leaves
- `reset()` - Full reset on channel leave
- `dispose()` - Resource cleanup

### 2. SpeakingEvent Model (`speaking_event.dart`)

**UserSpeakingState**: Tracks current state
```dart
{
  uid: int,
  isSpeaking: bool,
  lastStartTime: DateTime?,
  lastEndTime: DateTime?,
}
```

**SpeakingEvent**: Completed event (sent to backend)
```dart
{
  userId: int,
  sessionId: int,
  startTime: DateTime,
  endTime: DateTime,
}
```

Converts to JSON:
```json
{
  "userId": 12345,
  "sessionId": 987654,
  "start": "2026-04-08T20:43:50.471Z",
  "end": "2026-04-08T20:43:55.123Z"
}
```

### 3. Updated VoiceCallScreen (`voice_call_screen.dart`)

**Audio Volume Indication Setup**:
```dart
await _agoraEngine.enableAudioVolumeIndication(
  interval: 200,        // Report every 200ms
  smooth: 3,            // Smooth factor
  reportVad: true,      // Enable VAD
);
```

**Event Handler Integration**:
```dart
onAudioVolumeIndication: (connection, speakers) {
  for (final speaker in speakers) {
    if (speaker.vad == 1 || speaker.volume > 0) {
      _speakerTracker.processAudioVolume(
        uid: speaker.uid,
        volume: speaker.volume,
      );
    }
  }
}
```

**UI Components**:
- User list with speaking indicators (green = speaking, gray = silent)
- Real-time speaking status with 🎤 indicator
- Speaking events history showing durations
- Clean lifecycle management (initialize on `initState`, dispose properly)

### 4. Backend Endpoints (`backend/app.js`)

**POST /events/speaking** - Record speaking event
```
Request:
{
  "userId": 12345,
  "sessionId": 987654,
  "start": "2026-04-08T20:43:50.471Z",
  "end": "2026-04-08T20:43:55.123Z"
}

Response (201):
{
  "success": true,
  "eventId": "evt_1712698830471_abc123",
  "message": "Speaking event recorded for user 12345",
  "event": {
    "userId": 12345,
    "sessionId": 987654,
    "duration": 5  // seconds
  }
}
```

**GET /events/speaking** - Retrieve events (with optional filters)
```
Query params:
  ?userId=12345
  ?sessionId=987654
  ?userId=12345&sessionId=987654

Response:
{
  "total": 3,
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
    ...
  ]
}
```

## How It Works

### Detection Flow

1. **Agora Sends Volume Data** (every 200ms)
   - Includes uid, volume (0-100), and VAD (voice activity flag)

2. **SpeakerTracker.processAudioVolume()**
   - Initializes user state if new
   - Cancels existing debounce timer
   - **Starts debounce timer** (300ms delay)

3. **After Debounce Expires** (_handleStateTransition)
   - Compares old speaking state with new (volume-based)
   - **If silent → speaking**:
     - Set `isSpeaking = true`
     - Record `lastStartTime = now()`
     - Log: "🎤 User started speaking"
   - **If speaking → silent**:
     - Set `isSpeaking = false`
     - Record `lastEndTime = now()`
     - Create `SpeakingEvent` object
     - Call callback (UI updates)
     - **POST to backend**

4. **UI Updates**
   - `ValueListenable` notifies all listeners
   - User indicator changes color to green
   - Speaking indicator shows "🎤 Speaking..."
   - Event added to history list

5. **Backend Processing**
   - Receives POST at `/events/speaking`
   - Validates data
   - Stores event (in-memory, ready for DB)
   - Returns success response

### Debouncing Example

```
Volume Over Time:
60 ──────        ▲ Speaking
50 ──────        │
40 ──────    ┌───┴───────────┐
30 ──────────┘               └────  ← Real user voice (clear intent)
20 ──

Without debounce:
- Would trigger multiple start/stop events at edges
- Noise creates false "speaking" moments

With 300ms debounce:
- Ignores rapid fluctuations
- Only triggers when signal stabilizes
- One start event, one stop event per speaking turn
```

### User State Machine

```
┌──────────────┐
│    Silent    │
│ isSpeaking=F │
└──────┬───────┘
       │ volume > 50 (after 300ms debounce)
       ▼
┌──────────────────────────┐
│    Speaking              │
│ isSpeaking=T             │
│ lastStartTime=now()      │
└──────┬───────────────────┘
       │ volume ≤ 50 (after 300ms debounce)
       ▼
┌──────────────────────────────┐
│    Silent (Event Created)    │
│ isSpeaking=F                 │
│ lastEndTime=now()            │
│ → POST to backend            │
└──────────────────────────────┘
```

## Configuration & Tuning

### Volume Threshold
**Current**: 50 (on Agora's 0-100 scale)

**Adjust if**:
- Too sensitive: Increase to 60-70
- Too insensitive: Decrease to 30-40

### Debounce Duration
**Current**: 300ms

**Adjust if**:
- Too many false events: Increase to 400-500ms
- Missing real speaking: Decrease to 200ms

### Check Interval
**Current**: 200ms (Agora's reporting interval)

**Why fixed**: Set by `enableAudioVolumeIndication(interval: 200)`
- Agora's minimum effective interval
- Balances responsiveness vs. CPU usage

## Usage in Your App

### Basic Usage

```dart
// Already done in VoiceCallScreen!
// SpeakerTracker is initialized in initState
// and integrated with Agora event handlers

// To listen to speaking state changes:
_speakerTracker.speakingStatesNotifier.addListener(() {
  final states = _speakerTracker.getAllUserStates();
  // Update UI with states
});

// To check if specific user is speaking:
bool isSpeaking = _speakerTracker.isUserSpeaking(uid);

// When user leaves channel:
_speakerTracker.removeUser(uid);

// When leaving channel:
_speakerTracker.reset();
```

### Accessing Speaking Data

```dart
// Get state for specific user
UserSpeakingState? state = _speakerTracker.getUserState(uid);
if (state != null) {
  print('User ${state.uid} speaking: ${state.isSpeaking}');
  print('Started at: ${state.lastStartTime}');
}

// Get all user states
Map<int, UserSpeakingState> allStates = _speakerTracker.getAllUserStates();
allStates.forEach((uid, state) {
  print('User $uid: ${state.isSpeaking ? "Speaking" : "Silent"}');
});

// Listen to completed events
_speakerTracker.onSpeakingEventComplete = (event) {
  final duration = event.endTime.difference(event.startTime);
  print('User ${event.userId} spoke for ${duration.inSeconds}s');
};
```

## Testing Recommendations

### Manual Testing

1. **Two-User Test**
   - Start call with 2 devices
   - One user speaks continuously
   - Verify: Green indicator appears immediately after 300ms debounce
   - Verify: Backend receives event when user goes silent
   - Check console: "🎤 User X started speaking", "🛑 User X stopped speaking"

2. **Noise Test**
   - Speak in short bursts (< 300ms)
   - Verify: No false speaking events
   - Verify: Real speaking (> 300ms) detected correctly

3. **Multiple Users**
   - 3+ users in channel
   - Different users speak simultaneously
   - Verify: Each user tracked independently
   - Verify: Correct events sent to backend

4. **Backend Verification**
   ```bash
   # Check recorded events
   curl https://your-backend/events/speaking
   
   # Filter by user
   curl "https://your-backend/events/speaking?userId=12345"
   ```

### Debug Logging

Look for these console messages:
```
🎤 User X started speaking at <timestamp>
🛑 User X stopped speaking at <timestamp>
📊 Event: SpeakingEvent(userId: X, start: ..., end: ...)
✅ Event sent successfully: X
```

## Production Checklist

- [ ] Replace in-memory event storage with database (MongoDB, PostgreSQL, etc.)
- [ ] Add authentication to `/events/speaking` endpoint
- [ ] Implement rate limiting on backend
- [ ] Add error handling for failed backend requests (retry logic)
- [ ] Store speaking events in persistent database
- [ ] Create analytics dashboard to view speaking patterns
- [ ] Add session management (track which call each event belongs to)
- [ ] Implement event cleanup/archival strategy
- [ ] Add metrics (avg speaking duration, speaking frequency, etc.)
- [ ] Test with 10+ users to verify scalability
- [ ] Implement end-to-end encryption if needed
- [ ] Add user privacy settings (opt-out of tracking)

## Troubleshooting

### No speaking events recorded

**Check**:
1. Is audio volume indication enabled?
   ```dart
   await _agoraEngine.enableAudioVolumeIndication(interval: 200, reportVad: true);
   ```

2. Is microphone permission granted?
   ```dart
   await Permission.microphone.request();
   ```

3. Check console logs for "🎤 User X started speaking"
   - If not appearing: Volume threshold might be too high

4. Is backend running and accessible?
   - Test: `curl https://your-backend/health`

### Backend not receiving events

**Check**:
1. Backend URL is correct
2. Network connectivity (try simple HTTP request)
3. CORS enabled on backend: `app.use(cors())`
4. Backend logs show POST requests arriving

### High false positive rate

**Solution**:
- Increase `debounceMs` in SpeakerTracker (e.g., 500ms)
- Increase `volumeThreshold` (e.g., 60-70)
- Check microphone sensitivity settings on device

### Speaking ends immediately after starting

**Cause**: Volume threshold might be set too high
- Lower `volumeThreshold` to 40-45
- Test with different microphone positions

## Performance Considerations

- **Memory**: ~100 bytes per active user tracked
- **CPU**: Debounce timers are lightweight, processed on volume indication
- **Network**: Only 1 POST per speaking turn (when speaker goes silent)
- **UI Updates**: Only when state changes (not on every volume report)

## Future Enhancements

1. **Voice Quality Metrics**
   - Track VU (volume units) over time
   - Detect background noise levels

2. **Speaker Analytics**
   - Most talkative users
   - Average speaking duration
   - Speaking patterns by time of day

3. **Real-time Transcription**
   - Integrate Speech-to-Text
   - Convert voice to text for meeting notes

4. **Speaker Dominance**
   - Calculate % of speaking time per user
   - Alert if one person dominates

5. **Meeting Insights**
   - Generate meeting summary
   - Speaking time breakdown
   - Participation metrics

## Support & Questions

Refer to Agora documentation:
- Audio Volume Indication: https://docs.agora.io/en/video-calling/custom-experience/capture-audio-volume/
- Voice Activity Detection (VAD): https://docs.agora.io/en/video-calling/develop/advanced-features/
- Event Handlers: https://docs.agora.io/en/video-calling/reference/android-api/api-overview/

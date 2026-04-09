# Host Dashboard Implementation Guide

## Overview

This guide documents the Host Dashboard screen for the Flutter Agora voice communication app. The dashboard provides real-time visualization of:
- Active users in a session
- Speaking timeline (who spoke when)
- Audio recordings with playback functionality

## Architecture

### Backend Endpoints (Express.js)

#### New Endpoints Added

1. **POST /session/:id/users/add**
   - Register a user as joining a session
   - Body: `{ userId, username }`
   - Used when a user joins to register them in the active session

2. **GET /session/:id/users**
   - Fetch all users in a session
   - Returns: `{ sessionId, users: [], total: number }`
   - Each user has: `{ userId, username, isSpeaking }`

3. **GET /recordings**
   - Fetch recordings for a session with optional filtering
   - Query params: `?sessionId=xyz&userId=123`
   - Returns: `{ total, recordings: [] }`
   - Each recording has: `{ id, userId, sessionId, filename, url, recordedAt, durationMs }`

4. **POST /recordings/add**
   - Manually add a recording (useful for testing)
   - Body: `{ userId, sessionId, filename, url }`
   - Returns: created recording object

#### Existing Endpoints Used

- `POST /events/speaking` - Record completed speaking events
- `GET /events/speaking` - Retrieve speaking events with optional filtering
- `POST /recording/start` - Start recording a session
- `POST /recording/stop` - Stop recording a session

### Flutter Components

#### Core Files

1. **dashboard_screen.dart**
   - Main StatefulWidget managing dashboard state
   - Handles data fetching and polling (2-second intervals)
   - Manages recording start/stop
   - Coordinates with three child widgets

2. **user_list_widget.dart**
   - Displays list of users in session
   - Shows speaking status (green = speaking, grey = silent)
   - Simple, read-only display component

3. **timeline_widget.dart**
   - Renders horizontal timeline of speaking events
   - **Key Logic:**
     - Calculates timeline scale based on min/max timestamps
     - Converts timestamps to pixel positions using formula:
       ```
       left = (elapsed_ms / total_duration_ms) * width
       ```
     - Groups events by user for row-based display
     - Renders event bars with duration labels
     - Includes tooltips for duration info

4. **recording_list_widget.dart**
   - Displays recordings with play controls
   - **Audio Playback Implementation:**
     - Uses `just_audio` package for playback
     - Single AudioPlayer instance (only one audio plays at a time)
     - Tracks current playing recording, position, and duration
     - Shows progress bar with time indicators
     - Play/Pause/Stop controls
     - Automatically resets on completion

5. **Data Models**
   - `user.dart` - User model with fromJson/toJson
   - `recording.dart` - Recording model for audio files
   - `speaking_event.dart` - SpeakingEvent model (already existed, enhanced)

## State Management Pattern

The dashboard uses StatefulWidget with setState for simplicity:

```dart
class _DashboardScreenState extends State<DashboardScreen> {
  List<User> _users = [];
  List<SpeakingEvent> _speakingEvents = [];
  List<Recording> _recordings = [];

  void _startDataPolling() {
    _fetchData();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _startDataPolling();
      }
    });
  }
}
```

## Timeline Rendering Logic

### Scale Calculation

```dart
// Find earliest start and latest end time across all events
DateTime timelineStart = events.first.start;
DateTime timelineEnd = events.first.end;

// Add 10% padding on both sides for visual breathing room
final totalDuration = timelineEnd.difference(timelineStart);
final padding = Duration(milliseconds: (totalDuration.inMilliseconds * 0.1).toInt());
```

### Position Mapping

```dart
// Convert a timestamp to pixel position
double getPixelPosition(DateTime time, DateTime timelineStart, Duration totalDuration, double width) {
  final elapsed = time.difference(timelineStart);
  return (elapsed.inMilliseconds / totalDuration.inMilliseconds) * width;
}

// Example: If event starts at 10s and duration is 100s with 1000px width:
// Position = (10 * 1000 / 100) * 1000 = 100px from left
```

### Event Bar Width

```dart
// Width is calculated from start and end pixel positions
final startPixel = getPixelPosition(event.start, timelineStart, totalDuration, width);
final endPixel = getPixelPosition(event.end, timelineStart, totalDuration, width);
final barWidth = (endPixel - startPixel).clamp(2.0, double.infinity);
```

## Audio Playback Implementation

### Setup

```dart
late AudioPlayer _audioPlayer;
String? _currentPlayingRecordingId;

@override
void initState() {
  super.initState();
  _audioPlayer = AudioPlayer();
  _setupAudioPlayerListeners();
}

void _setupAudioPlayerListeners() {
  // Track position changes
  _audioPlayer.positionStream.listen((duration) {
    setState(() {
      _currentPosition = duration;
    });
  });

  // Track duration changes
  _audioPlayer.durationStream.listen((duration) {
    setState(() {
      _totalDuration = duration ?? Duration.zero;
    });
  });

  // Track playback state
  _audioPlayer.playerStateStream.listen((state) {
    setState(() {
      _isPlaying = state.playing;
    });
    if (state.processingState == ProcessingState.completed) {
      _stopPlayback();
    }
  });
}
```

### Playing a Recording

```dart
Future<void> _playRecording(Recording recording) async {
  try {
    // Stop current playback if different recording
    if (_currentPlayingRecordingId != null && _currentPlayingRecordingId != recording.id) {
      await _audioPlayer.stop();
    }

    // Load and play
    await _audioPlayer.setUrl(recording.url);
    await _audioPlayer.play();

    setState(() {
      _currentPlayingRecordingId = recording.id;
    });
  } catch (e) {
    print('Error: $e');
  }
}
```

### Key Features

- **Single Playback**: Only one audio can play at a time
- **Progress Tracking**: Real-time position and duration display
- **Play/Pause/Stop Controls**: Full playback control
- **Auto-reset**: Clears state when playback completes
- **Visual Feedback**: Highlights currently playing recording

## API Integration

### Data Fetching Flow

```dart
Future<void> _fetchData() async {
  try {
    // Fetch all data concurrently
    final usersResponse = await http.get(usersUrl);
    final eventsResponse = await http.get(eventsUrl);
    final recordingsResponse = await http.get(recordingsUrl);

    // Parse and update state
    if (mounted) {
      setState(() {
        _users = parseUsersResponse(usersResponse);
        _speakingEvents = parseEventsResponse(eventsResponse);
        _recordings = parseRecordingsResponse(recordingsResponse);
      });
    }
  } catch (e) {
    setState(() => _errorMessage = 'Error: $e');
  }
}
```

### Error Handling

- Try-catch blocks on all API calls
- Error messages displayed in UI container
- Mounted check before setState to prevent memory leaks
- User-friendly error notifications via SnackBars

## Usage Example

```dart
// Navigate to dashboard
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => DashboardScreen(
      sessionId: 'test_room',
      backendUrl: 'https://api.example.com',
      currentUserId: 1,
      currentUsername: 'Host',
    ),
  ),
);
```

## UI Layout Structure

```
┌─────────────────────────────────────────┐
│ Host Dashboard (AppBar)                 │
├─────────────────────────────────────────┤
│ Session: test_room                      │
│ [Start Recording] [Stop Recording]      │
├─────────────────────────────────────────┤
│ Users in Session                        │
│ ┌─────────────────────────────────────┐ │
│ │ User1     Status: Speaking   🟢     │ │
│ │ User2     Status: Silent     ⚪     │ │
│ └─────────────────────────────────────┘ │
├─────────────────────────────────────────┤
│ Speaking Timeline                       │
│ ┌─────────────────────────────────────┐ │
│ │ User1 |███████████|  3.2s           │ │
│ │ User2 |  ████|  1.5s                │ │
│ └─────────────────────────────────────┘ │
├─────────────────────────────────────────┤
│ Recordings                              │
│ ┌─────────────────────────────────────┐ │
│ │ ► User1 recording.m4a  2 min ago   │ │
│ │ ► User2 recording.m4a  5 min ago   │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

## Dependencies Added

```yaml
just_audio: ^0.9.36  # Audio playback with progress tracking
```

## Testing Tips

### Mock Data Generation

```dart
// Add test recordings via backend API
POST /recordings/add
{
  "userId": 1,
  "sessionId": "test_room",
  "filename": "user1_rec.m4a",
  "url": "https://example.com/recordings/user1.m4a"
}
```

### Common Issues

1. **Audio not playing**: Ensure URL is accessible and properly formatted
2. **Timeline not showing**: Check that events have proper start/end times in ISO8601 format
3. **Users not updating**: Verify polling is working (check console logs)
4. **State not updating**: Use `mounted` check before setState calls

## Future Enhancements

1. Add Provider/Riverpod for better state management
2. Implement server-sent events (SSE) for real-time updates instead of polling
3. Add filters by time range for timeline
4. Export timeline data as JSON/CSV
5. Add speaker statistics (total speaking time, count)
6. Implement local recording storage and playback
7. Add video thumbnail previews for recordings
8. Implement cloud storage integration for recordings

## Clean Code Principles Applied

- ✓ Separated concerns (each widget has single responsibility)
- ✓ Reusable components (UserList, Timeline, RecordingList are independent)
- ✓ Clear naming (variables, methods, and files are self-documenting)
- ✓ Error handling at API boundaries
- ✓ Resource cleanup (AudioPlayer disposal, polling cancellation)
- ✓ Comments on complex logic (timeline scaling, playback management)
- ✓ Type safety (strong typing throughout)
- ✓ Null safety considerations (mounted checks, fallbacks)

# Flutter Integration Guide for Agora Cloud Recording

This guide shows how to integrate the Agora Cloud Recording API with your Flutter app.

## Overview

When a user joins a voice channel, the backend will automatically start recording their audio in INDIVIDUAL mode. When they leave, the recording stops.

## Integration Steps

### Step 1: Add HTTP Package

```yaml
# pubspec.yaml
dependencies:
  flutter:
    sdk: flutter
  http: ^1.1.0
```

### Step 2: Create Recording Service

Create `lib/services/recording_service.dart`:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class RecordingService {
  static const String baseUrl = 'http://your-backend.com'; // Replace with your backend URL

  static Future<Map<String, dynamic>> startRecording({
    required String channelName,
    required int uid,
  }) async {
    try {
      print('🎬 Starting recording for channel: $channelName, uid: $uid');

      final response = await http.post(
        Uri.parse('$baseUrl/recording/start'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'channelName': channelName,
          'uid': uid,
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        print('✅ Recording started: ${data['sid']}');
        return data;
      } else {
        final error = jsonDecode(response.body);
        throw Exception('Failed to start recording: ${error['error']}');
      }
    } catch (e) {
      print('❌ Error starting recording: $e');
      rethrow;
    }
  }

  static Future<void> stopRecording({
    required String channelName,
    required int uid,
    required String resourceId,
    required String sid,
  }) async {
    try {
      print('⏹️ Stopping recording for channel: $channelName');

      final response = await http.post(
        Uri.parse('$baseUrl/recording/stop'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'channelName': channelName,
          'uid': uid,
          'resourceId': resourceId,
          'sid': sid,
        }),
      );

      if (response.statusCode == 200) {
        print('✅ Recording stopped successfully');
      } else {
        final error = jsonDecode(response.body);
        throw Exception('Failed to stop recording: ${error['error']}');
      }
    } catch (e) {
      print('❌ Error stopping recording: $e');
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getActiveRecordings() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/recording/active'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['recordings']);
      } else {
        throw Exception('Failed to fetch recordings');
      }
    } catch (e) {
      print('❌ Error fetching recordings: $e');
      rethrow;
    }
  }
}
```

### Step 3: Integrate with Voice Call Screen

Update your `voice_call_screen.dart`:

```dart
import 'package:your_app/services/recording_service.dart';

class VoiceCallScreen extends StatefulWidget {
  final String channelName;
  final int uid;

  const VoiceCallScreen({
    required this.channelName,
    required this.uid,
  });

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  late AgoraRtcEngine _engine;
  String? _recordingResourceId;
  String? _recordingSid;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    initializeAgoraAndRecording();
  }

  Future<void> initializeAgoraAndRecording() async {
    // 1. Initialize Agora engine
    _engine = createAgoraRtcEngine();
    await _engine.initialize(RtcEngineContext(appId: agoraAppId));

    // 2. Start cloud recording
    try {
      final recordingData = await RecordingService.startRecording(
        channelName: widget.channelName,
        uid: widget.uid,
      );

      setState(() {
        _recordingResourceId = recordingData['resourceId'];
        _recordingSid = recordingData['sid'];
        _isRecording = true;
      });

      print('✅ Recording started: $_recordingSid');
    } catch (e) {
      print('⚠️ Failed to start recording: $e');
      // Continue without recording if it fails
    }

    // 3. Setup Agora event handlers
    _setupEventHandlers();

    // 4. Join channel
    await _engine.joinChannel(
      token: agoraToken,
      channelId: widget.channelName,
      uid: widget.uid,
      options: const RtcChannelMediaOptions(
        autoSubscribeAudio: true,
        autoSubscribeVideo: false, // Audio-only
      ),
    );
  }

  void _setupEventHandlers() {
    _engine.registerEventHandler(
      RtcEngineEventHandler(
        onUserJoined: (connection, remoteUid, elapsed) {
          print('User joined: $remoteUid');
        },
        onUserOffline: (connection, remoteUid, reason) {
          print('User offline: $remoteUid');
        },
      ),
    );
  }

  Future<void> _leaveChannel() async {
    try {
      // 1. Stop cloud recording
      if (_isRecording && _recordingResourceId != null && _recordingSid != null) {
        await RecordingService.stopRecording(
          channelName: widget.channelName,
          uid: widget.uid,
          resourceId: _recordingResourceId!,
          sid: _recordingSid!,
        );
        print('✅ Recording stopped');
      }

      // 2. Leave Agora channel
      await _engine.leaveChannel();

      // 3. Destroy engine
      await _engine.release();

      // 4. Navigate back
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('❌ Error leaving channel: $e');
    }
  }

  @override
  void dispose() {
    _engine.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Voice Call - ${widget.channelName}'),
        actions: [
          if (_isRecording)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Tooltip(
                message: 'Recording in progress',
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('REC'),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Channel: ${widget.channelName}',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            if (_isRecording)
              const Text(
                '🎙️ Recording in progress...',
                style: TextStyle(color: Colors.red, fontSize: 14),
              ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _leaveChannel,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 15,
                ),
              ),
              child: const Text(
                'Leave Call',
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

### Step 4: Navigate to Voice Call Screen

In your main app or channel selection screen:

```dart
void _startVoiceCall(String channelName) {
  final uid = Random().nextInt(10000); // Generate random UID

  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => VoiceCallScreen(
        channelName: channelName,
        uid: uid,
      ),
    ),
  );
}
```

## Key Points

### 1. Recording Lifecycle

```
User joins channel
       ↓
Flutter calls POST /recording/start
       ↓
Backend starts Agora recording
       ↓
Users speak (audio recorded)
       ↓
User leaves channel
       ↓
Flutter calls POST /recording/stop
       ↓
Recording ends and files processed
```

### 2. Error Handling

Always wrap recording calls in try-catch:

```dart
try {
  final data = await RecordingService.startRecording(...);
} catch (e) {
  // Show error to user or log it
  print('Recording error: $e');
  // App can continue without recording
}
```

### 3. Recording Status

Show visual indicator when recording is active:

```dart
if (_isRecording)
  Container(
    color: Colors.red.withOpacity(0.3),
    child: const Text('REC'),
  ),
```

### 4. Configuration

Update the backend URL in `recording_service.dart`:

```dart
static const String baseUrl = 'https://your-backend.com'; // Production
// or
static const String baseUrl = 'http://localhost:5000'; // Development
```

## Testing

### 1. Local Testing

Use local backend:
```dart
static const String baseUrl = 'http://192.168.1.100:5000'; // Your computer IP
```

### 2. Mock Recording Service

For testing without backend:

```dart
class MockRecordingService extends RecordingService {
  @override
  static Future<Map<String, dynamic>> startRecording({
    required String channelName,
    required int uid,
  }) async {
    // Simulate API delay
    await Future.delayed(Duration(seconds: 1));
    
    return {
      'resourceId': 'mock_resource_${DateTime.now().millisecond}',
      'sid': 'mock_sid_${DateTime.now().millisecond}',
    };
  }

  @override
  static Future<void> stopRecording({...}) async {
    await Future.delayed(Duration(seconds: 1));
  }
}
```

Use in tests:
```dart
testWidgets('Voice call records audio', (WidgetTester tester) async {
  // Use MockRecordingService instead of RecordingService
  final recordingData = await MockRecordingService.startRecording(...);
  expect(recordingData['resourceId'], isNotEmpty);
});
```

## Troubleshooting

### Issue: Recording not starting

**Check:**
1. Backend is running and accessible
2. Base URL is correct in `recording_service.dart`
3. Agora credentials are set in `.env`
4. Check app logs for error message

### Issue: App continues even if recording fails

**This is expected.** The app doesn't fail if recording fails. You can add error handling:

```dart
try {
  await RecordingService.startRecording(...);
} catch (e) {
  showErrorDialog('Recording failed: $e');
  // User decides to continue or cancel
}
```

### Issue: Recording doesn't stop properly

**Make sure:**
1. You have saved `resourceId` and `sid` from start response
2. User successfully leaves channel
3. Stop API is called before dispose()

### Issue: Multiple users' audio mixed

**Check:**
1. Backend is using `recordingMode: 'individual'` (it should be)
2. Recording configuration hasn't been changed
3. Each user should get their own file (confirmed by webhook)

## Next Steps

### Enhancements

1. **Show recording duration:**
```dart
Timer? _recordingTimer;
int _recordingSeconds = 0;

void _startRecordingTimer() {
  _recordingTimer = Timer.periodic(Duration(seconds: 1), (_) {
    setState(() => _recordingSeconds++);
  });
}

void _stopRecordingTimer() {
  _recordingTimer?.cancel();
}
```

2. **Pause/Resume recording:**
```dart
// Requires additional backend endpoints:
// POST /recording/pause
// POST /recording/resume
```

3. **List past recordings:**
```dart
Future<void> _showRecordings() async {
  final recordings = await RecordingService.getActiveRecordings();
  // Show in UI
}
```

4. **Download recordings:**
```dart
Future<void> _downloadRecording(String filename) async {
  // Download from storage (S3, OSS, etc.)
}
```

## Support

For issues:
1. Check backend logs: `npm run dev`
2. Check Flutter console: `flutter run -v`
3. Test API manually with cURL
4. Verify .env credentials are correct

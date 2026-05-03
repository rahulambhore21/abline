import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:math';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:talkcircle/voice_call_screen.dart' show VoiceCallScreen;
import 'dart:io';
import 'speaker_tracker.dart';
import 'speaking_event.dart';
import 'app_config.dart';
import 'auth_service.dart';
import 'recording.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

enum PresenceStatus { online, offline, reconnecting, waiting }

/// All mutable state for the voice call, extracted from [VoiceCallScreen].
///
/// Keeping business logic here makes the screen widget thin and testable.
class VoiceCallController extends ChangeNotifier {
  // ─── Config ───────────────────────────────────────────────────────────────
  final String channelName = 'test_room';
  final String agoraAppId = AppConfig.agoraAppId;
  final String backendUrl = AppConfig.backendBaseUrl;

  // ─── Dependencies ─────────────────────────────────────────────────────────
  late RtcEngine agoraEngine;
  late SpeakerTracker speakerTracker;
  late AuthService authService;
  late AudioRecorder audioRecorder;

  // ─── Agora state ──────────────────────────────────────────────────────────
  int uid = 0;
  String? agoraToken;
  DateTime? tokenFetchedAt;

  bool isConnected = false;
  bool isJoining = false;
  List<int> remoteUsers = [];
  String statusMessage = 'Disconnected';

  // ─── UI / call state ──────────────────────────────────────────────────────
  bool isMuted = true;
  String username = '';
  Map<int, String> usernames = {};
  bool isSessionActive = false;
  bool isSpeakerOn = false; // ✅ NEW: Track speakerphone status
  bool isHost = false;
  int? hostUid;
  PresenceStatus presenceStatus = PresenceStatus.waiting;

  // ─── Recording state ──────────────────────────────────────────────────────
  bool isRecording = false;           // Cloud recording active
  bool isRecordingAudio = false;      // Local hold-to-speak recording
  DateTime? recordingStartTime;
  List<Recording> userRecordings = [];

  // ─── Speaking events ──────────────────────────────────────────────────────
  List<SpeakingEvent> speakingEvents = [];

  // ─── Internal ─────────────────────────────────────────────────────────────
  bool _checkingSession = false;
  bool _checkingRecordingStatus = false;
  Timer? _sessionStatusTimer;
  Timer? _recordingStatusTimer;
  Timer? _usernamesFetchTimer;
  Timer? _heartbeatTimer;
  Directory? _appDocDir;


  static const int _tokenValidDuration = 3300;
  static const int _sessionPollInterval = 5;
  static const int _usernameFetchInterval = 10;

  // ─── Initialisation ───────────────────────────────────────────────────────

  Future<void> init() async {
    authService = AuthService(backendUrl: backendUrl);
    audioRecorder = AudioRecorder();
    _appDocDir = await getApplicationDocumentsDirectory();
    speakerTracker = SpeakerTracker(
      backendUrl: backendUrl,
      sessionId: channelName,
      authService: authService, // Pass authService here
      onSpeakingEventComplete: (event) {
        speakingEvents.add(event);
        notifyListeners();
      },
    );

    try {
      await _loadUserInfo();
      await _initializeAgora();
    } catch (e) {
      statusMessage = 'Init failed: $e';
      onError?.call('Init error: $e');
      notifyListeners();
    }
  }

  // ─── User info ────────────────────────────────────────────────────────────

  Future<void> _loadUserInfo() async {
    final name = await authService.getUsername();
    final host = await authService.isHost();
    username = name ?? 'User';
    isHost = host;
    notifyListeners();

    if (!isHost) {
      _startSessionStatusPolling();
    } else {
      isSessionActive = true;
      presenceStatus = PresenceStatus.online;
      _startHeartbeatPolling();
      notifyListeners();
    }
  }

  // ─── Agora ────────────────────────────────────────────────────────────────

  Future<void> _initializeAgora() async {
    statusMessage = 'Requesting mic permission...';
    notifyListeners();
    await _requestMicrophonePermission();

    statusMessage = 'Initializing Agora...';
    notifyListeners();
    agoraEngine = createAgoraRtcEngine();
    await agoraEngine.initialize(RtcEngineContext(
      appId: agoraAppId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));
    
    // ✅ OPTIMIZATION: Use speech-optimized profile to save data
    await agoraEngine.setAudioProfile(
      profile: AudioProfileType.audioProfileSpeechStandard,
      scenario: AudioScenarioType.audioScenarioDefault,

    );
    
    await agoraEngine.enableAudio();

    await agoraEngine.enableAudioVolumeIndication(
      interval: 200,
      smooth: 3,
      reportVad: true,
    );
    
    
    // ✅ NEW: Default to earpiece (receiver) for normal call sound
    try {
      await agoraEngine.setDefaultAudioRouteToSpeakerphone(false);
      await agoraEngine.setEnableSpeakerphone(false);
      isSpeakerOn = false;
    } catch (e) {
      debugPrint('⚠️ Audio routing setup warning: $e');
    }
    
    _setupEventHandlers();
    statusMessage = 'Ready to join';
    notifyListeners();
    await _autoJoinCall();
  }

  Future<void> _requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      throw Exception('Microphone permission denied');
    }
  }

  void _setupEventHandlers() {
    agoraEngine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          speakerTracker.start();
          _registerUserInSession(connection.localUid ?? 0);
          _startRecordingStatusPolling();
          uid = connection.localUid ?? 0;
          isConnected = true;
          statusMessage = 'Connected';
          notifyListeners();
          _startFetchingUsernames();
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          remoteUsers.add(remoteUid);
          notifyListeners();
          if (!isHost) {
            agoraEngine.muteRemoteAudioStream(uid: remoteUid, mute: true);
          }
          _applySelectiveAudioSubscription(remoteUid);
        },
        onUserOffline: (RtcConnection connection, int remoteUid,
            UserOfflineReasonType reason) {
          speakerTracker.removeUser(remoteUid);
          remoteUsers.remove(remoteUid);
          notifyListeners();
        },
        onAudioVolumeIndication:
            (connection, speakers, totalVolume, publishVolume) {
          final now = DateTime.now();
          for (final speaker in speakers) {
            speakerTracker.processAudioVolume(
              uid: speaker.uid ?? 0,
              volume: speaker.volume ?? 0,
              at: now,
            );
          }
          speakerTracker.tick(now: now);
        },
        onTokenPrivilegeWillExpire: (RtcConnection connection, String token) {
          debugPrint('🎟️ Token will expire soon. Renewing...');
          _renewToken();
        },
      ),
    );
  }

  // ─── Session management ───────────────────────────────────────────────────

  void _startSessionStatusPolling() {
    _sessionStatusTimer?.cancel();
    _checkSessionStatus();
    _sessionStatusTimer = Timer.periodic(
      const Duration(seconds: _sessionPollInterval),
      (timer) {
        if (!_checkingSession) _checkSessionStatus();
      },
    );
  }

  void _stopSessionStatusPolling() {
    _sessionStatusTimer?.cancel();
    _sessionStatusTimer = null;
  }

  Future<void> _checkSessionStatus() async {
    if (_checkingSession) return;
    _checkingSession = true;
    try {
      final response = await http
          .get(Uri.parse('$backendUrl/session/$channelName/status'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final wasActive = isSessionActive;
        final active = (data['isActive'] ?? false) as bool;
        isSessionActive = active;
        statusMessage = active
            ? 'Session active - Ready to join'
            : 'Waiting for host to start session...';
        notifyListeners();

        if (!wasActive && active && !isConnected && !isJoining) {
          await joinChannel();
        }
        if (wasActive && !active && isConnected) {
          debugPrint('🚪 Host ended call. Disconnecting...');
          unawaited(leaveChannel()); // ✅ NEW: Force leave locally
          unawaited(onHostLeft?.call());
        }
      }
    } catch (_) {
      presenceStatus = PresenceStatus.reconnecting;
      notifyListeners();
    } finally {
      _checkingSession = false;
    }
  }

  // ─── Heartbeat (Host only) ────────────────────────────────────────────────

  void _startHeartbeatPolling() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _sendHeartbeat(),
    );
  }

  void _stopHeartbeatPolling() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> _sendHeartbeat() async {
    if (!isHost || !isConnected) return;

    try {
      final token = await authService.getToken();
      if (token == null) return;

      final response = await http
          .post(
            Uri.parse('$backendUrl/session/$channelName/heartbeat'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        if (presenceStatus != PresenceStatus.online) {
          presenceStatus = PresenceStatus.online;
          notifyListeners();
        }
      } else if (response.statusCode == 404) {
        // Session was stopped or timed out on backend
        presenceStatus = PresenceStatus.offline;
        notifyListeners();
        unawaited(leaveChannel());
      } else {
        _handleHeartbeatFailure();
      }
    } catch (e) {
      _handleHeartbeatFailure();
    }
  }

  void _handleHeartbeatFailure() {
    if (presenceStatus == PresenceStatus.online) {
      presenceStatus = PresenceStatus.reconnecting;
      notifyListeners();
    }
  }

  /// Callback set by the screen to handle host-left event.
  Future<void> Function()? onHostLeft;

  Future<void> startSessionOnBackend() async {
    try {
      final token = await authService.getToken();
      if (token == null) return;
      final response = await http
          .post(
            Uri.parse('$backendUrl/session/$channelName/start'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        isSessionActive = true;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ Error starting session: $e');
    }
  }

  Future<void> stopSessionOnBackend() async {
    try {
      final token = await authService.getToken();
      if (token == null) return;
      await http
          .post(
            Uri.parse('$backendUrl/session/$channelName/stop'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));
      isSessionActive = false;
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error stopping session: $e');
    }
  }

  // ─── Token ────────────────────────────────────────────────────────────────

  Future<void> _fetchAgoraToken({bool force = false}) async {
    if (!force && agoraToken != null && tokenFetchedAt != null) {
      final age = DateTime.now().difference(tokenFetchedAt!).inSeconds;
      if (age < _tokenValidDuration) return;
    }

    if (uid == 0) uid = Random().nextInt(100000) + 1;

    final url =
        Uri.parse('$backendUrl/agora/token?channelName=$channelName&uid=$uid');
    final response =
        await http.get(url).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      agoraToken = data['token'] as String?;
      tokenFetchedAt = DateTime.now();
      statusMessage = 'Token obtained';
      notifyListeners();
    } else {
      throw Exception('Failed to get token');
    }
  }

  Future<void> _renewToken() async {
    try {
      await _fetchAgoraToken(force: true);
      if (agoraToken != null) {
        await agoraEngine.renewToken(agoraToken!);
        debugPrint('✅ Token renewed successfully');
      }
    } catch (e) {
      debugPrint('❌ Failed to renew token: $e');
    }
  }

  // ─── Join / Leave ─────────────────────────────────────────────────────────

  Future<void> _autoJoinCall() async {
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    if (isConnected || isJoining) return;
    if (isHost) {
      await startSessionOnBackend();
      await joinChannel();
    } else if (isSessionActive) {
      await joinChannel();
    }
  }

  Future<void> joinChannel() async {
    if (isJoining || isConnected) return;
    if (!isHost && !isSessionActive) return;

    isJoining = true;
    statusMessage = 'Connecting...';
    notifyListeners();

    try {
      statusMessage = 'Fetching token...';
      notifyListeners();
      await _fetchAgoraToken();
      if (agoraToken == null) throw Exception('Token is null');

      statusMessage = 'Joining channel...';
      notifyListeners();

      await agoraEngine.joinChannel(
        token: agoraToken!,
        channelId: channelName,
        uid: uid,
        options: const ChannelMediaOptions(
          autoSubscribeAudio: true,
          publishMicrophoneTrack: true,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );

      await agoraEngine.muteLocalAudioStream(true);
      isMuted = true;
      
      // ✅ NEW: Keep screen awake during call
      unawaited(WakelockPlus.enable());
    } catch (e) {
      statusMessage = 'Failed to connect - tap to retry';
      onError?.call('Failed to join: $e');
    } finally {
      isJoining = false;
      notifyListeners();
    }
  }

  Future<void> leaveChannel() async {
    if (isHost) await stopSessionOnBackend();
    await agoraEngine.leaveChannel();
    speakerTracker.reset();
    isConnected = false;
    remoteUsers.clear();
    isMuted = true;
    
    // ✅ NEW: Allow screen to sleep after call
    unawaited(WakelockPlus.disable());
    
    statusMessage = 'Disconnected';
    _stopRecordingStatusPolling();
    _stopHeartbeatPolling();
    presenceStatus = PresenceStatus.offline;
    notifyListeners();
    if (!isHost) _startSessionStatusPolling();
  }

  /// Callback set by the screen for errors to show in a SnackBar.
  void Function(String)? onError;

  // ─── Audio mute / unmute ──────────────────────────────────────────────────

  Future<void> unmute() async {
    if (!isConnected) return;
    if (!isMuted) return; // Already unmuted
    
    isMuted = false;
    notifyListeners();
    
    // Fire and forget (mostly) to avoid lag, but handle errors
    unawaited(agoraEngine.muteLocalAudioStream(false).catchError((Object e) {
      debugPrint('Error unmuting: $e');
    }));
    
    if (!isHost && !isRecordingAudio) {
      unawaited(startAudioRecording());
    }
  }

  Future<void> mute() async {
    if (!isConnected) return;
    if (isMuted) return; // Already muted
    
    isMuted = true;
    notifyListeners();
    
    unawaited(agoraEngine.muteLocalAudioStream(true).catchError((Object e) {
      debugPrint('Error muting: $e');
    }));
    
    if (!isHost && isRecordingAudio) {
      unawaited(stopAudioRecording());
    }
  }

  Future<void> toggleMute() async =>
      isMuted ? await unmute() : await mute();

  /// Toggles between speakerphone and earpiece
  Future<void> toggleSpeakerphone() async {
    try {
      isSpeakerOn = !isSpeakerOn;
      await agoraEngine.setEnableSpeakerphone(isSpeakerOn);
      notifyListeners();
    } catch (e) {
      onError?.call('Failed to toggle speaker: $e');
    }
  }

  // ─── Selective audio subscription ─────────────────────────────────────────

  Future<void> _applySelectiveAudioSubscription(int remoteUid) async {
    if (isHost) {
      await agoraEngine.muteRemoteAudioStream(uid: remoteUid, mute: false);
      return;
    }

    if (hostUid == null) {
      await _fetchHostUidAndApply(remoteUid);
      return;
    }

    final mute = remoteUid != hostUid;
    await agoraEngine.muteRemoteAudioStream(uid: remoteUid, mute: mute);
  }

  Future<void> _fetchHostUidAndApply(int remoteUid) async {
    try {
      final response = await http
          .get(Uri.parse('$backendUrl/session/$channelName/users'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final hUid = data['hostUid'];
        if (hUid != null) {
          hostUid = hUid is int ? hUid : int.parse(hUid.toString());
          notifyListeners();
          final mute = remoteUid != hostUid;
          await agoraEngine.muteRemoteAudioStream(
              uid: remoteUid, mute: mute);
        }
      }
    } catch (_) {}
  }

  // ─── Session user registration ────────────────────────────────────────────

  Future<void> _registerUserInSession(int userUid) async {
    try {
      final response = await http
          .post(
            Uri.parse('$backendUrl/session/$channelName/users/add'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': userUid,
              'username': username,
              'role': isHost ? 'host' : 'user',
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final hUid = data['hostUid'];
        usernames[userUid] = username;
        if (hUid != null) {
          hostUid = hUid is int ? hUid : int.parse(hUid.toString());
        }
        notifyListeners();

        if (!isHost && hostUid != null) {
          for (final rUid in remoteUsers) {
            await _applySelectiveAudioSubscription(rUid);
          }
        }
      } else if (response.statusCode == 403 || response.statusCode == 409) {
        // ✅ NEW: Handle Session Not Active (403) or Duplicate Name (409)
        final errorData = jsonDecode(response.body);
        final errorMsg = (errorData['message'] ?? 'Not authorized to join') as String;
        
        await agoraEngine.leaveChannel();
        isConnected = false;
        isJoining = false;
        statusMessage = response.statusCode == 403 ? 'Call not started' : 'Name active';
        notifyListeners();
        
        onError?.call(errorMsg);
      } else {
        debugPrint('⚠️ Failed to register user in session: ${response.statusCode}');
      }
    } catch (_) {}
  }

  // ─── Username fetching ────────────────────────────────────────────────────

  void _startFetchingUsernames() {
    _fetchUsernames();
    _usernamesFetchTimer = Timer.periodic(
      const Duration(seconds: _usernameFetchInterval),
      (_) {
        if (isConnected) _fetchUsernames();
      },
    );
  }

  Future<void> _fetchUsernames() async {
    try {
      final response = await http
          .get(Uri.parse('$backendUrl/session/$channelName/users'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final users = (data['users'] as List?) ?? [];
        final hUid = data['hostUid'];

        for (var user in users) {
          if (user is Map) {
            final uId = user['userId'] is int
                ? user['userId'] as int
                : int.tryParse(user['userId']?.toString() ?? '') ?? 0;
            if (uId != 0) {
              usernames[uId] = user['username']?.toString() ?? 'Unknown';
            }
          }
        }

        if (hUid != null && hostUid == null) {
          hostUid = hUid is int ? hUid : int.tryParse(hUid.toString());
        }
        notifyListeners();

        if (!isHost && hostUid != null) {
          for (final rUid in remoteUsers) {
            await _applySelectiveAudioSubscription(rUid);
          }
        }
      }
    } catch (_) {}
  }

  // ─── Recording status ─────────────────────────────────────────────────────

  void _startRecordingStatusPolling() {
    _recordingStatusTimer?.cancel();
    _checkRecordingStatus();
    _recordingStatusTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _checkRecordingStatus());
  }

  void _stopRecordingStatusPolling() {
    _recordingStatusTimer?.cancel();
    _recordingStatusTimer = null;
  }

  Future<void> _checkRecordingStatus() async {
    if (_checkingRecordingStatus) return;
    _checkingRecordingStatus = true;
    try {
      final token = await authService.getToken();
      final response = await http
          .get(
            Uri.parse('$backendUrl/recording/active'),
            headers: {
              if (token != null) 'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final recordings = (data['recordings'] as List?) ?? [];
        isRecording =
            recordings.any((rec) => rec is Map && rec['channelName'] == channelName);
        notifyListeners();
      }
    } catch (_) {
    } finally {
      _checkingRecordingStatus = false;
    }
  }


  // ─── Local audio recording (hold-to-speak) ────────────────────────────────

  Future<void> startAudioRecording() async {
    try {
      final dir = _appDocDir ?? await getApplicationDocumentsDirectory();
      final filePath =
          '${dir.path}/recording_${uid}_${DateTime.now().millisecondsSinceEpoch}.m4a';
      
      await audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          autoGain: true, // ✅ NEW: Boosts quiet voices
        ),

        path: filePath,
      );

      
      isRecordingAudio = true;
      recordingStartTime = DateTime.now();
      notifyListeners();
    } catch (e) {
      onError?.call('Failed to start recording: $e');
    }
  }

  Future<void> stopAudioRecording() async {
    try {
      final path = await audioRecorder.stop();
      if (path != null && recordingStartTime != null) {
        final durationMs =
            DateTime.now().difference(recordingStartTime!).inMilliseconds;
        isRecordingAudio = false;
        notifyListeners();
        await _uploadRecording(File(path), durationMs);
      }
    } catch (e) {
      isRecordingAudio = false;
      notifyListeners();
      onError?.call('Failed to save recording: $e');
    }
  }

  Future<void> _uploadRecording(File audioFile, int durationMs) async {
    try {
      final token = await authService.getToken();
      if (token == null) return;

      // 1. ✅ Request a Pre-signed URL (Optimization: Direct to S3)
      final filename = 'rec_${uid}_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final responseUrl = await http.post(
        Uri.parse('$backendUrl/recordings/request-upload-url'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'filename': filename,
          'contentType': 'audio/mp4',
        }),
      ).timeout(const Duration(seconds: 10));

      if (responseUrl.statusCode != 200) {
        throw Exception('Failed to get upload URL: ${responseUrl.statusCode}');
      }
      
      final uploadUrl = jsonDecode(responseUrl.body)['uploadUrl'] as String;

      // 2. ✅ Upload DIRECTLY to S3
      final fileBytes = await audioFile.readAsBytes();
      final uploadResponse = await http.put(
        Uri.parse(uploadUrl),
        headers: {
          'Content-Type': 'audio/mp4',
        },
        body: fileBytes,
      ).timeout(const Duration(seconds: 60));

      if (uploadResponse.statusCode != 200) {
        throw Exception('S3 Direct Upload failed: ${uploadResponse.statusCode}');
      }

      // 3. ✅ Notify backend to save the record
      final s3Url = uploadUrl.split('?').first;
      final saveResponse = await http.post(
        Uri.parse('$backendUrl/recordings/save'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'userId': uid,
          'username': username,
          'sessionId': channelName,
          'durationMs': durationMs,
          'url': s3Url,
          'filename': filename,
        }),
      ).timeout(const Duration(seconds: 15));

      if (saveResponse.statusCode == 200 || saveResponse.statusCode == 201) {
        final data = jsonDecode(saveResponse.body);
        userRecordings.add(Recording(
          id: (data['recordingId'] ?? 'rec_${DateTime.now().millisecondsSinceEpoch}') as String,
          userId: uid,
          username: username,
          sessionId: channelName,
          filename: filename,
          url: s3Url,
          recordedAt: DateTime.now().toIso8601String(),
          durationMs: durationMs,
        ));
        notifyListeners();
        // Removed notification as per user request: onSuccess?.call('✅ Recording saved! 🎙️');
      }

      if (audioFile.existsSync()) audioFile.deleteSync();
    } catch (e) {
      onError?.call('Upload error: $e');
    }
  }


  /// Callback set by the screen to show a success SnackBar.
  void Function(String)? onSuccess;

  // ─── Disposal ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _stopSessionStatusPolling();
    _stopRecordingStatusPolling();
    _usernamesFetchTimer?.cancel();
    audioRecorder.dispose();
    speakerTracker.dispose();
    WakelockPlus.disable(); // Ensure wakelock is off
    _leaveChannelAndDestroy();
    super.dispose();
  }

  Future<void> _leaveChannelAndDestroy() async {
    try {
      if (isConnected) await agoraEngine.leaveChannel();
      await agoraEngine.release();
    } catch (_) {}
  }
}

import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:math';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'speaker_tracker.dart';
import 'speaking_event.dart';
import 'app_config.dart';
import 'auth_service.dart';
import 'recording.dart';
import 'user_recordings_screen.dart';

class VoiceCallScreen extends StatefulWidget {
  const VoiceCallScreen({super.key});

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  late RtcEngine _agoraEngine;
  late SpeakerTracker _speakerTracker;
  late AuthService _authService;

  final String _channelName = 'test_room';
  final String _agoraAppId = '1400d886612b4896986d7db16b0bbc44';
  late final String _backendUrl = AppConfig.backendBaseUrl;

  int _uid = 0;
  int _remoteUid = 0;
  String? _agoraToken;
  DateTime? _tokenFetchedAt;  // ✅ NEW: Track when token was fetched

  bool _isConnected = false;
  bool _isJoining = false;
  List<int> _remoteUsers = [];
  String _statusMessage = 'Disconnected';
  List<SpeakingEvent> _speakingEvents = [];
  bool _isMuted = true; // ✅ Start muted (Host: tap to toggle, User: hold to talk)
  String _username = ''; // ✅ Store username dynamically

  // ✅ Username mapping: uid -> username
  Map<int, String> _usernames = {};

  // ✅ Session status
  bool _isSessionActive = false;
  bool _checkingSession = false;
  Timer? _sessionStatusTimer; // ✅ FIX: Proper timer for session polling

  // ✅ NEW: Recording status
  bool _isRecording = false;
  bool _checkingRecordingStatus = false;
  Timer? _recordingStatusTimer; // ✅ NEW: Timer for recording status polling

  // ✅ NEW: Audio recording for hold-to-speak
  late AudioRecorder _audioRecorder;
  bool _isRecordingAudio = false;
  DateTime? _recordingStartTime;
  List<Recording> _userRecordings = [];

  // ✅ NEW: User role check
  bool _isHost = false;

  // ✅ NEW: Host UID for selective audio subscription
  int? _hostUid;

  final bool _logVolumes = false; // ✅ OPTIMIZATION: Disabled to reduce console spam
  static const int TOKEN_VALID_DURATION = 3300; // Token valid for 1 hour (3600s), refresh at 55 min
  static const int SESSION_POLL_INTERVAL = 5; // ✅ OPTIMIZATION: Increased from 3s to 5s
  static const int USERNAME_FETCH_INTERVAL = 10; // ✅ OPTIMIZATION: Increased from 5s to 10s

  @override
  void initState() {
    super.initState();
    _authService = AuthService(backendUrl: _backendUrl);
    _audioRecorder = AudioRecorder(); // ✅ NEW: Initialize audio recorder
    _speakerTracker = SpeakerTracker(
      backendUrl: _backendUrl,
      sessionId: _channelName,
      onSpeakingEventComplete: (event) {
        setState(() {
          _speakingEvents.add(event);
        });
        print('✅ Speaking event completed: $event');
      },
    );
    _loadUserInfo(); // ✅ Load username
    _initializeAgora();
  }

  /// ✅ Load user info (username and role)
  Future<void> _loadUserInfo() async {
    final username = await _authService.getUsername();
    final isHost = await _authService.isHost();

    setState(() {
      _username = username ?? 'User';
      _isHost = isHost;
    });

    print('👤 User: $_username, Role: ${isHost ? "Host (Admin)" : "User"}');

    // ✅ If user (not host), start polling session status
    if (!isHost) {
      _startSessionStatusPolling();
    } else {
      // Host can always join
      setState(() {
        _isSessionActive = true;
      });
    }
  }

  /// ✅ Poll session status for regular users (FIX: Use proper Timer)
  void _startSessionStatusPolling() {
    // Cancel any existing timer first
    _sessionStatusTimer?.cancel();

    // Initial check
    _checkSessionStatus();

    // ✅ OPTIMIZATION: Poll every 5 seconds (less aggressive)
    // ✅ IMPORTANT: Continue polling even when connected so we detect when host leaves
    _sessionStatusTimer = Timer.periodic(Duration(seconds: SESSION_POLL_INTERVAL), (timer) {
      if (!mounted) {
        // Stop polling if widget disposed
        timer.cancel();
        _sessionStatusTimer = null;
        return;
      }
      // Continue polling even when connected to detect when session ends
      _checkSessionStatus();
    });
  }

  /// ✅ Stop session status polling
  void _stopSessionStatusPolling() {
    _sessionStatusTimer?.cancel();
    _sessionStatusTimer = null;
  }

  /// ✅ NEW: Start recording status polling
  void _startRecordingStatusPolling() {
    // Cancel any existing timer first
    _recordingStatusTimer?.cancel();

    // Initial check
    _checkRecordingStatus();

    // Then poll every 3 seconds
    _recordingStatusTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        _checkRecordingStatus();
      }
    });

    print('🎬 Recording status polling started');
  }

  /// ✅ NEW: Stop recording status polling
  void _stopRecordingStatusPolling() {
    _recordingStatusTimer?.cancel();
    _recordingStatusTimer = null;
  }

  /// ✅ Check if session is active
  Future<void> _checkSessionStatus() async {
    if (_checkingSession) return;

    setState(() => _checkingSession = true);

    try {
      final response = await http
          .get(Uri.parse('$_backendUrl/session/$_channelName/status'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final wasActive = _isSessionActive;
        final isActive = data['isActive'] ?? false;

        print('📡 Session check - wasActive: $wasActive, isActive: $isActive, connected: $_isConnected');

        if (mounted) {
          setState(() {
            _isSessionActive = isActive;
            _checkingSession = false;
            if (!isActive) {
              _statusMessage = 'Waiting for host to start session...';
            } else {
              _statusMessage = 'Session active - Ready to join';
            }
          });

          // ✅ Auto-join when session becomes active (state change)
          if (!wasActive && isActive && !_isConnected && !_isJoining) {
            print('✅ Session activated - auto-joining now...');
            _joinChannel();
          }

          // ✅ Kick out users when host leaves (session becomes inactive)
          if (wasActive && !isActive && _isConnected) {
            print('🚪 Host left! Kicking user out immediately...');
            _showErrorSnackBar('Host ended the call');
            // Force disconnect and navigate back to home
            await _forceExitCall();
          }
        }
      }
    } catch (e) {
      print('Error checking session status: $e');
      if (mounted) {
        setState(() => _checkingSession = false);
      }
    }
  }

  /// ✅ Force disconnect user and navigate to home (triggered when host leaves)
  Future<void> _forceExitCall() async {
    try {
      print('🚪 Forcing user to exit call...');

      // Leave Agora channel first
      try {
        await _agoraEngine.leaveChannel();
      } catch (e) {
        print('Error leaving Agora channel: $e');
      }

      _speakerTracker.reset();

      if (mounted) {
        setState(() {
          _isConnected = false;
          _remoteUsers.clear();
          _remoteUid = 0;
          _isMuted = true;
          _statusMessage = 'Host ended the call';
        });

        // ✅ Stop recording status polling
        _stopRecordingStatusPolling();

        // Navigate back to home screen
        print('🏠 Navigating back to home screen...');
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      print('Error forcing exit: $e');
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  Future<void> _initializeAgora() async {
    try {
      await _requestMicrophonePermission();
      _agoraEngine = createAgoraRtcEngine();
      await _agoraEngine.initialize(
        RtcEngineContext(appId: _agoraAppId),
      );
      await _agoraEngine.enableAudio();
      await _agoraEngine.enableAudioVolumeIndication(
        interval: 200,
        smooth: 3,
        reportVad: true,
      );
      _setupEventHandlers();
      setState(() {
        _statusMessage = 'Ready to join call';
      });

      // ✅ Auto-join call after initialization
      _autoJoinCall();
    } catch (e) {
      print('Error initializing Agora: $e');
      _showErrorSnackBar('Failed to initialize Agora: $e');
    }
  }

  /// ✅ Automatically join the call after Agora is ready
  Future<void> _autoJoinCall() async {
    // Wait longer to ensure Agora engine is fully initialized
    await Future.delayed(const Duration(milliseconds: 1000));

    if (mounted && !_isConnected && !_isJoining) {
      // Check if allowed to join
      if (_isHost) {
        print('🚀 Host auto-joining call and starting session...');
        // Host starts the session on backend before joining
        await _startSessionOnBackend();
        await _joinChannel();
      } else if (_isSessionActive) {
        print('🚀 Auto-joining call...');
        await _joinChannel();
      } else {
        print('⏸️ Waiting for host to start session before auto-joining');
        // Session polling will trigger auto-join when _isSessionActive becomes true
      }
    }
  }

  /// ✅ Start session on backend (host-only)
  Future<void> _startSessionOnBackend() async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        print('⚠️ No auth token available, skipping session start');
        return;
      }

      final response = await http.post(
        Uri.parse('$_backendUrl/session/$_channelName/start'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        print('✅ Session started on backend');
        setState(() {
          _isSessionActive = true;
        });
      } else {
        print('⚠️ Failed to start session: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Error starting session on backend: $e');
    }
  }

  Future<void> _requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _showErrorSnackBar('Microphone permission is required');
      throw Exception('Microphone permission denied');
    }
  }

  Future<void> _fetchAgoraToken() async {
    try {
      // ✅ OPTIMIZATION: Check if token is still valid (not expired)
      if (_agoraToken != null && _tokenFetchedAt != null) {
        final timeSinceFetch = DateTime.now().difference(_tokenFetchedAt!).inSeconds;
        if (timeSinceFetch < TOKEN_VALID_DURATION) {
          print('✅ Token still valid, reusing (fetched ${timeSinceFetch}s ago)');
          return; // Reuse existing token, skip network request
        }
      }

      if (_uid == 0) {
        _uid = Random().nextInt(100000) + 1;
      }

      final url = Uri.parse(
        '$_backendUrl/agora/token?channelName=$_channelName&uid=$_uid',
      );

      print('🔄 Fetching fresh token from backend...');
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Token request timeout');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _agoraToken = data['token'];
          _tokenFetchedAt = DateTime.now();  // ✅ Record fetch time
          _statusMessage = 'Token obtained';
        });
        print('✅ New token fetched');
      } else {
        throw Exception('Failed to get token');
      }
    } catch (e) {
      print('❌ Error fetching token: $e');
      _showErrorSnackBar('Failed to fetch token: $e');
      rethrow;
    }
  }

  void _setupEventHandlers() {
    _agoraEngine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          print('✅ Joined channel successfully');
          _speakerTracker.start();

          // ✅ Keep polling for non-host users so they can detect when host leaves
          // (Don't stop polling - we need it to kick out users when session ends)

          // ✅ Register user in session
          _registerUserInSession(connection.localUid ?? 0);

          // ✅ Check recording status when joined & start polling
          _startRecordingStatusPolling();

          setState(() {
            _uid = connection.localUid ?? 0;
            _isConnected = true;
            _statusMessage = 'Connected';
          });

          // ✅ Start fetching usernames periodically
          _startFetchingUsernames();
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          print('Remote user $remoteUid joined');
          setState(() {
            _remoteUsers.add(remoteUid);
            _remoteUid = remoteUid;
          });

          // ✅ Apply muting IMMEDIATELY - for non-host users, mute all by default
          // This prevents audio from other users, only unmute admin when identified
          if (!_isHost) {
            print('🔇 User role: Muting all remote users by default');
            _agoraEngine.muteRemoteAudioStream(uid: remoteUid, mute: true);
          }

          // ✅ SELECTIVE AUDIO: If current user is not host, mute all clients (only hear admin)
          _applySelectiveAudioSubscription(remoteUid);
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          print('Remote user $remoteUid left');
          _speakerTracker.removeUser(remoteUid);
          setState(() {
            _remoteUsers.remove(remoteUid);
            if (_remoteUid == remoteUid) {
              _remoteUid = 0;
            }
          });
        },
        onAudioVolumeIndication: (connection, speakers, totalVolume, publishVolume) {
          final now = DateTime.now();
          for (final speaker in speakers) {
            final uid = speaker.uid ?? 0;
            final volume = speaker.volume ?? 0;
            if (_logVolumes) {
              print('🔊 uid=$uid volume=$volume');
            }
            _speakerTracker.processAudioVolume(
              uid: uid,
              volume: volume,
              at: now,
            );
          }
          _speakerTracker.tick(now: now);
        },
      ),
    );
  }

  /// ✅ Apply selective audio subscription based on user role
  /// - Regular users: Only hear the admin/host
  /// - Admin/host users: Hear everyone
  Future<void> _applySelectiveAudioSubscription(int remoteUid) async {
    print('🔧 Applying audio subscription for UID: $remoteUid, isHost: $_isHost, hostUid: $_hostUid');

    if (_isHost) {
      // Host can hear everyone - subscribe to all audio streams (default behavior)
      print('👑 Host: Subscribing to all audio streams (UID: $remoteUid)');
      await _agoraEngine.muteRemoteAudioStream(uid: remoteUid, mute: false);
    } else {
      // Regular user: Only subscribe to host's audio stream
      if (_hostUid == null) {
        // ✅ CRITICAL FIX: If we don't know host UID yet, fetch it from backend immediately
        print('⏳ Client: Don\'t know host UID yet. Fetching from backend...');
        await _fetchHostUidAndApply(remoteUid);
        return;
      }

      if (remoteUid == _hostUid) {
        // This is the host - UNMUTE them (override default)
        print('🔊 Client: UNMUTING HOST audio stream (UID: $remoteUid)');
        await _agoraEngine.muteRemoteAudioStream(uid: remoteUid, mute: false);
      } else {
        // This is another client - keep muted (already muted by default)
        print('🔇 Client: Keeping other CLIENT muted (UID: $remoteUid)');
        await _agoraEngine.muteRemoteAudioStream(uid: remoteUid, mute: true);
      }
    }
  }

  /// ✅ NEW: Fetch host UID from backend and apply selective audio immediately
  /// This prevents the race condition where admin joins before we know their UID
  Future<void> _fetchHostUidAndApply(int remoteUid) async {
    try {
      final response = await http
          .get(Uri.parse('$_backendUrl/session/$_channelName/users'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final hostUid = data['hostUid'];

        if (hostUid != null) {
          final hostUidInt = hostUid is int
              ? hostUid as int
              : int.parse(hostUid.toString());

          setState(() {
            _hostUid = hostUidInt;
          });

          print('👑 Host UID fetched immediately: $_hostUid');

          // Now apply the audio subscription with the known host UID
          if (remoteUid == _hostUid) {
            print('🔊 Client: UNMUTING HOST audio stream (UID: $remoteUid)');
            await _agoraEngine.muteRemoteAudioStream(uid: remoteUid, mute: false);
          } else {
            print('🔇 Client: Keeping other CLIENT muted (UID: $remoteUid)');
            await _agoraEngine.muteRemoteAudioStream(uid: remoteUid, mute: true);
          }
        } else {
          print('⏳ No host UID found yet, keeping UID $remoteUid muted');
        }
      }
    } catch (e) {
      print('Error fetching host UID: $e');
    }
  }

  Future<void> _joinChannel() async {
    if (_isJoining || _isConnected) {
      print('⚠️ Already joining or connected - skipping join attempt');
      return;
    }

    // ✅ Check if user is allowed to join (non-host users need active session)
    if (!_isHost && !_isSessionActive) {
      print('⏸️ Waiting for host to start the session');
      return;
    }

    setState(() {
      _isJoining = true;
      _statusMessage = 'Connecting...';
    });

    try {
      // ✅ DEBUG: Track timing for delay analysis
      print('📥 Starting channel join process...');
      final startTime = DateTime.now();

      await _fetchAgoraToken();
      if (_agoraToken == null) {
        throw Exception('Token is null');
      }

      print('🎯 Joining channel with UID: $_uid, Token: ${_agoraToken!.substring(0, 20)}...');

      await _agoraEngine.joinChannel(
        token: _agoraToken!,
        channelId: _channelName,
        uid: _uid,
        options: ChannelMediaOptions(
          autoSubscribeAudio: true,
          publishMicrophoneTrack: true,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );

      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      print('✅ Channel join completed in ${elapsed}ms');

      // ✅ Start muted for both host and users
      // Host: Can toggle with tap, User: Hold to speak
      await _agoraEngine.muteLocalAudioStream(true); // Start muted

      setState(() {
        _isJoining = false;
        _isMuted = true; // Start muted
      });
    } catch (e) {
      print('❌ Error joining channel: $e');
      _showErrorSnackBar('Failed to join: $e');
      setState(() {
        _isJoining = false;  // ✅ CRITICAL FIX: Reset joining state so user can retry
        _statusMessage = 'Failed to connect - tap to retry';
      });
    }
  }

  Future<void> _leaveChannel() async {
    try {
      // ✅ Host stops the session on backend (users will be kicked out)
      if (_isHost) {
        await _stopSessionOnBackend();
      }

      await _agoraEngine.leaveChannel();
      _speakerTracker.reset();

      setState(() {
        _isConnected = false;
        _remoteUsers.clear();
        _remoteUid = 0;
        _isMuted = true; // Reset to muted when leaving
        _statusMessage = 'Disconnected';
      });

      // ✅ Stop recording status polling when leaving
      _stopRecordingStatusPolling();

      // ✅ Restart polling for non-host users after leaving
      if (!_isHost && mounted) {
        _startSessionStatusPolling();
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      print('Error leaving channel: $e');
      _showErrorSnackBar('Error leaving channel: $e');
    }
  }

  /// ✅ Stop session on backend (host-only) - kicks out all users
  Future<void> _stopSessionOnBackend() async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        print('⚠️ No auth token available, skipping session stop');
        return;
      }

      final response = await http.post(
        Uri.parse('$_backendUrl/session/$_channelName/stop'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        print('✅ Session stopped on backend - users will be kicked out');
        setState(() {
          _isSessionActive = false;
        });
      } else {
        print('⚠️ Failed to stop session: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Error stopping session on backend: $e');
    }
  }

  /// ✅ Check if recording is active for this session
  Future<void> _checkRecordingStatus() async {
    if (_checkingRecordingStatus) return;

    setState(() => _checkingRecordingStatus = true);

    try {
      final response = await http
          .get(Uri.parse('$_backendUrl/recording/active'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final recordings = data['recordings'] as List;

        // Check if there's an active recording for this channel
        final isRecording = recordings.any((rec) => rec['channelName'] == _channelName);

        if (mounted) {
          setState(() {
            _isRecording = isRecording;
            _checkingRecordingStatus = false;
          });
        }

        print('📡 Recording status: ${isRecording ? "🔴 RECORDING" : "⭕ Not recording"}');
      }
    } catch (e) {
      print('Error checking recording status: $e');
      if (mounted) {
        setState(() => _checkingRecordingStatus = false);
      }
    }
  }

  /// ✅ Register user in session with username
  Future<void> _registerUserInSession(int uid) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_backendUrl/session/$_channelName/users/add'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': uid,
              'username': _username,
              'role': _isHost ? 'host' : 'user', // ✅ Send role to backend
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        print('✅ User registered in session: $_username (uid: $uid)');

        // ✅ Get host UID from response
        final data = jsonDecode(response.body);
        final hostUid = data['hostUid'];

        setState(() {
          _usernames[uid] = _username;
          if (hostUid != null) {
            // ✅ FIX: Ensure hostUid is converted to int
            _hostUid = hostUid is int
                ? hostUid as int
                : int.parse(hostUid.toString());
            print('👑 Host UID identified: $_hostUid');
          }
        });

        // ✅ Apply selective audio subscription for existing users
        if (!_isHost && _hostUid != null) {
          print('🔄 Re-applying audio filters now that we know host UID: $_hostUid');
          print('📋 Remote users in channel: $_remoteUsers');
          for (final remoteUid in _remoteUsers) {
            print('   → Processing UID: $remoteUid (isHost: ${remoteUid == _hostUid})');
            await _applySelectiveAudioSubscription(remoteUid);
          }
          print('✅ Finished re-applying audio filters');
        }
      } else {
        print('⚠️ Failed to register user in session: ${response.body}');
      }
    } catch (e) {
      print('❌ Error registering user in session: $e');
    }
  }

  /// ✅ Start fetching usernames periodically
  Timer? _usernamesFetchTimer;
  void _startFetchingUsernames() {
    _fetchUsernames(); // Initial fetch

    // ✅ OPTIMIZATION: Fetch every 10 seconds (reduced frequency)
    _usernamesFetchTimer = Timer.periodic(Duration(seconds: USERNAME_FETCH_INTERVAL), (timer) {
      if (!mounted || !_isConnected) {
        timer.cancel();
        return;
      }
      _fetchUsernames();
    });
  }

  /// ✅ Fetch usernames from backend
  Future<void> _fetchUsernames() async {
    try {
      final response = await http
          .get(Uri.parse('$_backendUrl/session/$_channelName/users'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final users = data['users'] as List;
        final hostUid = data['hostUid'];

        if (mounted) {
          setState(() {
            for (var user in users) {
              // ✅ FIX: Explicitly convert userId to int to match Agora UID type
              final userId = user['userId'] is int
                  ? user['userId'] as int
                  : int.parse(user['userId'].toString());
              final username = user['username'] as String;
              _usernames[userId] = username;
              print('📝 Mapped username: UID $userId → $username');
            }

            // ✅ Update host UID if available
            if (hostUid != null && _hostUid == null) {
              _hostUid = hostUid is int
                  ? hostUid as int
                  : int.parse(hostUid.toString());
              print('👑 Host UID identified from user list: $_hostUid');
            }
          });

          // ✅ Re-apply selective audio subscription if we just learned the host UID
          if (!_isHost && _hostUid != null) {
            print('🔄 Re-applying audio filters (from fetchUsernames) for host UID: $_hostUid');
            print('📋 Remote users: $_remoteUsers');
            for (final remoteUid in _remoteUsers) {
              print('   → Processing UID: $remoteUid (isHost: ${remoteUid == _hostUid})');
              await _applySelectiveAudioSubscription(remoteUid);
            }
            print('✅ Finished re-applying filters (from fetchUsernames)');
          }
        }
      }
    } catch (e) {
      print('Error fetching usernames: $e');
    }
  }

  /// ✅ Unmute (hold to talk or toggle for host)
  Future<void> _unmute() async {
    if (!_isConnected) return;

    try {
      await _agoraEngine.muteLocalAudioStream(false);

      // ✅ NEW: Start audio recording when unmuting (for users)
      if (!_isHost && !_isRecordingAudio) {
        await _startAudioRecording();
      }

      setState(() {
        _isMuted = false;
      });
      print('🎤 Unmuted - Speaking');
    } catch (e) {
      print('Error unmuting: $e');
    }
  }

  /// ✅ Mute (release button or toggle for host)
  Future<void> _mute() async {
    if (!_isConnected) return;

    try {
      await _agoraEngine.muteLocalAudioStream(true);

      // ✅ NEW: Stop audio recording when muting (for users)
      if (!_isHost && _isRecordingAudio) {
        await _stopAudioRecording();
      }

      setState(() {
        _isMuted = true;
      });
      print('🔇 Muted - Listening');
    } catch (e) {
      print('Error muting: $e');
    }
  }

  /// ✅ NEW: Start audio recording for hold-to-speak
  Future<void> _startAudioRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final fileName = 'recording_${_uid}_${DateTime.now().millisecondsSinceEpoch}.m4a';
        final filePath = '${dir.path}/$fileName';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: filePath,
        );

        setState(() {
          _isRecordingAudio = true;
          _recordingStartTime = DateTime.now();
        });

        print('🎙️ Recording started - UID: $_uid, Path: $filePath');
      } else {
        print('❌ Microphone permission denied');
        _showErrorSnackBar('Microphone permission required');
      }
    } catch (e) {
      print('Error starting recording: $e');
      _showErrorSnackBar('Failed to start recording: $e');
    }
  }

  /// ✅ NEW: Stop audio recording and upload
  Future<void> _stopAudioRecording() async {
    try {
      final recordingPath = await _audioRecorder.stop();

      if (recordingPath != null && _recordingStartTime != null) {
        final durationMs = DateTime.now().difference(_recordingStartTime!).inMilliseconds;

        setState(() {
          _isRecordingAudio = false;
        });

        // Upload to backend
        await _uploadRecording(File(recordingPath), durationMs);

        print('✅ Recording saved and uploaded - Duration: ${durationMs}ms');
      }
    } catch (e) {
      print('Error stopping recording: $e');
      _showErrorSnackBar('Failed to save recording: $e');
      setState(() {
        _isRecordingAudio = false;
      });
    }
  }

  /// ✅ NEW: Upload recording to backend
  Future<void> _uploadRecording(File audioFile, int durationMs) async {
    try {
      final uri = Uri.parse('$_backendUrl/recordings/save');
      print('📤 Starting upload to: $uri');
      print('   File: ${audioFile.path}');
      print('   Size: ${audioFile.lengthSync()} bytes');
      print('   Duration: ${durationMs}ms');

      final request = http.MultipartRequest('POST', uri);

      // Add file
      request.files.add(
        await http.MultipartFile.fromPath('audioFile', audioFile.path),
      );

      // Add metadata
      request.fields['userId'] = _uid.toString();
      request.fields['sessionId'] = _channelName;
      request.fields['durationMs'] = durationMs.toString();

      print('📤 Sending request...');
      final response = await request.send().timeout(const Duration(seconds: 60));

      print('📡 Response status: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseBody = await response.stream.bytesToString();
        print('📦 Response body: $responseBody');

        final data = jsonDecode(responseBody);

        // Create Recording object
        final recording = Recording(
          id: data['recordingId'] ?? 'rec_${DateTime.now().millisecondsSinceEpoch}',
          userId: _uid,
          sessionId: _channelName,
          filename: audioFile.path.split('/').last,
          url: data['url'] ?? audioFile.path,
          recordedAt: DateTime.now().toIso8601String(),
          durationMs: durationMs,
        );

        if (mounted) {
          setState(() {
            _userRecordings.add(recording);
          });
        }

        _showSuccessSnackBar('✅ Recording saved! 🎙️');
        print('✅ Recording uploaded successfully - ID: ${data['recordingId']}');
      } else {
        final responseBody = await response.stream.bytesToString();
        print('❌ Upload failed: ${response.statusCode}');
        print('   Response: $responseBody');
        _showErrorSnackBar('Upload failed (${response.statusCode}): $responseBody');
      }

      // Clean up local file
      if (audioFile.existsSync()) {
        audioFile.deleteSync();
        print('✓ Cleaned up temp file');
      }
    } catch (e) {
      print('❌ Error uploading recording: $e');
      print('   Stack trace: $e');
      _showErrorSnackBar('Upload error: $e');
    }
  }

  /// ✅ NEW: Toggle mute state (for admin/host only)
  Future<void> _toggleMute() async {
    if (!_isConnected) return;

    if (_isMuted) {
      await _unmute();
    } else {
      await _mute();
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _stopSessionStatusPolling(); // ✅ FIX: Clean up polling timer
    _stopRecordingStatusPolling(); // ✅ NEW: Clean up recording status polling
    _usernamesFetchTimer?.cancel(); // ✅ Clean up username fetch timer
    _audioRecorder.dispose(); // ✅ NEW: Clean up audio recorder
    _leaveChannelAndDestroy();
    _speakerTracker.dispose();
    super.dispose();
  }

  Future<void> _leaveChannelAndDestroy() async {
    try {
      if (_isConnected) {
        await _agoraEngine.leaveChannel();
      }
      await _agoraEngine.release();
    } catch (e) {
      print('Error destroying engine: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2a2a2a),
      body: SafeArea(
        child: Column(
          children: [
            // Top bar with back button and username
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white30),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Hello, $_username', // ✅ Dynamic username
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ✅ NEW: Recording Status Indicator
            if (_isRecording)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  border: Border.all(color: Colors.red, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red,
                            blurRadius: 6,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      '🔴 RECORDING ACTIVE',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            if (_isRecording) const SizedBox(height: 16),

            // ✅ NEW: Session Status Indicator (for non-host users)
            if (!_isHost && !_isConnected)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: _isSessionActive
                      ? Colors.green.withOpacity(0.2)
                      : Colors.orange.withOpacity(0.2),
                  border: Border.all(
                    color: _isSessionActive ? Colors.green : Colors.orange,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isSessionActive ? Icons.check_circle : Icons.access_time,
                      color: _isSessionActive ? Colors.green : Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _isSessionActive
                            ? '✅ Session is active - You can join now'
                            : '⏳ Waiting for host to start the session...',
                        style: TextStyle(
                          color: _isSessionActive ? Colors.green : Colors.orange,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (!_isHost && !_isConnected) const SizedBox(height: 16),

            // Control buttons (Speaker, Bluetooth, My Recordings, Exit Room)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF3a3a3a),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildControlButton(
                    icon: Icons.volume_up,
                    label: 'Speaker',
                    color: const Color(0xFF00D4FF),
                  ),
                  _buildControlButton(
                    icon: Icons.bluetooth,
                    label: 'Bluetooth',
                    color: const Color(0xFF00D4FF),
                  ),
                  // ✅ NEW: My Recordings button (for non-host users)
                  if (!_isHost)
                    _buildControlButton(
                      icon: Icons.music_note,
                      label: 'Recordings',
                      color: const Color(0xFF00FF41),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => UserRecordingsScreen(
                              sessionId: _channelName,
                              userId: _uid,  // ✅ NEW: Pass Agora UID
                            ),
                          ),
                        );
                      },
                    ),
                  _buildControlButton(
                    icon: Icons.close,
                    label: 'Exit Room',
                    color: const Color(0xFF8B4789),
                    onTap: _leaveChannel,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            // Center content
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ✅ Microphone button with recording indicator badge
                  Stack(
                    alignment: Alignment.topRight,
                    children: [
                      GestureDetector(
                        // Host: Tap to toggle
                        onTap: _isHost && _isConnected ? () async {
                          await _toggleMute();
                        } : null,
                        // Regular User: Hold to talk
                        onTapDown: !_isHost && _isConnected ? (details) async {
                          await _unmute(); // Unmute when pressing down
                        } : null,
                        onTapUp: !_isHost && _isConnected ? (details) async {
                          await _mute(); // Mute when releasing
                        } : null,
                        onTapCancel: !_isHost && _isConnected ? () async {
                          await _mute(); // Mute if gesture is cancelled
                        } : null,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _isJoining
                                    ? const Color(0xFFFFCD00).withOpacity(0.6)
                                    : (!_isHost && !_isSessionActive && !_isConnected)
                                        ? Colors.grey.withOpacity(0.3) // ✅ Grey when disabled
                                        : _isMuted
                                            ? const Color(0xFFFF4757).withOpacity(0.6) // Red when muted
                                            : const Color(0xFF00FF41).withOpacity(0.6), // Green when speaking
                                blurRadius: 30,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _isJoining
                                    ? const Color(0xFFFFCD00).withOpacity(0.4)
                                    : (!_isHost && !_isSessionActive && !_isConnected)
                                        ? Colors.grey.withOpacity(0.3) // ✅ Grey border when disabled
                                        : _isMuted
                                            ? const Color(0xFFFF4757).withOpacity(0.4) // Red border when muted
                                            : const Color(0xFF00FF41).withOpacity(0.4), // Green border when speaking
                                width: 3,
                              ),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isJoining
                                    ? const Color(0xFFFFCD00)
                                    : (!_isHost && !_isSessionActive && !_isConnected)
                                        ? Colors.grey // ✅ Grey when disabled
                                        : _isMuted
                                            ? const Color(0xFFFF4757) // Red when muted
                                            : const Color(0xFF00FF41), // Green when speaking
                              ),
                              child: _isJoining
                                  ? const SizedBox(
                                      width: 60,
                                      height: 60,
                                      child: CircularProgressIndicator(
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        strokeWidth: 3,
                                      ),
                                    )
                                  : Icon(
                                      _isMuted ? Icons.mic_off : Icons.mic,
                                      size: 60,
                                      color: Colors.white,
                                    ),
                            ),
                          ),
                        ),
                      ),
                      // ✅ NEW: Recording indicator badge
                      if (_isRecordingAudio)
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.red,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withOpacity(0.8),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Text(
                            '🔴',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // ✅ Status text (different for host vs user)
                  Text(
                    _isJoining
                        ? 'CONNECTING...'
                        : _isConnected
                            ? _isHost
                                // Host: Toggle mode
                                ? (_isMuted ? 'TAP TO UNMUTE' : 'TAP TO MUTE')
                                // User: Hold-to-talk mode
                                : (_isMuted ? 'HOLD TO TALK' : 'SPEAKING - RELEASE TO MUTE')
                            : (!_isHost && !_isSessionActive)
                                ? 'WAITING FOR HOST...'
                                : 'JOINING...',
                    style: TextStyle(
                      color: _isJoining
                          ? const Color(0xFFFFCD00)
                          : _isConnected && !_isMuted
                              ? const Color(0xFF00FF41) // Green text when speaking
                              : Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            // ✅ Speaking Status Section (only visible to host/admin)
            if (_isConnected && _remoteUsers.isNotEmpty && _isHost)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3a3a3a),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Who\'s Talking',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ValueListenableBuilder<Map<int, UserSpeakingState>>(
                          valueListenable: _speakerTracker.speakingStatesNotifier,
                          builder: (context, speakingStates, _) {
                            // Build list of users with speaking status
                            final userEntries = speakingStates.entries.toList();

                            if (userEntries.isEmpty) {
                              return Center(
                                child: Text(
                                  'Listening...',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                              );
                            }

                            return ListView.separated(
                              itemCount: userEntries.length,
                              separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                              itemBuilder: (context, index) {
                                final entry = userEntries[index];
                                final uid = entry.key;
                                final state = entry.value;
                                final username = _usernames[uid] ?? 'User #$uid'; // ✅ Get actual username

                                return Row(
                                  children: [
                                    // Speaking indicator (animated dot)
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: state.isSpeaking
                                            ? Colors.green
                                            : Colors.grey,
                                        boxShadow: state.isSpeaking
                                            ? [
                                                BoxShadow(
                                                  color: Colors.green.withOpacity(0.5),
                                                  blurRadius: 8,
                                                )
                                              ]
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // User info
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            username, // ✅ Show actual username instead of User #123
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            state.isSpeaking ? '🎤 Speaking' : '🔇 Listening',
                                            style: TextStyle(
                                              color: state.isSpeaking
                                                  ? Colors.green
                                                  : Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Volume indicator
                                    if (state.isSpeaking)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'ACTIVE',
                                          style: TextStyle(
                                            color: Colors.green,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Bottom spacer
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

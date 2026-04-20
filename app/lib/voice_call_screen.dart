import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:math';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'speaker_tracker.dart';
import 'speaking_event.dart';
import 'app_config.dart';
import 'auth_service.dart';

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
  bool _isMuted = true; // ✅ Start muted, user holds to talk
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

  // ✅ NEW: User role check
  bool _isHost = false;

  // ✅ NEW: Host UID for selective audio subscription
  int? _hostUid;

  final bool _logVolumes = true;
  static const int TOKEN_VALID_DURATION = 3300; // Token valid for 1 hour (3600s), refresh at 55 min

  @override
  void initState() {
    super.initState();
    _authService = AuthService(backendUrl: _backendUrl);
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

    // Poll every 3 seconds until connected
    _sessionStatusTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted || _isConnected) {
        // Stop polling if widget disposed or user connected
        timer.cancel();
        _sessionStatusTimer = null;
        return;
      }
      _checkSessionStatus();
    });
  }

  /// ✅ Stop session status polling
  void _stopSessionStatusPolling() {
    _sessionStatusTimer?.cancel();
    _sessionStatusTimer = null;
  }

  /// ✅ Check if session is active
  Future<void> _checkSessionStatus() async {
    if (_checkingSession || _isConnected) return;

    setState(() => _checkingSession = true);

    try {
      final response = await http
          .get(Uri.parse('$_backendUrl/session/$_channelName/status'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final isActive = data['isActive'] ?? false;

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
        }

        print('📡 Session status: ${isActive ? "✅ Active" : "⏸️ Not started"}');
      }
    } catch (e) {
      print('Error checking session status: $e');
      if (mounted) {
        setState(() => _checkingSession = false);
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
    // Wait a brief moment for session status to be checked
    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted && !_isConnected && !_isJoining) {
      // Check if allowed to join
      if (_isHost || _isSessionActive) {
        print('🚀 Auto-joining call...');
        await _joinChannel();
      } else {
        print('⏸️ Waiting for host to start session before auto-joining');
        // Start listening for session status changes
        _waitForSessionAndAutoJoin();
      }
    }
  }

  /// ✅ Wait for session to become active, then auto-join
  void _waitForSessionAndAutoJoin() {
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_isConnected || _isJoining) {
        timer.cancel();
        return;
      }

      if (_isSessionActive) {
        print('✅ Session is now active, auto-joining...');
        timer.cancel();
        _joinChannel();
      }
    });
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

          // ✅ Stop session polling once connected
          _stopSessionStatusPolling();

          // ✅ Register user in session
          _registerUserInSession(connection.localUid ?? 0);

          // ✅ Check recording status when joined
          _checkRecordingStatus();

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
    if (_isHost) {
      // Host can hear everyone - subscribe to all audio streams (default behavior)
      print('👑 Host: Subscribing to all audio streams (UID: $remoteUid)');
      await _agoraEngine.muteRemoteAudioStream(remoteUid, false);
    } else {
      // Regular user: Only subscribe to host's audio stream
      if (_hostUid != null && remoteUid == _hostUid) {
        // This is the host - unmute them
        print('🔊 Client: Unmuting HOST audio stream (UID: $remoteUid)');
        await _agoraEngine.muteRemoteAudioStream(remoteUid, false);
      } else {
        // This is another client - mute them
        print('🔇 Client: Muting other CLIENT audio stream (UID: $remoteUid)');
        await _agoraEngine.muteRemoteAudioStream(remoteUid, true);
      }
    }
  }

  Future<void> _joinChannel() async {
    if (_isJoining || _isConnected) {
      _showErrorSnackBar('Already joining or connected');
      return;
    }

    // ✅ Check if user is allowed to join (non-host users need active session)
    if (!_isHost && !_isSessionActive) {
      _showErrorSnackBar('⏸️ Waiting for host to start the session');
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

      // ✅ Auto-unmute when joined to start conversation
      await _agoraEngine.muteLocalAudioStream(true); // Start muted

      setState(() {
        _isJoining = false;
        _isMuted = true; // Start muted, user holds button to talk
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
      await _agoraEngine.leaveChannel();
      _speakerTracker.reset();

      setState(() {
        _isConnected = false;
        _remoteUsers.clear();
        _remoteUid = 0;
        _isMuted = true; // Reset to muted when leaving
        _statusMessage = 'Disconnected';
      });

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
            _hostUid = hostUid;
            print('👑 Host UID identified: $_hostUid');
          }
        });

        // ✅ Apply selective audio subscription for existing users
        if (!_isHost) {
          for (final remoteUid in _remoteUsers) {
            await _applySelectiveAudioSubscription(remoteUid);
          }
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

    _usernamesFetchTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
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
              final userId = user['userId'];
              final username = user['username'];
              _usernames[userId] = username;
            }

            // ✅ Update host UID if available
            if (hostUid != null && _hostUid == null) {
              _hostUid = hostUid;
              print('👑 Host UID identified from user list: $_hostUid');

              // ✅ Re-apply selective audio subscription if we just learned the host UID
              if (!_isHost) {
                for (final remoteUid in _remoteUsers) {
                  _applySelectiveAudioSubscription(remoteUid);
                }
              }
            }
          });
        }
      }
    } catch (e) {
      print('Error fetching usernames: $e');
    }
  }

  /// ✅ Unmute (hold to talk)
  Future<void> _unmute() async {
    if (!_isConnected) return;

    try {
      await _agoraEngine.muteLocalAudioStream(false);
      setState(() {
        _isMuted = false;
      });
      print('🎤 Unmuted - Speaking');
    } catch (e) {
      print('Error unmuting: $e');
    }
  }

  /// ✅ Mute (release button)
  Future<void> _mute() async {
    if (!_isConnected) return;

    try {
      await _agoraEngine.muteLocalAudioStream(true);
      setState(() {
        _isMuted = true;
      });
      print('🔇 Muted - Listening');
    } catch (e) {
      print('Error muting: $e');
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

  @override
  void dispose() {
    _stopSessionStatusPolling(); // ✅ FIX: Clean up polling timer
    _usernamesFetchTimer?.cancel(); // ✅ Clean up username fetch timer
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

            // Control buttons (Speaker, Bluetooth, Exit Room)
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
                  // ✅ Microphone button (Hold to Talk - auto-joined, no tap to join)
                  GestureDetector(
                    // Hold to talk (push-to-talk)
                    onTapDown: _isConnected ? (details) async {
                      await _unmute(); // Unmute when pressing down
                    } : null,
                    onTapUp: _isConnected ? (details) async {
                      await _mute(); // Mute when releasing
                    } : null,
                    onTapCancel: _isConnected ? () async {
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
                  const SizedBox(height: 32),

                  // ✅ Status text (auto-joining, no manual join needed)
                  Text(
                    _isJoining
                        ? 'CONNECTING...'
                        : _isConnected
                            ? (_isMuted ? 'HOLD TO TALK' : 'SPEAKING - RELEASE TO MUTE')
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

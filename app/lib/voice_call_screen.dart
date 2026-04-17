import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'speaker_tracker.dart';
import 'speaking_event.dart';
import 'app_config.dart';

class VoiceCallScreen extends StatefulWidget {
  const VoiceCallScreen({super.key});

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  late RtcEngine _agoraEngine;
  late SpeakerTracker _speakerTracker;

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
  bool _isMuted = false;

  final bool _logVolumes = true;
  static const int TOKEN_VALID_DURATION = 3300; // Token valid for 1 hour (3600s), refresh at 55 min

  @override
  void initState() {
    super.initState();
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
    _initializeAgora();
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
    } catch (e) {
      print('Error initializing Agora: $e');
      _showErrorSnackBar('Failed to initialize Agora: $e');
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
          setState(() {
            _uid = connection.localUid ?? 0;
            _isConnected = true;
            _statusMessage = 'Connected';
          });
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          print('Remote user $remoteUid joined');
          setState(() {
            _remoteUsers.add(remoteUid);
            _remoteUid = remoteUid;
          });
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

  Future<void> _joinChannel() async {
    if (_isJoining || _isConnected) {
      _showErrorSnackBar('Already joining or connected');
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

      setState(() {
        _isJoining = false;
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
        _isMuted = false;
        _statusMessage = 'Disconnected';
      });

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      print('Error leaving channel: $e');
      _showErrorSnackBar('Error leaving channel: $e');
    }
  }

  Future<void> _toggleMute() async {
    if (!_isConnected) {
      _showErrorSnackBar('Not connected to call');
      return;
    }

    try {
      final newMuteState = !_isMuted;
      await _agoraEngine.muteLocalAudioStream(newMuteState);

      setState(() {
        _isMuted = newMuteState;
      });

      print('🔊 Mute toggled: $_isMuted');
      _showErrorSnackBar(
        _isMuted ? '🔇 Microphone Muted' : '🎤 Microphone Unmuted',
      );
    } catch (e) {
      print('Error toggling mute: $e');
      _showErrorSnackBar('Failed to toggle mute: $e');
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
                  const Text(
                    'Hello, pk',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

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
                  // Large microphone button (Toggle Mute / Join Call)
                  GestureDetector(
                    onTap: () async {
                      // Prevent rapid taps
                      if (_isJoining) {
                        _showErrorSnackBar('⏳ Connecting... please wait');
                        return;
                      }

                      // If connected: toggle mute
                      if (_isConnected) {
                        await _toggleMute();
                      }
                      // If not connected: join channel
                      else {
                        await _joinChannel();
                      }
                    },
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _isMuted
                                ? const Color(0xFF777777).withOpacity(0.6)
                                : _isJoining
                                    ? const Color(0xFFFFCD00).withOpacity(0.6)
                                    : const Color(0xFFFF4757).withOpacity(0.6),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _isMuted
                                ? const Color(0xFF777777).withOpacity(0.4)
                                : _isJoining
                                    ? const Color(0xFFFFCD00).withOpacity(0.4)
                                    : const Color(0xFFFF4757).withOpacity(0.4),
                            width: 3,
                          ),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isMuted
                                ? const Color(0xFF777777)
                                : _isJoining
                                    ? const Color(0xFFFFCD00)
                                    : const Color(0xFFFF4757),
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

                  // Touch to speak text
                  Text(
                    _isJoining
                        ? 'CONNECTING...'
                        : _isConnected
                            ? (_isMuted ? 'TAP TO UNMUTE' : 'TAP TO MUTE')
                            : 'TAP TO JOIN CALL',
                    style: TextStyle(
                      color: _isJoining ? const Color(0xFFFFCD00) : Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            // ✅ NEW: Speaking Status Section
            if (_isConnected && _remoteUsers.isNotEmpty)
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
                                            'User #$uid',
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

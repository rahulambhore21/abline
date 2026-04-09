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
  // Agora engine instance
  late RtcEngine _agoraEngine;

  // Speaker tracking
  late SpeakerTracker _speakerTracker;

  // Channel and user settings
  final String _channelName = 'test_room';
  final String _agoraAppId = '1400d886612b4896986d7db16b0bbc44';
  // Backend base URL (centralized in AppConfig)
  late final String _backendUrl = AppConfig.backendBaseUrl;
  int _uid = 0;
  int _remoteUid = 0;
  String? _agoraToken;

  // UI state
  bool _isConnected = false;
  bool _isJoining = false;
  List<int> _remoteUsers = [];
  String _statusMessage = 'Disconnected';
  List<SpeakingEvent> _speakingEvents = [];

  // Debug: set true if you want continuous UID+volume logs.
  // This can be noisy (prints every ~200ms per active speaker).
  final bool _logVolumes = true;

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
        print('✅ Speaking event completed and sent to backend: $event');
      },
    );
    _initializeAgora();
  }

  /// Initialize Agora RTC Engine
  Future<void> _initializeAgora() async {
    try {
      await _requestMicrophonePermission();
      _agoraEngine = createAgoraRtcEngine();
      await _agoraEngine.initialize(
        RtcEngineContext(appId: _agoraAppId),
      );
      await _agoraEngine.enableAudio();

      // Enable audio volume indication with reportVad
      await _agoraEngine.enableAudioVolumeIndication(
        interval: 200,
        smooth: 3,
        reportVad: true,
      );

      _setupEventHandlers();

      setState(() {
        _statusMessage = 'Ready to join call (click Join)';
      });
    } catch (e) {
      print('Error initializing Agora: $e');
      _showErrorSnackBar('Failed to initialize Agora: $e');
    }
  }

  /// Request microphone permission
  Future<void> _requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _showErrorSnackBar('Microphone permission is required for voice calls');
      throw Exception('Microphone permission denied');
    }
  }

  /// Fetch Agora token from backend
  Future<void> _fetchAgoraToken() async {
    try {
      if (_uid == 0) {
        _uid = Random().nextInt(100000) + 1;
      }

      final url = Uri.parse(
        '$_backendUrl/agora/token?channelName=$_channelName&uid=$_uid',
      );

      print('Fetching token from: $url');

      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Token request timeout - is backend running on $_backendUrl?');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _agoraToken = data['token'];
          _statusMessage = 'Token obtained successfully';
        });
        print('✅ Token fetched: ${_agoraToken?.substring(0, 20)}...');
      } else {
        final error = jsonDecode(response.body)['error'] ?? 'Unknown error';
        throw Exception('Failed to get token: $error (${response.statusCode})');
      }
    } catch (e) {
      print('❌ Error fetching token: $e');
      _showErrorSnackBar('Failed to fetch token: $e');
      setState(() {
        _statusMessage = 'Failed to fetch token';
      });
      rethrow;
    }
  }

  /// Setup event handlers for Agora RTC events
  void _setupEventHandlers() {
    _agoraEngine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          print('Local user ${connection.localUid} joined successfully');
          // Start tracker timers once we are actually in-channel.
          _speakerTracker.start();
          setState(() {
            _uid = connection.localUid ?? 0;
            _isConnected = true;
            _statusMessage = 'Connected to channel';
          });
        },

        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          print('Remote user $remoteUid joined');
          setState(() {
            _remoteUsers.add(remoteUid);
            _remoteUid = remoteUid;
            _statusMessage = 'Remote user joined: $remoteUid';
          });
        },

        onUserOffline: (RtcConnection connection, int remoteUid,
            UserOfflineReasonType reason) {
          print('Remote user $remoteUid left');
          _speakerTracker.removeUser(remoteUid);
          setState(() {
            _remoteUsers.remove(remoteUid);
            if (_remoteUid == remoteUid) {
              _remoteUid = 0;
            }
            _statusMessage = 'Remote user left';
          });
        },

        onConnectionStateChanged: (RtcConnection connection,
            ConnectionStateType state, ConnectionChangedReasonType reason) {
          print('Connection state changed to: $state');
          if (state == ConnectionStateType.connectionStateFailed) {
            _showErrorSnackBar('Connection failed: $reason');
          }
        },

        // Audio volume indication handler - 4 parameters: connection, speakers, totalVolume, publishVolume
        onAudioVolumeIndication:
            (connection, speakers, totalVolume, publishVolume) {
          final now = DateTime.now();

          // Logs show UID + volume values continuously (helps verify detection in real time)
          for (final speaker in speakers) {
            final uid = speaker.uid ?? 0;
            final volume = speaker.volume ?? 0;
            // final vad = speaker.vad ?? 0; // available if you want to log VAD

            if (_logVolumes) {
              print('🔊 volume uid=$uid volume=$volume');
            }

            _speakerTracker.processAudioVolume(
              uid: uid,
              volume: volume,
              at: now,
            );
          }

          // End "stuck speaking" users if SDK stops reporting them once they go silent.
          _speakerTracker.tick(now: now);
        },

        onError: (ErrorCodeType err, String msg) {
          print('Error occurred: $err - $msg');
          _showErrorSnackBar('Error: $msg');
        },
      ),
    );
  }

  /// Join the voice channel
  Future<void> _joinChannel() async {
    if (_isJoining) return;

    setState(() {
      _isJoining = true;
      _statusMessage = 'Fetching token...';
    });

    try {
      await _fetchAgoraToken();

      if (_agoraToken == null) {
        throw Exception('Token is null after fetching');
      }

      print('Joining channel: $_channelName with UID: $_uid');

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

      setState(() {
        _isJoining = false;
      });
    } catch (e) {
      print('Error joining channel: $e');
      _showErrorSnackBar('Failed to join channel: $e');
      setState(() {
        _isJoining = false;
        _statusMessage = 'Failed to join channel';
      });
    }
  }

  /// Leave the voice channel
  Future<void> _leaveChannel() async {
    try {
      setState(() {
        _statusMessage = 'Leaving channel...';
      });

      await _agoraEngine.leaveChannel();
      _speakerTracker.reset(); // also stops internal timers

      setState(() {
        _isConnected = false;
        _remoteUsers.clear();
        _remoteUid = 0;
        _statusMessage = 'Disconnected';
      });
    } catch (e) {
      print('Error leaving channel: $e');
      _showErrorSnackBar('Error leaving channel: $e');
    }
  }

  /// Show error message
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

  /// Leave channel and destroy Agora engine
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
      appBar: AppBar(
        title: const Text('Voice Call'),
        backgroundColor: Colors.blue.shade700,
      ),
      body: Column(
        children: [
          // Status section
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.grey.shade100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Status:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  _statusMessage,
                  style: TextStyle(
                    fontSize: 16,
                    color: _isConnected ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_isConnected)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Your UID: $_uid',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Users with speaking indicators (always show when connected)
          if (_isConnected)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Users in Call:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        _buildUserIndicator(
                          uid: _uid,
                          label: 'You',
                          isLocal: true,
                        ),
                        const SizedBox(height: 12),
                        if (_remoteUsers.isEmpty)
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Waiting for others to join...',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          )
                        else
                          ..._remoteUsers.map((uid) {
                            return Column(
                              children: [
                                _buildUserIndicator(
                                  uid: uid,
                                  label: 'User $uid',
                                  isLocal: false,
                                ),
                                if (uid != _remoteUsers.last)
                                  const SizedBox(height: 12),
                              ],
                            );
                          }).toList(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),

          // Main content
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.phone_in_talk,
                    size: 80,
                    color: _isConnected ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _isConnected ? 'Call in Progress' : 'Click Join to Start Call',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                  if (_remoteUsers.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        '${_remoteUsers.length} user(s) connected',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.green,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Speaking events history
          if (_speakingEvents.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12.0),
              color: Colors.blue.shade50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Speaking Events:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 60,
                    child: ListView.builder(
                      itemCount: _speakingEvents.length,
                      itemBuilder: (context, index) {
                        final event = _speakingEvents[index];
                        final duration = event.endTime.difference(event.startTime).inSeconds;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: Text(
                            '🎤 User ${event.userId}: ${duration}s',
                            style: const TextStyle(fontSize: 11),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isConnected ? _leaveChannel : null,
                    icon: const Icon(Icons.call_end),
                    label: const Text('Leave Call'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: !_isConnected && !_isJoining ? _joinChannel : null,
                    icon: const Icon(Icons.call),
                    label: const Text('Join Call'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build user indicator widget
  Widget _buildUserIndicator({
    required int uid,
    required String label,
    required bool isLocal,
  }) {
    return ValueListenableBuilder<Map<int, UserSpeakingState>>(
      valueListenable: _speakerTracker.speakingStatesNotifier,
      builder: (context, speakingStates, _) {
        final userState = speakingStates[uid];
        final isSpeaking = userState?.isSpeaking ?? false;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: isSpeaking ? Colors.green.shade50 : Colors.grey.shade50,
            border: Border.all(
              color: isSpeaking ? Colors.green : Colors.grey.shade300,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: isSpeaking ? Colors.green : Colors.grey.shade300,
                  shape: BoxShape.circle,
                ),
                child: isSpeaking
                    ? const Icon(Icons.mic, size: 10, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isSpeaking ? Colors.green.shade700 : Colors.grey.shade700,
                      ),
                    ),
                    if (isSpeaking)
                      const Text(
                        '🎤 Speaking...',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

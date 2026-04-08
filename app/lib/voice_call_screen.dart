import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:math';

class VoiceCallScreen extends StatefulWidget {
  const VoiceCallScreen({super.key});

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  // Agora engine instance
  late RtcEngine _agoraEngine;

  // Channel and user settings
  final String _channelName = 'test_room';
  final String _agoraAppId = '1400d886612b4896986d7db16b0bbc44';
  int _uid = 0; // Local user ID (0 = let Agora assign)
  int _remoteUid = 0; // Remote user ID

  // UI state
  bool _isConnected = false;
  bool _isJoining = false;
  List<int> _remoteUsers = []; // List of remote user IDs
  String _statusMessage = 'Disconnected';

  @override
  void initState() {
    super.initState();
    _initializeAgora();
  }

  /// Initialize Agora RTC Engine
  Future<void> _initializeAgora() async {
    try {
      // Request microphone permission
      await _requestMicrophonePermission();

      // Create Agora RTC Engine
      _agoraEngine = createAgoraRtcEngine();

      // Initialize the engine with your App ID
      await _agoraEngine.initialize(
        RtcEngineContext(appId: _agoraAppId),
      );

      // Enable audio module (audio-only, no video)
      await _agoraEngine.enableAudio();

      // Set event handlers to listen for channel events
      _setupEventHandlers();

      setState(() {
        _statusMessage = 'Ready to join call (click Join)';
      });
    } catch (e) {
      print('Error initializing Agora: $e');
      _showErrorSnackBar('Failed to initialize Agora: $e');
    }
  }

  /// Request microphone permission from the user
  Future<void> _requestMicrophonePermission() async {
    final status = await Permission.microphone.request();

    if (!status.isGranted) {
      _showErrorSnackBar('Microphone permission is required for voice calls');
      throw Exception('Microphone permission denied');
    }
  }

  /// Setup event handlers for Agora RTC events
  void _setupEventHandlers() {
    _agoraEngine.registerEventHandler(
      RtcEngineEventHandler(
        // Called when local user joins the channel
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          print('Local user ${connection.localUid} joined successfully');
          setState(() {
            _uid = connection.localUid ?? 0;
            _isConnected = true;
            _statusMessage = 'Connected to channel';
          });
        },

        // Called when a remote user joins the channel
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          print('Remote user $remoteUid joined');
          setState(() {
            _remoteUsers.add(remoteUid);
            _remoteUid = remoteUid;
            _statusMessage = 'Remote user joined: $remoteUid';
          });
        },

        // Called when a remote user leaves the channel
        onUserOffline: (RtcConnection connection, int remoteUid,
            UserOfflineReasonType reason) {
          print('Remote user $remoteUid left');
          setState(() {
            _remoteUsers.remove(remoteUid);
            if (_remoteUid == remoteUid) {
              _remoteUid = 0;
            }
            _statusMessage = 'Remote user left';
          });
        },

        // Called when connection state changes
        onConnectionStateChanged: (RtcConnection connection,
            ConnectionStateType state, ConnectionChangedReasonType reason) {
          print('Connection state changed to: $state');
          if (state == ConnectionStateType.connectionStateFailed) {
            _showErrorSnackBar('Connection failed: $reason');
          }
        },

        // Called when an error occurs
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
      _statusMessage = 'Joining channel...';
    });

    try {
      // Generate a random UID if not already set
      if (_uid == 0) {
        _uid = Random().nextInt(100000) + 1;
      }

      // Join the channel with:
      // - token: null (temporary, for testing without a token server)
      // - channelId: the channel name
      // - uid: local user ID
      // - options: channel configuration
      await _agoraEngine.joinChannel(
        token: '007eJxTYEiOvL+Ta310792kKZ/+/8g8Z8Rp+rsyMsL+7NuyOS3dF+IVGAxNDAxSLCzMzAyNkkwsLM0sLcxSzFOSDM2SDJKSkk1M/i66ltkQyMgwqVqIhZEBAkF8ToaS1OKS+KL8/FwGBgCjjCPK',
        channelId: _channelName,
        uid: _uid,
        options: ChannelMediaOptions(
          autoSubscribeAudio: true, // Auto-subscribe to remote audio
          publishMicrophoneTrack: true, // Publish local microphone
          clientRoleType: ClientRoleType.clientRoleBroadcaster, // Broadcaster role
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

      // Leave the channel
      await _agoraEngine.leaveChannel();

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

  /// Show error message as a snackbar
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
    // Leave channel and destroy engine on widget dispose
    _leaveChannelAndDestroy();
    super.dispose();
  }

  /// Leave channel and destroy Agora engine
  Future<void> _leaveChannelAndDestroy() async {
    try {
      if (_isConnected) {
        await _agoraEngine.leaveChannel();
      }
      // Destroy the Agora engine to release resources
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

          // Remote users section
          if (_remoteUsers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Remote Users:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: _remoteUsers.map((uid) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Text('• User ID: $uid'),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),

          // Main content area
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

          // Action buttons
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                // Leave button
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

                // Join button
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
}

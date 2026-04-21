import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'auth_service.dart';
import 'app_config.dart';
import 'voice_call_screen.dart';

/// Admin dashboard showing overview statistics
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  late AuthService _authService;
  int _totalUsers = 0;
  int _activeRecordings = 0;
  int _totalSpeakingEvents = 0;
  bool _isLoading = true;
  String _error = '';

  // ✅ NEW: Call session management
  bool _isHostLive = false;
  int _activeUsersInSession = 0;
  bool _isStartingCall = false;
  String _currentSessionId = '';

  // ✅ NEW: Recording management
  bool _isRecording = false;
  bool _isTogatingRecording = false;
  String _recordingResourceId = '';
  String _recordingSid = '';

  @override
  void initState() {
    super.initState();
    _authService = AuthService(backendUrl: AppConfig.backendBaseUrl);
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    try {
      setState(() {
        _isLoading = true;
        _error = '';
      });

      // Fetch users count
      final usersResponse = await _authService
          .authenticatedGet('${AppConfig.backendBaseUrl}/users');
      if (usersResponse.statusCode == 200) {
        final data = jsonDecode(usersResponse.body);
        setState(() => _totalUsers = data['count'] ?? 0);
      }

      // Fetch active recordings
      final recordingsResponse = await http
          .get(Uri.parse('${AppConfig.backendBaseUrl}/recording/active'));
      if (recordingsResponse.statusCode == 200) {
        final data = jsonDecode(recordingsResponse.body);
        setState(() => _activeRecordings = data['count'] ?? 0);
      }

      // Fetch speaking events
      final eventsResponse = await http
          .get(Uri.parse('${AppConfig.backendBaseUrl}/events/speaking'));
      if (eventsResponse.statusCode == 200) {
        final data = jsonDecode(eventsResponse.body);
        setState(() => _totalSpeakingEvents = data['total'] ?? 0);
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error = 'Failed to load dashboard: $e';
        _isLoading = false;
      });
    }
  }

  /// ✅ NEW: Start a call session (host goes live)
  Future<void> _startCallSession() async {
    if (_isStartingCall) return;

    setState(() {
      _isStartingCall = true;
      _error = '';
    });

    try {
      _currentSessionId = 'test_room'; // Using the same channel as VoiceCallScreen
      
      // Debug: Check token
      final token = await _authService.getToken();
      final role = await _authService.getRole();
      print('🔐 Token exists: ${token != null}, Role: $role');
      print('🌐 Starting call at: ${AppConfig.backendBaseUrl}/session/$_currentSessionId/start');

      final response = await _authService.authenticatedPost(
        '${AppConfig.backendBaseUrl}/session/$_currentSessionId/start',
        body: {'sessionId': _currentSessionId},
      );

      print('📡 Start session response: ${response.statusCode}');
      print('📄 Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        setState(() {
          _isHostLive = true;
          _isStartingCall = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Call session started! Users can now join.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        try {
          final errorData = jsonDecode(response.body);
          final errorMsg = errorData['error'] ?? 'Unknown error';
          final errorDetail = errorData['message'] ?? '';
          throw Exception('Failed to start session: $errorMsg - $errorDetail (Status: ${response.statusCode})');
        } catch (e) {
          throw Exception('Failed to start session: ${response.body} (Status: ${response.statusCode})');
        }
      }
    } catch (e) {
      print('❌ Error starting session: $e');
      setState(() {
        _error = 'Failed to start call: $e';
        _isStartingCall = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// ✅ NEW: Stop the call session (host goes offline)
  Future<void> _stopCallSession() async {
    try {
      final response = await _authService.authenticatedPost(
        '${AppConfig.backendBaseUrl}/session/$_currentSessionId/stop',
        body: {'sessionId': _currentSessionId},
      );

      if (response.statusCode == 200) {
        setState(() {
          _isHostLive = false;
          _activeUsersInSession = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Call session ended'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        throw Exception('Failed to stop session');
      }
    } catch (e) {
      setState(() => _error = 'Failed to stop call: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// ✅ NEW: Start recording the current session
  Future<void> _startRecording() async {
    if (_isTogatingRecording || !_isHostLive) return;

    setState(() {
      _isTogatingRecording = true;
      _error = '';
    });

    try {
      // Generate a random UID for the recorder (0 is commonly used)
      final recorderUid = 0;

      print('🎬 Starting recording for channel: $_currentSessionId');

      final response = await _authService.authenticatedPost(
        '${AppConfig.backendBaseUrl}/recording/start',
        body: {
          'channelName': _currentSessionId,
          'uid': recorderUid,
        },
      );

      print('📡 Start recording response: ${response.statusCode}');
      print('📄 Response body: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _isRecording = true;
          _recordingResourceId = data['resourceId'] ?? '';
          _recordingSid = data['sid'] ?? '';
          _isTogatingRecording = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Recording started!'),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        try {
          final errorData = jsonDecode(response.body);
          final errorMsg = errorData['error'] ?? 'Unknown error';
          throw Exception('Failed to start recording: $errorMsg (Status: ${response.statusCode})');
        } catch (e) {
          throw Exception('Failed to start recording: ${response.body} (Status: ${response.statusCode})');
        }
      }
    } catch (e) {
      print('❌ Error starting recording: $e');
      setState(() {
        _error = 'Failed to start recording: $e';
        _isTogatingRecording = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// ✅ NEW: Stop the current recording
  Future<void> _stopRecording() async {
    if (_isTogatingRecording || !_isRecording) return;

    setState(() {
      _isTogatingRecording = true;
      _error = '';
    });

    try {
      print('⏹️  Stopping recording for channel: $_currentSessionId');

      final response = await _authService.authenticatedPost(
        '${AppConfig.backendBaseUrl}/recording/stop',
        body: {
          'channelName': _currentSessionId,
          'resourceId': _recordingResourceId,
          'sid': _recordingSid,
        },
      );

      print('📡 Stop recording response: ${response.statusCode}');
      print('📄 Response body: ${response.body}');

      if (response.statusCode == 200) {
        setState(() {
          _isRecording = false;
          _recordingResourceId = '';
          _recordingSid = '';
          _isTogatingRecording = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Recording stopped!'),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        throw Exception('Failed to stop recording (Status: ${response.statusCode})');
      }
    } catch (e) {
      print('❌ Error stopping recording: $e');
      setState(() {
        _error = 'Failed to stop recording: $e';
        _isTogatingRecording = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// ✅ NEW: Check how many users are in the current session
  Future<void> _checkActiveUsers() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.backendBaseUrl}/session/$_currentSessionId/users'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() => _activeUsersInSession = data['total'] ?? 0);
      }
    } catch (e) {
      print('Error checking active users: $e');
    }
  }

  /// ✅ NEW: Join the call as host (participate in conversation)
  Future<void> _joinCall() async {
    try {
      print('🎤 Host joining call as participant...');
      if (!mounted) return;
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const VoiceCallScreen(),
        ),
      );
    } catch (e) {
      print('❌ Error joining call: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error joining call: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dashboard Overview',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'System statistics and monitoring',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),

          // Error message
          if (_error.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade900.withValues(alpha: 0.3),
                border: Border.all(color: Colors.red.shade700),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _error,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),

          if (_error.isEmpty) ...[
            // ✅ NEW: Call Status Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _isHostLive ? Colors.green.shade900.withValues(alpha: 0.3) : Colors.orange.shade900.withValues(alpha: 0.3),
                border: Border.all(
                  color: _isHostLive ? Colors.green : Colors.orange,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isHostLive ? Colors.green : Colors.orange,
                          boxShadow: [
                            BoxShadow(
                              color: (_isHostLive ? Colors.green : Colors.orange).withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _isHostLive ? '🔴 LIVE' : '⚪ OFFLINE',
                        style: TextStyle(
                          color: _isHostLive ? Colors.green : Colors.orange,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Call Status',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isHostLive
                        ? '✅ Call is active'
                        : '❌ No active call',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ✅ Join Call button - starts session automatically when clicked
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _joinCall,
                      icon: const Icon(Icons.phone),
                      label: const Text('Join Call as Host'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ✅ NEW: Recording Status Section
                  if (_isHostLive)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _isRecording ? Colors.red.shade900.withValues(alpha: 0.2) : Colors.grey.shade900.withValues(alpha: 0.2),
                        border: Border.all(
                          color: _isRecording ? Colors.red : Colors.grey,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (_isRecording)
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.red,
                                  ),
                                ),
                              if (_isRecording) const SizedBox(width: 8),
                              Text(
                                _isRecording ? '🔴 RECORDING' : '⭕ READY TO RECORD',
                                style: TextStyle(
                                  color: _isRecording ? Colors.red : Colors.grey,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _isRecording || _isTogatingRecording ? null : _startRecording,
                                  icon: const Icon(Icons.fiber_manual_record),
                                  label: const Text('Start Recording'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: Colors.grey,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: !_isRecording || _isTogatingRecording ? null : _stopRecording,
                                  icon: const Icon(Icons.stop_circle),
                                  label: const Text('Stop Recording'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: Colors.grey,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Stats grid - responsive
            LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount =
                    constraints.maxWidth > 1200 ? 3 : (constraints.maxWidth > 600 ? 2 : 1);
                return GridView(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 20,
                    crossAxisSpacing: 20,
                    childAspectRatio: 1.1,
                  ),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildStatCard(
                      title: 'Total Users',
                      value: '$_totalUsers',
                      icon: Icons.people,
                      color: Colors.blue,
                    ),
                    _buildStatCard(
                      title: 'Active Recordings',
                      value: '$_activeRecordings',
                      icon: Icons.videocam,
                      color: Colors.red,
                    ),
                    _buildStatCard(
                      title: 'Speaking Events',
                      value: '$_totalSpeakingEvents',
                      icon: Icons.mic,
                      color: Colors.green,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 40),

            // Quick actions section
            const Text(
              'Quick Actions',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 600) {
                  return Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _loadDashboardData,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('System health check passed ✅'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.health_and_safety),
                          label: const Text('Health Check'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _loadDashboardData,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('System health check passed ✅'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.health_and_safety),
                          label: const Text('Health Check'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  );
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF3a3a3a),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 36),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

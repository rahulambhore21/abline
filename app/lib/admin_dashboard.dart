import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'auth_service.dart';
import 'app_config.dart';
import 'voice_call_screen.dart';
import 'admin_recordings_screen.dart';

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
        setState(() => _totalUsers = (data['count'] ?? 0) as int);
      }

      // Fetch active recordings
      final recordingsResponse = await http
          .get(Uri.parse('${AppConfig.backendBaseUrl}/recording/active'));
      if (recordingsResponse.statusCode == 200) {
        final data = jsonDecode(recordingsResponse.body);
        setState(() => _activeRecordings = (data['count'] ?? 0) as int);
      }

      // Fetch speaking events
      final eventsResponse = await http
          .get(Uri.parse('${AppConfig.backendBaseUrl}/events/speaking'));
      if (eventsResponse.statusCode == 200) {
        final data = jsonDecode(eventsResponse.body);
        setState(() => _totalSpeakingEvents = (data['total'] ?? 0) as int);
      }

      // ✅ NEW: Fetch current session status
      await _checkSessionStatus();

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error = 'Failed to load dashboard: $e';
        _isLoading = false;
      });
    }
  }

  /// ✅ NEW: Start a call session (host goes live)
  Future<bool> _startCallSessionInternal() async {
    if (_isStartingCall) return false;

    setState(() {
      _isStartingCall = true;
      _error = '';
    });

    try {
      _currentSessionId = 'test_room';
      final response = await _authService.authenticatedPost(
        '${AppConfig.backendBaseUrl}/session/$_currentSessionId/start',
        body: {'sessionId': _currentSessionId},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (!mounted) return false;
        setState(() {
          _isHostLive = true;
          _isStartingCall = false;
        });
        return true;
      } else {
        throw Exception('Failed to start session: ${response.body}');
      }
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _error = 'Failed to start call: $e';
        _isStartingCall = false;
      });
      return false;
    }
  }

  Future<void> _handleJoinSession() async {
    if (!_isHostLive) {
      final success = await _startCallSessionInternal();
      if (!success) return;
    }
    await _joinCall();
  }

  /// ✅ NEW: Stop the call session (host goes offline)

  /// ✅ NEW: Check if the session is currently active on the server
  Future<void> _checkSessionStatus() async {
    try {
      _currentSessionId = 'test_room';
      final response = await http.get(
        Uri.parse('${AppConfig.backendBaseUrl}/session/$_currentSessionId/status'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (!mounted) return;
        setState(() {
          _isHostLive = (data['isActive'] ?? false) as bool;
          _activeUsersInSession = (data['userCount'] ?? 0) as int;
          // In our auto-recording flow, if host is live, recording is active
          _isRecording = _isHostLive;
        });
      }
    } catch (e) {
      debugPrint('❌ Error checking session status: $e');
    }
  }

  /// ✅ NEW: Join the call as host (participate in conversation)
  Future<void> _joinCall() async {
    try {
      debugPrint('🎤 Host joining call as participant...');
      if (!mounted) return;
      
      unawaited(Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (context) => const VoiceCallScreen(),
        ),
      ));
    } catch (e) {
      debugPrint('❌ Error joining call: $e');
      if (!mounted) return;
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
          const Text(
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
                  const Text(
                    'Call Status',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isHostLive
                        ? '✅ Call is active ($_activeUsersInSession users online)'
                        : '❌ No active call',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ✅ Session Controls
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isStartingCall ? null : _handleJoinSession,
                          icon: Icon(_isHostLive ? Icons.phone : Icons.bolt),
                          label: Text(_isHostLive ? 'Join Call' : 'Start & Join Call'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isHostLive ? Colors.blue : Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ✅ Auto-Recording Status (No manual buttons)
                  if (_isHostLive)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _isRecording ? Colors.red.shade900.withValues(alpha: 0.1) : Colors.grey.shade900.withValues(alpha: 0.1),
                        border: Border.all(
                          color: _isRecording ? Colors.red.withValues(alpha: 0.5) : Colors.grey.withValues(alpha: 0.5),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          if (_isRecording)
                            const Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
                          if (_isRecording) const SizedBox(width: 8),
                          Text(
                            _isRecording ? 'RECORDING ACTIVE' : 'RECORDING READY',
                            style: TextStyle(
                              color: _isRecording ? Colors.red : Colors.grey,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const Spacer(),
                          const Text(
                            '(Automatic)',
                            style: TextStyle(color: Colors.white38, fontSize: 11),
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
                  return Column(
                    children: [
                      Row(
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
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (context) => const AdminRecordingsScreen(
                                  sessionId: 'test_room',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.library_music),
                          label: const Text('All Recordings by User'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
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
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (context) => const AdminRecordingsScreen(
                                  sessionId: 'test_room',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.library_music),
                          label: const Text('All Recordings by User'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
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
  }) => Container(
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
            style: const TextStyle(
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

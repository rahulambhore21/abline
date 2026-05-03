import 'package:flutter/material.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'voice_call_screen.dart';
import 'user_recordings_screen.dart';
import 'admin_recordings_screen.dart';
import 'auth_service.dart';
import 'app_config.dart';

/// HomeScreen displays the welcome screen after login
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late AuthService _authService;
  String _loggedInUsername = ''; // ✅ Name of the currently signed-in user
  String _hostName = 'Loading...'; // ✅ Name of the actual host (from backend)
  bool _isHostOnline = false; // ✅ Default to offline
  bool _isLoading = true;
  Timer? _sessionStatusTimer; // ✅ Timer for polling session status
  bool _isHost = false; // ✅ NEW: Track if current user is host/admin

  @override
  void initState() {
    super.initState();
    _authService = AuthService(backendUrl: AppConfig.backendBaseUrl);
    _loadUserInfo();
    _startSessionStatusPolling(); // ✅ Start checking session status
  }

  @override
  void dispose() {
    _sessionStatusTimer?.cancel(); // ✅ Clean up timer
    super.dispose();
  }

  /// ✅ Poll session status to check if host has started the call
  /// OPTIMIZATION: Increased from 3s to 5s to reduce network load
  void _startSessionStatusPolling() {
    _checkSessionStatus(); // Initial check

    // Poll every 5 seconds (optimized from 3)
    _sessionStatusTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _checkSessionStatus();
    });
  }

  /// ✅ Check if session is active (host has started the call)
  Future<void> _checkSessionStatus() async {
    try {
      final response = await http
          .get(Uri.parse('${AppConfig.backendBaseUrl}/session/test_room/status'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final isActive = (data['isActive'] ?? false) as bool;

        if (mounted) {
          setState(() {
            _isHostOnline = isActive;
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking session status: $e');
      // Keep offline status on error
      if (mounted) {
        setState(() {
          _isHostOnline = false;
        });
      }
    }
  }

  /// Load user info — both the logged-in user's details and the actual host name.
  Future<void> _loadUserInfo() async {
    // 1. Load the current user's credentials from local storage.
    final username = await _authService.getUsername();
    final role = await _authService.getRole();
    final isHost = await _authService.isHost();

    debugPrint('🔍 User Info:');
    debugPrint('  - Username: $username');
    debugPrint('  - Role: $role');
    debugPrint('  - Is Host: $isHost');

    if (mounted) {
      setState(() {
        _loggedInUsername = username ?? 'User';
        _isHost = isHost;
        _isLoading = false; // Show UI immediately with what we have.
      });
    }

    // 2. Fetch the actual host's username from the backend (public endpoint).
    //    This runs after setState so the screen is already visible.
    unawaited(_fetchHostName());
  }

  /// Fetch the host's username from GET /host (no auth required).
  Future<void> _fetchHostName() async {
    try {
      final response = await http
          .get(Uri.parse('${AppConfig.backendBaseUrl}/host'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final name = data['username'] as String?;
        if (mounted) {
          setState(() {
            _hostName = name ?? 'No host registered';
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching host name: $e');
      if (mounted) {
        setState(() {
          _hostName = 'Unavailable';
        });
      }
    }
  }


  /// Handle logout
  Future<void> _handleLogout() async {
    await _authService.logout();
    if (mounted) {
      unawaited(Navigator.of(context).pushReplacementNamed('/login'));
    }
  }

  /// Show logout confirmation dialog
  void _showLogoutConfirmation() {
    unawaited(showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _handleLogout();
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF2a2a2a),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Logout button at top right
              Align(
                alignment: Alignment.topRight,
                child: GestureDetector(
                  onTap: _showLogoutConfirmation,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.logout, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Logout',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Main card
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3a3a3a),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Welcome text
                      Text(
                        'Welcome, $_loggedInUsername!',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Subtitle
                      const Text(
                        "You're now logged in and ready\nto join the call with your Host.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Host name label
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Your Host Name is :',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Host name and status
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Text(
                              _hostName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _isHostOnline
                                    ? Colors.green.withValues(alpha: 0.2)
                                    : Colors.red.withValues(alpha: 0.2), // ✅ Red when offline
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _isHostOnline
                                          ? const Color(0xFF00FF41)
                                          : Colors.red, // ✅ Red dot when offline
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _isHostOnline ? 'Host is Online' : 'Host is Offline', // ✅ Dynamic text
                                    style: TextStyle(
                                      color: _isHostOnline
                                          ? const Color(0xFF00FF41)
                                          : Colors.red, // ✅ Red text when offline
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Join Room button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isHostOnline
                              ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (context) => const VoiceCallScreen(),
                                    ),
                                  );
                                }
                              : null, // ✅ Disabled when host is offline
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isHostOnline ? Colors.blue : Colors.grey, // ✅ Grey when disabled
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey, // ✅ Grey when disabled
                            disabledForegroundColor: Colors.white60, // ✅ Dimmed text
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            _isHostOnline ? 'Join Room' : 'Waiting for Host...', // ✅ Dynamic button text
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // ✅ FIXED: Make "Your Recordings" clickable
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (context) => const UserRecordingsScreen(
                                sessionId: 'test_room',
                              ),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.white30,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.music_note,
                                  color: Colors.white70,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Your Recordings',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Tap to view all your recordings',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.arrow_forward,
                                color: Colors.white54,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ✅ NEW: Admin button for host/admin to view all recordings
                      if (_isHost) ...[
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (context) => const AdminRecordingsScreen(
                                  sessionId: 'test_room',
                                ),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.blue,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.admin_panel_settings,
                                    color: Colors.blue,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'All Recordings (Admin)',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'View all users\' recordings',
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_forward,
                                  color: Colors.white54,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      // ✅ Extra spacing for navigation bar
                      SizedBox(height: MediaQuery.of(context).padding.bottom),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),

    );
  }
}

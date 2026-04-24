import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'app_config.dart';
import 'auth_service.dart';
import 'admin_recordings_screen.dart';

/// ✅ NEW: Admin screen to view all past recorded sessions
class AdminSessionsScreen extends StatefulWidget {
  const AdminSessionsScreen({super.key});

  @override
  State<AdminSessionsScreen> createState() => _AdminSessionsScreenState();
}

class _AdminSessionsScreenState extends State<AdminSessionsScreen> {
  late AuthService _authService;
  late final String _backendUrl = AppConfig.backendBaseUrl;

  List<dynamic> _sessions = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _authService = AuthService(backendUrl: _backendUrl);
    _loadSessions();
  }

  /// Load all unique sessions with recordings
  Future<void> _loadSessions() async {
    try {
      setState(() {
        _isLoading = true;
        _error = '';
      });

      final token = await _authService.getToken();
      if (token == null) {
        setState(() {
          _error = 'Not authenticated - Please login again';
          _isLoading = false;
        });
        return;
      }

      final url = '$_backendUrl/recordings/sessions';
      print('🌐 Fetching all recorded sessions from: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      print('📡 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final sessions = data['sessions'] as List<dynamic>;

        setState(() {
          _sessions = sessions;
          _isLoading = false;
        });

        print('✅ Loaded ${sessions.length} recorded sessions');
      } else if (response.statusCode == 401) {
        setState(() {
          _error = 'Unauthorized - Admin access required';
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load sessions: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading sessions: $e');
      setState(() {
        _error = 'Error loading sessions: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2a2a2a),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a1a1a),
        title: const Text('Recorded Sessions'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSessions,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _error.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _error,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loadSessions,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _sessions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.history,
                            size: 64,
                            color: Colors.white.withOpacity(0.3),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No recorded sessions found',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _sessions.length,
                      itemBuilder: (context, index) {
                        final session = _sessions[index];
                        final sessionId = session['sessionId'] ?? 'Unknown';
                        final recordingCount = session['recordingCount'] ?? 0;
                        final userCount = session['userCount'] ?? 0;
                        final latestDate = session['latestRecordingDate'] != null
                            ? DateTime.parse(session['latestRecordingDate'])
                            : null;

                        return Card(
                          color: const Color(0xFF3a3a3a),
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: Colors.white10),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.forum, color: Colors.blue),
                            ),
                            title: Text(
                              sessionId,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.mic, size: 14, color: Colors.white.withOpacity(0.5)),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$recordingCount recordings',
                                      style: TextStyle(color: Colors.white.withOpacity(0.6)),
                                    ),
                                    const SizedBox(width: 12),
                                    Icon(Icons.people, size: 14, color: Colors.white.withOpacity(0.5)),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$userCount users',
                                      style: TextStyle(color: Colors.white.withOpacity(0.6)),
                                    ),
                                  ],
                                ),
                                if (latestDate != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Latest: ${_formatDateTime(latestDate)}',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.4),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AdminRecordingsScreen(
                                    sessionId: sessionId,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
    );
  }

  String _formatDateTime(DateTime dt) {
    // Basic formatting: 2024-04-24 10:00 AM
    // Using IST (UTC+5:30) as per previous context
    final istTime = dt.add(const Duration(hours: 5, minutes: 30));
    
    final day = istTime.day.toString().padLeft(2, '0');
    final month = istTime.month.toString().padLeft(2, '0');
    final year = istTime.year;
    
    final hour = istTime.hour;
    final minute = istTime.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    
    return '$day/$month/$year $hour12:$minute $ampm';
  }
}

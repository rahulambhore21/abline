import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'app_config.dart';
import 'auth_service.dart';
import 'recording.dart';
import 'recording_list_widget.dart';

/// ✅ NEW: Screen for users to view their personal recordings
class UserRecordingsScreen extends StatefulWidget {
  final String sessionId;
  final int? userId;  // ✅ NEW: Accept Agora UID as parameter

  const UserRecordingsScreen({
    super.key,
    required this.sessionId,
    this.userId,  // ✅ NEW: Optional Agora UID
  });

  @override
  State<UserRecordingsScreen> createState() => _UserRecordingsScreenState();
}

class _UserRecordingsScreenState extends State<UserRecordingsScreen> {
  late AuthService _authService;
  late final String _backendUrl = AppConfig.backendBaseUrl;

  List<Recording> _recordings = [];
  bool _isLoading = true;
  String _error = '';
  int _userId = 0;

  @override
  void initState() {
    super.initState();
    _authService = AuthService(backendUrl: _backendUrl);
    _loadRecordings();
  }

  /// ✅ Load user's recordings from backend
  Future<void> _loadRecordings() async {
    try {
      setState(() {
        _isLoading = true;
        _error = '';
      });

      // ✅ FIXED: Use session-based endpoint instead of user-based
      // This works because recordings are tied to sessions, not MongoDB user IDs
      final url = '$_backendUrl/recordings?sessionId=${widget.sessionId}';
      print('🌐 Fetching recordings from: $url');

      // Fetch recordings
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      print('📡 Response status: ${response.statusCode}');
      print('📄 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final recordings = (data['recordings'] as List?)
            ?.map((r) => Recording.fromJson(r as Map<String, dynamic>))
            .toList() ?? [];

        setState(() {
          _recordings = recordings;
          _isLoading = false;
        });

        print('✅ Loaded ${recordings.length} recordings');
      } else {
        setState(() {
          _error = 'Failed to load recordings: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading recordings: $e');
      setState(() {
        _error = 'Error loading recordings: $e';
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
        title: const Text('My Recordings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRecordings,
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
                        onPressed: _loadRecordings,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _recordings.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.mic_none,
                            size: 64,
                            color: Colors.white.withOpacity(0.3),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No recordings yet',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Hold the microphone button to record',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_recordings.length} Recording${_recordings.length != 1 ? 's' : ''}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // Use the existing RecordingListWidget for playback
                                RecordingListWidget(
                                  recordings: _recordings,
                                  backendUrl: _backendUrl,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'app_config.dart';
import 'auth_service.dart';
import 'recording.dart';
import 'recording_list_widget.dart';

/// ✅ NEW: Admin screen to view all users' recordings for a session
class AdminRecordingsScreen extends StatefulWidget {
  final String sessionId;

  const AdminRecordingsScreen({
    super.key,
    required this.sessionId,
  });

  @override
  State<AdminRecordingsScreen> createState() => _AdminRecordingsScreenState();
}

class _AdminRecordingsScreenState extends State<AdminRecordingsScreen> {
  late AuthService _authService;
  late final String _backendUrl = AppConfig.backendBaseUrl;

  Map<String, List<Recording>> _recordingsByUser = {};
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _authService = AuthService(backendUrl: _backendUrl);
    _loadAllRecordings();
  }

  /// Load all recordings for the session (admin view)
  Future<void> _loadAllRecordings() async {
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

      final url =
          '$_backendUrl/recordings/session/${widget.sessionId}?verify=true';
      print('🌐 Fetching all session recordings from: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      print('📡 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final byUser = (data['byUser'] as Map<String, dynamic>?) ?? {};

        // Convert to Map<String, List<Recording>>
        final recordingsByUser = <String, List<Recording>>{};
        byUser.forEach((userId, recordingsList) {
          recordingsByUser[userId] = (recordingsList as List<dynamic>)
              .map((r) => Recording.fromJson(r as Map<String, dynamic>))
              .toList();
        });

        setState(() {
          _recordingsByUser = recordingsByUser;
          _isLoading = false;
        });

        print('✅ Loaded recordings for ${recordingsByUser.length} users');
      } else if (response.statusCode == 401) {
        setState(() {
          _error = 'Unauthorized - Admin access required';
          _isLoading = false;
        });
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
        title: const Text('All Recordings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllRecordings,
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
                        onPressed: _loadAllRecordings,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _recordingsByUser.isEmpty
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
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Members: ${_recordingsByUser.length}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ..._recordingsByUser.entries.map((entry) {
                              final username = entry.key;
                              final recordings = entry.value;
                              final totalDuration = recordings.fold<int>(
                                  0, (sum, rec) => sum + (rec.durationMs ?? 0));

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3a3a3a),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: Theme(
                                  data: Theme.of(context).copyWith(
                                    dividerColor: Colors.transparent,
                                  ),
                                  child: ExpansionTile(
                                    leading: const CircleAvatar(
                                      backgroundColor: Color(0xFF1a73e8),
                                      child: Icon(Icons.person, color: Colors.white),
                                    ),
                                    title: Text(
                                      username, // ✅ Display username
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${recordings.length} clip${recordings.length != 1 ? 's' : ''} • ${_formatDuration(totalDuration)}',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.6),
                                        fontSize: 12,
                                      ),
                                    ),
                                    iconColor: Colors.white70,
                                    collapsedIconColor: Colors.white30,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 8),
                                        child: RecordingListWidget(
                                          recordings: recordings,
                                          backendUrl: _backendUrl,
                                          onVerificationComplete:
                                              (verifiedList) {
                                            if (verifiedList.length !=
                                                recordings.length) {
                                              setState(() {
                                                _recordingsByUser[username] =
                                                    verifiedList;
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ),
    );
  }

  /// Format duration as mm:ss
  String _formatDuration(int durationMs) {
    final duration = Duration(milliseconds: durationMs);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes);
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}

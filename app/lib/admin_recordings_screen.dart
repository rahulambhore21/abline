import 'package:flutter/material.dart';
import 'dart:convert';
import 'app_config.dart';
import 'auth_service.dart';
import 'recording.dart';
import 'admin_user_recordings_screen.dart'; // ✅ NEW

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
  Map<String, List<Recording>> _filteredRecordingsByUser = {};
  bool _isLoading = true;
  String _error = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _authService = AuthService(backendUrl: _backendUrl);
    _loadAllRecordings();
    _searchController.addListener(_filterRecordings);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterRecordings() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredRecordingsByUser = _recordingsByUser;
      } else {
        _filteredRecordingsByUser = Map.fromEntries(
          _recordingsByUser.entries.where(
            (entry) => entry.key.toLowerCase().contains(query),
          ),
        );
      }
    });
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
      debugPrint('🌐 Fetching all session recordings from: $url');

      final response = await _authService.authenticatedGet(
        url,
      ).timeout(const Duration(seconds: 10));

      debugPrint('📡 Response status: ${response.statusCode}');

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
          _filteredRecordingsByUser = recordingsByUser;
          _isLoading = false;
        });

        debugPrint('✅ Loaded recordings for ${recordingsByUser.length} users');
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
      debugPrint('❌ Error loading recordings: $e');
      setState(() {
        _error = 'Error loading recordings: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
                        color: Colors.red.withValues(alpha: 0.5),
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
                            color: Colors.white.withValues(alpha: 0.3),
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
                            // ✅ Search Bar
                            TextField(
                              controller: _searchController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Search user name...',
                                hintStyle: const TextStyle(color: Colors.white30),
                                prefixIcon: const Icon(Icons.search, color: Colors.white30),
                                filled: true,
                                fillColor: const Color(0xFF3a3a3a),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Total Members: ${_filteredRecordingsByUser.length}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ..._filteredRecordingsByUser.entries.map((entry) {
                              final username = entry.key;
                              final recordings = entry.value;
                              final totalDuration = recordings.fold<int>(
                                  0, (sum, rec) => sum + (rec.durationMs ?? 0));

                              return InkWell(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (context) =>
                                        AdminUserRecordingsScreen(
                                      username: username,
                                      recordings: recordings,
                                      backendUrl: _backendUrl,
                                      onVerificationComplete: (verifiedList) {
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
                                ),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF3a3a3a),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: Row(
                                    children: [
                                      const CircleAvatar(
                                        backgroundColor: Color(0xFF1a73e8),
                                        child: Icon(Icons.person,
                                            color: Colors.white),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              username,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 18,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${recordings.length} clip${recordings.length != 1 ? 's' : ''} • ${_formatDuration(totalDuration)}',
                                              style: TextStyle(
                                                color: Colors.white
                                                    .withValues(alpha: 0.6),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right,
                                          color: Colors.white30),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
    );

  /// Format duration as mm:ss
  String _formatDuration(int durationMs) {
    final duration = Duration(milliseconds: durationMs);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes);
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}

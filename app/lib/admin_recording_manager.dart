import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'auth_service.dart';
import 'app_config.dart';
import 'recording.dart';
import 'recording_list_widget.dart';

/// Admin recording manager for controlling recordings
class AdminRecordingManager extends StatefulWidget {
  const AdminRecordingManager({super.key});

  @override
  State<AdminRecordingManager> createState() => _AdminRecordingManagerState();
}

class _AdminRecordingManagerState extends State<AdminRecordingManager> {
  late AuthService _authService;
  List<Map<String, dynamic>> _activeRecordings = [];
  Map<String, List<Recording>> _recordingsByUser = {}; // ✅ FIXED: Use String key for userId
  bool _isLoading = true;
  String _error = '';

  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _authService = AuthService(backendUrl: AppConfig.backendBaseUrl);
    _loadRecordingData(refresh: true);
  }

  Future<void> _loadRecordingData({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _currentPage = 1;
        _hasMore = true;
        _recordingsByUser = {};
        _isLoading = true;
        _error = '';
      });
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      if (refresh) {
        final activeResponse = await http
            .get(Uri.parse('${AppConfig.backendBaseUrl}/recording/active'));
        if (activeResponse.statusCode == 200) {
          final data = jsonDecode(activeResponse.body);
          setState(() {
            _activeRecordings = List<Map<String, dynamic>>.from((data['recordings'] as Iterable?) ?? []);
          });
        }
      }

      // ✅ NEW: Load recordings with pagination
      try {
        final userRecordingsResponse = await http.get(
          Uri.parse('${AppConfig.backendBaseUrl}/recordings/session/test_room?page=$_currentPage&limit=50'),
          headers: {
            'Authorization': 'Bearer ${await _authService.getToken()}',
          },
        );

        if (userRecordingsResponse.statusCode == 200) {
          final data = jsonDecode(userRecordingsResponse.body);
          final totalPages = (data['totalPages'] ?? 1) as int;
          
          final byUserRaw = (data['byUser'] as Map?)?.map(
            (userId, recordings) => MapEntry(
              userId.toString(),
              (recordings as List)
                  .map((r) => Recording.fromJson(r as Map<String, dynamic>))
                  .toList(),
            ),
          ) ?? {};

          setState(() {
            // Merge into existing _recordingsByUser
            byUserRaw.forEach((userId, newRecs) {
              if (_recordingsByUser.containsKey(userId)) {
                _recordingsByUser[userId]!.addAll(newRecs);
              } else {
                _recordingsByUser[userId] = newRecs;
              }
            });
            
            _hasMore = _currentPage < totalPages;
            if (_hasMore) _currentPage++;
            _isLoading = false;
            _isLoadingMore = false;
          });
        }
      } catch (e) {
        debugPrint('❌ Error loading user recordings: $e');
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error loading recording data: $e';
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }


  // _showSnackBar was unreferenced

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recording Management',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Control and monitor recordings',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // ✅ FIXED: Wrap buttons with Flexible constraint
              Flexible(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    // ✅ REMOVED: Manual "Start Recording" button (now automatic)
                    // Recording starts automatically when host joins
                    ElevatedButton.icon(
                      onPressed: _loadRecordingData,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          if (_error.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(14),
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
            const SizedBox(height: 20),

            // ✅ NEW: Automatic Recording Status
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF00FF41).withValues(alpha: 0.15),
                border: Border.all(color: const Color(0xFF00FF41), width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    color: Color(0xFF00FF41),
                    size: 24,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '✅ Automatic Recording Active',
                          style: TextStyle(
                            color: Color(0xFF00FF41),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Recording starts automatically when you begin a session and stops when the session ends',
                          style: TextStyle(
                            color: Color(0xFF00FF41),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              'Active Recordings',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_activeRecordings.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF3a3a3a),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: const Center(
                  child: Text(
                    'No active recordings',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              )
            else
              Column(
                children: _activeRecordings.map((recording) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3a3a3a),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade400),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.videocam,
                            color: Colors.red,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Channel: ${recording['channelName'] ?? 'N/A'}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'SID: ${recording['sid']?.toString().substring(0, 20) ?? 'N/A'}...',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '✅ Auto-stopping when session ends',
                                style: TextStyle(
                                  color: Color(0xFF00FF41),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
              ),

            // ✅ NEW: All Recordings by User Section
            const SizedBox(height: 40),
            const Text(
              'All Recordings by User',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            if (_recordingsByUser.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF3a3a3a),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: const Center(
                  child: Text(
                    'No user recordings yet',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              )
            else
              Column(
                children: _recordingsByUser.entries.map((entry) {
                  final userId = entry.key;
                  final recordings = entry.value;
                  // Show shortened userId for display (first 8 chars of ObjectId)
                  final shortUserId = userId.length > 8 ? userId.substring(0, 8) : userId;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3a3a3a),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00FF41).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    shortUserId,
                                    style: const TextStyle(
                                      color: Color(0xFF00FF41),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                      Text(
                                        'User: ${recordings.isNotEmpty ? recordings.first.username : shortUserId}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${recordings.length} recording${recordings.length != 1 ? 's' : ''}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(16),
                          child: RecordingListWidget(
                            recordings: recordings,
                            backendUrl: AppConfig.backendBaseUrl,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),

            if (_hasMore)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: ElevatedButton.icon(
                    onPressed: _isLoadingMore ? null : () => _loadRecordingData(),
                    icon: _isLoadingMore 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.arrow_downward),
                    label: Text(_isLoadingMore ? 'Loading...' : 'Load More Recordings'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[800],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    ),
                  ),
                ),
              ),
            
            if (!_hasMore && _recordingsByUser.isNotEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    'No more recordings available',
                    style: TextStyle(color: Colors.white30, fontSize: 13),
                  ),
                ),
              ),
          ],
        ],
      ),
    );

}

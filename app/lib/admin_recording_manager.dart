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
  List<Map<String, dynamic>> _speakingEvents = [];
  Map<int, List<Recording>> _recordingsByUser = {}; // ✅ NEW: Recordings grouped by user
  List<Recording> _allSessionRecordings = []; // ✅ NEW: All recordings in session
  bool _isLoading = true;
  String _error = '';

  final _channelNameController = TextEditingController();
  final _uidController = TextEditingController();
  bool _isStarting = false;

  @override
  void initState() {
    super.initState();
    _authService = AuthService(backendUrl: AppConfig.backendBaseUrl);
    _loadRecordingData();
  }

  @override
  void dispose() {
    _channelNameController.dispose();
    _uidController.dispose();
    super.dispose();
  }

  Future<void> _loadRecordingData() async {
    try {
      setState(() {
        _isLoading = true;
        _error = '';
      });

      final recordingsResponse = await http
          .get(Uri.parse('${AppConfig.backendBaseUrl}/recording/active'));
      if (recordingsResponse.statusCode == 200) {
        final data = jsonDecode(recordingsResponse.body);
        setState(() {
          _activeRecordings = List<Map<String, dynamic>>.from(data['recordings'] ?? []);
        });
      }

      final eventsResponse = await http
          .get(Uri.parse('${AppConfig.backendBaseUrl}/events/speaking'));
      if (eventsResponse.statusCode == 200) {
        final data = jsonDecode(eventsResponse.body);
        setState(() {
          _speakingEvents = List<Map<String, dynamic>>.from(data['events'] ?? []);
        });
      }

      // ✅ NEW: Load all recordings by user for session
      try {
        final userRecordingsResponse = await http.get(
          Uri.parse('${AppConfig.backendBaseUrl}/recordings/session/test_room'),
          headers: {
            'Authorization': 'Bearer ${await _authService.getToken()}',
          },
        );

        if (userRecordingsResponse.statusCode == 200) {
          final data = jsonDecode(userRecordingsResponse.body);
          final recordingsList = (data['recordings'] as List?)
              ?.map((r) => Recording.fromJson(r as Map<String, dynamic>))
              .toList() ?? [];

          final byUser = (data['byUser'] as Map?)?.map(
            (userId, recordings) => MapEntry(
              int.parse(userId.toString()),
              (recordings as List)
                  .map((r) => Recording.fromJson(r as Map<String, dynamic>))
                  .toList(),
            ),
          ) ?? {};

          setState(() {
            _allSessionRecordings = recordingsList;
            _recordingsByUser = byUser;
          });

          print('✅ Loaded ${recordingsList.length} session recordings');
        }
      } catch (e) {
        print('Note: User recordings not available: $e');
        // Don't treat this as a fatal error
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error = 'Error loading recording data: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _startRecording() async {
    if (_channelNameController.text.isEmpty || _uidController.text.isEmpty) {
      _showSnackBar('Please fill in all fields', isError: true);
      return;
    }

    setState(() => _isStarting = true);

    try {
      final response = await _authService.authenticatedPost(
        '${AppConfig.backendBaseUrl}/recording/start',
        body: {
          'channelName': _channelNameController.text,
          'uid': int.parse(_uidController.text),
        },
      );

      if (response.statusCode == 201) {
        _showSnackBar('Recording started successfully!');
        _channelNameController.clear();
        _uidController.clear();
        if (mounted) Navigator.pop(context);
        await _loadRecordingData();
      } else {
        final error = jsonDecode(response.body);
        _showSnackBar(error['error'] ?? 'Failed to start recording', isError: true);
      }
    } catch (e) {
      _showSnackBar('Error: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isStarting = false);
      }
    }
  }

  Future<void> _stopRecording(String channelName) async {
    try {
      final response = await _authService.authenticatedPost(
        '${AppConfig.backendBaseUrl}/recording/stop',
        body: {
          'channelName': channelName,
        },
      );

      if (response.statusCode == 200) {
        _showSnackBar('Recording stopped successfully!');
        await _loadRecordingData();
      } else {
        final error = jsonDecode(response.body);
        _showSnackBar(error['error'] ?? 'Failed to stop recording', isError: true);
      }
    } catch (e) {
      _showSnackBar('Error: $e', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  void _showStartRecordingDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start Recording'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _channelNameController,
                decoration: InputDecoration(
                  labelText: 'Channel Name',
                  hintText: 'e.g., demo-channel',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.videocam),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _uidController,
                decoration: InputDecoration(
                  labelText: 'Recorder UID',
                  hintText: 'e.g., 0',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.numbers),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  border: Border.all(color: Colors.blue.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Note: Make sure participants are in the channel before starting the recording.',
                  style: TextStyle(
                    color: Colors.blue.shade900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _channelNameController.clear();
              _uidController.clear();
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _isStarting ? null : _startRecording,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
            ),
            child: _isStarting
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Start Recording'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Recording Management',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Control and monitor recordings',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              Column(
                children: [
                  ElevatedButton.icon(
                    onPressed: _showStartRecordingDialog,
                    icon: const Icon(Icons.play_circle),
                    label: const Text('Start Recording'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
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
                child: Center(
                  child: Text(
                    'No active recordings',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              )
            else
              Column(
                children: _activeRecordings.map((recording) {
                  return Container(
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
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () =>
                              _stopRecording(recording['channelName'] ?? ''),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          child: const Text('Stop'),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),

            const SizedBox(height: 40),

            const Text(
              'Recent Speaking Events',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            if (_speakingEvents.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF3a3a3a),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: Center(
                  child: Text(
                    'No speaking events',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF3a3a3a),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10),
                ),
                child: ListView.builder(
                  itemCount: _speakingEvents.length,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemBuilder: (context, index) {
                    final event = _speakingEvents[index];
                    final duration = event['duration'] ?? 0;
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.white10,
                            width: index < _speakingEvents.length - 1 ? 1 : 0,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                'U${event['userId']}',
                                style: const TextStyle(
                                  color: Colors.green,
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
                                  'User ${event['userId']} - Session ${event['sessionId']}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Duration: ${duration}s',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
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
                child: Center(
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
                                  color: const Color(0xFF00FF41).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    'U$userId',
                                    style: const TextStyle(
                                      color: Color(0xFF00FF41),
                                      fontSize: 12,
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
                                      'User #$userId',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${recordings.length} recording${recordings.length != 1 ? 's' : ''}',
                                      style: TextStyle(
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
          ],
        ],
      ),
    );
  }
}

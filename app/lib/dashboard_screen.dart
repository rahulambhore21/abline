import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'user.dart';
import 'speaking_event.dart';
import 'recording.dart';
import 'user_list_widget.dart';
import 'timeline_widget.dart';
import 'recording_list_widget.dart';
import 'auth_service.dart';

class DashboardScreen extends StatefulWidget {
  final String sessionId;
  final String backendUrl;
  final int currentUserId;
  final String currentUsername;
  final String? jwtToken; // JWT token for authenticated requests

  const DashboardScreen({
    super.key,
    required this.sessionId,
    required this.backendUrl,
    required this.currentUserId,
    required this.currentUsername,
    this.jwtToken,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;
  bool _isRecording = false;
  String _errorMessage = '';

  List<User> _users = [];
  List<SpeakingEvent> _speakingEvents = [];
  List<Recording> _recordings = [];

  @override
  void initState() {
    super.initState();
    _registerCurrentUser();
    _startDataPolling();
  }

  /// Register current user in the session
  Future<void> _registerCurrentUser() async {
    try {
      final url = Uri.parse('${widget.backendUrl}/session/${widget.sessionId}/users/add');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': widget.currentUserId,
          'username': widget.currentUsername,
        }),
      );

      if (response.statusCode != 200) {
        print('Failed to register user: ${response.body}');
      }
    } catch (e) {
      print('Error registering user: $e');
    }
  }

  /// Fetch users, events, and recordings from backend
  Future<void> _fetchData() async {
    try {
      final usersUrl = Uri.parse('${widget.backendUrl}/session/${widget.sessionId}/users');
      final eventsUrl = Uri.parse('${widget.backendUrl}/events/speaking?sessionId=${widget.sessionId}');
      final recordingsUrl = Uri.parse('${widget.backendUrl}/recordings?sessionId=${widget.sessionId}');

      // Build headers with JWT if available
      final headers = {'Content-Type': 'application/json'};
      if (widget.jwtToken != null && widget.jwtToken!.isNotEmpty) {
        headers['Authorization'] = 'Bearer ${widget.jwtToken}';
      }

      // Make concurrent requests
      final usersResponse = await http.get(usersUrl, headers: headers);
      final eventsResponse = await http.get(eventsUrl, headers: headers);
      final recordingsResponse = await http.get(recordingsUrl, headers: headers);

      if (mounted) {
        if (usersResponse.statusCode == 200) {
          final usersData = jsonDecode(usersResponse.body);
          final users = (usersData['users'] as List)
              .map((u) => User.fromJson(u as Map<String, dynamic>))
              .toList();
          setState(() {
            _users = users;
          });
        }

        if (eventsResponse.statusCode == 200) {
          final eventsData = jsonDecode(eventsResponse.body);
          final events = (eventsData['events'] as List)
              .map((e) => SpeakingEvent.fromJson(e as Map<String, dynamic>))
              .toList();
          setState(() {
            _speakingEvents = events;
          });
        }

        if (recordingsResponse.statusCode == 200) {
          final recordingsData = jsonDecode(recordingsResponse.body);
          final recordings = (recordingsData['recordings'] as List)
              .map((r) => Recording.fromJson(r as Map<String, dynamic>))
              .toList();
          setState(() {
            _recordings = recordings;
            _isLoading = false;
            _errorMessage = '';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error fetching data: $e';
          _isLoading = false;
        });
      }
      print('Error fetching dashboard data: $e');
    }
  }

  /// Poll data every 2 seconds to keep dashboard updated
  void _startDataPolling() {
    _fetchData();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _startDataPolling();
      }
    });
  }

  /// Toggle recording state (requires JWT for authentication)
  Future<void> _toggleRecording() async {
    try {
      final endpoint = _isRecording ? 'recording/stop' : 'recording/start';
      final url = Uri.parse('${widget.backendUrl}/$endpoint');

      // Build headers with JWT
      final headers = {'Content-Type': 'application/json'};
      if (widget.jwtToken != null && widget.jwtToken!.isNotEmpty) {
        headers['Authorization'] = 'Bearer ${widget.jwtToken}';
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Not authenticated. Please login.')),
        );
        return;
      }

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({
          'channelName': widget.sessionId,
          'uid': widget.currentUserId,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        setState(() {
          _isRecording = !_isRecording;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isRecording ? 'Recording started' : 'Recording stopped')),
        );
      } else if (response.statusCode == 403) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Host privileges required')),
        );
      } else if (response.statusCode == 401) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Authentication expired. Please login again.')),
        );
        Navigator.of(context).pushReplacementNamed('/login');
      } else {
        // Show backend error (usually includes Agora credential/config info).
        String message = 'Failed to toggle recording (HTTP ${response.statusCode})';
        try {
          final body = jsonDecode(response.body);
          if (body is Map && body['error'] != null) {
            message = body['error'].toString();
          }
        } catch (_) {
          // ignore JSON parse errors
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      print('Error toggling recording: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Host Dashboard'),
        backgroundColor: Colors.blue,
        elevation: 2,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Error message display
                  if (_errorMessage.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        border: Border.all(color: Colors.red),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _errorMessage,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),

                  // Session header with recording controls
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.grey.shade100,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Session: ${widget.sessionId}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: _toggleRecording,
                              icon: Icon(_isRecording ? Icons.stop : Icons.fiber_manual_record),
                              label: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isRecording ? Colors.red : Colors.green,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_isRecording)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'REC',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Users section
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Users in Session',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        UserListWidget(users: _users),
                      ],
                    ),
                  ),

                  const Divider(),

                  // Timeline section
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Speaking Timeline',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_speakingEvents.isEmpty)
                          const Text(
                            'No speaking events yet',
                            style: TextStyle(color: Colors.grey),
                          )
                        else
                          TimelineWidget(
                            events: _speakingEvents,
                            users: _users,
                          ),
                      ],
                    ),
                  ),

                  const Divider(),

                  // Recordings section
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Recordings',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_recordings.isEmpty)
                          const Text(
                            'No recordings yet',
                            style: TextStyle(color: Colors.grey),
                          )
                        else
                          RecordingListWidget(
                            recordings: _recordings,
                            backendUrl: widget.backendUrl,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}

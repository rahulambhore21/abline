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
  final ScrollController _scrollController = ScrollController();

  List<Recording> _recordings = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  bool _hasMore = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _authService = AuthService(backendUrl: _backendUrl);
    _loadRecordings(refresh: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && !_isLoadingMore && _hasMore) {
        _loadRecordings();
      }
    }
  }

  /// ✅ Load user's recordings from backend
  Future<void> _loadRecordings({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _currentPage = 1;
        _hasMore = true;
        _recordings = [];
        _isLoading = true;
        _error = '';
      });
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final url = '$_backendUrl/recordings?sessionId=${widget.sessionId}&userId=${widget.userId}&verify=true&page=$_currentPage&limit=20';
      debugPrint('🌐 Fetching recordings from: $url');

      final token = await _authService.getToken();
      
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              if (token != null) 'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newRecordings = (data['recordings'] as List?)
            ?.map((r) => Recording.fromJson(r as Map<String, dynamic>))
            .toList() ?? [];

        final totalPages = (data['totalPages'] ?? 1) as int;
        
        if (mounted) {
          setState(() {
            _recordings.addAll(newRecordings);
            _isLoading = false;
            _isLoadingMore = false;
            _hasMore = _currentPage < totalPages;
            if (_hasMore) _currentPage++;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Failed to load recordings: ${response.statusCode}';
            _isLoading = false;
            _isLoadingMore = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading recordings: $e');
      if (mounted) {
        setState(() {
          _error = 'Error loading recordings: $e';
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
            onPressed: () => _loadRecordings(refresh: true),
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
                        onPressed: () => _loadRecordings(refresh: true),
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
                  : ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          '${_recordings.length} Recording${_recordings.length != 1 ? 's' : ''}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 16),
                        RecordingListWidget(
                          recordings: _recordings,
                          backendUrl: _backendUrl,
                        ),
                        if (_isLoadingMore)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        if (!_hasMore && _recordings.isNotEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: Text(
                                'No more recordings to load',
                                style: TextStyle(color: Colors.white30, fontSize: 12),
                              ),
                            ),
                          ),
                      ],
                    ),
    );
}


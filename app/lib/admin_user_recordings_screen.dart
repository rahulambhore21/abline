import 'package:flutter/material.dart';
import 'recording.dart';
import 'recording_list_widget.dart';

/// ✅ NEW: Screen for Admin to view a specific user's recordings
class AdminUserRecordingsScreen extends StatelessWidget {
  final String username;
  final List<Recording> recordings;
  final String backendUrl;
  final Function(List<Recording>) onVerificationComplete;

  const AdminUserRecordingsScreen({
    super.key,
    required this.username,
    required this.recordings,
    required this.backendUrl,
    required this.onVerificationComplete,
  });

  @override
  Widget build(BuildContext context) {
    final totalDuration = recordings.fold<int>(
        0, (sum, rec) => sum + (rec.durationMs ?? 0));

    return Scaffold(
      backgroundColor: const Color(0xFF2a2a2a),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a1a1a),
        title: Text('$username\'s Recordings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User info header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF3a3a3a),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFF1a73e8),
                      radius: 30,
                      child: Icon(Icons.person, color: Colors.white, size: 30),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            username,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${recordings.length} clip${recordings.length != 1 ? 's' : ''} • ${_formatDuration(totalDuration)} total',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 14,
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
                'Recordings',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              RecordingListWidget(
                recordings: recordings,
                backendUrl: backendUrl,
                onVerificationComplete: onVerificationComplete,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(int durationMs) {
    final duration = Duration(milliseconds: durationMs);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes);
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}

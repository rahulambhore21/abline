import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'recording.dart';

class RecordingListWidget extends StatefulWidget {
  final List<Recording> recordings;
  final String backendUrl;

  const RecordingListWidget({
    super.key,
    required this.recordings,
    required this.backendUrl,
  });

  @override
  State<RecordingListWidget> createState() => _RecordingListWidgetState();
}

class _RecordingListWidgetState extends State<RecordingListWidget> {
  late AudioPlayer _audioPlayer;
  String? _currentPlayingRecordingId;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _setupAudioPlayerListeners();
  }

  /// Setup listeners for audio player state changes
  void _setupAudioPlayerListeners() {
    _audioPlayer.playerStateStream.listen((state) {
      // If player finished, reset
      if (state.processingState == ProcessingState.completed) {
        setState(() {
          _currentPlayingRecordingId = null;
        });
      }
    });
  }

  /// Play a recording from URL (auto-plays and auto-stops when done)
  Future<void> _playRecording(Recording recording) async {
    try {
      // Stop current playback if any
      if (_currentPlayingRecordingId != null) {
        await _audioPlayer.stop();
      }

      setState(() {
        _currentPlayingRecordingId = recording.id;
      });

      // Load and play the audio
      await _audioPlayer.setUrl(recording.url);
      await _audioPlayer.play();
    } catch (e) {
      print('Error playing recording: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error playing audio: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Stop playback
  Future<void> _stopPlayback() async {
    await _audioPlayer.stop();
    setState(() {
      _currentPlayingRecordingId = null;
    });
  }

  /// Format duration as mm:ss
  String _formatDuration(int durationMs) {
    final duration = Duration(milliseconds: durationMs);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  /// Format time as HH:MM AM/PM (Indian Standard Time - IST, UTC+5:30)
  String _formatTime(DateTime dateTime) {
    // Convert UTC to Indian Standard Time (IST, UTC+5:30)
    final istTime = dateTime.add(const Duration(hours: 5, minutes: 30));

    final hour = istTime.hour;
    final minute = istTime.minute;

    // Convert to 12-hour format
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    final ampm = hour >= 12 ? 'PM' : 'AM';

    return '${hour12.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $ampm';
  }

  /// Get date string from DateTime (Indian Standard Time - IST, UTC+5:30)
  String _getDateString(DateTime dateTime) {
    // Convert UTC to Indian Standard Time (IST, UTC+5:30)
    final istTime = dateTime.add(const Duration(hours: 5, minutes: 30));

    return '${istTime.day} ${_getMonthName(istTime.month)} ${istTime.year}';
  }

  /// Group recordings by date
  Map<String, List<Recording>> _groupRecordingsByDate() {
    final grouped = <String, List<Recording>>{};

    for (final recording in widget.recordings) {
      try {
        final dateTime = DateTime.parse(recording.recordedAt);
        final dateString = _getDateString(dateTime);

        if (!grouped.containsKey(dateString)) {
          grouped[dateString] = [];
        }
        grouped[dateString]!.add(recording);
      } catch (e) {
        print('Error parsing date: ${recording.recordedAt}');
      }
    }

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.recordings.isEmpty) {
      return const Text(
        'No recordings available',
        style: TextStyle(color: Colors.grey),
      );
    }

    final groupedRecordings = _groupRecordingsByDate();

    return Column(
      children: groupedRecordings.entries.map((entry) {
        final dateString = entry.key;
        final recordingsForDate = entry.value;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              child: Text(
                dateString,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
            ),
            // Recordings for this date
            ...recordingsForDate.map((recording) {
              final dateTime = DateTime.parse(recording.recordedAt);
              final timeString = _formatTime(dateTime);
              final durationString = _formatDuration(recording.durationMs ?? 0);
              final isCurrentlyPlaying = _currentPlayingRecordingId == recording.id;

              return GestureDetector(
                onTap: isCurrentlyPlaying
                    ? _stopPlayback
                    : () => _playRecording(recording),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isCurrentlyPlaying
                        ? Colors.blue.shade700
                        : Colors.white.withOpacity(0.05),
                    border: Border.all(
                      color: isCurrentlyPlaying
                          ? Colors.blue.shade500
                          : Colors.white.withOpacity(0.1),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      // Play/Stop icon
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isCurrentlyPlaying
                              ? Colors.blue.shade600
                              : Colors.blue.shade400,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isCurrentlyPlaying ? Icons.stop : Icons.play_arrow,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Time and duration
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              timeString,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Duration: $durationString',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Playing indicator
                      if (isCurrentlyPlaying)
                        Container(
                          width: 4,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.blue.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
            const SizedBox(height: 8),
          ],
        );
      }).toList(),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}

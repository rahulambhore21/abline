import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'recording.dart';
import 'user.dart';

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
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _setupAudioPlayerListeners();
  }

  /// Setup listeners for audio player state changes
  void _setupAudioPlayerListeners() {
    _audioPlayer.positionStream.listen((duration) {
      setState(() {
        _currentPosition = duration;
      });
    });

    _audioPlayer.durationStream.listen((duration) {
      setState(() {
        _totalDuration = duration ?? Duration.zero;
      });
    });

    _audioPlayer.playerStateStream.listen((state) {
      setState(() {
        _isPlaying = state.playing;
      });

      // If player finished, reset
      if (state.processingState == ProcessingState.completed) {
        _stopPlayback();
      }
    });
  }

  /// Play a recording from URL
  Future<void> _playRecording(Recording recording) async {
    try {
      // Stop current playback if any
      if (_currentPlayingRecordingId != null && _currentPlayingRecordingId != recording.id) {
        await _audioPlayer.stop();
      }

      setState(() {
        _currentPlayingRecordingId = recording.id;
        _currentPosition = Duration.zero;
      });

      // Load and play the audio
      await _audioPlayer.setUrl(recording.url);
      await _audioPlayer.play();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Playing: ${recording.filename}')),
      );
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

  /// Pause playback
  Future<void> _pausePlayback() async {
    await _audioPlayer.pause();
  }

  /// Resume playback
  Future<void> _resumePlayback() async {
    await _audioPlayer.play();
  }

  /// Stop playback
  Future<void> _stopPlayback() async {
    await _audioPlayer.stop();
    setState(() {
      _currentPlayingRecordingId = null;
      _currentPosition = Duration.zero;
    });
  }

  /// Format duration as mm:ss
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.recordings.isEmpty) {
      return const Text(
        'No recordings available',
        style: TextStyle(color: Colors.grey),
      );
    }

    return Column(
      children: [
        // Current playback display
        if (_currentPlayingRecordingId != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              border: Border.all(color: Colors.blue.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Now Playing',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                // Progress bar
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _totalDuration.inMilliseconds > 0
                            ? _currentPosition.inMilliseconds / _totalDuration.inMilliseconds
                            : 0,
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(_currentPosition),
                          style: const TextStyle(fontSize: 11),
                        ),
                        Text(
                          _formatDuration(_totalDuration),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Playback controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isPlaying ? _pausePlayback : _resumePlayback,
                      icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                      label: Text(_isPlaying ? 'Pause' : 'Resume'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _stopPlayback,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                    ),
                  ],
                ),
              ],
            ),
          ),

        // Recordings list
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.recordings.length,
          itemBuilder: (context, index) {
            final recording = widget.recordings[index];
            final isCurrentlyPlaying = _currentPlayingRecordingId == recording.id;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isCurrentlyPlaying ? Colors.blue : Colors.grey.shade300,
                  width: isCurrentlyPlaying ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(8),
                color: isCurrentlyPlaying ? Colors.blue.shade50 : Colors.white,
              ),
              child: Row(
                children: [
                  // Play button
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade400,
                      shape: BoxShape.circle,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: isCurrentlyPlaying
                            ? null
                            : () => _playRecording(recording),
                        customBorder: const CircleBorder(),
                        child: Center(
                          child: Icon(
                            isCurrentlyPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Recording info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'User: ${recording.userId}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          recording.filename,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Recorded: ${_formatRecordingTime(recording.recordedAt)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Status badge
                  if (isCurrentlyPlaying)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Playing',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  /// Format recording timestamp for display
  String _formatRecordingTime(String isoString) {
    try {
      final dateTime = DateTime.parse(isoString);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 1) {
        return 'just now';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inDays < 1) {
        return '${difference.inHours}h ago';
      } else {
        return dateTime.toString().substring(0, 16);
      }
    } catch (e) {
      return 'unknown';
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}

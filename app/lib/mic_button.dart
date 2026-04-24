import 'package:flutter/material.dart';

/// Large circular microphone button in the centre of the call screen.
///
/// - For [isHost]: tap to toggle mute.
/// - For regular users: hold (press-down) to speak, release to mute.
class MicButton extends StatelessWidget {
  final bool isHost;
  final bool isConnected;
  final bool isJoining;
  final bool isMuted;
  final bool isSessionActive;
  final bool isRecordingAudio;

  final Future<void> Function() onTap;
  final Future<void> Function() onTapDown;
  final Future<void> Function() onTapUp;
  final Future<void> Function() onTapCancel;

  const MicButton({
    super.key,
    required this.isHost,
    required this.isConnected,
    required this.isJoining,
    required this.isMuted,
    required this.isSessionActive,
    required this.isRecordingAudio,
    required this.onTap,
    required this.onTapDown,
    required this.onTapUp,
    required this.onTapCancel,
  });

  Color get _activeColor {
    if (isJoining) return const Color(0xFFFFCD00);
    if (!isHost && !isSessionActive && !isConnected) return Colors.grey;
    return isMuted ? const Color(0xFFFF4757) : const Color(0xFF00FF41);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topRight,
      children: [
        GestureDetector(
          onTap: isHost && isConnected ? () => onTap() : null,
          onTapDown:
              !isHost && isConnected ? (_) => onTapDown() : null,
          onTapUp: !isHost && isConnected ? (_) => onTapUp() : null,
          onTapCancel:
              !isHost && isConnected ? () => onTapCancel() : null,
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _activeColor.withOpacity(0.6),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _activeColor.withOpacity(0.4),
                  width: 3,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _activeColor,
                ),
                child: isJoining
                    ? const SizedBox(
                        width: 60,
                        height: 60,
                        child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                          strokeWidth: 3,
                        ),
                      )
                    : Icon(
                        isMuted ? Icons.mic_off : Icons.mic,
                        size: 60,
                        color: Colors.white,
                      ),
              ),
            ),
          ),
        ),

        // Red recording badge
        if (isRecordingAudio)
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red,
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.8),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Text('🔴', style: TextStyle(fontSize: 16)),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

/// The row of icon buttons shown above the microphone (Speaker, Bluetooth,
/// Recordings, Exit Room).
class CallControlsBar extends StatelessWidget {
  final bool isHost;
  final VoidCallback onExitRoom;
  final VoidCallback? onRecordingsTap;

  const CallControlsBar({
    super.key,
    required this.isHost,
    required this.onExitRoom,
    this.onRecordingsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF3a3a3a),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ControlButton(
            icon: Icons.volume_up,
            label: 'Speaker',
            color: const Color(0xFF00D4FF),
          ),
          _ControlButton(
            icon: Icons.bluetooth,
            label: 'Bluetooth',
            color: const Color(0xFF00D4FF),
          ),
          if (!isHost)
            _ControlButton(
              icon: Icons.music_note,
              label: 'Recordings',
              color: const Color(0xFF00FF41),
              onTap: onRecordingsTap,
            ),
          _ControlButton(
            icon: Icons.close,
            label: 'Exit Room',
            color: const Color(0xFF8B4789),
            onTap: onExitRoom,
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

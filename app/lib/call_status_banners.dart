import 'package:flutter/material.dart';

/// Top status banners shown on the call screen:
/// - Red "🔴 RECORDING ACTIVE" banner when cloud recording is on.
/// - Orange/green session status for non-host users who haven't joined yet.
class CallStatusBanners extends StatelessWidget {
  final bool isRecording;
  final bool isHost;
  final bool isConnected;
  final bool isSessionActive;

  const CallStatusBanners({
    super.key,
    required this.isRecording,
    required this.isHost,
    required this.isConnected,
    required this.isSessionActive,
  });

  @override
  Widget build(BuildContext context) => Column(
      children: [
        // Cloud recording active banner
        if (isRecording) ...[
          const _Banner(
            color: Colors.red,
            icon: Icons.fiber_manual_record,
            message: '🔴 RECORDING ACTIVE',
          ),
          const SizedBox(height: 16),
        ],

        // Session status for non-host users who are not yet connected
        if (!isHost && !isConnected) ...[
          _Banner(
            color: isSessionActive ? Colors.green : Colors.orange,
            icon: isSessionActive ? Icons.check_circle : Icons.access_time,
            message: isSessionActive
                ? '✅ Session is active - You can join now'
                : '⏳ Waiting for host to start the session...',
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
}

class _Banner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String message;

  const _Banner({
    required this.color,
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
}

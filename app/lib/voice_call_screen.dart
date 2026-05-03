import 'dart:async';
import 'package:flutter/material.dart';
import 'voice_call_controller.dart';
import 'call_controls_bar.dart';
import 'call_status_banners.dart';
import 'mic_button.dart';
import 'participants_talking_panel.dart';
import 'user_recordings_screen.dart';

/// Voice call screen — UI shell only.
///
/// All business logic lives in [VoiceCallController] (ChangeNotifier).
/// Widget files used:
///   • [CallStatusBanners]  — recording / session status banners
///   • [CallControlsBar]   — Speaker / Bluetooth / Recordings / Exit row
///   • [MicButton]         — large circular mic with hold-to-speak
///   • [ParticipantsTalkingPanel] — host-only "Who's Talking" list
class VoiceCallScreen extends StatefulWidget {
  const VoiceCallScreen({super.key});

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  late final VoiceCallController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = VoiceCallController();

    // Wire callbacks before init so they are available during setup.
    _ctrl.onError = (msg) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    };

    _ctrl.onSuccess = (msg) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    };

    _ctrl.onHostLeft = () async {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final nav = Navigator.of(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Host ended the call'),
          backgroundColor: Colors.orange,
        ),
      );
      nav.popUntil((route) => route.isFirst);
    };

    _ctrl.init();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: _ctrl,
      builder: (context, _) => _buildScaffold(context),
    );

  Widget _buildScaffold(BuildContext context) => PopScope(
      canPop: false, // Handle pop manually to ensure leaveChannel is called
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleExit(context);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF2a2a2a),
        body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => _handleExit(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white30),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.arrow_back,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Hello, ${_ctrl.username}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ─── Status banners ───────────────────────────────────────────
            CallStatusBanners(
              isRecording: _ctrl.isRecording,
              isHost: _ctrl.isHost,
              isConnected: _ctrl.isConnected,
              isSessionActive: _ctrl.isSessionActive,
              presenceStatus: _ctrl.presenceStatus,
            ),


            // ─── Controls bar ─────────────────────────────────────────────
            CallControlsBar(
              isHost: _ctrl.isHost,
              isSpeakerOn: _ctrl.isSpeakerOn,
              onSpeakerTap: _ctrl.toggleSpeakerphone,
              onExitRoom: () => _handleExit(context),
              onRecordingsTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => UserRecordingsScreen(
                    sessionId: _ctrl.channelName,
                    userId: _ctrl.uid,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),

            // ── Mic button ───────────────────────────────────────────────
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  MicButton(
                    isHost: _ctrl.isHost,
                    isConnected: _ctrl.isConnected,
                    isJoining: _ctrl.isJoining,
                    isMuted: _ctrl.isMuted,
                    isSessionActive: _ctrl.isSessionActive,
                    isRecordingAudio: _ctrl.isRecordingAudio,
                    onTap: _ctrl.toggleMute,
                    onTapDown: _ctrl.unmute,
                    onTapUp: _ctrl.mute,
                    onTapCancel: _ctrl.mute,
                  ),
                  const SizedBox(height: 32),
                  _StatusLabel(ctrl: _ctrl),
                ],
              ),
            ),

            // ── Participants panel (host only) ────────────────────────────
            if (_ctrl.isConnected &&
                _ctrl.remoteUsers.isNotEmpty &&
                _ctrl.isHost)
              ParticipantsTalkingPanel(
                speakerTracker: _ctrl.speakerTracker,
                usernames: _ctrl.usernames,
              ),

            // ✅ Bottom padding that adapts to system navigation bar
            SizedBox(height: 16 + MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),

    ),
  );

  Future<void> _handleExit(BuildContext context) async {
    // Show a small overlay to prevent interaction while leaving
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Leaving room...',
              style: TextStyle(
                color: Colors.white,
                decoration: TextDecoration.none,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    ));

    try {
      await _ctrl.leaveChannel();
    } catch (e) {
      debugPrint('Error during leave: $e');
    } finally {
      if (mounted && context.mounted) {
        // Pop the loading dialog
        Navigator.of(context, rootNavigator: true).pop();
        // Pop the VoiceCallScreen back to the dashboard/home
        Navigator.of(context).pop();
      }
    }
  }
}

/// Small status text beneath the mic button.
class _StatusLabel extends StatelessWidget {
  final VoiceCallController ctrl;
  const _StatusLabel({required this.ctrl});

  String get _text {
    if (ctrl.presenceStatus == PresenceStatus.reconnecting) return 'RECONNECTING...';
    if (ctrl.isJoining) return 'CONNECTING...';
    if (ctrl.isConnected) {
      if (ctrl.isHost) {
        return ctrl.isMuted ? 'TAP TO UNMUTE' : 'TAP TO MUTE';
      }
      return ctrl.isMuted ? 'HOLD TO TALK' : 'SPEAKING - RELEASE TO MUTE';
    }
    if (!ctrl.isHost && !ctrl.isSessionActive) return 'WAITING FOR HOST...';
    return ctrl.statusMessage.toUpperCase();
  }

  Color get _color {
    if (ctrl.presenceStatus == PresenceStatus.reconnecting) return Colors.amber;
    if (ctrl.isJoining) return const Color(0xFFFFCD00);
    if (ctrl.isConnected && !ctrl.isMuted) return const Color(0xFF00FF41);
    return Colors.white70;
  }

  @override
  Widget build(BuildContext context) => Text(
      _text,
      style: TextStyle(
        color: _color,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.5,
      ),
    );
}

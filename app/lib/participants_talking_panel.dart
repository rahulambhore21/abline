import 'package:flutter/material.dart';
import 'speaker_tracker.dart';
import 'speaking_event.dart';

/// Shows the host-only "Who's Talking" panel — a live list of participants
/// with green/grey speaking indicators, driven by [SpeakerTracker].
class ParticipantsTalkingPanel extends StatelessWidget {
  final SpeakerTracker speakerTracker;
  final Map<int, String> usernames;

  const ParticipantsTalkingPanel({
    super.key,
    required this.speakerTracker,
    required this.usernames,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF3a3a3a),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Who's Talking",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ValueListenableBuilder<Map<int, UserSpeakingState>>(
                valueListenable: speakerTracker.speakingStatesNotifier,
                builder: (context, speakingStates, _) {
                  final entries = speakingStates.entries.toList();

                  if (entries.isEmpty) {
                    return const Center(
                      child: Text(
                        'Listening...',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white10),
                    itemBuilder: (context, index) {
                      final uid = entries[index].key;
                      final state = entries[index].value;
                      final name =
                          usernames[uid] ?? 'User #$uid';

                      return Row(
                        children: [
                          _SpeakingDot(isSpeaking: state.isSpeaking),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  state.isSpeaking
                                      ? '🎤 Speaking'
                                      : '🔇 Listening',
                                  style: TextStyle(
                                    color: state.isSpeaking
                                        ? Colors.green
                                        : Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (state.isSpeaking)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'ACTIVE',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeakingDot extends StatelessWidget {
  final bool isSpeaking;
  const _SpeakingDot({required this.isSpeaking});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSpeaking ? Colors.green : Colors.grey,
        boxShadow: isSpeaking
            ? [
                BoxShadow(
                  color: Colors.green.withOpacity(0.5),
                  blurRadius: 8,
                )
              ]
            : null,
      ),
    );
  }
}

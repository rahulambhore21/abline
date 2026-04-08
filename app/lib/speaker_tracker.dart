import 'dart:async';
import 'package:flutter/material.dart';
import 'speaking_event.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Callback when a speaking event is completed.
typedef OnSpeakingEventComplete = void Function(SpeakingEvent event);

/// Manages real-time speaker detection and tracking.
///
/// How detection works:
/// - Agora reports per-user `volume` (0-100) every ~200ms.
/// - We consider `volume > 50` as "speaking".
/// - To prevent noise/flicker, we **debounce state changes**:
///   the new speaking/silent reading must remain consistent for >= 300ms
///   before we commit a transition.
///
/// How transitions are handled:
/// - Silent → Speaking: record `startTime` once.
/// - Speaking → Silent: record `endTime`, create a `SpeakingEvent`, POST to backend.
/// - A silence timeout also ends speaking if we stop receiving volume updates.
class SpeakerTracker {
  // Configuration constants
  static const int volumeThreshold = 50; // Volume > 50 = speaking
  static const int debounceMs = 300; // Ignore rapid fluctuations

  final Map<int, UserSpeakingState> _userStates = {};

  // Candidate transition tracking (stable-state debounce)
  final Map<int, bool> _candidateState = {}; // uid -> desired state
  final Map<int, DateTime> _candidateSince = {}; // uid -> when candidate started

  // Last time we received any volume sample for a user (used for silence timeout)
  final Map<int, DateTime> _lastSampleAt = {};

  // Optional periodic timer to close speaking when samples stop arriving
  Timer? _silenceTimer;

  final OnSpeakingEventComplete? onSpeakingEventComplete;
  final String backendUrl;
  final int sessionId;

  // ValueNotifier for UI updates (listening widgets rebuild when speaking state changes)
  final ValueNotifier<Map<int, UserSpeakingState>> speakingStatesNotifier;

  SpeakerTracker({
    required this.backendUrl,
    required this.sessionId,
    this.onSpeakingEventComplete,
  }) : speakingStatesNotifier = ValueNotifier<Map<int, UserSpeakingState>>({});

  /// Start background silence checks.
  ///
  /// Call this after joining a channel (optional but recommended).
  void start() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => tick(),
    );
  }

  /// Stop background checks.
  void stop() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
  }

  /// Process a single user's volume sample.
  void processAudioVolume({
    required int uid,
    required int volume,
    DateTime? at,
  }) {
    final now = at ?? DateTime.now();

    // Initialize user state if new
    _userStates.putIfAbsent(uid, () => UserSpeakingState(uid: uid));
    _lastSampleAt[uid] = now;

    final userState = _userStates[uid]!;
    final readingSpeaking = volume > volumeThreshold;

    // If reading matches current state, clear any pending candidate.
    if (readingSpeaking == userState.isSpeaking) {
      _candidateState.remove(uid);
      _candidateSince.remove(uid);
      return;
    }

    // Reading differs from current state -> begin/continue debounce confirmation.
    final existingCandidate = _candidateState[uid];

    if (existingCandidate == readingSpeaking) {
      final since = _candidateSince[uid] ?? now;
      if (now.difference(since).inMilliseconds >= debounceMs) {
        // Use the candidate start time for more accurate timelines.
        _commitTransition(uid: uid, toSpeaking: readingSpeaking, at: since);
        _candidateState.remove(uid);
        _candidateSince.remove(uid);
      }
    } else {
      // New candidate direction
      _candidateState[uid] = readingSpeaking;
      _candidateSince[uid] = now;
    }
  }

  /// Tick is used to end speaking when volume samples stop arriving.
  ///
  /// This prevents “stuck speaking” if the SDK stops reporting a user once silent.
  void tick({DateTime? now}) {
    final t = now ?? DateTime.now();

    for (final entry in _userStates.entries) {
      final uid = entry.key;
      final state = entry.value;

      if (!state.isSpeaking) continue;

      final last = _lastSampleAt[uid];
      if (last == null) continue;

      // If we haven't seen samples for > debounceMs, treat it as silence and end the event.
      // Use the last observed sample time as the best-available end timestamp.
      if (t.difference(last).inMilliseconds > debounceMs) {
        _commitTransition(uid: uid, toSpeaking: false, at: last, viaTimeout: true);
        _candidateState.remove(uid);
        _candidateSince.remove(uid);
      }
    }
  }

  void _commitTransition({
    required int uid,
    required bool toSpeaking,
    required DateTime at,
    bool viaTimeout = false,
  }) {
    final userState = _userStates[uid]!;

    if (toSpeaking) {
      // Silent → Speaking
      if (!userState.isSpeaking) {
        userState.isSpeaking = true;
        userState.lastStartTime = at;
        print('🎤 User $uid started speaking at $at');
        speakingStatesNotifier.value = Map.from(_userStates);
      }
      return;
    }

    // Speaking → Silent
    if (userState.isSpeaking) {
      userState.isSpeaking = false;
      userState.lastEndTime = at;

      if (userState.lastStartTime != null) {
        final event = SpeakingEvent(
          userId: uid,
          sessionId: sessionId,
          startTime: userState.lastStartTime!,
          endTime: at,
        );

        print(viaTimeout
            ? '🛑 User $uid stopped speaking (timeout) at $at'
            : '🛑 User $uid stopped speaking at $at');
        print('📊 Event: $event');

        onSpeakingEventComplete?.call(event);
        _sendEventToBackend(event);
      }

      speakingStatesNotifier.value = Map.from(_userStates);
    }
  }

  Future<void> _sendEventToBackend(SpeakingEvent event) async {
    try {
      final response = await http
          .post(
            Uri.parse('$backendUrl/events/speaking'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(event.toJson()),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 201 || response.statusCode == 200) {
        print('✅ Event sent successfully: ${event.userId}');
      } else {
        print('⚠️ Backend returned ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('❌ Error sending event to backend: $e');
    }
  }

  UserSpeakingState? getUserState(int uid) => _userStates[uid];
  Map<int, UserSpeakingState> getAllUserStates() => Map.from(_userStates);
  bool isUserSpeaking(int uid) => _userStates[uid]?.isSpeaking ?? false;

  void removeUser(int uid) {
    _candidateState.remove(uid);
    _candidateSince.remove(uid);
    _lastSampleAt.remove(uid);
    _userStates.remove(uid);
    speakingStatesNotifier.value = Map.from(_userStates);
  }

  void reset() {
    stop();
    _candidateState.clear();
    _candidateSince.clear();
    _lastSampleAt.clear();
    _userStates.clear();
    speakingStatesNotifier.value = {};
  }

  void dispose() {
    reset();
    speakingStatesNotifier.dispose();
  }
}

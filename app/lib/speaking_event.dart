/// Represents a completed speaking interval for a single user.
///
/// Compatibility note:
/// - The original call-flow (SpeakerTracker + VoiceCallScreen) used
///   `startTime` / `endTime`.
/// - The dashboard/timeline rendering prefers `start` / `end`.
///
/// To keep both working, this model stores `startTime/endTime` and exposes
/// `start/end` getters.
class SpeakingEvent {
  final String? id;
  final int userId;
  final String sessionId;
  final DateTime startTime;
  final DateTime endTime;

  SpeakingEvent({
    this.id,
    required this.userId,
    required this.sessionId,
    required this.startTime,
    required this.endTime,
  });

  /// Back-compat getters used by the timeline renderer.
  DateTime get start => startTime;
  DateTime get end => endTime;

  /// Duration in seconds.
  int get durationSeconds => endTime.difference(startTime).inSeconds;

  /// Parse from backend API response.
  ///
  /// Expected backend keys:
  /// - start/end (ISO8601)
  /// - userId, sessionId
  factory SpeakingEvent.fromJson(Map<String, dynamic> json) {
    // Some callers may send startTime/endTime, so accept both.
    final startRaw = (json['start'] ?? json['startTime']) as String;
    final endRaw = (json['end'] ?? json['endTime']) as String;

    return SpeakingEvent(
      id: json['id']?.toString(),
      userId: (json['userId'] as num).toInt(),
      sessionId: json['sessionId'].toString(),
      startTime: DateTime.parse(startRaw),
      endTime: DateTime.parse(endRaw),
    );
  }

  /// Convert to JSON for backend API integration.
  ///
  /// Backend endpoint: POST /events/speaking
  /// The backend expects `start` and `end` fields.
  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'sessionId': sessionId,
      'start': startTime.toIso8601String(),
      'end': endTime.toIso8601String(),
    };
  }

  @override
  String toString() =>
      'SpeakingEvent(userId: $userId, sessionId: $sessionId, start: $startTime, end: $endTime)';
}

/// Tracks the current speaking state of a user
class UserSpeakingState {
  int uid;
  bool isSpeaking;
  DateTime? lastStartTime;
  DateTime? lastEndTime;

  UserSpeakingState({
    required this.uid,
    this.isSpeaking = false,
    this.lastStartTime,
    this.lastEndTime,
  });

  @override
  String toString() =>
      'UserSpeakingState(uid: $uid, isSpeaking: $isSpeaking, startTime: $lastStartTime)';
}

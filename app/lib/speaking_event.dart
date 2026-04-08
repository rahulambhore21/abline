/// Represents a complete speaking event with start and end times
class SpeakingEvent {
  final int userId;
  final int sessionId;
  final DateTime startTime;
  final DateTime endTime;

  SpeakingEvent({
    required this.userId,
    required this.sessionId,
    required this.startTime,
    required this.endTime,
  });

  /// Convert to JSON for backend API
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
      'SpeakingEvent(userId: $userId, start: $startTime, end: $endTime)';
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

class Recording {
  final String id;
  final int userId;
  final String sessionId;
  final String filename;
  final String url;
  final String recordedAt;
  final int? durationMs;

  Recording({
    required this.id,
    required this.userId,
    required this.sessionId,
    required this.filename,
    required this.url,
    required this.recordedAt,
    this.durationMs,
  });

  factory Recording.fromJson(Map<String, dynamic> json) {
    return Recording(
      id: json['id'] as String,
      userId: json['userId'] as int,
      sessionId: json['sessionId'] as String,
      filename: json['filename'] as String,
      url: json['url'] as String,
      recordedAt: json['recordedAt'] as String,
      durationMs: json['durationMs'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'sessionId': sessionId,
      'filename': filename,
      'url': url,
      'recordedAt': recordedAt,
      'durationMs': durationMs,
    };
  }
}

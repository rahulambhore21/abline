class Recording {
  final String id;
  final int userId;
  final String username; // ✅ NEW
  final String sessionId;
  final String filename;
  final String url;
  final String recordedAt;
  final int? durationMs;
  final bool? exists; // ✅ NEW: Server-side existence check

  Recording({
    required this.id,
    required this.userId,
    required this.username,
    required this.sessionId,
    required this.filename,
    required this.url,
    required this.recordedAt,
    this.durationMs,
    this.exists,
  });

  factory Recording.fromJson(Map<String, dynamic> json) => Recording(
      id: json['id'] as String,
      userId: json['userId'] is int
          ? json['userId'] as int
          : int.tryParse(json['userId'].toString()) ?? 0,
      username: json['username']?.toString() ?? 'Unknown', // ✅ NEW
      sessionId: json['sessionId'] as String,
      filename: json['filename'] as String,
      url: json['url'] as String,
      recordedAt: json['recordedAt'] as String,
      durationMs: json['durationMs'] as int?,
      exists: json['exists'] as bool?, // ✅ NEW
    );

  Map<String, dynamic> toJson() => {
      'id': id,
      'userId': userId,
      'sessionId': sessionId,
      'filename': filename,
      'url': url,
      'recordedAt': recordedAt,
      'durationMs': durationMs,
    };
}

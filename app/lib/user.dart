class User {
  final int userId;
  final String username;
  final bool isSpeaking;

  User({
    required this.userId,
    required this.username,
    required this.isSpeaking,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      userId: json['userId'] as int,
      username: json['username'] as String,
      isSpeaking: json['isSpeaking'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'isSpeaking': isSpeaking,
    };
  }

  User copyWith({
    int? userId,
    String? username,
    bool? isSpeaking,
  }) {
    return User(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      isSpeaking: isSpeaking ?? this.isSpeaking,
    );
  }
}

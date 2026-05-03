import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// AuthService handles JWT token management, login, registration, and API calls
class AuthService {
  final String backendUrl;
  final String? storageKeyPrefix;
  final _storage = const FlutterSecureStorage();

  // ✅ OPTIMIZATION: Cache frequently accessed values to avoid storage reads
  String? _cachedToken;
  String? _cachedRole;
  String? _cachedUserId;
  String? _cachedUsername;
  bool _cacheInitialized = false;

  AuthService({required this.backendUrl, this.storageKeyPrefix});

  /// ✅ OPTIMIZATION: Initialize cache from SharedPreferences on first access
  Future<void> _initializeCache() async {
    if (_cacheInitialized) return;

    final prefs = await SharedPreferences.getInstance();
    
    // Tokens are stored in SecureStorage
    _cachedToken = await _storage.read(key: 'auth_token');
    
    // Other metadata stays in SharedPreferences for fast non-secure access
    _cachedRole = prefs.getString('user_role');
    _cachedUserId = prefs.getString('user_id');
    _cachedUsername = prefs.getString('username');
    _cacheInitialized = true;
  }

  /// ✅ OPTIMIZATION: Clear cache when values change
  void _invalidateCache() {
    _cacheInitialized = false;
    _cachedToken = null;
    _cachedRole = null;
    _cachedUserId = null;
    _cachedUsername = null;
  }

  /// Login with username and password, returns JWT token or null on failure
  Future<LoginResponse?> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final loginResponse = LoginResponse(
          token: data['token'] as String,
          role: data['role'] as String,
          userId: data['userId'] as String,
          username: username,
          message: (data['message'] ?? '') as String,
        );
        
        // Store token and role locally
        await _saveToken(loginResponse.token);
        await _saveRole(loginResponse.role);
        await _saveUserId(loginResponse.userId);
        await _saveUsername(username);
        
        return loginResponse;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Login failed');
      }
    } catch (e) {
      throw Exception('Login error: $e');
    }
  }

  /// Register a new host (only for first host user)
  Future<RegisterResponse?> registerHost(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/auth/register-host'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return RegisterResponse(
          success: (data['success'] ?? true) as bool,
          userId: data['userId'] as String,
          message: (data['message'] ?? 'Host registered successfully') as String,
        );
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Registration failed');
      }
    } catch (e) {
      throw Exception('Registration error: $e');
    }
  }

  /// Create a new user (host-only)
  Future<bool> createUser(String username, String password) async {
    try {
      final token = await getToken();
      if (token == null) throw Exception('Not authenticated');

      final response = await http.post(
        Uri.parse('$backendUrl/auth/create-user'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

      if (response.statusCode == 201) {
        return true;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'User creation failed');
      }
    } catch (e) {
      throw Exception('Create user error: $e');
    }
  }

  /// Delete a user (host-only)
  Future<bool> deleteUser(String userId) async {
    try {
      final token = await getToken();
      if (token == null) throw Exception('Not authenticated');

      final response = await http.delete(
        Uri.parse('$backendUrl/auth/users/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'User deletion failed');
      }
    } catch (e) {
      throw Exception('Delete user error: $e');
    }
  }

  /// Get stored JWT token (cached)
  Future<String?> getToken() async {
    await _initializeCache();
    return _cachedToken;
  }

  /// Get stored user role (host or user) (cached)
  Future<String?> getRole() async {
    await _initializeCache();
    return _cachedRole;
  }

  /// Get stored user ID (cached)
  Future<String?> getUserId() async {
    await _initializeCache();
    return _cachedUserId;
  }

  /// Get stored username (cached)
  Future<String?> getUsername() async {
    await _initializeCache();
    return _cachedUsername;
  }

  /// Check if user is authenticated AND the stored JWT has not expired.
  ///
  /// Decodes the base64 payload locally (no network call) to read `exp`.
  /// If the token is expired it is automatically cleared from storage so
  /// the user is redirected to login on the next app start.
  Future<bool> isAuthenticated() async {
    final token = await getToken();
    if (token == null || token.isEmpty) return false;

    if (isTokenExpired(token)) {
      // Silently clear stale credentials so the user sees the login screen.
      await logout();
      return false;
    }

    return true;
  }

  /// Returns true when [token] is past its `exp` timestamp.
  ///
  /// Falls back to `false` (not expired) when the token cannot be parsed,
  /// which keeps the app working if the backend ever issues tokens without `exp`.
  static bool isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;

      // JWT payload is base64url-encoded (no padding).
      String payload = parts[1];
      // Add padding so base64 decode works.
      while (payload.length % 4 != 0) {
        payload += '=';
      }

      final Uint8List decoded = base64Url.decode(payload);
      final Map<String, dynamic> data =
          jsonDecode(utf8.decode(decoded)) as Map<String, dynamic>;

      final exp = data['exp'];
      if (exp == null) return false; // No expiry claim — treat as valid.

      final expiry =
          DateTime.fromMillisecondsSinceEpoch((exp as int) * 1000, isUtc: true);
      return DateTime.now().toUtc().isAfter(expiry);
    } catch (_) {
      return true; // Malformed token — treat as expired.
    }
  }

  /// Returns the expiry [DateTime] of [token], or null if it cannot be parsed.
  static DateTime? getTokenExpiry(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;

      String payload = parts[1];
      while (payload.length % 4 != 0) {
        payload += '=';
      }

      final Uint8List decoded = base64Url.decode(payload);
      final Map<String, dynamic> data =
          jsonDecode(utf8.decode(decoded)) as Map<String, dynamic>;

      final exp = data['exp'];
      if (exp == null) return null;

      return DateTime.fromMillisecondsSinceEpoch((exp as int) * 1000,
          isUtc: true);
    } catch (_) {
      return null;
    }
  }

  /// Check if user is host
  Future<bool> isHost() async {
    final role = await getRole();
    return role == 'host';
  }

  /// Logout - clear all stored auth data
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await _storage.delete(key: 'auth_token'); // Securely remove token
    await prefs.remove('user_role');
    await prefs.remove('user_id');
    await prefs.remove('username');
    _invalidateCache(); // ✅ OPTIMIZATION: Clear cache on logout
  }

  /// Make authenticated HTTP GET request
  Future<http.Response> authenticatedGet(String url) async {
    final token = await getToken();
    
    return http.get(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
  }

  /// Make authenticated HTTP POST request
  Future<http.Response> authenticatedPost(String url, {Map<String, dynamic>? body}) async {
    final token = await getToken();
    
    return http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: body != null ? jsonEncode(body) : null,
    );
  }

  /// Save token to secure storage
  Future<void> _saveToken(String token) async {
    await _storage.write(key: 'auth_token', value: token);
    _cachedToken = token; // ✅ OPTIMIZATION: Update cache
  }

  /// Save role to local storage
  Future<void> _saveRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', role);
    _cachedRole = role; // ✅ OPTIMIZATION: Update cache
  }

  /// Save user ID to local storage
  Future<void> _saveUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', userId);
    _cachedUserId = userId; // ✅ OPTIMIZATION: Update cache
  }

  /// Save username to local storage
  Future<void> _saveUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', username);
    _cachedUsername = username; // ✅ OPTIMIZATION: Update cache
    _cacheInitialized = true; // Mark cache as initialized after saving
  }
}

/// Response object for login
class LoginResponse {
  final String token;
  final String role;
  final String userId;
  final String username;
  final String message;

  LoginResponse({
    required this.token,
    required this.role,
    required this.userId,
    required this.username,
    required this.message,
  });
}

/// Response object for registration
class RegisterResponse {
  final bool success;
  final String userId;
  final String message;

  RegisterResponse({
    required this.success,
    required this.userId,
    required this.message,
  });
}

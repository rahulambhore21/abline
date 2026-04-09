import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// AuthService handles JWT token management, login, registration, and API calls
class AuthService {
  final String backendUrl;
  
  AuthService({required this.backendUrl});

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
          token: data['token'],
          role: data['role'],
          userId: data['userId'],
          username: username,
          message: data['message'] ?? '',
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
          success: data['success'] ?? true,
          userId: data['userId'],
          message: data['message'] ?? 'Host registered successfully',
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

  /// Get stored JWT token
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  /// Get stored user role (host or user)
  Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_role');
  }

  /// Get stored user ID
  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  /// Get stored username
  Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('username');
  }

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Check if user is host
  Future<bool> isHost() async {
    final role = await getRole();
    return role == 'host';
  }

  /// Logout - clear all stored auth data
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_role');
    await prefs.remove('user_id');
    await prefs.remove('username');
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
  Future<http.Response> authenticatedPost(String url, {Map? body}) async {
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

  /// Save token to local storage
  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  /// Save role to local storage
  Future<void> _saveRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', role);
  }

  /// Save user ID to local storage
  Future<void> _saveUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', userId);
  }

  /// Save username to local storage
  Future<void> _saveUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', username);
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

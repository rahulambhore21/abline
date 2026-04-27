import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'auth_service.dart';
import 'home_screen.dart';
import 'admin_screen.dart';
import 'app_config.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Talk Circle',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
      routes: {
        '/login': (context) => LoginScreen(backendUrl: AppConfig.backendBaseUrl),
        '/home': (context) => const HomeScreen(),
        '/admin': (context) => const AdminScreen(),
      },
    );
  }
}

/// AuthWrapper checks authentication state and routes appropriately
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  late AuthService _authService;
  bool _isAuthenticated = false;
  bool _isChecking = true;
  bool _isHost = false;

  @override
  void initState() {
    super.initState();
    _authService = AuthService(backendUrl: AppConfig.backendBaseUrl);
    _checkAuthentication();
  }

  /// Check if user is already logged in
  Future<void> _checkAuthentication() async {
    final isAuth = await _authService.isAuthenticated();
    final isHost = await _authService.isHost();
    setState(() {
      _isAuthenticated = isAuth;
      _isHost = isHost;
      _isChecking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_isAuthenticated) {
      // Route hosts to admin, regular users to home
      return _isHost ? const AdminScreen() : const HomeScreen();
    }

    return LoginScreen(backendUrl: AppConfig.backendBaseUrl);
  }
}


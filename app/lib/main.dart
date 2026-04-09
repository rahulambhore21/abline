import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'auth_service.dart';
import 'home_screen.dart';
import 'app_config.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agora Voice Call',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
      routes: {
        '/login': (context) => LoginScreen(backendUrl: AppConfig.backendBaseUrl),
        '/home': (context) => const HomeScreen(),
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

  @override
  void initState() {
    super.initState();
    _authService = AuthService(backendUrl: AppConfig.backendBaseUrl);
    _checkAuthentication();
  }

  /// Check if user is already logged in
  Future<void> _checkAuthentication() async {
    final isAuth = await _authService.isAuthenticated();
    setState(() {
      _isAuthenticated = isAuth;
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

    return _isAuthenticated
        ? const HomeScreen()
        : LoginScreen(backendUrl: AppConfig.backendBaseUrl);
  }
}


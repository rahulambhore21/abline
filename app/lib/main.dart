import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'login_screen.dart';
import 'auth_service.dart';
import 'home_screen.dart';
import 'admin_screen.dart';
import 'app_config.dart';

void main() {
  // Catch Flutter framework errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('🛑 FLUTTER ERROR: ${details.exception}');
    debugPrint('📚 STACK TRACE: ${details.stack}');
  };

  // Catch errors outside the Flutter framework (asynchronous)
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('🛑 ASYNC ERROR: $error');
    debugPrint('📚 STACK TRACE: $stack');
    return true; // Return true to indicate the error is handled
  };

  // Custom Error Widget for the "Red Screen of Death"
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return GlobalErrorScreen(
      error: details.exception.toString(),
      stackTrace: details.stack.toString(),
    );
  };

  runApp(
    const RestartWidget(
      child: MyApp(),
    ),
  );
}

/// A widget that allows restarting the entire application tree
class RestartWidget extends StatefulWidget {
  final Widget child;
  const RestartWidget({super.key, required this.child});

  static void restartApp(BuildContext context) {
    context.findAncestorStateOfType<_RestartWidgetState>()?.restartApp();
  }

  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  Key key = UniqueKey();

  void restartApp() {
    setState(() {
      key = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: key,
      child: widget.child,
    );
  }
}

class GlobalErrorScreen extends StatelessWidget {
  final String error;
  final String stackTrace;

  const GlobalErrorScreen({
    super.key,
    required this.error,
    required this.stackTrace,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Theme(
        data: ThemeData.dark(),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white, fontSize: 14),
          child: Material(
            color: const Color(0xFF1a1a1a),
            child: Center(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF2a2a2a),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bug_report, color: Colors.red, size: 64),
                    const SizedBox(height: 16),
                    const Text(
                      'Application Error',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      error,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 16),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Technical Details:',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            stackTrace,
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontFamily: 'monospace',
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        // Use the restart widget to re-initialize the app
                        RestartWidget.restartApp(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      ),
                      child: const Text('Restart Application'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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


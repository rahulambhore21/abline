import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'login_screen.dart';
import 'auth_service.dart';
import 'home_screen.dart';
import 'admin_screen.dart';
import 'app_config.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

Future<void> main() async {
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

  // Custom Error Widget for the "Red Screen of Deaths"
  ErrorWidget.builder = (FlutterErrorDetails details) => GlobalErrorScreen(
      error: details.exception.toString(),
      stackTrace: details.stack.toString(),
    );

  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://7c200378df530687f7a85e819bfd0b6f@o4511324775383040.ingest.us.sentry.io/4511324778397696';
      // Set tracesSampleRate to 1.0 to capture 100% of transactions for tracing.
      // We recommend adjusting this value in production.
      options.tracesSampleRate = 1.0;
      // The sampling rate for profiling is relative to tracesSampleRate
      // Setting to 1.0 will profile 100% of sampled transactions:
      // ignore: experimental_member_use
      options.profilesSampleRate = 1.0;
    },
    appRunner: () => runApp(SentryWidget(child: 
    const RestartWidget(
      child: MyApp(),
    ),
  )),
  );
  // TODO: Remove this line after sending the first sample event to sentry.
  await Sentry.captureException(Exception('This is a sample exception.'));
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
  Widget build(BuildContext context) => KeyedSubtree(
      key: key,
      child: widget.child,
    );
}

class GlobalErrorScreen extends StatefulWidget {
  final String error;
  final String stackTrace;

  const GlobalErrorScreen({
    super.key,
    required this.error,
    required this.stackTrace,
  });

  @override
  State<GlobalErrorScreen> createState() => _GlobalErrorScreenState();
}

class _GlobalErrorScreenState extends State<GlobalErrorScreen> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) => Directionality(
      textDirection: TextDirection.ltr,
      child: Theme(
        data: ThemeData.dark(),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white, fontSize: 14),
          child: Material(
            color: const Color(0xFF1a1a1a),
            child: Center(
              child: SingleChildScrollView(
                child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2a2a2a),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orangeAccent,
                        size: 72,
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Oops! Something went wrong',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'The application encountered an unexpected error. We apologize for the inconvenience.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 32),
                      
                      // Action Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            RestartWidget.restartApp(context);
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Restart Application'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Technical Details Toggle
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _showDetails = !_showDetails;
                          });
                        },
                        child: Text(
                          _showDetails ? 'Hide Details' : 'Show Technical Details',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 13,
                          ),
                        ),
                      ),
                      
                      if (_showDetails) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Error: ${widget.error}',
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              const Divider(color: Colors.white10, height: 20),
                              Text(
                                widget.stackTrace,
                                style: TextStyle(
                                  color: Colors.greenAccent.withValues(alpha: 0.8),
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
}



class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // If the app is moved to background (paused) or system-inactive
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      debugPrint('📱 App moved to background/inactive state: $state');
      
      // Force restart the app to ensure it doesn't continue running in background
      // This will effectively "close" the current session and return to AuthWrapper
      RestartWidget.restartApp(context);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
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


import 'package:flutter/material.dart';
import 'voice_call_screen.dart';
import 'dashboard_screen.dart';
import 'auth_service.dart';
import 'app_config.dart';
import 'user_management_dialog.dart';

/// HomeScreen displays main navigation with role-based features
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late AuthService _authService;
  String _username = '';
  String _role = '';
  bool _isHost = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _authService = AuthService(backendUrl: AppConfig.backendBaseUrl);
    _loadUserInfo();
  }

  /// Load authenticated user info
  Future<void> _loadUserInfo() async {
    final username = await _authService.getUsername();
    final role = await _authService.getRole();
    final isHost = await _authService.isHost();

    setState(() {
      _username = username ?? 'User';
      _role = role ?? 'user';
      _isHost = isHost;
      _isLoading = false;
    });
  }

  /// Handle logout
  Future<void> _handleLogout() async {
    await _authService.logout();
    
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  /// Show logout confirmation dialog
  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _handleLogout();
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agora Voice System'),
        elevation: 0,
        backgroundColor: Colors.blue.shade700,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Header Card with gradient
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade600, Colors.blue.shade800],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.shade300.withOpacity(0.5),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome, $_username!',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _isHost
                                    ? Colors.orange.shade400
                                    : Colors.grey.shade400,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _role.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.white),
                        tooltip: 'Logout',
                        onPressed: _showLogoutConfirmation,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_isHost)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.star, color: Colors.orange, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Host Mode - Full Access',
                            style: TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Quick Actions Section
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),

            // Voice Call Card
            _buildActionCard(
              icon: Icons.call,
              title: 'Voice Call',
              subtitle: 'Join or start a voice call',
              color: Colors.green,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const VoiceCallScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // Dashboard Card
            _buildActionCard(
              icon: Icons.dashboard,
              title: 'Dashboard',
              subtitle: _isHost
                  ? 'Manage sessions & recordings'
                  : 'View session details',
              color: Colors.purple,
              onTap: () async {
                final token = await _authService.getToken();

                if (mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DashboardScreen(
                        sessionId: 'test_room',
                        backendUrl: AppConfig.backendBaseUrl,
                        currentUserId: 1,
                        currentUsername: _username,
                        jwtToken: token,
                      ),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 12),

            // User Management (Host-Only)
            if (_isHost) ...[
              _buildActionCard(
                icon: Icons.group_add,
                title: 'User Management',
                subtitle: 'Create new session users',
                color: Colors.teal,
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => UserManagementDialog(
                      authService: _authService,
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
            ],

            // Features Section
            Text(
              'Available Features',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),

            // Feature Grid
            if (_isHost) ...[
              Row(
                children: [
                  Expanded(
                    child: _buildFeatureBox(
                      icon: Icons.fiber_manual_record,
                      title: 'Recording',
                      enabled: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildFeatureBox(
                      icon: Icons.people,
                      title: 'Users',
                      enabled: true,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: _buildFeatureBox(
                      icon: Icons.fiber_manual_record,
                      title: 'Recording',
                      enabled: false,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildFeatureBox(
                      icon: Icons.people,
                      title: 'Users',
                      enabled: false,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildFeatureBox(
                    icon: Icons.info,
                    title: 'Dashboard',
                    enabled: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildFeatureBox(
                    icon: Icons.security,
                    title: 'Auth',
                    enabled: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Security Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                border: Border.all(color: Colors.green.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lock, color: Colors.green.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Secure Session',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your connection is protected with JWT authentication. Token expires in 24 hours.',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Build action card (Voice Call, Dashboard, User Management)
  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: color.withOpacity(0.3), width: 2),
            borderRadius: BorderRadius.circular(12),
            color: color.withOpacity(0.05),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward, color: color),
            ],
          ),
        ),
      ),
    );
  }

  /// Build feature box (2x2 grid)
  Widget _buildFeatureBox({
    required IconData icon,
    required String title,
    required bool enabled,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: enabled ? Colors.blue.shade50 : Colors.grey.shade50,
        border: Border.all(
          color: enabled ? Colors.blue.shade300 : Colors.grey.shade300,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 32,
            color: enabled ? Colors.blue.shade600 : Colors.grey.shade400,
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: enabled ? Colors.blue.shade900 : Colors.grey.shade600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Icon(
            enabled ? Icons.check_circle : Icons.lock,
            size: 16,
            color: enabled ? Colors.green : Colors.grey,
          ),
        ],
      ),
    );
  }
}

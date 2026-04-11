import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'app_config.dart';
import 'admin_users_manager.dart';
import 'admin_recording_manager.dart';
import 'admin_dashboard.dart';

/// AdminScreen is the main admin dashboard for hosts
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late AuthService _authService;
  int _selectedIndex = 0;
  String _username = '';
  bool _isLoading = true;
  bool _isHost = false;

  @override
  void initState() {
    super.initState();
    _authService = AuthService(backendUrl: AppConfig.backendBaseUrl);
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    try {
      final username = await _authService.getUsername();
      final isHost = await _authService.isHost();

      if (!isHost) {
        // Not a host, redirect to home
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/home');
        }
        return;
      }

      setState(() {
        _username = username ?? 'Admin';
        _isHost = isHost;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleLogout() async {
    await _authService.logout();
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

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

    if (!_isHost) {
      return const Scaffold(
        body: Center(child: Text('Access Denied')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF2a2a2a),
      appBar: AppBar(
        title: const Text('Admin Control Panel'),
        backgroundColor: const Color(0xFF1a1a1a),
        elevation: 2,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Center(
              child: Text(
                'Welcome, $_username',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: GestureDetector(
              onTap: _showLogoutConfirmation,
              child: const Icon(Icons.logout),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Row(
          children: [
            // Sidebar navigation
            NavigationRail(
              backgroundColor: const Color(0xFF1a1a1a),
              selectedIndex: _selectedIndex,
              onDestinationSelected: (int index) {
                setState(() => _selectedIndex = index);
              },
              labelType: NavigationRailLabelType.selected,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.dashboard),
                  selectedIcon: Icon(Icons.dashboard, color: Colors.blue),
                  label: Text('Dashboard'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.people),
                  selectedIcon: Icon(Icons.people, color: Colors.blue),
                  label: Text('Users'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.videocam),
                  selectedIcon: Icon(Icons.videocam, color: Colors.blue),
                  label: Text('Recordings'),
                ),
              ],
            ),
            // Main content area
            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: const [
                  AdminDashboard(),
                  AdminUsersManager(),
                  AdminRecordingManager(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

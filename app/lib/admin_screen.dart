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

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late AuthService _authService;
  late TabController _tabController;
  String _username = '';
  bool _isLoading = true;
  bool _isHost = false;

  @override
  void initState() {
    super.initState();
    _authService = AuthService(backendUrl: AppConfig.backendBaseUrl);
    _tabController = TabController(length: 3, vsync: this);
    _loadUserInfo();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              icon: Icon(Icons.dashboard),
              text: 'Dashboard',
            ),
            Tab(
              icon: Icon(Icons.people),
              text: 'Users',
            ),
            Tab(
              icon: Icon(Icons.videocam),
              text: 'Recordings',
            ),
          ],
          indicatorColor: Colors.blue,
          labelColor: Colors.blue,
          unselectedLabelColor: Colors.white70,
          indicatorSize: TabBarIndicatorSize.label,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          AdminDashboard(),
          AdminUsersManager(),
          AdminRecordingManager(),
        ],
      ),
    );
  }
}

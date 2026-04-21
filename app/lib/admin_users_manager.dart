import 'package:flutter/material.dart';
import 'dart:convert';
import 'auth_service.dart';
import 'app_config.dart';

/// Admin users manager for creating and managing users
class AdminUsersManager extends StatefulWidget {
  const AdminUsersManager({super.key});

  @override
  State<AdminUsersManager> createState() => _AdminUsersManagerState();
}

class _AdminUsersManagerState extends State<AdminUsersManager> {
  late AuthService _authService;
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String _error = '';
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _authService = AuthService(backendUrl: AppConfig.backendBaseUrl);
    _loadUsers();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      setState(() {
        _isLoading = true;
        _error = '';
      });

      final response = await _authService
          .authenticatedGet('${AppConfig.backendBaseUrl}/users');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _users = List<Map<String, dynamic>>.from(data['users'] ?? []);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load users';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _createUser() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      _showSnackBar('Please fill in all fields', isError: true);
      return;
    }

    if (_passwordController.text.length < 6) {
      _showSnackBar('Password must be at least 6 characters', isError: true);
      return;
    }

    setState(() => _isCreating = true);

    try {
      final result = await _authService.createUser(
        _usernameController.text,
        _passwordController.text,
      );

      if (result) {
        _showSnackBar('User created successfully!');
        _usernameController.clear();
        _passwordController.clear();
        await _loadUsers();
        if (mounted) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      _showSnackBar('Error: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  void _showCreateUserDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New User'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Username',
                  hintText: 'Enter username',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  hintText: 'Enter password (min 6 chars)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _usernameController.clear();
              _passwordController.clear();
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _isCreating ? null : _createUser,
            child: _isCreating
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'User Management',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Create and manage users',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // ✅ FIXED: Wrap buttons with Flexible constraint
              Flexible(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _showCreateUserDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Create User'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _loadUsers,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Error message
          if (_error.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.shade900.withValues(alpha: 0.3),
                border: Border.all(color: Colors.red.shade700),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _error,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),

          if (_error.isEmpty) ...[
            const SizedBox(height: 20),

            // Users list
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_users.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(40.0),
                  child: Column(
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 48,
                        color: Colors.white30,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No users found',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF3a3a3a),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: DataTable(
                  columnSpacing: 20,
                  headingRowHeight: 56,
                  dataRowHeight: 60,
                  columns: const [
                    DataColumn(
                      label: Text(
                        'Username',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'Role',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'Created',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                  rows: _users.map((user) {
                    final createdAt = user['createdAt'] as String?;
                    final formattedDate = createdAt != null
                        ? DateTime.parse(createdAt)
                            .toString()
                            .split('.')
                            .first
                        : 'N/A';

                    return DataRow(
                      cells: [
                        DataCell(
                          Text(
                            user['username'] ?? 'Unknown',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: user['role'] == 'host'
                                  ? Colors.orange.withValues(alpha: 0.2)
                                  : Colors.blue.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              user['role'] ?? 'user',
                              style: TextStyle(
                                color: user['role'] == 'host'
                                    ? Colors.orange
                                    : Colors.blue,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            formattedDate,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

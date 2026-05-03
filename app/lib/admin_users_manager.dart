import 'dart:async';
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
        if (mounted) {
          setState(() {
            _users = List<Map<String, dynamic>>.from((data['users'] as Iterable?) ?? []);
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Failed to load users';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _createUser() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      _showSnackBar('Please fill in all fields', isError: true);
      return;
    }

    if (_passwordController.text.length < 4) {
      _showSnackBar('Password must be at least 4 characters', isError: true);
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

  Future<void> _deleteUser(String userId, String username) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _DeleteConfirmDialog(
        username: username,
        onSnackBar: (msg, isErr) => _showSnackBar(msg, isError: isErr),
      ),
    );

    if (confirmed == true) {
      try {
        final success = await _authService.deleteUser(userId);
        if (success) {
          _showSnackBar('User deleted successfully');
          unawaited(_loadUsers());
        }
      } catch (e) {
        _showSnackBar('Error: $e', isError: true);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    try {
      // Use findAncestorStateOfType instead of maybeOf to avoid registering a dependency.
      // This prevents "InheritedElement.debugDeactivated: _dependents.isEmpty is not true"
      // assertion failures when the widget is being unmounted.
      final messenger = context.findAncestorStateOfType<ScaffoldMessengerState>();
      if (messenger != null) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: isError ? Colors.red : Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error showing snackbar: $e');
    }
  }

  void _showCreateUserDialog() {
    unawaited(showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New User'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  hintText: 'Enter username',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  hintText: 'Enter password (min 4 chars)',
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
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create'),
          ),
        ],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'User Management',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
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
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40.0),
                  child: Column(
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 48,
                        color: Colors.white30,
                      ),
                      SizedBox(height: 16),
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
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF3a3a3a),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: DataTable(
                    columnSpacing: 20,
                    headingRowHeight: 56,
                    dataRowMinHeight: 48,
                    dataRowMaxHeight: 64,
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
                          'Actions',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                    rows: _users.map((user) => DataRow(
                        cells: [
                          DataCell(
                            Text(
                              (user['username'] ?? 'Unknown') as String,
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
                                (user['role'] ?? 'user') as String,
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
                            user['role'] == 'host'
                                ? const SizedBox.shrink()
                                : IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                                    onPressed: () => _deleteUser(user['id'] as String, (user['username'] ?? 'Unknown') as String),
                                    tooltip: 'Delete User',
                                  ),
                          ),
                        ],
                      )).toList(),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
}

/// Dedicated dialog to manage its own TextEditingController lifecycle
class _DeleteConfirmDialog extends StatefulWidget {
  final String username;
  final void Function(String, bool) onSnackBar;

  const _DeleteConfirmDialog({
    required this.username,
    required this.onSnackBar,
  });

  @override
  State<_DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends State<_DeleteConfirmDialog> {
  final _pinController = TextEditingController();
  bool _isVerifying = false;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _verifyAndProceed() async {
    if (_pinController.text.isEmpty) return;

    setState(() => _isVerifying = true);

    try {
      final authService = AuthService(backendUrl: AppConfig.backendBaseUrl);
      final response = await authService.authenticatedPost(
        '${AppConfig.backendBaseUrl}/auth/verify-pin',
        body: {'pin': _pinController.text},
      );

      if (response.statusCode == 200) {
        if (mounted) Navigator.pop(context, true);
      } else {
        final error = jsonDecode(response.body);
        widget.onSnackBar(error['message'] ?? '❌ Invalid PIN', true);
      }
    } catch (e) {
      widget.onSnackBar('❌ Verification error: $e', true);
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
      title: const Text('Confirm Deletion'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Are you sure you want to delete user "${widget.username}"?'),
          const SizedBox(height: 20),
          const Text(
            'Enter Admin PIN to confirm:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _pinController,
            decoration: const InputDecoration(
              hintText: 'Enter PIN',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock_outline, size: 20),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            keyboardType: TextInputType.number,
            obscureText: true,
            autofocus: true,
            onSubmitted: (_) => _verifyAndProceed(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isVerifying ? null : _verifyAndProceed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: _isVerifying
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Delete User'),
        ),
      ],
    );
}

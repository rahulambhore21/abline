import 'package:flutter/material.dart';
import 'user.dart';

class UserListWidget extends StatelessWidget {
  final List<User> users;

  const UserListWidget({
    super.key,
    required this.users,
  });

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return const Text(
        'No users in session',
        style: TextStyle(color: Colors.grey),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              // Speaking status indicator
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: user.isSpeaking ? Colors.green : Colors.grey,
                ),
              ),
              const SizedBox(width: 12),

              // User info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.username,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'ID: ${user.userId}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),

              // Speaking status text
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: user.isSpeaking ? Colors.green.shade100 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  user.isSpeaking ? 'Speaking' : 'Silent',
                  style: TextStyle(
                    fontSize: 12,
                    color: user.isSpeaking ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

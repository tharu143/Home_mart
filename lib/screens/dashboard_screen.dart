import 'package:flutter/material.dart';
import 'package:home_mart/error_handler.dart'; // Import error handler

class DashboardScreen extends StatelessWidget {
  final String serverUrl;
  final String sid;
  final String fullName;

  const DashboardScreen({
    super.key,
    required this.serverUrl,
    required this.sid,
    required this.fullName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Mart Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Logout',
            onPressed: () {
              // Navigate back to login screen
              Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFE0F7FA), // Light teal
              Color(0xFFF5F9FF), // Light neutral white
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Display full name and SID
              Card(
                margin: const EdgeInsets.only(bottom: 20.0),
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome to Home Mart, $fullName!',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      // Text(
                      //   'Session ID: $sid',
                      //   style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      //     color: Colors.grey[700],
                      //   ),
                      // ),
                      // const SizedBox(height: 4),
                      // Text(
                      //   'Server URL: $serverUrl',
                      //   style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      //     color: Colors.grey[700],
                      //   ),
                      // ),
                    ],
                  ),
                ),
              ),
              // Quotations Feature Card
              _buildFeatureCard(
                context,
                icon: Icons.receipt_long,
                title: 'Manage Quotations',
                subtitle: 'View, create, and edit customer quotations.',
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    '/quotation_list',
                    arguments: {'sid': sid, 'serverUrl': serverUrl},
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDisabled = false,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Opacity(
            opacity: isDisabled ? 0.6 : 1.0,
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 40,
                  color: isDisabled
                      ? Colors.grey
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: isDisabled ? Colors.grey[600] : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isDisabled
                              ? Colors.grey[500]
                              : Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: isDisabled
                      ? Colors.grey
                      : Theme.of(context).colorScheme.secondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

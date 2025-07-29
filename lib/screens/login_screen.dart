import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:home_mart/error_handler.dart'; // Import the error handler

class LoginScreen extends StatefulWidget {
  final String serverUrl;
  const LoginScreen({super.key, required this.serverUrl});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse("${widget.serverUrl}/api/method/login"),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'usr': _usernameController.text,
          'pwd': _passwordController.text,
        }),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        if (jsonResponse['message'] == 'Logged In') {
          // Extract the SID from the response headers
          String? sid;
          String? fullName =
              jsonResponse['full_name'] ??
              'User'; // Fetch full name from response
          final setCookieHeader = response.headers['set-cookie'];
          if (setCookieHeader != null) {
            // Parse cookies to find the 'sid'
            final cookies = setCookieHeader.split(';');
            for (var cookie in cookies) {
              final parts = cookie.trim().split('=');
              if (parts.length == 2 && parts[0] == 'sid') {
                sid = parts[1];
                break;
              }
            }
          }

          if (sid != null && sid.isNotEmpty) {
            // Navigate to Dashboard and pass the SID and full name
            Navigator.pushReplacementNamed(
              context,
              '/dashboard',
              arguments: {
                'sid': sid,
                'fullName': fullName,
                'serverUrl': widget.serverUrl,
              },
            );
          } else {
            showErrorDialog(
              context,
              'Login Error',
              'Session ID (SID) not found.',
            );
          }
        } else {
          showErrorDialog(context, 'Login Failed', 'Invalid credentials.');
        }
      } else {
        // Use the error handler for API responses
        showApiErrorDialog(
          context,
          statusCode: response.statusCode,
          message: response.body,
        );
      }
    } catch (e) {
      showErrorDialog(
        context,
        'Network Error',
        'Could not connect to the server: $e',
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 400;

    // Assuming logo.jpg dimensions (adjust these based on actual image size)
    const double logoWidth = 300; // Example width of logo.jpg
    const double logoHeight = 200; // Example height of logo.jpg

    return Scaffold(
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
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isSmallScreen ? 16.0 : 24.0),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  padding: EdgeInsets.all(isSmallScreen ? 20.0 : 32.0),
                  width: isSmallScreen ? screenWidth * 0.9 : 400,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Plain Logo Display
                        Container(
                          padding: const EdgeInsets.all(8.0),
                          color: Colors.white,
                          child: Image.asset(
                            'assets/images/logo.jpg', // Ensure this path is correct and asset is added to pubspec.yaml
                            width: double.infinity,
                            height:
                                (logoHeight / logoWidth) *
                                (isSmallScreen ? 200 : 240),
                            fit: BoxFit.contain,
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 20 : 32),
                        // Username Field
                        TextFormField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            labelText: 'Username',
                            labelStyle: const TextStyle(
                              color: Color(0xFF003366),
                              fontWeight: FontWeight.w500,
                            ),
                            prefixIcon: const Icon(
                              Icons.person_outline,
                              color: Color(0xFF00B4D8),
                              size: 24,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFFDDDDDD),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFF00B4D8),
                                width: 2,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFFDDDDDD),
                              ),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 12,
                            ),
                          ),
                          validator: (value) =>
                              value!.isEmpty ? 'Username required' : null,
                        ),
                        SizedBox(height: isSmallScreen ? 12 : 16),
                        // Password Field
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            labelStyle: const TextStyle(
                              color: Color(0xFF003366),
                              fontWeight: FontWeight.w500,
                            ),
                            prefixIcon: const Icon(
                              Icons.lock_outline,
                              color: Color(0xFF00B4D8),
                              size: 24,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFFDDDDDD),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFF00B4D8),
                                width: 2,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFFDDDDDD),
                              ),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 12,
                            ),
                          ),
                          validator: (value) =>
                              value!.isEmpty ? 'Password required' : null,
                        ),
                        SizedBox(height: isSmallScreen ? 20 : 24),
                        // Sign In Button
                        ElevatedButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00B4D8),
                            padding: EdgeInsets.symmetric(
                              vertical: isSmallScreen ? 12 : 16,
                              horizontal: isSmallScreen ? 24 : 32,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Sign In',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

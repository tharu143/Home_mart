import 'package:flutter/material.dart';
import 'package:home_mart/screens/login_screen.dart';
import 'package:home_mart/screens/dashboard_screen.dart';
import 'package:home_mart/screens/quotation_list_screen.dart';
import 'package:home_mart/screens/quotation_screen.dart';
import 'package:home_mart/screens/quotation_detail_screen.dart';

void main() {
  runApp(const HomeMartApp());
}

class HomeMartApp extends StatelessWidget {
  const HomeMartApp({super.key});
  // Define the common server URL for the application
  static const String serverUrl = "http://128.199.27.173";

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Home Mart', // New app name
      theme: ThemeData(
        // Define a consistent color scheme for the app for an attractive design
        primaryColor: const Color(0xFF005BAC), // A deep blue for primary actions and app bars
        colorScheme: ColorScheme.fromSwatch().copyWith(
          secondary: const Color(0xFF00B4D8), // A vibrant teal for accents and interactive elements
          surface: const Color(0xFFF5F9FF), // A light neutral white for backgrounds
          onSurface: const Color(0xFF333333), // Dark grey for general text
          error: const Color(0xFFF44336), // Red for error states
        ),
        scaffoldBackgroundColor: const Color(0xFFE0F7FA), // Light teal for default screen backgrounds
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF005BAC),
          foregroundColor: Colors.white,
          elevation: 4,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontFamily: 'Dubai',
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        fontFamily: 'Dubai', // Set Dubai as the default font family
        textTheme: const TextTheme(
          titleLarge: TextStyle(
            fontFamily: 'Dubai',
            fontWeight: FontWeight.bold,
            color: Color(0xFF003366),
          ),
          bodyMedium: TextStyle(fontFamily: 'Dubai', color: Color(0xFF333333)),
          labelLarge: TextStyle(
            fontFamily: 'Dubai',
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        buttonTheme: ButtonThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          buttonColor: const Color(0xFF00B4D8),
          textTheme: ButtonTextTheme.primary,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00B4D8),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            elevation: 4,
            textStyle: const TextStyle(
              fontFamily: 'Dubai',
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          labelStyle: const TextStyle(
            fontFamily: 'Dubai',
            color: Color(0xFF005BAC),
          ),
          hintStyle: const TextStyle(
            fontFamily: 'Dubai',
            color: Color(0xFF757575),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF005BAC), width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 12,
          ),
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const LoginScreen(serverUrl: serverUrl),
        // Pass SID and fullName to Dashboard Screen
        '/dashboard': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
          if (args == null || args['sid'] == null || (args['sid'] as String).isEmpty) {
            // Redirect to login if sid is missing
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.pushReplacementNamed(context, '/');
            });
            return const LoginScreen(serverUrl: serverUrl); // Fallback widget
          }
          return DashboardScreen(
            serverUrl: serverUrl,
            sid: args['sid'] as String,
            fullName: args['fullName'] as String? ?? 'User',
          );
        },
        // Pass SID to Quotation List Screen
        '/quotation_list': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
          if (args == null || args['sid'] == null || (args['sid'] as String).isEmpty) {
            // Redirect to login if sid is missing
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.pushReplacementNamed(context, '/');
            });
            return const LoginScreen(serverUrl: serverUrl); // Fallback widget
          }
          return QuotationListScreen(
            serverUrl: serverUrl,
            sid: args['sid'] as String,
          );
        },
        // Pass SID to Quotation Creation Screen
        '/quotation': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
          if (args == null || args['sid'] == null || (args['sid'] as String).isEmpty) {
            // Redirect to login if sid is missing
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.pushReplacementNamed(context, '/');
            });
            return const LoginScreen(serverUrl: serverUrl); // Fallback widget
          }
          return QuotationScreen(
            serverUrl: serverUrl,
            sid: args['sid'] as String,
            initialData: args['initialData'],
          );
        },
        // Pass SID and initialData to Quotation Detail Screen
        '/quotation_detail': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
          if (args == null || args['sid'] == null || (args['sid'] as String).isEmpty) {
            // Redirect to login if sid is missing
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.pushReplacementNamed(context, '/');
            });
            return const LoginScreen(serverUrl: serverUrl); // Fallback widget
          }
          return QuotationDetailScreen(
            serverUrl: serverUrl,
            sid: args['sid'] as String,
            // Optionally pass initialData if editing an existing quotation
            // initialData: args['initialData'],
          );
        },
      },
    );
  }
}
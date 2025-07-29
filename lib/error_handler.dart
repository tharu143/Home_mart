import 'package:flutter/material.dart';
import 'dart:convert';

/// Parses the Frappe exception to get a user-friendly message.
/// Frappe can return errors in different keys like 'exception', '_server_messages', or 'message'.
/// This function intelligently finds the most relevant one.
String _parseFrappeException(String responseBody) {
  try {
    final data = json.decode(responseBody);

    // 1. Check for 'exception' key (most specific)
    if (data['exception'] != null && data['exception'] is String) {
      // Often contains a technical prefix, e.g., "frappe.exceptions.ValidationError: ..."
      // We split it to get the actual message part.
      List<String> parts = data['exception'].split(':');
      if (parts.length > 1) {
        return parts.sublist(1).join(':').trim();
      }
      return data['exception'];
    }

    // 2. Check for '_server_messages' key
    if (data['_server_messages'] != null) {
      // These are usually a JSON string array, so we decode it again.
      final serverMessages = json.decode(data['_server_messages']);
      if (serverMessages is List && serverMessages.isNotEmpty) {
        // Join all server messages into a single readable string.
        return serverMessages
            .map((msg) => json.decode(msg)['message'].toString())
            .join('\n');
      }
    }

    // 3. Check for a simple 'message' key
    if (data['message'] != null && data['message'] is String) {
      return data['message'];
    }

    // 4. Fallback to the full response if no specific message is found
    return responseBody;
  } catch (e) {
    // If the response is not a valid JSON, return the raw text.
    return responseBody;
  }
}

/// Removes any remaining HTML tags from a string to keep the output clean.
String _stripHtmlIfNeeded(String text) {
  return text.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), ' ').trim();
}

/// Returns a user-friendly message in English based on the HTTP status code.
String getUserFriendlyMessage(int statusCode, String message) {
  // First, parse the message to get the core error from Frappe.
  final cleanMessage = _stripHtmlIfNeeded(_parseFrappeException(message));

  switch (statusCode) {
    case 200:
      return "Success: $cleanMessage";
    case 400:
      return "Bad Request: Please check your input. $cleanMessage";
    case 401:
      return "Unauthorized: Please check your credentials or session. $cleanMessage";
    case 403:
      return "Forbidden: You do not have permission to perform this action. $cleanMessage";
    case 404:
      return "Not Found: The requested resource could not be found. $cleanMessage";
    case 409:
      return "Conflict: The resource already exists or there is a conflict. $cleanMessage";
    case 417:
      return "Expectation Failed: The server could not meet the expectation. $cleanMessage";
    case 422:
      return "Unprocessable Entity: Please check the data you provided. $cleanMessage";
    case 500:
      return "Internal Server Error: Something went wrong on the server. Please try again later. $cleanMessage";
    default:
      return "An unexpected error occurred (Status Code: $statusCode). $cleanMessage";
  }
}

/// Shows a generic error dialog with a title and message.
void showErrorDialog(BuildContext context, String title, String message) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge!.copyWith(
          color: Colors.red.shade700,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
      content: Text(
        // Ensure the final message is clean of HTML tags
        _stripHtmlIfNeeded(message),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'OK',
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
        ),
      ],
    ),
  );
}

/// Shows a user-friendly error dialog specifically for API responses.
void showApiErrorDialog(
  BuildContext context, {
  int? statusCode,
  String message = "An unknown error occurred.",
}) {
  String friendlyMessage;
  if (statusCode != null) {
    // Get a friendly message based on the status code and parsed Frappe message
    friendlyMessage = getUserFriendlyMessage(statusCode, message);
  } else {
    // If there's no status code, just parse and clean the message
    friendlyMessage = _stripHtmlIfNeeded(_parseFrappeException(message));
  }
  showErrorDialog(context, 'Error', friendlyMessage);
}

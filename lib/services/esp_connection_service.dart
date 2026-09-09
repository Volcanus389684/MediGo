import 'dart:async';

import 'package:http/http.dart' as http;

/// Outcome of a real WiFi request to the ESP32 dispenser.
class EspConnectionResult {
  const EspConnectionResult({required this.success, required this.message});

  final bool success;
  final String message;
}

/// Talks to the ESP32 dispenser over the local WiFi network using the
/// address (IP, hostname, or MAC) read from the QR code stuck on the bus.
/// A MAC address alone cannot be reached over HTTP, so callers get a clear
/// message telling them an IP/hostname is required.
class EspConnectionService {
  EspConnectionService._();

  static final EspConnectionService instance = EspConnectionService._();

  static const Duration _timeout = Duration(seconds: 6);
  static final RegExp _macPattern = RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$');

  bool looksLikeMac(String address) => _macPattern.hasMatch(address.trim());

  String normalizeHost(String raw) {
    var value = raw.trim();
    value = value.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    value = value.split('/').first;
    return value;
  }

  Future<EspConnectionResult> testConnection(String address) => _request(address, path: '/status');

  Future<EspConnectionResult> sendCommand({required String address, required String command}) =>
      _request(address, path: '/dispense', query: {'command': command});

  Future<EspConnectionResult> _request(String address, {required String path, Map<String, String>? query}) async {
    final trimmed = address.trim();
    if (trimmed.isEmpty) {
      return const EspConnectionResult(success: false, message: 'No dispenser is paired yet. Scan the QR code on the bus first.');
    }
    if (looksLikeMac(trimmed)) {
      return EspConnectionResult(success: false, message: 'The paired address ($trimmed) is a MAC address. The dispenser needs an IP address or hostname to connect over WiFi.');
    }

    final host = normalizeHost(trimmed);
    final uri = Uri.http(host, path, query);
    try {
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return EspConnectionResult(success: true, message: 'Dispenser at $host responded successfully.');
      }
      return EspConnectionResult(success: false, message: 'Dispenser at $host returned an error (HTTP ${response.statusCode}).');
    } on TimeoutException {
      return EspConnectionResult(success: false, message: 'Could not reach the dispenser at $host. It did not respond in time.');
    } catch (error) {
      return EspConnectionResult(success: false, message: 'Could not reach the dispenser at $host. $error');
    }
  }
}

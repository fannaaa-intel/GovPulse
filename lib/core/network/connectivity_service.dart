import 'dart:io';

/// Checks whether the device has real internet access
/// by pinging a known lightweight endpoint.
Future<bool> hasRealInternet() async {
  try {
    return await _pingEndpoint(
      'https://clients3.google.com/generate_204',
    ).timeout(const Duration(seconds: 8));
  } catch (_) {
    return false;
  }
}

Future<bool> _pingEndpoint(String url) async {
  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    await response.drain();
    return response.statusCode < 500;
  } catch (_) {
    return false;
  }
}

import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/restaurant.dart';

class ClaudeService {
  static const apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://39feutdvbj.execute-api.us-east-1.amazonaws.com//ai',
  );

  static Future<String> chat({
    required String question,
    required LatLng userLocation,
    required List<Restaurant> restaurants,
    required List<Map<String, String>> history,
  }) async {
    final locationStr =
        '${userLocation.latitude.toStringAsFixed(4)}, ${userLocation.longitude.toStringAsFixed(4)}';

    final restaurantList = restaurants.take(30).map((r) {
      final dist = _distKm(userLocation, LatLng(r.lat, r.lng));
      final parts = [
        r.emoji,
        r.name,
        '(${dist.toStringAsFixed(1)} km)',
        '-',
        r.displayType,
        if (r.cuisine != null) '· ${r.cuisine}',
        if (r.address != null) '· ${r.address}',
      ];
      return parts.join(' ');
    }).join('\n');

    final res = await http
        .post(
          Uri.parse(apiUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'question': question,
            'location': locationStr,
            'restaurants': restaurantList.isEmpty
                ? 'No restaurants loaded yet.'
                : restaurantList,
            'history': history,
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (res.statusCode == 200) {
      return (jsonDecode(res.body) as Map<String, dynamic>)['content'] as String;
    }
    throw Exception('AI request failed: ${res.statusCode}');
  }

  static double _distKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _rad(b.latitude - a.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(a.latitude)) *
            cos(_rad(b.latitude)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return r * 2 * asin(sqrt(h));
  }

  static double _rad(double deg) => deg * pi / 180;
}

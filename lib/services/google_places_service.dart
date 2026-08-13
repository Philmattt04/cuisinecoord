import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/restaurant.dart';

class GooglePlacesService {
  // All Places calls go through Lambda — no CORS issues, key stays server-side.
  static const _baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://39feutdvbj.execute-api.us-east-1.amazonaws.com',
  );

  static String get _restaurantsUrl => '$_baseUrl/restaurants';
  static String get _detailsUrl => '$_baseUrl/place-details';

  // Always available — Lambda checks if GOOGLE_PLACES_KEY is set server-side.
  static bool get hasKey => true;

  // ── Nearby search ─────────────────────────────────────────────────────────

  static Future<List<Restaurant>> nearbySearch(
    double lat,
    double lng, {
    int radius = 2500,
  }) async {
    final res = await http
        .post(
          Uri.parse(_restaurantsUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'lat': lat, 'lng': lng, 'radius': radius}),
        )
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      throw Exception('Restaurant fetch failed: ${res.statusCode} ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['error'] != null) {
      throw Exception(data['error'].toString());
    }

    final places = (data['places'] as List?) ?? [];
    return places
        .cast<Map<String, dynamic>>()
        .map(Restaurant.fromNewPlacesApi)
        .toList();
  }

  // ── Place details ─────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> placeDetails(String placeId) async {
    final res = await http
        .post(
          Uri.parse(_detailsUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'placeId': placeId}),
        )
        .timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['error'] != null ? null : data;
  }
}

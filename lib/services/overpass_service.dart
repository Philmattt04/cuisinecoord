import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/restaurant.dart';

class OverpassService {
  static const _url = 'https://overpass-api.de/api/interpreter';

  static Future<List<Restaurant>> fetchNearby(
    double lat,
    double lng, {
    int radius = 2500,
  }) async {
    final query = '''
[out:json][timeout:30];
(
  node["amenity"~"^(restaurant|cafe|fast_food|bar|pub|food_court|ice_cream)\$"]["name"](around:$radius,$lat,$lng);
  way["amenity"~"^(restaurant|cafe|fast_food|bar|pub|food_court)\$"]["name"](around:$radius,$lat,$lng);
);
out center qt 200;
''';

    final res = await http.post(
      Uri.parse(_url),
      body: {'data': query},
    ).timeout(const Duration(seconds: 30));

    if (res.statusCode != 200) {
      throw Exception('Overpass API error: ${res.statusCode}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final elements = (data['elements'] as List?) ?? [];

    return elements
        .where((e) {
          final tags = (e['tags'] as Map?) ?? {};
          return tags['name'] != null;
        })
        .map((e) => Restaurant.fromOverpass(e as Map<String, dynamic>))
        .toList();
  }
}

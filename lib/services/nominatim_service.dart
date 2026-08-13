import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

class NominatimService {
  static const _url = 'https://nominatim.openstreetmap.org/search';

  static Future<({LatLng coords, String displayName})?> geocode(
      String location) async {
    final uri = Uri.parse(_url).replace(queryParameters: {
      'q': location,
      'format': 'json',
      'limit': '1',
      'addressdetails': '0',
    });

    final res = await http.get(uri, headers: {
      'User-Agent': 'CuisineCoord/1.0 (com.philmathieu.cuisinecoord)',
    }).timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) return null;

    final data = jsonDecode(res.body) as List;
    if (data.isEmpty) return null;

    final item = data[0] as Map<String, dynamic>;
    return (
      coords: LatLng(
        double.parse(item['lat'] as String),
        double.parse(item['lon'] as String),
      ),
      displayName: (item['display_name'] as String).split(',').take(2).join(', '),
    );
  }
}

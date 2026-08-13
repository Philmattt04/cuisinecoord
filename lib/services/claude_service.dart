import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import '../models/restaurant.dart';
import '../models/user_data.dart';

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
    Restaurant? focusedRestaurant,
    Restaurant? compareRestaurant,
    List<DiningVisit> diningHistory = const [],
    String? currentDateTime,
  }) async {
    final locationStr =
        '${userLocation.latitude.toStringAsFixed(4)}, ${userLocation.longitude.toStringAsFixed(4)}';

    final restaurantList = restaurants.take(30).map((r) {
      final dist = _distMiles(userLocation, LatLng(r.lat, r.lng));
      return [
        r.name,
        '(${dist.toStringAsFixed(1)} mi)',
        '-', r.displayType,
        if (r.cuisine != null) '· ${r.cuisine}',
        if (r.rating != null) '· ⭐ ${r.rating!.toStringAsFixed(1)}',
        if (r.priceLevelStr.isNotEmpty) '· ${r.priceLevelStr}',
        if (r.isOpenNow != null) '· ${r.isOpenNow! ? "Open" : "Closed"}',
      ].join(' ');
    }).join('\n');

    // Focused restaurant with reviews
    String? focusedContext;
    if (focusedRestaurant != null) {
      final r = focusedRestaurant;
      final dist = _distMiles(userLocation, LatLng(r.lat, r.lng));
      final reviewSection = r.reviews.isNotEmpty
          ? '\nGoogle Reviews:\n' +
              r.reviews
                  .map((rev) =>
                      '  • ${rev.authorName} ${'⭐' * rev.rating} (${rev.relativeTime}): "${rev.text.length > 200 ? '${rev.text.substring(0, 200)}…' : rev.text}"')
                  .join('\n')
          : '\nNo reviews loaded.';

      final personalSection = diningHistory.isNotEmpty
          ? '\nMy personal visits:\n' +
              diningHistory
                  .map((v) =>
                      '  • ${v.visitedAt.toLocal().toString().substring(0, 10)}'
                      '${v.personalRating != null ? " — ${'⭐' * v.personalRating!}" : ""}'
                      '${v.note != null && v.note!.isNotEmpty ? " — ${v.note}" : ""}')
                  .join('\n')
          : '';

      focusedContext = '''
Currently selected restaurant:
Name: ${r.name}  |  Type: ${r.displayType}${r.cuisine != null ? ' (${r.cuisine})' : ''}
Distance: ${dist.toStringAsFixed(2)} mi  |  Rating: ${r.rating != null ? '${r.rating!.toStringAsFixed(1)}/5 (${r.userRatingsTotal ?? 0} reviews)' : 'Not rated'}
Price: ${r.priceLevelStr.isEmpty ? 'Unknown' : r.priceLevelStr}  |  Open: ${r.isOpenNow == null ? 'Unknown' : (r.isOpenNow! ? 'Yes' : 'No')}
Address: ${r.address ?? 'Not listed'}  |  Phone: ${r.phone ?? 'Not listed'}
Website: ${r.website ?? 'Not listed'}  |  Hours: ${r.openingHours ?? 'Not listed'}
$reviewSection$personalSection''';
    }

    // Compare restaurant context
    String? compareContext;
    if (compareRestaurant != null) {
      final r = compareRestaurant;
      final dist = _distMiles(userLocation, LatLng(r.lat, r.lng));
      compareContext = '''
Compare with:
Name: ${r.name}  |  Type: ${r.displayType}${r.cuisine != null ? ' (${r.cuisine})' : ''}
Distance: ${dist.toStringAsFixed(2)} mi  |  Rating: ${r.rating != null ? '${r.rating!.toStringAsFixed(1)}/5 (${r.userRatingsTotal ?? 0} reviews)' : 'Not rated'}
Price: ${r.priceLevelStr.isEmpty ? 'Unknown' : r.priceLevelStr}  |  Open: ${r.isOpenNow == null ? 'Unknown' : (r.isOpenNow! ? 'Yes' : 'No')}
Address: ${r.address ?? 'Not listed'}''';
    }

    final res = await http
        .post(
          Uri.parse(apiUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'question': question,
            'location': locationStr,
            'restaurants': restaurantList.isEmpty ? 'No restaurants loaded yet.' : restaurantList,
            'focusedRestaurant': focusedContext,
            'compareRestaurant': compareContext,
            'currentDateTime': currentDateTime,
            'history': history,
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (res.statusCode == 200) {
      return (jsonDecode(res.body) as Map<String, dynamic>)['content'] as String;
    }
    throw Exception('AI request failed: ${res.statusCode}');
  }

  static double _distMiles(LatLng a, LatLng b) {
    const r = 3958.8; // Earth radius in miles
    final dLat = _rad(b.latitude - a.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(a.latitude)) * cos(_rad(b.latitude)) *
            sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * asin(sqrt(h));
  }

  static double _rad(double deg) => deg * pi / 180;
}

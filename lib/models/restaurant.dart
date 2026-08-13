import 'package:flutter/material.dart';

class PlaceReview {
  final String authorName;
  final int rating;
  final String text;
  final String relativeTime;

  const PlaceReview({
    required this.authorName,
    required this.rating,
    required this.text,
    required this.relativeTime,
  });

  factory PlaceReview.fromJson(Map<String, dynamic> j) => PlaceReview(
        authorName: j['author_name'] as String? ?? 'Anonymous',
        rating: (j['rating'] as num?)?.toInt() ?? 3,
        text: j['text'] as String? ?? '',
        relativeTime: j['relative_time_description'] as String? ?? '',
      );
}

class Restaurant {
  final String id;           // Google place_id
  final String name;
  final double lat;
  final double lng;
  final String amenity;
  final String? cuisine;
  final String? address;
  final String? phone;
  final String? website;
  final String? openingHours;
  final bool? isOpenNow;
  final double? rating;
  final int? userRatingsTotal;
  final int? priceLevel;     // 0–4 (Free → $$$$)
  final List<PlaceReview> reviews;

  const Restaurant({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.amenity,
    this.cuisine,
    this.address,
    this.phone,
    this.website,
    this.openingHours,
    this.isOpenNow,
    this.rating,
    this.userRatingsTotal,
    this.priceLevel,
    this.reviews = const [],
  });

  Restaurant copyWithDetails({
    String? phone,
    String? website,
    String? openingHours,
    bool? isOpenNow,
    double? rating,
    int? userRatingsTotal,
    int? priceLevel,
    List<PlaceReview>? reviews,
  }) =>
      Restaurant(
        id: id,
        name: name,
        lat: lat,
        lng: lng,
        amenity: amenity,
        cuisine: cuisine,
        address: address,
        phone: phone ?? this.phone,
        website: website ?? this.website,
        openingHours: openingHours ?? this.openingHours,
        isOpenNow: isOpenNow ?? this.isOpenNow,
        rating: rating ?? this.rating,
        userRatingsTotal: userRatingsTotal ?? this.userRatingsTotal,
        priceLevel: priceLevel ?? this.priceLevel,
        reviews: reviews ?? this.reviews,
      );

  String get priceLevelStr {
    if (priceLevel == null) return '';
    return List.filled(priceLevel! + 1, '\$').join();
  }

  String get emoji {
    final c = (cuisine ?? '').toLowerCase();
    final a = amenity.toLowerCase();
    if (c.contains('pizza')) return '🍕';
    if (c.contains('sushi') || c.contains('japanese')) return '🍣';
    if (c.contains('chinese') || c.contains('asian')) return '🍜';
    if (c.contains('italian')) return '🍝';
    if (c.contains('mexican')) return '🌮';
    if (c.contains('burger') || c.contains('american')) return '🍔';
    if (c.contains('indian')) return '🍛';
    if (c.contains('thai')) return '🍲';
    if (a == 'cafe') return '☕';
    if (a == 'fast_food') return '🍔';
    if (a == 'bar' || a == 'pub') return '🍺';
    if (a == 'ice_cream') return '🍦';
    return '🍽️';
  }

  Color get markerColor {
    switch (amenity) {
      case 'cafe':
        return const Color(0xFFf59e0b);
      case 'fast_food':
        return const Color(0xFFef4444);
      case 'bar':
      case 'pub':
        return const Color(0xFF8b5cf6);
      case 'ice_cream':
        return const Color(0xFFec4899);
      default:
        return const Color(0xFFFF6535);
    }
  }

  String get displayType {
    if (cuisine != null && cuisine!.isNotEmpty) {
      return cuisine![0].toUpperCase() + cuisine!.substring(1);
    }
    switch (amenity) {
      case 'cafe':
        return 'Café';
      case 'fast_food':
        return 'Fast Food';
      case 'bar':
        return 'Bar';
      case 'pub':
        return 'Pub';
      default:
        return 'Restaurant';
    }
  }

  // ── Overpass (OSM) fallback factory ──────────────────────────────────────

  factory Restaurant.fromOverpass(Map<String, dynamic> e) {
    final tags = (e['tags'] as Map?)?.cast<String, dynamic>() ?? {};
    double lat, lng;
    if (e['type'] == 'way' && e['center'] != null) {
      final c = e['center'] as Map;
      lat = (c['lat'] as num).toDouble();
      lng = (c['lon'] as num).toDouble();
    } else {
      lat = (e['lat'] as num).toDouble();
      lng = (e['lon'] as num).toDouble();
    }
    final parts = [
      tags['addr:housenumber'] as String? ?? '',
      tags['addr:street'] as String? ?? '',
      tags['addr:city'] as String? ?? '',
    ].where((s) => s.isNotEmpty);

    return Restaurant(
      id: e['id'].toString(),
      name: tags['name'] as String? ?? 'Restaurant',
      lat: lat,
      lng: lng,
      amenity: tags['amenity'] as String? ?? 'restaurant',
      cuisine: tags['cuisine'] as String?,
      address: parts.isNotEmpty ? parts.join(', ') : null,
      phone: tags['phone'] as String? ?? tags['contact:phone'] as String?,
      website: tags['website'] as String? ?? tags['contact:website'] as String?,
      openingHours: tags['opening_hours'] as String?,
      rating: _parseRating(
          tags['stars'] ?? tags['rating'] ?? tags['michelin:stars']),
      priceLevel: int.tryParse(
          (tags['price'] ?? tags['level'] ?? '').toString()),
    );
  }

  static double? _parseRating(dynamic raw) {
    if (raw == null) return null;
    final v = double.tryParse(raw.toString());
    return v == null ? null : v.clamp(0.0, 5.0);
  }

  // ── Google Places (New API v1) factory ───────────────────────────────────

  static int? _parsePriceLevel(dynamic raw) {
    if (raw == null) return null;
    const map = {
      'PRICE_LEVEL_FREE': 0,
      'PRICE_LEVEL_INEXPENSIVE': 1,
      'PRICE_LEVEL_MODERATE': 2,
      'PRICE_LEVEL_EXPENSIVE': 3,
      'PRICE_LEVEL_VERY_EXPENSIVE': 4,
    };
    return map[raw.toString()];
  }

  factory Restaurant.fromNewPlacesApi(Map<String, dynamic> p) {
    final types = (p['types'] as List?)?.cast<String>() ?? [];
    final loc = (p['location'] as Map<String, dynamic>?) ?? {};

    String amenity = 'restaurant';
    if (types.any((t) => t == 'bar' || t == 'night_club')) {
      amenity = 'bar';
    } else if (types.any((t) => t == 'cafe' || t == 'coffee_shop')) {
      amenity = 'cafe';
    } else if (types.any((t) => t == 'meal_takeaway' || t == 'fast_food_restaurant')) {
      amenity = 'fast_food';
    }

    const _skip = {
      'restaurant', 'food', 'establishment', 'point_of_interest',
      'bar', 'cafe', 'meal_takeaway', 'meal_delivery', 'night_club',
      'fast_food_restaurant', 'store', 'health',
    };
    final cuisineType =
        types.where((t) => !_skip.contains(t)).firstOrNull;

    return Restaurant(
      id: p['id'] as String? ?? '',
      name: (p['displayName'] as Map?)?['text'] as String? ?? 'Restaurant',
      lat: (loc['latitude'] as num?)?.toDouble() ?? 0,
      lng: (loc['longitude'] as num?)?.toDouble() ?? 0,
      amenity: amenity,
      cuisine: cuisineType?.replaceAll('_', ' '),
      address: p['formattedAddress'] as String?,
      phone: p['nationalPhoneNumber'] as String?,
      website: p['websiteUri'] as String?,
      isOpenNow: (p['currentOpeningHours'] as Map?)?['openNow'] as bool?,
      rating: (p['rating'] as num?)?.toDouble(),
      userRatingsTotal: p['userRatingCount'] as int?,
      priceLevel: _parsePriceLevel(p['priceLevel']),
    );
  }

  // ── Google Places (legacy) factory ────────────────────────────────────────

  factory Restaurant.fromGooglePlace(Map<String, dynamic> p) {
    final types = (p['types'] as List?)?.cast<String>() ?? [];
    final loc = (p['geometry']?['location']) as Map<String, dynamic>? ?? {};

    String amenity = 'restaurant';
    if (types.any((t) => t == 'bar' || t == 'night_club')) {
      amenity = 'bar';
    } else if (types.any((t) => t == 'cafe' || t == 'coffee_shop')) {
      amenity = 'cafe';
    } else if (types
        .any((t) => t == 'meal_takeaway' || t == 'meal_delivery')) {
      amenity = 'fast_food';
    }

    // Extract cuisine hint from types (exclude generic Google types)
    const _skip = {
      'restaurant', 'food', 'establishment', 'point_of_interest',
      'bar', 'cafe', 'meal_takeaway', 'meal_delivery', 'night_club',
      'store', 'health', 'lodging',
    };
    final cuisineType =
        types.where((t) => !_skip.contains(t)).firstOrNull;

    return Restaurant(
      id: p['place_id'] as String? ?? '',
      name: p['name'] as String? ?? 'Restaurant',
      lat: (loc['lat'] as num?)?.toDouble() ?? 0,
      lng: (loc['lng'] as num?)?.toDouble() ?? 0,
      amenity: amenity,
      cuisine: cuisineType?.replaceAll('_', ' '),
      address: p['vicinity'] as String?,
      isOpenNow: (p['opening_hours'] as Map?)?['open_now'] as bool?,
      rating: (p['rating'] as num?)?.toDouble(),
      userRatingsTotal: p['user_ratings_total'] as int?,
      priceLevel: p['price_level'] as int?,
    );
  }

  // ── Apply Place Details response ──────────────────────────────────────────

  Restaurant withDetails(Map<String, dynamic> d) {
    // Support both legacy API and New API response shapes
    final hours = d['opening_hours'] as Map<String, dynamic>?
        ?? d['currentOpeningHours'] as Map<String, dynamic>?;
    final weekdayTexts = hours?['weekday_text'] as List?
        ?? hours?['weekdayDescriptions'] as List?;
    final hoursText = weekdayTexts?.cast<String>().take(3).join(' · ');

    final rawReviews = (d['reviews'] as List?) ?? [];
    final reviewList = rawReviews
        .cast<Map<String, dynamic>>()
        .map((r) {
          // New API: authorAttribution.displayName + text.text
          if (r.containsKey('authorAttribution')) {
            return PlaceReview(
              authorName: (r['authorAttribution'] as Map?)?['displayName'] as String? ?? 'Guest',
              rating: (r['rating'] as num?)?.toInt() ?? 3,
              text: (r['text'] as Map?)?['text'] as String? ?? '',
              relativeTime: r['relativePublishTimeDescription'] as String? ?? '',
            );
          }
          return PlaceReview.fromJson(r);
        })
        .toList();

    return copyWithDetails(
      phone: d['formatted_phone_number'] as String?,
      website: d['website'] as String?,
      openingHours: hoursText,
      isOpenNow: (hours?['open_now']) as bool?,
      rating: (d['rating'] as num?)?.toDouble() ?? rating,
      userRatingsTotal:
          d['user_ratings_total'] as int? ?? userRatingsTotal,
      priceLevel: d['price_level'] as int? ?? priceLevel,
      reviews: reviewList,
    );
  }
}

const kAmenityFilters = <({String label, String? value})>[
  (label: 'All', value: null),
  (label: '🍽️ Restaurant', value: 'restaurant'),
  (label: '☕ Café', value: 'cafe'),
  (label: '🍔 Fast Food', value: 'fast_food'),
  (label: '🍺 Bar', value: 'bar'),
];

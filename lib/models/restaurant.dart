import 'package:flutter/material.dart';

class Restaurant {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final String amenity;
  final String? cuisine;
  final String? address;
  final String? phone;
  final String? website;
  final String? openingHours;

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
  });

  String get emoji {
    final c = (cuisine ?? '').toLowerCase();
    final a = amenity.toLowerCase();
    if (c.contains('pizza')) return '🍕';
    if (c.contains('sushi') || c.contains('japanese')) return '🍣';
    if (c.contains('chinese') || c.contains('asian')) return '🍜';
    if (c.contains('italian')) return '🍝';
    if (c.contains('mexican') || c.contains('burger')) return '🌮';
    if (c.contains('indian')) return '🍛';
    if (c.contains('thai')) return '🍲';
    if (a == 'cafe' || a == 'coffee_shop') return '☕';
    if (a == 'fast_food') return '🍔';
    if (a == 'bar' || a == 'pub') return '🍺';
    if (a == 'ice_cream') return '🍦';
    return '🍽️';
  }

  Color get markerColor {
    switch (amenity) {
      case 'cafe': return const Color(0xFFf59e0b);
      case 'fast_food': return const Color(0xFFef4444);
      case 'bar':
      case 'pub': return const Color(0xFF8b5cf6);
      case 'ice_cream': return const Color(0xFFec4899);
      default: return const Color(0xFFFF6535);
    }
  }

  String get displayType {
    switch (amenity) {
      case 'cafe': return 'Café';
      case 'fast_food': return 'Fast Food';
      case 'bar': return 'Bar';
      case 'pub': return 'Pub';
      case 'food_court': return 'Food Court';
      case 'ice_cream': return 'Ice Cream';
      default: return cuisine != null
          ? cuisine![0].toUpperCase() + cuisine!.substring(1)
          : 'Restaurant';
    }
  }

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

    final houseNum = tags['addr:housenumber'] as String? ?? '';
    final street = tags['addr:street'] as String? ?? '';
    final city = tags['addr:city'] as String? ?? '';
    final parts = [houseNum, street, city].where((s) => s.isNotEmpty);
    final address = parts.isNotEmpty ? parts.join(', ') : null;

    return Restaurant(
      id: e['id'].toString(),
      name: tags['name'] as String? ?? 'Restaurant',
      lat: lat,
      lng: lng,
      amenity: tags['amenity'] as String? ?? 'restaurant',
      cuisine: tags['cuisine'] as String?,
      address: address,
      phone: tags['phone'] as String? ?? tags['contact:phone'] as String?,
      website: tags['website'] as String? ?? tags['contact:website'] as String?,
      openingHours: tags['opening_hours'] as String?,
    );
  }
}

const kAmenityFilters = <({String label, String? value})>[
  (label: 'All', value: null),
  (label: '🍽️ Restaurant', value: 'restaurant'),
  (label: '☕ Café', value: 'cafe'),
  (label: '🍔 Fast Food', value: 'fast_food'),
  (label: '🍺 Bar', value: 'bar'),
  (label: '🍦 Ice Cream', value: 'ice_cream'),
];

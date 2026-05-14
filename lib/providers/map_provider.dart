import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/restaurant.dart';
import '../services/overpass_service.dart';
import '../services/claude_service.dart';

class MapProvider extends ChangeNotifier {
  LatLng _center = const LatLng(25.7617, -80.1918); // Miami default
  List<Restaurant> _restaurants = [];
  String? _selectedFilter;
  bool _isSatellite = false;
  bool _isLoading = false;
  bool _locationLoaded = false;
  String _searchQuery = '';
  Restaurant? _selectedRestaurant;
  String? _error;

  // AI
  final List<Map<String, String>> _chatHistory = [];
  bool _chatLoading = false;

  Timer? _debounce;

  // ── Getters ──────────────────────────────────────────────────────────────

  LatLng get center => _center;
  bool get isSatellite => _isSatellite;
  bool get isLoading => _isLoading;
  bool get locationLoaded => _locationLoaded;
  String? get selectedFilter => _selectedFilter;
  String get searchQuery => _searchQuery;
  Restaurant? get selectedRestaurant => _selectedRestaurant;
  String? get error => _error;
  List<Map<String, String>> get chatHistory => _chatHistory;
  bool get chatLoading => _chatLoading;

  List<Restaurant> get visibleRestaurants {
    return _restaurants.where((r) {
      if (_selectedFilter != null && r.amenity != _selectedFilter) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return r.name.toLowerCase().contains(q) ||
            (r.cuisine?.toLowerCase().contains(q) ?? false) ||
            r.displayType.toLowerCase().contains(q);
      }
      return true;
    }).toList();
  }

  List<Restaurant> get searchSuggestions {
    if (_searchQuery.isEmpty) return [];
    final q = _searchQuery.toLowerCase();
    return _restaurants
        .where((r) =>
            r.name.toLowerCase().contains(q) ||
            (r.cuisine?.toLowerCase().contains(q) ?? false))
        .take(5)
        .toList();
  }

  // ── Init ─────────────────────────────────────────────────────────────────

  Future<void> init() async {
    await _loadLocation();
  }

  Future<void> _loadLocation() async {
    try {
      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await fetchRestaurants(_center);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      _center = LatLng(pos.latitude, pos.longitude);
      _locationLoaded = true;
      notifyListeners();
    } catch (_) {
      // Fall back to default center
    }
    await fetchRestaurants(_center);
  }

  // ── Restaurant loading ────────────────────────────────────────────────────

  Future<void> fetchRestaurants(LatLng center) async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _restaurants = await OverpassService.fetchNearby(
        center.latitude,
        center.longitude,
      );
    } catch (e) {
      _error = 'Could not load restaurants. Check your connection.';
    }
    _isLoading = false;
    notifyListeners();
  }

  void onMapMoved(LatLng center) {
    _center = center;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () {
      fetchRestaurants(center);
    });
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  void setFilter(String? type) {
    _selectedFilter = type;
    notifyListeners();
  }

  void toggleSatellite() {
    _isSatellite = !_isSatellite;
    notifyListeners();
  }

  void setSearch(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void selectRestaurant(Restaurant? r) {
    _selectedRestaurant = r;
    notifyListeners();
  }

  void moveToCenter(LatLng pos) {
    _center = pos;
    notifyListeners();
  }

  // ── AI ────────────────────────────────────────────────────────────────────

  Future<void> sendMessage(String question) async {
    _chatHistory.add({'role': 'user', 'content': question});
    _chatLoading = true;
    notifyListeners();
    try {
      final reply = await ClaudeService.chat(
        question: question,
        userLocation: _center,
        restaurants: visibleRestaurants,
        history: _chatHistory.where((m) => m['role'] == 'assistant').toList(),
      );
      _chatHistory.add({'role': 'assistant', 'content': reply});
    } catch (_) {
      _chatHistory.add({
        'role': 'assistant',
        'content': 'Sorry, I had trouble connecting. Please try again.',
      });
    }
    _chatLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

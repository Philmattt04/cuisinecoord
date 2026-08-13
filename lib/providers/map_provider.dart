import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:intl/intl.dart';
import '../models/restaurant.dart';
import '../models/user_data.dart';
import '../services/google_places_service.dart';
import '../services/overpass_service.dart';
import '../services/nominatim_service.dart';
import '../services/claude_service.dart';
import '../services/user_storage.dart';

class MapProvider extends ChangeNotifier {
  LatLng _center = const LatLng(25.7617, -80.1918);
  List<Restaurant> _restaurants = [];
  String? _selectedFilter;
  bool _isSatellite = false;
  bool _isLoading = false;
  bool _isSearchingLocation = false;
  bool _locationLoaded = false;
  String _searchQuery = '';
  String _locationLabel = '';
  Restaurant? _selectedRestaurant;
  String? _error;
  LatLng? _lastFetchCenter;

  final Map<String, Restaurant> _detailsCache = {};

  // ── User data ─────────────────────────────────────────────────────────────
  List<String> _hiddenIds = [];
  List<DiningVisit> _diningHistory = [];
  List<RestaurantCollection> _collections = [];

  // ── AI ────────────────────────────────────────────────────────────────────
  final List<Map<String, String>> _chatHistory = [];
  bool _chatLoading = false;
  Restaurant? _focusedRestaurant;
  Restaurant? _compareRestaurant;

  Timer? _debounce;

  // ── Getters ───────────────────────────────────────────────────────────────

  LatLng get center => _center;
  bool get isSatellite => _isSatellite;
  bool get isLoading => _isLoading;
  bool get isSearchingLocation => _isSearchingLocation;
  bool get locationLoaded => _locationLoaded;
  String? get selectedFilter => _selectedFilter;
  String get searchQuery => _searchQuery;
  String get locationLabel => _locationLabel;
  Restaurant? get selectedRestaurant => _selectedRestaurant;
  String? get error => _error;
  List<Map<String, String>> get chatHistory => _chatHistory;
  bool get chatLoading => _chatLoading;
  Restaurant? get focusedRestaurant => _focusedRestaurant;
  Restaurant? get compareRestaurant => _compareRestaurant;
  List<String> get hiddenIds => _hiddenIds;
  List<DiningVisit> get diningHistory => _diningHistory;
  List<RestaurantCollection> get collections => _collections;

  List<DiningVisit> visitsFor(String restaurantId) =>
      _diningHistory.where((v) => v.restaurantId == restaurantId).toList();

  List<Restaurant> get hiddenRestaurants =>
      _restaurants.where((r) => _hiddenIds.contains(r.id)).toList();

  Set<String> get savedRestaurantIds =>
      _collections.expand((c) => c.restaurantIds).toSet();

  List<Restaurant> get savedRestaurants =>
      _restaurants.where((r) => savedRestaurantIds.contains(r.id)).toList();

  List<RestaurantCollection> collectionsFor(String restaurantId) =>
      _collections.where((c) => c.contains(restaurantId)).toList();

  List<Restaurant> get visibleRestaurants {
    return _restaurants.where((r) {
      if (_hiddenIds.contains(r.id)) return false;
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
            !_hiddenIds.contains(r.id) &&
            (r.name.toLowerCase().contains(q) ||
                (r.cuisine?.toLowerCase().contains(q) ?? false)))
        .take(6)
        .toList();
  }

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    // Load user data before fetching restaurants
    _hiddenIds = await UserStorage.instance.loadHiddenIds();
    _diningHistory = await UserStorage.instance.loadDiningHistory();
    _collections = await UserStorage.instance.loadCollections();
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
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      _center = LatLng(pos.latitude, pos.longitude);
      _locationLoaded = true;
      _locationLabel = 'My Location';
      notifyListeners();
    } catch (_) {}
    await fetchRestaurants(_center);
  }

  // ── Location search ───────────────────────────────────────────────────────

  Future<LatLng?> searchLocation(String query) async {
    if (query.trim().isEmpty) return null;
    _isSearchingLocation = true;
    _error = null;
    notifyListeners();
    try {
      final result = await NominatimService.geocode(query.trim());
      if (result != null) {
        _center = result.coords;
        _locationLabel = result.displayName;
        _locationLoaded = true;
        _lastFetchCenter = null;
        notifyListeners();
        await fetchRestaurants(_center, force: true);
        return _center;
      }
      _error = 'Location "$query" not found.';
    } catch (_) {
      _error = 'Could not search for that location.';
    } finally {
      _isSearchingLocation = false;
      notifyListeners();
    }
    return null;
  }

  Future<LatLng?> goToMyLocation() async {
    _error = null;
    notifyListeners();
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _error = 'Location permission denied.';
        notifyListeners();
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      _center = LatLng(pos.latitude, pos.longitude);
      _locationLabel = 'My Location';
      _locationLoaded = true;
      _lastFetchCenter = null;
      notifyListeners();
      await fetchRestaurants(_center, force: true);
      return _center;
    } catch (_) {
      _error = 'Could not get your location.';
      notifyListeners();
      return null;
    }
  }

  // ── Restaurant loading ────────────────────────────────────────────────────

  Future<void> fetchRestaurants(LatLng center, {bool force = false}) async {
    if (_isLoading && !force) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      List<Restaurant> results;
      if (GooglePlacesService.hasKey) {
        results = await GooglePlacesService.nearbySearch(
            center.latitude, center.longitude);
      } else {
        results = await OverpassService.fetchNearby(
            center.latitude, center.longitude);
      }
      _restaurants = results.map((r) => _detailsCache[r.id] ?? r).toList();
      _lastFetchCenter = center;
    } catch (e) {
      _error = e.toString().contains('API key')
          ? 'Google Places API key not configured.'
          : 'Could not load restaurants. Check your connection.';
    }
    _isLoading = false;
    notifyListeners();
  }

  void onMapMoved(LatLng center) {
    _center = center;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final shouldFetch = _lastFetchCenter == null ||
          _distanceMeters(_lastFetchCenter!, center) > 400;
      if (shouldFetch) fetchRestaurants(center);
    });
  }

  Future<void> loadPlaceDetails(String placeId) async {
    if (_detailsCache.containsKey(placeId)) return;
    final details = await GooglePlacesService.placeDetails(placeId);
    if (details == null) return;
    final idx = _restaurants.indexWhere((r) => r.id == placeId);
    if (idx == -1) return;
    final enriched = _restaurants[idx].withDetails(details);
    _detailsCache[placeId] = enriched;
    _restaurants[idx] = enriched;
    if (_selectedRestaurant?.id == placeId) _selectedRestaurant = enriched;
    if (_focusedRestaurant?.id == placeId) _focusedRestaurant = enriched;
    notifyListeners();
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
    if (r != null) {
      _focusedRestaurant = r;
      if (r.reviews.isEmpty && GooglePlacesService.hasKey) {
        loadPlaceDetails(r.id);
      }
    }
    notifyListeners();
  }

  void setFocusedRestaurant(Restaurant? r) {
    _focusedRestaurant = r;
    notifyListeners();
  }

  void setCompareRestaurant(Restaurant? r) {
    _compareRestaurant = r;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ── Personal data ─────────────────────────────────────────────────────────

  Future<void> hideRestaurant(String id) async {
    if (!_hiddenIds.contains(id)) {
      _hiddenIds = [..._hiddenIds, id];
      await UserStorage.instance.saveHiddenIds(_hiddenIds);
      notifyListeners();
    }
  }

  Future<void> unhideRestaurant(String id) async {
    if (_hiddenIds.contains(id)) {
      _hiddenIds = _hiddenIds.where((h) => h != id).toList();
      await UserStorage.instance.saveHiddenIds(_hiddenIds);
      notifyListeners();
    }
  }

  Future<void> logVisit(String restaurantId, String restaurantName,
      int? rating, String? note) async {
    final visit = DiningVisit(
      restaurantId: restaurantId,
      restaurantName: restaurantName,
      visitedAt: DateTime.now(),
      personalRating: rating,
      note: note,
    );
    _diningHistory = [visit, ..._diningHistory];
    await UserStorage.instance.saveDiningHistory(_diningHistory);
    notifyListeners();
  }

  Future<RestaurantCollection> createCollection(String name) async {
    final col = RestaurantCollection(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      restaurantIds: [],
    );
    _collections = [..._collections, col];
    await UserStorage.instance.saveCollections(_collections);
    notifyListeners();
    return col;
  }

  Future<void> toggleInCollection(String collectionId, String restaurantId) async {
    _collections = _collections.map((c) {
      if (c.id != collectionId) return c;
      return c.contains(restaurantId)
          ? c.withoutRestaurant(restaurantId)
          : c.withRestaurant(restaurantId);
    }).toList();
    await UserStorage.instance.saveCollections(_collections);
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
        focusedRestaurant: _focusedRestaurant,
        compareRestaurant: _compareRestaurant,
        diningHistory: _focusedRestaurant != null
            ? visitsFor(_focusedRestaurant!.id)
            : [],
        currentDateTime: DateFormat('h:mm a, EEEE, MMMM d').format(DateTime.now()),
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

  double _distanceMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(a.latitude * pi / 180) *
            cos(b.latitude * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return r * 2 * asin(sqrt(h));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/restaurant.dart';
import '../providers/map_provider.dart';
import '../main.dart';

// ── Theme-aware color helpers ─────────────────────────────────────────────────
extension _AppColors on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get panelBg => isDark ? const Color(0xFF1e1e2e) : Colors.white;
  Color get secondaryBg => isDark ? const Color(0xFF2d2d3e) : const Color(0xFFF3F4F6);
  Color get primaryText => isDark ? Colors.white : const Color(0xFF111827);
  Color get secondaryText => isDark ? const Color(0xFF9ca3af) : const Color(0xFF6b7280);
  Color get hintText => isDark ? const Color(0xFF4b5563) : const Color(0xFF9ca3af);
  Color get borderColor => isDark
      ? Colors.white.withValues(alpha: 0.07)
      : const Color(0xFFe5e7eb);
  Color get shadowColor => isDark
      ? Colors.black.withValues(alpha: 0.4)
      : Colors.black.withValues(alpha: 0.12);
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Completer<GoogleMapController> _controllerCompleter = Completer();
  GoogleMapController? _mapController;
  final _searchCtrl = TextEditingController();
  final _chatCtrl = TextEditingController();
  bool _showSuggestions = false;
  LatLng? _cameraCenter;
  Brightness? _lastBrightness;

  final Map<String, BitmapDescriptor> _markerIcons = {};
  bool _iconsReady = false;
  bool _initialLocationSet = false;
  int _sheetsOpen = 0;
  bool _compareModeActive = false;

  // Dark map style JSON
  static const _darkStyle = '''[
    {"elementType":"geometry","stylers":[{"color":"#1a1a2e"}]},
    {"elementType":"labels.text.fill","stylers":[{"color":"#746855"}]},
    {"elementType":"labels.text.stroke","stylers":[{"color":"#242f3e"}]},
    {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#d59563"}]},
    {"featureType":"poi","stylers":[{"visibility":"off"}]},
    {"featureType":"road","elementType":"geometry","stylers":[{"color":"#38414e"}]},
    {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#212a37"}]},
    {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#9ca5b3"}]},
    {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#746855"}]},
    {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#f3d19c"}]},
    {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#2f3948"}]},
    {"featureType":"water","elementType":"geometry","stylers":[{"color":"#17263c"}]},
    {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#515c6d"}]}
  ]''';

  @override
  void initState() {
    super.initState();
    _preloadMarkerIcons();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MapProvider>().init();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _chatCtrl.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  // ── Pre-load marker icons ──────────────────────────────────────────────────

  // Maps amenity type → (background color, Material icon, icon color)
  static const _markerDefs = {
    'restaurant': (bg: Color(0xFFFF6535), icon: Icons.restaurant,  fg: Colors.white),
    'cafe':       (bg: Color(0xFFf59e0b), icon: Icons.local_cafe,  fg: Colors.white),
    'fast_food':  (bg: Color(0xFFef4444), icon: Icons.fastfood,    fg: Colors.white),
    'bar':        (bg: Color(0xFF8b5cf6), icon: Icons.local_bar,   fg: Colors.white),
    'selected':   (bg: Colors.white,      icon: Icons.place,        fg: Color(0xFFFF6535)),
  };

  Future<void> _preloadMarkerIcons() async {
    for (final e in _markerDefs.entries) {
      _markerIcons[e.key] = await _buildMarkerIcon(
        bg: e.value.bg,
        iconData: e.value.icon,
        fg: e.value.fg,
        isSelected: e.key == 'selected',
      );
    }
    if (mounted) setState(() => _iconsReady = true);
  }

  Future<BitmapDescriptor> _buildMarkerIcon({
    required Color bg,
    required IconData iconData,
    required Color fg,
    required bool isSelected,
  }) async {
    final size = isSelected ? 56.0 : 46.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final cx = size / 2;
    final r = (size / 2) - 2;

    // Shadow
    canvas.drawCircle(Offset(cx, cx + 2), r,
        Paint()..color = Colors.black.withValues(alpha: 0.3));
    // Fill
    canvas.drawCircle(Offset(cx, cx), r, Paint()..color = bg);
    // Border for selected
    if (isSelected) {
      canvas.drawCircle(Offset(cx, cx), r,
          Paint()
            ..color = const Color(0xFFFF6535)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
    }
    // Pin tip
    final tip = ui.Path()
      ..moveTo(cx - 6, cx + r - 4)
      ..lineTo(cx, cx + r + 8)
      ..lineTo(cx + 6, cx + r - 4)
      ..close();
    canvas.drawPath(tip, Paint()..color = bg);

    // Material icon — always renders correctly on Flutter web
    final iconSize = isSelected ? 24.0 : 20.0;
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          fontSize: iconSize,
          fontFamily: iconData.fontFamily ?? 'MaterialIcons',
          color: fg,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cx - tp.height / 2 - 1));

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), (size + 10).toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  BitmapDescriptor _iconFor(Restaurant r, bool isSelected) {
    if (isSelected) return _markerIcons['selected'] ?? BitmapDescriptor.defaultMarker;
    return _markerIcons[r.amenity] ??
        _markerIcons['restaurant'] ??
        BitmapDescriptor.defaultMarker;
  }

  // ── Map controller helpers ────────────────────────────────────────────────

  Future<void> _moveTo(LatLng pos, {double zoom = 15}) async {
    final ctrl = await _controllerCompleter.future;
    ctrl.animateCamera(CameraUpdate.newLatLngZoom(pos, zoom));
  }

  // ── Markers ───────────────────────────────────────────────────────────────

  Set<Marker> _buildMarkers(MapProvider p) {
    if (!_iconsReady) return {};
    return p.visibleRestaurants.map((r) {
      final isSelected = p.selectedRestaurant?.id == r.id;
      final isCompare = p.compareRestaurant?.id == r.id;
      return Marker(
        markerId: MarkerId(r.id),
        position: LatLng(r.lat, r.lng),
        icon: isCompare
            ? (_markerIcons['selected'] ?? BitmapDescriptor.defaultMarker)
            : _iconFor(r, isSelected),
        zIndex: (isSelected || isCompare) ? 1 : 0,
        onTap: () {
          if (_compareModeActive) {
            // Second tap in compare mode — set compare target and open AI
            p.setCompareRestaurant(r);
            setState(() => _compareModeActive = false);
            final q = 'Compare ${p.focusedRestaurant?.name ?? "the selected restaurant"} vs ${r.name}. Which should I choose and why?';
            p.sendMessage(q);
            _showAISheet(context);
          } else {
            p.selectRestaurant(r);
            _moveTo(LatLng(r.lat, r.lng), zoom: 16);
            _showRestaurantSheet(r);
          }
        },
      );
    }).toSet();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = context.watch<MapProvider>();

    // Move to GPS location once — never again on subsequent rebuilds
    if (p.locationLoaded && !_initialLocationSet && _mapController != null) {
      _initialLocationSet = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _moveTo(p.center));
    }

    // Reactively update map style when theme changes
    final brightness = Theme.of(context).brightness;
    if (_mapController != null && brightness != _lastBrightness) {
      _lastBrightness = brightness;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final ctrl = await _controllerCompleter.future;
        final dark = brightness == Brightness.dark;
        await ctrl.setMapStyle(dark && !p.isSatellite ? _darkStyle : null);
      });
    }

    final isDark = context.isDark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1a1a2e) : const Color(0xFFF8F8F8),
      body: Stack(
        children: [
          // ── Google Map ───────────────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: p.center,
              zoom: 15,
            ),
            mapType: p.isSatellite ? MapType.satellite : MapType.normal,
            markers: _buildMarkers(p),
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            webCameraControlEnabled: false,
            scrollGesturesEnabled: _sheetsOpen == 0,
            zoomGesturesEnabled: _sheetsOpen == 0,
            rotateGesturesEnabled: false,
            onMapCreated: (GoogleMapController ctrl) async {
              _mapController = ctrl;
              if (!_controllerCompleter.isCompleted) {
                _controllerCompleter.complete(ctrl);
              }
              final dark = context.isDark;
              _lastBrightness = dark ? Brightness.dark : Brightness.light;
              await ctrl.setMapStyle(
                  dark && !p.isSatellite ? _darkStyle : null);
            },
            onCameraMove: (CameraPosition pos) {
              _cameraCenter = pos.target;
            },
            onCameraIdle: () {
              if (_cameraCenter != null) p.onMapMoved(_cameraCenter!);
            },
            onTap: (LatLng _) {
              p.selectRestaurant(null);
              setState(() => _showSuggestions = false);
              FocusScope.of(context).unfocus();
            },
          ),

          // ── Top overlay ──────────────────────────────────────────────────
          _TopOverlay(
            searchCtrl: _searchCtrl,
            showSuggestions: _showSuggestions,
            onSearchChanged: (v) {
              p.setSearch(v);
              setState(() => _showSuggestions = v.isNotEmpty);
            },
            onSuggestionTap: (r) {
              p.selectRestaurant(r);
              _moveTo(LatLng(r.lat, r.lng), zoom: 17);
              _searchCtrl.text = r.name;
              setState(() => _showSuggestions = false);
              FocusScope.of(context).unfocus();
              _showRestaurantSheet(r);
            },
            onClear: () {
              _searchCtrl.clear();
              p.setSearch('');
              setState(() => _showSuggestions = false);
            },
            onLocationTap: _showLocationSearch,
            onSavedTap: _showHiddenSheet,
          ),

          // ── Compare mode banner ───────────────────────────────────────────
          if (_compareModeActive)
            Positioned(
              top: MediaQuery.of(context).padding.top + 130,
              left: 20, right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366f1),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8, offset: const Offset(0, 2),
                  )],
                ),
                child: Row(children: [
                  const Icon(Icons.touch_app_rounded,
                      color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Tap another restaurant to compare',
                      style: TextStyle(color: Colors.white, fontSize: 13,
                          fontWeight: FontWeight.w500))),
                  GestureDetector(
                    onTap: () => setState(() => _compareModeActive = false),
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white70, size: 18),
                  ),
                ]),
              ),
            ),

          // ── Loading pill ─────────────────────────────────────────────────
          if (p.isLoading)
            Positioned(
              top: 130,
              left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1a1a2e).withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFFFF6535))),
                    SizedBox(width: 8),
                    Text('Finding restaurants…',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ]),
                ),
              ),
            ),

          // ── Error snack ──────────────────────────────────────────────────
          if (p.error != null)
            Positioned(
              bottom: 100, left: 20, right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                    color: const Color(0xFFef4444),
                    borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Expanded(child: Text(p.error!,
                      style: const TextStyle(color: Colors.white, fontSize: 13))),
                  GestureDetector(
                    onTap: p.clearError,
                    child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                  ),
                ]),
              ),
            ),

          // ── Right controls ────────────────────────────────────────────────
          // Single column, top→bottom: my location, satellite, theme, AI.
          // One Positioned/Column so the AI FAB is always last in the stack
          // and can never overlap the buttons above it.
          Positioned(
            right: 16, bottom: 32,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _MapButton(
                tooltip: 'My location',
                icon: Icons.my_location_rounded,
                isDark: isDark,
                onTap: () async {
                  final pos = await context.read<MapProvider>().goToMyLocation();
                  if (pos != null) _moveTo(pos);
                },
              ),
              const SizedBox(height: 12),
              _MapButton(
                tooltip: p.isSatellite ? 'Map view' : 'Satellite view',
                icon: p.isSatellite ? Icons.map_rounded : Icons.satellite_alt_rounded,
                isDark: isDark,
                onTap: () async {
                  p.toggleSatellite();
                  final ctrl = await _controllerCompleter.future;
                  final dark = context.isDark;
                  await ctrl.setMapStyle(
                      !p.isSatellite && dark ? _darkStyle : null);
                },
              ),
              const SizedBox(height: 12),
              _MapButton(
                tooltip: isDark ? 'Light mode' : 'Dark mode',
                icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                isDark: isDark,
                onTap: () => CuisineCoordApp.of(context).toggleTheme(),
              ),
              const SizedBox(height: 12),
              // AI FAB — last in the row, always below the white buttons above.
              GestureDetector(
                onTap: () => _showAISheet(context),
                child: Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6535),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 10, offset: const Offset(0, 3),
                    )],
                  ),
                  child: const Center(
                      child: Text('✨', style: TextStyle(fontSize: 22))),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  // ── Sheet helper — disables map gestures while any sheet is open ──────────

  Future<T?> _showSheet<T>({required WidgetBuilder builder, bool isScrollControlled = true}) {
    setState(() => _sheetsOpen++);
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: isScrollControlled,
      builder: builder,
    ).whenComplete(() => setState(() => _sheetsOpen--));
  }

  // ── Restaurant sheet ──────────────────────────────────────────────────────

  void _showRestaurantSheet(Restaurant r) {
    final p = context.read<MapProvider>();
    p.selectRestaurant(r);
    _showSheet(builder: (sheetCtx) => ChangeNotifierProvider.value(
      value: p,
      child: _RestaurantSheetWrapper(
        placeId: r.id,
        onShowOnMap: () {
          Navigator.pop(sheetCtx);
          _moveTo(LatLng(r.lat, r.lng), zoom: 16);
        },
        onCheckIn: () { Navigator.pop(sheetCtx); _showCheckInDialog(r); },
        onHide: () {
          Navigator.pop(sheetCtx);
          p.hideRestaurant(r.id);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${r.name} hidden from map'),
            backgroundColor: const Color(0xFF374151),
            duration: const Duration(seconds: 2),
          ));
        },
        onSave: () { Navigator.pop(sheetCtx); _showCollectionPicker(r); },
        onCompare: () {
          Navigator.pop(sheetCtx);
          setState(() => _compareModeActive = true);
        },
      ),
    ));
  }

  // ── Location search ───────────────────────────────────────────────────────

  void _showLocationSearch() {
    final ctrl = TextEditingController();
    _showSheet(builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: context.panelBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4,
                decoration: BoxDecoration(
                    color: context.isDark
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('Search a Location',
                style: TextStyle(color: context.primaryText, fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: TextStyle(color: context.primaryText),
              onSubmitted: (v) async {
                Navigator.pop(ctx);
                final pos = await context.read<MapProvider>().searchLocation(v);
                if (pos != null) _moveTo(pos);
              },
              decoration: InputDecoration(
                hintText: 'e.g. Tokyo, Paris, New York…',
                hintStyle: TextStyle(color: context.hintText),
                prefixIcon: const Icon(Icons.place_rounded,
                    color: Color(0xFFFF6535)),
                filled: true,
                fillColor: context.secondaryBg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final pos =
                      await context.read<MapProvider>().searchLocation(ctrl.text);
                  if (pos != null) _moveTo(pos);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6535),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Search',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── AI sheet ──────────────────────────────────────────────────────────────

  void _showAISheet(BuildContext ctx) {
    final p = ctx.read<MapProvider>();
    _showSheet(builder: (_) => ChangeNotifierProvider.value(
      value: p,
      child: _AISheet(
        chatCtrl: _chatCtrl,
        onGroupTap: _showGroupAssistant,
        onHistoryTap: _showHistorySheet,
        onHiddenTap: _showHiddenSheet,
      ),
    ));
  }

  // ── Check-in dialog ───────────────────────────────────────────────────────

  void _showCheckInDialog(Restaurant r) {
    int selectedRating = 0;
    final noteCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
        final isDark = ctx.isDark;
        return AlertDialog(
          backgroundColor: ctx.panelBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Text(r.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Expanded(child: Text(r.name,
                style: TextStyle(fontSize: 16, color: ctx.primaryText,
                    fontWeight: FontWeight.w700))),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Rate your visit', style: TextStyle(
                color: ctx.secondaryText, fontSize: 13)),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) => GestureDetector(
                onTap: () => setDlg(() => selectedRating = i + 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    i < selectedRating ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: const Color(0xFFf59e0b), size: 32,
                  ),
                ),
              )),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: noteCtrl,
              maxLines: 2,
              style: TextStyle(color: ctx.primaryText, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Add a note (optional)',
                hintStyle: TextStyle(color: ctx.hintText),
                filled: true,
                fillColor: ctx.secondaryBg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: ctx.secondaryText)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.read<MapProvider>().logVisit(
                  r.id, r.name,
                  selectedRating > 0 ? selectedRating : null,
                  noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
                );
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Visit to ${r.name} logged!'),
                  backgroundColor: const Color(0xFFFF6535),
                  duration: const Duration(seconds: 2),
                ));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6535),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Log Visit'),
            ),
          ],
        );
      }),
    );
  }

  // ── Collection picker sheet ───────────────────────────────────────────────

  void _showCollectionPicker(Restaurant r) {
    _showSheet(builder: (ctx) => _CollectionPickerSheet(
      restaurant: r,
      provider: context.read<MapProvider>(),
    ));
  }

  // ── Group assistant sheet ─────────────────────────────────────────────────

  void _showGroupAssistant() {
    _showSheet(builder: (_) => _GroupAssistantSheet(
      onSubmit: (prompt) {
        context.read<MapProvider>().sendMessage(prompt);
        _showAISheet(context);
      },
    ));
  }

  // ── Dining history sheet ──────────────────────────────────────────────────

  void _showHistorySheet() {
    _showSheet(builder: (_) => ChangeNotifierProvider.value(
      value: context.read<MapProvider>(),
      child: const _HistorySheet(),
    ));
  }

  // ── Saved & hidden restaurants sheet ──────────────────────────────────────

  void _showHiddenSheet() {
    _showSheet(builder: (sheetCtx) => ChangeNotifierProvider.value(
      value: context.read<MapProvider>(),
      child: _SavedHiddenSheet(onManage: (r) {
        Navigator.pop(sheetCtx);
        _showCollectionPicker(r);
      }),
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top overlay — search bar + filter chips
// ─────────────────────────────────────────────────────────────────────────────

class _TopOverlay extends StatelessWidget {
  final TextEditingController searchCtrl;
  final bool showSuggestions;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<Restaurant> onSuggestionTap;
  final VoidCallback onClear;
  final VoidCallback onLocationTap;
  final VoidCallback onSavedTap;

  const _TopOverlay({
    required this.searchCtrl,
    required this.showSuggestions,
    required this.onSearchChanged,
    required this.onSuggestionTap,
    required this.onClear,
    required this.onLocationTap,
    required this.onSavedTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.watch<MapProvider>();

    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: Column(children: [
        // Search bar
        Container(
          decoration: BoxDecoration(
            color: context.panelBg,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(
              color: context.shadowColor,
              blurRadius: 12, offset: const Offset(0, 4),
            )],
          ),
          child: Row(children: [
            Expanded(child: TextField(
              controller: searchCtrl,
              onChanged: onSearchChanged,
              style: TextStyle(color: context.primaryText, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Search restaurants, cuisine…',
                hintStyle: TextStyle(color: context.hintText, fontSize: 15),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: Color(0xFFFF6535), size: 22),
                suffixIcon: searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close_rounded,
                            color: context.secondaryText, size: 18),
                        onPressed: onClear)
                    : null,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                filled: true,
                fillColor: Colors.transparent,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            )),
            GestureDetector(
              onTap: onSavedTap,
              child: Container(
                width: 48, height: 48,
                color: Colors.transparent,
                child: Icon(Icons.bookmark_rounded,
                    color: context.secondaryText, size: 22),
              ),
            ),
            GestureDetector(
              onTap: onLocationTap,
              child: Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6535).withValues(alpha: 0.15),
                  borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(14)),
                ),
                child: const Icon(Icons.place_rounded,
                    color: Color(0xFFFF6535), size: 22),
              ),
            ),
          ]),
        ),

        // Location label
        if (p.locationLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Row(children: [
              const Icon(Icons.navigation_rounded,
                  size: 12, color: Color(0xFFFF6535)),
              const SizedBox(width: 4),
              Text(p.locationLabel,
                  style: TextStyle(fontSize: 11,
                      color: context.secondaryText,
                      fontWeight: FontWeight.w500)),
              if (p.isSearchingLocation) ...[
                const SizedBox(width: 8),
                const SizedBox(width: 10, height: 10,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: Color(0xFFFF6535))),
              ],
            ]),
          ),

        // Suggestions
        if (showSuggestions && p.searchSuggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: context.panelBg,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(
                color: context.shadowColor,
                blurRadius: 12, offset: const Offset(0, 4),
              )],
            ),
            child: Column(children: p.searchSuggestions.map((r) => ListTile(
              dense: true,
              leading: Text(r.emoji, style: const TextStyle(fontSize: 20)),
              title: Text(r.name,
                  style: TextStyle(color: context.primaryText, fontSize: 14)),
              subtitle: Text(r.displayType,
                  style: TextStyle(color: context.secondaryText, fontSize: 12)),
              onTap: () => onSuggestionTap(r),
            )).toList()),
          ),

        const SizedBox(height: 10),

        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: kAmenityFilters.map((f) {
            final sel = p.selectedFilter == f.value;
            return GestureDetector(
              onTap: () => p.setFilter(f.value),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: sel
                      ? const Color(0xFFFF6535)
                      : context.panelBg.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(
                    color: context.shadowColor,
                    blurRadius: 6, offset: const Offset(0, 2),
                  )],
                ),
                child: Text(f.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : context.primaryText,
                    )),
              ),
            );
          }).toList()),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Map button
// ─────────────────────────────────────────────────────────────────────────────

class _MapButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool isDark;
  final Function() onTap;
  const _MapButton({required this.tooltip, required this.icon,
      required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: context.panelBg,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(
            color: context.shadowColor,
            blurRadius: 8, offset: const Offset(0, 2),
          )],
        ),
        child: Icon(icon,
            color: isDark ? Colors.white : const Color(0xFF374151), size: 20),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Restaurant sheet wrapper — rebuilds as details load in
// ─────────────────────────────────────────────────────────────────────────────

class _RestaurantSheetWrapper extends StatelessWidget {
  final String placeId;
  final VoidCallback onShowOnMap;
  final VoidCallback? onCheckIn;
  final VoidCallback? onHide;
  final VoidCallback? onSave;
  final VoidCallback? onCompare;
  const _RestaurantSheetWrapper({
    required this.placeId,
    required this.onShowOnMap,
    this.onCheckIn, this.onHide, this.onSave, this.onCompare,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.watch<MapProvider>();
    final r = p.visibleRestaurants.firstWhere(
      (r) => r.id == placeId,
      orElse: () => p.selectedRestaurant!,
    );
    return _RestaurantSheet(
      restaurant: r,
      onShowOnMap: onShowOnMap,
      onCheckIn: onCheckIn,
      onHide: onHide,
      onSave: onSave,
      onCompare: onCompare,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Restaurant detail sheet
// ─────────────────────────────────────────────────────────────────────────────

class _RestaurantSheet extends StatelessWidget {
  final Restaurant restaurant;
  final VoidCallback onShowOnMap;
  final VoidCallback? onCheckIn;
  final VoidCallback? onHide;
  final VoidCallback? onSave;
  final VoidCallback? onCompare;
  const _RestaurantSheet({
    required this.restaurant,
    required this.onShowOnMap,
    this.onCheckIn,
    this.onHide,
    this.onSave,
    this.onCompare,
  });

  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    return Container(
      decoration: BoxDecoration(
        color: context.panelBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: context.isDark
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.black.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            const SizedBox(height: 16),

            // Header
            Row(children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: r.markerColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(child: Text(r.emoji,
                    style: const TextStyle(fontSize: 26))),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name, style: TextStyle(color: context.primaryText,
                        fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 6, runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: r.markerColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(r.displayType,
                                style: TextStyle(fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: r.markerColor)),
                          ),
                          if (r.priceLevelStr.isNotEmpty)
                            Text(r.priceLevelStr,
                                style: const TextStyle(
                                    color: Color(0xFF9ca3af), fontSize: 12)),
                          if (r.isOpenNow != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: (r.isOpenNow!
                                    ? const Color(0xFF22c55e)
                                    : const Color(0xFFef4444))
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(r.isOpenNow! ? 'Open' : 'Closed',
                                  style: TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w600,
                                    color: r.isOpenNow!
                                        ? const Color(0xFF22c55e)
                                        : const Color(0xFFef4444),
                                  )),
                            ),
                        ]),
                    if (r.rating != null) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        _StarRating(rating: r.rating!),
                        if (r.userRatingsTotal != null) ...[
                          const SizedBox(width: 6),
                          Text('(${_formatCount(r.userRatingsTotal!)})',
                              style: const TextStyle(
                                  color: Color(0xFF6b7280), fontSize: 11)),
                        ],
                      ]),
                    ],
                  ])),
            ]),
            const SizedBox(height: 20),

            // Details
            if (r.address != null) ...[
              _DetailRow(icon: Icons.place_rounded,
                  text: r.address!, color: const Color(0xFF9ca3af)),
              const SizedBox(height: 10),
            ],
            if (r.phone != null) ...[
              _DetailRow(icon: Icons.phone_rounded, text: r.phone!,
                  color: const Color(0xFF9ca3af),
                  onTap: () => launchUrl(Uri.parse('tel:${r.phone}'))),
              const SizedBox(height: 10),
            ],
            if (r.website != null) ...[
              _DetailRow(icon: Icons.language_rounded, text: r.website!,
                  color: const Color(0xFF6366f1),
                  onTap: () => launchUrl(Uri.parse(r.website!))),
              const SizedBox(height: 10),
            ],
            if (r.openingHours != null) ...[
              _DetailRow(icon: Icons.access_time_rounded,
                  text: r.openingHours!, color: const Color(0xFF9ca3af)),
              const SizedBox(height: 10),
            ],

            // Reviews
            if (r.reviews.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Reviews', style: TextStyle(color: context.primaryText,
                  fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              ...r.reviews.take(3).map((rev) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.secondaryBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(child: Text(rev.authorName,
                              style: TextStyle(color: context.primaryText,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600))),
                          Row(mainAxisSize: MainAxisSize.min,
                              children: List.generate(5, (i) => Icon(
                                i < rev.rating ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                size: 12, color: const Color(0xFFf59e0b),
                              ))),
                          const SizedBox(width: 6),
                          Text(rev.relativeTime,
                              style: const TextStyle(
                                  color: Color(0xFF6b7280), fontSize: 10)),
                        ]),
                        if (rev.text.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            rev.text.length > 160
                                ? '${rev.text.substring(0, 160)}…'
                                : rev.text,
                            style: TextStyle(color: context.secondaryText,
                                fontSize: 12, height: 1.4),
                          ),
                        ],
                      ]),
                ),
              )),
            ] else if (r.id.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Row(children: [
                SizedBox(width: 12, height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: Color(0xFFFF6535))),
                SizedBox(width: 8),
                Text('Loading reviews…',
                    style: TextStyle(color: Color(0xFF6b7280), fontSize: 12)),
              ]),
            ],

            // Action row — personal features
            const SizedBox(height: 16),
            Row(children: [
              _ActionBtn(icon: Icons.check_circle_outline_rounded,
                  label: 'Check In', color: const Color(0xFF22c55e),
                  onTap: onCheckIn),
              const SizedBox(width: 8),
              _ActionBtn(icon: Icons.compare_arrows_rounded,
                  label: 'Compare', color: const Color(0xFF6366f1),
                  onTap: onCompare),
              const SizedBox(width: 8),
              _ActionBtn(icon: Icons.bookmark_border_rounded,
                  label: 'Save', color: const Color(0xFFf59e0b),
                  onTap: onSave),
              const SizedBox(width: 8),
              _ActionBtn(icon: Icons.visibility_off_outlined,
                  label: 'Hide', color: const Color(0xFF9ca3af),
                  onTap: onHide),
            ]),

            // Personal visit history for this restaurant
            Builder(builder: (ctx) {
              final visits = ctx.watch<MapProvider>().visitsFor(r.id);
              if (visits.isEmpty) return const SizedBox.shrink();
              return Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Text('My Visits', style: TextStyle(
                      color: ctx.primaryText, fontSize: 14,
                      fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ...visits.take(3).map((v) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: ctx.secondaryBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        if (v.personalRating != null)
                          Row(mainAxisSize: MainAxisSize.min,
                            children: List.generate(v.personalRating!, (_) =>
                                const Icon(Icons.star_rounded,
                                    size: 12, color: Color(0xFFf59e0b)))),
                        const SizedBox(width: 6),
                        Text(v.visitedAt.toLocal().toString().substring(0, 10),
                            style: TextStyle(color: ctx.secondaryText,
                                fontSize: 11)),
                        if (v.note != null && v.note!.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Expanded(child: Text(v.note!,
                              style: TextStyle(color: ctx.primaryText,
                                  fontSize: 12),
                              overflow: TextOverflow.ellipsis)),
                        ],
                      ]),
                    ),
                  )),
                ],
              );
            }),

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onShowOnMap,
                icon: const Icon(Icons.place_rounded),
                label: const Text('Show on Map'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6535),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

class _StarRating extends StatelessWidget {
  final double rating;
  const _StarRating({required this.rating});

  @override
  Widget build(BuildContext context) {
    final full = rating.floor();
    final half = (rating - full) >= 0.5;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ...List.generate(5, (i) {
        IconData icon;
        if (i < full) icon = Icons.star_rounded;
        else if (i == full && half) icon = Icons.star_half_rounded;
        else icon = Icons.star_outline_rounded;
        return Icon(icon, size: 14, color: const Color(0xFFf59e0b));
      }),
      const SizedBox(width: 4),
      Text(rating.toStringAsFixed(1),
          style: const TextStyle(color: Color(0xFFf59e0b),
              fontSize: 11, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final VoidCallback? onTap;
  const _DetailRow({required this.icon, required this.text,
      required this.color, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: TextStyle(
          color: color, fontSize: 13,
          decoration: onTap != null ? TextDecoration.underline : null))),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// AI assistant sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AISheet extends StatefulWidget {
  final TextEditingController chatCtrl;
  final VoidCallback? onGroupTap;
  final VoidCallback? onHistoryTap;
  final VoidCallback? onHiddenTap;
  const _AISheet({required this.chatCtrl, this.onGroupTap, this.onHistoryTap,
      this.onHiddenTap});

  @override
  State<_AISheet> createState() => _AISheetState();
}

class _AISheetState extends State<_AISheet> {
  final _scrollCtrl = ScrollController();

  // Mood chips — each sends a pre-built question
  static const _moods = [
    (emoji: '🛋️', label: 'Comfort food',
        prompt: 'I want comfort food right now — something warm, hearty, and satisfying. What do you recommend?'),
    (emoji: '💕', label: 'Date night',
        prompt: 'I\'m planning a date night. Suggest the most romantic or impressive restaurant nearby.'),
    (emoji: '⚡', label: 'Quick lunch',
        prompt: 'I need a quick lunch — somewhere fast but good. What\'s nearest and worth it?'),
    (emoji: '🥗', label: 'Healthy',
        prompt: 'I want something healthy — light, fresh, good ingredients. What would you recommend?'),
    (emoji: '👥', label: 'Group',
        prompt: null), // opens group assistant sheet
    (emoji: '📖', label: 'My history',
        prompt: null), // opens history sheet
    (emoji: '📌', label: 'Saved & hidden',
        prompt: null), // opens saved/hidden restaurants sheet
  ];

  void _send() {
    final text = widget.chatCtrl.text.trim();
    if (text.isEmpty) return;
    widget.chatCtrl.clear();
    context.read<MapProvider>().sendMessage(text);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<MapProvider>();
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: context.panelBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6535).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Center(child: Text('✨',
                    style: TextStyle(fontSize: 16))),
              ),
              const SizedBox(width: 10),
              Expanded(child: Builder(builder: (ctx) {
                final focused = ctx.watch<MapProvider>().focusedRestaurant;
                return Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('AI Food Guide',
                          style: TextStyle(
                              color: ctx.primaryText,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      Text(
                        focused != null
                            ? 'Asking about ${focused.name}'
                            : 'Powered by Claude',
                        style: TextStyle(
                          color: focused != null
                              ? ctx.primaryText
                              : ctx.secondaryText,
                          fontSize: 11,
                        ),
                      ),
                    ]);
              })),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: context.secondaryBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close_rounded,
                      color: context.secondaryText, size: 18),
                ),
              ),
            ]),
          ]),
        ),
        Divider(color: context.secondaryBg, height: 20),
        Expanded(child: ListView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            if (p.chatHistory.isEmpty)
              Wrap(spacing: 8, runSpacing: 8,
                  children: _moods.map((m) => GestureDetector(
                    onTap: () {
                      if (m.prompt != null) {
                        widget.chatCtrl.text = m.prompt!;
                        _send();
                      } else if (m.label == 'Group') {
                        Navigator.pop(context);
                        // re-open group sheet (via parent)
                        widget.onGroupTap?.call();
                      } else if (m.label == 'My history') {
                        Navigator.pop(context);
                        widget.onHistoryTap?.call();
                      } else if (m.label == 'Saved & hidden') {
                        Navigator.pop(context);
                        widget.onHiddenTap?.call();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: context.secondaryBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: context.borderColor),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(m.emoji, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 5),
                        Text(m.label, style: TextStyle(
                            fontSize: 12, color: context.primaryText,
                            fontWeight: FontWeight.w500)),
                      ]),
                    ),
                  )).toList()),
            ...p.chatHistory.map((m) => _ChatBubble(message: m)),
            if (p.chatLoading)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Container(width: 26, height: 26,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6535).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(child: Text('✨',
                          style: TextStyle(fontSize: 12)))),
                  const SizedBox(width: 8),
                  const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFFFF6535))),
                ]),
              ),
          ],
        )),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          decoration: BoxDecoration(
            color: context.panelBg,
            border: Border(top: BorderSide(color: context.borderColor)),
          ),
          child: Row(children: [
            Expanded(child: TextField(
              controller: widget.chatCtrl,
              onSubmitted: (_) => _send(),
              style: TextStyle(color: context.primaryText, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Ask about restaurants near you…',
                hintStyle: TextStyle(color: context.hintText, fontSize: 14),
                filled: true,
                fillColor: context.secondaryBg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
            )),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6535),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.arrow_upward_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final Map<String, String> message;
  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message['role'] == 'user';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(width: 26, height: 26,
                decoration: BoxDecoration(
                    color: const Color(0xFFFF6535).withValues(alpha: 0.15),
                    shape: BoxShape.circle),
                child: const Center(child: Text('✨',
                    style: TextStyle(fontSize: 12)))),
            const SizedBox(width: 6),
          ],
          Flexible(child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isUser ? const Color(0xFFFF6535) : context.secondaryBg,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(14),
                topRight: const Radius.circular(14),
                bottomLeft: Radius.circular(isUser ? 14 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 14),
              ),
            ),
            child: isUser
                ? Text(message['content'] ?? '',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 14, height: 1.5))
                : MarkdownBody(
                    data: message['content'] ?? '',
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(color: context.primaryText,
                          fontSize: 14, height: 1.5),
                    ),
                  ),
          )),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _ActionBtn({required this.icon, required this.label,
      required this.color, this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(color: color, fontSize: 10,
              fontWeight: FontWeight.w600)),
        ]),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Collection picker sheet
// ─────────────────────────────────────────────────────────────────────────────

class _CollectionPickerSheet extends StatefulWidget {
  final Restaurant restaurant;
  final MapProvider provider;
  const _CollectionPickerSheet({required this.restaurant, required this.provider});

  @override
  State<_CollectionPickerSheet> createState() => _CollectionPickerSheetState();
}

class _CollectionPickerSheetState extends State<_CollectionPickerSheet> {
  @override
  Widget build(BuildContext context) {
    final cols = widget.provider.collections;
    return Container(
      decoration: BoxDecoration(
        color: context.panelBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _handle(context),
        const SizedBox(height: 14),
        Text('Save to List', style: TextStyle(
            color: context.primaryText, fontSize: 16,
            fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        if (cols.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('No lists yet. Create one below.',
                style: TextStyle(color: context.secondaryText, fontSize: 13)),
          ),
        ...cols.map((c) {
          final has = c.contains(widget.restaurant.id);
          return ListTile(
            dense: true,
            leading: Icon(has ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                color: has ? const Color(0xFFf59e0b) : context.secondaryText),
            title: Text(c.name, style: TextStyle(color: context.primaryText)),
            trailing: Text('${c.restaurantIds.length} places',
                style: TextStyle(color: context.secondaryText, fontSize: 11)),
            onTap: () {
              widget.provider.toggleInCollection(c.id, widget.restaurant.id);
              setState(() {});
            },
          );
        }),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _createList(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('New List'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFF6535),
              side: const BorderSide(color: Color(0xFFFF6535)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ]),
    );
  }

  void _createList(BuildContext ctx) {
    final ctrl = TextEditingController();
    showDialog(context: ctx, builder: (dlgCtx) => AlertDialog(
      backgroundColor: ctx.panelBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text('New List', style: TextStyle(color: ctx.primaryText)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        style: TextStyle(color: ctx.primaryText),
        decoration: InputDecoration(
          hintText: 'e.g. Date spots, Work lunches',
          hintStyle: TextStyle(color: ctx.hintText),
          filled: true, fillColor: ctx.secondaryBg,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dlgCtx),
            child: Text('Cancel', style: TextStyle(color: ctx.secondaryText))),
        ElevatedButton(
          onPressed: () async {
            if (ctrl.text.trim().isEmpty) return;
            final col = await widget.provider.createCollection(ctrl.text.trim());
            widget.provider.toggleInCollection(col.id, widget.restaurant.id);
            Navigator.pop(dlgCtx);
            setState(() {});
          },
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6535),
              foregroundColor: Colors.white),
          child: const Text('Create'),
        ),
      ],
    ));
  }
}

Widget _handle(BuildContext context) => Center(child: Container(
  width: 40, height: 4,
  decoration: BoxDecoration(
    color: context.isDark
        ? Colors.white.withValues(alpha: 0.2)
        : Colors.black.withValues(alpha: 0.1),
    borderRadius: BorderRadius.circular(2),
  ),
));

// ─────────────────────────────────────────────────────────────────────────────
// Group assistant sheet
// ─────────────────────────────────────────────────────────────────────────────

class _GroupAssistantSheet extends StatefulWidget {
  final void Function(String prompt) onSubmit;
  const _GroupAssistantSheet({required this.onSubmit});

  @override
  State<_GroupAssistantSheet> createState() => _GroupAssistantSheetState();
}

class _GroupAssistantSheetState extends State<_GroupAssistantSheet> {
  final List<({TextEditingController name, TextEditingController pref})>
      _members = [];

  @override
  void initState() {
    super.initState();
    _addMember();
    _addMember();
  }

  void _addMember() {
    _members.add((
      name: TextEditingController(),
      pref: TextEditingController(),
    ));
  }

  String _buildPrompt() {
    final lines = _members.where((m) => m.pref.text.trim().isNotEmpty).map((m) {
      final name = m.name.text.trim().isNotEmpty ? m.name.text.trim() : 'Person ${_members.indexOf(m) + 1}';
      return '  • $name: ${m.pref.text.trim()}';
    }).join('\n');
    return 'I\'m planning a group outing. Pick one restaurant nearby that works for everyone:\n$lines\n\nExplain why it fits each person.';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.panelBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _handle(context),
        const SizedBox(height: 14),
        Text('Group Decision', style: TextStyle(color: context.primaryText,
            fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Add each person\'s preference or restriction',
            style: TextStyle(color: context.secondaryText, fontSize: 12)),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.35),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _members.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _members[i].name,
                    style: TextStyle(color: context.primaryText, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Name',
                      hintStyle: TextStyle(color: context.hintText, fontSize: 12),
                      filled: true, fillColor: context.secondaryBg,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: TextField(
                  controller: _members[i].pref,
                  style: TextStyle(color: context.primaryText, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'e.g. vegetarian, loves sushi',
                    hintStyle: TextStyle(color: context.hintText, fontSize: 12),
                    filled: true, fillColor: context.secondaryBg,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                  ),
                )),
              ]),
            ),
          ),
        ),
        TextButton.icon(
          onPressed: () => setState(() => _addMember()),
          icon: const Icon(Icons.add_rounded, size: 16,
              color: Color(0xFFFF6535)),
          label: const Text('Add person',
              style: TextStyle(color: Color(0xFFFF6535), fontSize: 13)),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onSubmit(_buildPrompt());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6535),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Find a place for everyone',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dining history sheet
// ─────────────────────────────────────────────────────────────────────────────

class _HistorySheet extends StatelessWidget {
  const _HistorySheet();

  @override
  Widget build(BuildContext context) {
    final history = context.watch<MapProvider>().diningHistory;
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: context.panelBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(children: [
        _handle(context),
        const SizedBox(height: 14),
        Text('My Dining History', style: TextStyle(color: context.primaryText,
            fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        Expanded(
          child: history.isEmpty
              ? Center(child: Text('No visits logged yet.',
                  style: TextStyle(color: context.secondaryText)))
              : ListView.separated(
                  itemCount: history.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final v = history[i];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.secondaryBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(v.restaurantName, style: TextStyle(
                                  color: context.primaryText, fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                              Text(v.visitedAt.toLocal().toString().substring(0, 10),
                                  style: TextStyle(color: context.secondaryText,
                                      fontSize: 11)),
                              if (v.note != null && v.note!.isNotEmpty)
                                Text(v.note!, style: TextStyle(
                                    color: context.secondaryText, fontSize: 12)),
                            ])),
                        if (v.personalRating != null)
                          Row(mainAxisSize: MainAxisSize.min,
                            children: List.generate(v.personalRating!, (_) =>
                                const Icon(Icons.star_rounded, size: 14,
                                    color: Color(0xFFf59e0b)))),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Saved & hidden restaurants sheet
// ─────────────────────────────────────────────────────────────────────────────

enum _SavedHiddenTab { saved, hidden }

class _SavedHiddenSheet extends StatefulWidget {
  final ValueChanged<Restaurant> onManage;
  const _SavedHiddenSheet({required this.onManage});

  @override
  State<_SavedHiddenSheet> createState() => _SavedHiddenSheetState();
}

class _SavedHiddenSheetState extends State<_SavedHiddenSheet> {
  _SavedHiddenTab _tab = _SavedHiddenTab.saved;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<MapProvider>();
    final items =
        _tab == _SavedHiddenTab.saved ? p.savedRestaurants : p.hiddenRestaurants;
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: context.panelBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(children: [
        _handle(context),
        const SizedBox(height: 14),
        Text('Saved & Hidden', style: TextStyle(color: context.primaryText,
            fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: context.secondaryBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            _tabButton(context, 'Saved', _SavedHiddenTab.saved),
            _tabButton(context, 'Hidden', _SavedHiddenTab.hidden),
          ]),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: items.isEmpty
              ? Center(child: Text(
                  _tab == _SavedHiddenTab.saved
                      ? 'No saved restaurants yet.'
                      : 'No hidden restaurants.',
                  style: TextStyle(color: context.secondaryText)))
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final r = items[i];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.secondaryBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        Text(r.emoji, style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(r.name, style: TextStyle(
                            color: context.primaryText, fontSize: 14,
                            fontWeight: FontWeight.w600))),
                        TextButton(
                          onPressed: () => _tab == _SavedHiddenTab.saved
                              ? widget.onManage(r)
                              : context.read<MapProvider>().unhideRestaurant(r.id),
                          child: Text(
                              _tab == _SavedHiddenTab.saved ? 'Manage' : 'Unhide',
                              style: const TextStyle(color: Color(0xFFFF6535),
                                  fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Widget _tabButton(BuildContext context, String label, _SavedHiddenTab value) {
    final selected = _tab == value;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _tab = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? context.panelBg : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: selected
              ? [BoxShadow(color: context.shadowColor, blurRadius: 4)]
              : null,
        ),
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(
            color: selected ? context.primaryText : context.secondaryText,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      ),
    ));
  }

}

String _formatCount(int n) {
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return n.toString();
}

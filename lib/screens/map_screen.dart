import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/restaurant.dart';
import '../providers/map_provider.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapController = MapController();
  final _searchCtrl = TextEditingController();
  final _chatCtrl = TextEditingController();
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MapProvider>().init();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _chatCtrl.dispose();
    super.dispose();
  }

  // ── Tile URL helpers ──────────────────────────────────────────────────────

  static const _darkTile =
      'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
  static const _satelliteTile =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const _hybridLabelTile =
      'https://basemaps.cartocdn.com/dark_only_labels/{z}/{x}/{y}.png';

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = context.watch<MapProvider>();

    // Sync map controller when provider center changes (e.g. after location loaded)
    if (p.locationLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_mapController.camera.center != p.center) {
          _mapController.move(p.center, 15);
        }
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      body: Stack(
        children: [
          // ── Map ──────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: p.center,
              initialZoom: 15,
              onMapEvent: (event) {
                if (event is MapEventMoveEnd ||
                    event is MapEventFlingAnimationEnd) {
                  p.onMapMoved(event.camera.center);
                }
              },
              onTap: (_, __) {
                p.selectRestaurant(null);
                setState(() => _showSuggestions = false);
                FocusScope.of(context).unfocus();
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    p.isSatellite ? _satelliteTile : _darkTile,
                userAgentPackageName: 'com.philmathieu.cuisinecoord',
                maxZoom: 19,
              ),
              if (p.isSatellite)
                TileLayer(
                  urlTemplate: _hybridLabelTile,
                  userAgentPackageName: 'com.philmathieu.cuisinecoord',
                  maxZoom: 19,
                ),
              MarkerLayer(markers: _buildMarkers(p)),
            ],
          ),

          // ── Top overlay: search + filters ─────────────────────────────────
          _TopOverlay(
            searchCtrl: _searchCtrl,
            showSuggestions: _showSuggestions,
            onSearchChanged: (v) {
              p.setSearch(v);
              setState(() => _showSuggestions = v.isNotEmpty);
            },
            onSuggestionTap: (r) {
              p.selectRestaurant(r);
              _mapController.move(LatLng(r.lat, r.lng), 17);
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
          ),

          // ── Error snack ───────────────────────────────────────────────────
          if (p.error != null)
            Positioned(
              bottom: 100,
              left: 20,
              right: 20,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFef4444),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(p.error!,
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
            ),

          // ── Loading indicator ─────────────────────────────────────────────
          if (p.isLoading)
            Positioned(
              top: 130,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1a1a2e).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFFF6535),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text('Finding restaurants…',
                        style: TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ]),
                ),
              ),
            ),

          // ── Right-side controls ───────────────────────────────────────────
          Positioned(
            right: 16,
            bottom: 100,
            child: Column(children: [
              _MapButton(
                tooltip: 'My location',
                icon: Icons.my_location_rounded,
                onTap: () {
                  _mapController.move(p.center, 15);
                  p.fetchRestaurants(p.center);
                },
              ),
              const SizedBox(height: 10),
              _MapButton(
                tooltip: p.isSatellite ? 'Map view' : 'Satellite view',
                icon: p.isSatellite
                    ? Icons.map_rounded
                    : Icons.satellite_alt_rounded,
                onTap: p.toggleSatellite,
              ),
            ]),
          ),
        ],
      ),

      // ── AI assistant FAB ──────────────────────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'ai_fab',
        backgroundColor: const Color(0xFFFF6535),
        foregroundColor: Colors.white,
        icon: const Text('✨', style: TextStyle(fontSize: 18)),
        label: const Text('AI Assistant',
            style: TextStyle(fontWeight: FontWeight.w600)),
        onPressed: () => _showAISheet(context),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  // ── Markers ───────────────────────────────────────────────────────────────

  List<Marker> _buildMarkers(MapProvider p) {
    return p.visibleRestaurants.map((r) {
      final isSelected = p.selectedRestaurant?.id == r.id;
      return Marker(
        point: LatLng(r.lat, r.lng),
        width: isSelected ? 54 : 42,
        height: isSelected ? 62 : 48,
        child: GestureDetector(
          onTap: () {
            p.selectRestaurant(r);
            _mapController.move(LatLng(r.lat, r.lng), 16);
            _showRestaurantSheet(r);
          },
          child: _RestaurantMarker(restaurant: r, isSelected: isSelected),
        ),
      );
    }).toList();
  }

  // ── Restaurant detail sheet ───────────────────────────────────────────────

  void _showRestaurantSheet(Restaurant r) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _RestaurantSheet(restaurant: r),
    );
  }

  // ── AI assistant sheet ────────────────────────────────────────────────────

  void _showAISheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<MapProvider>(),
        child: _AISheet(chatCtrl: _chatCtrl),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top overlay
// ─────────────────────────────────────────────────────────────────────────────

class _TopOverlay extends StatelessWidget {
  final TextEditingController searchCtrl;
  final bool showSuggestions;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<Restaurant> onSuggestionTap;
  final VoidCallback onClear;

  const _TopOverlay({
    required this.searchCtrl,
    required this.showSuggestions,
    required this.onSearchChanged,
    required this.onSuggestionTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.watch<MapProvider>();

    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: Column(
        children: [
          // Search bar
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1e1e2e),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: TextField(
              controller: searchCtrl,
              onChanged: onSearchChanged,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Search restaurants, cuisine…',
                hintStyle: const TextStyle(
                    color: Color(0xFF6b7280), fontSize: 15),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: Color(0xFFFF6535), size: 22),
                suffixIcon: searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Color(0xFF6b7280), size: 18),
                        onPressed: onClear,
                      )
                    : const Icon(Icons.place_rounded,
                        color: Color(0xFF6b7280), size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.transparent,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

          // Suggestions dropdown
          if (showSuggestions && p.searchSuggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1e1e2e),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                children: p.searchSuggestions.map((r) => ListTile(
                  dense: true,
                  leading: Text(r.emoji,
                      style: const TextStyle(fontSize: 20)),
                  title: Text(r.name,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14)),
                  subtitle: Text(r.displayType,
                      style: const TextStyle(
                          color: Color(0xFF9ca3af), fontSize: 12)),
                  onTap: () => onSuggestionTap(r),
                )).toList(),
              ),
            ),

          const SizedBox(height: 10),

          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: kAmenityFilters.map((f) {
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
                          : const Color(0xFF1e1e2e)
                              .withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      f.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            sel ? Colors.white : const Color(0xFFd1d5db),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Map control button
// ─────────────────────────────────────────────────────────────────────────────

class _MapButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  const _MapButton(
      {required this.tooltip, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF1e1e2e),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Restaurant map marker
// ─────────────────────────────────────────────────────────────────────────────

class _RestaurantMarker extends StatelessWidget {
  final Restaurant restaurant;
  final bool isSelected;
  const _RestaurantMarker(
      {required this.restaurant, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final color = restaurant.markerColor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: isSelected ? 54 : 42,
          height: isSelected ? 54 : 42,
          decoration: BoxDecoration(
            color: isSelected ? color : color.withValues(alpha: 0.85),
            shape: BoxShape.circle,
            border: isSelected
                ? Border.all(color: Colors.white, width: 2.5)
                : null,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: isSelected ? 12 : 6,
                spreadRadius: isSelected ? 2 : 0,
              ),
            ],
          ),
          child: Center(
            child: Text(
              restaurant.emoji,
              style: TextStyle(fontSize: isSelected ? 24 : 18),
            ),
          ),
        ),
        // Pin triangle
        CustomPaint(
          size: const Size(10, 6),
          painter: _PinTipPainter(
              color: isSelected ? color : color.withValues(alpha: 0.85)),
        ),
      ],
    );
  }
}

class _PinTipPainter extends CustomPainter {
  final Color color;
  const _PinTipPainter({required this.color});

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final paint = ui.Paint()..color = color;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PinTipPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Restaurant detail bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _RestaurantSheet extends StatelessWidget {
  final Restaurant restaurant;
  const _RestaurantSheet({required this.restaurant});

  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1e1e2e),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: r.markerColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                  child:
                      Text(r.emoji, style: const TextStyle(fontSize: 26))),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: r.markerColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(r.displayType,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: r.markerColor)),
                    ),
                  ]),
            ),
          ]),
          const SizedBox(height: 20),

          // Details
          if (r.address != null) ...[
            _DetailRow(
              icon: Icons.place_rounded,
              text: r.address!,
              color: const Color(0xFF9ca3af),
            ),
            const SizedBox(height: 10),
          ],
          if (r.phone != null) ...[
            _DetailRow(
              icon: Icons.phone_rounded,
              text: r.phone!,
              color: const Color(0xFF9ca3af),
              onTap: () => launchUrl(Uri.parse('tel:${r.phone}')),
            ),
            const SizedBox(height: 10),
          ],
          if (r.website != null) ...[
            _DetailRow(
              icon: Icons.language_rounded,
              text: r.website!,
              color: const Color(0xFF6366f1),
              onTap: () => launchUrl(Uri.parse(r.website!)),
            ),
            const SizedBox(height: 10),
          ],
          if (r.openingHours != null) ...[
            _DetailRow(
              icon: Icons.access_time_rounded,
              text: r.openingHours!,
              color: const Color(0xFF9ca3af),
            ),
            const SizedBox(height: 10),
          ],

          const SizedBox(height: 12),

          // Directions button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => launchUrl(Uri.parse(
                  'https://www.google.com/maps/dir/?api=1&destination=${r.lat},${r.lng}')),
              icon: const Icon(Icons.directions_rounded),
              label: const Text('Get Directions'),
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
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final VoidCallback? onTap;
  const _DetailRow(
      {required this.icon,
      required this.text,
      required this.color,
      this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: color,
                    fontSize: 13,
                    decoration: onTap != null
                        ? TextDecoration.underline
                        : null)),
          ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// AI assistant bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AISheet extends StatefulWidget {
  final TextEditingController chatCtrl;
  const _AISheet({required this.chatCtrl});

  @override
  State<_AISheet> createState() => _AISheetState();
}

class _AISheetState extends State<_AISheet> {
  final _scrollCtrl = ScrollController();

  static const _suggestions = [
    "What's the best restaurant near me?",
    "Any good pizza places around here?",
    "Where should I go for a date night?",
    "Which cafés are closest?",
  ];

  void _send() {
    final text = widget.chatCtrl.text.trim();
    if (text.isEmpty) return;
    widget.chatCtrl.clear();
    context.read<MapProvider>().sendMessage(text);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<MapProvider>();
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(
        color: Color(0xFF1e1e2e),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        // Handle + header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6535).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                    child: Text('✨', style: TextStyle(fontSize: 16))),
              ),
              const SizedBox(width: 10),
              const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI Food Guide',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    Text('Powered by Claude',
                        style: TextStyle(
                            color: Color(0xFF9ca3af), fontSize: 11)),
                  ]),
            ]),
          ]),
        ),
        const Divider(color: Color(0xFF2d2d3e), height: 20),

        // Chat messages
        Expanded(
          child: ListView(
            controller: _scrollCtrl,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              if (p.chatHistory.isEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _suggestions.map((s) => GestureDetector(
                    onTap: () {
                      widget.chatCtrl.text = s;
                      _send();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2d2d3e),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.07)),
                      ),
                      child: Text(s,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFFd1d5db))),
                    ),
                  )).toList(),
                ),
              ...p.chatHistory.map((m) => _ChatBubble(message: m)),
              if (p.chatLoading)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6535)
                            .withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                          child: Text('✨',
                              style: TextStyle(fontSize: 13))),
                    ),
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFFFF6535)),
                    ),
                  ]),
                ),
            ],
          ),
        ),

        // Input
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1e1e2e),
            border: Border(
              top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.07)),
            ),
          ),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: widget.chatCtrl,
                onSubmitted: (_) => _send(),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Ask about restaurants near you…',
                  hintStyle: const TextStyle(
                      color: Color(0xFF4b5563), fontSize: 14),
                  filled: true,
                  fillColor: const Color(0xFF2d2d3e),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 42,
                height: 42,
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
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: const Color(0xFFFF6535).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Center(
                  child: Text('✨', style: TextStyle(fontSize: 12))),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? const Color(0xFFFF6535)
                    : const Color(0xFF2d2d3e),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isUser ? 14 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 14),
                ),
              ),
              child: isUser
                  ? Text(message['content'] ?? '',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14, height: 1.5))
                  : MarkdownBody(
                      data: message['content'] ?? '',
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(
                            color: Color(0xFFd1d5db),
                            fontSize: 14,
                            height: 1.5),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ignore_for_file: use_build_context_synchronously
//
// ─────────────────────────────────────────────────────────────────────────────
// location_service.dart — FoodFeast
// Uses OpenStreetMap (flutter_map) — FREE, no API key, no billing needed.
//
// ── pubspec.yaml — REMOVE google_maps_flutter & geocoding, ADD these: ────────
//   dependencies:
//     geolocator: ^12.0.0
//     flutter_map: ^7.0.2
//     latlong2: ^0.9.1
//     http: ^1.2.1          # for Nominatim reverse-geocoding (free OSM)
//
// ── AndroidManifest.xml — keep these, remove the Google Maps meta-data: ──────
//   <uses-permission android:name="android.permission.INTERNET"/>
//   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
//   <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
//
// ── No API key needed anywhere. ──────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────
// AppLocation — data model (unchanged)
// ─────────────────────────────────────────────
class AppLocation {
  final double lat;
  final double lng;
  final String address;
  final String shortName;

  const AppLocation({
    required this.lat,
    required this.lng,
    required this.address,
    required this.shortName,
  });

  Map<String, dynamic> toMap() => {
        'lat': lat,
        'lng': lng,
        'address': address,
        'shortName': shortName,
      };

  factory AppLocation.fromMap(Map<String, dynamic> m) => AppLocation(
        lat:       (m['lat'] as num).toDouble(),
        lng:       (m['lng'] as num).toDouble(),
        address:   m['address'] as String? ?? '',
        shortName: m['shortName'] as String? ?? '',
      );
}

// ─────────────────────────────────────────────
// Nominatim — free OpenStreetMap geocoding
// Reverse: lat/lng → address
// Forward: query string → list of places
// No API key needed. Fair-use: max 1 request/second.
// ─────────────────────────────────────────────
class _Nominatim {
  static const _headers = {
    'User-Agent': 'FoodFeastApp/1.0',
    'Accept-Language': 'en',
  };

  // ── Reverse geocode ──────────────────────────────────────────────
  static Future<AppLocation> reverse(double lat, double lng) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=$lat&lon=$lng&format=json&addressdetails=1&zoom=16',
      );
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final addr = data['address'] as Map<String, dynamic>? ?? {};

        final localName = _firstNonEmpty([
          addr['hamlet']        as String?,
          addr['locality']      as String?,
          addr['neighbourhood'] as String?,
          addr['quarter']       as String?,
          addr['suburb']        as String?,
          addr['village']       as String?,
          addr['town']          as String?,
          addr['municipality']  as String?,
          addr['city_district'] as String?,
          addr['city']          as String?,
          addr['county']        as String?,
        ]);

        final district = _firstNonEmpty([
          addr['county']         as String?,
          addr['state_district'] as String?,
          addr['state']          as String?,
        ]);

        final shortName = localName.isNotEmpty
            ? (district.isNotEmpty && district != localName
                ? '$localName, $district'
                : localName)
            : 'Selected Location';

        final fullAddress = data['display_name'] as String? ?? '$lat, $lng';

        return AppLocation(
          lat:       lat,
          lng:       lng,
          address:   fullAddress,
          shortName: shortName,
        );
      }
    } catch (_) {}

    return AppLocation(
      lat:       lat,
      lng:       lng,
      address:   '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
      shortName: 'Selected Location',
    );
  }

  // ── Forward geocode (search) ─────────────────────────────────────
  // Returns up to [limit] results sorted by OSM relevance.
  static Future<List<_SearchResult>> search(String query,
      {int limit = 6}) async {
    if (query.trim().isEmpty) return [];
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}'
        '&format=json&addressdetails=1&limit=$limit',
      );
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List<dynamic>;
        return list.map((e) {
          final m    = e as Map<String, dynamic>;
          final addr = m['address'] as Map<String, dynamic>? ?? {};

          final localName = _firstNonEmpty([
            addr['amenity']       as String?,
            addr['shop']          as String?,
            addr['road']          as String?,
            addr['hamlet']        as String?,
            addr['neighbourhood'] as String?,
            addr['suburb']        as String?,
            addr['village']       as String?,
            addr['town']          as String?,
            addr['city']          as String?,
          ]);

          final district = _firstNonEmpty([
            addr['county']         as String?,
            addr['state_district'] as String?,
            addr['state']          as String?,
          ]);

          final shortName = localName.isNotEmpty
              ? (district.isNotEmpty && district != localName
                  ? '$localName, $district'
                  : localName)
              : (m['display_name'] as String? ?? 'Place')
                  .split(',')
                  .first
                  .trim();

          return _SearchResult(
            lat:         double.tryParse(m['lat'] as String? ?? '') ?? 0,
            lng:         double.tryParse(m['lon'] as String? ?? '') ?? 0,
            displayName: m['display_name'] as String? ?? '',
            shortName:   shortName,
          );
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  static String _firstNonEmpty(List<String?> values) {
    for (final v in values) {
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }
}

// Simple model for a forward-geocode result
class _SearchResult {
  final double lat;
  final double lng;
  final String displayName;
  final String shortName;
  const _SearchResult({
    required this.lat,
    required this.lng,
    required this.displayName,
    required this.shortName,
  });
}

// ─────────────────────────────────────────────
// LocationService — singleton ChangeNotifier
// ─────────────────────────────────────────────
class LocationService extends ChangeNotifier {
  LocationService._() {
    loadSaved();
  }
  static final instance = LocationService._();

  static const _kPrefsKey = 'saved_app_location';

  AppLocation? _current;
  AppLocation? get current => _current;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  Future<void> loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPrefsKey);
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _current = AppLocation.fromMap(map);
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _persist(AppLocation loc) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefsKey, jsonEncode(loc.toMap()));
    } catch (_) {}
  }

  Future<AppLocation?> fetchCurrentLocation() async {
    _loading = true;
    _error   = null;
    notifyListeners();

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _error   = 'Location services are disabled. Please enable GPS.';
        _loading = false;
        notifyListeners();
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _error   = 'Location permission denied.';
          _loading = false;
          notifyListeners();
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _error   = 'Location permission permanently denied. Please enable in Settings.';
        _loading = false;
        notifyListeners();
        return null;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      final loc = await _Nominatim.reverse(pos.latitude, pos.longitude);
      _current  = loc;
      _loading  = false;
      _error    = null;
      await _persist(loc);
      notifyListeners();
      return loc;
    } catch (e) {
      _error   = 'Could not fetch location. Please try again.';
      _loading = false;
      notifyListeners();
      return null;
    }
  }

  Future<AppLocation?> fromLatLng(double lat, double lng) async {
    _loading = true;
    notifyListeners();
    try {
      final loc = await _Nominatim.reverse(lat, lng);
      _current  = loc;
      _loading  = false;
      await _persist(loc);
      notifyListeners();
      return loc;
    } catch (e) {
      _loading = false;
      notifyListeners();
      return null;
    }
  }

  void setLocation(AppLocation loc) {
    _current = loc;
    _persist(loc);
    notifyListeners();
  }
}

// ─────────────────────────────────────────────
// MapPickerScreen — OpenStreetMap version
// Search bar added at top: type a location name,
// pick from dropdown, map jumps to it instantly.
// ─────────────────────────────────────────────
class MapPickerScreen extends StatefulWidget {
  final AppLocation? initialLocation;
  final String title;

  const MapPickerScreen({
    super.key,
    this.initialLocation,
    this.title = 'Choose Location',
  });

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  static const _blue = Color(0xFF0077B6);
  static const _red  = Color(0xFFFF3B30);

  late final MapController _mapCtrl;
  late LatLng _pickedLatLng;
  AppLocation? _pickedLocation;
  bool _resolving = false;

  // Debounce timer for reverse-geocoding on map move
  Timer? _debounce;

  // ── Search state ────────────────────────────
  final _searchCtrl     = TextEditingController();
  final _searchFocus    = FocusNode();
  List<_SearchResult>   _searchResults = [];
  bool _searching       = false;
  bool _showDropdown    = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _mapCtrl = MapController();
    _pickedLatLng = widget.initialLocation != null
        ? LatLng(widget.initialLocation!.lat, widget.initialLocation!.lng)
        : const LatLng(22.0716, 78.9462); // India centre
    _pickedLocation = widget.initialLocation;

    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchDebounce?.cancel();
    _mapCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Search input handler ─────────────────────
  void _onSearchChanged() {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      _searchDebounce?.cancel();
      setState(() {
        _searchResults = [];
        _showDropdown  = false;
        _searching     = false;
      });
      return;
    }
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    if (!mounted) return;
    setState(() { _searching = true; _showDropdown = true; });
    final results = await _Nominatim.search(q);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _searching     = false;
      });
    }
  }

  // Called when the user taps a search result
  void _pickSearchResult(_SearchResult result) {
    _searchFocus.unfocus();
    setState(() {
      _showDropdown  = false;
      _searchResults = [];
    });
    _searchCtrl.text = result.shortName;

    final target = LatLng(result.lat, result.lng);
    _mapCtrl.move(target, 16);
    _pickedLatLng = target;
    _resolveAddress();
  }

  // ── Map move handler ─────────────────────────
  void _onMapEvent(MapEvent event) {
    if (event is MapEventMove || event is MapEventScrollWheelZoom) {
      _pickedLatLng = _mapCtrl.camera.center;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), _resolveAddress);
    }
  }

  Future<void> _resolveAddress() async {
    if (!mounted) return;
    setState(() => _resolving = true);
    final loc = await LocationService.instance
        .fromLatLng(_pickedLatLng.latitude, _pickedLatLng.longitude);
    if (mounted) {
      setState(() {
        _pickedLocation = loc;
        _resolving      = false;
      });
    }
  }

  Future<void> _jumpToGps() async {
    final loc = await LocationService.instance.fetchCurrentLocation();
    if (loc != null && mounted) {
      _mapCtrl.move(LatLng(loc.lat, loc.lng), 16);
    }
  }

  // Dismiss dropdown when tapping outside
  void _dismissDropdown() {
    if (_showDropdown) {
      setState(() => _showDropdown = false);
    }
    _searchFocus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _dismissDropdown,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded,
                color: Color(0xFF1C1C1E), size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(widget.title,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1C1C1E))),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.my_location_rounded, color: _blue),
              tooltip: 'Jump to my GPS location',
              onPressed: _jumpToGps,
            ),
          ],
        ),
        body: Stack(children: [

          // ── OpenStreetMap via flutter_map ─────────────────
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: _pickedLatLng,
              initialZoom: 15,
              onMapEvent: _onMapEvent,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.foodfeast.app',
              ),
            ],
          ),

          // ── Fixed centre pin ─────────────────────────────
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_pin, color: _red, size: 48),
                SizedBox(height: 24),
              ],
            ),
          ),

          // ── OSM attribution ──────────────────────────────
          Positioned(
            bottom: 160,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(4)),
              child: const Text('© OpenStreetMap contributors',
                  style: TextStyle(fontSize: 9, color: Color(0xFF555555))),
            ),
          ),

          // ── Search bar + dropdown (overlaid on map top) ──
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Search input
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.14),
                        blurRadius: 18,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _runSearch(_searchCtrl.text.trim()),
                    style: const TextStyle(
                        fontSize: 14, color: Color(0xFF1C1C1E)),
                    decoration: InputDecoration(
                      hintText: 'Search for a location…',
                      hintStyle: const TextStyle(
                          fontSize: 14, color: Color(0xFFAEAEB2)),
                      prefixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(
                                    color: _blue, strokeWidth: 2),
                              ),
                            )
                          : const Icon(Icons.search_rounded,
                              color: Color(0xFF6E6E73), size: 22),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  color: Color(0xFF6E6E73), size: 20),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {
                                  _searchResults = [];
                                  _showDropdown  = false;
                                });
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 4),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: _blue, width: 1.8)),
                    ),
                  ),
                ),

                // Search results dropdown
                if (_showDropdown && (_searching || _searchResults.isNotEmpty))
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    constraints: const BoxConstraints(maxHeight: 280),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.14),
                          blurRadius: 18,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _searching && _searchResults.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                      color: _blue, strokeWidth: 2),
                                ),
                                SizedBox(width: 10),
                                Text('Searching…',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF6E6E73))),
                              ],
                            ),
                          )
                        : _searchResults.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('No results found.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF6E6E73))),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 6),
                                shrinkWrap: true,
                                itemCount: _searchResults.length,
                                separatorBuilder: (_, __) => const Divider(
                                    height: 1,
                                    indent: 48,
                                    color: Color(0xFFF0F0F0)),
                                itemBuilder: (_, i) {
                                  final r = _searchResults[i];
                                  return InkWell(
                                    onTap: () => _pickSearchResult(r),
                                    borderRadius: BorderRadius.circular(10),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 10),
                                      child: Row(children: [
                                        Container(
                                          width: 30, height: 30,
                                          decoration: BoxDecoration(
                                            color: _blue.withOpacity(0.08),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                              Icons.location_on_rounded,
                                              color: _blue,
                                              size: 16),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(r.shortName,
                                                  style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color:
                                                          Color(0xFF1C1C1E)),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis),
                                              const SizedBox(height: 2),
                                              Text(r.displayName,
                                                  style: const TextStyle(
                                                      fontSize: 11,
                                                      color:
                                                          Color(0xFF6E6E73)),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis),
                                            ],
                                          ),
                                        ),
                                        const Icon(
                                            Icons.north_west_rounded,
                                            color: Color(0xFFAEAEB2),
                                            size: 14),
                                      ]),
                                    ),
                                  );
                                },
                              ),
                  ),
              ],
            ),
          ),

          // ── Bottom card — address + confirm ───────────────
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black26,
                        blurRadius: 20,
                        offset: Offset(0, -4))
                  ]),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Drag handle
                Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                      color: const Color(0xFFE5E5EA),
                      borderRadius: BorderRadius.circular(2)),
                ),

                // Address row
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                        color: _red.withOpacity(0.1),
                        shape: BoxShape.circle),
                    child: const Icon(Icons.location_on_rounded,
                        color: _red, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _resolving
                        ? const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: LinearProgressIndicator(
                                color: _blue,
                                backgroundColor: Color(0xFFE5E5EA)),
                          )
                        : _pickedLocation == null
                            ? const Text('Move map to choose',
                                style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF6E6E73)))
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_pickedLocation!.shortName,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF1C1C1E))),
                                  if (_pickedLocation!.address.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(_pickedLocation!.address,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF6E6E73),
                                            height: 1.4),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                  ],
                                ],
                              ),
                  ),
                ]),

                const SizedBox(height: 18),

                // Confirm button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _blue,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: _resolving || _pickedLocation == null
                        ? null
                        : () => Navigator.pop(context, _pickedLocation),
                    child: const Text('Confirm Location',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// LocationSheet — bottom sheet (unchanged UI)
// ─────────────────────────────────────────────
class LocationSheet extends StatefulWidget {
  final void Function(AppLocation) onLocationSet;
  const LocationSheet({super.key, required this.onLocationSet});

  @override
  State<LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends State<LocationSheet> {
  static const _blue = Color(0xFF0077B6);
  static const _red  = Color(0xFFFF3B30);

  bool _detecting = false;
  String? _error;

  Future<void> _useGps() async {
    setState(() { _detecting = true; _error = null; });
    final loc = await LocationService.instance.fetchCurrentLocation();
    if (!mounted) return;
    setState(() => _detecting = false);
    if (loc != null) {
      widget.onLocationSet(loc);
      Navigator.pop(context);
    } else {
      setState(() => _error = LocationService.instance.error);
    }
  }

  Future<void> _pickOnMap() async {
    Navigator.pop(context);
    final loc = await Navigator.push<AppLocation?>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initialLocation: LocationService.instance.current,
          title: 'Choose Delivery Location',
        ),
      ),
    );
    if (loc != null) {
      LocationService.instance.setLocation(loc);
      widget.onLocationSet(loc);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = LocationService.instance.current;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: const Color(0xFFE5E5EA),
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          const Text('Set Delivery Location',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1C1C1E))),
          const SizedBox(height: 6),
          const Text(
              'We use your location to show nearby restaurants and deliver to you.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: Color(0xFF6E6E73), height: 1.4)),

          if (current != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: _blue.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _blue.withOpacity(0.15))),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded,
                    color: _blue, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(current.shortName,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1C1C1E))),
                    Text(current.address,
                        style: const TextStyle(
                            fontSize: 11.5, color: Color(0xFF6E6E73)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ]),
            ),
          ],

          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(fontSize: 12.5, color: _red)),
          ],

          const SizedBox(height: 20),

          // GPS button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: _detecting ? null : _useGps,
              icon: _detecting
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.my_location_rounded,
                      color: Colors.white, size: 20),
              label: Text(
                  _detecting ? 'Detecting...' : 'Use My Current Location',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 10),

          // Map picker button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFE5E5EA), width: 1.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _pickOnMap,
              icon: const Icon(Icons.map_rounded,
                  color: Color(0xFF1C1C1E), size: 20),
              label: const Text('Choose on Map',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1C1C1E))),
            ),
          ),
        ]),
      ),
    );
  }
}
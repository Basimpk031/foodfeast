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
// Nominatim — free OpenStreetMap reverse geocoding
// No API key needed. Fair-use: max 1 request/second.
// ─────────────────────────────────────────────
class _Nominatim {
  static Future<AppLocation> reverse(double lat, double lng) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=$lat&lon=$lng&format=json&addressdetails=1',
      );
      final response = await http.get(uri, headers: {
        'User-Agent': 'FoodFeastApp/1.0',   // Nominatim requires a User-Agent
        'Accept-Language': 'en',
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final addr = data['address'] as Map<String, dynamic>? ?? {};

        // Build short name: neighbourhood / suburb / city
        final shortName = _firstNonEmpty([
          addr['neighbourhood'] as String?,
          addr['suburb'] as String?,
          addr['village'] as String?,
          addr['town'] as String?,
          addr['city'] as String?,
          addr['county'] as String?,
        ]);

        // Build full address
        final fullAddress = data['display_name'] as String? ?? '$lat, $lng';

        return AppLocation(
          lat:       lat,
          lng:       lng,
          address:   fullAddress,
          shortName: shortName.isNotEmpty ? shortName : 'Selected Location',
        );
      }
    } catch (_) {
      // Network error or timeout — fall through to coordinate fallback
    }

    return AppLocation(
      lat:       lat,
      lng:       lng,
      address:   '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
      shortName: 'Selected Location',
    );
  }

  static String _firstNonEmpty(List<String?> values) {
    for (final v in values) {
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }
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

  // Restores the last saved location from SharedPreferences.
  // Called automatically by the constructor (covers hot reload + cold start).
  Future<void> loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPrefsKey);
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _current = AppLocation.fromMap(map);
        notifyListeners();
      }
    } catch (_) {
      // Corrupt prefs — ignore, user will re-set location
    }
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
        _error = 'Location services are disabled. Please enable GPS.';
        _loading = false;
        notifyListeners();
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _error = 'Location permission denied.';
          _loading = false;
          notifyListeners();
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _error = 'Location permission permanently denied. Please enable in Settings.';
        _loading = false;
        notifyListeners();
        return null;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      final loc = await _Nominatim.reverse(pos.latitude, pos.longitude);
      _current = loc;
      _loading = false;
      _error   = null;
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
      _current = loc;
      _loading = false;
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
// Uses flutter_map with OpenStreetMap tiles.
// No API key. No billing. 100% free.
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

  // Debounce timer so we don't spam Nominatim on every pixel of camera move
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _mapCtrl = MapController();
    _pickedLatLng = widget.initialLocation != null
        ? LatLng(widget.initialLocation!.lat, widget.initialLocation!.lng)
        : const LatLng(22.0716, 78.9462); // India centre
    _pickedLocation = widget.initialLocation;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _mapCtrl.dispose();
    super.dispose();
  }

  // Called on every map move — debounced 600ms then reverse-geocodes
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            // OSM tile layer — free, no key
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.foodfeast.app',
            ),
          ],
        ),

        // ── Fixed centre pin (map moves under it) ─────────
        const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_pin, color: _red, size: 48),
              SizedBox(height: 24), // offset so pin tip sits on map centre
            ],
          ),
        ),

        // ── OSM attribution (required by OSM tile usage policy) ──
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

        // ── Bottom card — address + confirm ───────────────
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: Container(
            decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                                  fontSize: 14, color: Color(0xFF6E6E73)))
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
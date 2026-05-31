// ─────────────────────────────────────────────
// location_filter.dart — FoodFeast
// Shared utility: filter restaurants by user's
// current GPS location within a radius.
// ─────────────────────────────────────────────

import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'location_service.dart'; // your existing LocationService

/// Default radius shown to users (matches Swiggy-style 7 km cap).
const double kDefaultRadiusKm = 7.0;

/// Returns distance in km between user's current location and a restaurant
/// document's `location.lat` / `location.lng` fields.
/// Returns `null` if either location is unavailable.
double? distanceToRestaurant(Map<String, dynamic> restData) {
  final locMap = restData['location'] as Map<String, dynamic>?;
  if (locMap == null) return null;
  final restLat = (locMap['lat'] as num?)?.toDouble();
  final restLng = (locMap['lng'] as num?)?.toDouble();
  if (restLat == null || restLng == null) return null;

  final userLoc = LocationService.instance.current;
  if (userLoc == null) return null;

  // Haversine formula
  const R = 6371.0;
  final dLat = (restLat - userLoc.lat) * (math.pi / 180);
  final dLng = (restLng - userLoc.lng) * (math.pi / 180);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(userLoc.lat * (math.pi / 180)) *
          math.cos(restLat * (math.pi / 180)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return R * c;
}

/// Returns `true` if the restaurant is within [radiusKm] of the user.
/// If user location is unknown, returns `true` (show all — fail open).
bool isRestaurantNearby(
  Map<String, dynamic> restData, {
  double radiusKm = kDefaultRadiusKm,
}) {
  final dist = distanceToRestaurant(restData);
  if (dist == null) return true; // location unknown → show restaurant
  return dist <= radiusKm;
}

/// Filters a list of Firestore [QueryDocumentSnapshot]s to only those
/// within [radiusKm] of the user. Preserves original order.
List<QueryDocumentSnapshot> filterNearbyRestaurants(
  List<QueryDocumentSnapshot> docs, {
  double radiusKm = kDefaultRadiusKm,
}) {
  return docs.where((doc) {
    final data = doc.data() as Map<String, dynamic>;
    return isRestaurantNearby(data, radiusKm: radiusKm);
  }).toList();
}

/// Formats distance for display, e.g. "850 m" or "3.2 km".
String formatDistance(double km) {
  if (km < 1) return '${(km * 1000).round()} m';
  return '${km.toStringAsFixed(1)} km';
}

// ─────────────────────────────────────────────
// Bundle location gate
// ─────────────────────────────────────────────

/// Result of a bundle location check.
class BundleLocationResult {
  /// True when every restaurant in the bundle is within [radiusKm].
  final bool isOrderable;

  /// Names of restaurants that are too far away (empty when [isOrderable] is true).
  final List<String> outOfRangeRestaurantNames;

  const BundleLocationResult({
    required this.isOrderable,
    required this.outOfRangeRestaurantNames,
  });
}

/// Checks whether every restaurant referenced by the bundle items is within
/// [radiusKm] of the user's current location.
///
/// [restaurantLocations] is a map of `restaurantId → {'lat': double, 'lng': double}`.
/// Pass the data you already cached in `_allItems` so there's no extra Firestore read.
///
/// If the user's location is unknown, returns `isOrderable: true` (fail-open,
/// consistent with [isRestaurantNearby]).
BundleLocationResult checkBundleLocation(
  /// Map of restaurantId → location map (must contain 'lat' and 'lng').
  Map<String, Map<String, dynamic>?> restaurantLocations, {
  double radiusKm = kDefaultRadiusKm,
}) {
  final userLoc = LocationService.instance.current;
  if (userLoc == null) {
    // Location unknown — fail open (same policy as isRestaurantNearby).
    return const BundleLocationResult(
        isOrderable: true, outOfRangeRestaurantNames: []);
  }

  final List<String> outOfRange = [];

  for (final entry in restaurantLocations.entries) {
    final locMap = entry.value;
    if (locMap == null) continue; // no location stored → skip (fail open)

    final restData = <String, dynamic>{'location': locMap};
    if (!isRestaurantNearby(restData, radiusKm: radiusKm)) {
      outOfRange.add(entry.key); // key is restaurantId; caller maps to name
    }
  }

  return BundleLocationResult(
    isOrderable: outOfRange.isEmpty,
    outOfRangeRestaurantNames: outOfRange,
  );
}
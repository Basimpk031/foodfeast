// ─────────────────────────────────────────────
// favorites_ratings_service.dart — FoodFeast
//
// Central singleton that handles:
//   • Favorites  → Firestore: users/{uid}/favorites/{itemKey}
//   • Food item reviews  → Firestore: item_ratings/{restaurantId_itemName}/reviews/{uid}
//   • Restaurant reviews → Firestore: restaurant_ratings/{restaurantId}/reviews/{uid}
//   • Average rating recompute on each write
//
// FIX: Added 'userId' field to ReviewEntry.toMap() so Firestore
// security rules that check request.resource.data.userId work correctly.
// ─────────────────────────────────────────────
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

// ─── Model ───────────────────────────────────
class FavoriteItem {
  final String itemName;
  final String restaurantId;
  final String restaurantName;
  final String imageUrl;
  final bool isVeg;
  final double price;

  const FavoriteItem({
    required this.itemName,
    required this.restaurantId,
    required this.restaurantName,
    required this.imageUrl,
    required this.isVeg,
    required this.price,
  });

  Map<String, dynamic> toMap() => {
        'itemName': itemName,
        'restaurantId': restaurantId,
        'restaurantName': restaurantName,
        'imageUrl': imageUrl,
        'isVeg': isVeg,
        'price': price,
        'savedAt': FieldValue.serverTimestamp(),
      };

  factory FavoriteItem.fromMap(Map<String, dynamic> m) => FavoriteItem(
        itemName: m['itemName'] ?? '',
        restaurantId: m['restaurantId'] ?? '',
        restaurantName: m['restaurantName'] ?? '',
        imageUrl: m['imageUrl'] ?? '',
        isVeg: m['isVeg'] ?? false,
        price: (m['price'] ?? 0).toDouble(),
      );
}

class ReviewEntry {
  final String uid;
  final String userName;
  final String userPhotoUrl;
  final double rating;
  final String comment;
  final DateTime createdAt;

  const ReviewEntry({
    required this.uid,
    required this.userName,
    required this.userPhotoUrl,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  // FIX: Added 'userId' field alongside 'uid'.
  // The Firestore rules for item_ratings and restaurant_ratings now use
  // reviewId == request.auth.uid (doc ID check) as the primary write guard,
  // but having userId in the data is good practice and keeps legacy rules working.
  Map<String, dynamic> toMap() => {
        'uid': uid,
        'userId': uid, // ← ADDED: required by any rule checking request.resource.data.userId
        'userName': userName,
        'userPhotoUrl': userPhotoUrl,
        'rating': rating,
        'comment': comment,
        'createdAt': FieldValue.serverTimestamp(),
      };

  factory ReviewEntry.fromMap(Map<String, dynamic> m) => ReviewEntry(
        uid: m['uid'] ?? m['userId'] ?? '',
        userName: m['userName'] ?? 'User',
        userPhotoUrl: m['userPhotoUrl'] ?? '',
        rating: (m['rating'] ?? 0).toDouble(),
        comment: m['comment'] ?? '',
        createdAt: m['createdAt'] != null
            ? (m['createdAt'] as Timestamp).toDate()
            : DateTime.now(),
      );
}

// ─── Service ─────────────────────────────────
class FavoritesRatingsService extends ChangeNotifier {
  FavoritesRatingsService._();
  static final instance = FavoritesRatingsService._();

  final _db = FirebaseFirestore.instance;
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // ════════════════════════════════════════
  // FAVORITES
  // ════════════════════════════════════════

  /// Firestore key: sanitised "restaurantId_itemName"
  String _favKey(String restaurantId, String itemName) =>
      '${restaurantId}_${itemName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';

  CollectionReference? get _favCol {
    final uid = _uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid).collection('favorites');
  }

  /// Stream of all favorites for the current user
  Stream<List<FavoriteItem>> favoritesStream() {
    final uid = _uid;
    if (uid == null) return const Stream.empty();
    return _db
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .orderBy('savedAt', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => FavoriteItem.fromMap(d.data()))
            .toList());
  }

  /// Stream that tells whether a specific item is favorited
  Stream<bool> isFavoriteStream(String restaurantId, String itemName) {
    final uid = _uid;
    if (uid == null) return Stream.value(false);
    final key = _favKey(restaurantId, itemName);
    return _db
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .doc(key)
        .snapshots()
        .map((s) => s.exists);
  }

  Future<void> toggleFavorite(FavoriteItem item) async {
    final col = _favCol;
    if (col == null) return;
    final key = _favKey(item.restaurantId, item.itemName);
    final doc = col.doc(key);
    final snap = await doc.get();
    if (snap.exists) {
      await doc.delete();
    } else {
      await doc.set(item.toMap());
    }
  }

  /// Fast check (single read — use only when stream isn't available)
  Future<bool> isFavorite(String restaurantId, String itemName) async {
    final col = _favCol;
    if (col == null) return false;
    final snap = await col.doc(_favKey(restaurantId, itemName)).get();
    return snap.exists;
  }

  // ════════════════════════════════════════
  // REVIEWS — FOOD ITEMS
  // ════════════════════════════════════════

  String _itemDocId(String restaurantId, String itemName) =>
      '${restaurantId}_${itemName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';

  DocumentReference _itemAggDoc(String restaurantId, String itemName) =>
      _db.collection('item_ratings').doc(_itemDocId(restaurantId, itemName));

  CollectionReference _itemReviewsCol(String restaurantId, String itemName) =>
      _itemAggDoc(restaurantId, itemName).collection('reviews');

  /// Stream of all reviews for a food item (sorted newest first)
  Stream<List<ReviewEntry>> itemReviewsStream(
      String restaurantId, String itemName) {
    return _itemReviewsCol(restaurantId, itemName)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => ReviewEntry.fromMap(d.data() as Map<String, dynamic>))
            .toList());
  }

  /// Returns average rating for an item
  Stream<double> itemAverageRatingStream(
      String restaurantId, String itemName) {
    return _itemAggDoc(restaurantId, itemName)
        .snapshots()
        .map((s) => s.exists
            ? ((s.data() as Map?)?['averageRating'] ?? 0).toDouble()
            : 0.0);
  }

  /// Returns the current user's existing review for an item (null if none)
  Future<ReviewEntry?> myItemReview(
      String restaurantId, String itemName) async {
    final uid = _uid;
    if (uid == null) return null;
    final snap =
        await _itemReviewsCol(restaurantId, itemName).doc(uid).get();
    if (!snap.exists) return null;
    return ReviewEntry.fromMap(snap.data() as Map<String, dynamic>);
  }

  /// Write or update a food item review and recompute average
  Future<void> submitItemReview({
    required String restaurantId,
    required String itemName,
    required double rating,
    required String comment,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not logged in');

    final user = FirebaseAuth.instance.currentUser!;
    final entry = ReviewEntry(
      uid: uid,
      userName: user.displayName ?? 'User',
      userPhotoUrl: user.photoURL ?? '',
      rating: rating,
      comment: comment,
      createdAt: DateTime.now(),
    );

    final col = _itemReviewsCol(restaurantId, itemName);
    await col.doc(uid).set(entry.toMap());

    // Recompute average
    await _recomputeItemAverage(restaurantId, itemName);
  }

  Future<void> _recomputeItemAverage(
      String restaurantId, String itemName) async {
    final snap = await _itemReviewsCol(restaurantId, itemName).get();
    if (snap.docs.isEmpty) return;
    final avg = snap.docs
            .map((d) => (d.data() as Map<String, dynamic>)['rating'] as num)
            .reduce((a, b) => a + b) /
        snap.docs.length;
    await _itemAggDoc(restaurantId, itemName).set({
      'averageRating': avg,
      'reviewCount': snap.docs.length,
    }, SetOptions(merge: true));
  }

  // ════════════════════════════════════════
  // REVIEWS — RESTAURANTS
  // ════════════════════════════════════════

  DocumentReference _restAggDoc(String restaurantId) =>
      _db.collection('restaurant_ratings').doc(restaurantId);

  CollectionReference _restReviewsCol(String restaurantId) =>
      _restAggDoc(restaurantId).collection('reviews');

  Stream<List<ReviewEntry>> restaurantReviewsStream(String restaurantId) {
    return _restReviewsCol(restaurantId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => ReviewEntry.fromMap(d.data() as Map<String, dynamic>))
            .toList());
  }

  Stream<double> restaurantAverageRatingStream(String restaurantId) {
    return _restAggDoc(restaurantId)
        .snapshots()
        .map((s) => s.exists
            ? ((s.data() as Map?)?['averageRating'] ?? 0).toDouble()
            : 0.0);
  }

  Future<ReviewEntry?> myRestaurantReview(String restaurantId) async {
    final uid = _uid;
    if (uid == null) return null;
    final snap = await _restReviewsCol(restaurantId).doc(uid).get();
    if (!snap.exists) return null;
    return ReviewEntry.fromMap(snap.data() as Map<String, dynamic>);
  }

  Future<void> submitRestaurantReview({
    required String restaurantId,
    required double rating,
    required String comment,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('Not logged in');

    final user = FirebaseAuth.instance.currentUser!;
    final entry = ReviewEntry(
      uid: uid,
      userName: user.displayName ?? 'User',
      userPhotoUrl: user.photoURL ?? '',
      rating: rating,
      comment: comment,
      createdAt: DateTime.now(),
    );

    await _restReviewsCol(restaurantId).doc(uid).set(entry.toMap());

    // Recompute average and update restaurants collection
    await _recomputeRestaurantAverage(restaurantId);
  }

  Future<void> _recomputeRestaurantAverage(String restaurantId) async {
    final snap = await _restReviewsCol(restaurantId).get();
    if (snap.docs.isEmpty) return;
    final avg = snap.docs
            .map((d) => (d.data() as Map<String, dynamic>)['rating'] as num)
            .reduce((a, b) => a + b) /
        snap.docs.length;

    final data = {
      'averageRating': avg,
      'reviewCount': snap.docs.length,
    };
    await _restAggDoc(restaurantId).set(data, SetOptions(merge: true));

    // Also update the main restaurants doc so existing UI picks it up
    await _db.collection('restaurants').doc(restaurantId).set(
          {'rating': avg},
          SetOptions(merge: true),
        );
  }

  // ════════════════════════════════════════
  // ELIGIBILITY CHECK
  // ════════════════════════════════════════

  /// Returns true if the current user has a delivered order containing this
  /// restaurant (so they're eligible to review it).
  Future<bool> hasOrderedFromRestaurant(String restaurantId) async {
    final uid = _uid;
    if (uid == null) return false;
    final snap = await _db
        .collection('orders')
        .where('userId', isEqualTo: uid)
        .where('status', isEqualTo: 'delivered')
        .get();
    for (final doc in snap.docs) {
      final data = doc.data();
      final items = (data['items'] as List?) ?? [];
      final hasRest = items.any((i) =>
          (i as Map<String, dynamic>)['restaurantId'] == restaurantId);
      final directRestId = data['restaurantId'] as String?;
      if (hasRest || directRestId == restaurantId) return true;
    }
    return false;
  }

  /// Returns list of {restaurantId, restaurantName, itemName, imageUrl, isVeg, price}
  /// for all items the user has ordered (delivered + active orders).
  Future<List<Map<String, dynamic>>> deliveredItems() async {
    final uid = _uid;
    if (uid == null) return [];
    // Include delivered orders AND active in-progress orders
    final deliveredSnap = await _db
        .collection('orders')
        .where('userId', isEqualTo: uid)
        .where('status', isEqualTo: 'delivered')
        .get();
    final activeStatuses = [
      'placed',
      'confirmed',
      'preparing',
      'out_for_delivery',
      'accepted'
    ];
    final activeSnaps = await Future.wait(
      activeStatuses.map((s) => _db
          .collection('orders')
          .where('userId', isEqualTo: uid)
          .where('status', isEqualTo: s)
          .get()),
    );
    final allDocs = [
      ...deliveredSnap.docs,
      for (final s in activeSnaps) ...s.docs,
    ];
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final doc in allDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final restaurantId = (data['restaurantId'] as String?) ?? '';
      final restaurantName = (data['restaurantName'] as String?) ?? '';
      final items = (data['items'] as List?) ?? [];

      if (items.isNotEmpty) {
        // Nested items array (standard structure)
        for (final raw in items) {
          final item = raw as Map<String, dynamic>;
          final name = (item['name'] ?? '').toString();
          final rid = (item['restaurantId'] ?? restaurantId).toString();
          if (name.isEmpty) continue;
          final key = '${rid}_$name';
          if (seen.contains(key)) continue;
          seen.add(key);
          result.add({
            'restaurantId': rid,
            'restaurantName':
                (item['restaurantName'] ?? restaurantName).toString(),
            'itemName': name,
            'imageUrl': (item['imageUrl'] ?? '').toString(),
            'isVeg': item['isVeg'] ?? true,
            'price': (item['price'] ?? 0).toDouble(),
          });
        }
      } else if (restaurantId.isNotEmpty) {
        // Flat order (no nested items) — add restaurant-level entry as fallback
        final name = (data['itemName'] ?? data['name'] ?? '').toString();
        if (name.isNotEmpty) {
          final key = '${restaurantId}_$name';
          if (!seen.contains(key)) {
            seen.add(key);
            result.add({
              'restaurantId': restaurantId,
              'restaurantName': restaurantName,
              'itemName': name,
              'imageUrl': (data['imageUrl'] ?? '').toString(),
              'isVeg': data['isVeg'] ?? true,
              'price': (data['price'] ?? 0).toDouble(),
            });
          }
        }
      }
    }

    // ── Refresh with LIVE images ──────────────────────────────
    // Order docs only ever store a snapshot of imageUrl taken at checkout
    // time, so an item photo updated later (e.g. re-uploaded via admin/
    // owner panel) would never show here without this. We look up each
    // unique item's current menuItems doc and overwrite the stale URL,
    // falling back to the order snapshot if the item was deleted/renamed
    // or the lookup fails.
    await Future.wait(result.map((entry) async {
      try {
        final q = await _db
            .collection('restaurants')
            .doc(entry['restaurantId'] as String)
            .collection('menuItems')
            .where('name', isEqualTo: entry['itemName'])
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          final live = q.docs.first.data();
          final liveImage = (live['imageUrl'] ?? '').toString();
          if (liveImage.isNotEmpty) entry['imageUrl'] = liveImage;
        }
      } catch (_) {
        // Keep the order-snapshot image on failure — better than nothing.
      }
    }));

    return result;
  }

  /// Returns unique restaurants from all orders (delivered + active).
  Future<List<Map<String, dynamic>>> deliveredRestaurants() async {
    final uid = _uid;
    if (uid == null) return [];
    final deliveredSnap = await _db
        .collection('orders')
        .where('userId', isEqualTo: uid)
        .where('status', isEqualTo: 'delivered')
        .get();
    final activeStatuses = [
      'placed',
      'confirmed',
      'preparing',
      'out_for_delivery',
      'accepted'
    ];
    final activeSnaps = await Future.wait(
      activeStatuses.map((s) => _db
          .collection('orders')
          .where('userId', isEqualTo: uid)
          .where('status', isEqualTo: s)
          .get()),
    );
    final allDocs = [
      ...deliveredSnap.docs,
      for (final s in activeSnaps) ...s.docs,
    ];

    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final doc in allDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final items = (data['items'] as List?) ?? [];

      // Collect from nested items array
      for (final raw in items) {
        final item = raw as Map<String, dynamic>;
        final rid = (item['restaurantId'] as String?) ?? '';
        if (rid.isEmpty || seen.contains(rid)) continue;
        seen.add(rid);
        result.add({
          'restaurantId': rid,
          'restaurantName':
              (item['restaurantName'] ?? data['restaurantName'] ?? '').toString(),
          'imageUrl': (data['restaurantImageUrl'] ?? '').toString(),
        });
      }

      // Fallback: top-level restaurantId (flat orders or orders without nested items)
      final topRid = (data['restaurantId'] as String?) ?? '';
      if (topRid.isNotEmpty && !seen.contains(topRid)) {
        seen.add(topRid);
        result.add({
          'restaurantId': topRid,
          'restaurantName': (data['restaurantName'] ?? '').toString(),
          'imageUrl': (data['restaurantImageUrl'] ?? '').toString(),
        });
      }
    }
    return result;
  }
}
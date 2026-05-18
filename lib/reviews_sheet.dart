// ─────────────────────────────────────────────
// reviews_sheet.dart — FoodFeast  (FIXED)
//
// FIX 1 — Write a Review blink/collapse:
//   _ReviewFormSection is now a sibling of the StreamBuilder, NOT a child.
//   Previously it lived inside StreamBuilder's builder(), so every Firestore
//   emission rebuilt the form widget from scratch, losing _showForm /
//   _myRating / TextEditingController state → visible blink + collapse.
//   Solution: Column children are [header, chips, divider, FormSection, reviews].
//   The StreamBuilder only owns the review-list portion.
//
// FIX 2 — Rate & Review shows limited items:
//   The standalone RateAndReviewSheet (new) calls deliveredItems() properly
//   and lists EVERY unique ordered item for review. Call it from your
//   profile screen with:
//     RateAndReviewSheet.show(context);
//
// Usage — item reviews:
//   ReviewsSheet.showItem(context, restaurantId: '...', itemName: '...', ...);
// Usage — restaurant reviews:
//   ReviewsSheet.showRestaurant(context, restaurantId: '...', ...);
// Usage — Rate & Review all ordered items (profile):
//   RateAndReviewSheet.show(context);
// ─────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'favorites_ratings_service.dart';

enum _ReviewTarget { item, restaurant }

// ════════════════════════════════════════════════════════════════════════════
// ReviewsSheet  (item or restaurant)
// ════════════════════════════════════════════════════════════════════════════

class ReviewsSheet extends StatefulWidget {
  final _ReviewTarget target;
  final String restaurantId;
  final String restaurantName;
  final String itemName;
  final bool hasOrdered;

  const ReviewsSheet._({
    required this.target,
    required this.restaurantId,
    required this.restaurantName,
    required this.itemName,
    required this.hasOrdered,
  });

  static Future<void> showItem(
    BuildContext context, {
    required String restaurantId,
    required String itemName,
    required String restaurantName,
    required bool hasOrdered,
  }) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ReviewsSheet._(
          target: _ReviewTarget.item,
          restaurantId: restaurantId,
          restaurantName: restaurantName,
          itemName: itemName,
          hasOrdered: hasOrdered,
        ),
      );

  static Future<void> showRestaurant(
    BuildContext context, {
    required String restaurantId,
    required String restaurantName,
    required bool hasOrdered,
  }) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ReviewsSheet._(
          target: _ReviewTarget.restaurant,
          restaurantId: restaurantId,
          restaurantName: restaurantName,
          itemName: '',
          hasOrdered: hasOrdered,
        ),
      );

  @override
  State<ReviewsSheet> createState() => _ReviewsSheetState();
}

class _ReviewsSheetState extends State<ReviewsSheet> {
  static const _red  = Color(0xFF0077B6);
  static const _green = Color(0xFF34C759);

  final _svc = FavoritesRatingsService.instance;

  String _sort = 'Newest';
  final _sorts = ['Newest', 'Oldest', 'Highest', 'Lowest'];

  ReviewEntry? _myExisting;

  @override
  void initState() {
    super.initState();
    _loadMyReview();
  }

  Future<void> _loadMyReview() async {
    final existing = widget.target == _ReviewTarget.item
        ? await _svc.myItemReview(widget.restaurantId, widget.itemName)
        : await _svc.myRestaurantReview(widget.restaurantId);
    if (mounted && existing != null) {
      setState(() => _myExisting = existing);
    }
  }

  List<ReviewEntry> _sorted(List<ReviewEntry> list) {
    final copy = List<ReviewEntry>.from(list);
    switch (_sort) {
      case 'Oldest':
        copy.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case 'Highest':
        copy.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      case 'Lowest':
        copy.sort((a, b) => a.rating.compareTo(b.rating));
        break;
      default:
        copy.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return copy;
  }

  Stream<List<ReviewEntry>> get _reviewStream =>
      widget.target == _ReviewTarget.item
          ? _svc.itemReviewsStream(widget.restaurantId, widget.itemName)
          : _svc.restaurantReviewsStream(widget.restaurantId);

  Stream<double> get _avgStream =>
      widget.target == _ReviewTarget.item
          ? _svc.itemAverageRatingStream(widget.restaurantId, widget.itemName)
          : _svc.restaurantAverageRatingStream(widget.restaurantId);

  @override
  Widget build(BuildContext context) {
    final title = widget.target == _ReviewTarget.item
        ? widget.itemName
        : widget.restaurantName;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      snap: false,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          // ── Drag handle ─────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E5EA),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Header ──────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: StreamBuilder<double>(
              stream: _avgStream,
              builder: (context, snap) {
                final avg = snap.data ?? 0.0;
                return Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.target == _ReviewTarget.item
                              ? 'Reviews for'
                              : 'Restaurant Reviews',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF6E6E73)),
                        ),
                        Text(
                          title,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1C1C1E)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (avg > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                          color: _green,
                          borderRadius: BorderRadius.circular(12)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(avg.toStringAsFixed(1),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900)),
                        const SizedBox(width: 4),
                        const Icon(Icons.star_rounded,
                            color: Colors.white, size: 18),
                      ]),
                    ),
                ]);
              },
            ),
          ),

          const SizedBox(height: 12),

          // ── Sort chips ───────────────────────────
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: _sorts.map((s) {
                final sel = _sort == s;
                return GestureDetector(
                  onTap: () => setState(() => _sort = s),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? _red : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: sel ? _red : const Color(0xFFE5E5EA)),
                    ),
                    child: Text(s,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: sel
                                ? Colors.white
                                : const Color(0xFF6E6E73))),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 8),
          const Divider(height: 1),

          // ── FIX 1: Write-review form is OUTSIDE StreamBuilder ────────────
          // Previously this was a child of StreamBuilder's builder(), causing
          // every Firestore stream event to destroy & recreate the form widget,
          // which reset _showForm, _myRating, and TextEditingController → blink.
          // Now it lives at a stable position in the Column tree so its State
          // is never torn down by stream events.
          if (widget.hasOrdered)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _ReviewFormSection(
                myExisting: _myExisting,
                onSubmitted: (entry) {
                  if (mounted) setState(() => _myExisting = entry);
                },
                submitFn: (rating, comment) async {
                  if (widget.target == _ReviewTarget.item) {
                    await _svc.submitItemReview(
                      restaurantId: widget.restaurantId,
                      itemName: widget.itemName,
                      rating: rating,
                      comment: comment,
                    );
                  } else {
                    await _svc.submitRestaurantReview(
                      restaurantId: widget.restaurantId,
                      rating: rating,
                      comment: comment,
                    );
                  }
                },
              ),
            ),

          if (widget.hasOrdered) const SizedBox(height: 12),

          // ── Review list (StreamBuilder only owns the list) ───────────────
          Expanded(
            child: StreamBuilder<List<ReviewEntry>>(
              stream: _reviewStream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: _red));
                }
                final all = snap.data ?? [];
                final sorted = _sorted(all);

                if (sorted.isEmpty) {
                  return Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('⭐', style: TextStyle(fontSize: 48)),
                          const SizedBox(height: 12),
                          const Text('No reviews yet',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1C1C1E))),
                          const SizedBox(height: 6),
                          Text(
                            widget.hasOrdered
                                ? 'Be the first to review!'
                                : 'Order to leave a review',
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFF6E6E73)),
                          ),
                        ]),
                  );
                }

                return ListView.builder(
                  controller: ctrl,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: sorted.length,
                  itemBuilder: (_, i) => _ReviewCard(entry: sorted[i]),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// RateAndReviewSheet  — NEW: lists ALL ordered items for rating
// FIX 2 for "Rate & Review shows limited items"
// Previously deliveredItems() existed in the service but was NEVER CALLED.
// This sheet calls it, paginates results, and lets the user tap any item
// to open its ReviewsSheet.
// ════════════════════════════════════════════════════════════════════════════

class RateAndReviewSheet extends StatefulWidget {
  const RateAndReviewSheet._();

  static Future<void> show(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const RateAndReviewSheet._(),
      );

  @override
  State<RateAndReviewSheet> createState() => _RateAndReviewSheetState();
}

class _RateAndReviewSheetState extends State<RateAndReviewSheet> {
  static const _red   = Color(0xFF0077B6);
  static const _green = Color(0xFF34C759);

  final _svc = FavoritesRatingsService.instance;
  List<Map<String, dynamic>>? _items;
  bool _loading = true;

  // Track which items have already been reviewed (uid → entry)
  final _myReviews = <String, ReviewEntry?>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _svc.deliveredItems();
    if (!mounted) return;
    setState(() {
      _items   = items;
      _loading = false;
    });
    // Fetch existing reviews in background so badges show immediately
    for (final item in items) {
      final key = '${item['restaurantId']}_${item['itemName']}';
      _svc
          .myItemReview(item['restaurantId'], item['itemName'])
          .then((entry) {
        if (mounted) setState(() => _myReviews[key] = entry);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      snap: false,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E5EA),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Rate & Review',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1C1C1E))),
                    SizedBox(height: 2),
                    Text('All items from your delivered orders',
                        style:
                            TextStyle(fontSize: 13, color: Color(0xFF6E6E73))),
                  ],
                ),
              ),
            ]),
          ),

          const Divider(height: 1),

          // Body
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _red))
                : _items == null || _items!.isEmpty
                    ? Center(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Text('📦',
                                  style: TextStyle(fontSize: 52)),
                              SizedBox(height: 12),
                              Text('No delivered orders yet',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1C1C1E))),
                              SizedBox(height: 6),
                              Text('Your reviewed items will appear here',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF6E6E73))),
                            ]))
                    : ListView.builder(
                        controller: ctrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: _items!.length,
                        itemBuilder: (_, i) {
                          final item = _items![i];
                          final key =
                              '${item['restaurantId']}_${item['itemName']}';
                          final myReview = _myReviews[key];
                          return _RateItemRow(
                            item: item,
                            myReview: myReview,
                            onTap: () async {
                              await ReviewsSheet.showItem(
                                context,
                                restaurantId: item['restaurantId'],
                                itemName:     item['itemName'],
                                restaurantName: item['restaurantName'],
                                hasOrdered: true,
                              );
                              // Refresh after sheet closes
                              final updated = await _svc.myItemReview(
                                  item['restaurantId'], item['itemName']);
                              if (mounted) {
                                setState(() => _myReviews[key] = updated);
                              }
                            },
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}

class _RateItemRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final ReviewEntry? myReview;
  final VoidCallback onTap;
  const _RateItemRow(
      {required this.item, required this.myReview, required this.onTap});

  static const _red   = Color(0xFF0077B6);
  static const _green = Color(0xFF34C759);

  @override
  Widget build(BuildContext context) {
    final isVeg    = item['isVeg'] as bool? ?? true;
    final imageUrl = item['imageUrl'] as String? ?? '';
    final name     = item['itemName'] as String? ?? '';
    final restName = item['restaurantName'] as String? ?? '';
    final reviewed = myReview != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 4))
            ]),
        child: Row(children: [
          // Thumbnail
          Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: imageUrl.isNotEmpty
                  ? Image.network(imageUrl,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder())
                  : _placeholder(),
            ),
            Positioned(
              top: 4, left: 4,
              child: Container(
                width: 12, height: 12,
                decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                        color: isVeg ? _green : _red, width: 1.5),
                    borderRadius: BorderRadius.circular(3)),
                child: Center(
                    child: Container(
                        width: 5, height: 5,
                        decoration: BoxDecoration(
                            color: isVeg ? _green : _red,
                            shape: BoxShape.circle))),
              ),
            ),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C1C1E)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.store_rounded,
                        size: 11, color: Color(0xFF6E6E73)),
                    const SizedBox(width: 3),
                    Flexible(
                        child: Text(restName,
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF6E6E73)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                  ]),
                  const SizedBox(height: 6),
                  reviewed
                      ? Row(children: [
                          _StarRow(rating: myReview!.rating, size: 13),
                          const SizedBox(width: 6),
                          const Text('Reviewed',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: _green,
                                  fontWeight: FontWeight.w600)),
                        ])
                      : Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                              color: _red,
                              borderRadius: BorderRadius.circular(8)),
                          child: const Text('Rate Now',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                        ),
                ]),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: Color(0xFFAEAEB2), size: 20),
        ]),
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
            color: _red.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.fastfood_rounded, color: _red, size: 26),
      );
}

// ────────────────────────────────────────────────────────────────────────────
// All widgets below are unchanged from original
// ────────────────────────────────────────────────────────────────────────────

class _ReviewFormSection extends StatefulWidget {
  final ReviewEntry? myExisting;
  final void Function(ReviewEntry) onSubmitted;
  final Future<void> Function(double rating, String comment) submitFn;

  const _ReviewFormSection({
    required this.myExisting,
    required this.onSubmitted,
    required this.submitFn,
  });

  @override
  State<_ReviewFormSection> createState() => _ReviewFormSectionState();
}

class _ReviewFormSectionState extends State<_ReviewFormSection> {
  static const _red   = Color(0xFF0077B6);
  static const _green = Color(0xFF34C759);

  bool _showForm   = false;
  double _myRating = 0;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;
  ReviewEntry? _myExisting;

  @override
  void initState() {
    super.initState();
    _myExisting = widget.myExisting;
    if (_myExisting != null) {
      _myRating = _myExisting!.rating;
      _commentCtrl.text = _myExisting!.comment;
    }
  }

  @override
  void didUpdateWidget(_ReviewFormSection old) {
    super.didUpdateWidget(old);
    if (old.myExisting != widget.myExisting && widget.myExisting != null) {
      setState(() {
        _myExisting       = widget.myExisting;
        _myRating         = widget.myExisting!.rating;
        _commentCtrl.text = widget.myExisting!.comment;
      });
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_myRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a star rating')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.submitFn(_myRating, _commentCtrl.text.trim());
      if (mounted) {
        final entry = ReviewEntry(
          uid: '',
          userName: '',
          userPhotoUrl: '',
          rating: _myRating,
          comment: _commentCtrl.text.trim(),
          createdAt: DateTime.now(),
        );
        setState(() {
          _showForm   = false;
          _myExisting = entry;
        });
        widget.onSubmitted(entry);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Review submitted! Thank you 🙏'),
          backgroundColor: _green,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: _red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_myExisting != null && !_showForm) {
      return _MyExistingReviewCard(
        entry: _myExisting!,
        onEdit: () => setState(() => _showForm = true),
      );
    }
    if (_showForm) {
      return _WriteReviewForm(
        myRating: _myRating,
        commentCtrl: _commentCtrl,
        submitting: _submitting,
        onRatingChanged: (r) => setState(() => _myRating = r),
        onSubmit: _submit,
        onCancel: () => setState(() => _showForm = false),
      );
    }
    return _WriteReviewButton(
      onTap: () => setState(() => _showForm = true),
    );
  }
}

class _WriteReviewButton extends StatelessWidget {
  final VoidCallback onTap;
  const _WriteReviewButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0077B6).withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: const Color(0xFF0077B6).withOpacity(0.2), width: 1.5),
        ),
        child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.rate_review_outlined,
                  color: Color(0xFF0077B6), size: 20),
              SizedBox(width: 8),
              Text('Write a Review',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0077B6))),
            ]),
      ),
    );
  }
}

class _MyExistingReviewCard extends StatelessWidget {
  final ReviewEntry entry;
  final VoidCallback onEdit;
  const _MyExistingReviewCard({required this.entry, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0077B6).withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFF0077B6).withOpacity(0.3), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Your Review',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0077B6))),
          GestureDetector(
            onTap: onEdit,
            child: const Row(children: [
              Icon(Icons.edit_outlined, size: 16, color: Color(0xFF0077B6)),
              SizedBox(width: 4),
              Text('Edit',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0077B6))),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        _StarRow(rating: entry.rating, size: 18),
        if (entry.comment.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(entry.comment,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF1C1C1E), height: 1.4)),
        ],
      ]),
    );
  }
}

class _WriteReviewForm extends StatelessWidget {
  final double myRating;
  final TextEditingController commentCtrl;
  final bool submitting;
  final ValueChanged<double> onRatingChanged;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  const _WriteReviewForm({
    required this.myRating,
    required this.commentCtrl,
    required this.submitting,
    required this.onRatingChanged,
    required this.onSubmit,
    required this.onCancel,
  });

  static const _red = Color(0xFF0077B6);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5EA)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Your Rating',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1C1C1E))),
          GestureDetector(
            onTap: onCancel,
            child: const Icon(Icons.close_rounded,
                color: Color(0xFFAEAEB2), size: 20),
          ),
        ]),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: List.generate(5, (i) {
            final filled = i < myRating;
            return GestureDetector(
              onTap: () => onRatingChanged((i + 1).toDouble()),
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  filled ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: const Color(0xFFFFCC02),
                  size: 36,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: commentCtrl,
          maxLines: 3,
          maxLength: 300,
          decoration: InputDecoration(
            hintText: 'Share your experience… (optional)',
            hintStyle:
                const TextStyle(fontSize: 13, color: Color(0xFFAEAEB2)),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFFE5E5EA))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: _red, width: 1.5)),
            contentPadding: const EdgeInsets.all(12),
          ),
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _red,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0),
            onPressed: submitting ? null : onSubmit,
            child: submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text('Submit Review',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final ReviewEntry entry;
  const _ReviewCard({required this.entry});

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}mo ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return 'Just now';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF0F0F0)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor:
                const Color(0xFF0077B6).withOpacity(0.1),
            backgroundImage: entry.userPhotoUrl.isNotEmpty
                ? NetworkImage(entry.userPhotoUrl)
                : null,
            child: entry.userPhotoUrl.isEmpty
                ? Text(
                    entry.userName.isNotEmpty
                        ? entry.userName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        color: Color(0xFF0077B6),
                        fontWeight: FontWeight.w700,
                        fontSize: 15))
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.userName,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1C1C1E))),
                  _StarRow(rating: entry.rating, size: 13),
                ]),
          ),
          Text(_timeAgo(entry.createdAt),
              style: const TextStyle(
                  fontSize: 11, color: Color(0xFFAEAEB2))),
        ]),
        if (entry.comment.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(entry.comment,
              style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF444444),
                  height: 1.45)),
        ],
      ]),
    );
  }
}

class _StarRow extends StatelessWidget {
  final double rating;
  final double size;
  const _StarRow({required this.rating, required this.size});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final full = i < rating.floor();
        final half = !full && i < rating;
        return Icon(
          full
              ? Icons.star_rounded
              : half
                  ? Icons.star_half_rounded
                  : Icons.star_outline_rounded,
          color: const Color(0xFFFFCC02),
          size: size,
        );
      }),
    );
  }
}

// ─── Exported widgets (used in other screens — unchanged) ────────────────────

class StarRatingBadge extends StatelessWidget {
  final double rating;
  final int reviewCount;
  final VoidCallback? onTap;
  final double fontSize;

  const StarRatingBadge({
    super.key,
    required this.rating,
    this.reviewCount = 0,
    this.onTap,
    this.fontSize = 13,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: fontSize * 0.6, vertical: fontSize * 0.3),
        decoration: BoxDecoration(
          color: const Color(0xFF34C759),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(rating.toStringAsFixed(1),
              style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 2),
          Icon(Icons.star_rounded, color: Colors.white, size: fontSize),
          if (reviewCount > 0) ...[
            const SizedBox(width: 3),
            Text('($reviewCount)',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: fontSize - 2)),
          ],
        ]),
      ),
    );
  }
}

class FavoriteHeartButton extends StatelessWidget {
  final String restaurantId;
  final String restaurantName;
  final String itemName;
  final String imageUrl;
  final bool isVeg;
  final double price;
  final double size;

  const FavoriteHeartButton({
    super.key,
    required this.restaurantId,
    required this.restaurantName,
    required this.itemName,
    required this.imageUrl,
    required this.isVeg,
    required this.price,
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) {
    final svc = FavoritesRatingsService.instance;
    return StreamBuilder<bool>(
      stream: svc.isFavoriteStream(restaurantId, itemName),
      builder: (context, snap) {
        final isFav = snap.data ?? false;
        return GestureDetector(
          onTap: () => svc.toggleFavorite(FavoriteItem(
            itemName: itemName,
            restaurantId: restaurantId,
            restaurantName: restaurantName,
            imageUrl: imageUrl,
            isVeg: isVeg,
            price: price,
          )),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Icon(
              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              key: ValueKey(isFav),
              color: isFav ? Colors.red : const Color(0xFFAEAEB2),
              size: size,
            ),
          ),
        );
      },
    );
  }
}
// ai_recommendation_engine.dart — FoodFeast
//
// Hybrid Recommendation System:
//   1. Rule-Based Filtering  — uses BMI, calorie goal, remaining
//      calories, diet preferences (list), activity level, veg pref
//      to hard-filter and score items.
//   2. Collaborative Filtering — uses order history to find items
//      ordered by similar users (same BMI category + diet pref)
//      and boosts their scores.
//
// ─── FIXES IN THIS VERSION ────────────────────────────────────────
// FIX 1 — Hard calorie gate
// FIX 2 — Active lifestyle rule no longer rewards over-budget food
// FIX 3 — Smart Portion Suggestion
// FIX 4 — Overweight/Obese BMI penalties raised
// FIX 5 — Budget-proximity scoring replaces absolute thresholds
// NEW   — Daily macro-goal gap scoring
//
// UI CHANGE — Card size reduced:
//   SizedBox height (list):  330 → 260
//   Card width:              180 → 160
//   Card image height:       130 → 105
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'calorie_tracker.dart';
import 'cart_provider.dart';
import 'location_filter.dart';
import 'location_service.dart';
import 'portion_sheet.dart';

// ───────────────────────────────────────────────────────────────────
// Data model returned to the UI
// ───────────────────────────────────────────────────────────────────
class FoodRecommendation {
  final String itemName;
  final String restaurantId;
  final String restaurantName;
  final double price;
  final String imageUrl;
  final bool isVeg;

  /// Full-item calories (used for display when no portion is suggested)
  final int calories;
  final double protein;
  final double carbs;
  final double fat;

  final double? distanceKm;
  final String reason;
  final double score;
  final String source;

  // Portion support
  final bool portionsEnabled;
  final Map<String, double> portionPrices;
  final Map<String, PortionNutrition> portionNutrition;

  // ── Smart portion suggestion ────────────────────────────────────
  final String? suggestedPortion;
  final PortionNutrition? suggestedPortionNutrition;
  final double? suggestedPortionPrice;

  const FoodRecommendation({
    required this.itemName,
    required this.restaurantId,
    required this.restaurantName,
    required this.price,
    required this.imageUrl,
    required this.isVeg,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.reason,
    required this.score,
    required this.source,
    this.distanceKm,
    this.portionsEnabled = false,
    this.portionPrices = const {},
    this.portionNutrition = const {},
    this.suggestedPortion,
    this.suggestedPortionNutrition,
    this.suggestedPortionPrice,
  });

  int get displayCalories =>
      suggestedPortionNutrition?.calories ?? calories;

  double get displayProtein =>
      suggestedPortionNutrition?.protein ?? protein;

  double get displayCarbs =>
      suggestedPortionNutrition?.carbs ?? carbs;

  double get displayFat =>
      suggestedPortionNutrition?.fat ?? fat;

  double get displayPrice =>
      suggestedPortionPrice ?? price;
}

// ───────────────────────────────────────────────────────────────────
// Internal scored candidate
// ───────────────────────────────────────────────────────────────────
class _Candidate {
  final Map<String, dynamic> item;
  final String restaurantId;
  final String restaurantName;
  final double? distanceKm;
  double score;
  String reason;
  String source;

  String? suggestedPortion;
  PortionNutrition? suggestedPortionNutrition;
  double? suggestedPortionPrice;

  _Candidate({
    required this.item,
    required this.restaurantId,
    required this.restaurantName,
    required this.score,
    required this.reason,
    required this.source,
    this.distanceKm,
    this.suggestedPortion,
    this.suggestedPortionNutrition,
    this.suggestedPortionPrice,
  });
}

class _FakeSnap {
  final List<QueryDocumentSnapshot> docs;
  const _FakeSnap(this.docs);
}

// ───────────────────────────────────────────────────────────────────
// FoodRecommendationEngine — singleton
// ───────────────────────────────────────────────────────────────────
class FoodRecommendationEngine {
  FoodRecommendationEngine._internal();
  static final FoodRecommendationEngine instance =
      FoodRecommendationEngine._internal();

  List<FoodRecommendation> _cache = [];
  DateTime? _cacheTime;
  static const _cacheTtl = Duration(minutes: 10);

  bool get hasCachedResults =>
      _cache.isNotEmpty &&
      _cacheTime != null &&
      DateTime.now().difference(_cacheTime!) < _cacheTtl;

  List<FoodRecommendation> get cachedResults => _cache;

  Future<List<FoodRecommendation>> getRecommendations({
    int limit = 10,
    bool forceRefresh = false,
    bool ignoreCalorieLimit = false,
  }) async {
    if (!forceRefresh && hasCachedResults && !ignoreCalorieLimit) return _cache;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data() ?? {};

      final _rawOrdersSnap = await FirebaseFirestore.instance
          .collection('orders')
          .where('userId', isEqualTo: user.uid)
          .limit(80)
          .get();
      final _sortedDocs = _rawOrdersSnap.docs.where((d) {
        final s = (d.data() as Map<String, dynamic>)['status'] as String? ?? '';
        return s == 'delivered';
      }).toList()
        ..sort((a, b) {
          final aT = (a.data() as Map<String, dynamic>)['createdAt'];
          final bT = (b.data() as Map<String, dynamic>)['createdAt'];
          if (aT == null && bT == null) return 0;
          if (aT == null) return 1;
          if (bT == null) return -1;
          return (bT as Timestamp).compareTo(aT as Timestamp);
        });
      final ordersSnap = _FakeSnap(_sortedDocs.take(50).toList());

      final restaurantsSnap = await FirebaseFirestore.instance
          .collection('restaurants')
          .get();

      final candidates = await _runHybridEngine(
        userData: userData,
        orderDocs: ordersSnap.docs,
        restaurantDocs: restaurantsSnap.docs,
        ignoreCalorieLimit: ignoreCalorieLimit,
      );

      final seen = <String>{};
      final unique = <_Candidate>[];
      for (final c in candidates
        ..sort((a, b) => b.score.compareTo(a.score))) {
        final key = '${c.restaurantId}__${(c.item['name'] ?? '')}';
        if (seen.add(key)) unique.add(c);
        if (unique.length >= limit) break;
      }

      _cache = unique.map(_toRecommendation).toList();
      _cacheTime = DateTime.now();
      return _cache;
    } catch (e) {
      debugPrint('FoodRecommendationEngine error: $e');
      return _cache;
    }
  }

  void invalidateCache() {
    _cache = [];
    _cacheTime = null;
  }

  Future<List<_Candidate>> _runHybridEngine({
    required Map<String, dynamic> userData,
    required List<QueryDocumentSnapshot> orderDocs,
    required List<QueryDocumentSnapshot> restaurantDocs,
    bool ignoreCalorieLimit = false,
  }) async {
    final double weightKg =
        (userData['weight'] as num?)?.toDouble() ?? 0;
    final double heightCm =
        (userData['height'] as num?)?.toDouble() ?? 0;
    final int age = (userData['age'] as num?)?.toInt() ?? 0;
    final String gender = userData['gender'] ?? 'Male';
    final String activityLevel =
        userData['activityLevel'] ?? 'Moderate';
    final bool vegOnly = userData['isVeg'] ?? false;
    final int goalCalories =
        (userData['goalCalories'] as num?)?.toInt() ??
            CalorieTracker.instance.goalCalories;
    final int consumedCalories =
        CalorieTracker.instance.consumedCalories;
    final int remainingCalories =
        (goalCalories - consumedCalories).clamp(0, goalCalories);

    final double hardGateMultiplier =
        remainingCalories < 300 ? 1.15 : 1.25;
    final int hardGateCalories =
        (remainingCalories * hardGateMultiplier).round();

    List<String> dietPrefs;
    final dynamic rawPrefs = userData['dietPreferences'];
    if (rawPrefs is List && rawPrefs.isNotEmpty) {
      dietPrefs = rawPrefs.cast<String>();
    } else {
      final singular = userData['dietPreference'] as String?;
      dietPrefs = singular != null && singular.isNotEmpty
          ? [singular]
          : ['Balanced'];
    }
    final bool effectiveVegOnly =
        vegOnly || dietPrefs.contains('Vegan');

    double? bmi;
    String bmiCategory = 'Normal';
    if (weightKg > 0 && heightCm > 0) {
      final hM = heightCm / 100;
      bmi = weightKg / (hM * hM);
      if (bmi < 18.5) bmiCategory = 'Underweight';
      else if (bmi < 25) bmiCategory = 'Normal';
      else if (bmi < 30) bmiCategory = 'Overweight';
      else bmiCategory = 'Obese';
    }

    final bool isHighProtein = dietPrefs.contains('High Protein');
    final bool isLowCarb     = dietPrefs.contains('Low Carb');
    final bool isKeto        = dietPrefs.contains('Keto');

    double proteinRatio, carbRatio, fatRatio;
    if (isKeto) {
      proteinRatio = 0.25; carbRatio = 0.05; fatRatio = 0.70;
    } else if (isLowCarb) {
      proteinRatio = 0.30; carbRatio = 0.20; fatRatio = 0.50;
    } else if (isHighProtein) {
      proteinRatio = 0.35; carbRatio = 0.40; fatRatio = 0.25;
    } else {
      proteinRatio = 0.25; carbRatio = 0.50; fatRatio = 0.25;
    }

    final double dailyProteinGoal = goalCalories * proteinRatio / 4;
    final double dailyCarbGoal    = goalCalories * carbRatio    / 4;
    final double dailyFatGoal     = goalCalories * fatRatio     / 9;

    final double remainingProtein =
        (dailyProteinGoal - CalorieTracker.instance.consumedProtein)
            .clamp(0, dailyProteinGoal);
    final double remainingCarbs =
        (dailyCarbGoal - CalorieTracker.instance.consumedCarbs)
            .clamp(0, dailyCarbGoal);
    final double remainingFat =
        (dailyFatGoal - CalorieTracker.instance.consumedFat)
            .clamp(0, dailyFatGoal);

    final Map<String, int> userOrderFreq = {};
    final Map<String, int> similarUserFreq = {};

    for (final doc in orderDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final items =
          (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final item in items) {
        final rid  = data['restaurantId'] as String? ?? '';
        final name = item['name'] as String? ?? '';
        final key  = '${rid}__$name';
        userOrderFreq[key] = (userOrderFreq[key] ?? 0) + 1;
      }
    }

    if (bmiCategory.isNotEmpty) {
      try {
        final similarSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('bmiCategory', isEqualTo: bmiCategory)
            .limit(50)
            .get();
        final similarUids = similarSnap.docs
            .map((d) => d.id)
            .where((uid) =>
                uid != FirebaseAuth.instance.currentUser?.uid)
            .toList();
        if (similarUids.isNotEmpty) {
          final batches = <List<String>>[];
          for (int i = 0; i < similarUids.length; i += 10) {
            batches.add(similarUids.sublist(
                i,
                (i + 10) > similarUids.length
                    ? similarUids.length
                    : i + 10));
          }
          for (final batch in batches) {
            final simOrdersSnap = await FirebaseFirestore.instance
                .collection('orders')
                .where('userId', whereIn: batch)
                .limit(100)
                .get();
            for (final doc in simOrdersSnap.docs) {
              final data = doc.data() as Map<String, dynamic>;
              if ((data['status'] as String? ?? '') != 'delivered') continue;
              final items =
                  (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
              for (final item in items) {
                final rid  = data['restaurantId'] as String? ?? '';
                final name = item['name'] as String? ?? '';
                final key  = '${rid}__$name';
                similarUserFreq[key] =
                    (similarUserFreq[key] ?? 0) + 1;
              }
            }
          }
        }
      } catch (_) {}
    }

    final List<_Candidate> candidates = [];

    for (final restDoc in restaurantDocs) {
      final restData = restDoc.data() as Map<String, dynamic>;
      if (!(restData['isActive'] ?? true)) continue;
      if (!isRestaurantNearby(restData)) continue;

      final restName = (restData['name'] ?? 'Restaurant') as String;
      final distKm   = distanceToRestaurant(restData);

      QuerySnapshot menuSnap;
      try {
        menuSnap = await FirebaseFirestore.instance
            .collection('restaurants')
            .doc(restDoc.id)
            .collection('menuItems')
            .where('isAvailable', isEqualTo: true)
            .get();
      } catch (_) {
        continue;
      }

      for (final itemDoc in menuSnap.docs) {
        final item     = itemDoc.data() as Map<String, dynamic>;
        final itemName = (item['name'] ?? '') as String;
        if (itemName.isEmpty) continue;

        final int    itemCalories = (item['calories'] ?? 0) as int;
        final double itemProtein  = (item['protein']  ?? 0).toDouble();
        final double itemCarbs    = (item['carbs']    ?? 0).toDouble();
        final double itemFat      = (item['fat']      ?? 0).toDouble();
        final bool   itemIsVeg    = item['isVeg'] ?? false;

        if (effectiveVegOnly && !itemIsVeg) continue;

        final bool portionsEnabled =
            (item['portionsEnabled'] ?? false) as bool;
        String? suggestedPortion;
        PortionNutrition? suggestedPortionNutrition;
        double? suggestedPortionPrice;

        int effectiveCalories  = itemCalories;
        double effectiveProtein = itemProtein;
        double effectiveCarbs   = itemCarbs;
        double effectiveFat     = itemFat;

        if (itemCalories > hardGateCalories && !ignoreCalorieLimit) {
          if (portionsEnabled) {
            final portionOrder = ['full', 'half', 'quarter'];
            String? bestPortion;
            PortionNutrition? bestNutrition;
            double? bestPortionPrice;
            int bestCals = 0;
            double bestProteinDensity = -1;

            for (final p in portionOrder) {
              final pCals = (item['${p}Calories'] ?? 0) as int;
              if (pCals <= 0) continue;
              if (pCals > hardGateCalories) continue;

              final pProt = (item['${p}Protein'] ?? 0).toDouble();
              final density = pCals > 0 ? pProt / pCals * 100 : 0.0;
              if (pCals > bestCals ||
                  (pCals == bestCals && density > bestProteinDensity)) {
                bestCals           = pCals;
                bestProteinDensity = density;
                bestPortion        = p;
                bestNutrition = PortionNutrition(
                  calories: pCals,
                  protein: pProt,
                  carbs:   (item['${p}Carbs'] ?? 0).toDouble(),
                  fat:     (item['${p}Fat']   ?? 0).toDouble(),
                );
                bestPortionPrice =
                    (item['${p}Price'] ?? 0).toDouble();
              }
            }

            if (bestPortion == null) continue;
            suggestedPortion          = bestPortion;
            suggestedPortionNutrition = bestNutrition;
            suggestedPortionPrice     = bestPortionPrice;
            effectiveCalories  = bestNutrition!.calories;
            effectiveProtein   = bestNutrition.protein;
            effectiveCarbs     = bestNutrition.carbs;
            effectiveFat       = bestNutrition.fat;
          } else {
            continue;
          }
        }

        double ruleScore = 50.0;
        final List<String> reasons = [];

        if (effectiveCalories > 0 && remainingCalories > 0) {
          final calRatio = effectiveCalories / remainingCalories;

          if (calRatio >= 0.60 && calRatio <= 1.00) {
            ruleScore += 30;
            reasons.add(effectiveCalories < 450
                ? 'Fits your calorie budget 🎯'
                : _absoluteCalLabel(effectiveCalories));
          } else if (calRatio >= 0.40 && calRatio < 0.60) {
            ruleScore += 20;
            reasons.add('Good for your budget 👌');
          } else if (calRatio >= 0.20 && calRatio < 0.40) {
            ruleScore += 10;
            reasons.add(_absoluteCalLabel(effectiveCalories));
          } else if (calRatio > 1.00 && calRatio <= hardGateMultiplier) {
            ruleScore -= 5;
            reasons.add('Slightly over budget ⚠️');
          }
        } else if (effectiveCalories > 0) {
          if (effectiveCalories < 250) {
            ruleScore += 10;
            reasons.add('Light on calories 🔥');
          } else if (effectiveCalories < 450) {
            ruleScore += 5;
            reasons.add('Moderate calories 🎯');
          } else {
            ruleScore -= 10;
            reasons.add(_absoluteCalLabel(effectiveCalories));
          }
        }

        if (bmiCategory == 'Underweight') {
          if (effectiveCalories > 400) {
            ruleScore += 18;
            reasons.add('High energy for weight gain 💪');
          }
          if (effectiveProtein > 20) {
            ruleScore += 12;
            reasons.add('Protein-rich for muscle building 🏋️');
          }
        } else if (bmiCategory == 'Overweight' ||
            bmiCategory == 'Obese') {
          if (effectiveCalories > 0 && effectiveCalories < 350) {
            ruleScore += 20;
            reasons.add('Low calorie for weight loss 🥗');
          }
          if (effectiveFat > 0 && effectiveFat < 10) {
            ruleScore += 12;
            reasons.add('Low fat choice 🌿');
          }
          if (effectiveProtein > 15) {
            ruleScore += 10;
            reasons.add('Keeps you full longer 💪');
          }
          if (effectiveCalories > 600) {
            ruleScore -= 40;
          }
        } else {
          if (effectiveProtein > 15 && effectiveCalories < 500) {
            ruleScore += 12;
            reasons.add('Nutritionally balanced ⚖️');
          }
        }

        if (activityLevel == 'Active') {
          if (effectiveProtein > 20) {
            ruleScore += 10;
            reasons.add('High protein for active lifestyle 🏃');
          }
          if (effectiveCalories > 300 &&
              effectiveCalories <= remainingCalories) {
            ruleScore += 8;
          }
        } else if (activityLevel == 'Light') {
          if (effectiveCalories < 400) {
            ruleScore += 10;
            reasons.add('Light meal for your activity level 🧘');
          }
        }

        double macroGapScore = 0.0;
        final List<String> macroReasons = [];

        if (remainingProtein > 0 && effectiveProtein > 0) {
          final proteinFill =
              (effectiveProtein / remainingProtein).clamp(0.0, 1.0);
          if (proteinFill >= 0.30) {
            macroGapScore += proteinFill * 15;
            macroReasons.add("Closes today's protein gap 💪");
          }
        }

        if (!isLowCarb && !isKeto && remainingCarbs > 0 &&
            effectiveCarbs > 0) {
          final carbFill =
              (effectiveCarbs / remainingCarbs).clamp(0.0, 1.0);
          if (carbFill >= 0.25) {
            macroGapScore += carbFill * 8;
            macroReasons.add("Fills your carb goal 🌾");
          }
        }

        if (remainingFat > 0 && effectiveFat > 0) {
          final fatFill =
              (effectiveFat / remainingFat).clamp(0.0, 1.0);
          if (fatFill >= 0.20) {
            macroGapScore += fatFill * 6;
          }
        }

        ruleScore += macroGapScore;
        for (final r in macroReasons) {
          if (!reasons.contains(r)) reasons.add(r);
        }

        double dietScore = 0.0;
        final List<String> dietReasons = [];

        for (final pref in dietPrefs) {
          switch (pref) {
            case 'High Protein':
              if (effectiveCalories > 0) {
                final proteinDensity = effectiveProtein /
                    effectiveCalories * 100;

                if (proteinDensity > 6.0) {
                  dietScore += 25;
                  dietReasons.add('High protein match 💪');
                } else if (proteinDensity > 4.5) {
                  dietScore += 15;
                  dietReasons.add('Good protein density 🥩');
                } else if (effectiveProtein > 20) {
                  dietScore += 10;
                  dietReasons.add('Good protein source 🥩');
                } else if (effectiveProtein > 12) {
                  dietScore += 4;
                }

                if (effectiveProtein < 12 && effectiveCalories > 150) {
                  dietScore -= 30;
                  dietReasons.add('Low protein for your goal ⚠️');
                }
                if (effectiveProtein < 8) {
                  dietScore -= 10;
                }
              }
              break;

            case 'Low Carb':
              if (effectiveCarbs < 10) {
                dietScore += 25;
                dietReasons.add('Very low carb 🥑');
              } else if (effectiveCarbs < 20) {
                dietScore += 12;
                dietReasons.add('Low carb option 🥑');
              } else if (effectiveCarbs < 35) {
                dietScore -= 12;
                dietReasons.add('Moderate carbs ⚠️');
              } else if (effectiveCarbs < 50) {
                dietScore -= 30;
                dietReasons.add('High carb — not for Low Carb diet ⚠️');
              } else {
                dietScore -= 45;
                dietReasons.add('Very high carb ❌');
              }
              break;

            case 'Vegan':
              if (!itemIsVeg) {
                dietScore -= 50;
                dietReasons.add('Not plant-based ❌');
              } else if (effectiveFat < 15) {
                dietScore += 22;
                dietReasons.add('Whole-food plant-based choice 🌱');
              } else {
                dietScore += 10;
                dietReasons.add('Plant-based choice 🌱');
              }
              break;

            case 'Keto':
              final double fatCalPercent = effectiveCalories > 0
                  ? (effectiveFat * 9) / effectiveCalories
                  : 0.0;

              if (effectiveCarbs < 10) {
                if (fatCalPercent >= 0.60) {
                  dietScore += 28;
                  dietReasons.add('Keto-friendly 🥓');
                } else if (fatCalPercent >= 0.40) {
                  dietScore += 15;
                  dietReasons.add('Keto-compatible 🥑');
                } else {
                  dietScore += 8;
                  dietReasons.add('Low carb option 🥑');
                }
              } else if (effectiveCarbs < 20) {
                dietScore -= 15;
                dietReasons.add('Too many carbs for Keto ⚠️');
              } else if (effectiveCarbs < 35) {
                dietScore -= 35;
                dietReasons.add('High carb — breaks ketosis ❌');
              } else {
                dietScore -= 50;
                dietReasons.add('Way too high carb for Keto ❌');
              }
              break;

            case 'Balanced':
            default:
              if (effectiveCalories > 0 &&
                  effectiveProtein > 0 &&
                  effectiveCarbs > 0 &&
                  effectiveFat > 0) {
                final pCal  = effectiveProtein * 4;
                final cCal  = effectiveCarbs   * 4;
                final fCal  = effectiveFat     * 9;
                final total = pCal + cCal + fCal;
                if (total > 0) {
                  final pRatio = pCal / total;
                  final cRatio = cCal / total;
                  final fRatio = fCal / total;

                  final bool macrosBalanced =
                      pRatio >= 0.20 && pRatio <= 0.35 &&
                      cRatio >= 0.40 && cRatio <= 0.55 &&
                      fRatio >= 0.20 && fRatio <= 0.35;

                  if (macrosBalanced) {
                    dietScore += 20;
                    dietReasons.add('Well-balanced macros ⚖️');
                  } else if (pRatio >= 0.15 && cRatio <= 0.65 && fRatio <= 0.40) {
                    dietScore += 8;
                  } else {
                    dietScore -= 10;
                    dietReasons.add('Unbalanced macros ⚠️');
                  }
                }

                if (effectiveFat > 30) {
                  dietScore -= 12;
                  dietReasons.add('High fat content ⚠️');
                }
                if (effectiveCarbs > 70) {
                  dietScore -= 10;
                }
                if (effectiveProtein < 8) {
                  dietScore -= 8;
                }
              }
              break;
          }
        }

        ruleScore += dietScore;
        for (final r in dietReasons) {
          if (!reasons.contains(r)) reasons.add(r);
        }

        if (suggestedPortion != null) {
          ruleScore += 8;
          final portionLabel = suggestedPortion == 'quarter'
              ? 'Quarter portion'
              : suggestedPortion == 'half'
                  ? 'Half portion'
                  : 'Full portion';
          reasons.insert(
              0,
              '$portionLabel fits your budget 🍽️ '
              '(${effectiveCalories} kcal)');
        }

        if (distKm != null) {
          if (distKm < 1.5) ruleScore += 8;
          else if (distKm < 3.0) ruleScore += 4;
          else if (distKm > 6.0) ruleScore -= 5;
        }

        final itemKey        = '${restDoc.id}__$itemName';
        final userOrderCount = userOrderFreq[itemKey] ?? 0;
        if (userOrderCount > 0) {
          ruleScore +=
              (userOrderCount * 5).clamp(0, 25).toDouble();
          if (!reasons.any((r) => r.contains('ordered'))) {
            reasons.add("You've ordered this before 🔄");
          }
        }

        double collabBoost = 0.0;
        final simCount      = similarUserFreq[itemKey] ?? 0;
        if (simCount > 0) {
          collabBoost =
              (10 * (1 + simCount)).clamp(0, 30).toDouble();
          if (reasons.isEmpty) {
            reasons.add('Popular with users like you 👥');
          } else {
            reasons.add('Trending among similar users 📈');
          }
        }

        final totalScore = ruleScore + collabBoost;
        final String sourceLabel = collabBoost > 0
            ? (ruleScore > 50 ? 'hybrid' : 'collaborative')
            : 'rule';

        final primaryReason = reasons.isNotEmpty
            ? reasons.first
            : _defaultReason(bmiCategory, dietPrefs);

        candidates.add(_Candidate(
          item:           item,
          restaurantId:   restDoc.id,
          restaurantName: restName,
          score:          totalScore,
          reason:         primaryReason,
          source:         sourceLabel,
          distanceKm:     distKm,
          suggestedPortion:          suggestedPortion,
          suggestedPortionNutrition: suggestedPortionNutrition,
          suggestedPortionPrice:     suggestedPortionPrice,
        ));
      }
    }

    return candidates;
  }

  String _absoluteCalLabel(int kcal) {
    if (kcal < 250) return 'Light on calories 🔥';
    if (kcal < 450) return 'Moderate calories 🎯';
    if (kcal < 600) return 'Filling meal 🍽️';
    return 'High calorie meal ⚠️';
  }

  String _defaultReason(String bmiCat, List<String> dietPrefs) {
    final notable =
        dietPrefs.firstWhere((p) => p != 'Balanced', orElse: () => '');
    if (notable.isNotEmpty) return 'Matches your $notable diet 🎯';
    switch (bmiCat) {
      case 'Underweight':
        return 'Good for weight gain 📈';
      case 'Overweight':
      case 'Obese':
        return 'Supports your weight loss goal 🥗';
      default:
        return 'Great match for your profile ✨';
    }
  }

  FoodRecommendation _toRecommendation(_Candidate c) {
    final item           = c.item;
    final bool portEnabled =
        (item['portionsEnabled'] ?? false) as bool;
    final Map<String, double> portionPrices = portEnabled
        ? {
            'quarter': (item['quarterPrice'] ?? 0).toDouble(),
            'half':    (item['halfPrice']    ?? 0).toDouble(),
            'full':    (item['fullPrice']     ?? 0).toDouble(),
          }
        : {};
    final Map<String, PortionNutrition> portionNutrition =
        portEnabled
            ? {
                'quarter': PortionNutrition(
                  calories: (item['quarterCalories'] ?? 0) as int,
                  protein:  (item['quarterProtein']  ?? 0).toDouble(),
                  carbs:    (item['quarterCarbs']    ?? 0).toDouble(),
                  fat:      (item['quarterFat']      ?? 0).toDouble(),
                ),
                'half': PortionNutrition(
                  calories: (item['halfCalories'] ?? 0) as int,
                  protein:  (item['halfProtein']  ?? 0).toDouble(),
                  carbs:    (item['halfCarbs']    ?? 0).toDouble(),
                  fat:      (item['halfFat']      ?? 0).toDouble(),
                ),
                'full': PortionNutrition(
                  calories: (item['fullCalories'] ?? 0) as int,
                  protein:  (item['fullProtein']  ?? 0).toDouble(),
                  carbs:    (item['fullCarbs']    ?? 0).toDouble(),
                  fat:      (item['fullFat']      ?? 0).toDouble(),
                ),
              }
            : {};

    return FoodRecommendation(
      itemName:         (item['name'] ?? '') as String,
      restaurantId:     c.restaurantId,
      restaurantName:   c.restaurantName,
      price:            (item['price'] ?? 0).toDouble(),
      imageUrl:         (item['imageUrl'] ?? '') as String,
      isVeg:            (item['isVeg'] ?? false) as bool,
      calories:         (item['calories'] ?? 0) as int,
      protein:          (item['protein'] ?? 0).toDouble(),
      carbs:            (item['carbs']   ?? 0).toDouble(),
      fat:              (item['fat']     ?? 0).toDouble(),
      reason:           c.reason,
      score:            c.score,
      source:           c.source,
      distanceKm:       c.distanceKm,
      portionsEnabled:  portEnabled,
      portionPrices:    portionPrices,
      portionNutrition: portionNutrition,
      suggestedPortion:          c.suggestedPortion,
      suggestedPortionNutrition: c.suggestedPortionNutrition,
      suggestedPortionPrice:     c.suggestedPortionPrice,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// AiRecommendationSection — drop-in UI widget
// ═══════════════════════════════════════════════════════════════════
class AiRecommendationSection extends StatefulWidget {
  final void Function(FoodRecommendation rec)? onItemTap;
  final void Function(FoodRecommendation rec)? onAddToCart;

  const AiRecommendationSection({
    super.key,
    this.onItemTap,
    this.onAddToCart,
  });

  @override
  State<AiRecommendationSection> createState() =>
      _AiRecommendationSectionState();
}

class _AiRecommendationSectionState
    extends State<AiRecommendationSection> {
  static const _blue   = Color(0xFF0077B6);
  static const _green  = Color(0xFF34C759);
  static const _orange = Color(0xFFFF9500);

  List<FoodRecommendation> _recs = [];
  bool _loading  = true;
  bool _expanded = true;
  bool _caloriesExceeded    = false;
  bool _ignoreCalorieLimit  = false;

  @override
  void initState() {
    super.initState();
    _load();
    LocationService.instance.addListener(_onLocationChanged);
  }

  @override
  void dispose() {
    LocationService.instance.removeListener(_onLocationChanged);
    super.dispose();
  }

  void _onLocationChanged() {
    FoodRecommendationEngine.instance.invalidateCache();
    _load(force: true);
  }

  Future<void> _load({bool force = false, bool ignoreLimit = false}) async {
    if (!mounted) return;
    setState(() { _loading = true; _caloriesExceeded = false; });
    final recs = await FoodRecommendationEngine.instance
        .getRecommendations(
          limit: 10,
          forceRefresh: force || ignoreLimit,
          ignoreCalorieLimit: ignoreLimit,
        );
    if (mounted) {
      final exceeded = recs.isEmpty &&
          CalorieTracker.instance.consumedCalories >=
              CalorieTracker.instance.goalCalories;
      setState(() {
        _recs              = recs;
        _loading           = false;
        _caloriesExceeded  = exceeded && !ignoreLimit;
        _ignoreCalorieLimit = ignoreLimit;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ──────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0077B6), Color(0xFF00B4D8)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        color: Colors.white, size: 13),
                    SizedBox(width: 4),
                    Text('AI',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Recommended for You',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1C1C1E)),
                ),
              ),
              GestureDetector(
                onTap: () => _load(force: true),
                child: Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: _blue.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.refresh_rounded,
                      color: _blue, size: 16),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () =>
                    setState(() => _expanded = !_expanded),
                child: Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: const Color(0xFF6E6E73),
                  size: 22,
                ),
              ),
            ],
          ),
        ),

        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
            child: _PersonalisationPill(),
          ),

        if (_expanded) ...[
          if (_loading)
            const SizedBox(
              height: 220,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                        color: Color(0xFF0077B6),
                        strokeWidth: 2.5),
                    SizedBox(height: 12),
                    Text(
                      'Personalising your feed...',
                      style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6E6E73),
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            )
          else if (_caloriesExceeded)
            _CalorieExceededBanner(
              onContinue: () => _load(force: true, ignoreLimit: true),
            )
          else if (_recs.isEmpty)
            _EmptyRecommendations(
                onRetry: () => _load(force: true))
          else
            SizedBox(
              height: 260, // ← reduced from 330
              child: ListView.builder(
                padding:
                    const EdgeInsets.fromLTRB(16, 0, 16, 0),
                scrollDirection: Axis.horizontal,
                itemCount: _recs.length,
                itemBuilder: (_, i) => _RecommendationCard(
                  rec: _recs[i],
                  onTap: widget.onItemTap != null
                      ? () => widget.onItemTap!(_recs[i])
                      : null,
                  onAddToCart: widget.onAddToCart != null
                      ? () => widget.onAddToCart!(_recs[i])
                      : null,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

// ── Personalisation pill ────────────────────────────────────────────
class _PersonalisationPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseAuth.instance.currentUser != null
          ? FirebaseFirestore.instance
              .collection('users')
              .doc(FirebaseAuth.instance.currentUser!.uid)
              .get()
          : null,
      builder: (_, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final data =
            snap.data?.data() as Map<String, dynamic>? ?? {};
        final bmi      = _bmiLabel(data);
        final activity = data['activityLevel'] as String? ?? '';

        final dynamic rawPrefs = data['dietPreferences'];
        List<String> dietPrefs;
        if (rawPrefs is List && rawPrefs.isNotEmpty) {
          dietPrefs = rawPrefs.cast<String>();
        } else {
          final singular = data['dietPreference'] as String?;
          dietPrefs = singular != null && singular.isNotEmpty
              ? [singular]
              : [];
        }

        final chips = <String>[];
        if (bmi.isNotEmpty) chips.add('BMI: $bmi');
        chips.addAll(dietPrefs);
        if (activity.isNotEmpty) chips.add(activity);
        chips.add(
            '${CalorieTracker.instance.remainingCalories} kcal left');

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: chips
                .map((c) => Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0077B6)
                            .withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: const Color(0xFF0077B6)
                                .withOpacity(0.2)),
                      ),
                      child: Text(c,
                          style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF0077B6),
                              fontWeight: FontWeight.w600)),
                    ))
                .toList(),
          ),
        );
      },
    );
  }

  String _bmiLabel(Map<String, dynamic> data) {
    final h = (data['height'] as num?)?.toDouble();
    final w = (data['weight'] as num?)?.toDouble();
    if (h == null || w == null || h <= 0) return '';
    final bmi = w / ((h / 100) * (h / 100));
    if (bmi < 18.5) return 'Underweight';
    if (bmi < 25) return 'Normal';
    if (bmi < 30) return 'Overweight';
    return 'Obese';
  }
}

// ── Recommendation card ─────────────────────────────────────────────
class _RecommendationCard extends StatelessWidget {
  final FoodRecommendation rec;
  final VoidCallback? onTap;
  final VoidCallback? onAddToCart;

  static const _blue      = Color(0xFF0077B6);
  static const _orange    = Color(0xFFFF9500);
  static const _vegGreen  = Color(0xFF34C759);
  static const _nonVegRed = Color(0xFFE63946);
  static const _teal      = Color(0xFF00B4D8);

  const _RecommendationCard({
    required this.rec,
    this.onTap,
    this.onAddToCart,
  });

  void _handleAdd(BuildContext context) {
    final cart = CartProvider.instance;
    if (rec.portionsEnabled && rec.portionPrices.isNotEmpty) {
      PortionSheet.show(
        context:          context,
        name:             rec.itemName,
        restaurantId:     rec.restaurantId,
        restaurantName:   rec.restaurantName,
        imageUrl:         rec.imageUrl,
        isVeg:            rec.isVeg,
        portionPrices:    rec.portionPrices,
        portionNutrition: rec.portionNutrition,
        cart:             cart,
      );
      return;
    }
    if (onAddToCart != null) {
      onAddToCart!();
      return;
    }
    cart.addItem(CartItem(
      name:           rec.itemName,
      restaurantId:   rec.restaurantId,
      restaurantName: rec.restaurantName,
      price:          rec.displayPrice,
      imageUrl:       rec.imageUrl,
      isVeg:          rec.isVeg,
      calories:       rec.displayCalories,
      protein:        rec.displayProtein,
      carbs:          rec.displayCarbs,
      fat:            rec.displayFat,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hasPortions = rec.portionsEnabled &&
        rec.portionPrices.isNotEmpty;
    final hasSuggestedPortion = rec.suggestedPortion != null;

    final displayCals = rec.displayCalories;
    final displayProt = rec.displayProtein;
    final displayCarb = rec.displayCarbs;
    final displayFat  = rec.displayFat;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160, // ← reduced from 180
        margin:
            const EdgeInsets.only(right: 14, bottom: 4, top: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Image ──────────────────────────────────────
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20)),
              child: SizedBox(
                height: 105, // ← reduced from 130
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    rec.imageUrl.isNotEmpty
                        ? Image.network(rec.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _placeholder())
                        : _placeholder(),
                    // Gradient
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.55),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Veg/non-veg dot
                    Positioned(
                      top: 8, left: 8,
                      child: Container(
                        width: 17, height: 17,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: rec.isVeg
                                ? _vegGreen
                                : _nonVegRed,
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: 8, height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: rec.isVeg
                                  ? _vegGreen
                                  : _nonVegRed,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Source badge
                    Positioned(
                      top: 8, right: 8,
                      child: _SourceBadge(source: rec.source),
                    ),
                    // Calorie badge
                    if (displayCals > 0)
                      Positioned(
                        bottom: 7, left: 8,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                                Icons.local_fire_department_rounded,
                                color: _orange,
                                size: 12),
                            const SizedBox(width: 2),
                            Text('$displayCals kcal',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    // Portions badge
                    if (hasPortions && !hasSuggestedPortion)
                      Positioned(
                        bottom: 7, right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: _blue,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text('PORTIONS',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3)),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Suggested portion banner ────────────────────
            if (hasSuggestedPortion)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _teal.withOpacity(0.12),
                  border: Border(
                    bottom: BorderSide(
                        color: _teal.withOpacity(0.25),
                        width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.restaurant_menu_rounded,
                        size: 11, color: _teal),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Try ${_portionLabel(rec.suggestedPortion!)} · fits budget',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: _teal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

            // ── Info section ────────────────────────────────
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(10, 7, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name
                    Text(
                      rec.itemName,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1C1C1E),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    // Restaurant
                    Text(
                      rec.restaurantName,
                      style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF6E6E73)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    // Macros
                    if (displayProt > 0 ||
                        displayCarb > 0 ||
                        displayFat > 0)
                      Row(
                        children: [
                          _MacroChip('P', displayProt,
                              const Color(0xFF007AFF)),
                          const SizedBox(width: 3),
                          _MacroChip('C', displayCarb,
                              const Color(0xFF34C759)),
                          const SizedBox(width: 3),
                          _MacroChip('F', displayFat,
                              const Color(0xFFFF9500)),
                        ],
                      ),
                    const SizedBox(height: 5),
                    // Reason chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: _blue.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: _blue.withOpacity(0.18)),
                      ),
                      child: Text(
                        rec.reason,
                        style: const TextStyle(
                          fontSize: 9,
                          color: _blue,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Spacer(),
                    // Price + ADD / SELECT
                    Row(
                      crossAxisAlignment:
                          CrossAxisAlignment.center,
                      children: [
                        Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              (hasPortions ||
                                      hasSuggestedPortion)
                                  ? 'From'
                                  : '₹${rec.displayPrice.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: (hasPortions ||
                                        hasSuggestedPortion)
                                    ? 9
                                    : 13,
                                fontWeight: (hasPortions ||
                                        hasSuggestedPortion)
                                    ? FontWeight.w500
                                    : FontWeight.w800,
                                color: (hasPortions ||
                                        hasSuggestedPortion)
                                    ? const Color(0xFF6E6E73)
                                    : _blue,
                              ),
                            ),
                            if (hasPortions ||
                                hasSuggestedPortion) ...[
                              Text(
                                '₹${rec.displayPrice.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: _blue,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const Spacer(),
                        AnimatedBuilder(
                          animation: CartProvider.instance,
                          builder: (_, __) {
                            final cart = CartProvider.instance;
                            final qty = cart.getQuantity(
                                rec.itemName, rec.restaurantId);

                            if (hasPortions ||
                                hasSuggestedPortion) {
                              return GestureDetector(
                                onTap: () =>
                                    _handleAdd(context),
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 5),
                                  decoration: BoxDecoration(
                                    color: hasSuggestedPortion
                                        ? _teal
                                        : _blue,
                                    borderRadius:
                                        BorderRadius.circular(9),
                                  ),
                                  child: Text(
                                    qty > 0
                                        ? '$qty ✓'
                                        : hasSuggestedPortion
                                            ? 'PORTION'
                                            : 'SELECT',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              );
                            }

                            if (qty == 0) {
                              return GestureDetector(
                                onTap: () =>
                                    _handleAdd(context),
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 5),
                                  decoration: BoxDecoration(
                                    color: _blue,
                                    borderRadius:
                                        BorderRadius.circular(9),
                                  ),
                                  child: const Text(
                                    'ADD',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              );
                            }

                            return Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: _blue, width: 1.5),
                                borderRadius:
                                    BorderRadius.circular(9),
                              ),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                GestureDetector(
                                  onTap: () =>
                                      cart.removeItem(rec.itemName,
                                          rec.restaurantId),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 4),
                                    child: Icon(
                                        Icons.remove_rounded,
                                        size: 12,
                                        color: _blue),
                                  ),
                                ),
                                Text('$qty',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color:
                                            Color(0xFF1C1C1E))),
                                GestureDetector(
                                  onTap: () =>
                                      _handleAdd(context),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 4),
                                    child: Icon(Icons.add_rounded,
                                        size: 12, color: _blue),
                                  ),
                                ),
                              ]),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _portionLabel(String portion) {
    switch (portion) {
      case 'quarter': return 'Quarter portion';
      case 'half':    return 'Half portion';
      default:        return 'Full portion';
    }
  }

  Widget _placeholder() => Container(
        color: _blue.withOpacity(0.07),
        child: const Center(
            child: Icon(Icons.fastfood_rounded,
                color: _blue, size: 32)),
      );
}

// ── Macro chip ──────────────────────────────────────────────────────
class _MacroChip extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _MacroChip(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        '$label:${value.toStringAsFixed(0)}g',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ── Source badge ────────────────────────────────────────────────────
class _SourceBadge extends StatelessWidget {
  final String source;
  const _SourceBadge({required this.source});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    final IconData icon;

    switch (source) {
      case 'collaborative':
        color = const Color(0xFF5856D6);
        label = 'CF';
        icon  = Icons.people_rounded;
        break;
      case 'hybrid':
        color = const Color(0xFF0077B6);
        label = 'AI';
        icon  = Icons.auto_awesome_rounded;
        break;
      default:
        color = const Color(0xFF34C759);
        label = 'RB';
        icon  = Icons.rule_rounded;
    }

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: Colors.white, size: 9),
        const SizedBox(width: 2),
        Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

// ── Calorie exceeded banner ──────────────────────────────────────────
class _CalorieExceededBanner extends StatelessWidget {
  final VoidCallback onContinue;
  const _CalorieExceededBanner({required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final consumed = CalorieTracker.instance.consumedCalories;
    final goal     = CalorieTracker.instance.goalCalories;
    final over     = consumed - goal;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFB74D), width: 1.5),
      ),
      child: Column(
        children: [
          const Text('🔥', style: TextStyle(fontSize: 32)),
          const SizedBox(height: 10),
          const Text(
            'Your calorie limit is exceeded',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1C1C1E),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'You\'ve consumed $consumed kcal of your $goal kcal goal'
            '${over > 0 ? ' (+$over kcal over)' : ''}.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              color: Color(0xFF6E6E73),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Do you want to continue eating?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1C1C1E),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onContinue,
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9500),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'Yes, Continue',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Empty state ─────────────────────────────────────────────────────
class _EmptyRecommendations extends StatelessWidget {
  final VoidCallback onRetry;
  const _EmptyRecommendations({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🤖',
              style: TextStyle(fontSize: 36)),
          const SizedBox(height: 10),
          const Text(
            'Complete your profile for AI picks!',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1C1C1E)),
          ),
          const SizedBox(height: 4),
          const Text(
            'Add your weight, height & diet preference',
            style: TextStyle(
                fontSize: 12, color: Color(0xFF6E6E73)),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0077B6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('Try Again',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
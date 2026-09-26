import 'package:flutter/foundation.dart';

import '../domain/pareto_optimizer.dart';
import '../models/evidence.dart';
import '../repositories/hospitality_repository.dart';

enum StayChipFilter {
  all('All Stays'),
  wheelchair('Wheelchair Ramp'),
  solar('100% Solar Energy'),
  zeroWaste('Zero Waste Certified'),
  braille('Braille & Tactile');

  const StayChipFilter(this.label);

  final String label;
}

/// Loads every stay once, Pareto-ranks it, then applies the search query and
/// chip filter in memory. Port of `viewmodel/HospitalityViewModel.kt`.
class HospitalityViewModel extends ChangeNotifier {
  HospitalityViewModel(this._repository) {
    _load();
  }

  final HospitalityRepository _repository;

  List<RankedHospitalityStay> _allRanked = const [];
  List<RankedHospitalityStay> _visible = const [];
  String _query = '';
  StayChipFilter _chipFilter = StayChipFilter.all;
  bool _isLoading = true;

  bool get isLoading => _isLoading;

  List<RankedHospitalityStay> get rankedStays => _visible;

  StayChipFilter get chipFilter => _chipFilter;

  Future<void> _load() async {
    final stays = await _repository.getAllStays();
    _allRanked = ParetoOptimizer.rank(stays);
    _isLoading = false;
    _applyFilters();
  }

  void updateQuery(String query) {
    _query = query;
    _applyFilters();
  }

  void updateChipFilter(StayChipFilter filter) {
    _chipFilter = filter;
    _applyFilters();
  }

  void _applyFilters() {
    final q = _query.trim().toLowerCase();
    _visible = _allRanked.where((ranked) {
      final stay = ranked.stay;
      final matchesQuery =
          q.isEmpty ||
          stay.name.toLowerCase().contains(q) ||
          stay.location.toLowerCase().contains(q) ||
          stay.category.toLowerCase().contains(q);

      bool hasTag(List<String> needles) => stay.accessibilityTags.any(
        (t) => needles.any((n) => t.toLowerCase().contains(n)),
      );

      final matchesChip = switch (_chipFilter) {
        StayChipFilter.all => true,
        StayChipFilter.wheelchair => hasTag(const ['wheelchair', 'step-free']),
        StayChipFilter.solar => stay.energySource.toLowerCase().contains(
          'solar',
        ),
        StayChipFilter.zeroWaste => stay.wastePolicy.toLowerCase().contains(
          'zero',
        ),
        StayChipFilter.braille => hasTag(const ['braille', 'tactile']),
      };

      return matchesQuery && matchesChip;
    }).toList();
    notifyListeners();
  }
}

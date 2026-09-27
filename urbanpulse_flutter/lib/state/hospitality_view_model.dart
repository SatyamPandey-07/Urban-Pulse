import 'package:flutter/foundation.dart';

import '../domain/pareto_optimizer.dart';
import '../models/evidence.dart';
import '../services/live_stays.dart';

enum StayChipFilter {
  all('All Stays'),
  wheelchair('Wheelchair Ramp'),
  solar('100% Solar Energy'),
  zeroWaste('Zero Waste Certified'),
  braille('Braille & Tactile');

  const StayChipFilter(this.label);

  final String label;
}

/// Finds the stays for a place (live, when the screen opens), Pareto-ranks them,
/// then applies the search query and chip filter in memory. Port of
/// `viewmodel/HospitalityViewModel.kt`, now fed by the live stay search.
class HospitalityViewModel extends ChangeNotifier {
  HospitalityViewModel(this._loader) {
    reload();
  }

  final Future<LiveStaysResult> Function() _loader;
  bool _disposed = false;

  /// Why nothing was found, and where what was found came from.
  String? error;
  List<String> sources = const [];
  List<String> warnings = const [];
  int considered = 0;

  List<RankedHospitalityStay> _allRanked = const [];
  List<RankedHospitalityStay> _visible = const [];
  String _query = '';
  StayChipFilter _chipFilter = StayChipFilter.all;
  bool _isLoading = true;

  bool get isLoading => _isLoading;

  List<RankedHospitalityStay> get rankedStays => _visible;

  StayChipFilter get chipFilter => _chipFilter;

  Future<void> reload() async {
    _isLoading = true;
    error = null;
    notifyListeners();
    final r = await _loader();
    if (_disposed) return;
    _allRanked = ParetoOptimizer.rank(r.stays);
    error = r.error;
    sources = r.sources;
    warnings = r.warnings;
    considered = r.considered;
    _isLoading = false;
    _applyFilters();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
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
    if (!_disposed) notifyListeners();
  }
}

import 'package:flutter/material.dart';

import '../core/formatting.dart';
import '../models/itinerary/itinerary.dart';
import '../state/app_scope.dart';
import '../services/tile_cache.dart';
import '../state/map_requests.dart';
import '../widgets/common.dart';

/// Whether a day has anything to put on a map.
bool dayHasMappedPlaces(ItineraryDay day) => day.slots.any((s) => s.kind == SlotKind.visit && s.location != null);

/// Shows a day of the trip on the Live Map (its stops numbered in order), and,
/// with [navigateToRefId], sets off for that stop straight away. Returns false
/// when the day has no places with a position.
bool showDayOnLiveMap(BuildContext context, ItineraryDay day, {String? navigateToRefId}) {
  final services = context.getInheritedWidgetOfExactType<AppScope>()?.services;
  final stops = [
    for (final s in day.slots)
      if (s.kind == SlotKind.visit && s.location != null) TripStop(name: s.title, point: s.location!, when: clock12(s.start), refId: s.refId),
  ];
  if (services == null || stops.isEmpty) {
    showToast(context, 'This day has no places to show on the map.');
    return false;
  }
  final go = navigateToRefId == null ? null : stops.indexWhere((s) => s.refId == navigateToRefId);
  services.mapRequests.show(TripMapRequest(title: 'Day ${day.number} · ${day.title}', stops: stops, navigateTo: go != null && go >= 0 ? go : null));
  // Back to the app's home; it switches to the map.
  Navigator.of(context).popUntil((r) => r.isFirst);
  return true;
}

/// Saves the map around the whole trip (its stops and the stay) on the device,
/// so it can be looked at without signal.
Future<void> saveTripMapOffline(BuildContext context, Itinerary it) async {
  final points = [
    for (final d in it.days)
      for (final s in d.slots)
        if (s.location != null) s.location!,
    ?it.hotel?.location,
  ];
  if (points.isEmpty) {
    showToast(context, 'This trip has no places to save a map for.');
    return;
  }
  showToast(context, 'Saving the map for offline use…');
  final n = await TileCache.instance.saveArea(points);
  if (!context.mounted) return;
  showToast(context, n == 0 ? 'Could not save the map. Check your connection and try again.' : 'Map saved for offline use around your trip.');
}

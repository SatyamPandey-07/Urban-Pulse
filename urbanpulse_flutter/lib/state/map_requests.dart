import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// One place on a day of the trip, as the Live Map needs it.
class TripStop {
  const TripStop({required this.name, required this.point, this.when = '', this.refId});

  final String name;
  final LatLng point;

  /// "9:30 AM", shown beside the name.
  final String when;
  final String? refId;
}

/// A day of the trip to show on the Live Map, and where to start.
class TripMapRequest {
  const TripMapRequest({required this.title, required this.stops, this.navigateTo});

  final String title;
  final List<TripStop> stops;

  /// Set off to this stop straight away (a "Navigate here" tap).
  final int? navigateTo;
}

/// The itinerary screen puts a request here and the Live Map, which lives in
/// another tab, picks it up.
class MapRequests extends ChangeNotifier {
  TripMapRequest? _pending;

  TripMapRequest? get pending => _pending;

  void show(TripMapRequest request) {
    _pending = request;
    notifyListeners();
  }

  /// Hands the request over (once).
  TripMapRequest? take() {
    final r = _pending;
    _pending = null;
    return r;
  }
}

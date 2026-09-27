import 'dart:math' as math;

/// What kind of help is needed.
enum SosCategory {
  general('Emergency'),
  medical('Medical'),
  safety('Personal safety'),
  accident('Accident'),
  fire('Fire');

  const SosCategory(this.label);

  final String label;

  static SosCategory parse(Object? v) => SosCategory.values.firstWhere((c) => c.name == v, orElse: () => SosCategory.general);
}

/// How an SOS was raised.
enum SosSource {
  powerButton('power_button'),
  app('app'),
  notification('notification');

  const SosSource(this.wire);

  final String wire;
}

/// A position fix.
class SosPoint {
  const SosPoint(this.lat, this.lng, {this.accuracyM, this.at});

  final double lat;
  final double lng;
  final double? accuracyM;
  final DateTime? at;

  double kmTo(double lat2, double lng2) => haversineKm(lat, lng, lat2, lng2);

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'accuracyM': accuracyM, 'at': at?.toIso8601String()};

  static SosPoint? fromJson(Object? j) {
    if (j is! Map) return null;
    final lat = j['lat'], lng = j['lng'];
    if (lat is! num || lng is! num) return null;
    return SosPoint(lat.toDouble(), lng.toDouble(), accuracyM: (j['accuracyM'] as num?)?.toDouble(), at: DateTime.tryParse('${j['at']}'));
  }
}

double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 6371 * 2 * math.asin(math.min(1, math.sqrt(a)));
}

enum SosStatus { active, resolved, cancelled }

/// One SOS as stored in `sos_events`.
class SosEvent {
  const SosEvent({
    required this.id,
    required this.userId,
    required this.name,
    required this.category,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.lat,
    this.lng,
    this.accuracyM,
    this.source = 'app',
    this.resolvedAt,
  });

  final String id;
  final String userId;
  final String name;
  final SosCategory category;
  final double? lat;
  final double? lng;
  final double? accuracyM;
  final SosStatus status;
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? resolvedAt;

  /// No heartbeat for this long and an SOS is stale (matches the database).
  static const staleAfter = Duration(hours: 2);

  bool get isActive => status == SosStatus.active;
  bool get hasLocation => lat != null && lng != null;
  bool isStale(DateTime now) => now.difference(updatedAt) > staleAfter;

  static SosEvent fromRow(Map<String, dynamic> r) => SosEvent(
    id: '${r['id']}',
    userId: '${r['user_id']}',
    name: '${r['display_name'] ?? 'Someone'}',
    category: SosCategory.parse(r['category']),
    lat: (r['lat'] as num?)?.toDouble(),
    lng: (r['lng'] as num?)?.toDouble(),
    accuracyM: (r['accuracy_m'] as num?)?.toDouble(),
    status: SosStatus.values.firstWhere((s) => s.name == r['status'], orElse: () => SosStatus.active),
    source: '${r['source'] ?? 'app'}',
    createdAt: DateTime.tryParse('${r['created_at']}')?.toLocal() ?? DateTime.now(),
    updatedAt: DateTime.tryParse('${r['updated_at']}')?.toLocal() ?? DateTime.now(),
    resolvedAt: DateTime.tryParse('${r['resolved_at']}')?.toLocal(),
  );
}

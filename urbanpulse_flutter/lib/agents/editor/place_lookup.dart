import 'package:latlong2/latlong.dart';

import '../../domain/access/access_rules.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../../services/data/http_util.dart';
import '../atithi/hotel_candidate.dart';
import '../bhatkanti/hotspot_candidate.dart';
import '../runtime/agent_toolkit.dart';
import '../runtime/report.dart';

/// Finds one named place for the traveller ("add Eravikulam National Park"):
/// Geoapify, then OpenStreetMap by name, then Wikipedia, always required to land
/// near the destination so a name that exists elsewhere never puts a pin in the
/// wrong country. Never throws; null means "could not find it".
class PlaceLookup {
  PlaceLookup(this.toolkit);

  final AgentToolkit toolkit;

  static const maxKm = 45.0;

  Future<Hotspot?> find(String rawName, {required LatLng center, required String destination, Set<AccessibilityNeed> needs = const {}}) async {
    final name = rawName.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (name.isEmpty || name.length > 90) return null;

    bool near(double lat, double lon) => haversineKm(center.latitude, center.longitude, lat, lon) <= maxKm;

    LatLng? at;
    Map<String, String> tags = const {};
    String? osmId;
    String? source;
    String? url;
    String? title;

    // 1. OpenStreetMap by name (gives tags and opening hours too).
    try {
      final osm = await toolkit.overpass.byName(name, center.latitude, center.longitude, radiusM: (maxKm * 1000).round());
      final hit = osm?.where((p) => near(p.lat, p.lon)).firstOrNull;
      if (hit != null) {
        at = LatLng(hit.lat, hit.lon);
        tags = hit.tags;
        osmId = hit.id;
        title = hit.name;
        source = 'OpenStreetMap';
        url = 'https://www.openstreetmap.org/${hit.id}';
      }
    } catch (_) {
      // try the next source
    }

    // 2. Geoapify geocoding.
    final geo = toolkit.geoapify;
    if (at == null && geo != null && geo.isConfigured) {
      try {
        final c = await geo.geocode('$name, $destination', limit: 3);
        final hit = c?.where((x) => near(x.lat, x.lon)).firstOrNull;
        if (hit != null) {
          at = LatLng(hit.lat, hit.lon);
          title = name;
          source = 'Geoapify';
        }
      } catch (_) {
        // try the next source
      }
    }

    // 3. Wikipedia: a description, and coordinates if it has them.
    String? extract;
    try {
      final w = await toolkit.wikipedia.summary(name);
      if (w != null) {
        extract = w.extract;
        url ??= w.url;
        if (at == null && w.lat != null && w.lon != null && near(w.lat!, w.lon!)) {
          at = LatLng(w.lat!, w.lon!);
          title = w.title;
          source = 'Wikipedia';
        }
      }
    } catch (_) {
      // optional
    }

    // 4. The open geocoder, for a town-sized place.
    if (at == null) {
      try {
        final p = await toolkit.geocoder.lookup('$name $destination');
        if (p != null && near(p.latitude, p.longitude)) {
          at = p;
          title = name;
          source = 'Open-Meteo geocoding';
        }
      } catch (_) {
        // not found
      }
    }
    if (at == null) return null;

    final kind = HotspotCandidates.kindFromTags(tags) ?? HotspotCandidates.kindFromName(name) ?? HotspotKind.other;
    final fee = HotspotCandidates.feeFromTags(tags);
    final why = HotspotCandidates.firstSentence(extract);
    final access = tags.isEmpty ? <AccessibilityNeed, NeedSupport>{} : AccessRules.fromOsmTags(tags, needs, provenance: const Provenance(source: 'OpenStreetMap', confidence: 0.75));

    return Hotspot(
      id: osmId ?? 'user:${HotelCandidates.normalize(name).replaceAll(' ', '_')}',
      name: (title ?? name).length > 90 ? name : (title ?? name),
      location: at,
      kind: kind,
      why: why.isEmpty ? 'A place you asked to add.' : why,
      visitMinutes: HotspotCandidates.defaultVisitMinutes(kind),
      feeInr: fee ?? 0,
      openingHours: tags['opening_hours'],
      isOutdoor: HotspotCandidates.defaultOutdoor(kind),
      score: 0.75,
      access: {
        for (final n in AccessRules.relevant(needs))
          n: access[n] ?? NeedSupport(need: n, level: SupportLevel.unknown, detail: 'No information found', provenance: const Provenance(source: 'none', confidence: 0)),
      },
      sources: [if (url != null) SourceRef(title: title ?? name, url: url, source: source ?? 'Web')],
      provenance: Provenance(source: 'Added by you, located via ${source ?? 'a map'}', url: url, confidence: 0.7),
    );
  }
}

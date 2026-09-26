import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config.dart';

/// Real HTTP client for the Central Registry backend (`server/server.js`) — the
/// same shared SQLite-backed service the web app talks to. Every call returns
/// null on any failure (no network, backend not running, bad response) so
/// callers fall back to the on-device SQLite cache instead of crashing or
/// showing a broken state.
///
/// Port of `network/CentralRegistryClient.kt`.
abstract final class CentralRegistryClient {
  static const _timeout = Duration(seconds: 4);
  static const _jsonHeaders = {
    'Content-Type': 'application/json; charset=utf-8',
  };

  static String get _baseUrl => AppConfig.centralRegistryBaseUrl;

  static Future<List<RegistryExperience>?> fetchExperiences() async {
    final body = await _get('/api/experiences');
    if (body == null) return null;
    try {
      return (jsonDecode(body) as List<dynamic>)
          .map((e) => RegistryExperience.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<RegistryExperience?> createExperience({
    required String name,
    required String category,
    required String location,
    required double duration,
    required int price,
    required int ecoScore,
    required int accessibilityRating,
    required List<String> accessibilityTags,
    required String sustainability,
    required double carbonKg,
  }) async {
    final body = await _send(
      'POST',
      '/api/experiences',
      payload: {
        'name': name,
        'category': category,
        'location': location,
        'duration': duration,
        'price': price,
        'ecoScore': ecoScore,
        'accessibilityRating': accessibilityRating,
        'accessibilityTags': accessibilityTags,
        'sustainability': sustainability,
        'carbonKg': carbonKg,
      },
    );
    return _decodeExperience(body);
  }

  static Future<RegistryExperience?> toggleAvailability(String id) async {
    final body = await _send('PATCH', '/api/experiences/$id/availability');
    return _decodeExperience(body);
  }

  static Future<RegistryExperience?> recordView(String id) =>
      _recordEvent(id, 'view');

  static Future<RegistryExperience?> recordInquiry(String id) =>
      _recordEvent(id, 'inquiry');

  static Future<RegistryExperience?> _recordEvent(
    String id,
    String endpoint,
  ) async {
    final body = await _send('POST', '/api/experiences/$id/$endpoint');
    return _decodeExperience(body);
  }

  /// Real individual booking records for one experience — who actually booked,
  /// not just the aggregate count already shown on the provider card.
  static Future<List<RegistryBooking>?> fetchBookings(
    String experienceId,
  ) async {
    final body = await _get('/api/experiences/$experienceId/bookings');
    if (body == null) return null;
    try {
      return (jsonDecode(body) as List<dynamic>)
          .map((e) => RegistryBooking.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Real individual accessibility reports for one experience, including the
  /// traveler's note text.
  static Future<List<RegistryReport>?> fetchReports(String experienceId) async {
    final body = await _get('/api/experiences/$experienceId/reports');
    if (body == null) return null;
    try {
      return (jsonDecode(body) as List<dynamic>)
          .map((e) => RegistryReport.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<RegistryBooking?> createBooking(
    String experienceId, {
    required String travelerName,
    required int partySize,
    required String bookingDate,
  }) async {
    final body = await _send(
      'POST',
      '/api/experiences/$experienceId/bookings',
      payload: {
        'travelerName': travelerName,
        'partySize': partySize,
        'bookingDate': bookingDate,
      },
    );
    if (body == null) return null;
    try {
      return RegistryBooking.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<RegistryReport?> submitReport(
    String experienceId, {
    required bool confirmsAccessibility,
    required String note,
  }) async {
    final body = await _send(
      'POST',
      '/api/experiences/$experienceId/reports',
      payload: {'confirmsAccessibility': confirmsAccessibility, 'note': note},
    );
    if (body == null) return null;
    try {
      return RegistryReport.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Real cross-user aggregate stats computed by the backend via SQL over actual
  /// rows — not a fabricated headline number. Mirrors the same
  /// `/api/impact-stats` endpoint the web app uses.
  static Future<ImpactStats?> fetchImpactStats() async {
    final body = await _get('/api/impact-stats');
    if (body == null) return null;
    try {
      return ImpactStats.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Real redeemable partner perks from the shared backend. Passing the
  /// traveler's name returns any voucher they have already redeemed, so a
  /// redemption survives a restart instead of living in screen state.
  static Future<List<RegistryPerk>?> fetchPerks({String? travelerName}) async {
    final query = travelerName == null
        ? ''
        : '?travelerName=${Uri.encodeQueryComponent(travelerName)}';
    final body = await _get('/api/perks$query');
    if (body == null) return null;
    try {
      return (jsonDecode(body) as List<dynamic>)
          .map((e) => RegistryPerk.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Redeems a perk and returns it with its real, server-issued voucher code.
  static Future<RegistryPerk?> redeemPerk(
    String perkId, {
    required String travelerName,
  }) async {
    final body = await _send(
      'POST',
      '/api/perks/$perkId/redeem',
      payload: {'travelerName': travelerName},
    );
    if (body == null) return null;
    try {
      return RegistryPerk.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // ---- transport helpers ----

  static RegistryExperience? _decodeExperience(String? body) {
    if (body == null) return null;
    try {
      return RegistryExperience.fromJson(
        jsonDecode(body) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _get(String path) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl$path'))
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return response.body;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _send(
    String method,
    String path, {
    Map<String, dynamic>? payload,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl$path');
      final body = payload == null ? '' : jsonEncode(payload);
      final response = await switch (method) {
        'POST' => http.post(uri, headers: _jsonHeaders, body: body),
        'PATCH' => http.patch(uri, headers: _jsonHeaders, body: body),
        _ => http.get(uri),
      }.timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return response.body;
    } catch (_) {
      return null;
    }
  }
}

class RegistryExperience {
  const RegistryExperience({
    required this.id,
    required this.name,
    required this.category,
    required this.location,
    required this.duration,
    required this.price,
    required this.ecoScore,
    required this.accessibilityRating,
    required this.accessibilityTags,
    required this.sustainability,
    required this.carbonKg,
    required this.isAvailableToday,
    required this.viewsCount,
    required this.inquiryCount,
    required this.bookingCount,
    required this.accessibilityConfirmCount,
    required this.accessibilityDisputeCount,
  });

  final String id;
  final String name;
  final String category;
  final String location;
  final double duration;
  final int price;
  final int ecoScore;
  final int accessibilityRating;
  final List<String> accessibilityTags;
  final String sustainability;
  final double carbonKg;
  final bool isAvailableToday;
  final int viewsCount;
  final int inquiryCount;
  final int bookingCount;
  final int accessibilityConfirmCount;
  final int accessibilityDisputeCount;

  static RegistryExperience fromJson(Map<String, dynamic> o) =>
      RegistryExperience(
        id: o['id'] as String,
        name: o['name'] as String,
        category: o['category'] as String? ?? 'General',
        location: o['location'] as String? ?? 'Unspecified',
        duration: (o['duration'] as num?)?.toDouble() ?? 2.0,
        price: (o['price'] as num?)?.toInt() ?? 350,
        ecoScore: (o['ecoScore'] as num?)?.toInt() ?? 5,
        accessibilityRating: (o['accessibilityRating'] as num?)?.toInt() ?? 75,
        accessibilityTags:
            (o['accessibilityTags'] as List<dynamic>? ?? const [])
                .cast<String>(),
        sustainability: o['sustainability'] as String? ?? '',
        carbonKg: (o['carbonKg'] as num?)?.toDouble() ?? 0.3,
        isAvailableToday: o['isAvailableToday'] as bool? ?? true,
        viewsCount: (o['viewsCount'] as num?)?.toInt() ?? 0,
        inquiryCount: (o['inquiryCount'] as num?)?.toInt() ?? 0,
        bookingCount: (o['bookingCount'] as num?)?.toInt() ?? 0,
        accessibilityConfirmCount:
            (o['accessibilityConfirmCount'] as num?)?.toInt() ?? 0,
        accessibilityDisputeCount:
            (o['accessibilityDisputeCount'] as num?)?.toInt() ?? 0,
      );
}

class RegistryBooking {
  const RegistryBooking({
    required this.id,
    required this.experienceId,
    required this.travelerName,
    required this.partySize,
    required this.bookingDate,
    required this.status,
  });

  final String id;
  final String experienceId;
  final String travelerName;
  final int partySize;
  final String bookingDate;
  final String status;

  static RegistryBooking fromJson(Map<String, dynamic> o) => RegistryBooking(
    id: o['id'] as String,
    experienceId: o['experienceId'] as String,
    travelerName: o['travelerName'] as String? ?? 'Traveler',
    partySize: (o['partySize'] as num?)?.toInt() ?? 1,
    bookingDate: o['bookingDate'] as String? ?? '',
    status: o['status'] as String? ?? 'confirmed',
  );
}

class RegistryReport {
  const RegistryReport({
    required this.id,
    required this.experienceId,
    required this.confirmsAccessibility,
    required this.note,
  });

  final String id;
  final String experienceId;
  final bool confirmsAccessibility;
  final String note;

  static RegistryReport fromJson(Map<String, dynamic> o) => RegistryReport(
    id: o['id'] as String,
    experienceId: o['experienceId'] as String,
    confirmsAccessibility: o['confirmsAccessibility'] as bool? ?? true,
    note: o['note'] as String? ?? '',
  );
}

class ImpactStats {
  const ImpactStats({
    required this.experienceCount,
    required this.bookingCount,
    required this.travelerCount,
    required this.accessibilityConfirmCount,
    required this.accessibilityDisputeCount,
    required this.bookedExperiencesCarbonFootprintKg,
    required this.averageEcoScore,
  });

  final int experienceCount;
  final int bookingCount;
  final int travelerCount;
  final int accessibilityConfirmCount;
  final int accessibilityDisputeCount;
  final double bookedExperiencesCarbonFootprintKg;
  final double averageEcoScore;

  static ImpactStats fromJson(Map<String, dynamic> o) => ImpactStats(
    experienceCount: (o['experienceCount'] as num?)?.toInt() ?? 0,
    bookingCount: (o['bookingCount'] as num?)?.toInt() ?? 0,
    travelerCount: (o['travelerCount'] as num?)?.toInt() ?? 0,
    accessibilityConfirmCount:
        (o['accessibilityConfirmCount'] as num?)?.toInt() ?? 0,
    accessibilityDisputeCount:
        (o['accessibilityDisputeCount'] as num?)?.toInt() ?? 0,
    bookedExperiencesCarbonFootprintKg:
        (o['bookedExperiencesCarbonFootprintKg'] as num?)?.toDouble() ?? 0.0,
    averageEcoScore: (o['averageEcoScore'] as num?)?.toDouble() ?? 0.0,
  );
}

class RegistryPerk {
  const RegistryPerk({
    required this.id,
    required this.title,
    required this.description,
    required this.partner,
    required this.pulseCost,
    required this.redeemedVoucherCode,
  });

  final String id;
  final String title;
  final String description;
  final String partner;
  final int pulseCost;

  /// Non-null once this traveler has redeemed it.
  final String? redeemedVoucherCode;

  bool get isRedeemed => redeemedVoucherCode != null;

  static RegistryPerk fromJson(Map<String, dynamic> o) => RegistryPerk(
    id: o['id'] as String,
    title: o['title'] as String,
    description: o['description'] as String? ?? '',
    partner: o['partner'] as String? ?? '',
    pulseCost: (o['pulseCost'] as num?)?.toInt() ?? 0,
    redeemedVoucherCode: o['redeemedVoucherCode'] as String?,
  );
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/formatting.dart';
import '../domain/experience_optimizer.dart';
import '../models/chat_message.dart';
import '../models/evidence.dart';
import '../models/experience_listing.dart';
import '../models/trip_models.dart';
import '../screens/dialogs/add_experience_dialog.dart';
import '../services/groq_agentic_engine.dart';
import '../services/groq_api_client.dart';
import '../services/live_city_intelligence_service.dart';
import '../services/location_service.dart';
import 'app_scope.dart';

/// The Yatri AI conversation: message list, the multi-turn trip-planning state
/// machine, the circumstance-adaptation / family / micro-experience filters, and
/// the Groq call with its grounded fallback.
///
/// Port of the logic half of `YatriAiFragment.kt`, lifted out of the widget so
/// the screen stays a view and this stays testable.
class YatriAiController extends ChangeNotifier {
  YatriAiController(this._services) {
    _greet();
    _initLocation();
  }

  /// The three action chips the experience detail card offers.
  static const bookAction = '📅 Book This Experience';
  static const confirmAction = '✅ Confirm Accessibility';
  static const reportAction = '⚠️ Report an Issue';

  final AppServices _services;

  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  double _userLatitude = LocationService.defaultLat;
  double _userLongitude = LocationService.defaultLon;
  String _userCityName = 'Mumbai';
  bool _hasAutoCheckedRainAdaptation = false;

  // Multi-turn trip-planning state machine.
  String? _pendingTripDestination;
  int _pendingTripDays = 2;

  /// Id of the experience last shown in a detail card — lets the Book / Confirm
  /// / Report chip taps act on the right listing without re-parsing the chat.
  String? _lastViewedExperienceId;

  void _greet() {
    _messages.add(
      ChatMessage(
        'Hello! I am Yatri AI, your agentic green travel & inclusive hospitality '
        'companion.\n\nI can plan multi-day eco-itineraries for any destination '
        '(e.g. Kedarnath, Lonavala, Alibaug, Manali), calculate low-carbon transit '
        'routes, and find verified step-free stays.\n\nTry asking: "Plan a trip to '
        'Kedarnath" or "Plan a trip to Lonavala"!',
        isUser: false,
      ),
    );
  }

  Future<void> clearChat() async {
    _messages.clear();
    _pendingTripDestination = null;
    _messages.add(
      ChatMessage(
        'Hello! I am Yatri AI, your sustainable mobility and inclusive hospitality '
        'assistant. How can I assist your journey today?',
        isUser: false,
      ),
    );
    notifyListeners();
  }

  // ---- Location ----

  Future<void> _initLocation() async {
    final position = await _services.location.currentPosition();
    if (position == null) return;
    _userLatitude = position.latitude;
    _userLongitude = position.longitude;
    final city = await _services.location.resolveCityName(
      _userLatitude,
      _userLongitude,
    );
    if (city != null) _userCityName = city;
    await _maybeAutoTriggerRainAdaptation();
  }

  /// Proactively checks real live weather at the user's location once per
  /// session and, if it's actually raining, pushes an adapted recommendation
  /// without the user needing to say "rain" — this is what makes Circumstance
  /// Adaptation autonomous rather than purely keyword-reactive.
  Future<void> _maybeAutoTriggerRainAdaptation() async {
    if (_hasAutoCheckedRainAdaptation) return;
    _hasAutoCheckedRainAdaptation = true;

    final weather = await LiveCityIntelligenceService.getLiveWeatherAndAqi(
      _userLatitude,
      _userLongitude,
    );
    if (weather == null || !weather.isRaining) return;

    final adaptive = await _services.experiences.getAdaptiveExperiences(
      isRain: true,
      maxDuration: 2.0,
    );
    final ranked = ExperienceOptimizer.rank(adaptive);
    if (ranked.isEmpty) return;

    await _recordViews(ranked.take(3));

    final buffer = StringBuffer(
      '☔ **Live weather at your location shows rain (${weather.condition}, '
      '${weather.temperatureC}°C)** — I\'ve proactively adapted your recommendations to '
      'covered, indoor options without you needing to ask:\n\n',
    );
    ranked.take(3).toList().asMap().forEach((index, r) {
      final exp = r.experience;
      buffer.writeln(
        '${index + 1}. **${exp.name}** 🏛️ Indoor/Covered • ${exp.location} • '
        '${fixed(exp.durationHours)}h • ${exp.pricePerPerson}',
      );
    });

    _addAiMessage(
      buffer.toString(),
      mcq: QuickMcqQuestion(
        questionId: 'auto_rain_mcq',
        questionText: 'Select rain-adapted experience',
        options: ranked.take(3).map((r) => r.experience.name).toList(),
      ),
    );
  }

  // ---- Conversation ----

  void _addAiMessage(String text, {QuickMcqQuestion? mcq, TripPlan? trip}) {
    _messages.add(
      ChatMessage(text, isUser: false, mcqQuestion: mcq, generatedTrip: trip),
    );
    notifyListeners();
  }

  void _showTyping() {
    if (_messages.any((m) => m.isLoading)) return;
    _messages.add(ChatMessage('', isUser: false, isLoading: true));
    notifyListeners();
  }

  void _removeTyping() {
    final index = _messages.indexWhere((m) => m.isLoading);
    if (index != -1) {
      _messages.removeAt(index);
      notifyListeners();
    }
  }

  /// Echoes a freshly published provider listing back into the conversation, as
  /// the Kotlin publish handler did.
  void announcePublishedExperience(PublishedExperience exp) {
    _addAiMessage(
      '🎉 **Experience Published to UrbanPulse!**\n\n'
      '• **Name**: ${exp.name}\n'
      '• **Category**: ${exp.category} • ${exp.location}\n'
      '• **Duration**: ${fixed(exp.duration)}h • ${rupees(exp.price)} / person\n'
      '• **Accessibility**: ${exp.tags.join(", ")}\n'
      '• **Sustainability**: ${exp.sustainability}\n\n'
      'Your experience is now live in the local registry and automatically recommended '
      'to travelers with matching time & interest profiles!',
    );
  }

  Future<void> send(String text) async {
    _messages.add(ChatMessage(text, isUser: true));
    notifyListeners();
    await _generateResponse(text);
  }

  Future<void> _generateResponse(String prompt) async {
    _showTyping();
    // Refresh the fix so grounded answers use the user's current position.
    unawaited(_refreshLocation());

    final lowerPrompt = prompt.toLowerCase();

    // 0a. Real booking / accessibility-report actions on the last-viewed experience.
    if (await _handleListingAction(prompt)) return;

    // 0b. An experience chip/name was tapped directly -> record a real inquiry
    //     and show its evidence-graph detail card.
    if (await _handleExperienceTap(prompt)) return;

    // 1. Answering the pending "how many days?" question.
    if (_handleDaysAnswer(lowerPrompt)) return;

    // 2. Answering the pending "travel style?" question.
    if (await _handleStyleAnswer(lowerPrompt)) return;

    // 3. A new trip-planning request (explicit destination, or any plan/trip wording).
    if (_handleTripRequest(prompt, lowerPrompt)) return;

    // 4. Circumstance adaptation (rain / bad weather / sudden delays).
    if (lowerPrompt.contains('adapt') ||
        lowerPrompt.contains('rain') ||
        lowerPrompt.contains('weather') ||
        lowerPrompt.contains('delay')) {
      await _handleCircumstanceAdaptation();
      return;
    }

    // 5. Family & child-friendly filter.
    if (lowerPrompt.contains('family') ||
        lowerPrompt.contains('child') ||
        lowerPrompt.contains('kid')) {
      await _handleFamilyFilter();
      return;
    }

    // 6. Micro-experience time-crunch filter.
    if (lowerPrompt.contains('2 hour') ||
        lowerPrompt.contains('2 hr') ||
        lowerPrompt.contains('micro-experience') ||
        lowerPrompt.contains('micro experience') ||
        lowerPrompt.contains('time crunch') ||
        lowerPrompt.contains('short time')) {
      await _handleMicroExperiences();
      return;
    }

    // 7. Groq, grounded in the on-device experience catalog; then the rule-routed
    //    live-intelligence fallback.
    await _handleGeneralQuery(prompt);
  }

  Future<void> _refreshLocation() async {
    final position = await _services.location.currentPosition();
    if (position == null) return;
    _userLatitude = position.latitude;
    _userLongitude = position.longitude;
  }

  Future<bool> _handleListingAction(String prompt) async {
    final expId = _lastViewedExperienceId;
    if (expId == null) return false;
    if (prompt != bookAction &&
        prompt != confirmAction &&
        prompt != reportAction) {
      return false;
    }

    _removeTyping();
    switch (prompt) {
      case bookAction:
        final travelerName = await _services.auth.getOrCreateTravelerName();
        final bookingDate = _isoDate(DateTime.now());
        final success = await _services.experiences.createBooking(
          expId,
          travelerName: travelerName,
          partySize: 1,
          bookingDate: bookingDate,
        );
        _addAiMessage(
          success
              ? '✅ **Booked!** Confirmed for $travelerName on $bookingDate. This is a real '
                    'reservation recorded in the Central Registry.'
              : "⚠️ Couldn't reach the booking service right now — please try again.",
        );
      case confirmAction:
        final success = await _services.experiences.submitAccessibilityReport(
          expId,
          confirmsAccessibility: true,
          note: 'Confirmed via Yatri AI chat',
        );
        _addAiMessage(
          success
              ? '✅ Thanks — your confirmation was recorded and will strengthen this '
                    "listing's Evidence Graph confidence for future travelers."
              : "⚠️ Couldn't submit your report right now — please try again.",
        );
      case reportAction:
        final success = await _services.experiences.submitAccessibilityReport(
          expId,
          confirmsAccessibility: false,
          note: 'Disputed via Yatri AI chat',
        );
        _addAiMessage(
          success
              ? '⚠️ Thanks for flagging this — future travelers will see this as a real '
                    'disputed claim in the Evidence Graph.'
              : "⚠️ Couldn't submit your report right now — please try again.",
        );
    }
    return true;
  }

  Future<bool> _handleExperienceTap(String prompt) async {
    ExperienceListing? matched;
    try {
      final all = await _services.experiences.getAllExperiences();
      matched = all.where((e) => e.name == prompt).firstOrNull;
    } catch (_) {
      matched = null;
    }
    if (matched == null) return false;

    await _services.experiences.recordInquiry(matched.id);
    _lastViewedExperienceId = matched.id;
    _removeTyping();

    final evidence = _services.accessibility.evidenceForExperience(matched);
    final evidenceText = evidence.map(_formatClaim).join('\n');

    _addAiMessage(
      '**${matched.name}**\n\n'
      '${matched.category} • ${matched.location} • ${fixed(matched.durationHours)}h • '
      '${matched.pricePerPerson}\n'
      '📅 ${matched.bookingCount} real booking(s) • 👁️ ${matched.viewsCount} views\n\n'
      '**Evidence Graph — Why this?**\n$evidenceText',
      mcq: const QuickMcqQuestion(
        questionId: 'exp_detail_mcq',
        questionText: 'Next step',
        options: [bookAction, confirmAction, reportAction, 'Show on Live Map'],
      ),
    );
    return true;
  }

  static String _formatClaim(EvidenceClaim claim) {
    final base =
        '${claim.confidence.icon} ${claim.confidence.label}: ${claim.claim}';
    return claim.contradiction != null
        ? '$base\n   ⚠️ ${claim.contradiction}'
        : base;
  }

  bool _handleDaysAnswer(String lowerPrompt) {
    if (_pendingTripDestination == null) return false;
    final mentionsDuration =
        lowerPrompt.contains('day') ||
        lowerPrompt.contains('express') ||
        lowerPrompt.contains('weekend') ||
        lowerPrompt.contains('leisure') ||
        lowerPrompt.contains('yatra') ||
        lowerPrompt.contains('pilgrimage') ||
        RegExp(r'\b[1-7]\b').hasMatch(lowerPrompt);
    if (!mentionsDuration) return false;

    _removeTyping();
    _pendingTripDays = switch (lowerPrompt) {
      _ when lowerPrompt.contains('1') || lowerPrompt.contains('express') => 1,
      _ when lowerPrompt.contains('3') => 3,
      _
          when lowerPrompt.contains('4') ||
              lowerPrompt.contains('5') ||
              lowerPrompt.contains('pilgrimage') =>
        4,
      _ when lowerPrompt.contains('7') || lowerPrompt.contains('complete') => 7,
      _ => 2,
    };

    final dest = _pendingTripDestination ?? 'Kedarnath';
    final options = _isHimalayan(dest)
        ? const [
            'Palki & Accessible ♿',
            'Eco Pilgrim Trek 🌿',
            'Budget Devotee 🎒',
            'Heli-Yatra & Luxury 🚁',
          ]
        : const [
            'Wheelchair Step-Free ♿',
            'Eco Nature & Farm 🌿',
            'Budget Explorer 🎒',
            'Luxury Heritage 🏰',
          ];

    _addAiMessage(
      'Got it! A **$_pendingTripDays-Day trip to $dest** is selected.\n\nNow, what is your '
      'preferred travel style and accessibility requirement for $dest?',
      mcq: QuickMcqQuestion(
        questionId: 'style_mcq',
        questionText: 'Select travel style',
        options: options,
      ),
    );
    return true;
  }

  Future<bool> _handleStyleAnswer(String lowerPrompt) async {
    if (_pendingTripDestination == null) return false;
    const styleWords = [
      'wheelchair',
      'palki',
      'heli',
      'step-free',
      'eco',
      'nature',
      'pilgrim',
      'devotee',
      'budget',
      'luxury',
      'heritage',
    ];
    if (!styleWords.any(lowerPrompt.contains)) return false;

    _removeTyping();
    final dest = _pendingTripDestination ?? 'Kedarnath';
    final days = _pendingTripDays;
    final isAccessible =
        lowerPrompt.contains('wheelchair') ||
        lowerPrompt.contains('palki') ||
        lowerPrompt.contains('step-free');
    final style = isAccessible
        ? 'Wheelchair / Step-Free Accessible'
        : 'Eco Nature Explorer';

    final trip = await GroqAgenticEngine.generateAutonomousTripPlan(
      destination: dest,
      originCity: _userCityName,
      days: days,
      isAccessible: isAccessible,
      travelStyle: style,
    );

    final header = trip.isAiGenerated
        ? '🌿 **Your $days-Day Sustainable & Accessible Itinerary for $dest is Ready!** '
              '(Generated live by Groq AI)\n\n'
        : '🌿 **Your $days-Day Sustainable & Accessible Itinerary for $dest**\n'
              '⚠️ Groq AI was unreachable — this is an offline template estimate, not a '
              'live-verified plan.\n\n';
    final stayLabel = trip.isAiGenerated
        ? 'AI-Suggested Stay'
        : 'Example Stay (unverified)';

    _addAiMessage(
      '$header'
      '• 🚆 **Transit Option**: ${trip.travelMode} (Cost: ${rupees(trip.transitCostInr)})\n'
      '• 🏨 **$stayLabel**: ${trip.hotelName} (Rating: ★ ${trip.hotelRating})\n'
      '• ♿ **Accessibility**: ${trip.isStepFreeAccessible ? "100% Level Boarding & Assisted Palki / Concourse" : "Standard Concourse"}\n'
      '• 💨 **Air Quality**: ${trip.aqiStatus}\n'
      '• 💰 **Estimated Budget**: ${rupees(trip.totalBudgetInr)}\n'
      '• 🌱 **Carbon Avoided**: -${trip.co2SavedKg} kg CO2e vs private petrol SUV!\n\n'
      'You can save this trip to your **Trips tab** or open the full timeline below:',
      trip: trip,
    );
    _pendingTripDestination = null;
    return true;
  }

  bool _handleTripRequest(String prompt, String lowerPrompt) {
    final extractedDest = extractDestination(prompt);
    if (extractedDest == null &&
        !lowerPrompt.contains('plan') &&
        !lowerPrompt.contains('trip') &&
        !lowerPrompt.contains('itinerary')) {
      return false;
    }

    _removeTyping();
    final dest = extractedDest ?? 'Kedarnath';
    _pendingTripDestination = dest;

    final options = _isHimalayan(dest)
        ? const [
            '3 Days Express Yatra',
            '4 Days Pilgrim Trek',
            '7 Days Complete Circuit',
            'Custom Duration',
          ]
        : const [
            '1 Day Express (Same Day)',
            '2 Days Weekend',
            '3 Days Leisure',
            'Custom Duration',
          ];

    _addAiMessage(
      'I would be happy to design a smart, low-carbon, and accessible itinerary to '
      '**$dest**! 🏔️\n\nHow many days are you planning for your $dest trip?',
      mcq: QuickMcqQuestion(
        questionId: 'days_mcq',
        questionText: 'Select trip duration',
        options: options,
      ),
    );
    return true;
  }

  /// Cross-checked against real live Open-Meteo conditions, not just the user's
  /// own wording — the adaptation fires if the user mentions rain OR the live
  /// weather at their GPS coordinates shows it.
  Future<void> _handleCircumstanceAdaptation() async {
    _removeTyping();
    final liveWeather = await LiveCityIntelligenceService.getLiveWeatherAndAqi(
      _userLatitude,
      _userLongitude,
    );
    final adaptive = await _services.experiences.getAdaptiveExperiences(
      isRain: true,
      maxDuration: 2.0,
    );
    final ranked = ExperienceOptimizer.rank(adaptive);
    await _recordViews(ranked.take(3));

    final weatherLine = liveWeather == null
        ? 'Weather change or schedule delay reported — '
        : liveWeather.isRaining
        ? 'Live weather check confirms rain (${liveWeather.condition}, '
              '${liveWeather.temperatureC}°C) at your coordinates — '
        : 'Live weather check shows ${liveWeather.condition} (no rain detected right '
              'now) — adapting based on your request anyway — ';

    final buffer =
        StringBuffer(
          '☔ **Real-Time Circumstance Adaptation Triggered**\n\n',
        )..write(
          '$weatherLine we\'ve dynamically adapted your itinerary, swapping outdoor '
          'cycling and treks for covered, indoor cultural workshops & tactile '
          'galleries:\n\n',
        );

    ranked.take(3).toList().asMap().forEach((index, r) {
      final exp = r.experience;
      final badge = r.badges.isNotEmpty ? ' [${r.badges.first.label}]' : '';
      buffer
        ..writeln('${index + 1}. **${exp.name}**$badge')
        ..writeln('   • **Type**: 🏛️ Indoor / Covered • ${exp.location}')
        ..writeln(
          '   • **Duration**: ${fixed(exp.durationHours)}h • '
          '**Price**: ${exp.pricePerPerson}',
        )
        ..writeln(
          '   • **Accessibility**: ${exp.accessibilityRating}% '
          '(${exp.accessibilityTags.join(", ")})',
        )
        ..writeln(
          '   • **Status**: '
          '${exp.isAvailableToday ? "✅ Available Today" : "⚠️ Busy"}\n',
        );
    });
    buffer.write(
      'Would you like to route transit to the nearest covered indoor workshop?',
    );

    _addAiMessage(
      buffer.toString(),
      mcq: QuickMcqQuestion(
        questionId: 'adapt_mcq',
        questionText: 'Select rain-adapted experience',
        options: [
          ...ranked.take(3).map((r) => r.experience.name),
          'Check Live AQI & Transit',
        ],
      ),
    );
  }

  Future<void> _handleFamilyFilter() async {
    _removeTyping();
    final familyExp = await _services.experiences.getAdaptiveExperiences(
      maxDuration: 3.0,
      familyOnly: true,
    );
    final ranked = ExperienceOptimizer.rank(familyExp);
    await _recordViews(ranked.take(4));

    final buffer =
        StringBuffer(
          '👨‍👩‍👧‍👦 **Family & Child-Friendly Recommendations**\n\n',
        )..write(
          'Filtered for safe, interactive, and family-appropriate activities with '
          'step-free stroller/ramp concourses:\n\n',
        );

    ranked.take(4).toList().asMap().forEach((index, r) {
      final exp = r.experience;
      final badge = r.badges.isNotEmpty ? ' [${r.badges.first.label}]' : '';
      buffer
        ..writeln('${index + 1}. **${exp.name}**$badge')
        ..writeln('   • **Category**: ${exp.category} (${exp.location})')
        ..writeln('   • **Tags**: ${exp.travelerTags.join(", ")}')
        ..writeln(
          '   • **Duration**: ${fixed(exp.durationHours)}h • '
          '**Price**: ${exp.pricePerPerson}',
        )
        ..writeln(
          '   • **Accessibility**: ${exp.accessibilityRating}% '
          '(${exp.accessibilityTags.join(", ")})\n',
        );
    });
    buffer.write(
      'Select an activity to view family group pricing and step-free transit '
      'directions:',
    );

    _addAiMessage(
      buffer.toString(),
      mcq: QuickMcqQuestion(
        questionId: 'family_mcq',
        questionText: 'Select family activity',
        options: [
          ...ranked.take(3).map((r) => r.experience.name),
          'Explore Eco Stays',
        ],
      ),
    );
  }

  Future<void> _handleMicroExperiences() async {
    _removeTyping();
    List<ExperienceListing> all;
    try {
      all = await _services.experiences.getAllExperiences();
    } catch (_) {
      all = const [];
    }
    final isWheelchair = _services.accessibility.isWheelchairModeEnabled;
    final filtered = all
        .where(
          (e) =>
              e.durationHours <= 2.5 &&
              (!isWheelchair || e.accessibilityRating >= 80),
        )
        .toList();
    final ranked = ExperienceOptimizer.rank(filtered);
    await _recordViews(ranked.take(4));

    final buffer =
        StringBuffer(
          '⏱️ **Found ${ranked.length} Pareto-Optimized Micro-Experiences (Under 2 Hours)**\n\n',
        )..write(
          'Curated for your available time window near your coordinates with verified '
          'accessibility:\n\n',
        );

    ranked.take(4).toList().asMap().forEach((index, r) {
      final exp = r.experience;
      final badge = r.badges.isNotEmpty ? ' [${r.badges.first.label}]' : '';
      buffer
        ..writeln('${index + 1}. **${exp.name}**$badge')
        ..writeln('   • **Category**: ${exp.category} (${exp.location})')
        ..writeln(
          '   • **Duration**: ${fixed(exp.durationHours)}h • '
          '**Price**: ${exp.pricePerPerson}',
        )
        ..writeln(
          '   • **Accessibility**: ${exp.accessibilityRating}% '
          '(${exp.accessibilityTags.join(", ")})',
        )
        ..writeln('   • **Eco Impact**: ${exp.carbonFootprintPerVisit}\n');
    });
    buffer.write(
      'Would you like transit directions or to book a spot for one of these?',
    );

    _addAiMessage(
      buffer.toString(),
      mcq: QuickMcqQuestion(
        questionId: 'micro_exp_mcq',
        questionText: 'Select experience to route',
        options: [
          ...ranked.take(3).map((r) => r.experience.name),
          'Explore More Stays',
        ],
      ),
    );
  }

  Future<void> _handleGeneralQuery(String prompt) async {
    String? expContext;
    try {
      final all = await _services.experiences.getAllExperiences();
      expContext = all
          .take(6)
          .map(
            (e) =>
                '${e.name} (${e.category} in ${e.location}, '
                '${fixed(e.durationHours)}h, ${e.pricePerPerson}, Eco: ${e.ecoScore}/5, '
                'Access: ${e.accessibilityRating}%)',
          )
          .join('; ');
    } catch (_) {
      expContext = null;
    }

    final groundingLine = (expContext != null && expContext.isNotEmpty)
        ? 'Verified Local Experiences in SQLite: [$expContext]. When asked for local '
              'recommendations, workshops, cultural activities, or short experiences, '
              'prioritize recommending these verified gems! '
        : '';
    final systemPrompt =
        'You are Yatri AI, an expert sustainable travel & smart mobility companion for '
        'UrbanPulse. You can answer ANY question naturally, including math, logic, '
        'science, and travel. User location: ($_userLatitude, $_userLongitude). '
        '$groundingLine'
        'Keep answers concise, direct, and actionable.';

    var response = await GroqApiClient.queryGroq(
      prompt,
      systemPrompt: systemPrompt,
    );
    response ??= await LiveCityIntelligenceService.queryGroundedIntelligence(
      userPrompt: prompt,
      userLat: _userLatitude,
      userLon: _userLongitude,
      hospitalityRepository: _services.hospitality,
    );

    _removeTyping();
    _addAiMessage(response);
  }

  Future<void> _recordViews(Iterable<RankedExperience> ranked) async {
    for (final r in ranked) {
      await _services.experiences.recordView(r.experience.id);
    }
  }

  // ---- Helpers ----

  static bool _isHimalayan(String dest) {
    final lower = dest.toLowerCase();
    return lower.contains('kedar') ||
        lower.contains('badri') ||
        lower.contains('manali') ||
        lower.contains('leh');
  }

  static String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Known pilgrimage/tourist spots first, then a general "trip to X" pattern.
  @visibleForTesting
  static String? extractDestination(String prompt) {
    final lower = prompt.toLowerCase().trim();

    const knownPlaces = <List<String>, String>{
      ['kedar nath', 'kedarnath']: 'Kedarnath',
      ['badrinath', 'badri nath']: 'Badrinath',
      ['rishikesh']: 'Rishikesh',
      ['haridwar']: 'Haridwar',
      ['manali']: 'Manali',
      ['shimla']: 'Shimla',
      ['leh', 'ladakh']: 'Leh Ladakh',
      ['alibaug', 'alibag']: 'Alibaug',
      ['mahabaleshwar']: 'Mahabaleshwar',
      ['matheran']: 'Matheran',
      ['lonavala', 'lonavla']: 'Lonavala',
      ['goa']: 'Goa',
      ['jaipur']: 'Jaipur',
      ['udaipur']: 'Udaipur',
      ['varanasi', 'kashi', 'banaras']: 'Varanasi',
      ['ayodhya']: 'Ayodhya',
      ['pune']: 'Pune',
      ['mumbai']: 'Mumbai',
    };
    for (final entry in knownPlaces.entries) {
      if (entry.key.any(lower.contains)) return entry.value;
    }

    final match = RegExp(
      r'(?:plan(?:ning)?(?:\s+a)?\s+trip\s+to|trip\s+to|visit|travel\s+to|going\s+to|'
      r'guide\s+for|itinerary\s+for)\s+([a-zA-Z\s]{2,30})',
      caseSensitive: false,
    ).firstMatch(prompt);
    if (match == null) return null;

    final raw = match.group(1)!.trim();
    final cleaned = raw
        .split(RegExp(r'\s(?:with|for|in|using|by)\s'))
        .first
        .trim();
    if (cleaned.isEmpty) return null;
    return cleaned
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}

import 'package:flutter/material.dart';

import '../domain/trip_brief/accessibility_followups.dart';
import '../domain/trip_brief/answer_applier.dart';
import '../domain/trip_brief/brief_validator.dart';
import '../domain/trip_brief/question_catalog.dart';
import '../models/trip_brief.dart';
import '../models/yatri_question.dart';
import '../widgets/yatri/answer_view.dart';
import '../widgets/yatri/choice_answers.dart';
import '../widgets/yatri/option_card.dart';

/// The trip brief as a form: the second way in beside the chat, and the
/// review-and-confirm step after it. It reuses the chat's answer widgets in
/// embedded mode and the same validator, so both paths agree on what "valid"
/// means. Pops with the confirmed [TripBrief], or null if dismissed.
class TripBriefFormScreen extends StatefulWidget {
  const TripBriefFormScreen({
    required this.initial,
    required this.now,
    this.detectedCity,
    this.settingsNeeds = const {},
    super.key,
  });

  final TripBrief initial;
  final DateTime now;
  final String? detectedCity;
  final Set<AccessibilityNeed> settingsNeeds;

  static Future<TripBrief?> open(
    BuildContext context, {
    required TripBrief initial,
    required DateTime now,
    String? detectedCity,
    Set<AccessibilityNeed> settingsNeeds = const {},
  }) => Navigator.of(context).push<TripBrief>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => TripBriefFormScreen(
        initial: initial,
        now: now,
        detectedCity: detectedCity,
        settingsNeeds: settingsNeeds,
      ),
    ),
  );

  @override
  State<TripBriefFormScreen> createState() => _TripBriefFormScreenState();
}

class _TripBriefFormScreenState extends State<TripBriefFormScreen> {
  late TripBrief _brief;
  late final TextEditingController _destination;
  late final TextEditingController _origin;
  late final TextEditingController _notes;
  final Map<String, String> _errors = {};
  final Map<BriefField, GlobalKey> _keys = {
    for (final f in BriefField.values) f: GlobalKey(),
  };
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    var b = widget.initial;
    // What the form shows as ticked counts as the traveler's answer: Settings
    // pre-ticks for accessibility and the greener default for transport.
    if (!b.accessibilityConfirmed) {
      final pre = {...b.accessibilityNeeds, ...widget.settingsNeeds};
      if (pre.isNotEmpty) {
        b = b.copyWith(accessibilityNeeds: pre, accessibilityConfirmed: true);
      }
    }
    if (b.transportModes.isEmpty) {
      b = b.copyWith(
        transportModes: {TripTransportMode.train, TripTransportMode.eBus},
      );
    }
    _brief = b;
    _destination = TextEditingController(text: b.destination ?? '');
    _origin = TextEditingController(text: b.originCity ?? widget.detectedCity ?? '');
    _notes = TextEditingController(text: b.notes ?? '');
    if (b.originCity == null && widget.detectedCity != null) {
      _brief = _brief.copyWith(originCity: widget.detectedCity);
    }
  }

  @override
  void dispose() {
    _destination.dispose();
    _origin.dispose();
    _notes.dispose();
    super.dispose();
  }

  ValidationReport get _report => BriefValidator.validate(
    _brief.copyWith(uncertain: const {}),
    widget.now,
  );

  YatriQuestion _q(String id, {Map<String, Object?>? prefill}) {
    final q = QuestionCatalog.build(
      id,
      _brief,
      now: widget.now,
      detectedCity: widget.detectedCity,
      settingsNeeds: widget.settingsNeeds,
    );
    return prefill == null ? q : q.copyWith(prefill: prefill);
  }

  /// Applies an embedded widget's value; null means the widget is currently
  /// invalid or empty.
  void _apply(String id, YatriAnswer? answer, {required BriefField field}) {
    setState(() {
      if (answer == null) {
        _brief = _brief.clearing(field);
        _errors.remove(id);
        return;
      }
      final q = _q(id);
      final res = AnswerApplier.apply(_brief, q, answer, widget.now);
      if (res.isOk) {
        _brief = res.brief!;
        _errors.remove(id);
      } else {
        _errors[id] = res.error!;
      }
    });
  }

  void _onGroup(YatriAnswer? a) {
    if (a is! GroupAnswer) {
      setState(() => _brief = _brief.clearing(BriefField.group));
      return;
    }
    setState(() {
      _brief = _brief.copyWith(
        travellerCount: a.adults + a.seniors + a.children,
        adults: a.adults,
        seniors: a.seniors,
        children: a.children,
        women: a.women,
        childAges: a.childAges,
      );
      if (a.women == 0) _brief = _brief.copyWith(womenSafety: const {});
      _errors.remove('group');
    });
  }

  void _confirm() {
    setState(() => _submitted = true);
    final report = _report;
    if (!report.isComplete) {
      final first = report.issues.first.field;
      final target = first == BriefField.accessibilityDetails
          ? BriefField.accessibility
          : first;
      final ctx = _keys[target]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: 0.05,
        );
      }
      return;
    }
    final notes = _notes.text.trim();
    Navigator.of(context).pop(
      _brief.copyWith(uncertain: const {}, notes: notes.isEmpty ? null : notes),
    );
  }

  String? _issueFor(BriefField field) {
    if (!_submitted) return null;
    final list = _report.forField(field).toList();
    return list.isEmpty ? null : list.first.message;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final report = _report;

    final needs = _brief.accessibilityNeeds;
    final people = _brief.travellerCount ?? 1;
    final days = _brief.days == 0 ? 1 : _brief.days;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review your trip'),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${report.satisfied}/${report.required} done',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      Text(
                        'Check everything below and change anything that’s off. '
                        'Required details are marked with an asterisk.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _Section(
                        key: _keys[BriefField.destination],
                        icon: Icons.place_rounded,
                        title: 'Trip *',
                        error: _issueFor(BriefField.destination) ??
                            _issueFor(BriefField.origin),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _field(_destination, 'Destination', Icons.flag_rounded, (v) {
                              setState(() => _brief = v.trim().isEmpty
                                  ? _brief.clearing(BriefField.destination)
                                  : _brief.copyWith(destination: v.trim()));
                            }),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final d in QuestionCatalog.popularDestinations)
                                  OptionPill(
                                    option: QuestionOption(id: d, label: d, emoji: '📍'),
                                    selected: _brief.destination == d,
                                    onTap: () {
                                      _destination.text = d;
                                      setState(() => _brief = _brief.copyWith(destination: d));
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _field(_origin, 'Starting city', Icons.my_location_rounded, (v) {
                              setState(() => _brief = v.trim().isEmpty
                                  ? _brief.clearing(BriefField.origin)
                                  : _brief.copyWith(originCity: v.trim()));
                            }),
                            if (widget.detectedCity != null) ...[
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: OptionPill(
                                  option: QuestionOption(
                                    id: 'loc',
                                    label: 'Use my location: ${widget.detectedCity}',
                                    emoji: '🎯',
                                    recommended: true,
                                  ),
                                  selected: _brief.originCity == widget.detectedCity,
                                  onTap: () {
                                    _origin.text = widget.detectedCity!;
                                    setState(() => _brief =
                                        _brief.copyWith(originCity: widget.detectedCity));
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      _Section(
                        key: _keys[BriefField.dates],
                        icon: Icons.event_rounded,
                        title: 'When *',
                        error: _errors['dates'] ?? _issueFor(BriefField.dates),
                        child: DateTimeAnswerViewHost(
                          question: _q('dates'),
                          onChanged: (a) => _apply('dates', a, field: BriefField.dates),
                        ),
                      ),
                      _Section(
                        key: _keys[BriefField.group],
                        icon: Icons.groups_rounded,
                        title: 'Who’s travelling *',
                        error: _errors['group'] ??
                            _issueFor(BriefField.group) ??
                            _issueFor(BriefField.travellers),
                        child: buildAnswerView(
                          _q('group', prefill: {
                            'total': null,
                            'adults': _brief.adults ?? _brief.travellerCount ?? 1,
                            'seniors': _brief.seniors ?? 0,
                            'children': _brief.children ?? 0,
                            'women': _brief.women ?? 0,
                            'childAges': _brief.childAges,
                          }),
                          key: const ValueKey('form-group'),
                          embedded: true,
                          onSubmit: (_) {},
                          onChanged: _onGroup,
                        ),
                      ),
                      _Section(
                        key: _keys[BriefField.accessibility],
                        icon: Icons.accessible_forward_rounded,
                        title: 'Accessibility *',
                        error: _issueFor(BriefField.accessibility) ??
                            _issueFor(BriefField.accessibilityDetails),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            buildAnswerView(
                              _q('accessibility').copyWith(
                                preselected: {for (final n in needs) n.name},
                              ),
                              key: const ValueKey('form-a11y'),
                              embedded: true,
                              onSubmit: (_) {},
                              onChanged: (a) {
                                if (a == null) {
                                  setState(() => _brief = _brief.copyWith(
                                    accessibilityNeeds: const {},
                                    accessibilityConfirmed: false,
                                  ));
                                } else {
                                  _apply('accessibility', a, field: BriefField.accessibility);
                                }
                              },
                            ),
                            for (final f in AccessibilityFollowUps.forNeeds(needs))
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      f.text,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    buildAnswerView(
                                      _q(f.id),
                                      key: ValueKey('form-${f.id}'),
                                      embedded: true,
                                      onSubmit: (_) {},
                                      onChanged: (a) => _apply(
                                        f.id,
                                        a,
                                        field: BriefField.accessibilityDetails,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      if ((_brief.women ?? 0) > 0)
                        _Section(
                          key: _keys[BriefField.womenSafety],
                          icon: Icons.shield_rounded,
                          title: 'Safety preferences *',
                          error: _issueFor(BriefField.womenSafety),
                          child: buildAnswerView(
                            _q('womenSafety'),
                            key: const ValueKey('form-safety'),
                            embedded: true,
                            onSubmit: (_) {},
                            onChanged: (a) =>
                                _apply('womenSafety', a, field: BriefField.womenSafety),
                          ),
                        ),
                      _Section(
                        key: _keys[BriefField.transport],
                        icon: Icons.directions_transit_rounded,
                        title: 'How you’ll travel *',
                        error: _issueFor(BriefField.transport),
                        child: buildAnswerView(
                          _q('transport').copyWith(
                            preselected: {
                              for (final m in _brief.transportModes) m.name,
                            },
                          ),
                          key: const ValueKey('form-transport'),
                          embedded: true,
                          onSubmit: (_) {},
                          onChanged: (a) =>
                              _apply('transport', a, field: BriefField.transport),
                        ),
                      ),
                      _Section(
                        key: _keys[BriefField.budget],
                        icon: Icons.account_balance_wallet_rounded,
                        title: 'Budget *',
                        error: _errors['budget'] ?? _issueFor(BriefField.budget),
                        child: buildAnswerView(
                          _q('budget', prefill: {
                            'people': people,
                            'days': days,
                            'min': _brief.budgetMinInr,
                            'max': _brief.budgetMaxInr,
                          }),
                          // Tiers scale with group size and length, so start
                          // fresh when either changes.
                          key: ValueKey('form-budget-$people-$days'),
                          embedded: true,
                          onSubmit: (_) {},
                          onChanged: (a) => _apply('budget', a, field: BriefField.budget),
                        ),
                      ),
                      _Section(
                        icon: Icons.tune_rounded,
                        title: 'Optional preferences',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final (id, label, field) in const [
                              ('style', 'Trip style', BriefField.style),
                              ('pace', 'Pace', BriefField.pace),
                              ('stay', 'Stay', BriefField.stay),
                              ('dietary', 'Food', BriefField.dietary),
                            ]) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: 4, bottom: 8),
                                child: Text(
                                  label,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              buildAnswerView(
                                _optional(id),
                                key: ValueKey('form-$id'),
                                embedded: true,
                                onSubmit: (_) {},
                                onChanged: (a) => _apply(id, a, field: field),
                              ),
                              const SizedBox(height: 12),
                            ],
                            TextField(
                              controller: _notes,
                              maxLines: 3,
                              maxLength: 300,
                              decoration: InputDecoration(
                                labelText: 'Anything else we should know?',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: CtaButton(
                    icon: Icons.check_rounded,
                    label: 'Confirm & plan trip',
                    onPressed: _confirm,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// An optional question pre-ticked from the current brief.
  YatriQuestion _optional(String id) {
    final q = _q(id);
    final pre = switch (id) {
      'style' => {if (_brief.style != null) _brief.style!.name},
      'pace' => {if (_brief.pace != null) _brief.pace!.name},
      'stay' => {for (final s in _brief.stayTypes) s.name},
      _ => {for (final d in _brief.dietary) d.name},
    };
    return q.copyWith(preselected: pre);
  }

  Widget _field(
    TextEditingController c,
    String label,
    IconData icon,
    ValueChanged<String> onChanged,
  ) => TextField(
    controller: c,
    onChanged: onChanged,
    textCapitalization: TextCapitalization.words,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

/// Embedded date view with the "no fixed prefill" starting values of the form.
class DateTimeAnswerViewHost extends StatelessWidget {
  const DateTimeAnswerViewHost({
    required this.question,
    required this.onChanged,
    super.key,
  });

  final YatriQuestion question;
  final AnswerChanged onChanged;

  @override
  Widget build(BuildContext context) => buildAnswerView(
    question,
    key: const ValueKey('form-dates'),
    embedded: true,
    onSubmit: (_) {},
    onChanged: onChanged,
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.child,
    this.error,
    super.key,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: error != null ? scheme.error : scheme.outlineVariant,
          width: error != null ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded, size: 18, color: scheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/formatting.dart';
import '../../models/yatri_question.dart';
import 'choice_answers.dart';
import 'option_card.dart';

/// Start / end date and time. Presets cover the common weekend trips; the
/// range picker and two time tiles cover everything else.
class DateTimeAnswerView extends StatefulWidget {
  const DateTimeAnswerView({
    required this.question,
    required this.onSubmit,
    this.embedded = false,
    this.onChanged,
    super.key,
  });

  final YatriQuestion question;
  final AnswerSubmit onSubmit;
  final bool embedded;
  final AnswerChanged? onChanged;

  @override
  State<DateTimeAnswerView> createState() => _DateTimeAnswerViewState();
}

class _DateTimeAnswerViewState extends State<DateTimeAnswerView> {
  static const _minLead = Duration(hours: 2);
  static const _defaultStart = TimeOfDay(hour: 9, minute: 0);
  static const _defaultEnd = TimeOfDay(hour: 18, minute: 0);

  late final DateTime _now =
      (widget.question.prefill['now'] as DateTime?) ?? DateTime.now();
  late DateTime? _start = widget.question.prefill['start'] as DateTime?;
  late DateTime? _end = widget.question.prefill['end'] as DateTime?;

  DateTime _at(DateTime day, TimeOfDay t) =>
      DateTime(day.year, day.month, day.day, t.hour, t.minute);

  /// (label, start, end) presets that are still in the future.
  List<(String, DateTime, DateTime)> get _presets {
    final today = DateTime(_now.year, _now.month, _now.day);
    var sat = today.add(Duration(days: (DateTime.saturday - today.weekday) % 7));
    if (_at(sat, _defaultStart).isBefore(_now.add(_minLead))) {
      sat = sat.add(const Duration(days: 7));
    }
    var fri = today.add(Duration(days: (DateTime.friday - today.weekday) % 7));
    if (DateTime(fri.year, fri.month, fri.day, 18).isBefore(_now.add(_minLead))) {
      fri = fri.add(const Duration(days: 7));
    }
    return [
      (
        'This weekend',
        _at(sat, _defaultStart),
        _at(sat.add(const Duration(days: 1)), _defaultEnd),
      ),
      (
        'Next weekend',
        _at(sat.add(const Duration(days: 7)), _defaultStart),
        _at(sat.add(const Duration(days: 8)), _defaultEnd),
      ),
      (
        'Long weekend',
        DateTime(fri.year, fri.month, fri.day, 18),
        _at(fri.add(const Duration(days: 3)), _defaultEnd),
      ),
    ];
  }

  String? get _problem {
    final s = _start;
    final e = _end;
    if (s == null || e == null) return 'Choose a start and an end.';
    if (s.isBefore(_now)) return 'The start time is in the past.';
    if (e.isBefore(s.add(_minLead))) return 'The trip must end after it starts.';
    if (e.difference(s).inDays >= 60) return 'Trips can be at most 60 days.';
    return null;
  }

  void _emit() {
    setState(() {});
    if (widget.embedded) {
      widget.onChanged?.call(
        _problem == null ? DateRangeAnswer(_start!, _end!) : null,
      );
    }
  }

  Future<void> _pickRange() async {
    final today = DateTime(_now.year, _now.month, _now.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      initialDateRange: _start != null && _end != null
          ? DateTimeRange(
              start: DateTime(_start!.year, _start!.month, _start!.day),
              end: DateTime(_end!.year, _end!.month, _end!.day),
            )
          : null,
      helpText: 'Select trip dates',
    );
    if (picked == null) return;
    final st = _start == null ? _defaultStart : TimeOfDay.fromDateTime(_start!);
    final en = _end == null ? _defaultEnd : TimeOfDay.fromDateTime(_end!);
    _start = _at(picked.start, st);
    _end = _at(picked.end, en);
    _emit();
  }

  Future<void> _pickTime({required bool start}) async {
    final base = start ? _start : _end;
    if (base == null) {
      await _pickRange();
      return;
    }
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (t == null) return;
    if (start) {
      _start = _at(base, t);
    } else {
      _end = _at(base, t);
    }
    _emit();
  }

  bool _matches(DateTime s, DateTime e) => _start == s && _end == e;

  /// The agent chooses between an inline calendar and quick presets. The
  /// calendar is the default; an unknown variant behaves like it.
  bool get _calendarVariant => widget.question.variant != 'presets';

  DateTime? _focused;

  /// An inline range calendar: tap a departure day, then a return day (tap the
  /// same day twice for a one-day trip). The two time tiles below set the
  /// clock times.
  Widget _calendar(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = DateTime(_now.year, _now.month, _now.day);
    DateTime? dayOnly(DateTime? d) => d == null ? null : DateTime(d.year, d.month, d.day);
    final onSurface = theme.textTheme.bodyMedium!;
    final lastDay = today.add(const Duration(days: 365));
    // A brief being re-asked may carry dates already in the past. The calendar
    // can only show days from today on, so keep those out of its range and
    // focus.
    DateTime? inRange(DateTime? d) {
      final day = dayOnly(d);
      return day == null || day.isBefore(today) || day.isAfter(lastDay) ? null : day;
    }
    final focus = _focused ?? inRange(_start) ?? today;

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: TableCalendar<void>(
        firstDay: today,
        lastDay: lastDay,
        focusedDay: focus.isBefore(today) ? today : (focus.isAfter(lastDay) ? lastDay : focus),
        rangeStartDay: inRange(_start),
        rangeEndDay: inRange(_end),
        rangeSelectionMode: RangeSelectionMode.toggledOn,
        startingDayOfWeek: StartingDayOfWeek.monday,
        availableGestures: AvailableGestures.horizontalSwipe,
        rowHeight: 44,
        onPageChanged: (day) => _focused = day,
        onRangeSelected: (start, end, focused) {
          _focused = focused;
          if (start == null) return;
          final st = _start == null ? _defaultStart : TimeOfDay.fromDateTime(_start!);
          final en = _end == null ? _defaultEnd : TimeOfDay.fromDateTime(_end!);
          _start = _at(start, st);
          _end = _at(end ?? start, en);
          _emit();
        },
        headerStyle: HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextStyle: theme.textTheme.titleSmall!.copyWith(fontWeight: FontWeight.w800),
          leftChevronIcon: Icon(Icons.chevron_left_rounded, color: scheme.primary),
          rightChevronIcon: Icon(Icons.chevron_right_rounded, color: scheme.primary),
        ),
        daysOfWeekStyle: DaysOfWeekStyle(
          weekdayStyle: theme.textTheme.labelSmall!.copyWith(color: scheme.onSurfaceVariant),
          weekendStyle: theme.textTheme.labelSmall!.copyWith(color: scheme.onSurfaceVariant),
        ),
        calendarStyle: CalendarStyle(
          outsideDaysVisible: false,
          defaultTextStyle: onSurface,
          weekendTextStyle: onSurface,
          disabledTextStyle: onSurface.copyWith(color: scheme.onSurface.withValues(alpha: 0.28)),
          todayTextStyle: onSurface.copyWith(fontWeight: FontWeight.w800),
          todayDecoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: scheme.primary.withValues(alpha: 0.6)),
          ),
          rangeHighlightColor: scheme.primary.withValues(alpha: 0.16),
          rangeStartDecoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
          rangeEndDecoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
          rangeStartTextStyle: onSurface.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w800),
          rangeEndTextStyle: onSurface.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w800),
          withinRangeTextStyle: onSurface.copyWith(color: scheme.primary, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final problem = _start == null || _end == null ? null : _problem;
    final s = _start;
    final e = _end;
    final days = s == null || e == null
        ? 0
        : DateTime(e.year, e.month, e.day)
                  .difference(DateTime(s.year, s.month, s.day))
                  .inDays +
              1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, ps, pe) in _presets)
              OptionPill(
                option: QuestionOption(id: label, label: label, icon: Icons.calendar_today_outlined),
                selected: _matches(ps, pe),
                onTap: () {
                  _start = ps;
                  _end = pe;
                  _emit();
                },
              ),
            if (!_calendarVariant)
              OptionPill(
                option: const QuestionOption(id: 'pick', label: 'Pick dates', icon: Icons.date_range_outlined),
                selected: false,
                onTap: _pickRange,
              ),
          ],
        ),
        if (_calendarVariant) ...[
          const SizedBox(height: 12),
          _calendar(context),
        ],
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final tiles = [
              _TimeTile(
                title: 'Departure',
                date: s == null ? null : shortDate(s),
                time: s == null ? null : clock12(s),
                onTap: () => _pickTime(start: true),
              ),
              _TimeTile(
                title: 'Return',
                date: e == null ? null : shortDate(e),
                time: e == null ? null : clock12(e),
                onTap: () => _pickTime(start: false),
              ),
            ];
            if (c.maxWidth < 360) {
              return Column(
                children: [tiles[0], const SizedBox(height: 8), tiles[1]],
              );
            }
            return Row(
              children: [
                Expanded(child: tiles[0]),
                const SizedBox(width: 8),
                Expanded(child: tiles[1]),
              ],
            );
          },
        ),
        if (s != null && e != null) ...[
          const SizedBox(height: 10),
          Text(
            problem ?? '$days day${days == 1 ? '' : 's'} · ${days - 1} night${days - 1 == 1 ? '' : 's'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: problem == null ? scheme.primary : scheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (!widget.embedded) ...[
          const SizedBox(height: 12),
          CtaButton(
            icon: Icons.check_rounded,
            label: 'Confirm dates',
            onPressed: _problem == null
                ? () => widget.onSubmit(DateRangeAnswer(_start!, _end!))
                : null,
          ),
        ],
      ],
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.title,
    required this.date,
    required this.time,
    required this.onTap,
  });

  final String title;
  final String? date;
  final String? time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final set = date != null;
    return Material(
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: set ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.schedule_rounded, size: 20, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      set ? '$date · $time' : 'Tap to set',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

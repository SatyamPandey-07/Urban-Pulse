import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/domain/opening_hours.dart';

void main() {
  test('the common shapes are read', () {
    final h = OpeningHours.parse('Mo-Sa 09:00-17:00; Su off');
    expect(h.readable, isTrue);
    expect(h.isOpenFor(1, 9 * 60, 60), isTrue, reason: 'Monday 9-10');
    expect(h.isOpenFor(6, 16 * 60, 60), isTrue, reason: 'Saturday 4-5pm');
    expect(h.isOpenFor(6, 16 * 60 + 30, 60), isFalse, reason: 'past closing');
    expect(h.closedAllDay(7), isTrue);
    expect(h.isOpenFor(7, 10 * 60, 30), isFalse);
  });

  test('24/7 and time-only rules apply every day', () {
    expect(OpeningHours.parse('24/7').isOpenFor(3, 3 * 60, 600), isTrue);
    final t = OpeningHours.parse('08:00-18:00');
    for (var d = 1; d <= 7; d++) {
      expect(t.isOpenFor(d, 9 * 60, 60), isTrue);
    }
  });

  test('split days and late nights', () {
    final split = OpeningHours.parse('Mo-Fr 09:00-13:00,14:00-18:00');
    expect(split.isOpenFor(2, 13 * 60 + 15, 30), isFalse, reason: 'lunch break');
    expect(split.isOpenFor(2, 14 * 60, 60), isTrue);
    final late = OpeningHours.parse('Fr,Sa 18:00-02:00');
    expect(late.isOpenFor(5, 22 * 60, 120), isTrue);
    expect(late.isOpenFor(5, 23 * 60, 180), isTrue, reason: 'runs past midnight');
  });

  test('a day the text does not mention is closed (OSM semantics)', () {
    final h = OpeningHours.parse('Mo-Fr 10:00-16:00');
    expect(h.closedAllDay(6), isTrue);
    expect(h.nextSlot(6, 10 * 60, 60), isNull);
  });

  test('the next fitting slot waits for opening but not past closing', () {
    final h = OpeningHours.parse('Tu-Su 10:00-16:00');
    expect(h.nextSlot(2, 8 * 60, 60), 10 * 60, reason: 'arrive early, wait for 10');
    expect(h.nextSlot(2, 11 * 60, 60), 11 * 60);
    expect(h.nextSlot(2, 15 * 60 + 30, 60), isNull, reason: 'too late to fit');
  });

  test('anything unreadable means "may be open", never "closed"', () {
    for (final text in [null, '', 'sunrise-sunset', 'Mo-Fr 09:00-17:00; PH off', 'by appointment', 'Jan-Mar Mo 10:00-12:00', '???']) {
      final h = OpeningHours.parse(text);
      expect(h.readable, isFalse, reason: '$text');
      expect(h.isOpenFor(1, 600, 60), isNull, reason: '$text');
      expect(h.nextSlot(1, 600, 60), 600, reason: '$text: any time');
      expect(h.closedAllDay(1), isFalse, reason: '$text');
    }
  });

  test('garbage never throws', () {
    for (final text in ['\u0000', 'Mo-Xx 10:00-12:00', '25:99-99:99', 'Mo-Su', ';;;', 'a' * 5000, '10:00-10:00']) {
      expect(() => OpeningHours.parse(text), returnsNormally, reason: text);
    }
  });
}

/// The people an SOS actually reaches.
///
/// Before this, the SOS screen broadcast a BLE beacon to strangers in range and
/// nothing else: there was no one to tell. This is the list, stored on the
/// device next to every other preference.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One person to reach. [phone] is kept as the traveller typed it, because a
/// reformatted number is a number they cannot check.
@immutable
class EmergencyContact {
  const EmergencyContact({required this.name, required this.phone});

  final String name;
  final String phone;

  /// Digits and a leading `+` only — what an `sms:` URI and SmsManager want.
  String get dialable {
    final kept = StringBuffer();
    for (var i = 0; i < phone.length; i++) {
      final c = phone[i];
      if (c == '+' && kept.isEmpty) {
        kept.write(c);
      } else if (c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39) {
        kept.write(c);
      }
    }
    return kept.toString();
  }

  Map<String, Object?> toJson() => {'name': name, 'phone': phone};

  static EmergencyContact? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final phone = raw['phone'];
    if (name is! String || phone is! String) return null;
    if (name.trim().isEmpty || phone.trim().isEmpty) return null;
    return EmergencyContact(name: name.trim(), phone: phone.trim());
  }

  @override
  bool operator ==(Object other) =>
      other is EmergencyContact && other.name == name && other.phone == phone;

  @override
  int get hashCode => Object.hash(name, phone);

  @override
  String toString() => 'EmergencyContact($name, $phone)';
}

/// What is wrong with a contact the traveller is trying to save, or null when
/// nothing is.
///
/// Validation is deliberately loose on format and strict on substance: numbers
/// differ too much between countries to pattern-match safely, but a number with
/// fewer than 7 digits cannot reach anyone.
String? validateEmergencyContact({required String name, required String phone}) {
  if (name.trim().isEmpty) return 'Give this contact a name';
  if (name.trim().length > 40) return 'Keep the name under 40 characters';
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return 'Add a phone number';
  if (digits.length < 7) return 'That number is too short to dial';
  if (digits.length > 15) return 'That number is too long (E.164 allows 15 digits)';
  if (RegExp(r'[^0-9+\-()\s]').hasMatch(phone)) {
    return 'A phone number can only hold digits, spaces, +, -, ( and )';
  }
  return null;
}

/// The stored emergency contacts. A [ChangeNotifier] so the settings row, the
/// management screen and the SOS controller all see the same list.
class EmergencyContactsRepository extends ChangeNotifier {
  EmergencyContactsRepository(this._prefs) {
    _load();
  }

  static const _key = 'emergency_contacts_v1';

  /// Five is the ceiling: an SOS sends one message per contact, and a longer
  /// list turns a 10-second window into a queue.
  static const max = 5;

  final SharedPreferences _prefs;
  List<EmergencyContact> _contacts = const [];

  List<EmergencyContact> get contacts => List.unmodifiable(_contacts);

  bool get isEmpty => _contacts.isEmpty;

  bool get isFull => _contacts.length >= max;

  void _load() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _contacts = decoded
          .map(EmergencyContact.fromJson)
          .whereType<EmergencyContact>()
          .take(max)
          .toList(growable: false);
    } catch (_) {
      // A preference we cannot read is treated as no contacts, which the SOS
      // controller already refuses to send on.
      _contacts = const [];
    }
  }

  Future<void> _save() async {
    await _prefs.setString(_key, jsonEncode(_contacts.map((c) => c.toJson()).toList()));
    notifyListeners();
  }

  /// Adds [contact]. Returns the reason it was refused, or null on success.
  Future<String?> add(EmergencyContact contact) async {
    if (isFull) return 'You can keep up to $max emergency contacts';
    final problem = validateEmergencyContact(name: contact.name, phone: contact.phone);
    if (problem != null) return problem;
    if (_contacts.any((c) => c.dialable == contact.dialable)) {
      return 'That number is already on the list';
    }
    _contacts = [..._contacts, contact];
    await _save();
    return null;
  }

  /// Replaces the contact at [index]. Returns the reason it was refused, or null.
  Future<String?> update(int index, EmergencyContact contact) async {
    if (index < 0 || index >= _contacts.length) return 'That contact is no longer on the list';
    final problem = validateEmergencyContact(name: contact.name, phone: contact.phone);
    if (problem != null) return problem;
    final clash = _contacts.indexWhere((c) => c.dialable == contact.dialable);
    if (clash >= 0 && clash != index) return 'That number is already on the list';
    final next = [..._contacts];
    next[index] = contact;
    _contacts = next;
    await _save();
    return null;
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _contacts.length) return;
    _contacts = [..._contacts]..removeAt(index);
    await _save();
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/emergency/emergency_contacts.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';

/// The people an SOS reaches, and the only place they can be changed.
///
/// The empty state is deliberately blunt: until there is at least one contact, an
/// SOS has nobody to tell, and both this screen and the SOS button say so rather
/// than letting the traveller find out in an emergency.
class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = AppScope.of(context).emergencyContacts;

    return Scaffold(
      appBar: const ScreenHeader(
        title: 'Emergency contacts',
        subtitle: 'Who an SOS message goes to',
      ),
      body: AnimatedBuilder(
        animation: repo,
        builder: (context, _) {
          final contacts = repo.contacts;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              SectionCard(
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        contacts.isEmpty
                            ? 'Add at least one contact. Without one, SOS cannot send anything.'
                            : 'An SOS sends each of these a message with a map link, after a '
                                  '10 second window in which you can cancel.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (contacts.isEmpty)
                EmptyState(
                  icon: Icons.contact_emergency_outlined,
                  message: 'No emergency contacts yet. Add up to '
                      '${EmergencyContactsRepository.max} people to alert when you raise an SOS.',
                )
              else
                ...List.generate(contacts.length, (i) => _row(context, repo, i, contacts[i])),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: repo.isFull ? null : () => _edit(repo, null),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(
                  repo.isFull
                      ? 'Maximum ${EmergencyContactsRepository.max} contacts'
                      : 'Add a contact',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(
    BuildContext context,
    EmergencyContactsRepository repo,
    int index,
    EmergencyContact contact,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SectionCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                contact.name.isEmpty ? '?' : contact.name[0].toUpperCase(),
                style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.name,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    contact.phone,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _edit(repo, index),
            ),
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _confirmRemove(repo, index, contact),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(
    EmergencyContactsRepository repo,
    int index,
    EmergencyContact contact,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove contact?'),
        content: Text('${contact.name} will no longer be alerted by an SOS.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (yes == true) await repo.removeAt(index);
  }

  /// [index] null adds; otherwise edits that contact.
  Future<void> _edit(EmergencyContactsRepository repo, int? index) async {
    final existing = index == null ? null : repo.contacts[index];
    final name = TextEditingController(text: existing?.name ?? '');
    final phone = TextEditingController(text: existing?.phone ?? '');
    String? error;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                index == null ? 'Add emergency contact' : 'Edit contact',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  // Only what a number can contain, so validation is about
                  // substance rather than stray characters.
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-()\s]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  hintText: '+91 98765 43210',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  final candidate = EmergencyContact(
                    name: name.text.trim(),
                    phone: phone.text.trim(),
                  );
                  final problem = index == null
                      ? await repo.add(candidate)
                      : await repo.update(index, candidate);
                  if (problem == null) {
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } else {
                    setSheet(() => error = problem);
                  }
                },
                child: Text(index == null ? 'Add contact' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );

    name.dispose();
    phone.dispose();
    if (saved == true && mounted) {
      showToast(context, index == null ? 'Contact added' : 'Contact updated');
    }
  }
}

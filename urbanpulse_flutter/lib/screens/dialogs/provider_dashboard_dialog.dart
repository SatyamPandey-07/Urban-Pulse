import 'package:flutter/material.dart';

import '../../core/formatting.dart';
import '../../models/experience_listing.dart';
import '../../repositories/experience_repository.dart';
import '../../services/central_registry_client.dart';
import '../../widgets/common.dart';

/// Port of `dialog_provider_dashboard.xml` and
/// `YatriAiFragment.showProviderDashboardDialog` — the provider hub: real
/// platform impact stats, each listing's real view/inquiry/booking counters, an
/// availability switch, and a drill-down into the actual booking and
/// accessibility-report rows.
class ProviderDashboardDialog extends StatefulWidget {
  const ProviderDashboardDialog({
    required this.repository,
    required this.onAddNew,
    super.key,
  });

  final ExperienceRepository repository;
  final VoidCallback onAddNew;

  static Future<void> show(
    BuildContext context, {
    required ExperienceRepository repository,
    required VoidCallback onAddNew,
  }) => showDialog<void>(
    context: context,
    builder: (_) =>
        ProviderDashboardDialog(repository: repository, onAddNew: onAddNew),
  );

  @override
  State<ProviderDashboardDialog> createState() =>
      _ProviderDashboardDialogState();
}

class _ProviderDashboardDialogState extends State<ProviderDashboardDialog> {
  List<ExperienceListing> _listings = const [];
  ImpactStats? _impact;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<ExperienceListing> listings;
    try {
      listings = await widget.repository.getAllExperiences();
    } catch (_) {
      listings = const [];
    }
    final impact = await CentralRegistryClient.fetchImpactStats();
    if (!mounted) return;
    setState(() {
      _listings = listings;
      _impact = impact;
      _isLoading = false;
    });
  }

  Future<void> _toggleAvailability(ExperienceListing exp, bool value) async {
    await widget.repository.toggleAvailability(exp.id, available: value);
    if (!mounted) return;
    showToast(context, '${exp.name} availability updated!');
    await _load();
  }

  Future<void> _showDetails(ExperienceListing exp) async {
    final bookings = await CentralRegistryClient.fetchBookings(exp.id);
    final reports = await CentralRegistryClient.fetchReports(exp.id);
    if (!mounted) return;

    final buffer = StringBuffer()
      ..writeln('${bookings?.length ?? 0} Real Booking(s)');
    if (bookings == null || bookings.isEmpty) {
      buffer.writeln('No bookings yet');
    } else {
      for (final b in bookings) {
        buffer.writeln(
          '• ${b.travelerName} — party of ${b.partySize} — ${b.bookingDate} (${b.status})',
        );
      }
    }
    buffer
      ..writeln()
      ..writeln('${reports?.length ?? 0} Real Accessibility Report(s)');
    if (reports == null || reports.isEmpty) {
      buffer.writeln('No reports yet');
    } else {
      for (final r in reports) {
        final verdict = r.confirmsAccessibility ? '[Confirmed]' : '[Disputed]';
        buffer.writeln('• $verdict${r.note.isNotEmpty ? ": ${r.note}" : ""}');
      }
    }
    if (bookings == null && reports == null) {
      buffer
        ..writeln()
        ..writeln('Note: Central Registry backend unreachable.');
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(exp.name),
        content: SingleChildScrollView(child: Text(buffer.toString())),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Provider Hub — My Listings'),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: _isLoading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  // Real Impact Dashboard summary — SQL-aggregated from actual
                  // bookings/reports on the Central Registry backend, not a
                  // fabricated headline number. Omitted entirely (rather than
                  // showing zeros) when the backend isn't reachable, so it never
                  // implies live data it doesn't have.
                  if (_impact case final impact?) ...[
                    SectionCard(
                      padding: const EdgeInsets.all(16),
                      borderWidth: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Real Platform Impact (Live)',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${impact.experienceCount} experiences • '
                            '${impact.bookingCount} real bookings • '
                            '${impact.travelerCount} travelers served',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${impact.accessibilityConfirmCount + impact.accessibilityDisputeCount} '
                            'accessibility reports collected • '
                            'Avg. eco score: ${impact.averageEcoScore}/5',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_listings.isEmpty)
                    const EmptyState(
                      message:
                          'No listings yet — publish your first experience.',
                      icon: Icons.storefront_outlined,
                    )
                  else
                    for (final exp in _listings) ...[
                      _listingCard(context, exp),
                      const SizedBox(height: 16),
                    ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            widget.onAddNew();
          },
          child: const Text('Add New Listing'),
        ),
      ],
    );
  }

  Widget _listingCard(BuildContext context, ExperienceListing exp) {
    final theme = Theme.of(context);
    return SectionCard(
      padding: const EdgeInsets.all(16),
      borderWidth: 2,
      borderColor: theme.colorScheme.outlineVariant,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exp.name,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${exp.category} • ${exp.location} • ${fixed(exp.durationHours)}h • '
            '${exp.pricePerPerson}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            '${exp.viewsCount} Views • ${exp.inquiryCount} Inquiries • '
            '${exp.bookingCount} Bookings',
            style: theme.textTheme.bodySmall,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              exp.isAvailableToday
                  ? 'Available Today (Accepting Travelers)'
                  : 'Booked Out / Paused',
              style: theme.textTheme.bodySmall,
            ),
            value: exp.isAvailableToday,
            onChanged: (value) => _toggleAvailability(exp, value),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _showDetails(exp),
              child: const Text('View Booking & Report Details'),
            ),
          ),
        ],
      ),
    );
  }
}

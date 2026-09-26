import 'package:flutter/material.dart';

import '../../repositories/experience_repository.dart';

/// Result of a successful publish, so the caller can echo the new listing back
/// into the conversation.
class PublishedExperience {
  const PublishedExperience({
    required this.name,
    required this.category,
    required this.location,
    required this.duration,
    required this.price,
    required this.sustainability,
    required this.tags,
  });

  final String name;
  final String category;
  final String location;
  final double duration;
  final int price;
  final String sustainability;
  final List<String> tags;
}

/// Port of `dialog_add_experience.xml` and `YatriAiFragment.showAddExperienceDialog`
/// — the provider self-listing form. Publishes through [ExperienceRepository],
/// which writes to the Central Registry when reachable and always to the local
/// store.
class AddExperienceDialog extends StatefulWidget {
  const AddExperienceDialog({
    required this.repository,
    this.detectedCity,
    super.key,
  });

  final ExperienceRepository repository;

  /// Pre-fills the location field with where the provider actually is.
  final String? detectedCity;

  static Future<PublishedExperience?> show(
    BuildContext context,
    ExperienceRepository repository, {
    String? detectedCity,
  }) => showDialog<PublishedExperience>(
    context: context,
    builder: (_) =>
        AddExperienceDialog(repository: repository, detectedCity: detectedCity),
  );

  @override
  State<AddExperienceDialog> createState() => _AddExperienceDialogState();
}

class _AddExperienceDialogState extends State<AddExperienceDialog> {
  final _name = TextEditingController();
  final _category = TextEditingController(text: 'Cultural Workshop');
  late final _location = TextEditingController(text: widget.detectedCity ?? '');
  final _duration = TextEditingController(text: '2.0');
  final _price = TextEditingController(text: '350');
  final _sustainability = TextEditingController(
    text: 'Local artisan cooperative, zero single-use plastic',
  );

  bool _stepFree = false;
  bool _audioGuide = false;
  bool _isPublishing = false;
  String? _nameError;

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _location.dispose();
    _duration.dispose();
    _price.dispose();
    _sustainability.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Please enter an experience name');
      return;
    }

    final category = _category.text.trim().isEmpty
        ? 'Cultural Workshop'
        : _category.text.trim();
    final location = _location.text.trim().isEmpty
        ? (widget.detectedCity ?? 'Unspecified')
        : _location.text.trim();
    final duration = double.tryParse(_duration.text) ?? 2.0;
    final price = int.tryParse(_price.text) ?? 350;
    final sustainability = _sustainability.text.trim().isEmpty
        ? 'Local artisan cooperative'
        : _sustainability.text.trim();

    final tags = <String>[
      if (_stepFree) 'Step-Free Ramp Access',
      if (_audioGuide) 'Audio & Tactile Guide',
    ];
    if (tags.isEmpty) tags.add('Standard Access');

    setState(() {
      _isPublishing = true;
      _nameError = null;
    });

    final success = await widget.repository.addExperience(
      name: name,
      category: category,
      location: location,
      sustainabilityPractice: sustainability,
      accessibilityTags: tags,
      accessibilityRating: _stepFree ? 96 : 75,
      ecoScore: 5,
      carbonKg: 0.4,
      priceRupees: price,
      durationHours: duration,
    );

    if (!mounted) return;
    Navigator.of(context).pop(
      success
          ? PublishedExperience(
              name: name,
              category: category,
              location: location,
              duration: duration,
              price: price,
              sustainability: sustainability,
              tags: tags,
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      scrollable: true,
      title: const Text('List Your Local Experience'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Empower travelers to discover your local heritage, workshop, or eco-tour',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Experience / Workshop Name',
              errorText: _nameError,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _category,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Category (e.g. Heritage, Culinary, Workshop)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _location,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Location / Neighborhood (e.g. Bandra West, Mumbai)',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _duration,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Duration (Hours)',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Price (₹ / person)',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _sustainability,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Sustainability Practice',
              hintText: 'e.g. 100% natural clay, solar-powered',
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Step-Free / Wheelchair Accessible Ramps'),
            value: _stepFree,
            onChanged: (v) => setState(() => _stepFree = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Audio Guide / Tactile Tour Available'),
            value: _audioGuide,
            onChanged: (v) => setState(() => _audioGuide = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isPublishing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isPublishing ? null : _publish,
          child: _isPublishing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Publish Listing'),
        ),
      ],
    );
  }
}

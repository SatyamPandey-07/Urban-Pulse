import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../core/formatting.dart';
import '../domain/linear_regression.dart';
import '../repositories/facility_repository.dart';
import '../services/esg_pdf_generator.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';

/// Port of `HotelOptimizerActivity` / `activity_hotel_optimizer.xml` — the B2B
/// resource hub. Energy, water and food-surplus figures are predicted by three
/// ordinary-least-squares models trained at runtime on the 60-day occupancy
/// history in the on-device store, not fixed coefficients.
class HotelOptimizerScreen extends StatefulWidget {
  const HotelOptimizerScreen({super.key});

  @override
  State<HotelOptimizerScreen> createState() => _HotelOptimizerScreenState();
}

class _HotelOptimizerScreenState extends State<HotelOptimizerScreen> {
  /// Read from the editable facility profile, not compiled in.
  FacilityProfile? _facility;

  double _occupancyPercent = 75;
  bool _isEcoHvacActive = false;
  bool _isDispatched = false;
  bool _isGeneratingReport = false;

  LinearRegression? _energyModel;
  LinearRegression? _waterModel;
  LinearRegression? _wasteModel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFacility();
      _trainModels();
    });
  }

  Future<void> _loadFacility() async {
    final profile = await AppScope.of(context).facility.getProfile();
    if (!mounted) return;
    setState(() => _facility = profile);
  }

  Future<void> _trainModels() async {
    final history = await AppScope.of(context).hotelMetrics.getHistory();
    if (!mounted || history.length < 2) return;
    setState(() {
      _energyModel = LinearRegression.fit([
        for (final s in history) (s.occupancyPercent, s.energyKwh),
      ]);
      _waterModel = LinearRegression.fit([
        for (final s in history) (s.occupancyPercent, s.waterLiters),
      ]);
      _wasteModel = LinearRegression.fit([
        for (final s in history) (s.occupancyPercent, s.foodWasteKg),
      ]);
    });
  }

  int get _totalRooms => _facility?.totalRooms ?? 0;

  int get _occupiedRooms => (_totalRooms * (_occupancyPercent / 100)).toInt();

  int get _vacantRooms => _totalRooms - _occupiedRooms;

  int get _covers => (_occupiedRooms * 2.5).toInt();

  double get _hvacSavings =>
      _isEcoHvacActive ? _vacantRooms * 4.8 : _vacantRooms * 1.5;

  String get _energyTotal {
    final model = _energyModel;
    if (model == null) return '…';
    final predicted = model.predict(_occupancyPercent);
    final total = (predicted - (_isEcoHvacActive ? _hvacSavings : 0.0)).toInt();
    return grouped(total < 0 ? 0 : total);
  }

  String get _waterTotal {
    final model = _waterModel;
    if (model == null) return '…';
    final total = model.predict(_occupancyPercent).toInt();
    return grouped(total < 0 ? 0 : total);
  }

  String get _foodSurplus {
    final model = _wasteModel;
    if (model == null) return '…';
    return fixed(model.predict(_occupancyPercent).coerceAtLeast(0));
  }

  Future<void> _generateEsgReport() async {
    final facility = _facility;
    if (facility == null) return;
    setState(() => _isGeneratingReport = true);
    final mealsCount = (_covers * 0.076 * 2.5).toInt();

    try {
      final result = await EsgPdfGenerator.generate(
        facilityName: facility.name,
        occupancyPct: _occupancyPercent.toInt(),
        totalRooms: facility.totalRooms,
        energyTotalKwh: _energyTotal,
        energySavedKwh: '${_hvacSavings.toInt()} kWh',
        waterTotalLiters: _waterTotal,
        foodSurplusKg: _foodSurplus,
        mealsCount: mealsCount,
        energyRSquared: _energyModel?.rSquared ?? 0.0,
        wasteRSquared: _wasteModel?.rSquared ?? 0.0,
        solarMixPercent: facility.solarMixPercent,
        greywaterRatePercent: facility.greywaterRatePercent,
        energyTargetKwhPerRoom: facility.energyTargetKwhPerRoom,
        waterTargetLitersPerRoom: facility.waterTargetLitersPerRoom,
      );
      if (!mounted) return;
      setState(() => _isGeneratingReport = false);

      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Official ESG Audit PDF Generated'),
          content: Text(
            'Your ISO 14064 & LEED Platinum-benchmarked audit PDF report is ready.\n\n'
            '• File: ${result.fileName}\n'
            '• Size: ${result.sizeKb} KB\n'
            '• Compliance: ${result.complianceStatus} (computed from live occupancy vs. '
            'benchmarks)\n'
            '• Integrity Hash: ${result.contentHash.substring(0, 12)}…',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('done'),
              child: const Text('Done'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('share'),
              child: const Text('Share PDF'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('open'),
              child: const Text('Open PDF'),
            ),
          ],
        ),
      );

      if (!mounted || action == null || action == 'done') return;
      if (action == 'open') {
        await Printing.layoutPdf(
          onLayout: (_) async => result.bytes,
          name: result.fileName,
        );
      } else {
        await Printing.sharePdf(bytes: result.bytes, filename: result.fileName);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGeneratingReport = false);
      showToast(context, 'Failed to generate PDF: $e');
    }
  }

  /// Lets the operator edit the declared facility parameters the model and the
  /// audit sheet are built from.
  Future<void> _editFacility() async {
    final current = _facility;
    if (current == null) return;

    final name = TextEditingController(text: current.name);
    final rooms = TextEditingController(text: '${current.totalRooms}');
    final solar = TextEditingController(text: '${current.solarMixPercent}');
    final greywater = TextEditingController(
      text: '${current.greywaterRatePercent}',
    );
    final energyTarget = TextEditingController(
      text: '${current.energyTargetKwhPerRoom}',
    );
    final waterTarget = TextEditingController(
      text: '${current.waterTargetLitersPerRoom}',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Facility Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Facility name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rooms,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Total rooms'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: solar,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Declared onsite renewable mix (%)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: greywater,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Declared greywater recycling rate (%)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: energyTarget,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Energy benchmark (kWh per room)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: waterTarget,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Water benchmark (litres per room)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) return;
    final updated = current.copyWith(
      name: name.text.trim().isEmpty ? current.name : name.text.trim(),
      totalRooms: int.tryParse(rooms.text) ?? current.totalRooms,
      solarMixPercent: double.tryParse(solar.text) ?? current.solarMixPercent,
      greywaterRatePercent:
          double.tryParse(greywater.text) ?? current.greywaterRatePercent,
      energyTargetKwhPerRoom:
          double.tryParse(energyTarget.text) ?? current.energyTargetKwhPerRoom,
      waterTargetLitersPerRoom:
          double.tryParse(waterTarget.text) ?? current.waterTargetLitersPerRoom,
    );
    await AppScope.of(context).facility.saveProfile(updated);
    if (!mounted) return;
    setState(() => _facility = updated);
    showToast(context, 'Facility profile updated.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final facility = _facility;
    final isTraining =
        facility == null ||
        _energyModel == null ||
        _waterModel == null ||
        _wasteModel == null;

    return Scaffold(
      appBar: ScreenHeader(
        title: 'Hotel Resource Optimizer',
        subtitle:
            facility?.name ?? 'Real-Time Energy, Water & ESG Compliance Hub',
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Edit facility profile',
            onPressed: facility == null ? null : _editFacility,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Live Facility Operations Parameter',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Occupied Rooms: $_occupiedRooms / $_totalRooms '
                  '(${_occupancyPercent.toInt()}%)',
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  'Dining Covers: $_covers',
                  style: theme.textTheme.bodySmall,
                ),
                Slider(
                  value: _occupancyPercent,
                  max: 100,
                  divisions: 100,
                  label: '${_occupancyPercent.toInt()}%',
                  onChanged: (value) =>
                      setState(() => _occupancyPercent = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SectionCard(
                  padding: const EdgeInsets.all(16),
                  child: StatTile(
                    label: 'Total Energy',
                    value: _energyTotal,
                    caption: 'kWh / day',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SectionCard(
                  padding: const EdgeInsets.all(16),
                  child: StatTile(
                    label: 'Water Recycled',
                    value: _waterTotal,
                    caption: 'Liters / day',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SectionCard(
                  padding: const EdgeInsets.all(16),
                  child: StatTile(
                    label: 'Food Surplus',
                    value: _foodSurplus,
                    caption: 'kg diverted',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isTraining
                ? 'Fitting prediction model on 60 days of occupancy history…'
                : '▼ ${_hvacSavings.toInt()} kWh saved (predicted, '
                      'R²=${fixed(_energyModel!.rSquared, 2)})',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'ESG Sustainability & Audit Sheet',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      'LEED PLATINUM',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Generates signed, live compliance audit sheets for BEE Star Rating, '
                  'ESG reporting, and municipal zero-waste tax credits.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: isTraining || _isGeneratingReport
                        ? null
                        : _generateEsgReport,
                    icon: _isGeneratingReport
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('Generate & Share ESG Audit Sheet'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Kitchen Surplus & Waste Diversion',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _isDispatched
                      ? 'Dispatched: $_foodSurplus kg surplus food claimed by Roti Bank & '
                            'Feeding India Mumbai. Driver en route.'
                      : isTraining
                      ? 'Fitting prediction model on 60 days of occupancy history…'
                      : 'Dinner Buffet Forecast: ~$_foodSurplus kg surplus meals '
                            'predicted from ${_wasteModel!.sampleCount}-day occupancy '
                            'trend (R²=${fixed(_wasteModel!.rSquared, 2)}).',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: _isDispatched || isTraining
                        ? null
                        : () {
                            setState(() => _isDispatched = true);
                            showToast(
                              context,
                              'Shelter alert sent! +200 XP toward Green Star Hotel '
                              'Certification.',
                            );
                          },
                    child: Text(
                      _isDispatched
                          ? 'Shelter Dispatch Active'
                          : 'Auto-Dispatch Alert to Local Food Shelter',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Smart HVAC & Lighting Dynamic Schedule',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Occupancy sensor: $_vacantRooms vacant rooms detected. '
                  '${_isEcoHvacActive ? "26°C Eco setpoint active." : "Shift cooling to 26°C to save energy."}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: _isEcoHvacActive
                        ? null
                        : () {
                            setState(() => _isEcoHvacActive = true);
                            showToast(
                              context,
                              'Automated 26°C Eco Setpoint applied across all vacant '
                              'wings!',
                            );
                          },
                    child: Text(
                      _isEcoHvacActive
                          ? 'Eco Setpoint Active (26°C)'
                          : 'Apply Automated 26°C Eco Setpoint',
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

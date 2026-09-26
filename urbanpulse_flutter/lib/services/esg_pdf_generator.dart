import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/formatting.dart';

class EsgAuditResult {
  const EsgAuditResult({
    required this.bytes,
    required this.fileName,
    required this.complianceStatus,
    required this.contentHash,
  });

  final Uint8List bytes;
  final String fileName;
  final String complianceStatus;
  final String contentHash;

  int get sizeKb => (bytes.lengthInBytes / 1024).round();
}

/// Builds the A4 ISO 14064 / LEED-benchmarked ESG audit sheet.
///
/// Port of `utils/EsgPdfGenerator.kt`. Compliance is *computed* from the live
/// occupancy-derived figures against the stated benchmarks (it is not a fixed
/// "PASSED"), and the footer carries a genuine SHA-256 digest of the report's
/// own data fields.
abstract final class EsgPdfGenerator {
  // BEE 5-Star energy benchmark and the facility's water target.
  static const _energyTargetKwhPerRoom = 20.0;
  static const _waterTargetLitersPerRoom = 220.0;

  static Future<EsgAuditResult> generate({
    required String facilityName,
    required int occupancyPct,
    required int totalRooms,
    required String energyTotalKwh,
    required String energySavedKwh,
    required String waterTotalLiters,
    required String foodSurplusKg,
    required int mealsCount,
    required double energyRSquared,
    required double wasteRSquared,
  }) async {
    final dateStr = _formatTimestamp(DateTime.now());

    final energyTotalNum =
        double.tryParse(energyTotalKwh.replaceAll(',', '')) ?? 0.0;
    final waterTotalNum =
        double.tryParse(waterTotalLiters.replaceAll(',', '')) ?? 0.0;
    final powerPerRoom = totalRooms > 0 ? energyTotalNum / totalRooms : 0.0;
    final waterPerRoom = totalRooms > 0 ? waterTotalNum / totalRooms : 0.0;
    final passPower = powerPerRoom <= _energyTargetKwhPerRoom;
    final passWater = waterPerRoom <= _waterTargetLitersPerRoom;
    final complianceStatus = passPower && passWater
        ? 'PASSED'
        : 'NEEDS IMPROVEMENT';
    final greywaterRecycled = (waterTotalNum * 0.85).toInt();

    final reportBody =
        'Facility=$facilityName;Occupancy=$occupancyPct%;Rooms=$totalRooms;'
        'Date=$dateStr;Energy=$energyTotalKwh;Water=$waterTotalLiters;Food=$foodSurplusKg;'
        'PowerPerRoom=${fixed(powerPerRoom, 2)};WaterPerRoom=${fixed(waterPerRoom, 2)};'
        'Compliance=$complianceStatus';
    final contentHash = sha256.convert(utf8.encode(reportBody)).toString();

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.Stack(
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _header(),
                pw.Padding(
                  padding: const pw.EdgeInsets.fromLTRB(32, 15, 32, 0),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      _metaBox(
                        facilityName: facilityName,
                        dateStr: dateStr,
                        occupancyPct: occupancyPct,
                        totalRooms: totalRooms,
                        complianceStatus: complianceStatus,
                        compliant: passPower && passWater,
                      ),
                      pw.SizedBox(height: 22),
                      _sectionTitle('Energy Efficiency & HVAC Load'),
                      _metricRow(
                        'Daily Power Consumption (${fixed(powerPerRoom)} kWh/room)',
                        '$energyTotalKwh kWh',
                        passPower
                            ? 'PASS — Target <= 20 kWh/room'
                            : 'FAIL — Target <= 20 kWh/room',
                        highlight: passPower,
                      ),
                      _metricRow(
                        'Automated HVAC Power Avoided (R²=${fixed(energyRSquared, 2)})',
                        energySavedKwh,
                        'Automated 26°C Setback',
                        highlight: true,
                      ),
                      _metricRow(
                        'Onsite Solar Generation Mix (facility-declared, not metered)',
                        '38.5% Renewable',
                        'Target: >= 30.0%',
                      ),
                      pw.SizedBox(height: 10),
                      _sectionTitle('Water Stewardship & Recycling'),
                      _metricRow(
                        'Daily Potable Water Consumption (${fixed(waterPerRoom, 0)} L/room)',
                        '$waterTotalLiters Liters',
                        passWater
                            ? 'PASS — Target <= 220 L/room'
                            : 'FAIL — Target <= 220 L/room',
                        highlight: passWater,
                      ),
                      _metricRow(
                        'Greywater Recycled & Reused (declared 85% rate)',
                        '${grouped(greywaterRecycled)} Liters',
                        'Zero Liquid Discharge (ZLD)',
                      ),
                      pw.SizedBox(height: 10),
                      _sectionTitle('Kitchen Surplus & Food Diversion'),
                      _metricRow(
                        'Surplus Food Diverted (R²=${fixed(wasteRSquared, 2)})',
                        '$foodSurplusKg kg',
                        '60-Day Occupancy Trend Model',
                      ),
                      _metricRow(
                        'Shelter Meals Provided (est. 2 meals/kg)',
                        '$mealsCount Meals',
                        'Local Food Rescue Partner',
                        highlight: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.Positioned(
              left: 32,
              right: 32,
              bottom: 42,
              child: _footer(contentHash),
            ),
          ],
        ),
      ),
    );

    return EsgAuditResult(
      bytes: await doc.save(),
      fileName: 'UrbanPulse_ESG_Audit_Report_${occupancyPct}pct.pdf',
      complianceStatus: complianceStatus,
      contentHash: contentHash,
    );
  }

  static pw.Widget _header() => pw.Container(
    height: 90,
    width: double.infinity,
    color: PdfColor.fromInt(0xFF064E3B), // Deep emerald green
    padding: const pw.EdgeInsets.fromLTRB(32, 20, 32, 12),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'URBANPULSE • B2B SUSTAINABILITY INTELLIGENCE PLATFORM',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromInt(0xFF10B981),
          ),
        ),
        pw.Text(
          'ESG Compliance & Resource Audit',
          style: pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
        ),
        pw.Text(
          'Standard: ISO 14064 Greenhouse Protocol • LEED Platinum & BEE 5-Star '
          'Benchmarking',
          style: pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFFA7F3D0)),
        ),
      ],
    ),
  );

  static pw.Widget _metaBox({
    required String facilityName,
    required String dateStr,
    required int occupancyPct,
    required int totalRooms,
    required String complianceStatus,
    required bool compliant,
  }) {
    final statusColor = compliant
        ? PdfColor.fromInt(0xFF059669)
        : PdfColor.fromInt(0xFFDC2626);
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFF1F5F9),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Facility: $facilityName',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Audit Timestamp: $dateStr',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Occupancy Scale: $occupancyPct% ($totalRooms Active Rooms)',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Compliance Status: $complianceStatus (live figures vs. benchmarks)',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _sectionTitle(String title) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Divider(
          height: 1,
          thickness: 1,
          color: PdfColor.fromInt(0xFFCBD5E1),
        ),
      ],
    ),
  );

  static pw.Widget _metricRow(
    String label,
    String value,
    String benchmark, {
    bool highlight = false,
  }) => pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 6),
    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromInt(highlight ? 0xFFECFDF5 : 0xFFF8FAFC),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Row(
      children: [
        pw.Expanded(
          flex: 5,
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 10,
              color: PdfColor.fromInt(0xFF334155),
            ),
          ),
        ),
        pw.Expanded(
          flex: 3,
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromInt(highlight ? 0xFF059669 : 0xFF0F172A),
            ),
          ),
        ),
        pw.Expanded(
          flex: 4,
          child: pw.Text(
            benchmark,
            style: pw.TextStyle(
              fontSize: 9,
              color: PdfColor.fromInt(0xFF64748B),
            ),
          ),
        ),
      ],
    ),
  );

  static pw.Widget _footer(String contentHash) => pw.Container(
    decoration: pw.BoxDecoration(
      color: PdfColor.fromInt(0xFFF1F5F9),
      borderRadius: pw.BorderRadius.circular(8),
    ),
    padding: const pw.EdgeInsets.all(14),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Report Generation Method',
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromInt(0xFF064E3B),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Energy/Water/Food figures are live predictions from a linear regression fit '
          'on 60 days of occupancy history.',
          style: pw.TextStyle(
            fontSize: 7.5,
            color: PdfColor.fromInt(0xFF64748B),
          ),
        ),
        pw.Text(
          'Solar mix & greywater rate are facility-declared assumptions, not metered '
          'telemetry. Compliance is computed, not fixed.',
          style: pw.TextStyle(
            fontSize: 7.5,
            color: PdfColor.fromInt(0xFF64748B),
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          'Content Integrity Hash (SHA-256): $contentHash',
          style: pw.TextStyle(fontSize: 7, color: PdfColor.fromInt(0xFF64748B)),
        ),
        pw.Text(
          "Real digest of this report's data fields, computed on-device at generation "
          'time — not a legal/regulatory signature.',
          style: pw.TextStyle(fontSize: 7, color: PdfColor.fromInt(0xFF64748B)),
        ),
      ],
    ),
  );

  /// `dd MMMM yyyy, HH:mm`, matching the Kotlin `SimpleDateFormat`.
  static String _formatTimestamp(DateTime now) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '$day ${months[now.month - 1]} ${now.year}, $hour:$minute';
  }
}

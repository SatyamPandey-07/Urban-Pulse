import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/formatting.dart';
import '../models/itinerary/itinerary.dart';
import '../models/trip_brief.dart';

/// Builds a printable, shareable PDF of an [Itinerary]: the days with times,
/// the budget, the accessibility audit, the footprint, the assumptions and the
/// sources. Uses a Unicode font when it can be fetched (so ₹ prints), and
/// falls back to the built-in font with plain-text stand-ins when offline.
abstract final class ItineraryPdf {
  static const _green = PdfColor.fromInt(0xFF00B87A);
  static const _grey = PdfColor.fromInt(0xFF64748B);

  static Future<Uint8List> build(Itinerary it) async {
    pw.Font? base;
    pw.Font? bold;
    try {
      final fonts = await Future.wait([PdfGoogleFonts.notoSansRegular(), PdfGoogleFonts.notoSansBold()]).timeout(const Duration(seconds: 6));
      base = fonts[0];
      bold = fonts[1];
    } catch (_) {
      base = null;
    }
    final unicode = base != null;
    String t(String s) => unicode ? s : plain(s);

    final doc = pw.Document(
      title: '${it.destination} itinerary',
      author: 'UrbanPulse · Yatri AI',
      theme: unicode ? pw.ThemeData.withFont(base: base, bold: bold) : null,
    );

    final needs = {for (final n in it.brief?.accessibilityNeeds ?? const <AccessibilityNeed>{}) if (n != AccessibilityNeed.none) n};

    pw.Widget h1(String s) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
      child: pw.Text(t(s), style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _green)),
    );
    pw.Widget body(String s, {PdfColor? color, bool bold = false}) =>
        pw.Text(t(s), style: pw.TextStyle(fontSize: 10, color: color, fontWeight: bold ? pw.FontWeight.bold : null));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(t('Made with UrbanPulse · page ${ctx.pageNumber} of ${ctx.pagesCount}'), style: const pw.TextStyle(fontSize: 8, color: _grey)),
        ),
        build: (ctx) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(color: _green, borderRadius: pw.BorderRadius.circular(10)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(t('${it.destination}: ${it.dayCount}-day trip'), style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                pw.SizedBox(height: 4),
                pw.Text(t('${dateRangeLabel(it.start, it.end)} · from ${it.origin}'), style: const pw.TextStyle(fontSize: 11, color: PdfColors.white)),
                pw.SizedBox(height: 8),
                pw.Text(
                  t([
                    rupees(it.budget.totalInr),
                    if (it.green != null) '${fixed(it.green!.co2Kg, 0)} kg CO2',
                    '${(it.confidence * 100).round()}% real data',
                  ].join('   ·   ')),
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                ),
              ],
            ),
          ),
          if (it.travellerSummary.isNotEmpty) ...[pw.SizedBox(height: 8), body(it.travellerSummary, color: _grey)],

          h1('Where you stay'),
          if (it.hotel == null)
            body('No stay is included in this plan.')
          else ...[
            body(it.hotel!.name, bold: true),
            body([
              it.hotel!.type,
              if (it.hotel!.rating != null) 'rated ${it.hotel!.rating!.toStringAsFixed(1)}',
              if (it.hotel!.nightlyInr != null) '${it.hotel!.priceIsEstimated ? 'about ' : ''}${rupees(it.hotel!.nightlyInr!)} a night${it.hotel!.priceIsEstimated ? ' (estimate)' : ''}',
            ].join(' · ')),
            for (final n in needs)
              if (it.hotel!.access[n] != null) body('${n.label}: ${it.hotel!.access[n]!.level.label}${it.hotel!.access[n]!.detail.isEmpty ? '' : ' (${it.hotel!.access[n]!.detail})'}', color: _grey),
          ],

          if (it.chosenTransport != null) ...[
            h1('Getting there'),
            body('${it.chosenTransport!.mode.label}: ${it.chosenTransport!.from} to ${it.chosenTransport!.to}', bold: true),
            body('${_dur(it.chosenTransport!.durationMin)} · ${rupees(it.chosenTransport!.costInr)} one way (estimate) · ${fixed(it.chosenTransport!.co2Grams / 1000, 0)} kg CO2'),
            if (it.chosenTransport!.note != null) body(it.chosenTransport!.note!, color: _grey),
          ],

          for (final d in it.days) ...[
            h1('Day ${d.number} · ${shortDate(d.date)}: ${d.title}'),
            if (d.weather != null) body('Weather: ${d.weather}', color: _grey),
            pw.SizedBox(height: 4),
            if (d.slots.isEmpty)
              body('A free day: nothing is planned.')
            else
              pw.Table(
                columnWidths: {0: const pw.FixedColumnWidth(52), 1: const pw.FlexColumnWidth(3), 2: const pw.FlexColumnWidth(2)},
                border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
                children: [
                  for (final s in d.slots)
                    pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: body(clock12(s.start), color: _grey)),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 3),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              body(s.title, bold: s.kind == SlotKind.visit || s.kind == SlotKind.stay),
                              if (s.note != null && s.note!.isNotEmpty && s.kind != SlotKind.transit) body(s.note!, color: _grey),
                            ],
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 3),
                          child: body(
                            [
                              if (s.costInr != null && s.costInr! > 0) rupees(s.costInr!),
                              if (s.access != null) 'access: ${s.access!.label.toLowerCase()}',
                              ...s.flags,
                            ].join(' · '),
                            color: _grey,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
          ],

          h1('Budget'),
          pw.Table(
            columnWidths: {0: const pw.FlexColumnWidth(4), 1: const pw.FlexColumnWidth(1)},
            border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
            children: [
              for (final l in it.budget.lines)
                pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: body('${l.label}${l.isEstimated ? ' (estimate)' : ''}')),
                    pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: pw.Align(alignment: pw.Alignment.centerRight, child: body(rupees(l.amountInr)))),
                  ],
                ),
              pw.TableRow(
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.only(top: 5), child: body('Total', bold: true)),
                  pw.Padding(padding: const pw.EdgeInsets.only(top: 5), child: pw.Align(alignment: pw.Alignment.centerRight, child: body(rupees(it.budget.totalInr), bold: true))),
                ],
              ),
            ],
          ),
          if (it.budget.budgetMaxInr != null)
            body('Your budget: ${rupees(it.budget.budgetMaxInr!)} (${it.budget.remainingInr! >= 0 ? '${rupees(it.budget.remainingInr!)} left' : '${rupees(-it.budget.remainingInr!)} over'})', color: _grey),

          if (it.audit != null && it.audit!.items.isNotEmpty) ...[
            h1('Accessibility audit'),
            body('Overall: ${it.audit!.overall.label}', bold: true),
            pw.SizedBox(height: 4),
            for (final item in it.audit!.items)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: body('${item.name}: ${item.overall.label}${item.action == null ? '' : ' (${item.action})'}'),
              ),
            for (final a in it.audit!.actionsRequired) body('• $a', color: _grey),
          ],

          if (it.green != null) ...[
            h1('Carbon footprint'),
            body('${fixed(it.green!.co2Kg, 0)} kg CO2 for the whole trip (estimate), eco score ${it.green!.score}/100. ${fixed(it.green!.co2SavedKg, 0)} kg less than the most polluting comparable choices.'),
            for (final tip in it.green!.tips) body('• $tip', color: _grey),
          ],

          if (it.assumptions.isNotEmpty) ...[
            h1('What this plan assumes'),
            for (final a in it.assumptions) body('• $a', color: _grey),
          ],
          if (it.sources.isNotEmpty) ...[
            h1('Sources'),
            for (final s in it.sources.take(30)) body('${s.title}${s.source.isEmpty ? '' : ' (${s.source})'}: ${s.url}', color: _grey),
          ],
        ],
      ),
    );
    return doc.save();
  }

  static String _dur(int minutes) => minutes >= 60 ? '${minutes ~/ 60}h ${minutes % 60}m' : '${minutes}m';

  /// Stand-ins for characters the built-in PDF font cannot print.
  static String plain(String s) => s
      .replaceAll('₹', 'Rs ')
      .replaceAll('★', '*')
      .replaceAll('≈', '~')
      .replaceAll('₂', '2')
      .replaceAll('−', '-')
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('’', "'")
      .replaceAll('…', '...')
      .replaceAll('—', '-')
      .replaceAll('·', '-')
      .replaceAll('•', '-')
      .replaceAll(RegExp(r'[^\x00-\xFF]'), '');
}

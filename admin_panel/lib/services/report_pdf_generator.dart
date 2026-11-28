import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

/// Generates official Daily, Weekly, and Monthly Slaughterhouse Production & Revenue Reports
/// and official Condemnation Slips for Tabaco City Slaughterhouse in crisp black-and-white
/// government form formatting matching the official Tabaco City Abattoir templates.
class ReportPdfGenerator {
  static pw.MemoryImage? _cachedLogo1;
  static pw.MemoryImage? _cachedLogo2;
  static pw.ThemeData? _cachedFontTheme;
  static bool _fontThemeLoaded = false;

  static const double _borderW = 0.6;
  static const PdfColor _borderColor = PdfColors.black;

  // Shared fixed widths for exact pixel-aligned multi-row colspan headers & data rows
  static const double _wNo = 20;
  static const double _wMark = 46;
  static const double _wHead = 25; // x4 = 100
  static const double _wWt = 29; // x4 = 116
  static const double _wFee = 46;

  static Future<pw.ThemeData?> _loadFontTheme() async {
    if (_fontThemeLoaded) return _cachedFontTheme;
    _fontThemeLoaded = true;
    try {
      final regular = await PdfGoogleFonts.notoSansRegular();
      final bold = await PdfGoogleFonts.notoSansBold();
      final italic = await PdfGoogleFonts.notoSansItalic();
      final boldItalic = await PdfGoogleFonts.notoSansBoldItalic();
      _cachedFontTheme = pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        italic: italic,
        boldItalic: boldItalic,
      );
    } catch (_) {
      _cachedFontTheme = null;
    }
    return _cachedFontTheme;
  }

  static Future<void> _loadLogos() async {
    if (_cachedLogo1 == null) {
      try {
        final bytes = await rootBundle.load('assets/images/logo1.png');
        _cachedLogo1 = pw.MemoryImage(bytes.buffer.asUint8List());
      } catch (_) {}
    }
    if (_cachedLogo2 == null) {
      try {
        final bytes = await rootBundle.load('assets/images/logo2.png');
        _cachedLogo2 = pw.MemoryImage(bytes.buffer.asUint8List());
      } catch (_) {}
    }
  }

  static String get _currency => _cachedFontTheme != null ? '\u20b1 ' : 'PHP ';

  /// Main generator method.
  /// [reportSection]: 'all' (Complete Report: Sections 1, 2, & 3 + Summary),
  ///                  'production' (Official Daily/Period Production Report),
  ///                  'health_issues' (Official Condemnation Slip),
  ///                  'uninspected' (Uninspected Registrations Report).
  static Future<Uint8List> generate({
    DateTime? date,
    required List<Map<String, dynamic>> requests,
    String reportType = 'Daily',
    String? periodLabel,
    List<Map<String, dynamic>> healthIssueRequests = const [],
    List<Map<String, dynamic>> uninspectedRequests = const [],
    double? totalRevenue,
    int? totalLivestockProcessed,
    String reportSection = 'all',
  }) async {
    await _loadLogos();
    final logoCity = _cachedLogo1;
    final logoDa = _cachedLogo2 ?? _cachedLogo1;

    final targetDate = date ?? DateTime.now();
    final effectivePeriodLabel = periodLabel ??
        (reportType.toLowerCase().contains('daily')
            ? DateFormat('MMMM d, yyyy').format(targetDate)
            : reportType.toLowerCase().contains('monthly')
                ? DateFormat('MMMM yyyy').format(targetDate)
                : 'Week of ${DateFormat('MMMM d, yyyy').format(targetDate)}');

    final fontTheme = await _loadFontTheme();
    final pdf = pw.Document(theme: fontTheme);

    // Partition requests
    final marketRequests = requests
        .where((r) =>
            (r['request_type']?.toString() ?? '').toLowerCase() != 'barangay')
        .toList();
    final barangayRequests = requests
        .where((r) =>
            (r['request_type']?.toString() ?? '').toLowerCase() == 'barangay')
        .toList();

    // Compute commodity heads, carcass weights, and revenue
    int totalHogs = 0, totalCow = 0, totalCara = 0, totalGoat = 0;
    double totalWeight = 0;
    double computedRevenue = 0;

    for (final r in requests) {
      final type = (r['livestock_type']?.toString() ?? '').toLowerCase();
      final count = int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1;
      final weight = double.tryParse((r['carcass_weight'] ?? 0).toString()) ?? 0;
      totalWeight += weight;

      if (_isGoat(type)) {
        totalGoat += count;
      } else if (_isCow(type)) {
        totalCow += count;
      } else if (_isCara(type)) {
        totalCara += count;
      } else {
        totalHogs += count;
      }

      computedRevenue += _extractFee(r, weight);
    }

    final finalRevenue = totalRevenue ?? computedRevenue;
    final finalProcessedCount = totalLivestockProcessed ??
        (totalHogs + totalCow + totalCara + totalGoat);

    String productionTitle = 'DAILY SLAUGHTERHOUSE PRODUCTION REPORT';
    if (reportType.toLowerCase().contains('weekly')) {
      productionTitle = 'WEEKLY SLAUGHTERHOUSE PRODUCTION REPORT';
    } else if (reportType.toLowerCase().contains('monthly')) {
      productionTitle = 'MONTHLY SLAUGHTERHOUSE PRODUCTION REPORT';
    }

    if (reportSection == 'all') {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.legal,
          margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          build: (pw.Context context) {
            return [
              _buildOfficialHeader(
                logo: logoCity,
                title: productionTitle,
                subtitle: '(Incoming Livestock and Carcass Production)',
                dateLabel: effectivePeriodLabel,
              ),
              pw.SizedBox(height: 10),
              _buildHighlightsSummary(
                revenue: finalRevenue,
                processedCount: finalProcessedCount,
                totalWeight: totalWeight,
                healthIssueCount: healthIssueRequests.length,
                uninspectedCount: uninspectedRequests.length,
              ),
              pw.SizedBox(height: 12),
              _buildSectionTitle('1. PROCESSED LIVESTOCK & CARCASS PRODUCTION (PASSED INSPECTION)'),
              pw.SizedBox(height: 4),
              ..._buildMainTableWidgets(marketRequests, barangayRequests),
              pw.SizedBox(height: 14),
              _buildSectionTitle('2. CASES INVOLVING LIVESTOCK WITH HEALTH ISSUES & CONDEMNATIONS'),
              pw.SizedBox(height: 4),
              _buildHealthIssuesTable(healthIssueRequests),
              pw.SizedBox(height: 14),
              _buildSectionTitle('3. HELD / CONFINED LIVESTOCK — FAILED ANTE-MORTEM (2-DAY OBSERVATION)'),
              pw.SizedBox(height: 4),
              _buildUninspectedTable(uninspectedRequests),
              pw.SizedBox(height: 14),
              _buildSummaryTable(
                hogs: totalHogs,
                cow: totalCow,
                cara: totalCara,
                goat: totalGoat,
                totalWeight: totalWeight,
                totalRevenue: finalRevenue,
              ),
              pw.SizedBox(height: 18),
              _buildSignatures(),
            ];
          },
        ),
      );
    } else if (reportSection == 'production') {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.legal,
          margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          build: (pw.Context context) {
            return [
              _buildOfficialHeader(
                logo: logoCity,
                title: productionTitle,
                subtitle: '(Incoming Livestock and Carcass Production)',
                dateLabel: effectivePeriodLabel,
              ),
              pw.SizedBox(height: 10),
              ..._buildMainTableWidgets(marketRequests, barangayRequests),
              pw.SizedBox(height: 14),
              _buildSummaryTable(
                hogs: totalHogs,
                cow: totalCow,
                cara: totalCara,
                goat: totalGoat,
                totalWeight: totalWeight,
                totalRevenue: finalRevenue,
              ),
              pw.SizedBox(height: 18),
              _buildSignatures(),
            ];
          },
        ),
      );
    } else if (reportSection == 'health_issues') {
      // Exact official CONDEMNATION SLIP format
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          build: (pw.Context context) {
            return _buildCondemnationSlipContent(
              logoLeft: logoDa,
              logoRight: logoCity,
              dateLabel: effectivePeriodLabel,
              timeLabel: DateFormat('h:mm a').format(DateTime.now()),
              healthIssues: healthIssueRequests,
            );
          },
        ),
      );
    } else if (reportSection == 'uninspected') {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.legal,
          margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          build: (pw.Context context) {
            return [
              _buildOfficialHeader(
                logo: logoCity,
                title: 'HELD / CONFINED LIVESTOCK REPORT (FAILED ANTE-MORTEM)',
                subtitle: '(Mandatory 2-Day Observation Hold Awaiting Re-Evaluation)',
                dateLabel: effectivePeriodLabel,
              ),
              pw.SizedBox(height: 12),
              _buildUninspectedTable(uninspectedRequests),
              pw.SizedBox(height: 18),
              _buildSignatures(),
            ];
          },
        ),
      );
    }

    return pdf.save();
  }

  // ═══════════════════════════════════════════════════════════════
  //  OFFICIAL HEADER (PURE BLACK & WHITE, CENTERED)
  // ═══════════════════════════════════════════════════════════════
  static pw.Widget _buildOfficialHeader({
    required pw.MemoryImage? logo,
    required String title,
    required String subtitle,
    required String dateLabel,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logo != null)
              pw.Container(width: 44, height: 44, child: pw.Image(logo))
            else
              pw.SizedBox(width: 44, height: 44),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('Republic of the Philippines', style: const pw.TextStyle(fontSize: 8.5)),
                  pw.Text('Province of Albay', style: const pw.TextStyle(fontSize: 8.5)),
                  pw.Text('City of Tabaco', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text('OFFICE OF THE CITY VETERINARIAN & CITY SLAUGHTERHOUSE',
                      style: const pw.TextStyle(fontSize: 7.5)),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    title,
                    style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.Text(
                    subtitle,
                    style: const pw.TextStyle(fontSize: 8),
                    textAlign: pw.TextAlign.center,
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 44, height: 44),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Text('Date: ', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 1, left: 4, right: 4),
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: _borderColor, width: 0.6)),
              ),
              child: pw.Text(dateLabel, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  TOP HIGHLIGHTS SUMMARY (CRISP BLACK & WHITE)
  // ═══════════════════════════════════════════════════════════════
  static pw.Widget _buildHighlightsSummary({
    required double revenue,
    required int processedCount,
    required double totalWeight,
    required int healthIssueCount,
    required int uninspectedCount,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: _borderColor, width: _borderW),
      children: [
        pw.TableRow(
          children: [
            _summaryBoxCell('TOTAL REVENUE', '$_currency${NumberFormat('#,##0.00').format(revenue)}'),
            _summaryBoxCell('LIVESTOCK PROCESSED', '$processedCount Heads'),
            _summaryBoxCell('TOTAL CARCASS WEIGHT', '${totalWeight.toStringAsFixed(1)} kg'),
            _summaryBoxCell('HEALTH ISSUES / CONDEMNED', '$healthIssueCount Cases'),
            _summaryBoxCell('HELD / CONFINED (2-DAY)', '$uninspectedCount Cases'),
          ],
        ),
      ],
    );
  }

  static pw.Widget _summaryBoxCell(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 6), textAlign: pw.TextAlign.center),
          pw.SizedBox(height: 2),
          pw.Text(value, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
        ],
      ),
    );
  }

  static pw.Widget _buildSectionTitle(String title) {
    return pw.Text(
      title,
      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  SECTION 1: PROCESSED LIVESTOCK TABLE WITH TRUE MERGED HEADERS
  // ═══════════════════════════════════════════════════════════════
  static List<pw.Widget> _buildMainTableWidgets(
    List<Map<String, dynamic>> marketRequests,
    List<Map<String, dynamic>> barangayRequests,
  ) {
    final headerStyle = pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold);
    final subHeaderStyle = pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold);
    const cellStyle = pw.TextStyle(fontSize: 6.5);
    final sectionStyle = pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold);

    final widgets = <pw.Widget>[];

    // 1. TRUE MERGED MULTI-ROW HEADER BAND (Zero broken vertical wrapping)
    widgets.add(
      pw.Container(
        height: 30,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _borderColor, width: _borderW),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _headerColBox('No.', _wNo, headerStyle, rightBorder: true),
            pw.Expanded(
              flex: 26,
              child: _headerFlexBox('Name of Owner', headerStyle, rightBorder: true),
            ),
            _headerColBox('Markings', _wMark, headerStyle, rightBorder: true),
            // Merged super-header: No. of Heads (spans 4 sub-columns)
            pw.Container(
              width: _wHead * 4,
              decoration: const pw.BoxDecoration(
                border: pw.Border(right: pw.BorderSide(color: _borderColor, width: _borderW)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Expanded(
                    child: pw.Container(
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide(color: _borderColor, width: _borderW)),
                      ),
                      child: pw.Center(
                        child: pw.Text('No. of Heads', style: headerStyle, textAlign: pw.TextAlign.center),
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        _subColCell('Hogs', _wHead, subHeaderStyle, rightBorder: true),
                        _subColCell('Cow', _wHead, subHeaderStyle, rightBorder: true),
                        _subColCell('Cara', _wHead, subHeaderStyle, rightBorder: true),
                        _subColCell('Goat', _wHead, subHeaderStyle, rightBorder: false),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Merged super-header: Carcass Weight (Kgs) (spans 4 sub-columns)
            pw.Container(
              width: _wWt * 4,
              decoration: const pw.BoxDecoration(
                border: pw.Border(right: pw.BorderSide(color: _borderColor, width: _borderW)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Expanded(
                    child: pw.Container(
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide(color: _borderColor, width: _borderW)),
                      ),
                      child: pw.Center(
                        child: pw.Text('Carcass Weight (Kgs)', style: headerStyle, textAlign: pw.TextAlign.center),
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        _subColCell('Hogs', _wWt, subHeaderStyle, rightBorder: true),
                        _subColCell('Cow', _wWt, subHeaderStyle, rightBorder: true),
                        _subColCell('Cara', _wWt, subHeaderStyle, rightBorder: true),
                        _subColCell('Goat', _wWt, subHeaderStyle, rightBorder: false),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _headerColBox('Fees\n(PHP)', _wFee, headerStyle, rightBorder: true),
            pw.Expanded(
              flex: 16,
              child: _headerFlexBox('Remarks', headerStyle, rightBorder: false),
            ),
          ],
        ),
      ),
    );

    // 2. FULL-WIDTH MARKET SECTION BANNER + DATA TABLE
    widgets.add(_fullWidthSectionBanner('MARKET SECTION', sectionStyle));

    if (marketRequests.isEmpty) {
      widgets.add(_fullWidthEmptyRow('No market transactions for this period'));
    } else {
      widgets.add(_buildDataRowsTable(marketRequests, cellStyle));
    }

    // 3. FULL-WIDTH BARANGAY BANNER + DATA TABLE
    widgets.add(_fullWidthSectionBanner('BARANGAY', sectionStyle));

    if (barangayRequests.isEmpty) {
      widgets.add(_fullWidthEmptyRow('No barangay transactions for this period'));
    } else {
      widgets.add(_buildDataRowsTable(barangayRequests, cellStyle));
    }

    return widgets;
  }

  static pw.Widget _headerColBox(String text, double width, pw.TextStyle style, {required bool rightBorder}) {
    return pw.Container(
      width: width,
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      decoration: pw.BoxDecoration(
        border: rightBorder ? const pw.Border(right: pw.BorderSide(color: _borderColor, width: _borderW)) : null,
      ),
      child: pw.Center(child: pw.Text(text, style: style, textAlign: pw.TextAlign.center)),
    );
  }

  static pw.Widget _headerFlexBox(String text, pw.TextStyle style, {required bool rightBorder}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      decoration: pw.BoxDecoration(
        border: rightBorder ? const pw.Border(right: pw.BorderSide(color: _borderColor, width: _borderW)) : null,
      ),
      child: pw.Center(child: pw.Text(text, style: style, textAlign: pw.TextAlign.center)),
    );
  }

  static pw.Widget _subColCell(String text, double width, pw.TextStyle style, {required bool rightBorder}) {
    return pw.Container(
      width: width,
      padding: const pw.EdgeInsets.symmetric(vertical: 2.5, horizontal: 1),
      decoration: pw.BoxDecoration(
        border: rightBorder ? const pw.Border(right: pw.BorderSide(color: _borderColor, width: _borderW)) : null,
      ),
      child: pw.Center(child: pw.Text(text, style: style, textAlign: pw.TextAlign.center)),
    );
  }

  static pw.Widget _fullWidthSectionBanner(String label, pw.TextStyle style) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 3.5, horizontal: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          left: pw.BorderSide(color: _borderColor, width: _borderW),
          right: pw.BorderSide(color: _borderColor, width: _borderW),
          bottom: pw.BorderSide(color: _borderColor, width: _borderW),
        ),
      ),
      child: pw.Text(label, style: style),
    );
  }

  static pw.Widget _fullWidthEmptyRow(String text) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          left: pw.BorderSide(color: _borderColor, width: _borderW),
          right: pw.BorderSide(color: _borderColor, width: _borderW),
          bottom: pw.BorderSide(color: _borderColor, width: _borderW),
        ),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 6.5, fontStyle: pw.FontStyle.italic),
      ),
    );
  }

  static pw.Widget _buildDataRowsTable(List<Map<String, dynamic>> list, pw.TextStyle style) {
    final rows = <pw.TableRow>[];
    for (int i = 0; i < list.length; i++) {
      final req = list[i];
      final name = req['customer_name']?.toString() ?? '\u2014';
      final markings = (req['marking'] ?? req['customer_marking'] ?? '').toString();
      final livestockType = (req['livestock_type']?.toString() ?? '').toLowerCase();
      final animalCount = int.tryParse((req['animal_count'] ?? 1).toString()) ?? 1;
      final carcassWeight = double.tryParse((req['carcass_weight'] ?? 0).toString()) ?? 0;

      String hogsHeads = '', cowHeads = '', caraHeads = '', goatHeads = '';
      String hogsWeight = '', cowWeight = '', caraWeight = '', goatWeight = '';

      if (_isGoat(livestockType)) {
        goatHeads = animalCount.toString();
        if (carcassWeight > 0) goatWeight = carcassWeight.toStringAsFixed(1);
      } else if (_isCow(livestockType)) {
        cowHeads = animalCount.toString();
        if (carcassWeight > 0) cowWeight = carcassWeight.toStringAsFixed(1);
      } else if (_isCara(livestockType)) {
        caraHeads = animalCount.toString();
        if (carcassWeight > 0) caraWeight = carcassWeight.toStringAsFixed(1);
      } else {
        hogsHeads = animalCount.toString();
        if (carcassWeight > 0) hogsWeight = carcassWeight.toStringAsFixed(1);
      }

      final fee = _extractFee(req, carcassWeight);
      final feeStr = fee > 0 ? NumberFormat('#,##0.00').format(fee) : '\u2014';
      final remarks = _sanitizeNotes(req['process_notes']?.toString() ?? '');

      rows.add(
        pw.TableRow(
          children: [
            _tableCellCenter('${i + 1}', style),
            _tableCell(name, style),
            _tableCellCenter(markings, style),
            _tableCellCenter(hogsHeads, style),
            _tableCellCenter(cowHeads, style),
            _tableCellCenter(caraHeads, style),
            _tableCellCenter(goatHeads, style),
            _tableCellCenter(hogsWeight, style),
            _tableCellCenter(cowWeight, style),
            _tableCellCenter(caraWeight, style),
            _tableCellCenter(goatWeight, style),
            _tableCellCenter(feeStr, style),
            _tableCell(remarks, style),
          ],
        ),
      );
    }

    return pw.Table(
      border: const pw.TableBorder(
        left: pw.BorderSide(color: _borderColor, width: _borderW),
        right: pw.BorderSide(color: _borderColor, width: _borderW),
        bottom: pw.BorderSide(color: _borderColor, width: _borderW),
        horizontalInside: pw.BorderSide(color: _borderColor, width: _borderW),
        verticalInside: pw.BorderSide(color: _borderColor, width: _borderW),
      ),
      columnWidths: const {
        0: pw.FixedColumnWidth(_wNo),
        1: pw.FlexColumnWidth(26),
        2: pw.FixedColumnWidth(_wMark),
        3: pw.FixedColumnWidth(_wHead),
        4: pw.FixedColumnWidth(_wHead),
        5: pw.FixedColumnWidth(_wHead),
        6: pw.FixedColumnWidth(_wHead),
        7: pw.FixedColumnWidth(_wWt),
        8: pw.FixedColumnWidth(_wWt),
        9: pw.FixedColumnWidth(_wWt),
        10: pw.FixedColumnWidth(_wWt),
        11: pw.FixedColumnWidth(_wFee),
        12: pw.FlexColumnWidth(16),
      },
      children: rows,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  OFFICIAL CONDEMNATION SLIP (EXACT TEMPLATE MATCH)
  // ═══════════════════════════════════════════════════════════════
  static List<pw.Widget> _buildCondemnationSlipContent({
    required pw.MemoryImage? logoLeft,
    required pw.MemoryImage? logoRight,
    required String dateLabel,
    required String timeLabel,
    required List<Map<String, dynamic>> healthIssues,
  }) {
    final headerStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
    const bodyStyle = pw.TextStyle(fontSize: 8.5, lineSpacing: 2.5);
    const cellStyle = pw.TextStyle(fontSize: 8);

    // Build table rows (minimum 3 rows so blank lines remain printable like the official slip)
    final tableRows = <pw.TableRow>[
      pw.TableRow(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: pw.Text(
              'FOOD ANIMAL/MEAT/MEAT\nPRODUCTS/PROCESSED MEAT',
              style: headerStyle,
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: pw.Center(child: pw.Text('QUANTITY/WEIGHT', style: headerStyle)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: pw.Center(child: pw.Text('CAUSE OF CONDEMNATION', style: headerStyle)),
          ),
        ],
      ),
    ];

    for (final req in healthIssues) {
      final species = (req['livestock_type'] ?? 'Livestock').toString();
      final owner = (req['customer_name'] ?? '').toString().trim();
      final itemText = owner.isNotEmpty ? '$species ($owner)' : species;
      final heads = int.tryParse((req['animal_count'] ?? 1).toString()) ?? 1;
      final wt = double.tryParse((req['carcass_weight'] ?? 0).toString()) ?? 0;
      final qtyText = wt > 0
          ? '$heads ${heads == 1 ? "head" : "heads"} / ${wt.toStringAsFixed(1)} kg'
          : '$heads ${heads == 1 ? "head" : "heads"}';
      final cause = _sanitizeNotes(
        (req['condemnation_reason'] ??
                req['veterinary_findings'] ??
                req['process_notes'] ??
                'Failed veterinary inspection')
            .toString(),
        fallback: 'Did not meet sanitary & inspection standards',
      );

      tableRows.add(
        pw.TableRow(
          children: [
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(itemText, style: cellStyle)),
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Center(child: pw.Text(qtyText, style: cellStyle))),
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(cause, style: cellStyle)),
          ],
        ),
      );
    }

    // Pad to at least 3 data rows like the official printed slip
    final padCount = healthIssues.length < 3 ? 3 - healthIssues.length : 0;
    for (int i = 0; i < padCount; i++) {
      tableRows.add(
        pw.TableRow(
          children: [
            pw.SizedBox(height: 22),
            pw.SizedBox(height: 22),
            pw.SizedBox(height: 22),
          ],
        ),
      );
    }

    return [
      // Dual-logo header
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (logoLeft != null)
            pw.Container(width: 48, height: 48, child: pw.Image(logoLeft))
          else
            pw.SizedBox(width: 48, height: 48),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('Republic of the Philippines', style: const pw.TextStyle(fontSize: 9)),
                pw.Text('Province of Albay', style: const pw.TextStyle(fontSize: 9)),
                pw.Text('CITY OF TABACO', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          if (logoRight != null)
            pw.Container(width: 48, height: 48, child: pw.Image(logoRight))
          else
            pw.SizedBox(width: 48, height: 48),
        ],
      ),
      pw.SizedBox(height: 22),

      // Underlined establishment lines
      _underlinedFieldRow('Name of Establishment:', 'Tabaco City Slaughterhouse'),
      pw.SizedBox(height: 6),
      pw.Row(
        children: [
          pw.Expanded(child: _underlinedFieldRow('City:', 'Tabaco City')),
          pw.SizedBox(width: 36),
          pw.Expanded(child: _underlinedFieldRow('Province:', 'Albay')),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Row(
        children: [
          pw.Expanded(child: _underlinedFieldRow('Date:', dateLabel)),
          pw.SizedBox(width: 36),
          pw.Expanded(child: _underlinedFieldRow('Time:', timeLabel)),
        ],
      ),
      pw.SizedBox(height: 20),

      // Title
      pw.Center(
        child: pw.Text(
          'CONDEMNATION SLIP',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.SizedBox(height: 10),

      // Legal citation paragraph
      pw.Text(
        '    Pursuant to Republic Act No. 7394, otherwise known as the "Consumer Act of the Philippines" under Articles 10 and 17; and Republic Act No. 9296, "The Meat Inspection Code of the Philippines," and the Department of Agriculture Administrative Order No. 7, Rules and Regulations of RA 9296 series of 2005; and NMIS Administrative Order No. 6, the following meat/meat products/processed meat is hereby condemned.',
        style: bodyStyle,
        textAlign: pw.TextAlign.justify,
      ),
      pw.SizedBox(height: 14),

      // 3-Column Condemnation Table
      pw.Table(
        border: pw.TableBorder.all(color: _borderColor, width: _borderW),
        columnWidths: const {
          0: pw.FlexColumnWidth(1.3),
          1: pw.FlexColumnWidth(1.0),
          2: pw.FlexColumnWidth(1.4),
        },
        children: tableRows,
      ),
      pw.SizedBox(height: 26),

      // 2x2 Official Signatory Grid
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: _condemnationSignatureBlock(
              'Condemned by:',
              'Veterinarian/Meat Control Officer/Meat Inspector',
              '(Signature Over Printed Name)',
            ),
          ),
          pw.SizedBox(width: 40),
          pw.Expanded(
            child: _condemnationSignatureBlock(
              'Conforme:',
              'Name of Owner/Representative',
              '(Signature Over Printed Name)',
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 26),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: _condemnationSignatureBlock(
              'Disposed by:',
              'Veterinarian/Meat Control Officer/Meat Inspector',
              '(Signature Over Printed Name)',
            ),
          ),
          pw.SizedBox(width: 40),
          pw.Expanded(
            child: _condemnationSignatureBlock(
              'Witness:',
              '',
              '(Signature Over Printed Name)',
            ),
          ),
        ],
      ),
    ];
  }

  static pw.Widget _underlinedFieldRow(String label, String value) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 8.5)),
        pw.SizedBox(width: 6),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 1, left: 4),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: _borderColor, width: 0.6)),
            ),
            child: pw.Text(value, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  static pw.Widget _condemnationSignatureBlock(String heading, String roleLine, String subLine) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(heading, style: const pw.TextStyle(fontSize: 8.5)),
        pw.SizedBox(height: 22),
        pw.Container(
          width: double.infinity,
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _borderColor, width: 0.6)),
          ),
        ),
        pw.SizedBox(height: 3),
        if (roleLine.isNotEmpty)
          pw.Center(
            child: pw.Text(roleLine, style: const pw.TextStyle(fontSize: 7.5), textAlign: pw.TextAlign.center),
          ),
        pw.Center(
          child: pw.Text(subLine, style: const pw.TextStyle(fontSize: 7.5), textAlign: pw.TextAlign.center),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  SECTION 2 TABLE (USED INSIDE FULL REPORT, BLACK & WHITE)
  // ═══════════════════════════════════════════════════════════════
  static pw.Widget _buildHealthIssuesTable(List<Map<String, dynamic>> healthIssues) {
    final headerStyle = pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold);
    const cellStyle = pw.TextStyle(fontSize: 6.5);

    if (healthIssues.isEmpty) {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _borderColor, width: _borderW),
        ),
        child: pw.Center(
          child: pw.Text(
            'No health issues or condemnations reported during this period.',
            style: pw.TextStyle(fontSize: 6.5, fontStyle: pw.FontStyle.italic),
          ),
        ),
      );
    }

    final rows = <pw.TableRow>[
      pw.TableRow(
        children: [
          _tableCellCenter('No.', headerStyle),
          _tableCell('Reference No.', headerStyle),
          _tableCell('Customer Name', headerStyle),
          _tableCellCenter('Livestock / Heads', headerStyle),
          _tableCellCenter('Inspection Stage', headerStyle),
          _tableCell('Veterinary Findings / Cause', headerStyle),
          _tableCellCenter('Disposition', headerStyle),
        ],
      ),
    ];

    for (int i = 0; i < healthIssues.length; i++) {
      final req = healthIssues[i];
      final id = req['id']?.toString() ?? '';
      final ref = req['reference_no']?.toString() ?? 'MI-${DateTime.now().year}-${id.padLeft(3, '0')}';
      final name = req['customer_name']?.toString() ?? '\u2014';
      final livestock = '${req['livestock_type'] ?? 'Unknown'} (${req['animal_count'] ?? 1} head)';

      final anti = (req['anti_mortem'] ?? '').toString();
      final post = (req['post_mortem'] ?? '').toString();
      final status = (req['status'] ?? '').toString();

      String stage = 'Ante-Mortem';
      String disposition = 'Taken Back';
      if (post == 'Failed' || status == 'condemned' || status == 'post_mortem_failed') {
        stage = 'Post-Mortem';
        disposition = 'Carcass Condemned';
      } else if (anti == 'Failed' || status == 'anti_mortem_failed' || status == 'taken_back') {
        stage = 'Ante-Mortem';
        disposition = 'Rejected / Taken Back';
      }

      final findings = _sanitizeNotes(
        (req['veterinary_findings'] ?? req['condemnation_reason'] ?? req['process_notes'] ?? '').toString(),
        fallback: 'Did not meet sanitary & inspection standards',
      );

      rows.add(
        pw.TableRow(
          children: [
            _tableCellCenter('${i + 1}', cellStyle),
            _tableCell(ref, cellStyle),
            _tableCell(name, cellStyle),
            _tableCellCenter(livestock, cellStyle),
            _tableCellCenter(stage, cellStyle),
            _tableCell(findings, cellStyle),
            _tableCellCenter(disposition, cellStyle),
          ],
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(width: _borderW, color: _borderColor),
      columnWidths: const {
        0: pw.FixedColumnWidth(20),
        1: pw.FixedColumnWidth(64),
        2: pw.FlexColumnWidth(2.2),
        3: pw.FlexColumnWidth(1.8),
        4: pw.FlexColumnWidth(1.5),
        5: pw.FlexColumnWidth(3.2),
        6: pw.FlexColumnWidth(1.8),
      },
      children: rows,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  SECTION 3: HELD / CONFINED LIVESTOCK — FAILED ANTE-MORTEM (B&W)
  // ═══════════════════════════════════════════════════════════════
  static pw.Widget _buildUninspectedTable(List<Map<String, dynamic>> uninspected) {
    final headerStyle = pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold);
    const cellStyle = pw.TextStyle(fontSize: 6.5);

    if (uninspected.isEmpty) {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _borderColor, width: _borderW),
        ),
        child: pw.Center(
          child: pw.Text(
            'No livestock currently held or confined from ante-mortem inspection during this period.',
            style: pw.TextStyle(fontSize: 6.5, fontStyle: pw.FontStyle.italic),
          ),
        ),
      );
    }

    final rows = <pw.TableRow>[
      pw.TableRow(
        children: [
          _tableCellCenter('No.', headerStyle),
          _tableCell('Reference No.', headerStyle),
          _tableCell('Customer Name', headerStyle),
          _tableCellCenter('Livestock / Heads', headerStyle),
          _tableCellCenter('Date Held', headerStyle),
          _tableCellCenter('Hold Status', headerStyle),
          _tableCell('Ante-Mortem Findings / Remarks', headerStyle),
        ],
      ),
    ];

    for (int i = 0; i < uninspected.length; i++) {
      final req = uninspected[i];
      final id = req['id']?.toString() ?? '';
      final ref = req['reference_no']?.toString() ?? 'MI-${DateTime.now().year}-${id.padLeft(3, '0')}';
      final name = req['customer_name']?.toString() ?? '\u2014';
      final livestock = '${req['livestock_type'] ?? 'Unknown'} (${req['animal_count'] ?? 1} head)';
      final sched = req['inspection_created_at']?.toString() ?? req['preferred_date']?.toString() ?? req['created_at']?.toString() ?? '\u2014';
      final findings = _sanitizeNotes(
        (req['veterinary_findings'] ?? req['process_notes'] ?? '').toString(),
        fallback: 'Failed ante-mortem — held under mandatory 2-day confinement for re-evaluation',
      );

      rows.add(
        pw.TableRow(
          children: [
            _tableCellCenter('${i + 1}', cellStyle),
            _tableCell(ref, cellStyle),
            _tableCell(name, cellStyle),
            _tableCellCenter(livestock, cellStyle),
            _tableCellCenter(sched.length > 10 ? sched.substring(0, 10) : sched, cellStyle),
            _tableCellCenter('CONFINED (2-DAY HOLD)', cellStyle),
            _tableCell(findings, cellStyle),
          ],
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(width: _borderW, color: _borderColor),
      columnWidths: const {
        0: pw.FixedColumnWidth(20),
        1: pw.FixedColumnWidth(64),
        2: pw.FlexColumnWidth(2.4),
        3: pw.FlexColumnWidth(1.8),
        4: pw.FlexColumnWidth(1.6),
        5: pw.FlexColumnWidth(1.8),
        6: pw.FlexColumnWidth(3.2),
      },
      children: rows,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  ANIMAL COMMODITIES SLAUGHTERED SUMMARY TABLE (BLACK & WHITE)
  // ═══════════════════════════════════════════════════════════════
  static pw.Widget _buildSummaryTable({
    required int hogs,
    required int cow,
    required int cara,
    required int goat,
    required double totalWeight,
    required double totalRevenue,
  }) {
    final style = pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold);
    final totalHeads = hogs + cow + cara + goat;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text('ANIMAL COMMODITIES SLAUGHTERED', style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(width: _borderW, color: _borderColor),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.0),
            1: pw.FlexColumnWidth(1.0),
            2: pw.FlexColumnWidth(1.0),
            3: pw.FlexColumnWidth(1.0),
            4: pw.FlexColumnWidth(1.2),
            5: pw.FlexColumnWidth(1.4),
            6: pw.FlexColumnWidth(1.6),
          },
          children: [
            pw.TableRow(
              children: [
                _tableCellCenter('HOGS', style),
                _tableCellCenter('COW', style),
                _tableCellCenter('CARABAO', style),
                _tableCellCenter('GOAT', style),
                _tableCellCenter('TOTAL HEADS', style),
                _tableCellCenter('TOTAL WEIGHT', style),
                _tableCellCenter('TOTAL REVENUE', style),
              ],
            ),
            pw.TableRow(
              children: [
                _tableCellCenter(hogs.toString(), style),
                _tableCellCenter(cow.toString(), style),
                _tableCellCenter(cara.toString(), style),
                _tableCellCenter(goat.toString(), style),
                _tableCellCenter('$totalHeads Heads', style),
                _tableCellCenter('${totalWeight.toStringAsFixed(1)} kg', style),
                _tableCellCenter('$_currency${NumberFormat('#,##0.00').format(totalRevenue)}', style),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  OFFICIAL SIGNATURES (EXACT TABACO CITY FORM TITLES)
  // ═══════════════════════════════════════════════════════════════
  static pw.Widget _buildSignatures() {
    final labelStyle = pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold);
    final nameStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, decoration: pw.TextDecoration.underline);
    const titleStyle = pw.TextStyle(fontSize: 6.5);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text('LIVESTOCK RECORDERS ON DUTY:', style: labelStyle),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.start,
          children: [
            pw.SizedBox(width: 24),
            pw.Text('FERNANDO BALINGBING', style: nameStyle),
            pw.SizedBox(width: 70),
            pw.Text('ERWIN BIEN', style: nameStyle),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text('MEAT INSPECTORS ON DUTY:', style: labelStyle),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.start,
          children: [
            pw.SizedBox(width: 24),
            pw.Text('MELCHOR VARGAS', style: nameStyle),
            pw.SizedBox(width: 70),
            pw.Text('RODEL B. BALINGBING', style: nameStyle),
            pw.SizedBox(width: 70),
            pw.Text('HENRY GASCON', style: nameStyle),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text('CERTIFIED AND VALIDATED BY:', style: labelStyle),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.start,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: 24),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('JOSE ERNESTO ROS', style: nameStyle),
                pw.Text('Slaughterhouse Designate', style: titleStyle),
              ],
            ),
            pw.SizedBox(width: 48),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('JONEL P. ARCOS', style: nameStyle),
                pw.Text('Slaughterhouse Master 1', style: titleStyle),
              ],
            ),
            pw.SizedBox(width: 48),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('KIM RONAN ROMERO, DVM', style: nameStyle),
                pw.Text('OIC-City Veterinarian', style: titleStyle),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════════════════
  static double _extractFee(Map<String, dynamic> req, double weight) {
    double fee = 0;
    final payment = req['payment'] as Map<String, dynamic>?;
    if (payment != null) {
      fee = double.tryParse((payment['total_amount'] ?? payment['amount'] ?? 0).toString()) ?? 0;
    }
    if (fee == 0) {
      fee = double.tryParse((req['total_amount'] ?? req['total_fee'] ?? 0).toString()) ?? 0;
    }
    if (fee == 0 && weight > 0) {
      fee = (weight * 5.0) + 250.0;
    }
    return fee;
  }

  static String _sanitizeNotes(String raw, {String fallback = 'Passed Inspection'}) {
    final cleaned = raw
        .replaceAll(RegExp(r'\[AM_PASSED_AT:[^\]]+\]\s*\|?\s*'), '')
        .replaceAll(RegExp(r'\[PHONE:[^\]]+\]\s*\|?\s*'), '')
        .trim();
    if (cleaned.isEmpty || cleaned.toLowerCase() == 'null') {
      return fallback;
    }
    return cleaned;
  }

  static bool _isGoat(String t) =>
      t.contains('goat') || t.contains('sheep') || t.contains('caprine') || t.contains('kambing');

  static bool _isCow(String t) =>
      t.contains('cow') || t.contains('cattle') || t.contains('bovine') || t.contains('baka');

  static bool _isCara(String t) =>
      t.contains('cara') || t.contains('carabao') || t.contains('buffalo') || t.contains('kalabaw');

  static pw.Widget _tableCell(String text, pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      child: pw.Text(text, style: style),
    );
  }

  static pw.Widget _tableCellCenter(String text, pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 3),
      child: pw.Center(child: pw.Text(text, style: style, textAlign: pw.TextAlign.center)),
    );
  }
}

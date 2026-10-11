import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

/// Generates official Daily, Weekly, and Monthly Slaughterhouse Production & Revenue Reports
/// for Tabaco City Slaughterhouse in a single comprehensive PDF containing:
/// - Top KPI Summary: Total Revenue, Livestock Processed, Carcass Weight, Health Issues, Uninspected
/// - Section 1: Processed Livestock & Carcass Production (Passed Inspection) with HOG, COW, CARA, GOAT, POULTRY columns & Fees
/// - Section 2: Cases Involving Livestock with Health Issues & Condemnations (listed separately)
/// - Section 3: Cases Involving Livestock That Did Not Undergo Inspection (listed separately)
/// - Animal Commodities & Revenue Summary Table
/// - Official Signatures
class ReportPdfGenerator {
  static pw.MemoryImage? _cachedLogo;

  /// Main generator method.
  /// [reportSection]: 'all' (default, single PDF with Sections 1, 2, & 3 + Revenue),
  ///                  'production', 'health_issues', or 'uninspected'.
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
    // Load logo if available
    if (_cachedLogo == null) {
      try {
        final logoBytes = await rootBundle.load('assets/images/logo1.png');
        _cachedLogo = pw.MemoryImage(logoBytes.buffer.asUint8List());
      } catch (_) {}
    }
    final logoImage = _cachedLogo;

    final targetDate = date ?? DateTime.now();
    final effectivePeriodLabel = periodLabel ??
        (reportType.toLowerCase().contains('daily')
            ? DateFormat('MMMM d, yyyy').format(targetDate)
            : reportType.toLowerCase().contains('monthly')
                ? DateFormat('MMMM yyyy').format(targetDate)
                : 'Week of ${DateFormat('MMMM d, yyyy').format(targetDate)}');

    final pdf = pw.Document();

    // Partition requests
    final marketRequests = requests
        .where((r) =>
            (r['request_type']?.toString() ?? '').toLowerCase() != 'barangay')
        .toList();
    final barangayRequests = requests
        .where((r) =>
            (r['request_type']?.toString() ?? '').toLowerCase() == 'barangay')
        .toList();

    // Accurately compute commodity heads and carcass weights across all 5 livestock types
    int totalHogs = 0, totalCow = 0, totalCara = 0, totalGoat = 0, totalPoultry = 0;
    double totalWeight = 0;
    double computedRevenue = 0;

    for (var r in requests) {
      final type = (r['livestock_type']?.toString() ?? '').toLowerCase();
      final count = int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1;
      final weight = double.tryParse((r['carcass_weight'] ?? 0).toString()) ?? 0;
      totalWeight += weight;

      if (_isGoat(type)) {
        totalGoat += count;
      } else if (_isPoultry(type)) {
        totalPoultry += count;
      } else if (_isCow(type)) {
        totalCow += count;
      } else if (_isCara(type)) {
        totalCara += count;
      } else if (_isHog(type)) {
        totalHogs += count;
      } else {
        totalHogs += count;
      }

      // Compute revenue
      final payment = r['payment'] as Map<String, dynamic>?;
      if (payment != null) {
        final amt = double.tryParse((payment['total_amount'] ?? payment['amount'] ?? 0).toString()) ?? 0;
        if (amt > 0) {
          computedRevenue += amt;
        } else if (weight > 0) {
          computedRevenue += (weight * 5.0) + 250.0;
        }
      } else {
        final reqAmt = double.tryParse((r['total_amount'] ?? r['total_fee'] ?? 0).toString()) ?? 0;
        if (reqAmt > 0) {
          computedRevenue += reqAmt;
        } else if (weight > 0) {
          computedRevenue += (weight * 5.0) + 250.0;
        }
      }
    }

    final finalRevenue = totalRevenue ?? computedRevenue;
    final finalProcessedCount = totalLivestockProcessed ??
        (totalHogs + totalCow + totalCara + totalGoat + totalPoultry);

    String mainTitle = 'DAILY SLAUGHTERHOUSE PRODUCTION & REVENUE REPORT';
    if (reportType.toLowerCase().contains('weekly')) {
      mainTitle = 'WEEKLY SLAUGHTERHOUSE PRODUCTION & REVENUE REPORT';
    } else if (reportType.toLowerCase().contains('monthly')) {
      mainTitle = 'MONTHLY SLAUGHTERHOUSE PRODUCTION & REVENUE REPORT';
    }

    if (reportSection == 'all') {
      // ═══════════════════════════════════════════════════════════════
      // SINGLE COMPREHENSIVE PDF:
      // Includes Total Revenue, Livestock Processed, and Sections 1, 2, & 3
      // ═══════════════════════════════════════════════════════════════
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.legal,
          margin: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          build: (pw.Context context) {
            return [
              _buildHeader(logoImage, mainTitle, effectivePeriodLabel),
              pw.SizedBox(height: 10),
              _buildHighlightsSummary(
                revenue: finalRevenue,
                processedCount: finalProcessedCount,
                totalWeight: totalWeight,
                healthIssueCount: healthIssueRequests.length,
                uninspectedCount: uninspectedRequests.length,
              ),
              pw.SizedBox(height: 14),
              _buildSectionHeader('1. PROCESSED LIVESTOCK & CARCASS PRODUCTION (PASSED INSPECTION)'),
              pw.SizedBox(height: 6),
              _buildMainTable(marketRequests, barangayRequests),
              pw.SizedBox(height: 16),
              _buildSectionHeader('2. CASES INVOLVING LIVESTOCK WITH HEALTH ISSUES & CONDEMNATIONS (LISTED SEPARATELY)'),
              pw.SizedBox(height: 6),
              _buildHealthIssuesTable(healthIssueRequests),
              pw.SizedBox(height: 16),
              _buildSectionHeader('3. CASES INVOLVING LIVESTOCK THAT DID NOT UNDERGO INSPECTION (LISTED SEPARATELY)'),
              pw.SizedBox(height: 6),
              _buildUninspectedTable(uninspectedRequests),
              pw.SizedBox(height: 14),
              _buildSummaryTable(
                hogs: totalHogs,
                cow: totalCow,
                cara: totalCara,
                goat: totalGoat,
                poultry: totalPoultry,
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
      // Production section only
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.legal,
          margin: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          build: (pw.Context context) {
            return [
              _buildHeader(logoImage, 'DAILY SLAUGHTERHOUSE PRODUCTION REPORT', effectivePeriodLabel,
                  subtitle: '(Incoming Livestock and Carcass Production)'),
              pw.SizedBox(height: 12),
              _buildMainTable(marketRequests, barangayRequests),
              pw.SizedBox(height: 14),
              _buildSummaryTable(
                hogs: totalHogs,
                cow: totalCow,
                cara: totalCara,
                goat: totalGoat,
                poultry: totalPoultry,
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
      // Health issues section only
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.legal,
          margin: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          build: (pw.Context context) {
            return [
              _buildHeader(logoImage, 'LIVESTOCK HEALTH ISSUES & CONDEMNATIONS REPORT', effectivePeriodLabel,
                  subtitle: '(Ante-Mortem Rejections, Pathology Detected, and Post-Mortem Condemnations)'),
              pw.SizedBox(height: 12),
              _buildHealthIssuesTable(healthIssueRequests),
              pw.SizedBox(height: 18),
              _buildSignatures(),
            ];
          },
        ),
      );
    } else if (reportSection == 'uninspected') {
      // Uninspected section only
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.legal,
          margin: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          build: (pw.Context context) {
            return [
              _buildHeader(logoImage, 'UNINSPECTED LIVESTOCK REGISTRATION REPORT', effectivePeriodLabel,
                  subtitle: '(Cancelled, Withdrawn, and Non-Presented Registrations)'),
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
  //  HEADER
  // ═══════════════════════════════════════════════════════════════
  static pw.Widget _buildHeader(
    pw.MemoryImage? logo,
    String title,
    String periodLabel, {
    String subtitle = '(Official Operations, Inspection Results, and Revenue Summary)',
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logo != null)
          pw.Container(
            width: 46,
            height: 46,
            child: pw.Image(logo),
          )
        else
          pw.Container(width: 46, height: 46),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text('Republic of the Philippines', style: const pw.TextStyle(fontSize: 8.5)),
              pw.Text('Province of Albay', style: const pw.TextStyle(fontSize: 8.5)),
              pw.Text('City of Tabaco', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text('OFFICE OF THE CITY VETERINARIAN & CITY SLAUGHTERHOUSE',
                  style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 3),
              pw.Text(
                title,
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center,
              ),
              pw.Text(
                subtitle,
                style: const pw.TextStyle(fontSize: 7.5),
              ),
            ],
          ),
        ),
        pw.Container(
          width: 135,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(width: 0.5)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('REPORTING PERIOD:', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                    pw.Text(
                      periodLabel,
                      style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
                      textAlign: pw.TextAlign.right,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  TOP KPI HIGHLIGHTS SUMMARY BOX
  //  Includes Total Revenue, Livestock Processed, Carcass Weight, etc.
  // ═══════════════════════════════════════════════════════════════
  static pw.Widget _buildHighlightsSummary({
    required double revenue,
    required int processedCount,
    required double totalWeight,
    required int healthIssueCount,
    required int uninspectedCount,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F7FAFC'),
        border: pw.TableBorder.all(color: PdfColor.fromHex('#CBD5E0'), width: 0.8),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _summaryKpi('TOTAL REVENUE', '\u20b1 ${NumberFormat('#,##0.00').format(revenue)}', PdfColor.fromHex('#1B4332')),
          _summaryKpi('LIVESTOCK PROCESSED', '$processedCount Heads', PdfColor.fromHex('#2D6A4F')),
          _summaryKpi('TOTAL CARCASS WEIGHT', '${totalWeight.toStringAsFixed(1)} kg', PdfColor.fromHex('#2B6CB0')),
          _summaryKpi('HEALTH ISSUES / CONDEMNED', '$healthIssueCount Cases', PdfColor.fromHex('#C53030')),
          _summaryKpi('DID NOT UNDERGO INSPECTION', '$uninspectedCount Cases', PdfColor.fromHex('#718096')),
        ],
      ),
    );
  }

  static pw.Widget _summaryKpi(String label, String value, PdfColor color) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700)),
        pw.SizedBox(height: 2),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: color),
        ),
      ],
    );
  }

  static pw.Widget _buildSectionHeader(String title) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      color: PdfColor.fromHex('#2D3748'),
      child: pw.Text(
        title,
        style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  SECTION 1: PROCESSED LIVESTOCK TABLE
  //  Columns: No | Name | Markings | Heads (Hog, Cow, Cara, Goat, Poultry) |
  //           Weight (Hog, Cow, Cara, Goat, Poultry) | Fees (PHP) | Remarks
  // ═══════════════════════════════════════════════════════════════
  static pw.Widget _buildMainTable(
    List<Map<String, dynamic>> marketRequests,
    List<Map<String, dynamic>> barangayRequests,
  ) {
    final headerStyle = pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold);
    const cellStyle = pw.TextStyle(fontSize: 6);
    final sectionStyle = pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold);

    final rows = <pw.TableRow>[];

    // Header Row 1
    rows.add(
      pw.TableRow(
        decoration: pw.BoxDecoration(color: PdfColor.fromHex('#EDF2F7')),
        children: [
          _headerCellCenter('No.', headerStyle),
          _headerCell('Name of Owner / Customer', headerStyle),
          _headerCellCenter('Markings', headerStyle),
          _headerCellCenter('NUMBER OF HEADS', headerStyle),
          _headerCellCenter('', headerStyle),
          _headerCellCenter('', headerStyle),
          _headerCellCenter('', headerStyle),
          _headerCellCenter('', headerStyle),
          _headerCellCenter('CARCASS WEIGHT (KG)', headerStyle),
          _headerCellCenter('', headerStyle),
          _headerCellCenter('', headerStyle),
          _headerCellCenter('', headerStyle),
          _headerCellCenter('', headerStyle),
          _headerCellCenter('FEES (PHP)', headerStyle),
          _headerCellCenter('REMARKS', headerStyle),
        ],
      ),
    );

    // Header Row 2: Sub-columns for all 5 categories
    rows.add(
      pw.TableRow(
        decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F7FAFC')),
        children: [
          _headerCellCenter('', headerStyle),
          _headerCellCenter('MARKET SECTION', headerStyle),
          _headerCellCenter('', headerStyle),
          _headerCellCenter('HOG', headerStyle),
          _headerCellCenter('COW', headerStyle),
          _headerCellCenter('CARA', headerStyle),
          _headerCellCenter('GOAT', headerStyle),
          _headerCellCenter('POULTRY', headerStyle),
          _headerCellCenter('HOG', headerStyle),
          _headerCellCenter('COW', headerStyle),
          _headerCellCenter('CARA', headerStyle),
          _headerCellCenter('GOAT', headerStyle),
          _headerCellCenter('POULTRY', headerStyle),
          _headerCellCenter('TOTAL', headerStyle),
          _headerCellCenter('', headerStyle),
        ],
      ),
    );

    // Market records
    if (marketRequests.isEmpty) {
      rows.add(
        pw.TableRow(
          children: [
            _emptyCell(cellStyle),
            pw.Padding(
              padding: const pw.EdgeInsets.all(3),
              child: pw.Text('No market transactions for this period',
                  style: pw.TextStyle(fontSize: 6, fontStyle: pw.FontStyle.italic, color: PdfColors.grey600)),
            ),
            ...List.generate(13, (_) => _emptyCell(cellStyle)),
          ],
        ),
      );
    } else {
      for (int i = 0; i < marketRequests.length; i++) {
        rows.add(_buildProcessedDataRow(i + 1, marketRequests[i], cellStyle));
      }
    }

    // Barangay Header
    rows.add(
      pw.TableRow(
        decoration: pw.BoxDecoration(color: PdfColor.fromHex('#EDF2F7')),
        children: [
          _emptyCell(cellStyle),
          pw.Padding(
            padding: const pw.EdgeInsets.all(2),
            child: pw.Center(child: pw.Text('BARANGAY SECTION', style: sectionStyle)),
          ),
          ...List.generate(13, (_) => _emptyCell(cellStyle)),
        ],
      ),
    );

    // Barangay records
    if (barangayRequests.isEmpty) {
      rows.add(
        pw.TableRow(
          children: [
            _emptyCell(cellStyle),
            pw.Padding(
              padding: const pw.EdgeInsets.all(3),
              child: pw.Text('No barangay transactions for this period',
                  style: pw.TextStyle(fontSize: 6, fontStyle: pw.FontStyle.italic, color: PdfColors.grey600)),
            ),
            ...List.generate(13, (_) => _emptyCell(cellStyle)),
          ],
        ),
      );
    } else {
      for (int i = 0; i < barangayRequests.length; i++) {
        rows.add(_buildProcessedDataRow(i + 1, barangayRequests[i], cellStyle));
      }
    }

    return pw.Table(
      border: pw.TableBorder.all(width: 0.5, color: PdfColor.fromHex('#CBD5E0')),
      columnWidths: const {
        0: pw.FixedColumnWidth(16),  // No.
        1: pw.FlexColumnWidth(2.6),  // Name
        2: pw.FlexColumnWidth(1.1),  // Markings
        3: pw.FixedColumnWidth(18),  // Heads Hog
        4: pw.FixedColumnWidth(18),  // Heads Cow
        5: pw.FixedColumnWidth(18),  // Heads Cara
        6: pw.FixedColumnWidth(18),  // Heads Goat
        7: pw.FixedColumnWidth(22),  // Heads Poultry
        8: pw.FixedColumnWidth(22),  // Weight Hog
        9: pw.FixedColumnWidth(22),  // Weight Cow
        10: pw.FixedColumnWidth(22), // Weight Cara
        11: pw.FixedColumnWidth(22), // Weight Goat
        12: pw.FixedColumnWidth(24), // Weight Poultry
        13: pw.FixedColumnWidth(36), // Fee Total
        14: pw.FlexColumnWidth(1.8), // Remarks
      },
      children: rows,
    );
  }

  static pw.TableRow _buildProcessedDataRow(int number, Map<String, dynamic> req, pw.TextStyle style) {
    final name = req['customer_name']?.toString() ?? '\u2014';
    final markings = req['marking']?.toString() ?? '';
    final livestockType = (req['livestock_type']?.toString() ?? '').toLowerCase();
    final animalCount = int.tryParse((req['animal_count'] ?? 1).toString()) ?? 1;
    final carcassWeight = double.tryParse((req['carcass_weight'] ?? 0).toString()) ?? 0;

    String hogsHeads = '', cowHeads = '', caraHeads = '', goatHeads = '', poultryHeads = '';
    String hogsWeight = '', cowWeight = '', caraWeight = '', goatWeight = '', poultryWeight = '';

    // Accurate distribution across species: Goats & Poultry never dumped under Hogs!
    if (_isGoat(livestockType)) {
      goatHeads = animalCount.toString();
      if (carcassWeight > 0) goatWeight = carcassWeight.toStringAsFixed(1);
    } else if (_isPoultry(livestockType)) {
      poultryHeads = animalCount.toString();
      if (carcassWeight > 0) poultryWeight = carcassWeight.toStringAsFixed(1);
    } else if (_isCow(livestockType)) {
      cowHeads = animalCount.toString();
      if (carcassWeight > 0) cowWeight = carcassWeight.toStringAsFixed(1);
    } else if (_isCara(livestockType)) {
      caraHeads = animalCount.toString();
      if (carcassWeight > 0) caraWeight = carcassWeight.toStringAsFixed(1);
    } else if (_isHog(livestockType)) {
      hogsHeads = animalCount.toString();
      if (carcassWeight > 0) hogsWeight = carcassWeight.toStringAsFixed(1);
    } else {
      hogsHeads = animalCount.toString();
      if (carcassWeight > 0) hogsWeight = carcassWeight.toStringAsFixed(1);
    }

    // Fee calculation
    double fee = 0;
    final payment = req['payment'] as Map<String, dynamic>?;
    if (payment != null) {
      fee = double.tryParse((payment['total_amount'] ?? payment['amount'] ?? 0).toString()) ?? 0;
    }
    if (fee == 0) {
      fee = double.tryParse((req['total_amount'] ?? req['total_fee'] ?? 0).toString()) ?? 0;
    }
    if (fee == 0 && carcassWeight > 0) {
      fee = (carcassWeight * 5.0) + 250.0;
    }

    final feeStr = fee > 0 ? NumberFormat('#,##0.00').format(fee) : '\u2014';
    final notes = req['process_notes']?.toString() ?? '';
    final remarks = notes.isNotEmpty && notes != 'null' ? notes : 'Passed Inspection';

    return pw.TableRow(
      children: [
        _dataCellCenter(number.toString(), style),
        _dataCell(name, style),
        _dataCellCenter(markings, style),
        _dataCellCenter(hogsHeads, style),
        _dataCellCenter(cowHeads, style),
        _dataCellCenter(caraHeads, style),
        _dataCellCenter(goatHeads, style),
        _dataCellCenter(poultryHeads, style),
        _dataCellCenter(hogsWeight, style),
        _dataCellCenter(cowWeight, style),
        _dataCellCenter(caraWeight, style),
        _dataCellCenter(goatWeight, style),
        _dataCellCenter(poultryWeight, style),
        _dataCellCenter(feeStr, style),
        _dataCell(remarks, style),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  SECTION 2: HEALTH ISSUES & CONDEMNATIONS (SEPARATE LIST)
  // ═══════════════════════════════════════════════════════════════
  static pw.Widget _buildHealthIssuesTable(List<Map<String, dynamic>> healthIssues) {
    final headerStyle = pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold);
    const cellStyle = pw.TextStyle(fontSize: 6);

    if (healthIssues.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.TableBorder.all(color: PdfColor.fromHex('#E2E8F0'), width: 0.5),
          color: PdfColor.fromHex('#F7FAFC'),
        ),
        child: pw.Center(
          child: pw.Text(
            'No health issues or condemnations reported during this period. All processed animals met sanitary standards.',
            style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700),
          ),
        ),
      );
    }

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: pw.BoxDecoration(color: PdfColor.fromHex('#FFF5F5')),
        children: [
          _headerCellCenter('No.', headerStyle),
          _headerCell('Reference No.', headerStyle),
          _headerCell('Customer Name', headerStyle),
          _headerCellCenter('Livestock / Heads', headerStyle),
          _headerCellCenter('Inspection Stage', headerStyle),
          _headerCell('Veterinary Findings / Health Issues', headerStyle),
          _headerCellCenter('Action Taken / Disposition', headerStyle),
        ],
      ),
    ];

    for (int i = 0; i < healthIssues.length; i++) {
      final req = healthIssues[i];
      final id = req['id']?.toString() ?? '';
      final ref = 'MI-${DateTime.now().year}-${id.padLeft(3, '0')}';
      final name = req['customer_name']?.toString() ?? '\u2014';
      final livestock = '${req['livestock_type'] ?? 'Unknown'} (${req['animal_count'] ?? 1} head)';

      final anti = (req['anti_mortem'] ?? '').toString();
      final post = (req['post_mortem'] ?? '').toString();
      final status = (req['status'] ?? '').toString();

      String stage = 'Ante-Mortem';
      String disposition = 'Ante-Mortem Failed — Taken Back';

      if (post == 'Failed' || status == 'condemned' || status == 'post_mortem_failed') {
        stage = 'Post-Mortem Inspection';
        disposition = 'Carcass Condemned';
      } else if (anti == 'Failed' || status == 'anti_mortem_failed' || status == 'taken_back') {
        stage = 'Ante-Mortem Inspection';
        disposition = 'Rejected / Taken Back by Owner';
      }

      String findings = req['veterinary_findings']?.toString() ??
          req['condemnation_reason']?.toString() ??
          req['process_notes']?.toString() ??
          'Health abnormality detected during inspection';
      if (findings.isEmpty || findings == 'null') {
        findings = 'Did not meet health & inspection standards';
      }

      rows.add(
        pw.TableRow(
          children: [
            _dataCellCenter('${i + 1}', cellStyle),
            _dataCell(ref, cellStyle),
            _dataCell(name, cellStyle),
            _dataCellCenter(livestock, cellStyle),
            _dataCellCenter(stage,
                pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#C53030'))),
            _dataCell(findings, cellStyle),
            _dataCellCenter(disposition,
                pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#9B2C2C'))),
          ],
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(width: 0.5, color: PdfColor.fromHex('#FED7D7')),
      columnWidths: const {
        0: pw.FixedColumnWidth(18),
        1: pw.FixedColumnWidth(64),
        2: pw.FlexColumnWidth(2.4),
        3: pw.FlexColumnWidth(2.0),
        4: pw.FlexColumnWidth(2.0),
        5: pw.FlexColumnWidth(3.8),
        6: pw.FlexColumnWidth(2.6),
      },
      children: rows,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  SECTION 3: DID NOT UNDERGO INSPECTION (SEPARATE LIST)
  // ═══════════════════════════════════════════════════════════════
  static pw.Widget _buildUninspectedTable(List<Map<String, dynamic>> uninspected) {
    final headerStyle = pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold);
    const cellStyle = pw.TextStyle(fontSize: 6);

    if (uninspected.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.TableBorder.all(color: PdfColor.fromHex('#E2E8F0'), width: 0.5),
          color: PdfColor.fromHex('#F7FAFC'),
        ),
        child: pw.Center(
          child: pw.Text(
            'All registered livestock underwent official veterinary inspection as scheduled.',
            style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700),
          ),
        ),
      );
    }

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F7FAFC')),
        children: [
          _headerCellCenter('No.', headerStyle),
          _headerCell('Reference No.', headerStyle),
          _headerCell('Customer Name', headerStyle),
          _headerCellCenter('Livestock / Heads', headerStyle),
          _headerCellCenter('Scheduled Date', headerStyle),
          _headerCellCenter('Registration Status', headerStyle),
          _headerCell('Reason / Remarks', headerStyle),
        ],
      ),
    ];

    for (int i = 0; i < uninspected.length; i++) {
      final req = uninspected[i];
      final id = req['id']?.toString() ?? '';
      final ref = 'MI-${DateTime.now().year}-${id.padLeft(3, '0')}';
      final name = req['customer_name']?.toString() ?? '\u2014';
      final livestock = '${req['livestock_type'] ?? 'Unknown'} (${req['animal_count'] ?? 1} head)';
      final sched = req['preferred_date']?.toString() ?? req['created_at']?.toString() ?? '\u2014';
      final status = (req['status'] ?? 'Pending').toString();

      String reason = 'Inspection pending or omitted before slaughter';
      if (status == 'cancelled') {
        reason = 'Booking cancelled by customer prior to arrival';
      } else if (status == 'rejected') {
        reason = 'Registration rejected during document verification';
      } else if (status == 'pending' || status == 'approved') {
        reason = 'Pending animal arrival & ante-mortem inspection';
      }

      rows.add(
        pw.TableRow(
          children: [
            _dataCellCenter('${i + 1}', cellStyle),
            _dataCell(ref, cellStyle),
            _dataCell(name, cellStyle),
            _dataCellCenter(livestock, cellStyle),
            _dataCellCenter(sched.length > 10 ? sched.substring(0, 10) : sched, cellStyle),
            _dataCellCenter(status.toUpperCase(),
                pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#4A5568'))),
            _dataCell(reason, cellStyle),
          ],
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(width: 0.5, color: PdfColor.fromHex('#E2E8F0')),
      columnWidths: const {
        0: pw.FixedColumnWidth(18),
        1: pw.FixedColumnWidth(64),
        2: pw.FlexColumnWidth(2.5),
        3: pw.FlexColumnWidth(2.0),
        4: pw.FlexColumnWidth(2.0),
        5: pw.FlexColumnWidth(2.2),
        6: pw.FlexColumnWidth(3.5),
      },
      children: rows,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  SUMMARY COMMODITIES & REVENUE TABLE
  // ═══════════════════════════════════════════════════════════════
  static pw.Widget _buildSummaryTable({
    required int hogs,
    required int cow,
    required int cara,
    required int goat,
    required int poultry,
    required double totalWeight,
    required double totalRevenue,
  }) {
    final style = pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold);
    final totalHeads = hogs + cow + cara + goat + poultry;

    return pw.Table(
      border: pw.TableBorder.all(width: 0.5, color: PdfColor.fromHex('#CBD5E0')),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.0),
        1: pw.FlexColumnWidth(1.0),
        2: pw.FlexColumnWidth(1.0),
        3: pw.FlexColumnWidth(1.0),
        4: pw.FlexColumnWidth(1.0),
        5: pw.FlexColumnWidth(1.3),
        6: pw.FlexColumnWidth(1.5),
        7: pw.FlexColumnWidth(1.7),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColor.fromHex('#EDF2F7')),
          children: [
            _headerCellCenter('HOGS', style),
            _headerCellCenter('COW / CATTLE', style),
            _headerCellCenter('CARABAO', style),
            _headerCellCenter('GOAT', style),
            _headerCellCenter('POULTRY', style),
            _headerCellCenter('TOTAL HEADS', style),
            _headerCellCenter('TOTAL WEIGHT', style),
            _headerCellCenter('TOTAL REVENUE', style),
          ],
        ),
        pw.TableRow(
          children: [
            _headerCellCenter(hogs.toString(), style),
            _headerCellCenter(cow.toString(), style),
            _headerCellCenter(cara.toString(), style),
            _headerCellCenter(goat.toString(), style),
            _headerCellCenter(poultry.toString(), style),
            _headerCellCenter('$totalHeads Heads',
                pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#2D6A4F'))),
            _headerCellCenter('${totalWeight.toStringAsFixed(1)} kg', style),
            _headerCellCenter('\u20b1 ${NumberFormat('#,##0.00').format(totalRevenue)}',
                pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1B4332'))),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  OFFICIAL SIGNATURES
  // ═══════════════════════════════════════════════════════════════
  static pw.Widget _buildSignatures() {
    final labelStyle = pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold);
    final nameStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, decoration: pw.TextDecoration.underline);
    final titleStyle = const pw.TextStyle(fontSize: 6.5);

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
            pw.SizedBox(width: 40),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('JONEL P. ARCOS', style: nameStyle),
                pw.Text('Slaughterhouse Master 1', style: titleStyle),
              ],
            ),
            pw.SizedBox(width: 40),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('KIM RONAN ROMERO, DVM', style: nameStyle),
                pw.Text('CITY VETERINARIAN', style: titleStyle),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  SPECIES RECOGNITION HELPERS
  // ═══════════════════════════════════════════════════════════════
  static bool _isGoat(String t) =>
      t.contains('goat') || t.contains('sheep') || t.contains('caprine') || t.contains('kambing');

  static bool _isPoultry(String t) =>
      t.contains('poultry') || t.contains('chicken') || t.contains('duck') ||
      t.contains('turkey') || t.contains('fowl') || t.contains('manok') ||
      t.contains('pato') || t.contains('bibe');

  static bool _isCow(String t) =>
      t.contains('cow') || t.contains('cattle') || t.contains('bovine') || t.contains('baka');

  static bool _isCara(String t) =>
      t.contains('cara') || t.contains('carabao') || t.contains('buffalo') || t.contains('kalabaw');

  static bool _isHog(String t) =>
      t.contains('hog') || t.contains('pig') || t.contains('swine') || t.contains('baboy');

  // ═══════════════════════════════════════════════════════════════
  //  CELL HELPERS
  // ═══════════════════════════════════════════════════════════════
  static pw.Widget _headerCell(String text, pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 1.5),
      child: pw.Text(text, style: style),
    );
  }

  static pw.Widget _headerCellCenter(String text, pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 1.5),
      child: pw.Center(child: pw.Text(text, style: style, textAlign: pw.TextAlign.center)),
    );
  }

  static pw.Widget _dataCell(String text, pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 1.5),
      child: pw.Text(text, style: style, maxLines: 1),
    );
  }

  static pw.Widget _dataCellCenter(String text, pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 1.5),
      child: pw.Center(child: pw.Text(text, style: style, maxLines: 1)),
    );
  }

  static pw.Widget _emptyCell(pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 1.5),
      child: pw.Text('', style: style),
    );
  }
}

import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

/// Generates a PDF matching the official
/// "Daily Slaughterhouse Production Report"
class ReportPdfGenerator {
  static pw.MemoryImage? _cachedLogo;

  static Future<Uint8List> generate({
    required DateTime date,
    required List<Map<String, dynamic>> requests,
  }) async {
    // Load logo only once
    if (_cachedLogo == null) {
      final logoBytes = await rootBundle.load('assets/images/logo1.png');
      _cachedLogo = pw.MemoryImage(logoBytes.buffer.asUint8List());
    }
    final logoImage = _cachedLogo!;

    final pdf = pw.Document();

    // Separate by section
    final marketRequests = requests
        .where((r) =>
            (r['request_type']?.toString() ?? '').toLowerCase() != 'barangay')
        .toList();
    final barangayRequests = requests
        .where((r) =>
            (r['request_type']?.toString() ?? '').toLowerCase() == 'barangay')
        .toList();

    final dateStr = DateFormat('MMMM d, yyyy').format(date);

    // Calculate totals for the summary table
    int totalHogs = 0, totalCow = 0, totalCara = 0, totalGoat = 0;
    for (var r in requests) {
      final type = (r['livestock_type']?.toString() ?? '').toLowerCase();
      final count = int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1;
      if (type.contains('hog') || type.contains('pig')) {
        totalHogs += count;
      } else if (type.contains('cow') || type.contains('cattle')) {
        totalCow += count;
      } else if (type.contains('cara') || type.contains('carabao')) {
        totalCara += count;
      } else if (type.contains('goat')) {
        totalGoat += count;
      } else {
        totalHogs += count; // fallback
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.legal, // Using Legal size for the long form
        margin: const pw.EdgeInsets.all(30),
        build: (pw.Context context) {
          return [
            _buildHeader(logoImage, dateStr),
            pw.SizedBox(height: 10),
            _buildMainTable(marketRequests, barangayRequests),
            pw.SizedBox(height: 0),
            _buildSummaryTable(totalHogs, totalCow, totalCara, totalGoat),
            pw.SizedBox(height: 20),
            _buildSignatures(),
          ];
        },
      ),
    );

    return pdf.save();
  }

  // ═══════════════════════════════════════
  //  HEADER
  // ═══════════════════════════════════════
  static pw.Widget _buildHeader(pw.MemoryImage logo, String dateStr) {
    return pw.Column(
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Logo
            pw.Container(
              width: 50,
              height: 50,
              child: pw.Image(logo),
            ),
            pw.SizedBox(width: 12),
            // Government header text
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('Republic of the Philippines', style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('Province of Albay', style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('City of Tabaco', style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    'DAILY SLAUGHTERHOUSE PRODUCTION REPORT',
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    '(Incoming Livestock and Carcass Production)',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ),
            // Date field
            pw.Container(
              width: 100,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.end,
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('DATE', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(width: 8),
                      pw.Container(
                        width: 70,
                        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
                        child: pw.Text(dateStr, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════
  //  MAIN TABLE
  // ═══════════════════════════════════════
  static pw.Widget _buildMainTable(
    List<Map<String, dynamic>> marketRequests,
    List<Map<String, dynamic>> barangayRequests,
  ) {
    final headerStyle = pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold);
    const cellStyle = pw.TextStyle(fontSize: 7);
    final sectionStyle = pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold);

    final rows = <pw.TableRow>[];

    // ── Header row 1 ──
    rows.add(
      pw.TableRow(
        children: [
          _headerCell('No.', headerStyle),
          _headerCell('Name of Owner', headerStyle),
          _headerCellCenter('Markings', headerStyle),
          _headerCellCenter('No. of Heads', headerStyle),
          _headerCellCenter('CARCASS WEIGHT (KGS)', headerStyle),
          _headerCellCenter('CARCASS WEIGHT (KGS)', headerStyle),
          _headerCellCenter('CARCASS WEIGHT (KGS)', headerStyle),
          _headerCellCenter('REMARKS', headerStyle),
        ],
      ),
    );

    // ── Header row 2 (sub-columns) ──
    rows.add(
      pw.TableRow(
        children: [
          _headerCell('', headerStyle),
          _headerCellCenter('MARKET SECTION', headerStyle),
          _headerCellCenter('', headerStyle),
          _headerCellCenter('HOGS', headerStyle),
          _headerCellCenter('COW', headerStyle),
          _headerCellCenter('CARA', headerStyle),
          _headerCellCenter('HOGS', headerStyle),
          _headerCellCenter('COW', headerStyle),
          _headerCellCenter('CARA', headerStyle),
          _headerCellCenter('', headerStyle),
        ],
      ),
    );

    // ── Market data rows ──
    for (int i = 0; i < marketRequests.length; i++) {
      rows.add(_buildDataRow(i + 1, marketRequests[i], cellStyle));
    }

    // ── BARANGAY label ──
    rows.add(
      pw.TableRow(
        children: [
          pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 2), child: pw.Text('', style: cellStyle)),
          pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 2), child: pw.Center(child: pw.Text('BARANGAY', style: sectionStyle))),
          ...List.generate(8, (_) => pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 2), child: pw.Text('', style: cellStyle))),
        ],
      ),
    );

    // ── Barangay data rows ──
    for (int i = 0; i < barangayRequests.length; i++) {
      rows.add(_buildDataRow(i + 1, barangayRequests[i], cellStyle));
    }

    // ── Empty rows to fill the page ──
    final totalDataRows = marketRequests.length + barangayRequests.length;
    final minRows = 38;
    if (totalDataRows < minRows) {
      for (int i = 0; i < (minRows - totalDataRows); i++) {
        rows.add(_buildEmptyRow());
      }
    }

    // Since we need complicated spanning, we will use flat columns in the table structure:
    // 0: No
    // 1: Name
    // 2: Markings
    // 3: Hogs (Heads)
    // 4: Cow (Heads)
    // 5: Cara (Heads)
    // 6: Hogs (Weight)
    // 7: Cow (Weight)
    // 8: Cara (Weight)
    // 9: Remarks
    
    // Let's redefine the headers with correct columns:
    final fixedRows = <pw.TableRow>[];
    
    // ROW 1
    fixedRows.add(
      pw.TableRow(
        children: [
          _headerCell('No.', headerStyle),
          _headerCell('Name of Owner', headerStyle),
          _headerCellCenter('Markings', headerStyle),
          // Merge No. of heads text manually across 3 cols by just putting it in the middle and leaving others empty
          _headerCellCenter('', headerStyle),
          _headerCellCenter('No. of Heads', headerStyle),
          _headerCellCenter('', headerStyle),
          // Merge Carcass Weight across 3 cols
          _headerCellCenter('', headerStyle),
          _headerCellCenter('CARCASS WEIGHT (KGS)', headerStyle),
          _headerCellCenter('', headerStyle),
          _headerCellCenter('REMARKS', headerStyle),
        ],
      ),
    );
    
    // ROW 2
    fixedRows.add(
      pw.TableRow(
        children: [
          _headerCell('', headerStyle),
          _headerCellCenter('MARKET SECTION', headerStyle),
          _headerCellCenter('', headerStyle),
          _headerCellCenter('HOGS', headerStyle),
          _headerCellCenter('COW', headerStyle),
          _headerCellCenter('CARA', headerStyle),
          _headerCellCenter('HOGS', headerStyle),
          _headerCellCenter('COW', headerStyle),
          _headerCellCenter('CARA', headerStyle),
          _headerCellCenter('', headerStyle),
        ],
      ),
    );

    // DATA
    for (int i = 0; i < marketRequests.length; i++) {
      fixedRows.add(_buildDataRow(i + 1, marketRequests[i], cellStyle));
    }
    
    fixedRows.add(
      pw.TableRow(
        children: [
          _headerCellCenter('', headerStyle),
          _headerCellCenter('BARANGAY', headerStyle),
          ...List.generate(8, (_) => _headerCellCenter('', headerStyle)),
        ],
      ),
    );

    for (int i = 0; i < barangayRequests.length; i++) {
      fixedRows.add(_buildDataRow(i + 1, barangayRequests[i], cellStyle));
    }

    if (totalDataRows < minRows) {
      for (int i = 0; i < (minRows - totalDataRows); i++) {
        fixedRows.add(_buildEmptyRow());
      }
    }

    return pw.Table(
      border: pw.TableBorder.all(width: 0.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(25),  // No.
        1: const pw.FlexColumnWidth(3),    // Name of Owner
        2: const pw.FlexColumnWidth(1.2),  // Markings
        3: const pw.FixedColumnWidth(30),  // Heads HOGS
        4: const pw.FixedColumnWidth(30),  // Heads COW
        5: const pw.FixedColumnWidth(30),  // Heads CARA
        6: const pw.FixedColumnWidth(40),  // Weight HOGS
        7: const pw.FixedColumnWidth(40),  // Weight COW
        8: const pw.FixedColumnWidth(40),  // Weight CARA
        9: const pw.FlexColumnWidth(2),    // Remarks
      },
      children: fixedRows,
    );
  }

  // ═══════════════════════════════════════
  //  SUMMARY TABLE (Bottom)
  // ═══════════════════════════════════════
  static pw.Widget _buildSummaryTable(int hogs, int cow, int cara, int goat) {
    final style = pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold);
    return pw.Table(
      border: pw.TableBorder.all(width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(1),
        4: const pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          children: [
            _headerCellCenter('', style),
            _headerCellCenter('', style),
            _headerCellCenter('ANIMAL COMMODITIES SLAUGHTERED', style),
            _headerCellCenter('', style),
            _headerCellCenter('', style),
          ],
        ),
        pw.TableRow(
          children: [
            _headerCellCenter('HOGS', style),
            _headerCellCenter('COW', style),
            _headerCellCenter('CARABAO', style),
            _headerCellCenter('GOAT', style),
            _headerCellCenter('REMARKS', style),
          ],
        ),
        pw.TableRow(
          children: [
            _headerCellCenter(hogs > 0 ? hogs.toString() : '', style),
            _headerCellCenter(cow > 0 ? cow.toString() : '', style),
            _headerCellCenter(cara > 0 ? cara.toString() : '', style),
            _headerCellCenter(goat > 0 ? goat.toString() : '', style),
            _headerCellCenter('', style),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════
  //  SIGNATURES
  // ═══════════════════════════════════════
  static pw.Widget _buildSignatures() {
    final labelStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
    final nameStyle = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, decoration: pw.TextDecoration.underline);
    final titleStyle = pw.TextStyle(fontSize: 8);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // Livestock Recorders
        pw.Text('LIVESTOCK RECORDERS ON DUTY:', style: labelStyle),
        pw.SizedBox(height: 12),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.start,
          children: [
            pw.SizedBox(width: 30),
            pw.Text('FERNANDO BALINGBING', style: nameStyle),
            pw.SizedBox(width: 80),
            pw.Text('ERWIN BIEN', style: nameStyle),
          ],
        ),
        pw.SizedBox(height: 16),

        // Meat Inspectors
        pw.Text('MEAT INSPECTORS ON DUTY:', style: labelStyle),
        pw.SizedBox(height: 12),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.start,
          children: [
            pw.SizedBox(width: 30),
            pw.Text('MELCHOR VARGAS', style: nameStyle),
            pw.SizedBox(width: 80),
            pw.Text('RODEL B. BALINGBING', style: nameStyle),
            pw.SizedBox(width: 80),
            pw.Text('HENRY GASCON', style: nameStyle),
          ],
        ),
        pw.SizedBox(height: 16),

        // Certified By
        pw.Text('CERTIFIED AND VALIDATED BY:', style: labelStyle),
        pw.SizedBox(height: 12),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.start,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: 30),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('JOSE ERNESTO ROS', style: nameStyle),
                pw.Text('Slaughterhouse Designate', style: titleStyle),
              ],
            ),
            pw.SizedBox(width: 50),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('JONEL P. ARCOS', style: nameStyle),
                pw.Text('Slaughterhouse Master 1', style: titleStyle),
              ],
            ),
            pw.SizedBox(width: 50),
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

  // ═══════════════════════════════════════
  //  CELL HELPERS
  // ═══════════════════════════════════════
  static pw.TableRow _buildDataRow(
    int number,
    Map<String, dynamic> req,
    pw.TextStyle style,
  ) {
    final name = req['customer_name']?.toString() ?? '\u2014';
    final markings = req['marking']?.toString() ?? '';
    final livestockType = (req['livestock_type']?.toString() ?? '').toLowerCase();
    final animalCount = int.tryParse((req['animal_count'] ?? 1).toString()) ?? 1;
    final carcassWeight = double.tryParse((req['carcass_weight'] ?? 0).toString()) ?? 0;

    String hogsHeads = '', cowHeads = '', caraHeads = '';
    String hogsWeight = '', cowWeight = '', caraWeight = '';

    if (livestockType.contains('hog') || livestockType.contains('pig')) {
      hogsHeads = animalCount.toString();
      if (carcassWeight > 0) hogsWeight = carcassWeight.toStringAsFixed(1);
    } else if (livestockType.contains('cow') || livestockType.contains('cattle')) {
      cowHeads = animalCount.toString();
      if (carcassWeight > 0) cowWeight = carcassWeight.toStringAsFixed(1);
    } else if (livestockType.contains('cara') || livestockType.contains('carabao')) {
      caraHeads = animalCount.toString();
      if (carcassWeight > 0) caraWeight = carcassWeight.toStringAsFixed(1);
    } else {
      hogsHeads = animalCount.toString();
      if (carcassWeight > 0) hogsWeight = carcassWeight.toStringAsFixed(1);
    }

    final postMortem = req['post_mortem']?.toString();
    final notes = req['process_notes']?.toString() ?? '';
    String remarks = '';
    if (postMortem == 'Failed') {
      remarks = 'Condemned';
    } else if (notes.isNotEmpty && notes != 'null') {
      remarks = notes;
    }

    return pw.TableRow(
      children: [
        _dataCellCenter(number.toString(), style),
        _dataCell(name, style),
        _dataCellCenter(markings, style),
        _dataCellCenter(hogsHeads, style),
        _dataCellCenter(cowHeads, style),
        _dataCellCenter(caraHeads, style),
        _dataCellCenter(hogsWeight, style),
        _dataCellCenter(cowWeight, style),
        _dataCellCenter(caraWeight, style),
        _dataCellCenter(remarks, style),
      ],
    );
  }

  static pw.TableRow _buildEmptyRow() {
    return pw.TableRow(
      children: List.generate(
        10,
        (_) => pw.Container(
          height: 14,
          padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        ),
      ),
    );
  }

  static pw.Widget _headerCell(String text, pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 2),
      child: pw.Text(text, style: style),
    );
  }

  static pw.Widget _headerCellCenter(String text, pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 2),
      child: pw.Center(child: pw.Text(text, style: style, textAlign: pw.TextAlign.center)),
    );
  }

  static pw.Widget _dataCell(String text, pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 2),
      child: pw.Text(text, style: style, maxLines: 1),
    );
  }

  static pw.Widget _dataCellCenter(String text, pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 2),
      child: pw.Center(child: pw.Text(text, style: style, maxLines: 1)),
    );
  }
}

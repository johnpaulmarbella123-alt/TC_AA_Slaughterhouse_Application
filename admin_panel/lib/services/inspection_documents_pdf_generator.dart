import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

class InspectionDocumentsPdfGenerator {
  static pw.MemoryImage? _cachedLogo1;
  static pw.MemoryImage? _cachedLogo2;

  static Future<void> _loadLogos() async {
    if (_cachedLogo1 == null) {
      try {
        final b1 = await rootBundle.load('assets/images/logo1.png');
        _cachedLogo1 = pw.MemoryImage(b1.buffer.asUint8List());
      } catch (_) {}
    }
    if (_cachedLogo2 == null) {
      try {
        final b2 = await rootBundle.load('assets/images/logo2.png');
        _cachedLogo2 = pw.MemoryImage(b2.buffer.asUint8List());
      } catch (_) {}
    }
  }

  /// Generates the official Condemnation Slip PDF document.
  static Future<Uint8List> generateCondemnationSlip({
    required Map<String, dynamic> request,
    required String condemnationReason,
    required String inspectorName,
    required String carcassWeight,
    DateTime? date,
  }) async {
    await _loadLogos();

    final pdf = pw.Document();
    final now = date ?? DateTime.now();
    final dateNow = DateFormat('dd/MM/yyyy').format(now);
    final timeNow = DateFormat('hh:mm a').format(now);

    final customerName = request['customer_name']?.toString() ?? '—';
    final livestock = request['livestock_type']?.toString() ?? '—';
    final animalCount = request['animal_count']?.toString() ?? '1';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 36),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Header with Logos
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (_cachedLogo1 != null)
                    pw.Container(width: 55, height: 55, child: pw.Image(_cachedLogo1!))
                  else
                    pw.SizedBox(width: 55, height: 55),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text('Republic of the Philippines', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('Province of Albay', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('CITY OF TABACO', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  if (_cachedLogo2 != null)
                    pw.Container(width: 55, height: 55, child: pw.Image(_cachedLogo2!))
                  else
                    pw.SizedBox(width: 55, height: 55),
                ],
              ),
              pw.SizedBox(height: 16),

              // Establishment Info Lines
              pw.Row(
                children: [
                  pw.Expanded(
                    child: _buildPdfInfoLine('Name of Establishment:', 'Tabaco City Slaughterhouse'),
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Row(
                children: [
                  pw.Expanded(child: _buildPdfInfoLine('City:', 'Tabaco City')),
                  pw.SizedBox(width: 24),
                  pw.Expanded(child: _buildPdfInfoLine('Province:', 'Albay')),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Row(
                children: [
                  pw.Expanded(child: _buildPdfInfoLine('Date:', dateNow)),
                  pw.SizedBox(width: 24),
                  pw.Expanded(child: _buildPdfInfoLine('Time:', timeNow)),
                ],
              ),
              pw.SizedBox(height: 18),

              // Title
              pw.Text(
                'CONDEMNATION SLIP',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, letterSpacing: 1.2),
              ),
              pw.SizedBox(height: 12),

              // Legal Citation
              pw.Text(
                'Pursuant to Republic Act No. 7394, otherwise known as the Consumer Act of the Philippines '
                'under Article 10 and 17; and Republic Act 9296 "The Meat Inspection Code of the Philippines" and '
                'the Department of Agriculture Administrative Order No. 7, Rules, and Regulations of RA 9296 series '
                'of 2005; and NMIS Administrative Order No. 6 the following meat/meat products/processed meat is '
                'hereby condemned.',
                style: const pw.TextStyle(fontSize: 9.5, lineSpacing: 1.4),
                textAlign: pw.TextAlign.justify,
              ),
              pw.SizedBox(height: 16),

              // Condemnation Items Table
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.black, width: 0.8),
                columnWidths: const {
                  0: pw.FlexColumnWidth(2.2),
                  1: pw.FlexColumnWidth(1.5),
                  2: pw.FlexColumnWidth(2.3),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _buildPdfTableHeader('FOOD ANIMAL / MEAT / MEAT\nPRODUCTS / PROCESS MEAT'),
                      _buildPdfTableHeader('QUANTITY / WEIGHT'),
                      _buildPdfTableHeader('CAUSE OF CONDEMNATION'),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      _buildPdfTableCell(livestock, bold: true),
                      _buildPdfTableCell('$animalCount head(s)${carcassWeight.isNotEmpty ? '\n${carcassWeight}kg' : ''}'),
                      _buildPdfTableCell(condemnationReason.isNotEmpty ? condemnationReason : 'Post-mortem health inspection failure'),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      _buildPdfTableCell(''),
                      _buildPdfTableCell(''),
                      _buildPdfTableCell(''),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      _buildPdfTableCell(''),
                      _buildPdfTableCell(''),
                      _buildPdfTableCell(''),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 24),

              // Signatures: Condemned by & Conforme
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Condemned by:', style: const pw.TextStyle(fontSize: 10)),
                        pw.SizedBox(height: 22),
                        pw.Container(
                          width: 220,
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8)),
                          ),
                          padding: const pw.EdgeInsets.only(bottom: 2),
                          child: pw.Text(
                            inspectorName.isNotEmpty ? inspectorName : 'Meat Inspector',
                            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text('Veterinarian / Meat Control Officer / Meat Inspector', style: const pw.TextStyle(fontSize: 7.5)),
                        pw.Text('(Signature Over Printed Name)', style: pw.TextStyle(fontSize: 7.5, fontStyle: pw.FontStyle.italic)),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 20),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Conforme:', style: const pw.TextStyle(fontSize: 10)),
                        pw.SizedBox(height: 22),
                        pw.Container(
                          width: 220,
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8)),
                          ),
                          padding: const pw.EdgeInsets.only(bottom: 2),
                          child: pw.Text(
                            customerName,
                            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text('Name of Owner / Representative', style: const pw.TextStyle(fontSize: 7.5)),
                        pw.Text('(Signature Over Printed Name)', style: pw.TextStyle(fontSize: 7.5, fontStyle: pw.FontStyle.italic)),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 18),

              // Signatures: Disposed by & Witness
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Disposed by:', style: const pw.TextStyle(fontSize: 10)),
                        pw.SizedBox(height: 22),
                        pw.Container(
                          width: 220,
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8)),
                          ),
                          padding: const pw.EdgeInsets.only(bottom: 2),
                          child: pw.SizedBox(height: 12),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text('Veterinarian / Meat Control Officer / Meat Inspector', style: const pw.TextStyle(fontSize: 7.5)),
                        pw.Text('(Signature Over Printed Name)', style: pw.TextStyle(fontSize: 7.5, fontStyle: pw.FontStyle.italic)),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 20),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Witness:', style: const pw.TextStyle(fontSize: 10)),
                        pw.SizedBox(height: 22),
                        pw.Container(
                          width: 220,
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8)),
                          ),
                          padding: const pw.EdgeInsets.only(bottom: 2),
                          child: pw.SizedBox(height: 12),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text('(Signature Over Printed Name)', style: pw.TextStyle(fontSize: 7.5, fontStyle: pw.FontStyle.italic)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Generates the official Meat Inspection Certificate (MIC) PDF document.
  static Future<Uint8List> generateMIC({
    required Map<String, dynamic> request,
    DateTime? date,
  }) async {
    await _loadLogos();

    final pdf = pw.Document();
    final now = date ?? DateTime.now();
    final dateNow = DateFormat('dd/MM/yyyy').format(now);

    final reqId = request['id']?.toString() ?? '001';
    final certNo = 'MIC-${now.year}-${reqId.padLeft(3, '0')}';
    final refNo = 'MI-${now.year}-${reqId.padLeft(3, '0')}';
    final customerName = request['customer_name']?.toString() ?? '—';
    final livestock = request['livestock_type']?.toString() ?? '—';
    final slaughterDate = request['rescheduled_date'] ?? request['preferred_date'];
    
    String formattedSlaughterDate = '—';
    if (slaughterDate != null) {
      try {
        formattedSlaughterDate = DateFormat('dd/MM/yyyy').format(DateTime.parse(slaughterDate.toString()));
      } catch (_) {
        formattedSlaughterDate = slaughterDate.toString();
      }
    }

    final antiMortem = request['anti_mortem']?.toString().toUpperCase() ?? 'PASSED';
    final postMortem = request['post_mortem']?.toString().toUpperCase() ?? 'PASSED';
    final inspector = request['inspector_name']?.toString() ?? 'Meat Inspector';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 44, vertical: 40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header with Logos
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (_cachedLogo1 != null)
                    pw.Container(width: 60, height: 60, child: pw.Image(_cachedLogo1!))
                  else
                    pw.SizedBox(width: 60, height: 60),
                  pw.Column(
                    children: [
                      pw.Text(
                        'MEAT INSPECTION CERTIFICATE',
                        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, letterSpacing: 0.8),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'CITY GOVERNMENT OF TABACO — CITY SLAUGHTERHOUSE',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                  if (_cachedLogo2 != null)
                    pw.Container(width: 60, height: 60, child: pw.Image(_cachedLogo2!))
                  else
                    pw.SizedBox(width: 60, height: 60),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Divider(thickness: 1, color: PdfColors.grey400),
              pw.SizedBox(height: 16),

              // Certificate Info
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Certificate Number: $certNo', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  pw.Text('Date: $dateNow', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                ],
              ),
              pw.SizedBox(height: 14),

              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildCertificateRow('Customer Name:', customerName),
                    pw.SizedBox(height: 6),
                    _buildCertificateRow('Reference Number:', refNo),
                    pw.SizedBox(height: 6),
                    _buildCertificateRow('Livestock Type:', livestock),
                    pw.SizedBox(height: 6),
                    _buildCertificateRow('Slaughter Date:', formattedSlaughterDate),
                  ],
                ),
              ),
              pw.SizedBox(height: 18),

              // Inspection Results
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.green50,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border.all(color: PdfColors.green200),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      children: [
                        pw.Text('ANTI-MORTEM INSPECTION: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5)),
                        pw.Text(antiMortem, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5, color: PdfColors.green800)),
                      ],
                    ),
                    pw.SizedBox(height: 6),
                    pw.Row(
                      children: [
                        pw.Text('POST-MORTEM INSPECTION: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5)),
                        pw.Text(postMortem, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5, color: PdfColors.green800)),
                      ],
                    ),
                    pw.SizedBox(height: 6),
                    pw.Row(
                      children: [
                        pw.Text('Authorized Inspector: ', style: const pw.TextStyle(fontSize: 10.5)),
                        pw.Text(inspector, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 24),

              // Legal Statement
              pw.Text(
                'This Certificate of Inspection and Approval verifies that the meat product has undergone a comprehensive and systematic examination. '
                'The findings confirm that the product fully adheres to all prescribed health and sanitation standards, food safety regulations, and quality '
                'controls currently in effect. Consequently, this approval is granted, certifying the meat as fit for consumption by the general public.',
                style: const pw.TextStyle(height: 1.6, fontSize: 10),
                textAlign: pw.TextAlign.justify,
              ),
              pw.SizedBox(height: 20),
              pw.Text('Facility: Tabaco City Slaughterhouse', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.SizedBox(height: 36),

              // Signatures
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Inspected & Certified By:', style: const pw.TextStyle(fontSize: 9.5)),
                      pw.SizedBox(height: 30),
                      pw.Container(
                        width: 200,
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8)),
                        ),
                        padding: const pw.EdgeInsets.only(bottom: 2),
                        child: pw.Text(inspector, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5)),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text('Meat Inspector / Authorized Veterinarian', style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Approved & Released By:', style: const pw.TextStyle(fontSize: 9.5)),
                      pw.SizedBox(height: 30),
                      pw.Container(
                        width: 200,
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8)),
                        ),
                        padding: const pw.EdgeInsets.only(bottom: 2),
                        child: pw.Text('Tabaco City Slaughterhouse', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5)),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text('Slaughterhouse Administration', style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildPdfInfoLine(String label, String value) {
    return pw.Row(
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(width: 6),
        pw.Expanded(
          child: pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.7)),
            ),
            padding: const pw.EdgeInsets.only(bottom: 1),
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 9.5)),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildPdfTableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static pw.Widget _buildPdfTableCell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(fontSize: 8.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
      ),
    );
  }

  static pw.Widget _buildCertificateRow(String label, String value) {
    return pw.Row(
      children: [
        pw.SizedBox(
          width: 130,
          child: pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        ),
        pw.Expanded(
          child: pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ),
      ],
    );
  }
}

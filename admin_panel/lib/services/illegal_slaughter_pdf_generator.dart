import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

class IllegalSlaughterPdfGenerator {
  static pw.MemoryImage? _cachedLogo;

  static Future<Uint8List> generate({
    required Map<String, dynamic> report,
  }) async {
    if (_cachedLogo == null) {
      try {
        final logoBytes = await rootBundle.load('assets/images/logo1.png');
        _cachedLogo = pw.MemoryImage(logoBytes.buffer.asUint8List());
      } catch (_) {}
    }

    final pdf = pw.Document();

    final ref = report['reference_no'] ?? 'REP-UNSPECIFIED';
    final location = report['location'] ?? 'Tabaco City';
    final incidentDate = report['incident_date'] ?? report['created_at'] ?? '';
    final formattedDate = _formatDate(incidentDate);
    final description = report['description'] ?? 'No description provided.';
    final isAnon = report['is_anonymous'] == true || report['reporter_name'] == 'Anonymous';
    final reporter = isAnon ? 'Protected Anonymous Whistleblower' : (report['reporter_name'] ?? 'Citizen Reporter');
    final contact = report['contact_number'] != null && !isAnon ? report['contact_number'] : 'Confidential / Not Disclosed';
    final findings = report['findings'] ?? 'Investigation completed and violations verified on-site.';
    final endorsedTo = report['endorsed_to'] ?? 'NMIS (National Meat Inspection Service)';
    final resolvedAt = _formatDate(report['resolved_at'] ?? DateTime.now().toIso8601String());

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ── Formal Header ──
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (_cachedLogo != null)
                    pw.Container(
                      width: 55,
                      height: 55,
                      margin: const pw.EdgeInsets.only(right: 16),
                      child: pw.Image(_cachedLogo!),
                    ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          'Republic of the Philippines',
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                        ),
                        pw.Text(
                          'PROVINCE OF ALBAY | CITY GOVERNMENT OF TABACO',
                          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900),
                        ),
                        pw.Text(
                          'OFFICE OF THE CITY VETERINARIAN & CITY SLAUGHTERHOUSE',
                          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.green900),
                        ),
                        pw.Text(
                          'San Vicente, Tabaco City, Albay',
                          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Divider(thickness: 1.5, color: PdfColors.green900),
              pw.SizedBox(height: 12),

              // ── Document Title ──
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'OFFICIAL ILLEGAL SLAUGHTER ENFORCEMENT DOSSIER',
                      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.red900),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Case Incident File No: $ref',
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 18),

              // ── Section 1: Incident Specifications ──
              _buildSectionHeader('1. INCIDENT SPECIFICATIONS'),
              pw.SizedBox(height: 6),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  children: [
                    _buildRow('Incident Date & Time:', formattedDate),
                    pw.SizedBox(height: 4),
                    _buildRow('Incident Location:', location),
                    pw.SizedBox(height: 4),
                    _buildRow('Source of Tip:', 'Mobile Whistleblower Application'),
                    pw.SizedBox(height: 4),
                    _buildRow('Reporter Category:', reporter),
                    pw.SizedBox(height: 4),
                    _buildRow('Contact / Reference:', contact),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),

              // ── Section 2: Reported Allegation ──
              _buildSectionHeader('2. COMPLAINT & INITIAL ALLEGATION'),
              pw.SizedBox(height: 6),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  description,
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey900, lineSpacing: 2),
                ),
              ),
              pw.SizedBox(height: 14),

              // ── Section 3: On-Site Investigation & Official Findings ──
              _buildSectionHeader('3. ON-SITE INVESTIGATION FINDINGS & ACTIONS TAKEN'),
              pw.SizedBox(height: 6),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.green300),
                  color: PdfColors.green50,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      findings,
                      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900, lineSpacing: 2),
                    ),
                    pw.SizedBox(height: 8),
                    _buildRow('Statutory Enforcement:', 'Republic Act No. 9296 (Meat Inspection Code of the Philippines)'),
                    pw.SizedBox(height: 4),
                    _buildRow('Action Status:', 'Officially Compiled & Filed'),
                    pw.SizedBox(height: 4),
                    _buildRow('Date of Final Resolution:', resolvedAt),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),

              // ── Section 4: Inter-Agency Escalation & Endorsement ──
              _buildSectionHeader('4. LEGAL FORWARDING & ENDORSEMENT'),
              pw.SizedBox(height: 6),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.blue300),
                  color: PdfColors.blue50,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: _buildRow('Endorsed Authority:', endorsedTo, isBoldVal: true),
              ),
              pw.Spacer(),

              // ── Signatures ──
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(width: 160, height: 1, color: PdfColors.black),
                      pw.SizedBox(height: 4),
                      pw.Text('Investigating Officer / Inspector', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      pw.Text('City Meat Inspection Service', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(width: 160, height: 1, color: PdfColors.black),
                      pw.SizedBox(height: 4),
                      pw.Text('City Veterinarian', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Office of the City Veterinarian', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(
                  'This document serves as an official certified record of the Tabaco City Government Slaughterhouse Administration.',
                  style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey500),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildSectionHeader(String title) {
    return pw.Text(
      title,
      style: pw.TextStyle(
        fontSize: 10.5,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.blueGrey900,
      ),
    );
  }

  static pw.Widget _buildRow(String label, String value, {bool isBoldVal = false}) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 150,
          child: pw.Text(
            label,
            style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 9.5,
              fontWeight: isBoldVal ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: PdfColors.grey900,
            ),
          ),
        ),
      ],
    );
  }

  static String _formatDate(String raw) {
    if (raw.isEmpty) return 'N/A';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return DateFormat('MMMM d, yyyy - h:mm a').format(dt);
    } catch (_) {
      return raw;
    }
  }
}

import 'package:flutter/services.dart' show rootBundle, Uint8List;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'pdf_unicode_fonts.dart';

class ReceiptPdfGenerator {
  /// Formats `OR-YYYY-000001` from a request ID or existing receipt number.
  static String formatOfficialOrNo(Map<String, dynamic> req, String fallbackReceiptNo) {
    final idNum = int.tryParse((req['id'] ?? '').toString()) ?? 1;
    final year = DateTime.now().year;
    final trimmed = fallbackReceiptNo.trim();
    if (trimmed.toUpperCase().startsWith('OR-')) return trimmed.toUpperCase();
    return 'OR-$year-${idNum.toString().padLeft(6, '0')}';
  }

  /// Formats `TXN-YYYYMMDD-0001` from request `created_at` and `id`.
  static String formatTxnNo(Map<String, dynamic> req) {
    final idNum = int.tryParse((req['id'] ?? '').toString()) ?? 1;
    final dt = DateTime.tryParse((req['created_at'] ?? '').toString())?.toLocal() ?? DateTime.now();
    final ymd = DateFormat('yyyyMMdd').format(dt);
    return 'TXN-$ymd-${idNum.toString().padLeft(4, '0')}';
  }

  static Future<Uint8List> generate({
    required Map<String, dynamic> req,
    required Map<String, dynamic> fees,
    required String receiptNo,
    required String refNo,
    required String status,
    required String method,
    required double weight,
    bool isThermal80mm = true,
  }) async {
    final fonts = await PdfUnicodeFonts.load();
    const String currency = '\u20b1';

    pw.MemoryImage? sealImage;
    try {
      final byteData = await rootBundle.load('assets/images/logo1.png');
      sealImage = pw.MemoryImage(byteData.buffer.asUint8List());
    } catch (_) {}

    final pw.Font baseFont = isThermal80mm ? fonts.monoRegular : fonts.regular;
    final pw.Font baseBold = isThermal80mm ? fonts.monoBold : fonts.bold;
    final pw.Font monoFont = fonts.monoRegular;
    final pw.Font monoBold = fonts.monoBold;

    final pdf = pw.Document(
      theme: isThermal80mm ? fonts.thermalTheme : fonts.standardTheme,
    );

    final isBarangay = req['request_type'] == 'barangay';
    final payment = req['payment'] as Map<String, dynamic>?;
    final tracking = req['penalty_tracking'] as Map<String, dynamic>?;

    final now = DateTime.now();
    final dateTimeStr = DateFormat('MMM d, yyyy, hh:mm a').format(now);

    final orNo = formatOfficialOrNo(req, receiptNo);
    final bookletOr = (payment?['booklet_or_no'] ?? req['booklet_or_no'] ?? '').toString().trim();
    final txnNo = formatTxnNo(req);
    final customerName = (req['customer_name'] ?? '\u2014').toString().toUpperCase();
    final customerType = isBarangay ? 'Barangay Meat Dealer' : 'Market Meat Dealer';

    final totalCount = int.tryParse((req['animal_count'] ?? 1).toString()) ?? 1;
    int passedCount = int.tryParse((req['passed_count'] ?? '').toString()) ?? 0;
    int condemnedCount = int.tryParse((req['condemned_count'] ?? '').toString()) ?? 0;
    if (passedCount == 0 && condemnedCount == 0) {
      final notes = (req['process_notes'] ?? '').toString();
      final m = RegExp(r'\[PARTIAL_BATCH:\s*passed=(\d+),\s*condemned=(\d+)\]').firstMatch(notes);
      if (m != null) {
        passedCount = int.tryParse(m.group(1) ?? '') ?? 0;
        condemnedCount = int.tryParse(m.group(2) ?? '') ?? 0;
      }
    }
    final billableHeads = (passedCount > 0) ? passedCount : totalCount;

    String fmtAmt(num? val) {
      final num v = (val ?? 0).toDouble();
      return '$currency${NumberFormat('#,##0.00').format(v)}';
    }

    final additionalFee = (fees['additional_fee'] as num?)?.toDouble() ?? 0.0;
    final overduePenalty = (fees['overdue_penalty'] as num?)?.toDouble() ?? 0.0;
    final coldStoragePenalty = (fees['cold_storage_penalty'] as num?)?.toDouble() ?? 0.0;
    final penaltyFee = (fees['penalty_fee'] as num?)?.toDouble() ?? 0.0;
    final isWarningOnly = tracking?['is_warning_only'] == true ||
        req['is_warning_only'] == true ||
        (req['process_notes'] ?? '').toString().contains('1ST OFFENSE');

    final totalAmount = (fees['total'] as num?)?.toDouble() ?? 0.0;
    final rawTendered = (payment?['amount_tendered'] as num?)?.toDouble() ?? totalAmount;
    final tenderedAmount = rawTendered >= totalAmount ? rawTendered : totalAmount;
    final storedChange = (payment?['change_amount'] as num?)?.toDouble();
    final changeAmount = (storedChange != null && storedChange >= 0)
        ? storedChange
        : (tenderedAmount - totalAmount).clamp(0.0, double.infinity);
    final methodLabel = (method != '\u2014' && method.trim().isNotEmpty)
        ? method.trim().toUpperCase()
        : 'CASH';

    final double baseSize = isThermal80mm ? 9.5 : 11.5;
    final double titleSize = isThermal80mm ? 11.5 : 14.0;
    final double subTitleSize = isThermal80mm ? 10.0 : 12.0;

    pw.Widget dashedDivider({PdfColor? color}) {
      return pw.Container(
        margin: const pw.EdgeInsets.symmetric(vertical: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(
              color: color ?? PdfColor.fromHex('#94A3B8'),
              width: 0.8,
              style: pw.BorderStyle.dashed,
            ),
          ),
        ),
      );
    }

    pw.Widget metaRow(String label, String value, {bool boldValue = false, bool monoValue = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3.5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: baseSize,
                color: PdfColors.black,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Text(
                value,
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                  font: monoValue ? (boldValue ? monoBold : monoFont) : (boldValue ? baseBold : baseFont),
                  fontSize: baseSize,
                  fontWeight: boldValue ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: PdfColors.black,
                ),
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget feeLine(String label, String amount, {bool bold = false, double? fontSize}) {
      final sz = fontSize ?? baseSize;
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3.5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  fontSize: sz,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: PdfColors.black,
                ),
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Text(
              amount,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                font: bold ? monoBold : monoFont,
                fontSize: sz,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: PdfColors.black,
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget buildReceiptBody() {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          // 1. Header Block
          pw.Center(
            child: pw.Column(
              children: [
                if (sealImage != null) ...[
                  pw.Container(
                    width: 44,
                    height: 44,
                    child: pw.Image(sealImage, fit: pw.BoxFit.contain),
                  ),
                  pw.SizedBox(height: 5),
                ],
                pw.Text(
                  'REPUBLIC OF THE PHILIPPINES',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: baseSize - 0.5, color: PdfColors.black),
                ),
                pw.SizedBox(height: 1.5),
                pw.Text(
                  'Province of Albay \u2022 City of Tabaco',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: baseSize - 0.5, color: PdfColors.black),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'CITY ABATTOIR OFFICE',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: titleSize,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'OFFICIAL RECEIPT',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: subTitleSize,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1.0,
                    color: PdfColors.black,
                  ),
                ),
              ],
            ),
          ),

          dashedDivider(),

          // 2. Transaction Metadata
          metaRow('OR No.:', orNo, boldValue: true, monoValue: true),
          if (bookletOr.isNotEmpty)
            metaRow('Booklet OR #:', bookletOr, boldValue: true, monoValue: true),
          metaRow('TXN No.:', txnNo, monoValue: true),
          metaRow('Date:', dateTimeStr),
          metaRow('Payor:', customerName, boldValue: true),
          metaRow('Type:', customerType),

          dashedDivider(),

          // 3. Itemized Fee Lines
          feeLine('Veterinary Health Certificate ($billableHeads)', fmtAmt(fees['vet_health_cert'] as num?)),
          feeLine('Permit to Slaughter ($billableHeads)', fmtAmt(fees['permit_to_slaughter'] as num?)),
          feeLine('Facility Fee ($billableHeads)', fmtAmt(fees['facility'] as num?)),
          feeLine('Corral Fee ($billableHeads)', fmtAmt(fees['corral'] as num?)),
          feeLine('Ante-Mortem Fee ($billableHeads)', fmtAmt(fees['ante_mortem'] as num?)),
          feeLine('Post-Mortem Fee (${weight.toStringAsFixed(0)})', fmtAmt(fees['post_mortem'] as num?)),
          if (!isBarangay)
            feeLine('Delivery Van Fee ($billableHeads)', fmtAmt(fees['delivery_van'] as num?)),
          if (additionalFee > 0)
            feeLine('${fees['additional_fee_label'] ?? 'Additional Surcharge'} (1)', fmtAmt(additionalFee)),
          if (overduePenalty > 0)
            feeLine('Overdue Payment Penalty (1)', fmtAmt(overduePenalty), bold: true),
          if (coldStoragePenalty > 0)
            feeLine('Cold Storage Penalty Fee (1)', fmtAmt(coldStoragePenalty), bold: true),
          if (penaltyFee > 0)
            feeLine('Missed Schedule Penalty (1)', fmtAmt(penaltyFee), bold: true)
          else if (isWarningOnly)
            feeLine('Missed Schedule Notice (1st Offense)', '${currency}0.00'),

          dashedDivider(),

          // 4. Totals & Payment Summary
          feeLine(
            status == 'Verified' ? 'TOTAL PAID:' : 'TOTAL DUE:',
            fmtAmt(totalAmount),
            bold: true,
            fontSize: titleSize,
          ),
          pw.SizedBox(height: 2),
          feeLine(
            'Tendered ($methodLabel):',
            fmtAmt(status == 'Verified' ? tenderedAmount : 0.0),
          ),
          feeLine(
            'Change:',
            fmtAmt(status == 'Verified' ? changeAmount : 0.0),
          ),

          dashedDivider(color: PdfColor.fromHex('#CBD5E1')),

          // 5. Footer Note
          pw.Center(
            child: pw.Text(
              'Present this receipt to the Meat Inspector for MIC issuance.',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: isThermal80mm ? 8.5 : 10.0,
                color: PdfColor.fromHex('#64748B'),
              ),
            ),
          ),
        ],
      );
    }

    if (isThermal80mm) {
      pdf.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(
            80 * PdfPageFormat.mm,
            double.infinity,
            marginAll: 3 * PdfPageFormat.mm,
          ),
          build: (_) => buildReceiptBody(),
        ),
      );
    } else {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(8 * PdfPageFormat.mm),
          build: (_) => pw.Center(
            child: pw.Container(
              width: 360,
              padding: const pw.EdgeInsets.all(16),
              child: buildReceiptBody(),
            ),
          ),
        ),
      );
    }

    return pdf.save();
  }
}

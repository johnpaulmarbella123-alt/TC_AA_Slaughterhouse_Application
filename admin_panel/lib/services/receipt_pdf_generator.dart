import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ReceiptPdfGenerator {
  static Future<Uint8List> generate({
    required Map<String, dynamic> req,
    required Map<String, dynamic> fees,
    required String receiptNo,
    required String refNo,
    required String status,
    required String method,
    required double weight,
  }) async {
    pw.Font? regularFont;
    pw.Font? boldFont;
    String currency = '\u20b1';
    try {
      regularFont = await PdfGoogleFonts.notoSansRegular();
      boldFont = await PdfGoogleFonts.notoSansBold();
    } catch (_) {
      currency = 'PHP ';
    }

    final pdf = pw.Document(
      theme: (regularFont != null && boldFont != null)
          ? pw.ThemeData.withFont(base: regularFont, bold: boldFont)
          : null,
    );

    final isBarangay = req['request_type'] == 'barangay';
    final typeLabel = isBarangay ? 'BARANGAY' : 'MARKET';
    final payment = req['payment'] as Map<String, dynamic>?;
    final tracking = req['penalty_tracking'] as Map<String, dynamic>?;

    final now = DateTime.now();
    final dateStr = DateFormat('M/dd/yyyy').format(now);
    final timeStr = DateFormat('h:mm:ss a').format(now);

    final customerName = (req['customer_name'] ?? '\u2014').toString();
    final livestockType = (req['livestock_type'] ?? '\u2014').toString();
    final animalCount = (req['animal_count'] ?? 1).toString();
    final weightStr = weight > 0 ? '${weight.toStringAsFixed(0)} kg' : '\u2014';
    final cashierName = (payment?['cashier_name'] ?? 'Admin').toString();

    final authName = (req['authorized_person_name'] ?? '').toString().trim();
    final authContact = (req['authorized_person_contact'] ?? '').toString().trim();
    final authRel = (req['authorized_person_relationship'] ?? '').toString().trim();
    final authIdType = (req['authorized_person_id_type'] ?? '').toString().trim();
    final authIdNum = (req['authorized_person_id_num'] ?? '').toString().trim();
    final hasAuth = authName.isNotEmpty;

    String fmtAmt(num? val) => '$currency${(val ?? 0).toDouble().toStringAsFixed(2)}';

    final additionalFee = (fees['additional_fee'] as num?)?.toDouble() ?? 0.0;
    final overduePenalty = (fees['overdue_penalty'] as num?)?.toDouble() ?? 0.0;
    final coldStoragePenalty = (fees['cold_storage_penalty'] as num?)?.toDouble() ?? 0.0;
    final penaltyFee = (fees['penalty_fee'] as num?)?.toDouble() ?? 0.0;
    final ratePerKg = (fees['rate_per_kg'] as num?)?.toDouble() ?? 5.0;
    final isWarningOnly = tracking?['is_warning_only'] == true ||
        req['is_warning_only'] == true ||
        (req['process_notes'] ?? '').toString().contains('1ST OFFENSE');
    final coldStorageUnpaid = fees['cold_storage_unpaid_on_paid_order'] == true;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 64, vertical: 40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Title (matches dialog)
              pw.Center(
                child: pw.Text(
                  'Payment  Receipt for "$typeLabel"',
                  style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 18),

              // Receipt Info
              pw.Text('Receipt Number: $receiptNo', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              pw.Text('Date: $dateStr', style: const pw.TextStyle(fontSize: 11)),
              pw.Text('Time: $timeStr', style: const pw.TextStyle(fontSize: 11)),
              pw.SizedBox(height: 14),

              // Customer Info
              pw.Text('CUSTOMER INFORMATION:', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.Text('Name: $customerName', style: const pw.TextStyle(fontSize: 11)),
              pw.Text('Reference: $refNo', style: const pw.TextStyle(fontSize: 11)),
              pw.SizedBox(height: 14),

              // Livestock Info
              pw.Text('LIVESTOCK INFORMATION:', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.Text('Animal Type: $livestockType', style: const pw.TextStyle(fontSize: 11)),
              pw.Text('Count: $animalCount', style: const pw.TextStyle(fontSize: 11)),
              pw.Text('Weight: $weightStr', style: const pw.TextStyle(fontSize: 11)),
              pw.SizedBox(height: 14),

              // Fee Breakdown
              pw.Text('Payment Calculation Preview', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              _feeRow('Veterinary Health Certificate:', fmtAmt(fees['vet_health_cert'] as num?)),
              _feeRow('Permit to Slaughter:', fmtAmt(fees['permit_to_slaughter'] as num?)),
              _feeRow('Facility Fee:', fmtAmt(fees['facility'] as num?)),
              _feeRow('Corral Fee:', fmtAmt(fees['corral'] as num?)),
              _feeRow('Ante-Mortem Fee:', fmtAmt(fees['ante_mortem'] as num?)),
              _feeRow(
                'Post-Mortem (${weight.toStringAsFixed(0)} kg @ $currency${ratePerKg.toStringAsFixed(2)}/kg):',
                fmtAmt(fees['post_mortem'] as num?),
              ),
              if (additionalFee > 0)
                _feeRow(
                  '${fees['additional_fee_label'] ?? 'Additional Surcharge'}:',
                  fmtAmt(additionalFee),
                ),
              if (overduePenalty > 0)
                _feeRow(
                  'Overdue Payment Penalty (Past 5:00 PM):',
                  fmtAmt(overduePenalty),
                  bold: true,
                ),
              if (coldStoragePenalty > 0)
                _feeRow(
                  'Cold Storage Penalty Fee (Unclaimed Past 5:00 PM):',
                  fmtAmt(coldStoragePenalty),
                  bold: true,
                ),
              if (penaltyFee > 0)
                _feeRow(
                  'Missed Schedule Slot Penalty (Repeat Offense):',
                  fmtAmt(penaltyFee),
                  bold: true,
                  color: PdfColor.fromHex('#B91C1C'),
                )
              else if (isWarningOnly)
                _feeRow(
                  'Missed Schedule Notice (1st Offense):',
                  'Warning Issued (${currency}0.00 Waived)',
                  color: PdfColor.fromHex('#B45309'),
                ),

              pw.SizedBox(height: 6),
              pw.Divider(color: PdfColors.grey300, thickness: 0.8),
              _feeRow('Subtotal:', fmtAmt(fees['subtotal'] as num?), bold: true),
              if (!isBarangay) _feeRow('Delivery Van Fee:', fmtAmt(fees['delivery_van'] as num?)),
              pw.SizedBox(height: 4),
              pw.Divider(color: PdfColors.grey400, thickness: 0.8),
              pw.SizedBox(height: 2),
              _feeRow('TOTAL AMOUNT:', fmtAmt(fees['total'] as num?), bold: true, large: true),
              pw.SizedBox(height: 8),

              if (coldStorageUnpaid) ...[
                _feeRow('AMOUNT PAID (${method.toUpperCase()}):', fmtAmt(fees['amount_paid'] as num?), bold: true),
                _feeRow('BALANCE (COLD STORAGE FEE DUE AT PICKUP):', '${currency}150.00', bold: true),
              ] else
                _feeRow(
                  'BALANCE:',
                  status == 'Verified' ? '0' : fmtAmt(fees['total'] as num?),
                  bold: true,
                ),
              pw.SizedBox(height: 12),

              // Payment Details
              if (status == 'Verified') ...[
                pw.Text('Payment Method: ${method.toUpperCase()}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.Text(
                  coldStorageUnpaid
                      ? 'Status: PAID (BASE FEES) • ${currency}150.00 COLD STORAGE FEE DUE AT PICKUP'
                      : 'Status: PAID',
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 6),
                pw.Text('Cashier: $cashierName', style: const pw.TextStyle(fontSize: 11)),
                if (isBarangay) ...[
                  pw.SizedBox(height: 12),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#F0FDF4'),
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: PdfColor.fromHex('#86EFAC')),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'MEAT PICKUP AUTHORIZATION: GRANTED',
                          style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#15803D')),
                        ),
                        pw.SizedBox(height: 4),
                        if (hasAuth) ...[
                          pw.Text(
                            'Authorized Person for Pickup: $authName${authRel.isNotEmpty ? ' ($authRel)' : ''}',
                            style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1E293B')),
                          ),
                          if (authContact.isNotEmpty)
                            pw.Text('Contact: $authContact', style: pw.TextStyle(fontSize: 9.5, color: PdfColor.fromHex('#475569'))),
                          if (authIdType.isNotEmpty || authIdNum.isNotEmpty)
                            pw.Text('Valid ID: $authIdType \u2014 $authIdNum', style: pw.TextStyle(fontSize: 9.5, color: PdfColor.fromHex('#475569'))),
                        ] else
                          pw.Text(
                            'Authorized Person for Pickup: ${req['customer_name'] ?? 'Customer'} (Customer Direct)',
                            style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1E293B')),
                          ),
                      ],
                    ),
                  ),
                ],
              ] else ...[
                pw.Text(
                  'Payment Method: ${method != '\u2014' && method.isNotEmpty ? method : 'Pending'}',
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  'Status: $status',
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
              ],
              pw.SizedBox(height: 18),
              pw.Text('Thank you!', style: const pw.TextStyle(fontSize: 11)),
              pw.Text(
                'Tabaco City Slaughterhouse',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _feeRow(
    String label,
    String amount, {
    bool bold = false,
    bool large = false,
    PdfColor? color,
  }) {
    final style = pw.TextStyle(
      fontSize: large ? 12 : 11,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text(amount, style: style),
        ],
      ),
    );
  }
}

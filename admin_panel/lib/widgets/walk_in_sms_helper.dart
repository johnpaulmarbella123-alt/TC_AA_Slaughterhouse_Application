import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/audit_log_service.dart';

/// Reusable Walk-In Phone / SMS Notification helper for Tabaco City "AA" Slaughterhouse.
/// Replaces printed claim stubs with a direct, zero-printer SMS / Phone feedback workflow
/// using the walk-in customer's recorded `contact_number`.
class WalkInSmsHelper {
  /// Builds a clean default SMS message tailored to the current operational stage.
  static String buildDefaultMessage({
    required String stage,
    required String refNo,
    required String customerName,
    required String marking,
    String livestockType = '',
    int animalCount = 1,
    String statusSummary = '',
    String amountDue = '',
  }) {
    final headLabel = '$animalCount ${animalCount == 1 ? 'head' : 'heads'}';
    final animalInfo = livestockType.isNotEmpty ? '$headLabel of $livestockType' : headLabel;
    final markPart = marking.isNotEmpty ? ', Marking: $marking' : '';

    switch (stage.toLowerCase()) {
      case 'receiving':
        return 'Tabaco City AA Slaughterhouse: Hello $customerName, your walk-in request '
            '(Ref: $refNo$markPart) for $animalInfo has been received. '
            'We will notify you on this number for inspection, billing, and meat release updates.';
      case 'inspection':
        final detail = statusSummary.isNotEmpty ? statusSummary : 'Slaughter & inspection update recorded';
        return 'Tabaco City AA Slaughterhouse: Hello $customerName, inspection update for '
            'Ref: $refNo$markPart ($animalInfo) — $detail. '
            'Please contact the Abattoir Office if you have questions.';
      case 'payment':
        final amtPart = amountDue.isNotEmpty ? ' Total fee: $amountDue.' : '';
        return 'Tabaco City AA Slaughterhouse: Hello $customerName, billing for your request '
            '(Ref: $refNo$markPart) is ready.$amtPart '
            'Please settle payment at the Abattoir Cashier window for meat release.';
      case 'releasing':
        return 'Tabaco City AA Slaughterhouse: Hello $customerName, your meat carcass '
            '(Ref: $refNo$markPart, $animalInfo) is cleared and ready for pickup/release '
            'at the Tabaco City Abattoir releasing bay. Please present this reference number.';
      default:
        return 'Tabaco City AA Slaughterhouse: Status update for $customerName '
            '(Ref: $refNo$markPart) — ${statusSummary.isNotEmpty ? statusSummary : "Updated"}.';
    }
  }

  /// Compact icon button to drop into any operational table/card row when a request has a phone number.
  static Widget buildNotifyButton({
    required BuildContext context,
    required String contactNumber,
    required String stage,
    required String refNo,
    required String customerName,
    String marking = '',
    String livestockType = '',
    int animalCount = 1,
    String statusSummary = '',
    String amountDue = '',
    String? requestId,
  }) {
    final phone = contactNumber.trim();
    if (phone.isEmpty) return const SizedBox.shrink();

    return Tooltip(
      message: 'Notify Walk-In Customer via SMS ($phone)',
      child: IconButton(
        onPressed: () => showSmsFeedbackDialog(
          context: context,
          contactNumber: phone,
          stage: stage,
          refNo: refNo,
          customerName: customerName,
          marking: marking,
          livestockType: livestockType,
          animalCount: animalCount,
          statusSummary: statusSummary,
          amountDue: amountDue,
          requestId: requestId,
        ),
        icon: const Icon(Icons.sms_outlined, size: 18, color: Color(0xFF0F5132)),
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFFD1FAE5),
          padding: const EdgeInsets.all(6),
          minimumSize: const Size(32, 32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  /// Opens an editable SMS notification dialog with 1-click Copy Message, Copy Phone,
  /// Open SMS App (`sms:`), and automatic Audit Trail logging.
  static Future<void> showSmsFeedbackDialog({
    required BuildContext context,
    required String contactNumber,
    required String stage,
    required String refNo,
    required String customerName,
    String marking = '',
    String livestockType = '',
    int animalCount = 1,
    String statusSummary = '',
    String amountDue = '',
    String? requestId,
  }) async {
    final phone = contactNumber.trim();
    final msgCtrl = TextEditingController(
      text: buildDefaultMessage(
        stage: stage,
        refNo: refNo,
        customerName: customerName,
        marking: marking,
        livestockType: livestockType,
        animalCount: animalCount,
        statusSummary: statusSummary,
        amountDue: amountDue,
      ),
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Container(
          width: 520,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1FAE5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.sms_outlined, color: Color(0xFF0F5132), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Walk-In Customer SMS / Phone Update',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$customerName • Ref: $refNo',
                          style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Color(0xFF64748B)),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F6F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.phone_outlined, size: 18, color: Color(0xFF0F5132)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SelectableText(
                        phone.isNotEmpty ? phone : 'No phone number recorded',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    if (phone.isNotEmpty)
                      TextButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: phone));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Phone number copied: $phone'),
                              backgroundColor: const Color(0xFF0F5132),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 14),
                        label: const Text('Copy No.', style: TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'SMS Status / Feedback Message (editable)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: msgCtrl,
                maxLines: 4,
                style: const TextStyle(fontSize: 13.5, color: Color(0xFF0F172A), height: 1.4),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (phone.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final body = Uri.encodeComponent(msgCtrl.text.trim());
                        final uri = Uri.parse('sms:$phone?body=$body');
                        await AuditLogService.instance.log(
                          action: 'WALKIN_SMS_NOTIFIED',
                          module: stage.toUpperCase(),
                          targetId: requestId ?? refNo,
                          details: {
                            'method': 'sms_app',
                            'customer_name': customerName,
                            'contact_number': phone,
                            'ref_no': refNo,
                          },
                        );
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        } else if (context.mounted) {
                          Clipboard.setData(ClipboardData(text: msgCtrl.text.trim()));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('SMS app not available on desktop — message copied to clipboard!'),
                              backgroundColor: Color(0xFF0F5132),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.send_outlined, size: 16),
                      label: const Text('Open SMS App'),
                    ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: msgCtrl.text.trim()));
                      await AuditLogService.instance.log(
                        action: 'WALKIN_SMS_NOTIFIED',
                        module: stage.toUpperCase(),
                        targetId: requestId ?? refNo,
                        details: {
                          'method': 'copy_sms',
                          'customer_name': customerName,
                          'contact_number': phone,
                          'ref_no': refNo,
                        },
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('SMS update copied for $customerName ($phone)'),
                            backgroundColor: const Color(0xFF0F5132),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy SMS Update'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F5132),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    msgCtrl.dispose();
  }
}

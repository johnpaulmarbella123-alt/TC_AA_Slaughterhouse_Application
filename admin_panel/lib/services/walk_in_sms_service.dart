import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'audit_log_service.dart';

/// Dispatches real SMS notifications to Walk-In customers via the
/// `send-walkin-sms` Supabase Edge Function (backed by TextBee).
class WalkInSmsService {
  static Future<({bool success, String message})> sendSms({
    required String phone,
    required String message,
    required String stage,
    required String refNo,
    required String customerName,
    String? requestId,
  }) async {
    final cleanPhone = phone.trim();
    final cleanMsg = message.trim();
    if (cleanPhone.isEmpty || cleanMsg.isEmpty) {
      return (success: false, message: 'Phone number and message are required.');
    }

    try {
      final res = await Supabase.instance.client.functions.invoke(
        'send-walkin-sms',
        body: {
          'phone': cleanPhone,
          'message': cleanMsg,
          'stage': stage,
          'ref_no': refNo,
          'request_id': ?requestId,
        },
      );

      final data = res.data;
      final ok = res.status >= 200 &&
          res.status < 300 &&
          (data is! Map || data['success'] != false);

      if (ok) {
        await AuditLogService.instance.log(
          action: 'WALKIN_SMS_SENT',
          module: stage.toUpperCase(),
          targetId: requestId ?? refNo,
          details: {
            'provider': 'textbee',
            'customer_name': customerName,
            'contact_number': cleanPhone,
            'ref_no': refNo,
          },
        );
        return (
          success: true,
          message: 'SMS sent to $customerName ($cleanPhone)',
        );
      }

      final errMsg = (data is Map && data['error'] != null)
          ? data['error'].toString()
          : 'Failed to send SMS (HTTP ${res.status})';
      await AuditLogService.instance.log(
        action: 'WALKIN_SMS_FAILED',
        module: stage.toUpperCase(),
        targetId: requestId ?? refNo,
        details: {
          'provider': 'textbee',
          'customer_name': customerName,
          'contact_number': cleanPhone,
          'ref_no': refNo,
          'error': errMsg,
        },
      );
      return (success: false, message: errMsg);
    } catch (e) {
      debugPrint('WalkInSmsService.sendSms error: $e');
      await AuditLogService.instance.log(
        action: 'WALKIN_SMS_FAILED',
        module: stage.toUpperCase(),
        targetId: requestId ?? refNo,
        details: {
          'provider': 'textbee',
          'customer_name': customerName,
          'contact_number': cleanPhone,
          'ref_no': refNo,
          'error': e.toString(),
        },
      );
      return (success: false, message: 'SMS delivery error: $e');
    }
  }
}

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_settings_service.dart';
import 'audit_log_service.dart';
import 'regular_dealers_service.dart';

/// Dispatches real SMS notifications to Walk-In customers via the
/// `send-walkin-sms` Supabase Edge Function (Semaphore / TextBee).
class WalkInSmsService {
  /// Returns true when [req] represents a walk-in customer (no mobile app user_id,
  /// tagged `[WALK_IN]`, or has a direct `contact_number`).
  static bool isWalkInRequest(Map<String, dynamic>? req) {
    if (req == null) return false;
    final uid = (req['user_id'] ?? '').toString().trim();
    final instr = (req['special_instruction'] ?? '').toString();
    final direct = (req['contact_number'] ?? '').toString().trim();
    return uid.isEmpty || instr.contains('[WALK_IN]') || direct.isNotEmpty;
  }

  /// Resolves a walk-in customer's phone number from:
  /// 1. `requests.contact_number`
  /// 2. `[PHONE:...]` tag in `requests.special_instruction`
  /// 3. Their registered phone in `RegularDealersService`
  static String resolveWalkInPhone(Map<String, dynamic>? req) {
    if (req == null) return '';
    final direct = (req['contact_number'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;

    final instr = (req['special_instruction'] ?? '').toString();
    final phoneMatch = RegExp(r'\[PHONE:([^\]]+)\]').firstMatch(instr);
    if (phoneMatch != null) {
      final embedded = (phoneMatch.group(1) ?? '').trim();
      if (embedded.isNotEmpty) return embedded;
    }

    if (!isWalkInRequest(req)) return '';

    final custName = (req['customer_name'] ?? '').toString().trim();
    final marking = (req['marking'] ?? req['customer_marking'] ?? '').toString().trim();
    final dealer = RegularDealersService.instance.findAuthoritativeDealer(
      customerName: custName,
      marking: marking,
    );
    return (dealer?.phone ?? '').trim();
  }

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
      // Ensure active Supabase JWT session before invoking Edge Function
      await AppSettingsService.instance.ensureAdminAuthSession();

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

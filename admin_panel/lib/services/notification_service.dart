import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  /// Safely sends a notification without blocking or failing the parent operation
  /// if user_id is null, not found in `profiles`, or foreign key constraints fail.
  static Future<bool> sendNotificationSafely(
    SupabaseClient supabase, {
    required dynamic userId,
    required String title,
    required String message,
    required String type,
    Map<String, dynamic>? data,
    String? referenceNo,
  }) async {
    dynamic resolvedUserId = userId;
    if (resolvedUserId == null || resolvedUserId.toString().trim().isEmpty) {
      // Check if a walk-in customer claimed this order via `system_settings` ('walk_in_claims')
      try {
        dynamic reqId = data?['request_id'];
        if (reqId == null && referenceNo != null && referenceNo.isNotEmpty) {
          final m = RegExp(r'(?:MI-\d{4}-|RCP-\d{4}-|^)(\d+)$')
              .firstMatch(referenceNo.toUpperCase());
          if (m != null) reqId = int.tryParse(m.group(1)!);
        }
        if (reqId != null) {
          final claimsRow = await supabase
              .from('system_settings')
              .select('value')
              .eq('key', 'walk_in_claims')
              .maybeSingle();
          if (claimsRow != null && claimsRow['value'] is Map) {
            final claimsMap = Map<String, dynamic>.from(claimsRow['value']);
            final claimedUid = claimsMap[reqId.toString()];
            if (claimedUid != null && claimedUid.toString().trim().isNotEmpty) {
              resolvedUserId = claimedUid.toString().trim();
              try {
                await supabase
                    .from('requests')
                    .update({'user_id': resolvedUserId})
                    .eq('id', reqId);
              } catch (_) {}
            }
          }
        }
      } catch (_) {}
    }

    if (resolvedUserId == null || resolvedUserId.toString().trim().isEmpty) {
      debugPrint('Notification skipped: user_id is null or empty');
      return false;
    }

    try {
      final payload = <String, dynamic>{
        'user_id': resolvedUserId,
        'title': title,
        'message': message,
        'is_read': false,
        'type': type,
      };
      if (data != null) {
        payload['data'] = data;
      }
      if (referenceNo != null && referenceNo.isNotEmpty) {
        payload['reference_no'] = referenceNo;
      }

      await supabase.from('notifications').insert(payload);
      return true;
    } catch (e) {
      debugPrint('Notification skipped or failed (safe fallback): $e');
      return false;
    }
  }
}

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
    final resolvedUserId = userId;
    if (resolvedUserId == null || resolvedUserId.toString().trim().isEmpty) {
      debugPrint('Notification skipped: Walk-In customer (user_id is null or empty)');
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

      // Fire-and-forget real-time push notification to customer's phone (even when app is closed)
      supabase.functions
          .invoke(
            'send-push-notification',
            body: {
              'user_id': resolvedUserId.toString(),
              'title': title,
              'message': message,
              'type': type,
              if (referenceNo != null && referenceNo.isNotEmpty)
                'reference_no': referenceNo,
              'data': ?data,
            },
          )
          .then((res) {
            debugPrint('Push notification dispatch result (${res.status}): ${res.data}');
            return res;
          })
          .catchError((e) {
            debugPrint('Push notification dispatch notice (non-blocking): $e');
            return FunctionResponse(status: 200);
          });

      return true;
    } catch (e) {
      debugPrint('Notification skipped or failed (safe fallback): $e');
      return false;
    }
  }
}

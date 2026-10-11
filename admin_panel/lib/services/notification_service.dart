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
    if (userId == null || userId.toString().trim().isEmpty) {
      debugPrint('Notification skipped: user_id is null or empty');
      return false;
    }

    try {
      final payload = <String, dynamic>{
        'user_id': userId,
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

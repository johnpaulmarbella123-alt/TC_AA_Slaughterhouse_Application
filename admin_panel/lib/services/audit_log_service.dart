import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_settings_service.dart';

/// Immutable staff activity audit logger backed by `public.audit_logs`.
class AuditLogService {
  AuditLogService._();
  static final AuditLogService instance = AuditLogService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Records a staff operational event. Never throws so business flows remain resilient.
  Future<void> log({
    required String action,
    required String module,
    String? targetId,
    String? targetRef,
    Map<String, dynamic>? details,
  }) async {
    try {
      final settings = AppSettingsService.instance;
      final authUser = _supabase.auth.currentUser;

      final actorEmail = (settings.activeStaffOverrideEmail?.trim().isNotEmpty ?? false)
          ? settings.activeStaffOverrideEmail!.trim()
          : (settings.profileEmail.trim().isNotEmpty
              ? settings.profileEmail.trim()
              : (authUser?.email ?? 'unknown@tcaa.gov.ph'));

      final actorName = settings.profileName.trim().isNotEmpty
          ? settings.profileName.trim()
          : actorEmail;

      final actorRole = StaffAccount.normalizeRole(settings.currentRole);

      await _supabase.from('audit_logs').insert({
        'actor_id': authUser?.id,
        'actor_email': actorEmail,
        'actor_name': actorName,
        'actor_role': actorRole,
        'action': action,
        'module': module,
        if (targetId != null && targetId.isNotEmpty) 'target_id': targetId,
        if (targetRef != null && targetRef.isNotEmpty) 'target_ref': targetRef,
        'details': details ?? <String, dynamic>{},
      });
    } catch (e) {
      debugPrint('AuditLogService.log skipped: $e');
    }
  }

  /// Fetches audit log entries (Admin-only via RLS), ordered newest first.
  Future<List<Map<String, dynamic>>> fetchLogs({
    DateTimeRange? range,
    String? module,
    String? search,
    int limit = 500,
  }) async {
    try {
      dynamic query = _supabase.from('audit_logs').select();

      if (module != null && module.isNotEmpty && module != 'All') {
        query = query.eq('module', module);
      }

      if (range != null) {
        final startUtc = DateTime(
          range.start.year,
          range.start.month,
          range.start.day,
          0,
          0,
          0,
        ).toUtc().toIso8601String();
        final endUtc = DateTime(
          range.end.year,
          range.end.month,
          range.end.day,
          23,
          59,
          59,
          999,
        ).toUtc().toIso8601String();
        query = query.gte('created_at', startUtc).lte('created_at', endUtc);
      }

      final rows = await query.order('created_at', ascending: false).limit(limit);
      final list = List<Map<String, dynamic>>.from(rows as List);

      if (search != null && search.trim().isNotEmpty) {
        final q = search.trim().toLowerCase();
        return list.where((row) {
          final haystack = [
            row['actor_name'],
            row['actor_email'],
            row['actor_role'],
            row['action'],
            row['module'],
            row['target_ref'],
            row['target_id'],
            row['details']?.toString(),
          ].whereType<Object>().map((e) => e.toString().toLowerCase()).join(' ');
          return haystack.contains(q);
        }).toList();
      }

      return list;
    } catch (e) {
      debugPrint('AuditLogService.fetchLogs error: $e');
      rethrow;
    }
  }
}

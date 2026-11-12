import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_settings_service.dart';

/// A single staff bell notification (row of `staff_notifications`).
class StaffNotification {
  final int id;
  final String targetRole;
  final String type; // 'new_request' | 'doc_verified'
  final String title;
  final String message;
  final int? requestId;
  final String? referenceNo;
  final List<String> readBy;
  final DateTime createdAt;

  StaffNotification({
    required this.id,
    required this.targetRole,
    required this.type,
    required this.title,
    required this.message,
    required this.requestId,
    required this.referenceNo,
    required this.readBy,
    required this.createdAt,
  });

  factory StaffNotification.fromMap(Map<String, dynamic> m) {
    return StaffNotification(
      id: (m['id'] as num).toInt(),
      targetRole: m['target_role']?.toString() ?? '',
      type: m['type']?.toString() ?? '',
      title: m['title']?.toString() ?? '',
      message: m['message']?.toString() ?? '',
      requestId: (m['request_id'] as num?)?.toInt(),
      referenceNo: m['reference_no']?.toString(),
      readBy: (m['read_by'] as List?)?.map((e) => e.toString().toLowerCase()).toList() ?? <String>[],
      createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
    );
  }

  bool isReadBy(String email) => readBy.contains(email.toLowerCase());

  /// Sidebar module the notification should open.
  /// 1 = Receiving & New Requests, 3 = Slaughter & Inspection
  int get targetModule => type == 'doc_verified' ? 3 : 1;
}

/// Loads and live-updates staff notifications for the active role.
/// Admin -> Clerk + Inspector, Clerk -> Clerk, Inspector -> Inspector.
class StaffNotificationService extends ChangeNotifier {
  StaffNotificationService._();
  static final StaffNotificationService instance = StaffNotificationService._();

  static const int _limit = 30;

  SupabaseClient get _supabase => Supabase.instance.client;

  List<StaffNotification> _items = [];
  List<StaffNotification> get items => List.unmodifiable(_items);

  RealtimeChannel? _channel;
  Timer? _pollTimer;
  bool _started = false;
  String _activeRole = '';

  String get _email {
    final s = AppSettingsService.instance;
    return (s.activeStaffOverrideEmail ?? s.profileEmail).trim().toLowerCase();
  }

  static List<String> rolesFor(String role) {
    switch (role) {
      case 'Clerk':
        return const ['Clerk'];
      case 'Inspector':
        return const ['Inspector'];
      default:
        return const ['Clerk', 'Inspector']; // Admin
    }
  }

  int get unreadCount {
    final e = _email;
    return _items.where((n) => !n.isReadBy(e)).length;
  }

  bool isUnread(StaffNotification n) => !n.isReadBy(_email);

  void start() {
    if (_started) return;
    _started = true;
    _activeRole = AppSettingsService.instance.currentRole;
    AppSettingsService.instance.addListener(_onSettingsChanged);
    _subscribe();
    refresh();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => refresh());
  }

  void stop() {
    if (!_started) return;
    _started = false;
    AppSettingsService.instance.removeListener(_onSettingsChanged);
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_channel != null) {
      _supabase.removeChannel(_channel!);
      _channel = null;
    }
    _items = [];
    notifyListeners();
  }

  void _onSettingsChanged() {
    final role = AppSettingsService.instance.currentRole;
    if (role != _activeRole) {
      _activeRole = role;
      _items = [];
      notifyListeners();
      refresh();
    }
  }

  void _subscribe() {
    try {
      _channel = _supabase
          .channel('public:staff_notifications_bell')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'staff_notifications',
            callback: (_) => refresh(),
          )
          .subscribe();
    } catch (e) {
      debugPrint('StaffNotificationService realtime error: $e');
    }
  }

  Future<void> refresh() async {
    try {
      final roles = rolesFor(AppSettingsService.instance.currentRole);
      final res = await _supabase
          .from('staff_notifications')
          .select()
          .inFilter('target_role', roles)
          .order('created_at', ascending: false)
          .limit(_limit);
      _items = (res as List)
          .map((m) => StaffNotification.fromMap(Map<String, dynamic>.from(m)))
          .toList();
      notifyListeners();
    } catch (e) {
      // Table may not exist yet (migration not applied) — fail quietly.
      debugPrint('StaffNotificationService refresh error: $e');
    }
  }

  Future<void> markRead(List<int> ids) async {
    final e = _email;
    if (ids.isEmpty || e.isEmpty) return;

    // Optimistic local update
    _items = _items.map((n) {
      if (ids.contains(n.id) && !n.isReadBy(e)) {
        return StaffNotification(
          id: n.id,
          targetRole: n.targetRole,
          type: n.type,
          title: n.title,
          message: n.message,
          requestId: n.requestId,
          referenceNo: n.referenceNo,
          readBy: [...n.readBy, e],
          createdAt: n.createdAt,
        );
      }
      return n;
    }).toList();
    notifyListeners();

    try {
      await _supabase.rpc('mark_staff_notifications_read', params: {
        'p_ids': ids,
        'p_email': e,
      });
    } catch (err) {
      debugPrint('StaffNotificationService markRead error: $err');
    }
  }

  Future<void> markAllRead() async {
    final e = _email;
    final ids = _items.where((n) => !n.isReadBy(e)).map((n) => n.id).toList();
    await markRead(ids);
  }
}


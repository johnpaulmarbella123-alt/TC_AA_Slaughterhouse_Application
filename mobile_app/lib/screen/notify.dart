import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../pages/home_page.dart' show globalUnreadNotifCount;
import 'condemnation_slip_screen.dart';
import 'notification_options_dialog.dart';
import 'receipt_detail_screen.dart';
import 'view_status_update_screen.dart';

class NotifyPage extends StatefulWidget {
  /// Callback to switch bottom-nav tab (e.g. index 1 = Requests).
  /// Passed from HomeScreen so notification actions can navigate tabs.
  final void Function(int tabIndex)? onNavigateToTab;

  /// Increment this to force a notification reload (e.g. when switching tabs).
  final ValueNotifier<int>? refreshTrigger;

  const NotifyPage({super.key, this.onNavigateToTab, this.refreshTrigger});

  @override
  State<NotifyPage> createState() => _NotifyPageState();
}

class _NotifyPageState extends State<NotifyPage> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> notifications = [];
  Map<String, dynamic>? _activeRequest;
  bool isLoading = true;
  bool showUnreadOnly = false;
  bool _userSwitchedTab = false;

  RealtimeChannel? _notifChannel;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _loadActiveRequest();
    _subscribeRealtime();
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) {
        _loadNotifications();
        _loadActiveRequest();
      }
    });
    widget.refreshTrigger?.addListener(_onRefreshTriggered);
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    widget.refreshTrigger?.removeListener(_onRefreshTriggered);
    if (_notifChannel != null) {
      supabase.removeChannel(_notifChannel!);
    }
    super.dispose();
  }

  void _onRefreshTriggered() {
    _loadNotifications();
    _loadActiveRequest();
  }

  // =========================
  // LOAD ACTIVE REQUEST (FOR STATUS UPDATE BANNER)
  // Visible once approved, disappears once meat is released or completed
  // =========================
  Future<void> _loadActiveRequest() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final reqs = await supabase
          .from('requests')
          .select('*, slaughter_inspection(*), payments(*)')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(5);

      final activeList = (reqs as List).where((r) {
        final status = (r['status'] ?? '').toString().toLowerCase();
        // Visible once admin approved, disappears once meat is released/completed or cancelled
        return [
          'approved',
          'doc_verified',
          'slaughter_started',
          'in_progress',
          'releasable',
          'payment_pending',
          'paid'
        ].contains(status);
      }).toList();

      if (mounted) {
        setState(() {
          _activeRequest = activeList.isNotEmpty ? activeList.first : null;
        });
      }
    } catch (e) {
      debugPrint("Active request load error: $e");
    }
  }

  // =========================
  // LOAD NOTIFICATIONS
  // =========================
  Future<void> _loadNotifications() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final data = await supabase
          .from('notifications')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      // Filter out duplicate "Report filed successfully" since the
      // official "🚨 Illegal Slaughter Report Filed" notification is used instead
      final cleanedList = List<Map<String, dynamic>>.from(data).where((n) {
        final title = (n['title'] ?? '').toString().trim().toLowerCase();
        return !title.contains('report filed successfully');
      }).toList();

      // Silently clean up any duplicate records from Supabase in the background
      try {
        await supabase
            .from('notifications')
            .delete()
            .eq('user_id', user.id)
            .ilike('title', '%report filed successfully%');
      } catch (_) {}

      if (mounted) {
        setState(() {
          notifications = cleanedList;
          isLoading = false;
          // New unread notifications go to Unread tab; only switch if user hasn't explicitly selected
          if (!_userSwitchedTab) {
            final hasUnread = notifications.any((n) => !_asBool(n['is_read']));
            showUnreadOnly = hasUnread;
          }
        });
        _syncGlobalUnreadCount();
      }
    } catch (e) {
      debugPrint("Notification load error: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  // =========================
  // REALTIME SUBSCRIPTION
  // =========================
  void _subscribeRealtime() {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    _notifChannel = supabase.channel('notif-list');
    _notifChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (payload) {
            debugPrint('NOTIFY: Realtime INSERT → reloading list');
            _loadNotifications();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (payload) {
            debugPrint('NOTIFY: Realtime UPDATE → reloading list');
            _loadNotifications();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (payload) {
            debugPrint('NOTIFY: Realtime REQUEST change → reloading active request');
            _loadActiveRequest();
          },
        )
        .subscribe();
  }

  // =========================
  // MARK AS READ
  // =========================
  Future<void> _markAsRead(dynamic id) async {
    // Immediately update local state so UI is instant
    setState(() {
      final idx = notifications.indexWhere((n) => n['id'] == id);
      if (idx != -1) {
        notifications[idx] = {...notifications[idx], 'is_read': true};
      }
    });
    _syncGlobalUnreadCount();
    // Then persist to DB (stream will eventually sync too)
    await supabase.from('notifications').update({'is_read': true}).eq('id', id);
  }

  Future<void> _markAllAsRead() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    // Immediately update local state
    setState(() {
      for (int i = 0; i < notifications.length; i++) {
        notifications[i] = {...notifications[i], 'is_read': true};
      }
    });
    _syncGlobalUnreadCount();
    // Then persist to DB
    await supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', user.id);
  }

  /// Push the current unread count to the global notifier
  /// so the bottom-nav badge updates instantly.
  void _syncGlobalUnreadCount() {
    globalUnreadNotifCount.value = _unreadCount;
  }

  // =========================
  // SAFE VALUE HELPERS
  // These stop one bad/unexpected column value from blanking out
  // or crashing an entire notification card.
  // =========================
  bool _asBool(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is String) return value.toLowerCase() == 'true' || value == '1';
    return fallback;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return {};
  }

  // =========================
  // FILTER
  // "Unread" tab contains new unread notifications.
  // "All" tab contains everything that has already been read.
  // =========================
  List<Map<String, dynamic>> get _filtered => showUnreadOnly
      ? notifications.where((n) => !_asBool(n['is_read'])).toList()
      : notifications.where((n) => _asBool(n['is_read'])).toList();

  int get _unreadCount =>
      notifications.where((n) => !_asBool(n['is_read'])).length;

  // =========================
  // ACTION HANDLER
  // =========================
  void _handleAction(String? type, Map<String, dynamic> data, Map<String, dynamic> notif) {
    switch (type) {
      case 'slaughter_completed':
      case 'doc_verified':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ViewStatusUpdateScreen(
              initialRequest: _activeRequest,
              onNavigateToTab: widget.onNavigateToTab,
            ),
          ),
        );
        break;

      case 'doc_rejected':
        widget.onNavigateToTab?.call(1); // Requests tab to re-submit
        break;

      case 'receipt_issued':
        final requestId = data['request_id'];
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ReceiptDetailScreen(requestId: requestId)),
        );
        break;

      case 'post_mortem_failed':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CondemnationSlipScreen(data: data),
          ),
        );
        break;

      case 'anti_mortem_failed':
        NotificationOptionsDialog.show(
          context: context,
          notifType: 'anti_mortem_failed',
          data: data,
          title: (notif['title'] ?? '').toString(),
          onReschedule: () {
            widget.onNavigateToTab?.call(1);
          },
        );
        break;

      case 'health_issue':
      case 'operation_failed':
        NotificationOptionsDialog.show(
          context: context,
          notifType: type!,
          data: data,
          title: (notif['title'] ?? '').toString(),
          onReschedule: () {
            widget.onNavigateToTab?.call(1); // Requests tab
          },
        );
        break;

      case 'pickup_approved':
        _showPickupApprovedDialog(notif, data);
        break;

      case 'confine_confirmed':
        _showConfineConfirmedDialog(notif, data);
        break;

      case 'request_status_changed':
        final status = data['status'] ?? '';
        if (status == 'approved') {
          // Handled or viewed in status update
        } else {
          _showRescheduleDialog(notif, data);
        }
        break;

      case 'request_rejected':
        _showRescheduleDialog(notif, data);
        break;

      case 'status_update':
      case 'admin_manual':
        _showDetailDialog(notif);
        break;

      case 'meat_delivery':
      case 'meat_pickup':
        _showMeatReleaseDialog(notif, data);
        break;

      default:
        final t = (notif['title'] ?? '').toString().toLowerCase();
        if (t.contains('delivery') || t.contains('pickup')) {
          _showMeatReleaseDialog(notif, data);
        } else if (t.contains('reject') || t.contains('denied')) {
          _showRescheduleDialog(notif, data);
        } else {
          _showDetailDialog(notif);
        }
        break;
    }
  }

  void _showMeatReleaseDialog(Map<String, dynamic> notif, Map<String, dynamic> data) {
    final title = (notif['title'] ?? 'Meat Order Update').toString();
    final message = (notif['message'] ?? notif['body'] ?? '').toString();
    final isDelivery = title.toLowerCase().contains('delivery') ||
        (notif['type'] ?? '') == 'meat_delivery' ||
        (data['release_type'] ?? '') == 'delivery';
    final imagePath = isDelivery
        ? 'assets/images/icon-delivery-truck.png'
        : 'assets/images/icon-meat-box.png';
    final refNo = (data['reference_no'] ?? '').toString();
    final receiptNo = (data['receipt_no'] ?? '').toString();
    final requestId = data['request_id'];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                imagePath,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Icon(
                  isDelivery ? Icons.local_shipping : Icons.inventory_2,
                  size: 20,
                  color: isDelivery ? const Color(0xFF185FA5) : const Color(0xFFB57A00),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
            if (refNo.isNotEmpty || receiptNo.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDelivery ? const Color(0xFFE6F1FB) : const Color(0xFFFFF7E6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDelivery ? const Color(0xFFB6D8F6) : const Color(0xFFFFE0A3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (refNo.isNotEmpty) _pickupRow('Reference #', refNo),
                    if (receiptNo.isNotEmpty) _pickupRow('Receipt #', receiptNo),
                    _pickupRow('Method', isDelivery ? 'Refrigerated Delivery Van' : 'Slaughterhouse Pickup'),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (requestId != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ReceiptDetailScreen(requestId: requestId)),
                );
              },
              child: const Text('View Receipt', style: TextStyle(color: Color(0xFF0A3D2E))),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Color(0xFF0A3D2E))),
          ),
        ],
      ),
    );
  }

  void _showDetailDialog(Map<String, dynamic> notif) {
    final title = (notif['title'] ?? 'Notification').toString();
    final message = (notif['message'] ?? notif['body'] ?? 'No details available.').toString();
    final isIllegalReport = title.toLowerCase().contains('illegal slaughter') ||
        title.toLowerCase().contains('hot meat') ||
        title.toLowerCase().contains('illegal report') ||
        notif['type'] == 'admin_illegal_report' ||
        notif['type'] == 'report_status_update' ||
        notif['type'] == 'report_filed' ||
        notif['type'] == 'report_investigating' ||
        notif['type'] == 'report_resolved';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            if (isIllegalReport) ...[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  'assets/images/icon-illegal-slaughter-report-square.png',
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 13, color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close',
                style: TextStyle(color: Color(0xFF0A3D2E))),
          ),
        ],
      ),
    );
  }

  void _showRescheduleDialog(Map<String, dynamic> notif, Map<String, dynamic> data) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _RescheduleDialog(
        notif: notif,
        data: data,
        onSuccess: () {
          _loadNotifications();
          _loadActiveRequest();
        },
        onNavigateToRequests: () {
          widget.onNavigateToTab?.call(1);
        },
      ),
    );
  }

  void _showPickupApprovedDialog(Map<String, dynamic> notif, Map<String, dynamic> data) {
    final pickupDate = data['pickup_date'] ?? '';
    final pickupTime = data['pickup_time'] ?? '8:00 AM';
    final adminNotes = data['admin_notes'] ?? '';
    final livestock = data['livestock_type'] ?? 'Livestock';

    String formattedDate = pickupDate;
    try {
      if (pickupDate.toString().isNotEmpty) {
        final dt = DateTime.parse(pickupDate.toString());
        formattedDate = '${dt.month}/${dt.day}/${dt.year}';
      }
    } catch (_) {}

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.check_circle, size: 20, color: Colors.green.shade600),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Pickup Approved',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (notif['message'] ?? '').toString(),
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _pickupRow('Livestock', livestock),
                  _pickupRow('Pickup Date', formattedDate),
                  _pickupRow('Pickup Time', pickupTime),
                  _pickupRow('Location', 'Tabaco City Slaughterhouse'),
                  if (adminNotes.toString().isNotEmpty)
                    _pickupRow('Notes', adminNotes.toString()),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Color(0xFF0A3D2E))),
          ),
        ],
      ),
    );
  }

  Widget _pickupRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text('$label:', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        ),
      ],
    ),
  );

  void _showConfineConfirmedDialog(Map<String, dynamic> notif, Map<String, dynamic> data) {
    final newDate = data['new_date'] ?? '';
    final adminNotes = data['admin_notes'] ?? '';
    final livestock = data['livestock_type'] ?? 'Livestock';

    String formattedDate = newDate;
    try {
      if (newDate.toString().isNotEmpty) {
        final dt = DateTime.parse(newDate.toString());
        formattedDate = '${dt.month}/${dt.day}/${dt.year}';
      }
    } catch (_) {}

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFE6F1FB),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/images/confinement_transparent.png',
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    Icon(Icons.local_hospital, size: 20, color: Colors.blue.shade600),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Confinement Confirmed',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (notif['message'] ?? '').toString(),
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _pickupRow('Livestock', livestock),
                  _pickupRow('New Schedule', formattedDate),
                  _pickupRow('Location', 'Tabaco City Slaughterhouse'),
                  if (adminNotes.toString().isNotEmpty)
                    _pickupRow('Notes', adminNotes.toString()),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Color(0xFF0A3D2E))),
          ),
        ],
      ),
    );
  }

  // =========================
  // ICON + BADGE CONFIG
  // =========================
  _NotifStyle _styleFor(String? type, Map data, {String? title}) {
    final t = (title ?? '').toLowerCase();

    // ── ILLEGAL SLAUGHTER REPORTS & STATUS UPDATES ──
    if (type == 'admin_illegal_report' ||
        type == 'report_filed' ||
        type == 'report_status_update' ||
        type == 'report_investigating' ||
        type == 'report_resolved' ||
        t.contains('illegal slaughter') ||
        t.contains('hot meat') ||
        t.contains('illegal report') ||
        (t.contains('report') && (t.contains('filed') || t.contains('compiled') || t.contains('investigat')))) {
      final isStatus = t.contains('status') ||
          type == 'report_status_update' ||
          type == 'report_investigating' ||
          type == 'report_resolved' ||
          t.contains('acknowledged') ||
          t.contains('investigating') ||
          t.contains('compiled') ||
          t.contains('resolved');
      final statusVal = data['status']?.toString();
      String badgeText = 'Report Filed';
      Color badgeBg = const Color(0xFFFCEAEA);
      Color badgeTextColor = const Color(0xFFA32D2D);

      if (isStatus) {
        if (statusVal != null && statusVal.isNotEmpty) {
          badgeText = statusVal;
        } else if (t.contains('acknowledged')) {
          badgeText = 'Acknowledged';
        } else if (t.contains('investigating')) {
          badgeText = 'Investigating';
        } else if (t.contains('compiled')) {
          badgeText = 'Report Compiled';
        } else if (t.contains('resolved')) {
          badgeText = 'Resolved';
        } else {
          badgeText = 'Status Update';
        }
        badgeBg = const Color(0xFFEBF8FF);
        badgeTextColor = const Color(0xFF185FA5);
      }

      return _NotifStyle(
        icon: Icons.warning_rounded,
        iconColor: const Color(0xFFC0392B),
        iconBg: const Color(0xFFFCEAEA),
        imagePath: 'assets/images/icon-illegal-slaughter-report-square.png',
        badge: badgeText,
        badgeBg: badgeBg,
        badgeText: badgeTextColor,
        actionLabel: 'View Details',
        actionColor: isStatus ? const Color(0xFF185FA5) : const Color(0xFFA32D2D),
      );
    }

    if (type == 'meat_delivery' || t.contains('meat out for delivery') || t.contains('out for delivery')) {
      return const _NotifStyle(
        icon: Icons.local_shipping,
        iconColor: Color(0xFF185FA5),
        iconBg: Color(0xFFE6F1FB),
        imagePath: 'assets/images/icon-delivery-truck.png',
      );
    }
    if (type == 'meat_pickup' || t.contains('meat ready for pickup') || t.contains('ready for pick up') || t.contains('ready for pickup')) {
      return const _NotifStyle(
        icon: Icons.inventory_2,
        iconColor: Color(0xFFB57A00),
        iconBg: Color(0xFFFFF7E6),
        imagePath: 'assets/images/icon-meat-box.png',
      );
    }
    if (type == 'slaughter_completed' ||
        type == 'operation_completed' ||
        t.contains('operation complete') ||
        t.contains('slaughter complete')) {
      return _NotifStyle(
        icon: Icons.check_circle,
        iconColor: const Color(0xFF1A8C62),
        iconBg: const Color(0xFFE4F8F0),
        imagePath: 'assets/images/slaughter_operation.png',
        badge: 'Operation Complete',
        badgeBg: const Color(0xFFE4F8F0),
        badgeText: const Color(0xFF0A3D2E),
        actionLabel: 'View Status',
        actionColor: const Color(0xFF0F6E56),
      );
    }
    if (type == 'doc_verified' ||
        type == 'document_verified' ||
        type == 'documents_verified' ||
        t.contains('document verified') ||
        t.contains('documents verified')) {
      return const _NotifStyle(
        icon: Icons.check_circle,
        iconColor: Color(0xFF1A8C62),
        iconBg: Color(0xFFE4F8F0),
        imagePath: 'assets/images/docu.verify.png',
      );
    }
    if (type == 'doc_rejected' ||
        type == 'doc_failed' ||
        type == 'document_rejected' ||
        type == 'document_failed' ||
        type == 'document_verification_failed' ||
        t.contains('document verification failed') ||
        t.contains('document rejected') ||
        t.contains('documents rejected')) {
      return const _NotifStyle(
        icon: Icons.close,
        iconColor: Color(0xFFC0392B),
        iconBg: Color(0xFFFCEAEA),
        imagePath: 'assets/images/docu_reject.png',
      );
    }
    if (type == 'request_rescheduled' ||
        type == 'request_submitted' ||
        t.contains('request submitted') ||
        t.contains('submitted successfully') ||
        t.contains('request submmitted') ||
        t.contains('rescheduled') ||
        (t.contains('reschedule') && !t.contains('reject') && !t.contains('denied')) ||
        t.contains('submitted')) {
      return const _NotifStyle(
        icon: Icons.check_circle,
        iconColor: Color(0xFF1A8C62),
        iconBg: Color(0xFFE4F8F0),
        imagePath: 'assets/images/request_submitted.png',
      );
    }
    if (type == 'request_approved' ||
        t.contains('approved request') ||
        t.contains('request approved') ||
        t.contains('request has been approved') ||
        t.contains('approve request') ||
        t.contains('approved') ||
        t.contains('approve')) {
      return const _NotifStyle(
        icon: Icons.check_circle,
        iconColor: Color(0xFF1A8C62),
        iconBg: Color(0xFFE4F8F0),
        imagePath: 'assets/images/approved_request.png',
      );
    }
    if (type == 'operation_failed' ||
        t.contains('operation failed') ||
        t.contains('operation delayed') ||
        t.contains('operation delay') ||
        (t.contains('operation') && (t.contains('delay') || t.contains('fail')))) {
      return _NotifStyle(
        icon: Icons.calendar_today,
        iconColor: const Color(0xFFC0392B),
        iconBg: const Color(0xFFFCEAEA),
        imagePath: 'assets/images/operation_failed.png',
        badge: t.contains('delay') ? 'Operation Delayed' : 'Operation Failed',
        badgeBg: const Color(0xFFFCEAEA),
        badgeText: const Color(0xFFA32D2D),
        actionLabel: 'View Options',
        actionColor: const Color(0xFFA32D2D),
      );
    }
    if (type == 'request_rejected' ||
        t.contains('request rejected') ||
        t.contains('rejected request') ||
        t.contains('request denied') ||
        t.contains('rejected') ||
        t.contains('denied') ||
        t.contains('reject')) {
      return _NotifStyle(
        icon: Icons.block,
        iconColor: const Color(0xFFC0392B),
        iconBg: const Color(0xFFFCEAEA),
        imagePath: 'assets/images/request_rejected.png',
        badge: 'Request Rejected',
        badgeBg: const Color(0xFFFCEAEA),
        badgeText: const Color(0xFFA32D2D),
        actionLabel: 'Reschedule',
        actionColor: const Color(0xFFA32D2D),
      );
    }

    switch (type) {
      case 'meat_delivery':
        return const _NotifStyle(
          icon: Icons.local_shipping,
          iconColor: Color(0xFF185FA5),
          iconBg: Color(0xFFE6F1FB),
          imagePath: 'assets/images/icon-delivery-truck.png',
        );
      case 'meat_pickup':
        return const _NotifStyle(
          icon: Icons.inventory_2,
          iconColor: Color(0xFFB57A00),
          iconBg: Color(0xFFFFF7E6),
          imagePath: 'assets/images/icon-meat-box.png',
        );
      case 'request_submitted':
        return const _NotifStyle(
          icon: Icons.check_circle,
          iconColor: Color(0xFF1A8C62),
          iconBg: Color(0xFFE4F8F0),
          imagePath: 'assets/images/request_submitted.png',
        );
      case 'request_status_changed':
        final status = data['status'] ?? '';
        final approved = status == 'approved';
        return _NotifStyle(
          icon: approved ? Icons.check_circle : Icons.block,
          iconColor: approved ? const Color(0xFF1A8C62) : const Color(0xFFC0392B),
          iconBg: approved ? const Color(0xFFE4F8F0) : const Color(0xFFFCEAEA),
          imagePath: approved
              ? 'assets/images/approved_request.png'
              : 'assets/images/request_rejected.png',
          badge: approved ? null : 'Request Rejected',
          badgeBg: approved ? null : const Color(0xFFFCEAEA),
          badgeText: approved ? null : const Color(0xFFA32D2D),
          actionLabel: approved ? null : 'Reschedule',
          actionColor: const Color(0xFFA32D2D),
        );
      case 'anti_mortem_failed':
        return _NotifStyle(
          icon: Icons.close,
          iconColor: const Color(0xFFC0392B),
          iconBg: const Color(0xFFFCEAEA),
          imagePath: 'assets/images/livestock_health.png',
          badge: 'Health Issue Detected',
          badgeBg: const Color(0xFFFCEAEA),
          badgeText: const Color(0xFFA32D2D),
          actionLabel: 'View Options',
          actionColor: const Color(0xFFA32D2D),
        );
      case 'health_issue':
        return _NotifStyle(
          icon: Icons.close,
          iconColor: const Color(0xFFC0392B),
          iconBg: const Color(0xFFFCEAEA),
          imagePath: 'assets/images/livestock_health.png',
          badge: 'Health issue detected',
          badgeBg: const Color(0xFFFCEAEA),
          badgeText: const Color(0xFFA32D2D),
          actionLabel: 'View options',
          actionColor: const Color(0xFFA32D2D),
        );
      case 'post_mortem_failed':
        return _NotifStyle(
          icon: Icons.close,
          iconColor: const Color(0xFFC0392B),
          iconBg: const Color(0xFFFFF3E5),
          imagePath: 'assets/images/postmortem_failed_real.png',
          badge: 'Post-Mortem Result Failed',
          badgeBg: const Color(0xFFFFF3E5),
          badgeText: const Color(0xFF854F0B),
          actionLabel: 'View condemnation slip',
          actionColor: const Color(0xFF854F0B),
        );
      case 'pickup_approved':
        return _NotifStyle(
          icon: Icons.check_circle,
          iconColor: const Color(0xFF1A8C62),
          iconBg: const Color(0xFFE4F8F0),
          badge: 'Pickup Approved',
          badgeBg: const Color(0xFFE4F8F0),
          badgeText: const Color(0xFF0A3D2E),
          actionLabel: 'View Details',
          actionColor: const Color(0xFF0F6E56),
        );
      case 'confine_confirmed':
        return _NotifStyle(
          icon: Icons.local_hospital,
          iconColor: const Color(0xFF185FA5),
          iconBg: const Color(0xFFE6F1FB),
          imagePath: 'assets/images/confinement_transparent.png',
          badge: 'Confinement Confirmed',
          badgeBg: const Color(0xFFE6F1FB),
          badgeText: const Color(0xFF185FA5),
          actionLabel: 'View Details',
          actionColor: const Color(0xFF185FA5),
        );
      case 'slaughter_completed':
        return _NotifStyle(
          icon: Icons.check_circle,
          iconColor: const Color(0xFF1A8C62),
          iconBg: const Color(0xFFE4F8F0),
          imagePath: 'assets/images/slaughter_operation.png',
          badge: 'Operation Complete',
          badgeBg: const Color(0xFFE4F8F0),
          badgeText: const Color(0xFF0A3D2E),
          actionLabel: 'View Status',
          actionColor: const Color(0xFF0F6E56),
        );
      case 'receipt_issued':
        return _NotifStyle(
          icon: Icons.receipt_long,
          iconColor: const Color(0xFF1A8C62),
          iconBg: const Color(0xFFE4F8F0),
          imagePath: 'assets/images/receipt.png',
          actionLabel: 'View Receipt & Pay',
          actionColor: const Color(0xFF0F6E56),
        );
      case 'operation_failed':
        return _NotifStyle(
          icon: Icons.calendar_today,
          iconColor: const Color(0xFFC0392B),
          iconBg: const Color(0xFFFCEAEA),
          imagePath: 'assets/images/operation_failed.png',
          badge: 'Operation Failed',
          badgeBg: const Color(0xFFFCEAEA),
          badgeText: const Color(0xFFA32D2D),
          actionLabel: 'View Options',
          actionColor: const Color(0xFFA32D2D),
        );
      case 'status_update':
        return _NotifStyle(
          icon: Icons.description,
          iconColor: const Color(0xFF185FA5),
          iconBg: const Color(0xFFE6F1FB),
          actionLabel: 'View',
          actionColor: Colors.grey.shade700,
        );
      case 'admin_manual':
        return _NotifStyle(
          icon: Icons.admin_panel_settings,
          iconColor: const Color(0xFFC26E00),
          iconBg: const Color(0xFFFFF3E5),
        );
      case 'doc_verified':
        return const _NotifStyle(
          icon: Icons.check_circle,
          iconColor: Color(0xFF1A8C62),
          iconBg: Color(0xFFE4F8F0),
          imagePath: 'assets/images/docu.verify.png',
        );
      case 'doc_rejected':
        return const _NotifStyle(
          icon: Icons.close,
          iconColor: Color(0xFFC0392B),
          iconBg: Color(0xFFFCEAEA),
          imagePath: 'assets/images/docu_reject.png',
        );
      case 'request_approved':
        return const _NotifStyle(
          icon: Icons.check_circle,
          iconColor: Color(0xFF1A8C62),
          iconBg: Color(0xFFE4F8F0),
          imagePath: 'assets/images/approved_request.png',
        );
      case 'request_rescheduled':
        return const _NotifStyle(
          icon: Icons.check_circle,
          iconColor: Color(0xFF1A8C62),
          iconBg: Color(0xFFE4F8F0),
          imagePath: 'assets/images/request_submitted.png',
        );
      case 'request_rejected':
        return _NotifStyle(
          icon: Icons.block,
          iconColor: const Color(0xFFC0392B),
          iconBg: const Color(0xFFFCEAEA),
          imagePath: 'assets/images/request_rejected.png',
          badge: 'Request Rejected',
          badgeBg: const Color(0xFFFCEAEA),
          badgeText: const Color(0xFFA32D2D),
          actionLabel: 'Reschedule',
          actionColor: const Color(0xFFA32D2D),
        );
      case 'admin_illegal_report':
      case 'report_filed':
      case 'report_status_update':
      case 'report_investigating':
      case 'report_resolved':
        return _NotifStyle(
          icon: Icons.warning_rounded,
          iconColor: const Color(0xFFC0392B),
          iconBg: const Color(0xFFFCEAEA),
          imagePath: 'assets/images/icon-illegal-slaughter-report-square.png',
          badge: 'Illegal Slaughter',
          badgeBg: const Color(0xFFFCEAEA),
          badgeText: const Color(0xFFA32D2D),
          actionLabel: 'View Details',
          actionColor: const Color(0xFFA32D2D),
        );
      default:
        return _NotifStyle(
          icon: Icons.check_circle,
          iconColor: Colors.grey,
          iconBg: Colors.grey.shade100,
        );
    }
  }

  // =========================
  // TIME FORMAT
  // =========================
  String _timeAgo(dynamic isoValue) {
    if (isoValue == null) return '';
    try {
      final date = DateTime.parse(isoValue.toString());
      final diff = DateTime.now().difference(date);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (e) {
      debugPrint('Bad created_at value: $isoValue ($e)');
      return '';
    }
  }

  // =========================
  // BUILD
  // =========================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildHeader(),
          if (_activeRequest != null) _buildStatusUpdateBanner(),
          _buildTabs(),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildStatusUpdateBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ViewStatusUpdateScreen(
                initialRequest: _activeRequest,
                onNavigateToTab: widget.onNavigateToTab,
              ),
            ),
          ).then((_) => _loadActiveRequest());
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F8F4), // Light mint green from user's screenshot
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD6EADA), width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6EADA),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.find_in_page_outlined,
                  color: Color(0xFF1E855A),
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'View Status Update',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Track your request update status.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black45, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: const Color(0xFFC8E6C9),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notification',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
                SizedBox(height: 2),
                Text(
                  'Keeps you updated on every step of your slaughter request.',
                  style: TextStyle(fontSize: 11, color: Colors.black87),
                ),
              ],
            ),
          ),
          // Mark all read button
          if (_unreadCount > 0)
            TextButton(
              onPressed: _markAllAsRead,
              child: const Text('Mark all read',
                  style: TextStyle(fontSize: 12, color: Color(0xFF0A3D2E))),
            ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      child: Row(
        children: [
          _TabChip(
            label: 'All',
            active: !showUnreadOnly,
            onTap: () => setState(() {
              showUnreadOnly = false;
              _userSwitchedTab = true;
            }),
          ),
          const SizedBox(width: 8),
          _TabChip(
            label: 'Unread',
            active: showUnreadOnly,
            count: _unreadCount,
            onTap: () => setState(() {
              showUnreadOnly = true;
              _userSwitchedTab = true;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF3ECFA3)));
    }
    if (_filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_off_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              showUnreadOnly ? 'No unread notifications' : 'No read notifications yet',
              style: TextStyle(color: Colors.grey.shade400),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _filtered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final notif = _filtered[i];

        // Wrapped in try/catch so one malformed row shows a visible
        // error card instead of silently blanking out.
        try {
          final type = notif['type'] as String?;
          final data = _asMap(notif['data']);
          final title = (notif['title'] ?? '').toString();
          final style = _styleFor(type, data, title: title);
          final isRead = _asBool(notif['is_read'], fallback: true);

          return _NotifCard(
            notif: notif,
            style: style,
            isRead: isRead,
            timeAgo: _timeAgo(notif['created_at']),
            onTap: () {
              if (!isRead) _markAsRead(notif['id']);
              _handleAction(type, data, notif);
            },
            onAction: () {
              if (!isRead) _markAsRead(notif['id']);
              _handleAction(type, data, notif);
            },
          );
        } catch (e) {
          debugPrint('Failed to render notif $notif: $e');
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(
              'Could not display this notification ($e)',
              style: TextStyle(fontSize: 11, color: Colors.red.shade800),
            ),
          );
        }
      },
    );
  }
}

// =========================
// NOTIFICATION CARD
// =========================
class _NotifCard extends StatelessWidget {
  final Map<String, dynamic> notif;
  final _NotifStyle style;
  final bool isRead;
  final String timeAgo;
  final VoidCallback onTap;
  final VoidCallback? onAction;

  const _NotifCard({
    required this.notif,
    required this.style,
    required this.isRead,
    required this.timeAgo,
    required this.onTap,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Unread accent bar
              Container(
                width: 3,
                color: isRead ? Colors.transparent : const Color(0xFF3ECFA3),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _buildCardContent(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardContent() {
    return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon or custom image
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: style.iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: style.imagePath != null
                  ? Image.asset(
                      style.imagePath!,
                      width: 42,
                      height: 42,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        debugPrint('NOTIF IMAGE ASSET FAILED: ${style.imagePath} -> $error');
                        return Center(
                          child: Icon(style.icon, color: style.iconColor, size: 22),
                        );
                      },
                    )
                  : Center(
                      child: Icon(style.icon, color: style.iconColor, size: 22),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badge
                  if (style.badge != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: style.badgeBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        style.badge!,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: style.badgeText),
                      ),
                    ),
                  // Title
                  Text(
                    (notif['title'] ?? '').toString(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isRead ? FontWeight.normal : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Body — uses 'message' (your column) or 'body' as fallback
                  Text(
                    (notif['message'] ?? notif['body'] ?? '').toString(),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Action button
                  if (style.actionLabel != null) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton(
                        onPressed: onAction,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: style.actionColor,
                          side: BorderSide(color: style.actionColor!),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(style.actionLabel!),
                      ),
                    ),
                  ],
                  // Time
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(timeAgo,
                        style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ),
                ],
              ),
            ),
            // Unread dot
            if (!isRead)
              Container(
                margin: const EdgeInsets.only(left: 6, top: 2),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF3ECFA3),
                  shape: BoxShape.circle,
                ),
              ),
          ],
        );
  }
}

// =========================
// TAB CHIP
// =========================
class _TabChip extends StatelessWidget {
  final String label;
  final bool active;
  final int count;
  final VoidCallback onTap;

  const _TabChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.count = 0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF3ECFA3) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                color: active ? const Color(0xFF0A3D2E) : Colors.grey,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: active ? const Color(0xFF0A3D2E) : Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$count',
                    style: const TextStyle(fontSize: 10, color: Colors.white)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =========================
// STYLE MODEL
// =========================
class _NotifStyle {
  final IconData icon;
  final Color iconColor, iconBg;
  final String? badge, actionLabel;
  final Color? badgeBg, badgeText, actionColor;
  /// Optional asset path — when set, renders an image instead of the icon.
  final String? imagePath;

  const _NotifStyle({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    this.badge,
    this.actionLabel,
    this.badgeBg,
    this.badgeText,
    this.actionColor,
    this.imagePath,
  });
}

// =========================
// RESCHEDULE DIALOG
// =========================
class _RescheduleDialog extends StatefulWidget {
  final Map<String, dynamic> notif;
  final Map<String, dynamic> data;
  final VoidCallback onSuccess;
  final VoidCallback? onNavigateToRequests;

  const _RescheduleDialog({
    required this.notif,
    required this.data,
    required this.onSuccess,
    this.onNavigateToRequests,
  });

  @override
  State<_RescheduleDialog> createState() => _RescheduleDialogState();
}

class _RescheduleDialogState extends State<_RescheduleDialog> {
  final _notesController = TextEditingController();
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  bool _isSubmitting = false;

  dynamic _requestId;
  String _refNo = '';
  String _livestock = '';
  String _animalCount = '';
  String _prevDate = '';
  String _reason = '';

  @override
  void initState() {
    super.initState();
    if (_selectedDate.weekday == DateTime.sunday) {
      _selectedDate = _selectedDate.add(const Duration(days: 1));
    }
    _loadRequestInfo();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadRequestInfo() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    _reason = (widget.data['reason'] ??
            widget.notif['message'] ??
            widget.notif['body'] ??
            'Request denied — fully booked. Please select another date.')
        .toString();

    _requestId = widget.data['request_id'];
    _refNo = (widget.data['reference_no'] ?? '').toString();
    _livestock = (widget.data['livestock_type'] ?? '').toString();
    _animalCount = (widget.data['animal_count'] ?? '').toString();
    _prevDate = (widget.data['preferred_date'] ?? '').toString();

    try {
      // 1. If we already have request_id in data, load record from DB
      if (_requestId != null) {
        final req = await supabase
            .from('requests')
            .select()
            .eq('id', _requestId)
            .maybeSingle();
        if (req != null) {
          if (mounted) setState(() => _populateFromReq(req));
          return;
        }
      }

      // 2. Try parsing Reference No from message (e.g. "MI-2026-059" -> id 59)
      final notifMsg = (widget.notif['message'] ?? widget.notif['body'] ?? '').toString();
      final match = RegExp(r'MI-\d{4}-(\d+)').firstMatch(notifMsg);
      if (match != null) {
        final parsedId = int.tryParse(match.group(1)!);
        if (parsedId != null) {
          final req = await supabase
              .from('requests')
              .select()
              .eq('id', parsedId)
              .maybeSingle();
          if (req != null) {
            if (mounted) setState(() => _populateFromReq(req));
            return;
          }
        }
      }

      // 3. Fallback: Query the latest rejected request of this user
      if (user != null) {
        final req = await supabase
            .from('requests')
            .select()
            .eq('user_id', user.id)
            .eq('status', 'rejected')
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (req != null) {
          if (mounted) setState(() => _populateFromReq(req));
        }
      }
    } catch (e) {
      debugPrint('Error finding request for reschedule: $e');
    }
  }

  void _populateFromReq(Map<String, dynamic> req) {
    _requestId = req['id'];
    final idStr = req['id'].toString().padLeft(3, '0');
    _refNo = req['reference_no']?.toString().isNotEmpty == true
        ? req['reference_no'].toString()
        : "MI-${DateTime.now().year}-$idStr";
    _livestock = req['livestock_type']?.toString() ?? _livestock;
    _animalCount = req['animal_count']?.toString() ?? _animalCount;
    _prevDate = req['preferred_date']?.toString() ?? _prevDate;
  }

  String _formatDisplayDate(dynamic raw) {
    if (raw == null || raw.toString().isEmpty) return '—';
    try {
      final dt = DateTime.parse(raw.toString());
      return DateFormat('MMMM d, yyyy').format(dt);
    } catch (_) {
      return raw.toString();
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = now.add(const Duration(days: 1));
    final last = now.add(const Duration(days: 60));

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(first) ? first : _selectedDate,
      firstDate: first,
      lastDate: last,
      helpText: 'SELECT NEW SLAUGHTER DATE',
      confirmText: 'SELECT DATE',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0A3D2E),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF1A202C),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _submitReschedule() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      final dateIso = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final dateDisplay = DateFormat('MMMM d, yyyy').format(_selectedDate);

      if (_requestId != null) {
        // 1. Update the request in DB: status back to pending, new preferred_date & rescheduled_date
        final updatePayload = <String, dynamic>{
          'status': 'pending',
          'preferred_date': dateIso,
          'rescheduled_date': dateIso,
        };
        if (_notesController.text.trim().isNotEmpty) {
          updatePayload['special_instruction'] = _notesController.text.trim();
        }

        await supabase
            .from('requests')
            .update(updatePayload)
            .eq('id', _requestId);

        // 2. Mark this rejection notification as read
        if (widget.notif['id'] != null) {
          await supabase
              .from('notifications')
              .update({'is_read': true})
              .eq('id', widget.notif['id']);
        }

        // 3. Insert notification confirming the rescheduled submission
        if (user != null) {
          final refLabel = _refNo.isNotEmpty ? '\nRef: $_refNo' : '';
          await supabase.from('notifications').insert({
            'user_id': user.id,
            'title': 'Request Rescheduled',
            'message':
                'Your slaughter request has been rescheduled for $dateDisplay. Waiting for admin approval.$refLabel',
            'is_read': false,
            'type': 'request_submitted',
            'data': {
              'request_id': _requestId,
              'reference_no': _refNo,
              'preferred_date': dateIso,
              'rescheduled': true,
            },
          });
        }

        if (mounted) {
          Navigator.pop(context);
          widget.onSuccess();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Rescheduled for $dateDisplay! The admin has received your request.',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF2D6A4F),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        // If request id couldn't be located in DB, direct user to Requests screen
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not find existing request. Redirecting to Requests tab to submit new schedule.'),
              backgroundColor: Color(0xFFE53E3E),
            ),
          );
          widget.onNavigateToRequests?.call();
        }
      }
    } catch (e) {
      debugPrint('Submit reschedule error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting reschedule: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedSelected = DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate);

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCEAEA),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      'assets/images/request_rejected.png',
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.calendar_today, color: Color(0xFFC0392B), size: 22),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reschedule Request',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A202C),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Select a new slaughter date for review',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ── Rejection Reason Card ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF5F5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFEB2B2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFFE53E3E), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Reason for Rejection:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFC53030),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _reason,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF4A5568),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Request Summary (if available) ──
              if (_refNo.isNotEmpty || _livestock.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      if (_refNo.isNotEmpty)
                        _infoRow('Reference #', _refNo),
                      if (_livestock.isNotEmpty)
                        _infoRow(
                          'Livestock',
                          _animalCount.isNotEmpty ? '$_animalCount head(s) • $_livestock' : _livestock,
                        ),
                      if (_prevDate.isNotEmpty)
                        _infoRow('Previous Date', _formatDisplayDate(_prevDate)),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // ── Date Picker Field ──
              const Text(
                'Select New Slaughter Date *',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2D3748),
                ),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: _isSubmitting ? null : _pickDate,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2D6A4F),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.calendar_month, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Target Slaughter Date',
                              style: TextStyle(fontSize: 10, color: Color(0xFF2D6A4F), fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              formattedSelected,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0A3D2E),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF2D6A4F)),
                        ),
                        child: const Text(
                          'Change',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF2D6A4F)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // ── Optional Note Field ──
              const Text(
                'Note for Admin (Optional)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2D3748),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _notesController,
                maxLines: 2,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'e.g., Will bring animals early in the morning',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF2D6A4F), width: 1.5),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── Action Buttons ──
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Color(0xFF4A5568), fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitReschedule,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A3D2E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.send_rounded, size: 16),
                                SizedBox(width: 6),
                                Text(
                                  'Submit Reschedule',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1A202C))),
        ],
      ),
    );
  }
}
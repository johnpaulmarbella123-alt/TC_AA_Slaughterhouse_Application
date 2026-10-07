import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _loadActiveRequest();
    _subscribeRealtime();
    widget.refreshTrigger?.addListener(_onRefreshTriggered);
  }

  @override
  void dispose() {
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

      if (mounted) {
        setState(() {
          notifications = List<Map<String, dynamic>>.from(data);
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
        if (status != 'approved') {
          // Rejected — navigate to Requests to reschedule
          widget.onNavigateToTab?.call(1);
        }
        break;

      case 'status_update':
      case 'admin_manual':
        _showDetailDialog(notif);
        break;

      default:
        _showDetailDialog(notif);
        break;
    }
  }

  void _showDetailDialog(Map<String, dynamic> notif) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          (notif['title'] ?? 'Notification').toString(),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        content: Text(
          (notif['message'] ?? notif['body'] ?? 'No details available.').toString(),
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
                shape: BoxShape.circle,
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
                color: Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.local_hospital, size: 20, color: Colors.blue.shade600),
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
  _NotifStyle _styleFor(String? type, Map data) {
    switch (type) {
      case 'request_submitted':
        return _NotifStyle(
          icon: Icons.check_circle,
          iconColor: const Color(0xFF1A8C62),
          iconBg: const Color(0xFFE4F8F0),
        );
      case 'request_status_changed':
        final status = data['status'] ?? '';
        final approved = status == 'approved';
        return _NotifStyle(
          icon: approved ? Icons.check_circle : Icons.block,
          iconColor: approved ? const Color(0xFF1A8C62) : const Color(0xFFC0392B),
          iconBg: approved ? const Color(0xFFE4F8F0) : const Color(0xFFFCEAEA),
          actionLabel: approved ? null : 'Reschedule',
          actionColor: const Color(0xFFA32D2D),
        );
      case 'anti_mortem_failed':
        return _NotifStyle(
          icon: Icons.close,
          iconColor: const Color(0xFFC0392B),
          iconBg: const Color(0xFFFCEAEA),
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
          iconBg: const Color(0xFFFCEAEA),
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
          badge: 'Operation Complete',
          badgeBg: const Color(0xFFE4F8F0),
          badgeText: const Color(0xFF0A3D2E),
          actionLabel: 'View Status',
          actionColor: const Color(0xFF0F6E56),
        );
      case 'receipt_issued':
        return _NotifStyle(
          icon: Icons.check_circle,
          iconColor: const Color(0xFF1A8C62),
          iconBg: const Color(0xFFE4F8F0),
          actionLabel: 'View Receipt & Pay',
          actionColor: const Color(0xFF0F6E56),
        );
      case 'operation_failed':
        return _NotifStyle(
          icon: Icons.calendar_today,
          iconColor: const Color(0xFFC0392B),
          iconBg: const Color(0xFFFCEAEA),
          badge: 'Operation failed',
          badgeBg: const Color(0xFFFCEAEA),
          badgeText: const Color(0xFFA32D2D),
          actionLabel: 'View options',
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
        return _NotifStyle(
          icon: Icons.check_circle,
          iconColor: const Color(0xFF1A8C62),
          iconBg: Colors.transparent,
          imagePath: 'assets/images/docu.verify.png',
        );
      case 'doc_rejected':
        return _NotifStyle(
          icon: Icons.close,
          iconColor: const Color(0xFFC0392B),
          iconBg: Colors.transparent,
          imagePath: 'assets/images/docu_reject.png',
        );
      case 'request_approved':
        return _NotifStyle(
          icon: Icons.check_circle,
          iconColor: const Color(0xFF1A8C62),
          iconBg: const Color(0xFFE4F8F0),
        );
      case 'request_rejected':
        return _NotifStyle(
          icon: Icons.block,
          iconColor: const Color(0xFFC0392B),
          iconBg: const Color(0xFFFCEAEA),
          actionLabel: 'Reschedule',
          actionColor: const Color(0xFFA32D2D),
        );
      case 'report_filed':
        return _NotifStyle(
          icon: Icons.check_circle,
          iconColor: const Color(0xFF1A8C62),
          iconBg: const Color(0xFFE4F8F0),
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
          final style = _styleFor(type, data);
          final isRead = _asBool(notif['is_read'], fallback: true);

          return _NotifCard(
            notif: notif,
            style: style,
            isRead: isRead,
            timeAgo: _timeAgo(notif['created_at']),
            onTap: () {
              if (!isRead) _markAsRead(notif['id']);
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
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: style.iconBg,
                shape: BoxShape.circle,
              ),
              child: style.imagePath != null
                  ? ClipOval(
                      child: Image.asset(
                        style.imagePath!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Icon(style.icon, color: style.iconColor, size: 20),
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
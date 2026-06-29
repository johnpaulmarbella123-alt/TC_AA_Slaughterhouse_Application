import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotifyPage extends StatefulWidget {
  const NotifyPage({super.key});

  @override
  State<NotifyPage> createState() => _NotifyPageState();
}

class _NotifyPageState extends State<NotifyPage> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> notifications = [];
  bool isLoading = true;
  bool showUnreadOnly = false;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _subscribeRealtime(); // NEW: live updates
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

      setState(() {
        notifications = List<Map<String, dynamic>>.from(data);
        isLoading = false;
      });
    } catch (e) {
      debugPrint("Notification load error: $e");
      setState(() => isLoading = false);
    }
  }

  // =========================
  // REALTIME SUBSCRIPTION
  // =========================
  void _subscribeRealtime() {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    supabase
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .listen((data) {
          if (mounted) setState(() => notifications = data);
        });
  }

  // =========================
  // MARK AS READ
  // =========================
  Future<void> _markAsRead(String id) async {
    await supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('id', id);
  }

  Future<void> _markAllAsRead() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    await supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', user.id);
  }

  // =========================
  // FILTER
  // =========================
  List<Map<String, dynamic>> get _filtered => showUnreadOnly
      ? notifications.where((n) => n['is_read'] == false).toList()
      : notifications;

  int get _unreadCount =>
      notifications.where((n) => n['is_read'] == false).length;

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
          icon: approved ? Icons.verified : Icons.block,
          iconColor: approved ? const Color(0xFF1A8C62) : const Color(0xFFC0392B),
          iconBg: approved ? const Color(0xFFE4F8F0) : const Color(0xFFFCEAEA),
          actionLabel: approved ? null : 'Reschedule',
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
          badge: 'Post-mortem inspection failed',
          badgeBg: const Color(0xFFFFF3E5),
          badgeText: const Color(0xFF854F0B),
          actionLabel: 'View condemnation slip',
          actionColor: const Color(0xFF854F0B),
        );
      case 'receipt_issued':
        return _NotifStyle(
          icon: Icons.check_circle,
          iconColor: const Color(0xFF1A8C62),
          iconBg: const Color(0xFFE4F8F0),
          actionLabel: 'View receipt & pay',
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
      default:
        return _NotifStyle(
          icon: Icons.notifications,
          iconColor: Colors.grey,
          iconBg: Colors.grey.shade100,
        );
    }
  }

  // =========================
  // TIME FORMAT
  // =========================
  String _timeAgo(String iso) {
    final diff = DateTime.now().difference(DateTime.parse(iso));
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
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
          _buildTabs(),
          Expanded(child: _buildList()),
        ],
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
            onTap: () => setState(() => showUnreadOnly = false),
          ),
          const SizedBox(width: 8),
          _TabChip(
            label: 'Unread',
            active: showUnreadOnly,
            count: _unreadCount,
            onTap: () => setState(() => showUnreadOnly = true),
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
              showUnreadOnly ? 'No unread notifications' : 'No notifications yet',
              style: TextStyle(color: Colors.grey.shade400),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final notif = _filtered[i];
        final type = notif['type'] as String?;
        final data = (notif['data'] as Map<String, dynamic>?) ?? {};
        final style = _styleFor(type, data);
        final isRead = notif['is_read'] as bool? ?? true;

        return _NotifCard(
          notif: notif,
          style: style,
          isRead: isRead,
          timeAgo: _timeAgo(notif['created_at']),
          onTap: () {
            if (!isRead) _markAsRead(notif['id']);
          },
        );
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

  const _NotifCard({
    required this.notif,
    required this.style,
    required this.isRead,
    required this.timeAgo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(
              color: isRead ? Colors.transparent : const Color(0xFF3ECFA3),
              width: 3,
            ),
            top: BorderSide(color: Colors.grey.shade200),
            right: BorderSide(color: Colors.grey.shade200),
            bottom: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: style.iconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(style.icon, color: style.iconColor, size: 20),
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
                    notif['title'] ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isRead ? FontWeight.normal : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Body — uses 'message' (your column) or 'body'
                  Text(
                    notif['message'] ?? notif['body'] ?? '',
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
                        onPressed: () {},
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
        ),
      ),
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

  const _NotifStyle({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    this.badge,
    this.actionLabel,
    this.badgeBg,
    this.badgeText,
    this.actionColor,
  });
}
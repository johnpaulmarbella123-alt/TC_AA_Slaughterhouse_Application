import 'package:flutter/material.dart';
import '../services/staff_notification_service.dart';

/// Header bell for Admin / Clerk / Inspector dashboards.
/// Shows unread count and a dropdown list of staff notifications.
class StaffNotificationBell extends StatefulWidget {
  final void Function(int moduleIndex) onNavigate;

  const StaffNotificationBell({super.key, required this.onNavigate});

  @override
  State<StaffNotificationBell> createState() => _StaffNotificationBellState();
}

class _StaffNotificationBellState extends State<StaffNotificationBell> {
  final MenuController _menuController = MenuController();
  final _service = StaffNotificationService.instance;

  @override
  void initState() {
    super.initState();
    _service.start(); // idempotent
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours} hr ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes} min ago';
    return 'Just now';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final unread = _service.unreadCount;
        return MenuAnchor(
          controller: _menuController,
          alignmentOffset: const Offset(-310, 6),
          style: MenuStyle(
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            backgroundColor: const WidgetStatePropertyAll(Colors.white),
            elevation: const WidgetStatePropertyAll(8),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
          ),
          menuChildren: [_buildPanel()],
          builder: (context, controller, _) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: IconButton(
                tooltip: 'Notifications',
                onPressed: () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    _service.refresh();
                    controller.open();
                  }
                },
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      unread > 0 ? Icons.notifications_active_outlined : Icons.notifications_outlined,
                      size: 20,
                      color: unread > 0 ? const Color(0xFF2D6A4F) : const Color(0xFF64748B),
                    ),
                    if (unread > 0)
                      Positioned(
                        right: -8,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white, width: 1.2),
                          ),
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPanel() {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final items = _service.items;
        final unread = _service.unreadCount;
        return SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                child: Row(
                  children: [
                    const Text(
                      'Notifications',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                    ),
                    if (unread > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$unread new',
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFB91C1C)),
                        ),
                      ),
                    ],
                    const Spacer(),
                    TextButton(
                      onPressed: unread > 0 ? () => _service.markAllRead() : null,
                      child: const Text('Mark all as read', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              // Body
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: items.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 36),
                        child: Column(
                          children: [
                            Icon(Icons.notifications_none, size: 36, color: Color(0xFFCBD5E1)),
                            SizedBox(height: 8),
                            Text("You're all caught up",
                                style: TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        itemBuilder: (context, i) => _buildItem(items[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildItem(StaffNotification n) {
    final isUnread = _service.isUnread(n);
    final isDocVerified = n.type == 'doc_verified';
    final accent = isDocVerified ? const Color(0xFF059669) : const Color(0xFF2563EB);
    final bg = isDocVerified ? const Color(0xFFD1FAE5) : const Color(0xFFDBEAFE);

    return InkWell(
      onTap: () {
        _service.markRead([n.id]);
        _menuController.close();
        widget.onNavigate(n.targetModule);
      },
      child: Container(
        color: isUnread ? const Color(0xFFF0FDF4) : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
              child: Icon(isDocVerified ? Icons.fact_check_outlined : Icons.assignment_outlined,
                  size: 18, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isUnread ? FontWeight.w800 : FontWeight.w600,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    n.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.3),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${_timeAgo(n.createdAt)} · ${isDocVerified ? 'Slaughter & Inspection' : 'Receiving'}',
                    style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),
            if (isUnread)
              Container(
                margin: const EdgeInsets.only(top: 4, left: 6),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: Color(0xFFDC2626), shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}


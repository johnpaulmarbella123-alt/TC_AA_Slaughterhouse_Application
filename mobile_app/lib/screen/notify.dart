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

  @override
  void initState() {
    super.initState();
    _loadNotifications();
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
        notifications =
            List<Map<String, dynamic>>.from(data);
        isLoading = false;
      });
    } catch (e) {
      debugPrint("Notification load error: $e");
      setState(() => isLoading = false);
    }
  }

  // =========================
  // ICONS
  // =========================
  Widget _getIcon(String title) {
    if (title.contains("Submitted")) {
      return _icon(Icons.check_circle, Colors.green);
    } else if (title.contains("Approved")) {
      return _icon(Icons.verified, Colors.green);
    } else if (title.contains("Rejected")) {
      return _icon(Icons.cancel, Colors.red);
    } else {
      return _icon(Icons.notifications, Colors.blue);
    }
  }

  Widget _icon(IconData icon, Color color) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color),
    );
  }

  // =========================
  // TIME FORMAT
  // =========================
  String _formatTime(String date) {
    final dt = DateTime.parse(date);
    return "${dt.month}/${dt.day}/${dt.year}";
  }

  // =========================
  // UI LIST
  // =========================
  Widget _buildNotificationList() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (notifications.isEmpty) {
      return const Center(
        child: Text("No notifications yet"),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: notifications.map((notif) {
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: _getIcon(notif['title'] ?? ''),
              title: Text(notif['title'] ?? ''),
              subtitle: Text(notif['message'] ?? ''),
              trailing: Text(
                _formatTime(notif['created_at']),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Notifications"),
        backgroundColor: const Color(0xFF1E855A),
      ),
      body: _buildNotificationList(),
    );
  }
}
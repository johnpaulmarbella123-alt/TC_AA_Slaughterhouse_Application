import 'package:flutter/material.dart';

/// Bottom-sheet shown when the user taps "View options" on
/// `health_issue` or `operation_failed` notifications.
///
/// [notifType]  — the notification `type` string
/// [data]       — the notification `data` JSON map
/// [title]      — the notification title for the header
/// [onReschedule] — callback that navigates the user to the Requests tab
class NotificationOptionsDialog {
  static void show({
    required BuildContext context,
    required String notifType,
    required Map<String, dynamic> data,
    required String title,
    required VoidCallback onReschedule,
  }) {
    final isHealth = notifType == 'health_issue';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _Sheet(
        isHealth: isHealth,
        data: data,
        title: title,
        onReschedule: () {
          Navigator.pop(ctx);
          onReschedule();
        },
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  final bool isHealth;
  final Map<String, dynamic> data;
  final String title;
  final VoidCallback onReschedule;

  const _Sheet({
    required this.isHealth,
    required this.data,
    required this.title,
    required this.onReschedule,
  });

  String _val(String key, [String fallback = 'N/A']) =>
      (data[key] ?? fallback).toString();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header icon + title
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isHealth
                      ? const Color(0xFFFCEAEA)
                      : const Color(0xFFFCEAEA),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isHealth ? Icons.health_and_safety : Icons.error_outline,
                  color: const Color(0xFFC0392B),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isHealth ? "Health Issue Detected" : "Operation Failed",
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(title,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Details card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF9F9F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Details",
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (isHealth) ...[
                  _detailRow("Livestock:", _val('livestock_type')),
                  _detailRow("Issue:", _val('issue', 'Health issue detected')),
                  _detailRow("Detected by:", _val('inspector')),
                ] else ...[
                  _detailRow("Operation:", _val('operation', 'Slaughter')),
                  _detailRow("Reason:", _val('reason')),
                  _detailRow("Reference:", _val('reference_no')),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Option buttons
          _optionButton(
            icon: Icons.calendar_today,
            label: "Reschedule Request",
            subtitle: "Submit a new request with a different date",
            color: const Color(0xFF1E855A),
            onTap: onReschedule,
          ),
          const SizedBox(height: 10),
          _optionButton(
            icon: Icons.support_agent,
            label: "Contact Administrator",
            subtitle: "tabacocityslaughterhouse@gmail.com",
            color: const Color(0xFF185FA5),
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      "Contact: tabacocityslaughterhouse@gmail.com\nPhone: +63 917 123 4567"),
                  duration: Duration(seconds: 4),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            Flexible(
              child: Text(value,
                  style: const TextStyle(fontSize: 11),
                  textAlign: TextAlign.end),
            ),
          ],
        ),
      );

  Widget _optionButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style:
                          const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );
  }
}

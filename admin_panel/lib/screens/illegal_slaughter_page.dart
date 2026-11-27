import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'illegal_slaughter_reports_view.dart';
import '../widgets/staff_notification_bell.dart';

/// Dedicated Admin-only page for Illegal Slaughter Reports (accessible from the Sidebar).
class IllegalSlaughterPage extends StatelessWidget {
  final void Function(int moduleIndex, [dynamic tab])? onNavigate;
  final VoidCallback? onReportsUpdated;

  const IllegalSlaughterPage({
    super.key,
    this.onNavigate,
    this.onReportsUpdated,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now());
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Illegal Slaughter Reports',
                        style: TextStyle(
                          fontSize: 24,
                          height: 32 / 24,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Community whistleblower reports, evidence verification, and enforcement tracking',
                        style: TextStyle(
                          fontSize: 14,
                          height: 20 / 14,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    dateStr,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF4A5568)),
                  ),
                ),
                const SizedBox(width: 10),
                StaffNotificationBell(
                  onNavigate: (idx, [tab]) => onNavigate?.call(idx, tab),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: IllegalSlaughterReportsView(
                onReportsUpdated: onReportsUpdated,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

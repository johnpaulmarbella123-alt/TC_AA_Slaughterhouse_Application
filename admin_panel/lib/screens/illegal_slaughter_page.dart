import 'package:flutter/material.dart';
import 'illegal_slaughter_reports_view.dart';
import '../utils/admin_responsive.dart';

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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SingleChildScrollView(
        padding: AdminResponsive.pagePadding(context),
        child: IllegalSlaughterReportsView(
          onReportsUpdated: onReportsUpdated,
        ),
      ),
    );
  }
}

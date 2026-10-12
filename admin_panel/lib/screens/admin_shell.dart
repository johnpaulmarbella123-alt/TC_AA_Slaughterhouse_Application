import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dashboard.dart';
import 'receiving_requests_page.dart';
import 'document_verification_page.dart';
import 'slaughter_inspection_page.dart';
import 'payment_cashiering_page.dart';
import 'meat_releasing_page.dart';
import 'reports_records_page.dart';
import 'settings_page.dart';
import '../services/app_settings_service.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _selectedIndex = 0;
  String? _reportsInitialTab;
  int _settingsInitialTab = 0;
  final Set<int> _loadedPages = {0};

  @override
  void initState() {
    super.initState();
    _loadedPages.add(_selectedIndex);

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
      });
    } else {
      AppSettingsService.instance.syncWithAuthUser(session.user);
    }
  }

  void _onNavigate(int index, [dynamic tabArg]) {
    setState(() {
      _selectedIndex = index;
      _loadedPages.add(index);
      if (index == 6 && tabArg is String) {
        _reportsInitialTab = tabArg;
      } else if (index == 7 && tabArg is int) {
        _settingsInitialTab = tabArg;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettingsService.instance,
      builder: (context, _) {
        // If current role is restricted and current page is not allowed, revert to Dashboard
        if (!AppSettingsService.instance.isModuleAllowed(_selectedIndex)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selectedIndex = 0);
          });
        }

        return Scaffold(
          body: Row(
            children: [
              // ─── SIDEBAR ───
              _AdminSidebar(
                selectedIndex: _selectedIndex,
                onItemSelected: (idx, [tab]) => _onNavigate(idx, tab),
              ),
              // ─── CONTENT AREA (Preserved in memory for instant zero-lag navigation) ───
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex,
                  children: [
                    _loadedPages.contains(0)
                        ? DashboardPage(onNavigate: _onNavigate)
                        : const SizedBox.shrink(),
                    _loadedPages.contains(1)
                        ? const ReceivingRequestsPage()
                        : const SizedBox.shrink(),
                    _loadedPages.contains(2)
                        ? const DocumentVerificationPage()
                        : const SizedBox.shrink(),
                    _loadedPages.contains(3)
                        ? const SlaughterInspectionPage()
                        : const SizedBox.shrink(),
                    _loadedPages.contains(4)
                        ? const PaymentCashieringPage()
                        : const SizedBox.shrink(),
                    _loadedPages.contains(5)
                        ? const MeatReleasingPage()
                        : const SizedBox.shrink(),
                    _loadedPages.contains(6)
                        ? ReportsRecordsPage(
                            initialTab: _reportsInitialTab,
                          )
                        : const SizedBox.shrink(),
                    _loadedPages.contains(7)
                        ? SettingsPage(
                            initialTab: _settingsInitialTab,
                          )
                        : const SizedBox.shrink(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  SIDEBAR WIDGET
// ═══════════════════════════════════════════════════════════
class _AdminSidebar extends StatefulWidget {
  final int selectedIndex;
  final void Function(int index, [dynamic tab]) onItemSelected;

  const _AdminSidebar({
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  State<_AdminSidebar> createState() => _AdminSidebarState();
}

class _AdminSidebarState extends State<_AdminSidebar> {
  final supabase = Supabase.instance.client;
  int _illegalReportBadgeCount = 0;
  Timer? _badgeTimer;

  @override
  void initState() {
    super.initState();
    _fetchBadgeCount();
    _badgeTimer =
        Timer.periodic(const Duration(seconds: 12), (_) => _fetchBadgeCount());
  }

  @override
  void dispose() {
    _badgeTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchBadgeCount() async {
    try {
      final reportsRes = await supabase.from('reports').select();
      final Map<String, Map<String, dynamic>> reportsMap = {};

      for (var r in (reportsRes as List)) {
        final idStr = r['id']?.toString() ?? '';
        final shortId = idStr.length >= 8
            ? idStr.substring(0, 8).toUpperCase()
            : idStr.toUpperCase();
        final ref = r['reference_no']?.toString() ?? (idStr.isNotEmpty ? 'RPT-2026-$shortId' : '');
        final key = ref.isNotEmpty ? ref : idStr;
        if (key.isNotEmpty) {
          reportsMap[key] = {
            'id': idStr,
            'reference_no': ref,
            'status': r['status'] ?? 'Pending Review',
          };
        }
      }

      // Merge notifications to accurately reflect updated statuses (e.g. 'Report Compiled')
      try {
        final notifs = await supabase
            .from('notifications')
            .select('type, is_read, data, reference_no')
            .inFilter('type', [
              'admin_illegal_report',
              'report_filed',
              'report_status_update',
              'report_investigating',
              'report_resolved',
            ])
            .order('created_at', ascending: true);

        for (var n in (notifs as List)) {
          final data = n['data'] is Map ? Map<String, dynamic>.from(n['data']) : <String, dynamic>{};
          final ref = n['reference_no']?.toString() ?? data['reference_no']?.toString() ?? '';
          final rId = data['report_id']?.toString() ?? data['id']?.toString() ?? '';

          String? matchKey;
          for (var k in reportsMap.keys) {
            final item = reportsMap[k]!;
            if ((ref.isNotEmpty && (k == ref || item['reference_no'] == ref)) ||
                (rId.isNotEmpty && (item['id'] == rId || k == rId))) {
              matchKey = k;
              break;
            }
          }

          if (matchKey != null) {
            if (data['status'] != null && data['status'].toString().isNotEmpty) {
              reportsMap[matchKey]!['status'] = data['status'].toString();
            }
          } else if (ref.isNotEmpty || rId.isNotEmpty) {
            final key = ref.isNotEmpty ? ref : rId;
            reportsMap[key] = {
              'id': rId,
              'reference_no': ref,
              'status': data['status'] ?? 'Pending Review',
            };
          }
        }
      } catch (_) {}

      int count = 0;
      for (var rep in reportsMap.values) {
        final s = (rep['status'] ?? '').toString().trim().toLowerCase();
        final isPending = s == 'pending' ||
            s == 'unreviewed' ||
            s == 'submitted' ||
            s == 'new' ||
            s == 'pending review' ||
            s == 'pending_review' ||
            s == 'under review';
        if (isPending) {
          count++;
        }
      }

      if (mounted && count != _illegalReportBadgeCount) {
        setState(() => _illegalReportBadgeCount = count);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settingsService = AppSettingsService.instance;

    return Container(
      width: 285,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border(
          right: BorderSide(
            color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // ─── LOGO HEADER (Fixed at top) ───
          _buildLogoHeader(isDark, settingsService),
          const SizedBox(height: 8),

          // ─── SCROLLABLE NAV ITEMS (Filtered by role!) ───
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                children: [
                  if (settingsService.isModuleAllowed(0))
                    _buildNavItem(
                      index: 0,
                      icon: Icons.dashboard_outlined,
                      activeIcon: Icons.dashboard,
                      label: 'Dashboard',
                      subtitle: 'Overview & statistics',
                      isDark: isDark,
                    ),
                  if (settingsService.isModuleAllowed(1)) ...[
                    const SizedBox(height: 2),
                    _buildNavItem(
                      index: 1,
                      icon: Icons.assignment_outlined,
                      activeIcon: Icons.assignment,
                      label: 'Receiving & New Requests',
                      subtitle:
                          'Customer details, animal inspection, reference assignment',
                      isDark: isDark,
                    ),
                  ],
                  if (settingsService.isModuleAllowed(2)) ...[
                    const SizedBox(height: 2),
                    _buildNavItem(
                      index: 2,
                      icon: Icons.fact_check_outlined,
                      activeIcon: Icons.fact_check,
                      label: 'Document Verification',
                      subtitle: 'Permits and certificates verification',
                      isDark: isDark,
                    ),
                  ],
                  if (settingsService.isModuleAllowed(3)) ...[
                    const SizedBox(height: 2),
                    _buildNavItem(
                      index: 3,
                      icon: Icons.content_cut_outlined,
                      activeIcon: Icons.content_cut,
                      label: 'Slaughter & Inspection',
                      subtitle:
                          'Process tagging, post-mortem inspection, MC generation',
                      isDark: isDark,
                    ),
                  ],
                  if (settingsService.isModuleAllowed(4)) ...[
                    const SizedBox(height: 2),
                    _buildNavItem(
                      index: 4,
                      icon: Icons.payment_outlined,
                      activeIcon: Icons.payment,
                      label: 'Payment & Cashiering',
                      subtitle:
                          'Fee calculation, payment recording, receipts',
                      isDark: isDark,
                    ),
                  ],
                  if (settingsService.isModuleAllowed(5)) ...[
                    const SizedBox(height: 2),
                    _buildNavItem(
                      index: 5,
                      icon: Icons.inventory_2_outlined,
                      activeIcon: Icons.inventory_2,
                      label: 'Meat Releasing',
                      subtitle:
                          'Ready for pickup, collection confirmation',
                      isDark: isDark,
                    ),
                  ],
                  if (settingsService.isModuleAllowed(6)) ...[
                    const SizedBox(height: 2),
                    _buildNavItem(
                      index: 6,
                      icon: Icons.assessment_outlined,
                      activeIcon: Icons.assessment,
                      label: 'Reports & Records',
                      subtitle:
                          'Daily, weekly, monthly reports and analytics',
                      badgeCount: _illegalReportBadgeCount,
                      isDark: isDark,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ─── PINNED / FIXED AT THE TOP OF ADMIN ICON LOGO (NON-SCROLLABLE) ───
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
                  width: 1,
                ),
              ),
            ),
            child: _buildNavItem(
              index: 7,
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings,
              label: 'Settings',
              subtitle: 'Fees, Staff, Schedule, Profile',
              isDark: isDark,
            ),
          ),

          // ─── ADMIN FOOTER (Admin Icon / Profile + Logout) ───
          _buildAdminFooter(context, isDark, settingsService),
        ],
      ),
    );
  }

  Widget _buildLogoHeader(bool isDark, AppSettingsService settings) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF334155) : Colors.grey.shade100,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2D6A4F).withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(settings.cityLogoPath, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settings.headerTitle,
                  style: TextStyle(
                    color: isDark
                        ? const Color(0xFF40916C)
                        : const Color(0xFF2D6A4F),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  settings.headerSubtitle,
                  style: TextStyle(
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF718096),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required String subtitle,
    required bool isDark,
    int badgeCount = 0,
  }) {
    final isSelected = widget.selectedIndex == index;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => widget.onItemSelected(index),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF2D6A4F).withValues(alpha: isDark ? 0.25 : 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected
                ? Border.all(
                    color: const Color(0xFF2D6A4F).withValues(alpha: 0.4),
                    width: 1,
                  )
                : Border.all(color: Colors.transparent, width: 1),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                color: isSelected
                    ? (isDark ? const Color(0xFF40916C) : const Color(0xFF2D6A4F))
                    : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF718096)),
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              color: isSelected
                                  ? (isDark
                                      ? const Color(0xFF40916C)
                                      : const Color(0xFF2D6A4F))
                                  : (isDark
                                      ? const Color(0xFFF1F5F9)
                                      : const Color(0xFF2D3748)),
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (badgeCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC2626),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$badgeCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: isSelected
                            ? (isDark
                                ? const Color(0xFF40916C).withValues(alpha: 0.8)
                                : const Color(0xFF2D6A4F).withValues(alpha: 0.7))
                            : (isDark
                                ? const Color(0xFF64748B)
                                : const Color(0xFFA0AEC0)),
                        fontSize: 10.5,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdminFooter(
      BuildContext context, bool isDark, AppSettingsService settings) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF334155) : Colors.grey.shade100,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Admin profile row - clickable to open My Profile tab!
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => widget.onItemSelected(7, 3), // Tab 3 is My Profile
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: isDark
                          ? const Color(0xFF334155)
                          : Colors.grey.shade200,
                      backgroundImage: settings.profilePhotoUrl != null
                          ? NetworkImage(settings.profilePhotoUrl!)
                          : null,
                      child: settings.profilePhotoUrl == null
                          ? Icon(
                              Icons.person_outline,
                              color: isDark
                                  ? Colors.white70
                                  : const Color(0xFF718096),
                              size: 20,
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            settings.profileName,
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF2D3748),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            settings.currentRole,
                            style: TextStyle(
                              color: isDark
                                  ? const Color(0xFF40916C)
                                  : const Color(0xFF2D6A4F),
                              fontWeight: FontWeight.w500,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: isDark ? Colors.white38 : Colors.grey.shade400,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Logout button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('keepMeLoggedIn', false);
                await Supabase.instance.client.auth.signOut();
                if (context.mounted) {
                  Navigator.pushReplacementNamed(context, '/');
                }
              },
              icon: const Icon(Icons.logout, size: 17),
              label: const Text('Logout'),
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    isDark ? const Color(0xFF94A3B8) : const Color(0xFF718096),
                side: BorderSide(
                  color: isDark
                      ? const Color(0xFF334155)
                      : Colors.grey.shade300,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final session = Supabase.instance.client.auth.currentSession;
      final hasStaffSession = AppSettingsService.instance.hasActiveStaffSession;

      if (session == null && !hasStaffSession) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
        return;
      }

      // Verify active staff session against Supabase
      if (hasStaffSession) {
        await AppSettingsService.instance.reloadFromSupabase();
        final staffEmail = AppSettingsService.instance.activeStaffOverrideEmail;
        final validStaff = staffEmail != null &&
            AppSettingsService.instance.staffAccounts.any(
              (s) => s.email.toLowerCase() == staffEmail.toLowerCase() && s.isActive,
            );

        if (!validStaff) {
          // Staff account was deleted or deactivated in Supabase!
          await AppSettingsService.instance.setActiveStaffSession(null);
          await Supabase.instance.client.auth.signOut();
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/login');
          }
          return;
        }
        await AppSettingsService.instance.ensureAdminAuthSession();
      } else if (session != null) {
        // Verify active Supabase Auth user
        try {
          final userRes = await Supabase.instance.client.auth.getUser();
          if (userRes.user == null) {
            throw Exception('Account not found in Supabase');
          }
          AppSettingsService.instance.syncWithAuthUser(session.user);
        } catch (_) {
          await Supabase.instance.client.auth.signOut();
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/login');
          }
        }
      }
    });
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

class _AdminSidebarState extends State<_AdminSidebar>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  int _illegalReportBadgeCount = 0;
  Timer? _badgeTimer;
  late AnimationController _animController;
  late Animation<double> _widthAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _rotateAnimation;
  bool _isCollapsed = false;

  @override
  void initState() {
    super.initState();
    _fetchBadgeCount();
    _badgeTimer =
        Timer.periodic(const Duration(seconds: 12), (_) => _fetchBadgeCount());

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _widthAnimation = Tween<double>(begin: 285.0, end: 72.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeInOutCubic,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.40, curve: Curves.easeOut),
      ),
    );

    _rotateAnimation = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeInOutCubic,
      ),
    );
  }

  @override
  void dispose() {
    _badgeTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _toggleCollapse() {
    setState(() {
      _isCollapsed = !_isCollapsed;
      if (_isCollapsed) {
        _animController.forward();
      } else {
        _animController.reverse();
      }
    });
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

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final currentWidth = _widthAnimation.value;

        return Container(
          width: currentWidth,
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
          child: ClipRect(
            child: SizedBox(
              width: currentWidth,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ─── LOGO HEADER (Fixed compact height) ───
                            _buildLogoHeader(isDark, settingsService),

                            const SizedBox(height: 6),

                            // ─── OPERATIONAL MODULES (0 through 6) ───
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (settingsService.isModuleAllowed(0))
                                    _buildNavItem(
                                      index: 0,
                                      icon: Icons.dashboard_outlined,
                                      activeIcon: Icons.dashboard,
                                      label: settingsService.currentRole == 'Clerk'
                                          ? 'Clerk Dashboard'
                                          : (settingsService.currentRole == 'Inspector'
                                              ? 'Inspector Dashboard'
                                              : 'Dashboard'),
                                      subtitle: settingsService.currentRole == 'Clerk'
                                          ? 'Pending tasks & billing'
                                          : (settingsService.currentRole == 'Inspector'
                                              ? 'Pending tasks & ante-mortem'
                                              : 'Overview & statistics'),
                                      isDark: isDark,
                                    ),
                                  if (settingsService.isModuleAllowed(1)) ...[
                                    const SizedBox(height: 4),
                                    _buildNavItem(
                                      index: 1,
                                      icon: Icons.assignment_outlined,
                                      activeIcon: Icons.assignment,
                                      label: 'Receiving & New Requests',
                                      subtitle: 'Customer details & animal inspection',
                                      isDark: isDark,
                                    ),
                                  ],
                                  if (settingsService.isModuleAllowed(2)) ...[
                                    const SizedBox(height: 4),
                                    _buildNavItem(
                                      index: 2,
                                      icon: Icons.fact_check_outlined,
                                      activeIcon: Icons.fact_check,
                                      label: 'Document Verification',
                                      subtitle: 'Permits & certificates verification',
                                      isDark: isDark,
                                    ),
                                  ],
                                  if (settingsService.isModuleAllowed(3)) ...[
                                    const SizedBox(height: 4),
                                    _buildNavItem(
                                      index: 3,
                                      icon: Icons.content_cut_outlined,
                                      activeIcon: Icons.content_cut,
                                      label: 'Slaughter & Inspection',
                                      subtitle: 'Process tagging & post-mortem',
                                      isDark: isDark,
                                    ),
                                  ],
                                  if (settingsService.isModuleAllowed(4)) ...[
                                    const SizedBox(height: 4),
                                    _buildNavItem(
                                      index: 4,
                                      icon: Icons.payment_outlined,
                                      activeIcon: Icons.payment,
                                      label: 'Payment & Cashiering',
                                      subtitle: 'Fee calculation & receipts',
                                      isDark: isDark,
                                    ),
                                  ],
                                  if (settingsService.isModuleAllowed(5)) ...[
                                    const SizedBox(height: 4),
                                    _buildNavItem(
                                      index: 5,
                                      icon: Icons.inventory_2_outlined,
                                      activeIcon: Icons.inventory_2,
                                      label: 'Meat Releasing',
                                      subtitle: 'Ready for pickup & release',
                                      isDark: isDark,
                                    ),
                                  ],
                                  if (settingsService.isModuleAllowed(6)) ...[
                                    const SizedBox(height: 4),
                                    _buildNavItem(
                                      index: 6,
                                      icon: Icons.assessment_outlined,
                                      activeIcon: Icons.assessment,
                                      label: 'Reports & Records',
                                      subtitle: 'Daily, weekly & monthly analytics',
                                      badgeCount: _illegalReportBadgeCount,
                                      isDark: isDark,
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            const Spacer(),

                            // ─── 24PX GAP WITH SUBTLE DIVIDER LINE ───
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: Divider(
                                height: 1,
                                thickness: 1,
                                color: isDark
                                    ? const Color(0xFF334155)
                                    : Colors.grey.shade200,
                              ),
                            ),

                            // ─── SETTINGS / MY PROFILE (Grouped at bottom next to Profile & Logout) ───
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: _buildNavItem(
                                index: 7,
                                icon: settingsService.isAdmin
                                    ? Icons.settings_outlined
                                    : Icons.person_outline,
                                activeIcon: settingsService.isAdmin
                                    ? Icons.settings
                                    : Icons.person,
                                label: settingsService.isAdmin ? 'Settings' : 'My Profile',
                                subtitle: settingsService.isAdmin
                                    ? 'Fees, Staff, Schedule, Profile'
                                    : 'Account profile & password',
                                isDark: isDark,
                              ),
                            ),

                            const SizedBox(height: 4),

                            // ─── ADMIN FOOTER (Admin Avatar & Logout) ───
                            _buildAdminFooter(context, isDark, settingsService),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLogoHeader(
      bool isDark, AppSettingsService settings) {
    return Container(
      height: 66,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF334155) : Colors.grey.shade100,
            width: 1,
          ),
        ),
      ),
      child: AnimatedCrossFade(
        duration: const Duration(milliseconds: 280),
        firstCurve: Curves.easeInOutCubic,
        secondCurve: Curves.easeInOutCubic,
        sizeCurve: Curves.easeInOutCubic,
        crossFadeState: _isCollapsed ? CrossFadeState.showSecond : CrossFadeState.showFirst,
        firstChild: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2D6A4F).withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(settings.cityLogoPath, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRect(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          settings.headerTitle,
                          style: TextStyle(
                            color: isDark
                                ? const Color(0xFF40916C)
                                : const Color(0xFF2D6A4F),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          settings.headerSubtitle,
                          style: TextStyle(
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF718096),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
              IconButton(
                icon: RotationTransition(
                  turns: _rotateAnimation,
                  child: Icon(
                    Icons.menu_open_rounded,
                    color: isDark ? Colors.white60 : const Color(0xFF718096),
                    size: 20,
                  ),
                ),
                tooltip: 'Collapse Sidebar',
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: _toggleCollapse,
              ),
            ],
          ),
        ),
        secondChild: Container(
          width: 72,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipOval(
                  child: Image.asset(settings.cityLogoPath, width: 26, height: 26, fit: BoxFit.cover),
                ),
                const SizedBox(height: 3),
                InkWell(
                  onTap: _toggleCollapse,
                  borderRadius: BorderRadius.circular(4),
                  child: Tooltip(
                    message: 'Expand Sidebar',
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: RotationTransition(
                        turns: _rotateAnimation,
                        child: Icon(
                          Icons.menu_rounded,
                          color: isDark ? Colors.white70 : const Color(0xFF2D6A4F),
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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

    final itemWidget = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => widget.onItemSelected(index),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF2D6A4F).withValues(alpha: isDark ? 0.25 : 0.12)
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
              // ─── ANCHORED ICON SLOT (48px wide: centered in 72px collapsed strip) ───
              SizedBox(
                width: 48,
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        isSelected ? activeIcon : icon,
                        color: isSelected
                            ? (isDark ? const Color(0xFF40916C) : const Color(0xFF2D6A4F))
                            : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF718096)),
                        size: 20,
                      ),
                      if (badgeCount > 0)
                        Positioned(
                          right: -7,
                          top: -5,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC2626),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                            child: Text(
                              '$badgeCount',
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
              ),
              if (_animController.value < 0.95)
                Expanded(
                child: ClipRect(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
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
                                  fontSize: 12.5,
                                  height: 1.15,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                softWrap: false,
                              ),
                            ),
                            if (badgeCount > 0) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDC2626),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$badgeCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
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
                            fontSize: 10,
                            height: 1.15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );

    if (_isCollapsed) {
      return Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 200),
        child: itemWidget,
      );
    }
    return itemWidget;
  }

  Widget _buildAdminFooter(
      BuildContext context, bool isDark, AppSettingsService settings) {
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 280),
      firstCurve: Curves.easeInOutCubic,
      secondCurve: Curves.easeInOutCubic,
      sizeCurve: Curves.easeInOutCubic,
      crossFadeState: _isCollapsed ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      firstChild: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Admin profile row - clickable to open My Profile tab!
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () => widget.onItemSelected(7, 3), // Tab 3 is My Profile
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
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
                                size: 18,
                              )
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: ClipRect(
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
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  softWrap: false,
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  settings.currentRole,
                                  style: TextStyle(
                                    color: isDark
                                        ? const Color(0xFF40916C)
                                        : const Color(0xFF2D6A4F),
                                    fontWeight: FontWeight.w500,
                                    fontSize: 10.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  softWrap: false,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: isDark ? Colors.white38 : Colors.grey.shade400,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Logout button
            SizedBox(
              width: double.infinity,
              height: 32,
              child: OutlinedButton.icon(
                onPressed: () => _handleLogout(context),
                icon: const Icon(Icons.logout, size: 15),
                label: FadeTransition(
                  opacity: _fadeAnimation,
                  child: const Text('Logout', style: TextStyle(fontSize: 12)),
                ),
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
                  padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                ),
              ),
            ),
          ],
        ),
      ),
      secondChild: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: '${settings.profileName} (${settings.currentRole})',
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => widget.onItemSelected(7, 3), // Tab 3 is My Profile
                  child: CircleAvatar(
                    radius: 15,
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
                            size: 16,
                          )
                        : null,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Tooltip(
              message: 'Logout',
              child: IconButton(
                icon: const Icon(Icons.logout, size: 18),
                splashRadius: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF718096),
                onPressed: () => _handleLogout(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('keepMeLoggedIn', false);
    await AppSettingsService.instance.setActiveStaffSession(null);
    await Supabase.instance.client.auth.signOut();
    if (context.mounted) {
      Navigator.pushReplacementNamed(context, '/');
    }
  }
}

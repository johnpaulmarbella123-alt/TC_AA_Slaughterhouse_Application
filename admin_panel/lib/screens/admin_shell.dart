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
import '../services/staff_notification_service.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _selectedIndex = 0;
  String? _reportsInitialTab;
  int _settingsInitialTab = 0;
  int _settingsNavVersion = 0;
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

      // Start staff bell notifications (admin/clerk/inspector) once session is verified
      if (mounted) StaffNotificationService.instance.start();
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
        _settingsNavVersion++;
      } else if (index == 7 && tabArg == 'customers') {
        _settingsInitialTab = 5;
        _settingsNavVersion++;
      } else if (index == 7 && tabArg == 'feedback') {
        _settingsInitialTab = 6;
        _settingsNavVersion++;
      } else if (index == 7) {
        _settingsNavVersion++;
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
                        ? ReceivingRequestsPage(onNavigate: _onNavigate)
                        : const SizedBox.shrink(),
                    _loadedPages.contains(2)
                        ? DocumentVerificationPage(onNavigate: _onNavigate)
                        : const SizedBox.shrink(),
                    _loadedPages.contains(3)
                        ? SlaughterInspectionPage(onNavigate: _onNavigate)
                        : const SizedBox.shrink(),
                    _loadedPages.contains(4)
                        ? PaymentCashieringPage(onNavigate: _onNavigate)
                        : const SizedBox.shrink(),
                    _loadedPages.contains(5)
                        ? MeatReleasingPage(onNavigate: _onNavigate)
                        : const SizedBox.shrink(),
                    _loadedPages.contains(6)
                        ? ReportsRecordsPage(
                            initialTab: _reportsInitialTab,
                          )
                        : const SizedBox.shrink(),
                    _loadedPages.contains(7)
                        ? SettingsPage(
                            initialTab: _settingsInitialTab,
                            navVersion: _settingsNavVersion,
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
  bool _isCollapsed = false;

  @override
  void initState() {
    super.initState();
    _fetchBadgeCount();
    _badgeTimer =
        Timer.periodic(const Duration(seconds: 25), (_) => _fetchBadgeCount());

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _widthAnimation = Tween<double>(begin: 288.0, end: 80.0).animate(
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
            color: const Color(0xFF0F5132),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 15,
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
                            // ─── LOGO HEADER ───
                            _buildLogoHeader(isDark, settingsService),

                            const SizedBox(height: 14),

                            // ─── OPERATIONAL MODULES (0 through 7) ───
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (settingsService.isModuleAllowed(0))
                                    _buildNavItem(
                                      index: 0,
                                      icon: Icons.grid_view_outlined,
                                      activeIcon: Icons.grid_view_rounded,
                                      label: 'Dashboard',
                                      subtitle: '',
                                      isDark: isDark,
                                    ),
                                  if (settingsService.isModuleAllowed(1)) ...[
                                    const SizedBox(height: 4),
                                    _buildNavItem(
                                      index: 1,
                                      icon: Icons.assignment_outlined,
                                      activeIcon: Icons.assignment,
                                      label: 'Receiving',
                                      subtitle: '',
                                      isDark: isDark,
                                    ),
                                  ],
                                  if (settingsService.isModuleAllowed(2)) ...[
                                    const SizedBox(height: 4),
                                    _buildNavItem(
                                      index: 2,
                                      icon: Icons.fact_check_outlined,
                                      activeIcon: Icons.fact_check,
                                      label: 'Verification',
                                      subtitle: '',
                                      isDark: isDark,
                                    ),
                                  ],
                                  if (settingsService.isModuleAllowed(3)) ...[
                                    const SizedBox(height: 4),
                                    _buildNavItem(
                                      index: 3,
                                      icon: Icons.medical_services_outlined,
                                      activeIcon: Icons.medical_services,
                                      label: 'Inspection',
                                      subtitle: '',
                                      isDark: isDark,
                                    ),
                                  ],
                                  if (settingsService.isModuleAllowed(4)) ...[
                                    const SizedBox(height: 4),
                                    _buildNavItem(
                                      index: 4,
                                      icon: Icons.payments_outlined,
                                      activeIcon: Icons.payments,
                                      label: 'Cashiering',
                                      subtitle: '',
                                      isDark: isDark,
                                    ),
                                  ],
                                  if (settingsService.isModuleAllowed(5)) ...[
                                    const SizedBox(height: 4),
                                    _buildNavItem(
                                      index: 5,
                                      icon: Icons.local_shipping_outlined,
                                      activeIcon: Icons.local_shipping,
                                      label: 'Releasing',
                                      subtitle: '',
                                      isDark: isDark,
                                    ),
                                  ],
                                  if (settingsService.isModuleAllowed(6)) ...[
                                    const SizedBox(height: 4),
                                    _buildNavItem(
                                      index: 6,
                                      icon: Icons.description_outlined,
                                      activeIcon: Icons.description,
                                      label: 'Reports',
                                      subtitle: '',
                                      badgeCount: _illegalReportBadgeCount,
                                      isDark: isDark,
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            const Spacer(),

                            const SizedBox(height: 8),

                            // ─── PINNED SETTINGS (Admin Only) ───
                            if (settingsService.isAdmin) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                child: Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: Colors.white.withValues(alpha: 0.10),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: _buildNavItem(
                                  index: 7,
                                  icon: Icons.settings_outlined,
                                  activeIcon: Icons.settings,
                                  label: 'Settings',
                                  subtitle: '',
                                  isDark: isDark,
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],

                            // ─── FOOTER (Profile + Sign Out) ───
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

  Widget _buildLogoHeader(bool isDark, AppSettingsService settings) {
    return Container(
      height: 78,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.10),
            width: 1,
          ),
        ),
      ),
      child: AnimatedCrossFade(
        duration: const Duration(milliseconds: 200),
        firstCurve: Curves.easeInOutCubic,
        secondCurve: Curves.easeInOutCubic,
        sizeCurve: Curves.easeInOutCubic,
        crossFadeState: _isCollapsed ? CrossFadeState.showSecond : CrossFadeState.showFirst,
        firstChild: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset('assets/images/logo1.png', fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ClipRect(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CITY OF TABACO, ALBAY',
                          style: TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                            letterSpacing: 0.9,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                        ),
                        SizedBox(height: 2),
                        Text(
                          'City Abattoir System',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            height: 1.2,
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
              IconButton(
                icon: _buildPanelToggleIcon(isCollapsed: false),
                tooltip: 'Collapse Sidebar',
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: _toggleCollapse,
              ),
            ],
          ),
        ),
        secondChild: Container(
          width: 80,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset('assets/images/logo1.png', fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: _toggleCollapse,
                  borderRadius: BorderRadius.circular(4),
                  child: Tooltip(
                    message: 'Expand Sidebar',
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: _buildPanelToggleIcon(isCollapsed: true),
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

  Widget _buildPanelToggleIcon({required bool isCollapsed}) {
    const color = Color(0xFFCBD5E1);
    return Container(
      width: 20,
      height: 18,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4.5),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        children: [
          const SizedBox(width: 4.5),
          Container(width: 1.4, height: double.infinity, color: color),
          Expanded(
            child: Center(
              child: Icon(
                isCollapsed ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
                size: 12,
                color: color,
              ),
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

    final itemWidget = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => widget.onItemSelected(index),
        borderRadius: BorderRadius.circular(8),
        hoverColor: Colors.white.withValues(alpha: 0.10),
        child: Container(
          padding: _isCollapsed
              ? const EdgeInsets.symmetric(vertical: 12)
              : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment:
                _isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    isSelected ? activeIcon : icon,
                    color: isSelected
                        ? const Color(0xFF0F5132)
                        : const Color(0xFFE2E8F0),
                    size: 20,
                  ),
                  if (badgeCount > 0 && _isCollapsed)
                    Positioned(
                      right: -7,
                      top: -5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFB91C1C),
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
              if (_animController.value < 0.95)
                Expanded(
                  child: ClipRect(
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                label,
                                style: TextStyle(
                                  color: isSelected
                                      ? const Color(0xFF0F5132)
                                      : const Color(0xFFE2E8F0),
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                softWrap: false,
                              ),
                            ),
                            if (badgeCount > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFB91C1C),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$badgeCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
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
    final photoUrl = settings.profilePhotoUrl?.trim() ?? '';
    final hasPhoto = photoUrl.isNotEmpty;
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 200),
      firstCurve: Curves.easeInOutCubic,
      secondCurve: Curves.easeInOutCubic,
      sizeCurve: Curves.easeInOutCubic,
      crossFadeState: _isCollapsed ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      firstChild: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.10), width: 1),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () => widget.onItemSelected(7, 3),
                borderRadius: BorderRadius.circular(8),
                hoverColor: Colors.white.withValues(alpha: 0.10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.white.withValues(alpha: 0.14),
                        backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
                        child: hasPhoto
                            ? null
                            : const Icon(
                                Icons.person_outline_rounded,
                                size: 20,
                                color: Color(0xFFE2E8F0),
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ClipRect(
                          child: FadeTransition(
                            opacity: _fadeAnimation,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  settings.profileName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  settings.currentRole,
                                  style: const TextStyle(
                                    color: Color(0xFF6EE7B7),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: TextButton.icon(
                onPressed: () => _handleLogout(context),
                icon: const Icon(Icons.logout_rounded, size: 18, color: Color(0xFFE2E8F0)),
                label: FadeTransition(
                  opacity: _fadeAnimation,
                  child: const Text(
                    'Sign Out',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.hovered) ||
                        states.contains(WidgetState.pressed)) {
                      return Colors.white.withValues(alpha: 0.20);
                    }
                    return Colors.white.withValues(alpha: 0.10);
                  }),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      secondChild: Container(
        width: 80,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.10), width: 1),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: '${settings.profileName} • My Profile',
              child: InkWell(
                onTap: () => widget.onItemSelected(7, 3),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: CircleAvatar(
                    radius: 17,
                    backgroundColor: Colors.white.withValues(alpha: 0.14),
                    backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
                    child: hasPhoto
                        ? null
                        : const Icon(
                            Icons.person_outline_rounded,
                            size: 19,
                            color: Color(0xFFE2E8F0),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Tooltip(
              message: 'Sign Out',
              child: IconButton(
                icon: const Icon(Icons.logout_rounded, size: 20, color: Color(0xFFE2E8F0)),
                splashRadius: 18,
                onPressed: () => _handleLogout(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    StaffNotificationService.instance.stop();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('keepMeLoggedIn', false);
    await AppSettingsService.instance.setActiveStaffSession(null);
    await Supabase.instance.client.auth.signOut();
    if (context.mounted) {
      Navigator.pushReplacementNamed(context, '/');
    }
  }
}

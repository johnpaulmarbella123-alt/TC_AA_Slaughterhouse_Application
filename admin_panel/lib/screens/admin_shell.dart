import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dashboard.dart';
import 'receiving_requests_page.dart';
import 'document_verification_page.dart';
import 'slaughter_inspection_page.dart';
import 'payment_cashiering_page.dart';
import 'meat_releasing_page.dart';
import 'reports_records_page.dart';
import 'illegal_slaughter_page.dart';
import 'settings_page.dart';
import '../services/app_settings_service.dart';
import '../services/admin_realtime_hub.dart';
import '../services/audit_log_service.dart';
import '../services/staff_notification_service.dart';
import '../widgets/dialog_blur_observer.dart';
import '../widgets/lucide_sidebar_icons.dart';
import '../widgets/staff_notification_bell.dart';
import '../utils/admin_responsive.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;
  String? _reportsInitialTab;
  int _settingsInitialTab = 0;
  int _settingsNavVersion = 0;
  final Set<int> _loadedPages = {0};
  final List<int> _navHistory = [];

  String _moduleTitle(int index) {
    switch (index) {
      case 0:
        return 'Dashboard';
      case 1:
        return 'Receiving & Inspection';
      case 2:
        return 'Document Verification';
      case 3:
        return 'Slaughter & Inspection';
      case 4:
        return 'Payment & Cashiering';
      case 5:
        return 'Meat Releasing';
      case 6:
        return 'Reports & Records';
      case 7:
        return AppSettingsService.instance.isAdmin ? 'System Settings' : 'My Profile';
      case 8:
        return 'Illegal Slaughter Reports';
      default:
        return 'TC "AA" Slaughterhouse';
    }
  }

  String _moduleShortName(int index) {
    switch (index) {
      case 0:
        return 'Dashboard';
      case 1:
        return 'Receiving';
      case 2:
        return 'Verification';
      case 3:
        return 'Inspection';
      case 4:
        return 'Cashiering';
      case 5:
        return 'Releasing';
      case 6:
        return 'Reports';
      case 7:
        return 'Settings';
      case 8:
        return 'Illegal Reports';
      default:
        return 'Previous';
    }
  }

  String _moduleSubtitle(int index) {
    switch (index) {
      case 1:
        return 'Livestock intake, walk-in registration, and request approval';
      case 2:
        return 'Verify uploaded barangay certificates, ownership proofs, and vet permits';
      case 3:
        return 'Ante-mortem inspection, slaughter workflow, post-mortem, and MIC issuance';
      case 4:
        return 'Fee billing, official receipts, cash drawer & online Xendit reconciliation';
      case 5:
        return 'Ready for pickup, delivery handover, and collection verification';
      case 6:
        return 'Analytics, abattoir records, dealer logs, customer reviews & audit trails';
      case 7:
        return AppSettingsService.instance.isSuperAdmin
            ? 'Configure fees, staff accounts & roles, schedule, profile, and appearance'
            : AppSettingsService.instance.isAdmin
                ? 'Configure fees, schedule, profile, appearance, and customer accounts'
                : 'Manage your staff profile and account preferences';
      case 8:
        return 'Community whistleblower reports, evidence verification, and enforcement tracking';
      default:
        return '';
    }
  }

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
          await AppSettingsService.instance.reloadFromSupabase();
        } catch (_) {
          await Supabase.instance.client.auth.signOut();
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/login');
          }
        }
      }

      // Start staff bell notifications & shared real-time transaction hub once session is verified
      if (mounted) {
        StaffNotificationService.instance.start();
        AdminRealtimeHub.instance.start();
      }
    });
  }

  void _onNavigate(int index, [dynamic tabArg, bool recordHistory = true]) {
    setState(() {
      int targetIndex = index;
      dynamic resolvedTab = tabArg;

      // Redirect legacy routes cleanly:
      // - (6, 'Report Illegal') -> dedicated Admin-only Illegal Reports page (index 8)
      // - (7, 'feedback') -> Reports & Records -> Customer Reviews
      if (index == 6 && tabArg == 'Report Illegal') {
        targetIndex = 8;
        resolvedTab = null;
      } else if (index == 7 && tabArg == 'feedback') {
        targetIndex = 6;
        resolvedTab = 'Customer Reviews';
      }

      if (recordHistory && targetIndex != _selectedIndex) {
        if (_navHistory.isEmpty || _navHistory.last != _selectedIndex) {
          _navHistory.add(_selectedIndex);
          if (_navHistory.length > 15) {
            _navHistory.removeAt(0);
          }
        }
      }

      _selectedIndex = targetIndex;
      _loadedPages.add(targetIndex);
      if (targetIndex == 6 && resolvedTab is String) {
        _reportsInitialTab = resolvedTab;
      } else if (targetIndex == 7 && resolvedTab == 'profile') {
        _settingsInitialTab = AppSettingsService.instance.isSuperAdmin ? 3 : 2;
        _settingsNavVersion++;
      } else if (targetIndex == 7 && resolvedTab == 'customers') {
        _settingsInitialTab = AppSettingsService.instance.isSuperAdmin ? 5 : 4;
        _settingsNavVersion++;
      } else if (targetIndex == 7 && resolvedTab is int) {
        final maxTab = AppSettingsService.instance.isSuperAdmin ? 5 : 4;
        _settingsInitialTab = resolvedTab.clamp(0, maxTab);
        _settingsNavVersion++;
      } else if (targetIndex == 7) {
        _settingsNavVersion++;
      }
    });
  }

  void _goBack() {
    if (_navHistory.isEmpty) return;
    final prev = _navHistory.removeLast();
    _onNavigate(prev, null, false);
  }

  Widget _buildPersistentDesktopHeader() {
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now());
    final canGoBack = _navHistory.isNotEmpty;
    final prevName = canGoBack ? _moduleShortName(_navHistory.last) : '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: 100% fixed Title & Subtitle (never shifts horizontally)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _moduleTitle(_selectedIndex),
                  style: const TextStyle(
                    fontSize: 23,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _moduleSubtitle(_selectedIndex),
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF475569),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Middle-Right: Back button (appears without shifting Title or Bell/Date)
          if (canGoBack) ...[
            Tooltip(
              message: 'Return to $prevName',
              child: InkWell(
                onTap: _goBack,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D6A4F).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF2D6A4F).withValues(alpha: 0.28)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back_rounded, size: 16, color: Color(0xFF1B4332)),
                      const SizedBox(width: 5),
                      Text(
                        'Back to $prevName',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1B4332),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          // Fixed right-side utilities: Notification Bell FIRST, Date pill SECOND
          StaffNotificationBell(
            onNavigate: (m, [tab]) => _onNavigate(m, tab),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              dateStr,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF4A5568)),
            ),
          ),
        ],
      ),
    );
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

        final isCompact = AdminResponsive.isCompact(context);

        final contentStack = IndexedStack(
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
            _loadedPages.contains(8)
                ? IllegalSlaughterPage(onNavigate: _onNavigate)
                : const SizedBox.shrink(),
          ],
        );

        final shellBody = isCompact
            ? contentStack
            : Row(
                children: [
                  // ─── DESKTOP SIDEBAR ───
                  _AdminSidebar(
                    selectedIndex: _selectedIndex,
                    onItemSelected: (idx, [tab]) => _onNavigate(idx, tab),
                  ),
                  // ─── CONTENT AREA (Persistent Top Bar + Preserved Pages) ───
                  Expanded(
                    child: Column(
                      children: [
                        if (_selectedIndex != 0) _buildPersistentDesktopHeader(),
                        Expanded(child: contentStack),
                      ],
                    ),
                  ),
                ],
              );

        return Scaffold(
          key: _scaffoldKey,
          appBar: isCompact
              ? AppBar(
                  backgroundColor: const Color(0xFF0F5132),
                  foregroundColor: Colors.white,
                  elevation: 1,
                  titleSpacing: 4,
                  leading: IconButton(
                    icon: const Icon(Icons.menu_rounded, color: Colors.white),
                    tooltip: 'Open Menu',
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                  title: Text(
                    _moduleTitle(_selectedIndex),
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  actions: [
                    if (_navHistory.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                        tooltip: 'Back to ${_moduleShortName(_navHistory.last)}',
                        onPressed: _goBack,
                      ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          iconTheme: const IconThemeData(color: Colors.white),
                        ),
                        child: StaffNotificationBell(
                          onNavigate: (m, [tab]) => _onNavigate(m, tab),
                        ),
                      ),
                    ),
                  ],
                )
              : null,
          drawer: isCompact
              ? Drawer(
                  width: 288,
                  backgroundColor: const Color(0xFF0F5132),
                  child: SafeArea(
                    child: _AdminSidebar(
                      selectedIndex: _selectedIndex,
                      isDrawerMode: true,
                      onItemSelected: (idx, [tab]) {
                        Navigator.of(context).pop();
                        _onNavigate(idx, tab);
                      },
                    ),
                  ),
                )
              : null,
          body: ValueListenableBuilder<bool>(
            valueListenable: DialogBlurObserver.instance.hasActiveDialog,
            child: shellBody,
            builder: (context, hasDialog, child) {
              return TweenAnimationBuilder<double>(
                tween: Tween<double>(end: hasDialog ? 4.0 : 0.0),
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: child,
                builder: (context, sigma, innerChild) {
                  return ImageFiltered(
                    enabled: sigma > 0.05,
                    imageFilter: ImageFilter.blur(
                      sigmaX: sigma,
                      sigmaY: sigma,
                      tileMode: TileMode.clamp,
                    ),
                    child: innerChild,
                  );
                },
              );
            },
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
  final bool isDrawerMode;
  final void Function(int index, [dynamic tab]) onItemSelected;

  const _AdminSidebar({
    required this.selectedIndex,
    required this.onItemSelected,
    this.isDrawerMode = false,
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
                            _buildLogoHeader(isDark, settingsService, currentWidth),

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
                                      icon: LucideSidebarIcon.layoutGrid,
                                      label: 'Dashboard',
                                      subtitle: '',
                                      isDark: isDark,
                                      currentWidth: currentWidth,
                                    ),
                                  if (settingsService.isModuleAllowed(1)) ...[
                                    const SizedBox(height: 4),
                                    _buildNavItem(
                                      index: 1,
                                      icon: LucideSidebarIcon.clipboardPlus,
                                      label: 'Receiving',
                                      subtitle: '',
                                      isDark: isDark,
                                      currentWidth: currentWidth,
                                    ),
                                  ],
                                  if (settingsService.isModuleAllowed(2)) ...[
                                    const SizedBox(height: 4),
                                    _buildNavItem(
                                      index: 2,
                                      icon: LucideSidebarIcon.clipboardCheck,
                                      label: 'Verification',
                                      subtitle: '',
                                      isDark: isDark,
                                      currentWidth: currentWidth,
                                    ),
                                  ],
                                  if (settingsService.isModuleAllowed(3)) ...[
                                    const SizedBox(height: 4),
                                    _buildNavItem(
                                      index: 3,
                                      icon: LucideSidebarIcon.stethoscope,
                                      label: 'Inspection',
                                      subtitle: '',
                                      isDark: isDark,
                                      currentWidth: currentWidth,
                                    ),
                                  ],
                                  if (settingsService.isModuleAllowed(4)) ...[
                                    const SizedBox(height: 4),
                                    _buildNavItem(
                                      index: 4,
                                      icon: LucideSidebarIcon.receiptDollar,
                                      label: 'Cashiering',
                                      subtitle: '',
                                      isDark: isDark,
                                      currentWidth: currentWidth,
                                    ),
                                  ],
                                  if (settingsService.isModuleAllowed(5)) ...[
                                    const SizedBox(height: 4),
                                    _buildNavItem(
                                      index: 5,
                                      icon: LucideSidebarIcon.truck,
                                      label: 'Releasing',
                                      subtitle: '',
                                      isDark: isDark,
                                      currentWidth: currentWidth,
                                    ),
                                  ],
                                  if (settingsService.isModuleAllowed(6)) ...[
                                    const SizedBox(height: 4),
                                    _buildNavItem(
                                      index: 6,
                                      icon: LucideSidebarIcon.fileText,
                                      label: 'Reports',
                                      subtitle: '',
                                      isDark: isDark,
                                      currentWidth: currentWidth,
                                    ),
                                  ],
                                  if (settingsService.isModuleAllowed(8)) ...[
                                    const SizedBox(height: 4),
                                    _buildNavItem(
                                      index: 8,
                                      icon: LucideSidebarIcon.shieldAlert,
                                      label: 'Illegal Reports',
                                      subtitle: '',
                                      badgeCount: _illegalReportBadgeCount,
                                      isDark: isDark,
                                      currentWidth: currentWidth,
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
                                  icon: LucideSidebarIcon.settings,
                                  label: 'Settings',
                                  subtitle: '',
                                  isDark: isDark,
                                  currentWidth: currentWidth,
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],

                            // ─── FOOTER (Profile + Sign Out) ───
                            _buildAdminFooter(context, isDark, settingsService, currentWidth),
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

  Widget _buildFormalSidebarLogo(String logoPath, {required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.78),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 5,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          logoPath,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          isAntiAlias: true,
          errorBuilder: (_, _, _) => Image.asset(
            'assets/images/logo1.png',
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            isAntiAlias: true,
          ),
        ),
      ),
    );
  }

  Widget _buildLogoHeader(bool isDark, AppSettingsService settings, double currentWidth) {
    final showCollapsed = currentWidth < 115;
    final logoPath = settings.cityLogoPath.trim().isNotEmpty
        ? settings.cityLogoPath.trim()
        : 'assets/images/logo1.png';
    final headerTitle = settings.headerTitle.trim().isNotEmpty
        ? settings.headerTitle.trim()
        : 'TC "AA" Slaughterhouse';
    final headerSubtitle = settings.headerSubtitle.trim().isNotEmpty
        ? settings.headerSubtitle.trim()
        : 'CITY OF TABACO, ALBAY';
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
      child: showCollapsed
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Tooltip(
                      message: 'Go to Dashboard',
                      child: Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          onTap: () => widget.onItemSelected(0),
                          customBorder: const CircleBorder(),
                          hoverColor: Colors.white.withValues(alpha: 0.10),
                          child: _buildFormalSidebarLogo(logoPath, size: 38),
                        ),
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
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Container(
                width: 288,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Tooltip(
                        message: 'Go to Dashboard',
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            onTap: () => widget.onItemSelected(0),
                            borderRadius: BorderRadius.circular(10),
                            hoverColor: Colors.white.withValues(alpha: 0.08),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                              child: Row(
                                children: [
                                  _buildFormalSidebarLogo(logoPath, size: 52),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ClipRect(
                                      child: FadeTransition(
                                        opacity: _fadeAnimation,
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              headerSubtitle,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w400,
                                                letterSpacing: 0.55,
                                                color: Color(0xFFCBD5E1),
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              softWrap: false,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              headerTitle,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                height: 1.25,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              softWrap: false,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: widget.isDrawerMode
                          ? const Icon(Icons.close_rounded, color: Colors.white70, size: 20)
                          : _buildPanelToggleIcon(isCollapsed: false),
                      tooltip: widget.isDrawerMode ? 'Close Menu' : 'Collapse Sidebar',
                      splashRadius: 18,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                      onPressed: widget.isDrawerMode
                          ? () => Navigator.of(context).pop()
                          : _toggleCollapse,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPanelToggleIcon({required bool isCollapsed}) {
    return LucideIcon(
      isCollapsed ? LucideSidebarIcon.panelLeftOpen : LucideSidebarIcon.panelLeftClose,
      size: 20,
      color: const Color(0xFFCBD5E1),
    );
  }

  Widget _buildNavItem({
    required int index,
    required LucideSidebarIcon icon,
    required String label,
    required String subtitle,
    required bool isDark,
    required double currentWidth,
    int badgeCount = 0,
  }) {
    final isSelected = widget.selectedIndex == index;
    final t = _animController.value;
    final isFullyCollapsed = currentWidth < 115;
    // Pill is 60px wide when collapsed (80px - 20px outer padding), so left = 20px
    // centers the 20px icon without ever switching MainAxisAlignment or jumping right.
    final leftPad = 16.0 + (4.0 * t);
    final rightPad = 16.0 * (1.0 - t);

    final itemWidget = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => widget.onItemSelected(index),
        borderRadius: BorderRadius.circular(10),
        hoverColor: Colors.white.withValues(alpha: 0.10),
        child: Container(
          padding: EdgeInsets.fromLTRB(leftPad, 14, rightPad, 14),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  LucideIcon(
                    icon,
                    color: isSelected
                        ? const Color(0xFF0F5132)
                        : const Color(0xFFE2E8F0),
                    size: 20,
                  ),
                  if (badgeCount > 0 && isFullyCollapsed)
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
              if (!isFullyCollapsed)
                Expanded(
                  child: ClipRect(
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontFamily: 'Segoe UI',
                                  fontSize: 15,
                                  height: 20 / 15,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isSelected
                                      ? const Color(0xFF0F5132)
                                      : const Color(0xFFE2E8F0),
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

    if (isFullyCollapsed) {
      return Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 200),
        child: itemWidget,
      );
    }
    return itemWidget;
  }

  Widget _buildAdminFooter(
      BuildContext context, bool isDark, AppSettingsService settings, double currentWidth) {
    final photoUrl = settings.profilePhotoUrl?.trim() ?? '';
    final hasPhoto = photoUrl.isNotEmpty;
    final showCollapsed = currentWidth < 115;

    if (showCollapsed) {
      return Container(
        width: double.infinity,
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
                onTap: () => widget.onItemSelected(7, 'profile'),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: CircleAvatar(
                    radius: 17,
                    backgroundColor: Colors.white.withValues(alpha: 0.14),
                    backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
                    child: hasPhoto
                        ? null
                        : const LucideIcon(
                            LucideSidebarIcon.user,
                            size: 18,
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
                icon: const LucideIcon(
                  LucideSidebarIcon.logOut,
                  size: 20,
                  color: Color(0xFFE2E8F0),
                ),
                splashRadius: 18,
                onPressed: () => _handleLogout(context),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Container(
        width: 288,
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
                onTap: () => widget.onItemSelected(7, 'profile'),
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
                            : const LucideIcon(
                                LucideSidebarIcon.user,
                                size: 18,
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
                                    fontFamily: 'Segoe UI',
                                    color: Colors.white,
                                    fontSize: 14,
                                    height: 20 / 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  settings.currentRole,
                                  style: const TextStyle(
                                    fontFamily: 'Segoe UI',
                                    color: Color(0xFF6EE7B7),
                                    fontSize: 12,
                                    height: 16 / 12,
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
              child: TextButton(
                onPressed: () => _handleLogout(context),
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const LucideIcon(
                      LucideSidebarIcon.logOut,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: const Text(
                        'Sign Out',
                        style: TextStyle(
                          fontFamily: 'Segoe UI',
                          fontSize: 14,
                          height: 20 / 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    await AuditLogService.instance.log(
      action: 'staff_logout',
      module: 'Authentication',
      targetRef: AppSettingsService.instance.profileEmail,
      details: {
        'role': AppSettingsService.instance.currentRole,
        'name': AppSettingsService.instance.profileName,
      },
    );
    AdminRealtimeHub.instance.stop();
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

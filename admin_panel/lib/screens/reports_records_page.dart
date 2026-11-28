import 'dart:typed_data';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import 'customer_reviews_view.dart';
import 'audit_logs_tab.dart';
import '../services/app_settings_service.dart';
import '../services/admin_realtime_hub.dart';
import '../services/audit_log_service.dart';
import '../services/notification_service.dart';
import '../services/csv_export_helper.dart';
import '../services/report_pdf_generator.dart';
import '../services/regular_dealers_service.dart';
import '../services/nmic_report_pdf_generator.dart';
import '../utils/text_capitalization_formatters.dart';
import '../utils/phone_number_formatter.dart';
import '../utils/admin_responsive.dart';
import '../widgets/animated_date_dropdown.dart';
import '../widgets/animated_date_range_dropdown.dart';
import '../widgets/animated_export_dropdown.dart';
import '../widgets/animated_select_dropdown.dart';

class ReportsRecordsPage extends StatefulWidget {
  final String? initialTab;
  const ReportsRecordsPage({super.key, this.initialTab});
  @override
  State<ReportsRecordsPage> createState() => _ReportsRecordsPageState();
}

class _ReportsRecordsPageState extends State<ReportsRecordsPage> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;

  // All requests enriched with inspections and payments
  List<Map<String, dynamic>> _allRequests = [];

  // Filter state
  String _reportType = 'Daily Report'; // 'Daily Report', 'Weekly Report', 'Monthly Report', 'Custom Range'
  late String _activeTab;

  // Unified date & filter state (single source of truth across all report views)
  DateTime? _selectedDate = DateTime.now();
  DateTimeRange? _customDateRange;
  int _customRangeOpenVersion = 0;
  int _dealerLogStartDay = 1;
  bool _trendShowRevenue = true;
  String _analyticsSectionFilter = 'section1'; // 'section1' | 'section2' | 'section3' | 'all'

  StreamSubscription<String>? _realtimeSub;

  // Derived dates so all tabs share the single unified calendar/date picker
  DateTime get _nmicReportDate => _activeDate();
  DateTime get _monthlyLogMonth => DateTime(_activeDate().year, _activeDate().month);

  // NMIC & Abattoir Official Reports state
  String _selectedNmicSpecies = 'HOG';
  String _selectedNmicFormType = 'Weekly Summary';
  String? _selectedCustomerFilter;
  List<Map<String, dynamic>> _nmicTransmissionsList = [];
  String _dealerSearchQuery = '';
  String _dealerCategoryFilter = 'All'; // 'All', 'Market', 'Barangay', 'New'
  List<Map<String, dynamic>> _roleChangeRequests = [];
  bool _loadingRoleChanges = false;
  RealtimeChannel? _roleChangeChannel;

  List<String> get _availableReportViews => [
        'Analytics',
        'Daily Production (Abattoir)',
        'Monthly Dealer Log',
        'NMIS Reports & Transmittal',
        'Customer Records',
        'Meat Dealers Directory',
        'Customer Reviews',
        if (AppSettingsService.instance.isSuperAdmin) 'Audit Logs',
      ];

  String _normalizeTab(String? tab) {
    if (tab == null || tab.isEmpty || tab == 'Report Illegal') {
      return 'Analytics';
    }
    return _availableReportViews.contains(tab) ? tab : 'Analytics';
  }

  @override
  void initState() {
    super.initState();
    _activeTab = _normalizeTab(widget.initialTab);
    _loadData();
    _loadRoleChangeRequests();
    _subscribeRoleChangeRealtime();
    RegularDealersService.instance.init().then((_) {
      RegularDealersService.instance.getTransmissions().then((list) {
        if (mounted) setState(() => _nmicTransmissionsList = list);
      });
    });
    _realtimeSub = AdminRealtimeHub.instance.stream.listen((table) {
      if (!mounted) return;
      if (table == 'requests' || table == 'payments' || table == 'slaughter_inspection') {
        _loadData(silent: true);
      } else if (table == 'regular_dealers') {
        RegularDealersService.instance.reload().then((_) async {
          if (_allRequests.isNotEmpty) {
            await RegularDealersService.instance.syncCustomersFromRequests(_allRequests);
          }
          if (mounted) setState(() {});
        });
      }
    });
  }

  @override
  void didUpdateWidget(ReportsRecordsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != null && widget.initialTab != oldWidget.initialTab) {
      setState(() {
        _activeTab = _normalizeTab(widget.initialTab);
      });
    }
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    if (_roleChangeChannel != null) {
      supabase.removeChannel(_roleChangeChannel!);
      _roleChangeChannel = null;
    }
    super.dispose();
  }

  Future<void> _loadRoleChangeRequests() async {
    if (mounted) setState(() => _loadingRoleChanges = true);
    try {
      await AppSettingsService.instance.ensureAdminAuthSession();
      final rows = await supabase
          .from('dealer_role_change_requests')
          .select()
          .inFilter('status', ['pending', 'approved_awaiting_verification'])
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _roleChangeRequests = List<Map<String, dynamic>>.from(rows);
          _loadingRoleChanges = false;
        });
      }
    } catch (e) {
      debugPrint('Role change requests load notice: $e');
      if (mounted) setState(() => _loadingRoleChanges = false);
    }
  }

  void _subscribeRoleChangeRealtime() {
    try {
      _roleChangeChannel = supabase
          .channel('public:dealer_role_change_requests_admin')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'dealer_role_change_requests',
            callback: (_) {
              if (!mounted) return;
              _loadRoleChangeRequests();
              RegularDealersService.instance.reload().then((_) {
                if (mounted) setState(() {});
              });
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Role change realtime notice: $e');
    }
  }

  Future<void> _handleRoleChangeDecision(
    Map<String, dynamic> req, {
    required bool approve,
  }) async {
    final id = req['id'];
    final userId = req['user_id'];
    final customerName = (req['customer_name'] ?? 'Dealer').toString();
    final currentRole = (req['from_role'] ?? 'barangay').toString().toLowerCase();
    final targetRole = (req['requested_role'] ?? 'market').toString().toLowerCase();
    final targetLabel = targetRole == 'market' ? 'Market Dealer' : 'Barangay Dealer';
    final currentLabel = currentRole == 'market' ? 'Market Dealer' : 'Barangay Dealer';

    try {
      await AppSettingsService.instance.ensureAdminAuthSession();
      final newStatus = approve ? 'approved_awaiting_verification' : 'rejected';
      await supabase.from('dealer_role_change_requests').update({
        'status': newStatus,
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);

      await NotificationService.sendNotificationSafely(
        supabase,
        userId: userId,
        title: approve
            ? 'Dealer Role Switch Approved — Verification Required'
            : 'Dealer Role Switch Request Declined',
        message: approve
            ? 'Your request to switch from $currentLabel to $targetLabel has been approved by the Slaughterhouse Admin. Please open the Requests tab and complete the formal role verification form (including required documents) to finalize your new role.'
            : 'Your request to switch from $currentLabel to $targetLabel was declined by the Slaughterhouse Admin. Your account remains registered as $currentLabel.',
        type: approve ? 'dealer_role_change_approved' : 'dealer_role_change_rejected',
        data: {
          'role_change_request_id': id,
          'current_role': currentRole,
          'requested_role': targetRole,
          'status': newStatus,
        },
      );

      AuditLogService.instance.log(
        action: approve ? 'dealer_role_change_approved' : 'dealer_role_change_rejected',
        module: 'Meat Dealers Directory',
        targetId: id?.toString(),
        targetRef: customerName,
        details: {'from': currentRole, 'to': targetRole, 'status': newStatus},
      );

      await _loadRoleChangeRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              approve
                  ? 'Approved $customerName → $targetLabel. Awaiting customer formal verification.'
                  : 'Declined role switch request for $customerName.',
            ),
            backgroundColor: approve ? const Color(0xFF2D6A4F) : Colors.orange.shade800,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating role switch request: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ════════════════════════════════════════════
  //  LOAD DATA (ALL REQUESTS ENRICHED)
  // ════════════════════════════════════════════
  Future<void> _loadData({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);
    try {
      final data = await supabase
          .from('requests')
          .select('*, slaughter_inspection(*), payments(*)')
          .order('created_at', ascending: false);

      final enriched = List<Map<String, dynamic>>.from(data).map((r) {
        final inspectionList = r['slaughter_inspection'];
        if (inspectionList is List && inspectionList.isNotEmpty) {
          final insp = inspectionList.first as Map<String, dynamic>;
          r['carcass_weight'] = insp['carcass_weight'];
          r['post_mortem'] = insp['post_mortem'];
          r['anti_mortem'] = insp['anti_mortem'];
          r['process_stage'] = insp['process_stage'];
          r['process_notes'] = insp['process_notes'];
          r['condemnation_reason'] = insp['condemnation_reason'];
          r['veterinary_findings'] = insp['veterinary_findings'];
          r['inspector_name'] = insp['inspector_name'];
          r['inspection_created_at'] = insp['created_at'];
        } else if (inspectionList is Map) {
          r['carcass_weight'] = inspectionList['carcass_weight'];
          r['post_mortem'] = inspectionList['post_mortem'];
          r['anti_mortem'] = inspectionList['anti_mortem'];
          r['process_stage'] = inspectionList['process_stage'];
          r['process_notes'] = inspectionList['process_notes'];
          r['condemnation_reason'] = inspectionList['condemnation_reason'];
          r['veterinary_findings'] = inspectionList['veterinary_findings'];
          r['inspector_name'] = inspectionList['inspector_name'];
          r['inspection_created_at'] = inspectionList['created_at'];
        }

        final paymentsList = r['payments'];
        if (paymentsList is List && paymentsList.isNotEmpty) {
          r['payment'] = paymentsList.first as Map<String, dynamic>;
        } else if (paymentsList is Map) {
          r['payment'] = paymentsList;
        }
        return r;
      }).toList();

      try {
        await RegularDealersService.instance.init();
        await RegularDealersService.instance.syncFromConfirmedProfiles();
        await RegularDealersService.instance.syncCustomersFromRequests(enriched);
      } catch (_) {}

      setState(() {
        _allRequests = enriched;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Reports load error: $e');
      setState(() => _isLoading = false);
    }
  }

  // ════════════════════════════════════════════
  //  CATEGORIZATION & METRIC HELPERS
  // ════════════════════════════════════════════
  String _refNo(Map<String, dynamic> req) =>
      'MI-${DateTime.now().year}-${req['id'].toString().padLeft(3, '0')}';

  double _carcassWeight(Map<String, dynamic> req) {
    final w = req['carcass_weight'];
    if (w == null) return 0;
    return double.tryParse(w.toString()) ?? 0;
  }

  bool _isPartialPartCondemnation(Map<String, dynamic> r) {
    final status = (r['status'] ?? '').toString().toLowerCase();
    if (status == 'post_mortem_failed' || status == 'condemned') return false;
    final post = (r['post_mortem'] ?? '').toString().toLowerCase();
    final condReason = (r['condemnation_reason'] ?? '').toString();
    return post == 'partially condemned' || condReason.contains('[Partial Condemnation');
  }

  double _condemnedPartWeight(Map<String, dynamic> r) {
    if (!_isPartialPartCondemnation(r)) return 0.0;
    final condReason = (r['condemnation_reason'] ?? '').toString();
    final m = RegExp(r'Weight:\s*([0-9]+(?:\.[0-9]+)?)').firstMatch(condReason);
    if (m == null) return 0.0;
    return double.tryParse(m.group(1) ?? '') ?? 0.0;
  }

  double _netCarcassWeight(Map<String, dynamic> r) {
    final gross = _carcassWeight(r);
    final condemned = _condemnedPartWeight(r);
    return (gross - condemned).clamp(0.0, double.infinity);
  }

  double _calcRequestFee(Map<String, dynamic> req) {
    final payment = req['payment'] as Map<String, dynamic>?;
    if (payment != null) {
      final amt = double.tryParse((payment['total_amount'] ?? payment['amount'] ?? 0).toString()) ?? 0;
      if (amt > 0) return amt;
    }
    final reqAmt = double.tryParse((req['total_amount'] ?? req['total_fee'] ?? 0).toString()) ?? 0;
    if (reqAmt > 0) return reqAmt;

    final weight = _netCarcassWeight(req);
    if (weight > 0) {
      return (weight * 5.0) + 250.0;
    }
    return 0.0;
  }

  bool _isHealthIssue(Map<String, dynamic> r) {
    if (_isUninspected(r)) return false;
    // Partially condemned carcasses proceed through the complete slaughter & release process,
    // so they belong in Section 1 (Processed), not Section 2 (Whole Condemnations).
    if (_isPartialPartCondemnation(r)) return false;
    final status = (r['status'] ?? '').toString().toLowerCase();
    final post = (r['post_mortem'] ?? '').toString().toLowerCase();
    final condReason = (r['condemnation_reason'] ?? '').toString().trim();

    if (post == 'failed' || status == 'post_mortem_failed' || status == 'condemned') return true;
    if (condReason.isNotEmpty && condReason != 'null') return true;
    return false;
  }

  bool _isProcessed(Map<String, dynamic> r) {
    if (_isHealthIssue(r) || _isUninspected(r)) return false;
    final status = (r['status'] ?? '').toString().toLowerCase();
    final post = (r['post_mortem'] ?? '').toString().toLowerCase();
    final anti = (r['anti_mortem'] ?? '').toString().toLowerCase();

    if (post == 'passed' || post == 'partially condemned') return true;
    if (_isPartialPartCondemnation(r)) return true;
    if (['releasable', 'mic_generated', 'paid', 'released', 'completed'].contains(status)) return true;
    if (status == 'slaughter_started' && anti == 'passed') return true;
    return false;
  }

  /// Section 3: Livestock that failed ante-mortem inspection and are currently
  /// held/confined under mandatory 2-day observation (awaiting re-evaluation
  /// to either proceed to slaughter or be condemned).
  bool _isUninspected(Map<String, dynamic> r) {
    final status = (r['status'] ?? '').toString().toLowerCase();
    final anti = (r['anti_mortem'] ?? '').toString().toLowerCase();
    final post = (r['post_mortem'] ?? '').toString().toLowerCase();

    if (post == 'failed' || status == 'post_mortem_failed' || status == 'condemned') return false;
    if (post == 'passed' || ['releasable', 'paid', 'released', 'completed'].contains(status)) return false;
    if (status == 'confined' || status == 'anti_mortem_failed' || anti == 'failed') return true;
    return false;
  }

  DateTime _activeDate() => _selectedDate ?? DateTime.now();

  DateTimeRange _getActiveDateRange() {
    final base = _activeDate();
    if (_reportType == 'Custom Range' && _customDateRange != null) {
      final s = _customDateRange!.start;
      final e = _customDateRange!.end;
      return DateTimeRange(
        start: DateTime(s.year, s.month, s.day, 0, 0, 0),
        end: DateTime(e.year, e.month, e.day, 23, 59, 59, 999),
      );
    } else if (_reportType == 'Daily Report') {
      final start = DateTime(base.year, base.month, base.day, 0, 0, 0);
      final end = DateTime(base.year, base.month, base.day, 23, 59, 59, 999);
      return DateTimeRange(start: start, end: end);
    } else if (_reportType == 'Weekly Report') {
      final weekday = base.weekday; // 1 = Monday
      final start = DateTime(base.year, base.month, base.day - (weekday - 1), 0, 0, 0);
      final end = DateTime(start.year, start.month, start.day + 6, 23, 59, 59, 999);
      return DateTimeRange(start: start, end: end);
    } else {
      // Monthly Report
      final start = DateTime(base.year, base.month, 1, 0, 0, 0);
      final end = DateTime(base.year, base.month + 1, 0, 23, 59, 59, 999);
      return DateTimeRange(start: start, end: end);
    }
  }

  String _getActivePeriodLabel() {
    final base = _activeDate();
    if (_reportType == 'Custom Range' && _customDateRange != null) {
      return '${DateFormat('MMM d, yyyy').format(_customDateRange!.start)} – ${DateFormat('MMM d, yyyy').format(_customDateRange!.end)}';
    } else if (_reportType == 'Daily Report') {
      return DateFormat('EEEE, MMMM d, yyyy').format(base);
    } else if (_reportType == 'Weekly Report') {
      final range = _getActiveDateRange();
      return 'Week of ${DateFormat('MMM d').format(range.start)} – ${DateFormat('MMM d, yyyy').format(range.end)}';
    } else {
      return DateFormat('MMMM yyyy').format(base);
    }
  }

  void _activateCustomDateRange() {
    final now = DateTime.now();
    setState(() {
      _customDateRange ??= DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: DateTime(now.year, now.month, now.day),
      );
      _reportType = 'Custom Range';
      _customRangeOpenVersion++;
    });
  }

  DateTime? _getRequestDate(Map<String, dynamic> r) {
    final notesStr = (r['process_notes'] ?? '').toString();
    final completedMatch = RegExp(r'\[COMPLETED_AT:([^\]]+)\]').firstMatch(notesStr);
    if (completedMatch != null) {
      final parsed = DateTime.tryParse(completedMatch.group(1)!.trim());
      if (parsed != null) return parsed.toLocal();
    }
    final insp = r['inspection_created_at']?.toString();
    if (insp != null && insp.isNotEmpty) {
      try {
        return DateTime.parse(insp).toLocal();
      } catch (_) {}
    }
    final pref = r['preferred_date']?.toString();
    if (pref != null && pref.isNotEmpty) {
      try {
        return DateTime.parse(pref).toLocal();
      } catch (_) {}
    }
    final created = r['created_at']?.toString();
    if (created != null && created.isNotEmpty) {
      try {
        return DateTime.parse(created).toLocal();
      } catch (_) {}
    }
    return null;
  }

  List<Map<String, dynamic>> _getRequestsInActivePeriod() {
    final range = _getActiveDateRange();
    return _allRequests.where((r) {
      final dt = _getRequestDate(r);
      if (dt == null) return false;
      return !dt.isBefore(range.start) && !dt.isAfter(range.end);
    }).toList();
  }

  bool get _isMonthlyOnlyTab =>
      _activeTab == 'Monthly Dealer Log' || _activeTab == 'NMIS Reports & Transmittal';

  bool get _isDailyOnlyTab => _activeTab == 'Daily Production (Abattoir)';

  bool get _usesPeriodSelector =>
      _activeTab == 'Analytics' ||
      _activeTab == 'Customer Records' ||
      _activeTab == 'Audit Logs';

  bool get _usesDateFilter =>
      _activeTab != 'Meat Dealers Directory' && _activeTab != 'Customer Reviews';

  bool get _canExportActiveView =>
      _activeTab != 'Customer Reviews' && _activeTab != 'Audit Logs';

  bool get _canSendToNmis =>
      _activeTab == 'Daily Production (Abattoir)' ||
      _activeTab == 'Monthly Dealer Log' ||
      _activeTab == 'NMIS Reports & Transmittal';

  String _getUnifiedDateLabel() {
    final base = _activeDate();
    if (_isMonthlyOnlyTab) {
      return DateFormat('MMMM yyyy').format(base);
    }
    if (_isDailyOnlyTab) {
      return DateFormat('EEEE, MMM d, yyyy').format(base);
    }
    return _getActivePeriodLabel();
  }

  // Navigation handlers
  void _prevPeriod() {
    setState(() {
      final cur = _activeDate();
      if (_isMonthlyOnlyTab) {
        _selectedDate = DateTime(cur.year, cur.month - 1, 1);
      } else if (_isDailyOnlyTab || _reportType == 'Daily Report') {
        _selectedDate = cur.subtract(const Duration(days: 1));
      } else if (_reportType == 'Weekly Report') {
        _selectedDate = cur.subtract(const Duration(days: 7));
      } else {
        _selectedDate = DateTime(cur.year, cur.month - 1, 1);
      }
      _dealerLogStartDay = 1;
    });
  }

  void _nextPeriod() {
    setState(() {
      final cur = _activeDate();
      if (_isMonthlyOnlyTab) {
        _selectedDate = DateTime(cur.year, cur.month + 1, 1);
      } else if (_isDailyOnlyTab || _reportType == 'Daily Report') {
        _selectedDate = cur.add(const Duration(days: 1));
      } else if (_reportType == 'Weekly Report') {
        _selectedDate = cur.add(const Duration(days: 7));
      } else {
        _selectedDate = DateTime(cur.year, cur.month + 1, 1);
      }
      _dealerLogStartDay = 1;
    });
  }

  void _resetToCurrentPeriod() {
    setState(() {
      _selectedDate = DateTime.now();
      _dealerLogStartDay = 1;
    });
  }

  /// Group requests by date for recent daily reports
  Map<String, List<Map<String, dynamic>>> _groupByDate() {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (var r in _allRequests) {
      final dt = _getRequestDate(r);
      if (dt == null) continue;
      final key = DateFormat('yyyy-MM-dd').format(dt);
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(r);
    }
    final sorted = Map.fromEntries(
      grouped.entries.toList()..sort((a, b) => b.key.compareTo(a.key)),
    );
    return sorted;
  }

  // Animal type distribution for processed livestock
  Map<String, int> _animalDistribution() {
    final periodReqs = _getRequestsInActivePeriod().where(_isProcessed).toList();
    final dist = <String, int>{};
    for (var r in periodReqs) {
      final type = r['livestock_type']?.toString() ?? 'Unknown';
      final count = int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1;
      dist[type] = (dist[type] ?? 0) + count;
    }
    return dist;
  }

  String _remarkForRequest(Map<String, dynamic> req) {
    final status = req['status']?.toString();
    if (status == 'taken_back') return 'Ante-Mortem Failed — Taken Back';
    if (status == 'condemned') return 'Post-Mortem Failed — Condemned';
    if (_isPartialPartCondemnation(req)) {
      final condReason = (req['condemnation_reason'] ?? '').toString();
      final partMatch = RegExp(r'Part:\s*([^|\]]+)').firstMatch(condReason);
      final wtMatch = RegExp(r'Weight:\s*([0-9]+(?:\.[0-9]+)?)').firstMatch(condReason);
      final part = partMatch?.group(1)?.trim() ?? '';
      final wt = wtMatch?.group(1)?.trim() ?? '';
      if (part.isNotEmpty && wt.isNotEmpty) {
        return 'Partial Condemnation ($part, ${wt}kg)';
      } else if (part.isNotEmpty) {
        return 'Partial Condemnation ($part)';
      }
      return 'Passed — Partial Condemnation';
    }
    final postMortem = req['post_mortem']?.toString();
    final rawNotes = req['process_notes']?.toString() ?? '';
    final notes = rawNotes
        .replaceAll(RegExp(r'\[AM_PASSED_AT:[^\]]+\]\s*\|?\s*'), '')
        .replaceAll(RegExp(r'\[COMPLETED_AT:[^\]]+\]\s*\|?\s*'), '')
        .replaceAll(RegExp(r'\[PHONE:[^\]]+\]\s*\|?\s*'), '')
        .trim();
    if (postMortem == 'Failed') return 'Condemned';
    if (notes.isNotEmpty && notes != 'null') return notes;
    return 'Passed Inspection';
  }

  // ════════════════════════════════════════════
  //  PDF & CSV EXPORT ACTIONS
  // ════════════════════════════════════════════
  Future<void> _exportReportAsCsv(String section, String filePrefix) async {
    try {
      final periodReqs = _getRequestsInActivePeriod();
      List<Map<String, dynamic>> targetReqs;
      if (section == 'production') {
        targetReqs = periodReqs.where(_isProcessed).toList();
      } else if (section == 'health_issues') {
        targetReqs = periodReqs.where(_isHealthIssue).toList();
      } else if (section == 'uninspected') {
        targetReqs = periodReqs.where(_isUninspected).toList();
      } else {
        targetReqs = periodReqs;
      }

      final headers = [
        'Date',
        'Reference No',
        'Customer Name',
        'Barangay / Origin',
        'Species',
        'Head Count',
        'Carcass Weight (kg)',
        'Status',
        'Ante-Mortem',
        'Post-Mortem',
        'Payment Method',
        'Total Fee (PHP)',
      ];

      final rows = targetReqs.map((r) {
        final dt = _getRequestDate(r);
        final dateStr = dt != null ? DateFormat('yyyy-MM-dd').format(dt) : '';
        final refNo = (r['reference_no'] ?? 'REQ-${r['id']}').toString();
        final pay = r['payment'] is Map ? r['payment'] as Map : null;
        final method = (pay?['payment_method'] ?? r['payment_method'] ?? '').toString();
        return [
          dateStr,
          refNo,
          r['customer_name'] ?? '',
          r['barangay'] ?? r['address'] ?? '',
          r['livestock_type'] ?? '',
          r['animal_count'] ?? 1,
          _netCarcassWeight(r) > 0 ? _netCarcassWeight(r).toStringAsFixed(1) : (r['carcass_weight'] ?? ''),
          r['status'] ?? '',
          r['anti_mortem'] ?? '',
          r['post_mortem'] ?? '',
          method,
          _calcRequestFee(r).toStringAsFixed(2),
        ];
      }).toList();

      final range = _getActiveDateRange();
      final rangeTag =
          '${DateFormat('yyyyMMdd').format(range.start)}_${DateFormat('yyyyMMdd').format(range.end)}';
      final ok = await downloadCsvFile(
        filename: 'TCAA_${filePrefix}_$rangeTag.csv',
        headers: headers,
        rows: rows,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok
                ? 'Exported ${targetReqs.length} records to CSV (Excel-ready).'
                : 'Failed to export CSV.'),
            backgroundColor: ok ? const Color(0xFF2D6A4F) : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CSV export error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _exportReportBySection(String sectionKey, String label) async {
    final periodReqs = _getRequestsInActivePeriod();
    final processed = periodReqs.where(_isProcessed).toList();
    final healthIssues = periodReqs.where(_isHealthIssue).toList();
    final uninspected = periodReqs.where(_isUninspected).toList();

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Generating official PDF report...'),
          backgroundColor: Color(0xFF2D6A4F),
          duration: Duration(seconds: 1),
        ),
      );

      final totalHeads = processed.fold<int>(0, (sum, r) => sum + (int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1));
      final totalRev = processed.fold<double>(0, (sum, r) => sum + _calcRequestFee(r));

      final pdfBytes = await ReportPdfGenerator.generate(
        date: _activeDate(),
        requests: processed,
        reportType: _reportType,
        periodLabel: _getActivePeriodLabel(),
        healthIssueRequests: healthIssues,
        uninspectedRequests: uninspected,
        totalLivestockProcessed: totalHeads,
        totalRevenue: totalRev,
        reportSection: sectionKey,
      );

      final fileSlug = _reportType.toLowerCase().replaceAll(' ', '_');
      final dateStr = DateFormat('yyyyMMdd').format(_activeDate());
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'Slaughterhouse_${label}_${fileSlug}_$dateStr.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting report: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _downloadReport(DateTime date, List<Map<String, dynamic>> requests) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generating comprehensive PDF...'), backgroundColor: Color(0xFF2D6A4F), duration: Duration(seconds: 1)),
      );
      final processed = requests.where(_isProcessed).toList();
      final healthIssues = requests.where(_isHealthIssue).toList();
      final uninspected = requests.where(_isUninspected).toList();
      final totalHeads = processed.fold<int>(0, (sum, r) => sum + (int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1));
      final totalRev = processed.fold<double>(0, (sum, r) => sum + _calcRequestFee(r));

      final pdfBytes = await ReportPdfGenerator.generate(
        date: date,
        requests: processed,
        reportType: 'Daily',
        periodLabel: DateFormat('MMMM d, yyyy').format(date),
        healthIssueRequests: healthIssues,
        uninspectedRequests: uninspected,
        totalLivestockProcessed: totalHeads,
        totalRevenue: totalRev,
        reportSection: 'all',
      );
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      await Printing.sharePdf(bytes: pdfBytes, filename: 'Slaughterhouse_Daily_Report_$dateStr.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating PDF: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _printReport(DateTime date, List<Map<String, dynamic>> requests) async {
    try {
      final processed = requests.where(_isProcessed).toList();
      final healthIssues = requests.where(_isHealthIssue).toList();
      final uninspected = requests.where(_isUninspected).toList();
      final totalHeads = processed.fold<int>(0, (sum, r) => sum + (int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1));
      final totalRev = processed.fold<double>(0, (sum, r) => sum + _calcRequestFee(r));

      final pdfBytes = await ReportPdfGenerator.generate(
        date: date,
        requests: processed,
        reportType: 'Daily',
        periodLabel: DateFormat('MMMM d, yyyy').format(date),
        healthIssueRequests: healthIssues,
        uninspectedRequests: uninspected,
        totalLivestockProcessed: totalHeads,
        totalRevenue: totalRev,
        reportSection: 'all',
      );
      await Printing.layoutPdf(onLayout: (_) async => pdfBytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error printing report: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF2D6A4F)))
                : RefreshIndicator(
                    onRefresh: _loadData,
                    color: const Color(0xFF2D6A4F),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: AdminResponsive.pagePadding(context),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildUnifiedToolbar(),
                          const SizedBox(height: 20),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.015),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              );
                            },
                            child: KeyedSubtree(
                              key: ValueKey(_activeTab),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_activeTab == 'Analytics') ...[
                                    _buildSummaryCards(),
                                    const SizedBox(height: 24),
                                    _buildAnalyticsChartsRow(),
                                    const SizedBox(height: 24),
                                    _buildAnalyticsSectionFilterBar(),
                                    const SizedBox(height: 14),
                                    AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 200),
                                      switchInCurve: Curves.easeOutCubic,
                                      switchOutCurve: Curves.easeInCubic,
                                      child: KeyedSubtree(
                                        key: ValueKey(_analyticsSectionFilter),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (_analyticsSectionFilter == 'section1' || _analyticsSectionFilter == 'all') ...[
                                              _buildOperationsRecordsSection(),
                                              if (_analyticsSectionFilter == 'all') const SizedBox(height: 20),
                                            ],
                                            if (_analyticsSectionFilter == 'section2' || _analyticsSectionFilter == 'all') ...[
                                              _buildHealthIssuesSection(),
                                              if (_analyticsSectionFilter == 'all') const SizedBox(height: 20),
                                            ],
                                            if (_analyticsSectionFilter == 'section3' || _analyticsSectionFilter == 'all') ...[
                                              _buildUninspectedSection(),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    _buildRecentReports(),
                                  ] else if (_activeTab == 'Daily Production (Abattoir)') ...[
                                    _buildDailyAbattoirProductionTab(),
                                  ] else if (_activeTab == 'Monthly Dealer Log') ...[
                                    _buildMonthlyDealerLogTab(),
                                  ] else if (_activeTab == 'NMIS Reports & Transmittal') ...[
                                    _buildNmisReportsTab(),
                                  ] else if (_activeTab == 'Customer Records') ...[
                                    _buildCustomerHistoricalRecordsTab(),
                                  ] else if (_activeTab == 'Meat Dealers Directory') ...[
                                    _buildMeatDealersDirectoryTab(),
                                  ] else if (_activeTab == 'Customer Reviews') ...[
                                    const CustomerReviewsView(),
                                  ] else if (_activeTab == 'Audit Logs' && AppSettingsService.instance.isSuperAdmin) ...[
                                    AuditLogsTab(activeDateRange: _getActiveDateRange()),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  IconData _iconForReportView(String view) {
    switch (view) {
      case 'Analytics':
        return Icons.analytics_outlined;
      case 'Daily Production (Abattoir)':
        return Icons.factory_outlined;
      case 'Monthly Dealer Log':
        return Icons.calendar_view_month_outlined;
      case 'NMIS Reports & Transmittal':
        return Icons.assignment_turned_in_outlined;
      case 'Customer Records':
        return Icons.history_edu_outlined;
      case 'Meat Dealers Directory':
        return Icons.storefront_outlined;
      case 'Customer Reviews':
        return Icons.rate_review_outlined;
      case 'Audit Logs':
        return Icons.policy_outlined;
      default:
        return Icons.description_outlined;
    }
  }

  Widget _buildReportViewDropdown() {
    final views = _availableReportViews;
    final current = views.contains(_activeTab) ? _activeTab : 'Analytics';

    return AnimatedSelectDropdown<String>(
      value: current,
      items: views,
      labelBuilder: (view) => view,
      iconBuilder: _iconForReportView,
      minMenuWidth: 260,
      backgroundColor: const Color(0xFF2D6A4F).withValues(alpha: 0.08),
      borderColor: const Color(0xFF2D6A4F).withValues(alpha: 0.35),
      textColor: const Color(0xFF1B4332),
      iconColor: const Color(0xFF2D6A4F),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      onChanged: (val) {
        if (val != _activeTab) {
          setState(() => _activeTab = val);
          if (val == 'Meat Dealers Directory') {
            _loadRoleChangeRequests();
          }
        }
      },
    );
  }

  // ════════════════════════════════════════════
  //  UNIFIED TOOLBAR (VIEW + SINGLE DATE + EXPORT MODAL)
  // ════════════════════════════════════════════
  Widget _buildUnifiedToolbar() {
    final dateLabel = _getUnifiedDateLabel();
    String quickResetText = 'Today';
    if (_isMonthlyOnlyTab || (_usesPeriodSelector && _reportType == 'Monthly Report')) {
      quickResetText = 'This Month';
    } else if (_usesPeriodSelector && _reportType == 'Weekly Report') {
      quickResetText = 'This Week';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Left + Middle: Report View Dropdown aligned with Unified Date Filter
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildReportViewDropdown(),
              if (_usesDateFilter && _usesPeriodSelector)
                _dropdownChip(
                  value: _reportType,
                  items: ['Daily Report', 'Weekly Report', 'Monthly Report', 'Custom Range'],
                  onChanged: (v) {
                    if (v == 'Custom Range') {
                      _activateCustomDateRange();
                    } else {
                      setState(() {
                        _reportType = v;
                        _dealerLogStartDay = 1;
                      });
                    }
                  },
                ),
              if (_usesDateFilter) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!(_usesPeriodSelector && _reportType == 'Custom Range'))
                        IconButton(
                          icon: const Icon(Icons.chevron_left, size: 20),
                          onPressed: _prevPeriod,
                          splashRadius: 18,
                          tooltip: _isMonthlyOnlyTab ? 'Previous month' : 'Previous period',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                        ),
                      const SizedBox(width: 4),
                      if (_usesPeriodSelector && _reportType == 'Custom Range')
                        AnimatedDateRangeDropdown(
                          selectedRange: _customDateRange ??
                              DateTimeRange(
                                start: DateTime(DateTime.now().year, DateTime.now().month, 1),
                                end: DateTime.now(),
                              ),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                          label: dateLabel,
                          autoOpenVersion: _customRangeOpenVersion,
                          onRangeSelected: (picked) {
                            setState(() {
                              _customDateRange = picked;
                              _selectedDate = picked.start;
                              _dealerLogStartDay = 1;
                            });
                          },
                        )
                      else
                        AnimatedDateDropdown(
                          selectedDate: _activeDate(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                          label: dateLabel,
                          onDateSelected: (picked) {
                            setState(() {
                              _selectedDate = picked;
                              _dealerLogStartDay = 1;
                            });
                          },
                        ),
                      const SizedBox(width: 4),
                      if (!(_usesPeriodSelector && _reportType == 'Custom Range'))
                        IconButton(
                          icon: const Icon(Icons.chevron_right, size: 20),
                          onPressed: _nextPeriod,
                          splashRadius: 18,
                          tooltip: _isMonthlyOnlyTab ? 'Next month' : 'Next period',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                        ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _resetToCurrentPeriod,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF2D6A4F),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  child: Text(quickResetText, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                ),
              ],
            ],
          ),

          // Right: Single Unified Animated Export Dropdown
          if (_canExportActiveView)
            AnimatedExportDropdown(
              activeReportName: _activeTab,
              periodLabel: _usesDateFilter ? dateLabel : 'All Registered Records',
              showAnalyticsSections: _activeTab == 'Analytics',
              canSendToNmis: _canSendToNmis,
              onExportPdf: (section) => _exportActiveViewPdf(analyticsSection: section),
              onExportCsv: (section) => _exportActiveViewCsv(analyticsSection: section),
              onSendToNmis: _triggerNmisTransmittalForActiveView,
            ),
        ],
      ),
    );
  }

  Future<void> _exportActiveViewPdf({String analyticsSection = 'all'}) async {
    try {
      if (_activeTab == 'Analytics') {
        final prefix = analyticsSection == 'production'
            ? 'Production_Report'
            : analyticsSection == 'health_issues'
                ? 'Health_Issues_Report'
                : analyticsSection == 'uninspected'
                    ? 'Uninspected_Report'
                    : 'Complete_Report';
        await _exportReportBySection(analyticsSection, prefix);
        return;
      }
      if (_activeTab == 'Daily Production (Abattoir)') {
        final pdfBytes = await NmicReportPdfGenerator.generateDailyProductionReport(
          date: _nmicReportDate,
          requests: _allRequests,
        );
        await Printing.layoutPdf(onLayout: (_) => pdfBytes);
        return;
      }
      if (_activeTab == 'Monthly Dealer Log') {
        final pdfBytes = await NmicReportPdfGenerator.generateMonthlyDealerLog(
          month: _monthlyLogMonth,
          requests: _allRequests,
        );
        await Printing.layoutPdf(onLayout: (_) => pdfBytes);
        return;
      }
      if (_activeTab == 'NMIS Reports & Transmittal') {
        final Uint8List pdfBytes = _selectedNmicFormType == 'Weekly Summary'
            ? await NmicReportPdfGenerator.generateNmisWeeklySummary(
                month: _monthlyLogMonth,
                requests: _allRequests,
              )
            : await NmicReportPdfGenerator.generateNmisServiceTransactionReport(
                month: _monthlyLogMonth,
                species: _selectedNmicSpecies,
                requests: _allRequests,
              );
        await Printing.layoutPdf(onLayout: (_) => pdfBytes);
        return;
      }
      if (_activeTab == 'Customer Records') {
        final dealersService = RegularDealersService.instance;
        final filtered = _getFilteredCustomerRecords();
        RegularDealer? activeDealer;
        if (_selectedCustomerFilter != null && _selectedCustomerFilter!.isNotEmpty) {
          activeDealer = dealersService.findDealerByName(_selectedCustomerFilter!) ??
              dealersService.findDealerByMarking(_selectedCustomerFilter!);
        }
        final pdfBytes = await NmicReportPdfGenerator.generateCustomerSlaughterHistoryReport(
          customerName: activeDealer?.name ?? _selectedCustomerFilter ?? 'All Customers / Dealers',
          marking: activeDealer?.markings ?? 'ALL',
          periodLabel: _getActivePeriodLabel(),
          requests: filtered,
        );
        await Printing.layoutPdf(onLayout: (_) => pdfBytes);
        return;
      }
      if (_activeTab == 'Meat Dealers Directory') {
        final pdfBytes = await NmicReportPdfGenerator.generateDealersDirectoryPdf(
          dealers: _getFilteredDealers(),
          dealerHeadsCount: _calcDealerLifetimeHeads(),
        );
        await Printing.layoutPdf(onLayout: (_) => pdfBytes);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting PDF: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _exportActiveViewCsv({String analyticsSection = 'all'}) async {
    try {
      final dateStamp = DateFormat('yyyy-MM-dd').format(_activeDate());
      if (_activeTab == 'Analytics') {
        final prefix = analyticsSection == 'production'
            ? 'Production_Report'
            : analyticsSection == 'health_issues'
                ? 'Health_Issues_Report'
                : analyticsSection == 'uninspected'
                    ? 'Uninspected_Report'
                    : 'Complete_Report';
        await _exportReportAsCsv(analyticsSection, prefix);
        return;
      }
      if (_activeTab == 'Daily Production (Abattoir)') {
        final target = DateTime(_nmicReportDate.year, _nmicReportDate.month, _nmicReportDate.day);
        final dailyReqs = _allRequests.where((r) {
          final dtStr = r['scheduled_date'] ?? r['created_at'];
          if (dtStr == null) return false;
          final dt = DateTime.tryParse(dtStr.toString());
          return dt != null && DateTime(dt.year, dt.month, dt.day) == target;
        }).toList();
        final rows = dailyReqs.map((r) => [
          dateStamp,
          (r['customer_name'] ?? r['owner_name'] ?? '—').toString(),
          (r['customer_marking'] ?? r['animal_tag'] ?? '—').toString(),
          (r['request_type'] ?? 'barangay').toString().toUpperCase(),
          (r['livestock_type'] ?? 'Hog').toString(),
          r['animal_count'] ?? 1,
          r['carcass_weight'] ?? 0,
          _calcRequestFee(r).toStringAsFixed(2),
        ]).toList();
        await downloadCsvFile(
          filename: 'Daily_Production_Abattoir_$dateStamp.csv',
          headers: ['Date', 'Dealer / Owner', 'Mark', 'Section', 'Species', 'Heads', 'Carcass Wt (kg)', 'Total Fee (PHP)'],
          rows: rows,
        );
      } else if (_activeTab == 'Monthly Dealer Log') {
        final month = _monthlyLogMonth;
        final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
        final monthSlug = DateFormat('yyyy-MM').format(month);
        final tally = _computeMonthlyDealerTally(month);
        final dealers = RegularDealersService.instance.allDealers;
        final headers = ['No.', 'Name of Owner', 'Mark', 'Section', ...List.generate(daysInMonth, (i) => '${i + 1}'), 'Total'];
        final rows = dealers.map((d) {
          final key = d.name.trim().toLowerCase();
          final dayMap = tally[key] ?? const <int, int>{};
          int total = 0;
          final dayCells = List.generate(daysInMonth, (i) {
            final c = dayMap[i + 1] ?? 0;
            total += c;
            return c > 0 ? c : '';
          });
          return [d.dealerNumber, d.name, d.markings, d.category.toUpperCase(), ...dayCells, total];
        }).toList();
        await downloadCsvFile(
          filename: 'Monthly_Dealer_Log_$monthSlug.csv',
          headers: headers,
          rows: rows,
        );
      } else if (_activeTab == 'NMIS Reports & Transmittal') {
        final month = _monthlyLogMonth;
        final monthSlug = DateFormat('yyyy-MM').format(month);
        final monthReqs = _allRequests.where((r) {
          final dt = DateTime.tryParse((r['scheduled_date'] ?? r['created_at'] ?? '').toString());
          return dt != null && dt.year == month.year && dt.month == month.month;
        }).toList();
        final rows = monthReqs.map((r) => [
          (r['scheduled_date'] ?? r['created_at'] ?? '').toString().split('T').first,
          (r['reference_no'] ?? r['id'] ?? '').toString(),
          (r['customer_name'] ?? r['owner_name'] ?? '').toString(),
          (r['livestock_type'] ?? 'Hog').toString(),
          r['animal_count'] ?? 1,
          r['carcass_weight'] ?? 0,
          (r['status'] ?? '').toString(),
        ]).toList();
        await downloadCsvFile(
          filename: 'NMIS_Report_$monthSlug.csv',
          headers: ['Date', 'Reference #', 'Dealer', 'Species', 'Heads', 'Carcass Wt (kg)', 'Status'],
          rows: rows,
        );
      } else if (_activeTab == 'Customer Records') {
        final filtered = _getFilteredCustomerRecords();
        final rows = filtered.map((r) => [
          (r['scheduled_date'] ?? r['created_at'] ?? '').toString().split('T').first,
          (r['reference_no'] ?? 'MI-2026-${(r['id'] ?? '').toString().padLeft(3, '0')}').toString(),
          (r['customer_name'] ?? r['owner_name'] ?? '').toString(),
          (r['livestock_type'] ?? 'Hog').toString(),
          r['animal_count'] ?? 1,
          r['carcass_weight'] ?? 0,
          (r['status'] ?? '').toString(),
          _calcRequestFee(r).toStringAsFixed(2),
        ]).toList();
        await downloadCsvFile(
          filename: 'Customer_Records_$dateStamp.csv',
          headers: ['Date', 'Reference #', 'Customer', 'Species', 'Heads', 'Carcass Wt (kg)', 'Status', 'Fee Paid (PHP)'],
          rows: rows,
        );
      } else if (_activeTab == 'Meat Dealers Directory') {
        final lifetime = _calcDealerLifetimeHeads();
        final dealers = _getFilteredDealers();
        final rows = dealers.map((d) => [
          d.dealerNumber,
          d.name,
          d.markings,
          d.category.toUpperCase(),
          d.phone ?? '',
          lifetime[d.name.trim().toLowerCase()] ?? 0,
        ]).toList();
        await downloadCsvFile(
          filename: 'Meat_Dealers_Directory_$dateStamp.csv',
          headers: ['No.', 'Dealer Name', 'Official Mark', 'Section', 'Contact Number', 'Lifetime Heads'],
          rows: rows,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported $_activeTab to Excel (.csv) successfully.'),
            backgroundColor: const Color(0xFF2D6A4F),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting Excel file: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _triggerNmisTransmittalForActiveView() {
    if (_activeTab == 'Daily Production (Abattoir)') {
      _openNmicTransmittalDialog(
        reportType: 'Daily Production Report',
        periodLabel: DateFormat('MMMM d, yyyy').format(_nmicReportDate),
        getPdfBytes: () => NmicReportPdfGenerator.generateDailyProductionReport(
          date: _nmicReportDate,
          requests: _allRequests,
        ),
      );
    } else if (_activeTab == 'Monthly Dealer Log') {
      final monthStr = DateFormat('MMMM yyyy').format(_monthlyLogMonth);
      _openNmicTransmittalDialog(
        reportType: 'Monthly Dealer Log',
        periodLabel: monthStr,
        getPdfBytes: () => NmicReportPdfGenerator.generateMonthlyDealerLog(
          month: _monthlyLogMonth,
          requests: _allRequests,
        ),
      );
    } else if (_activeTab == 'NMIS Reports & Transmittal') {
      final monthStr = DateFormat('MMMM yyyy').format(_monthlyLogMonth);
      _openNmicTransmittalDialog(
        reportType: _selectedNmicFormType == 'Weekly Summary'
            ? 'NMIS Weekly Summary Report'
            : 'NMIS Form NMIS-POSM-F-034 ($_selectedNmicSpecies)',
        periodLabel: monthStr,
        getPdfBytes: () {
          if (_selectedNmicFormType == 'Weekly Summary') {
            return NmicReportPdfGenerator.generateNmisWeeklySummary(
              month: _monthlyLogMonth,
              requests: _allRequests,
            );
          } else {
            return NmicReportPdfGenerator.generateNmisServiceTransactionReport(
              month: _monthlyLogMonth,
              species: _selectedNmicSpecies,
              requests: _allRequests,
            );
          }
        },
      );
    }
  }

  Map<String, Map<int, int>> _computeMonthlyDealerTally(DateTime month) {
    final Map<String, Map<int, int>> tally = {};
    for (final r in _allRequests) {
      final dtStr = r['scheduled_date'] ?? r['created_at'];
      if (dtStr == null) continue;
      final dt = DateTime.tryParse(dtStr.toString());
      if (dt == null || dt.year != month.year || dt.month != month.month) continue;
      final name = (r['customer_name'] ?? r['owner_name'] ?? '').toString().trim().toLowerCase();
      if (name.isEmpty) continue;
      final count = int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1;
      final dayMap = tally.putIfAbsent(name, () => <int, int>{});
      dayMap[dt.day] = (dayMap[dt.day] ?? 0) + count;
    }
    return tally;
  }

  List<Map<String, dynamic>> _getFilteredCustomerRecords() {
    final range = _getActiveDateRange();
    List<Map<String, dynamic>> filtered = _allRequests.where((r) {
      final dt = _getRequestDate(r);
      if (dt == null) return false;
      return !dt.isBefore(range.start) && !dt.isAfter(range.end);
    }).toList();

    if (_selectedCustomerFilter != null && _selectedCustomerFilter!.isNotEmpty) {
      final query = _selectedCustomerFilter!.toUpperCase().trim();
      filtered = filtered.where((r) {
        final name = (r['customer_name'] ?? r['owner_name'] ?? '').toString().toUpperCase().trim();
        final mark = (r['customer_marking'] ?? r['animal_tag'] ?? r['tag_id'] ?? '').toString().toUpperCase().trim();
        return name == query || mark == query || name.contains(query);
      }).toList();
    }
    return filtered;
  }

  Widget _dropdownChip({required String value, required List<String> items, required ValueChanged<String> onChanged}) {
    return AnimatedSelectDropdown<String>(
      value: value,
      items: items,
      labelBuilder: (e) => e,
      minMenuWidth: 180,
      backgroundColor: const Color(0xFFEDF2F7),
      borderColor: const Color(0xFFE2E8F0),
      textColor: const Color(0xFF1E293B),
      iconColor: const Color(0xFF64748B),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      onChanged: onChanged,
    );
  }

  // ════════════════════════════════════════════
  //  SUMMARY CARDS (TOTAL REVENUE & SEPARATE METRICS)
  // ════════════════════════════════════════════
  Widget _buildSummaryCards() {
    final periodReqs = _getRequestsInActivePeriod();
    final processed = periodReqs.where(_isProcessed).toList();
    final healthIssues = periodReqs.where(_isHealthIssue).toList();
    final uninspected = periodReqs.where(_isUninspected).toList();

    double totalRevenue = 0;
    int livestockProcessed = 0;

    for (var r in processed) {
      totalRevenue += _calcRequestFee(r);
      livestockProcessed += int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1;
    }

    return AdminResponsive.kpiGrid([
      _summaryCard(
        label: 'Total Revenue',
        value: '\u20b1 ${NumberFormat('#,##0.00').format(totalRevenue)}',
        accent: const Color(0xFF1B4332),
        changeText: 'Fees collected for processed livestock',
        changeColor: const Color(0xFF2D6A4F),
        icon: Icons.payments_outlined,
        iconColor: const Color(0xFF1B4332),
      ),
      _summaryCard(
        label: 'Livestock Processed',
        value: '$livestockProcessed Heads',
        accent: const Color(0xFF2D6A4F),
        changeText: '${processed.length} operations passed inspection',
        changeColor: const Color(0xFF2D6A4F),
        showDot: true,
        dotColor: const Color(0xFF2D6A4F),
      ),
      _summaryCard(
        label: 'Health Issues / Condemned',
        value: '${healthIssues.length} Cases',
        accent: const Color(0xFFC53030),
        changeText: healthIssues.isEmpty ? 'Clean record (100% Passed)' : 'Listed separately below',
        changeColor: const Color(0xFFC53030),
        icon: Icons.health_and_safety_outlined,
        iconColor: const Color(0xFFC53030),
      ),
      _summaryCard(
        label: 'Held / Confined (Ante-Mortem)',
        value: '${uninspected.length} Cases',
        accent: const Color(0xFFB45309),
        changeText: uninspected.isEmpty ? 'No livestock in 2-day confinement' : 'Under 2-day observation hold',
        changeColor: const Color(0xFFD97706),
        icon: Icons.medical_services_outlined,
        iconColor: const Color(0xFFB45309),
      ),
    ], spacing: 14);
  }

  Widget _summaryCard({
    required String label,
    required String value,
    required Color accent,
    required String changeText,
    required Color changeColor,
    IconData? icon,
    Color? iconColor,
    bool showDot = false,
    Color? dotColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500))),
              if (showDot)
                Container(width: 10, height: 10, decoration: BoxDecoration(color: dotColor ?? accent, shape: BoxShape.circle))
              else if (icon != null)
                Icon(icon, size: 18, color: iconColor ?? accent),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: accent)),
          const SizedBox(height: 6),
          Text(changeText, style: TextStyle(fontSize: 10.5, color: changeColor), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  ANALYTICS CHARTS ROW (REVENUE/VOLUME BAR CHART + DONUT CHART)
  // ════════════════════════════════════════════
  Widget _buildAnalyticsChartsRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildRevenueVolumeBarChartCard()),
              const SizedBox(width: 24),
              Expanded(child: _buildDonutChartCard()),
            ],
          );
        }
        return Column(
          children: [
            _buildRevenueVolumeBarChartCard(),
            const SizedBox(height: 20),
            _buildDonutChartCard(),
          ],
        );
      },
    );
  }

  Widget _buildRevenueVolumeBarChartCard() {
    final base = _activeDate();
    final List<({String label, double revenue, int heads, bool isActive})> buckets = [];

    if (_reportType == 'Monthly Report') {
      // 4–5 weekly buckets for the selected month
      final daysInMonth = DateTime(base.year, base.month + 1, 0).day;
      for (int startDay = 1; startDay <= daysInMonth; startDay += 7) {
        final endDay = min(startDay + 6, daysInMonth);
        final bStart = DateTime(base.year, base.month, startDay, 0, 0, 0);
        final bEnd = DateTime(base.year, base.month, endDay, 23, 59, 59, 999);
        double rev = 0;
        int heads = 0;
        for (final r in _allRequests) {
          if (!_isProcessed(r)) continue;
          final dt = _getRequestDate(r);
          if (dt != null && !dt.isBefore(bStart) && !dt.isAfter(bEnd)) {
            rev += _calcRequestFee(r);
            heads += int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1;
          }
        }
        buckets.add((
          label: '$startDay–$endDay',
          revenue: rev,
          heads: heads,
          isActive: base.day >= startDay && base.day <= endDay,
        ));
      }
    } else {
      // 7-day rolling window ending on selected date (or Mon–Sun for Weekly)
      final DateTime start = _reportType == 'Weekly Report'
          ? DateTime(base.year, base.month, base.day - (base.weekday - 1))
          : DateTime(base.year, base.month, base.day).subtract(const Duration(days: 6));
      for (int i = 0; i < 7; i++) {
        final day = start.add(Duration(days: i));
        double rev = 0;
        int heads = 0;
        for (final r in _allRequests) {
          if (!_isProcessed(r)) continue;
          final dt = _getRequestDate(r);
          if (dt != null && dt.year == day.year && dt.month == day.month && dt.day == day.day) {
            rev += _calcRequestFee(r);
            heads += int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1;
          }
        }
        final isSel = day.year == base.year && day.month == base.month && day.day == base.day;
        buckets.add((
          label: DateFormat('EEE\nd').format(day),
          revenue: rev,
          heads: heads,
          isActive: isSel,
        ));
      }
    }

    final maxVal = buckets.fold<double>(
      0.0,
      (m, b) => max(m, _trendShowRevenue ? b.revenue : b.heads.toDouble()),
    );
    final safeMax = maxVal <= 0 ? 1.0 : maxVal;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _trendShowRevenue ? 'Revenue Trend' : 'Slaughter Volume Trend',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2D3748)),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _reportType == 'Monthly Report'
                          ? 'Weekly breakdown for ${DateFormat('MMMM yyyy').format(base)}'
                          : '7-day performance window around ${DateFormat('MMM d, yyyy').format(base)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _trendToggleChip('Revenue (₱)', _trendShowRevenue, () => setState(() => _trendShowRevenue = true)),
                    _trendToggleChip('Heads', !_trendShowRevenue, () => setState(() => _trendShowRevenue = false)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 230,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: buckets.map((b) {
                final val = _trendShowRevenue ? b.revenue : b.heads.toDouble();
                final ratio = (val / safeMax).clamp(0.0, 1.0);
                final barColor = b.isActive
                    ? const Color(0xFF2D6A4F)
                    : const Color(0xFF52B788).withValues(alpha: 0.65);
                final tooltipText = _trendShowRevenue
                    ? '${b.label.replaceAll('\n', ' ')}: ₱${NumberFormat('#,##0.00').format(b.revenue)} (${b.heads} heads)'
                    : '${b.label.replaceAll('\n', ' ')}: ${b.heads} heads (₱${NumberFormat('#,##0.00').format(b.revenue)})';
                final topLabel = val <= 0
                    ? ''
                    : (_trendShowRevenue
                        ? (b.revenue >= 1000
                            ? '₱${(b.revenue / 1000).toStringAsFixed(1)}k'
                            : '₱${b.revenue.toStringAsFixed(0)}')
                        : '${b.heads}');

                return Expanded(
                  child: Tooltip(
                    message: tooltipText,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            topLabel,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: b.isActive ? FontWeight.w700 : FontWeight.w600,
                              color: b.isActive ? const Color(0xFF1B4332) : const Color(0xFF64748B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: TweenAnimationBuilder<double>(
                                tween: Tween<double>(begin: 0, end: ratio),
                                duration: const Duration(milliseconds: 520),
                                curve: Curves.easeOutCubic,
                                builder: (context, animRatio, _) {
                                  return FractionallySizedBox(
                                    heightFactor: max(animRatio, val > 0 ? 0.05 : 0.015),
                                    widthFactor: 0.72,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: val > 0 ? barColor : const Color(0xFFE2E8F0),
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            b.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.2,
                              fontWeight: b.isActive ? FontWeight.w700 : FontWeight.w500,
                              color: b.isActive ? const Color(0xFF2D6A4F) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trendToggleChip(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1))]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? const Color(0xFF1B4332) : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildDonutChartCard() {
    final dist = _animalDistribution();
    final total = dist.values.fold(0, (a, b) => a + b);

    Color getColor(String animal) {
      final name = animal.toLowerCase();
      if (name.contains('hog') || name.contains('pig')) return Colors.blue;
      if (name.contains('cara')) return Colors.orange;
      if (name.contains('cow') || name.contains('cattle')) return Colors.red;
      if (name.contains('goat')) return Colors.yellow.shade700;
      if (name.contains('sheep')) return Colors.green;
      if (name.contains('poultry') || name.contains('chicken') || name.contains('duck') || name.contains('turkey') || name.contains('fowl')) return Colors.purple;
      return Colors.grey;
    }

    final mappedColors = dist.keys.map((k) => getColor(k)).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Processed Commodities Distribution', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
          const SizedBox(height: 4),
          Text('Breakdown of inspected animals slaughtered in ${_getActivePeriodLabel()}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 24),
          if (total == 0)
            SizedBox(
              height: 200,
              child: Center(child: Text('No processed animals for this period', style: TextStyle(color: Colors.grey.shade400))),
            )
          else
            _AnimatedCommoditiesDonut(
              labels: dist.keys.toList(),
              values: dist.values.toList(),
              colors: mappedColors,
              periodKey: '${_reportType}_${_getActivePeriodLabel()}_${dist.entries.map((e) => '${e.key}:${e.value}').join(',')}',
            ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  ANALYTICS SECTION FILTER BAR (SECTION 1 / 2 / 3 / ALL)
  // ════════════════════════════════════════════
  Widget _buildAnalyticsSectionFilterBar() {
    final periodReqs = _getRequestsInActivePeriod();
    final processedCount = periodReqs.where(_isProcessed).length;
    final healthCount = periodReqs.where(_isHealthIssue).length;
    final uninspectedCount = periodReqs.where(_isUninspected).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.025), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.filter_list_rounded, size: 17, color: Color(0xFF475569)),
              const SizedBox(width: 6),
              Text(
                'Show Section:',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.grey.shade700),
              ),
            ],
          ),
          _analyticsSectionChip(
            keyName: 'section1',
            label: 'Section 1: Processed',
            count: processedCount,
            activeColor: const Color(0xFF2D6A4F),
          ),
          _analyticsSectionChip(
            keyName: 'section2',
            label: 'Section 2: Health Issues',
            count: healthCount,
            activeColor: const Color(0xFFC53030),
          ),
          _analyticsSectionChip(
            keyName: 'section3',
            label: 'Section 3: Held / Confined',
            count: uninspectedCount,
            activeColor: const Color(0xFFB45309),
          ),
          _analyticsSectionChip(
            keyName: 'all',
            label: 'All Sections',
            count: processedCount + healthCount + uninspectedCount,
            activeColor: const Color(0xFF1E3A8A),
          ),
        ],
      ),
    );
  }

  Widget _analyticsSectionChip({
    required String keyName,
    required String label,
    required int count,
    required Color activeColor,
  }) {
    final isSelected = _analyticsSectionFilter == keyName;
    return InkWell(
      onTap: () {
        if (_analyticsSectionFilter != keyName) {
          setState(() => _analyticsSectionFilter = keyName);
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF334155),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.22)
                    : activeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : activeColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  SECTION 1: PROCESSED OPERATIONS RECORDS
  // ════════════════════════════════════════════
  Widget _buildOperationsRecordsSection() {
    final periodReqs = _getRequestsInActivePeriod();
    final records = periodReqs.where(_isProcessed).toList();
    final periodLabel = _getActivePeriodLabel();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2D6A4F).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('SECTION 1', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2D6A4F))),
                          ),
                          const SizedBox(width: 8),
                          Text('Processed Livestock Records — $periodLabel',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Livestock that successfully passed ante-mortem and post-mortem inspections and were slaughtered',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (records.isEmpty)
            Padding(
              padding: const EdgeInsets.all(36),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.event_busy, size: 44, color: Colors.grey.shade300),
                    const SizedBox(height: 10),
                    Text('No processed operations recorded for $periodLabel', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                  ],
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 820;
                return Table(
                  border: TableBorder(
                    horizontalInside: BorderSide(color: Colors.grey.shade200),
                    top: BorderSide(color: Colors.grey.shade200),
                    bottom: BorderSide(color: Colors.grey.shade200),
                  ),
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  columnWidths: isCompact
                      ? const {
                          0: FlexColumnWidth(1.3),
                          1: FlexColumnWidth(2.0),
                          2: FlexColumnWidth(1.2),
                          3: FlexColumnWidth(0.7),
                          4: FlexColumnWidth(1.2),
                        }
                      : const {
                          0: FlexColumnWidth(1.2),
                          1: FlexColumnWidth(1.8),
                          2: FlexColumnWidth(1.0),
                          3: FlexColumnWidth(1.1),
                          4: FlexColumnWidth(0.6),
                          5: FlexColumnWidth(1.0),
                          6: FlexColumnWidth(1.1),
                          7: FlexColumnWidth(1.2),
                          8: FlexColumnWidth(1.4),
                        },
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: Color(0xFFF7FAFC)),
                      children: [
                        const Padding(padding: EdgeInsets.all(10), child: Text('Reference', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                        const Padding(padding: EdgeInsets.all(10), child: Text('Customer', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                        if (!isCompact)
                          const Padding(padding: EdgeInsets.all(10), child: Text('Section', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                        const Padding(padding: EdgeInsets.all(10), child: Text('Commodity', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                        const Padding(padding: EdgeInsets.all(10), child: Text('Heads', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                        if (!isCompact)
                          const Padding(padding: EdgeInsets.all(10), child: Text('Weight', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                        const Padding(padding: EdgeInsets.all(10), child: Text('Revenue', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                        if (!isCompact) ...[
                          const Padding(padding: EdgeInsets.all(10), child: Text('Inspector', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                          const Padding(padding: EdgeInsets.all(10), child: Text('Remarks', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                        ],
                      ],
                    ),
                    ...records.map((req) {
                      final ref = _refNo(req);
                      final type = req['request_type']?.toString() ?? '';
                      final isBarangay = type == 'barangay';
                      final livestock = req['livestock_type']?.toString() ?? '\u2014';
                      final animalCount = req['animal_count'] ?? 1;
                      final grossWeight = _carcassWeight(req);
                      final condemnedWt = _condemnedPartWeight(req);
                      final netWeight = _netCarcassWeight(req);
                      final isPartial = _isPartialPartCondemnation(req);
                      final fee = _calcRequestFee(req);
                      final inspector = req['inspector_name']?.toString() ?? '\u2014';
                      final remark = _remarkForRequest(req);

                      return TableRow(
                        children: [
                          Padding(padding: const EdgeInsets.all(10), child: Text(ref, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11.5), overflow: TextOverflow.ellipsis)),
                          Padding(padding: const EdgeInsets.all(10), child: Text(req['customer_name']?.toString() ?? '\u2014', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                          if (!isCompact)
                            Padding(padding: const EdgeInsets.all(8), child: _buildTypeBadge(isBarangay ? 'Barangay' : 'Market')),
                          Padding(padding: const EdgeInsets.all(10), child: Text(livestock, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                          Padding(padding: const EdgeInsets.all(10), child: Text('$animalCount', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold))),
                          if (!isCompact)
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: grossWeight > 0
                                  ? Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('${netWeight.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')} kg', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                                        if (condemnedWt > 0)
                                          Text(
                                            'net of ${grossWeight.toStringAsFixed(0)} kg (-${condemnedWt.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')} kg)',
                                            style: const TextStyle(fontSize: 9.5, color: Color(0xFFB45309), fontWeight: FontWeight.w600),
                                          ),
                                      ],
                                    )
                                  : const Text('\u2014', style: TextStyle(fontSize: 12)),
                            ),
                          Padding(padding: const EdgeInsets.all(10), child: Text(fee > 0 ? '\u20b1 ${NumberFormat('#,##0.00').format(fee)}' : '\u2014',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1B4332)), overflow: TextOverflow.ellipsis)),
                          if (!isCompact) ...[
                            Padding(padding: const EdgeInsets.all(10), child: Text(inspector, style: const TextStyle(fontSize: 11.5, color: Color(0xFF4A5568)), overflow: TextOverflow.ellipsis)),
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(
                                remark,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isPartial ? const Color(0xFFB45309) : const Color(0xFF2D6A4F),
                                  fontWeight: isPartial ? FontWeight.w600 : FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      );
                    }),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  SECTION 2: CASES WITH HEALTH ISSUES & CONDEMNATIONS (SEPARATE LIST)
  // ════════════════════════════════════════════
  Widget _buildHealthIssuesSection() {
    final periodReqs = _getRequestsInActivePeriod();
    final healthIssues = periodReqs.where(_isHealthIssue).toList();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: healthIssues.isNotEmpty ? const Color(0xFFFEB2B2) : Colors.grey.shade200,
          width: healthIssues.isNotEmpty ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: healthIssues.isNotEmpty
                ? const Color(0xFFE53E3E).withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: healthIssues.isNotEmpty ? const Color(0xFFFFF5F5) : const Color(0xFFF7FAFC),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53E3E),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('SECTION 2', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cases Involving Livestock with Health Issues & Condemnations (${healthIssues.length})',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: healthIssues.isNotEmpty ? const Color(0xFF9B2C2C) : const Color(0xFF2D3748),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Post-mortem carcass condemnation or livestock condemned after 2-day confinement',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (healthIssues.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_outline, color: Color(0xFF2D6A4F), size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'No livestock health issues or condemnations recorded during this period.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 760;
                return Table(
                  border: TableBorder(
                    horizontalInside: BorderSide(color: Colors.grey.shade200),
                    top: BorderSide(color: Colors.grey.shade200),
                    bottom: BorderSide(color: Colors.grey.shade200),
                  ),
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  columnWidths: isCompact
                      ? const {
                          0: FlexColumnWidth(1.2),
                          1: FlexColumnWidth(1.8),
                          2: FlexColumnWidth(1.5),
                          3: FlexColumnWidth(1.8),
                        }
                      : const {
                          0: FlexColumnWidth(1.1),
                          1: FlexColumnWidth(1.5),
                          2: FlexColumnWidth(1.3),
                          3: FlexColumnWidth(1.4),
                          4: FlexColumnWidth(2.2),
                          5: FlexColumnWidth(1.6),
                        },
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: Color(0xFFFFF5F5)),
                      children: [
                        const Padding(padding: EdgeInsets.all(10), child: Text('Reference', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF9B2C2C)))),
                        const Padding(padding: EdgeInsets.all(10), child: Text('Customer', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                        if (!isCompact)
                          const Padding(padding: EdgeInsets.all(10), child: Text('Livestock', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                        const Padding(padding: EdgeInsets.all(10), child: Text('Stage', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                        if (!isCompact)
                          const Padding(padding: EdgeInsets.all(10), child: Text('Veterinary Findings', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                        const Padding(padding: EdgeInsets.all(10), child: Text('Disposition', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                      ],
                    ),
                    ...healthIssues.map((req) {
                      final ref = _refNo(req);
                      final name = req['customer_name']?.toString() ?? '\u2014';
                      final livestock = '${req['livestock_type'] ?? 'Unknown'} (${req['animal_count'] ?? 1} head)';
                      final anti = (req['anti_mortem'] ?? '').toString();
                      final post = (req['post_mortem'] ?? '').toString();
                      final status = (req['status'] ?? '').toString();
                      String stage = 'Ante-Mortem';
                      String disposition = 'Ante-Mortem Failed — Taken Back';
                      if (post == 'Failed' || status == 'condemned' || status == 'post_mortem_failed') {
                        stage = 'Post-Mortem';
                        disposition = 'Carcass Condemned';
                      } else if (anti == 'Failed' || status == 'anti_mortem_failed' || status == 'taken_back') {
                        stage = 'Ante-Mortem';
                        disposition = 'Rejected / Taken Back';
                      }
                      String findings = (req['veterinary_findings']?.toString() ??
                              req['condemnation_reason']?.toString() ??
                              req['process_notes']?.toString() ??
                              'Health abnormality detected')
                          .replaceAll(RegExp(r'\[AM_PASSED_AT:[^\]]+\]\s*\|?\s*'), '')
                          .trim();
                      if (findings.isEmpty || findings == 'null') {
                        findings = 'Did not meet health & inspection standards';
                      }
                      return TableRow(
                        children: [
                          Padding(padding: const EdgeInsets.all(10), child: Text(ref, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFF9B2C2C)), overflow: TextOverflow.ellipsis)),
                          Padding(padding: const EdgeInsets.all(10), child: Text(name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                          if (!isCompact)
                            Padding(padding: const EdgeInsets.all(10), child: Text(livestock, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: const Color(0xFFFED7D7), borderRadius: BorderRadius.circular(12)),
                              child: Text(stage, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFC53030)), overflow: TextOverflow.ellipsis),
                            ),
                          ),
                          if (!isCompact)
                            Padding(padding: const EdgeInsets.all(10), child: Text(findings, style: const TextStyle(fontSize: 11.5, color: Color(0xFF742A2A)))),
                          Padding(padding: const EdgeInsets.all(10), child: Text(disposition, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF9B2C2C)))),
                        ],
                      );
                    }),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  String _cleanDisplayRemarks(String raw, {String fallback = '—'}) {
    final cleaned = raw
        .replaceAll(RegExp(r'\[AM_PASSED_AT:[^\]]+\]\s*\|?\s*'), '')
        .replaceAll(RegExp(r'\[PHONE:[^\]]+\]\s*\|?\s*'), '')
        .trim();
    if (cleaned.isEmpty || cleaned.toLowerCase() == 'null') {
      return fallback;
    }
    return cleaned;
  }

  // ════════════════════════════════════════════
  //  SECTION 3: HELD / CONFINED LIVESTOCK (FAILED ANTE-MORTEM — 2-DAY HOLD)
  // ════════════════════════════════════════════
  Widget _buildUninspectedSection() {
    final periodReqs = _getRequestsInActivePeriod();
    final heldConfined = periodReqs.where(_isUninspected).toList();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              color: Color(0xFFFFFBEB),
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB45309),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('SECTION 3', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Held / Confined Livestock — Failed Ante-Mortem (${heldConfined.length})',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2D3748)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Livestock that failed ante-mortem inspection and are under mandatory 2-day confinement awaiting re-evaluation (slaughter or condemnation)',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (heldConfined.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_outline, color: Color(0xFF2D6A4F), size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'No livestock currently held or confined from ante-mortem inspection during this period.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 760;
                return Table(
                  border: TableBorder(
                    horizontalInside: BorderSide(color: Colors.grey.shade200),
                    top: BorderSide(color: Colors.grey.shade200),
                    bottom: BorderSide(color: Colors.grey.shade200),
                  ),
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  columnWidths: isCompact
                      ? const {
                          0: FlexColumnWidth(1.2),
                          1: FlexColumnWidth(1.8),
                          2: FlexColumnWidth(1.3),
                          3: FlexColumnWidth(1.8),
                        }
                      : const {
                          0: FlexColumnWidth(1.1),
                          1: FlexColumnWidth(1.6),
                          2: FlexColumnWidth(1.3),
                          3: FlexColumnWidth(1.0),
                          4: FlexColumnWidth(1.4),
                          5: FlexColumnWidth(2.2),
                        },
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: Color(0xFFEDF2F7)),
                      children: [
                        const Padding(padding: EdgeInsets.all(10), child: Text('Reference', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                        const Padding(padding: EdgeInsets.all(10), child: Text('Customer', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                        if (!isCompact) ...[
                          const Padding(padding: EdgeInsets.all(10), child: Text('Livestock', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                          const Padding(padding: EdgeInsets.all(10), child: Text('Date Held', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                        ],
                        const Padding(padding: EdgeInsets.all(10), child: Text('Hold Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                        const Padding(padding: EdgeInsets.all(10), child: Text('Ante-Mortem Findings / Remarks', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                      ],
                    ),
                    ...heldConfined.map((req) {
                      final ref = _refNo(req);
                      final name = req['customer_name']?.toString() ?? '\u2014';
                      final livestock = '${req['livestock_type'] ?? 'Unknown'} (${req['animal_count'] ?? 1} head)';
                      final sched = req['inspection_created_at']?.toString() ?? req['preferred_date']?.toString() ?? req['created_at']?.toString() ?? '\u2014';
                      final schedFmt = sched.length > 10 ? sched.substring(0, 10) : sched;
                      final findings = _cleanDisplayRemarks(
                        (req['veterinary_findings'] ?? req['process_notes'] ?? '').toString(),
                        fallback: 'Failed ante-mortem — held under mandatory 2-day confinement for re-evaluation',
                      );
                      return TableRow(
                        children: [
                          Padding(padding: const EdgeInsets.all(10), child: Text(ref, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11.5), overflow: TextOverflow.ellipsis)),
                          Padding(padding: const EdgeInsets.all(10), child: Text(name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                          if (!isCompact) ...[
                            Padding(padding: const EdgeInsets.all(10), child: Text(livestock, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                            Padding(padding: const EdgeInsets.all(10), child: Text(schedFmt, style: const TextStyle(fontSize: 11.5))),
                          ],
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(12)),
                              child: const Text('CONFINED (2-DAY HOLD)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFB45309)), overflow: TextOverflow.ellipsis),
                            ),
                          ),
                          Padding(padding: const EdgeInsets.all(10), child: Text(findings, style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569)))),
                        ],
                      );
                    }),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTypeBadge(String type) {
    final isBarangay = type == 'Barangay';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isBarangay ? const Color(0xFF2D6A4F).withValues(alpha: 0.1) : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        type,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isBarangay ? const Color(0xFF2D6A4F) : Colors.blue.shade700,
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  RECENT REPORTS
  // ════════════════════════════════════════════
  Widget _buildRecentReports() {
    final grouped = _groupByDate();
    final recentDates = grouped.keys.take(5).toList();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recent Daily Reports', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
          const SizedBox(height: 4),
          Text('Quick access to export past daily operations reports', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 16),
          if (recentDates.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(child: Text('No reports available', style: TextStyle(color: Colors.grey.shade400))),
            )
          else
            ...recentDates.map((dateKey) {
              final dayReqs = grouped[dateKey]!;
              final dt = DateTime.parse(dateKey);
              final dateFmt = DateFormat('EEE, MMMM d, yyyy').format(dt);
              final processed = dayReqs.where(_isProcessed).toList();
              final healthCount = dayReqs.where(_isHealthIssue).length;
              final heads = processed.fold<int>(0, (s, r) => s + (int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1));
              final totalWeight = processed.fold<double>(0, (s, r) => s + _carcassWeight(r));
              final totalRev = processed.fold<double>(0, (s, r) => s + _calcRequestFee(r));

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(dateFmt, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
                          const SizedBox(height: 4),
                          Text(
                            '$heads Heads Processed  •  ${totalWeight.toStringAsFixed(1)} kg  •  \u20b1 ${NumberFormat('#,##0.00').format(totalRev)}${healthCount > 0 ? "  •  $healthCount Health Issue(s)" : ""}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _downloadReport(dt, dayReqs),
                      icon: Icon(Icons.download, size: 20, color: Colors.grey.shade600),
                      splashRadius: 20,
                      tooltip: 'Download PDF',
                    ),
                    IconButton(
                      onPressed: () => _printReport(dt, dayReqs),
                      icon: Icon(Icons.print_outlined, size: 20, color: Colors.grey.shade600),
                      splashRadius: 20,
                      tooltip: 'Print Report',
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  1. DAILY ABATTOIR PRODUCTION TAB (Market & Barangay)
  // ═══════════════════════════════════════════════════════════
  Widget _buildDailyAbattoirProductionTab() {
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(_nmicReportDate);
    final targetDateOnly = DateTime(_nmicReportDate.year, _nmicReportDate.month, _nmicReportDate.day);

    final dailyReqs = _allRequests.where((r) {
      final dtStr = r['scheduled_date'] ?? r['created_at'];
      if (dtStr == null) return false;
      try {
        final dt = DateTime.parse(dtStr.toString());
        return DateTime(dt.year, dt.month, dt.day) == targetDateOnly;
      } catch (_) {
        return false;
      }
    }).toList();

    int hogs = 0, cow = 0, cara = 0;
    double totalWeight = 0;
    for (var r in dailyReqs) {
      final sp = (r['livestock_type'] ?? '').toString().toLowerCase();
      final count = int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1;
      final wt = double.tryParse((r['carcass_weight'] ?? 0).toString()) ?? 0;
      totalWeight += wt;
      if (sp.contains('cow') || sp.contains('cattle') || sp.contains('baka')) {
        cow += count;
      } else if (sp.contains('cara') || sp.contains('buffalo')) {
        cara += count;
      } else {
        hogs += count;
      }
    }

    final dealersService = RegularDealersService.instance;
    final marketDealers = dealersService.marketDealers;
    final barangayDealers = dealersService.barangayDealers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Action Bar
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Daily Slaughterhouse Production Report',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D3748)),
              ),
              const SizedBox(height: 4),
              Text(
                'Official Abattoir Record (Incoming Livestock & Carcass Production) • $dateStr',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Summary KPI Row
        Row(
          children: [
            _buildKpiCard('Hogs Slaughtered', '$hogs heads', const Color(0xFF2D6A4F), Icons.pets),
            const SizedBox(width: 16),
            _buildKpiCard('Cattle / Cow', '$cow heads', const Color(0xFF2B6CB0), Icons.agriculture),
            const SizedBox(width: 16),
            _buildKpiCard('Carabao', '$cara heads', const Color(0xFFD69E2E), Icons.nature),
            const SizedBox(width: 16),
            _buildKpiCard('Carcass Weight', '${NumberFormat("#,##0.0").format(totalWeight)} kg', const Color(0xFF805AD5), Icons.scale),
          ],
        ),
        const SizedBox(height: 20),

        // Market Section Preview (Rows 1-40)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('MARKET SECTION (40 Dealers)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
                  Text('Pre-assigned permanent markings active', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
              const SizedBox(height: 12),
              _buildDealersTablePreview(marketDealers, dailyReqs),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Barangay Section Preview (Rows 1-63)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('BARANGAY SECTION (63 Dealers)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
                  Text('Pre-assigned permanent markings active', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
              const SizedBox(height: 12),
              _buildDealersTablePreview(barangayDealers, dailyReqs),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDealersTablePreview(List<RegularDealer> dealers, List<Map<String, dynamic>> dailyReqs) {
    // Map requests by marking/name
    final Map<String, int> headsByMarking = {};
    final Map<String, double> wtByMarking = {};
    for (var r in dailyReqs) {
      final mark = (r['customer_marking'] ?? r['animal_tag'] ?? r['tag_id'] ?? '').toString().trim().toUpperCase();
      final name = (r['customer_name'] ?? r['owner_name'] ?? '').toString().trim().toUpperCase();
      final count = int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1;
      final wt = double.tryParse((r['carcass_weight'] ?? 0).toString()) ?? 0;
      if (mark.isNotEmpty) {
        headsByMarking[mark] = (headsByMarking[mark] ?? 0) + count;
        wtByMarking[mark] = (wtByMarking[mark] ?? 0) + wt;
      }
      if (name.isNotEmpty) {
        headsByMarking[name] = (headsByMarking[name] ?? 0) + count;
        wtByMarking[name] = (wtByMarking[name] ?? 0) + wt;
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Table(
        border: TableBorder.all(color: Colors.grey.shade200, width: 1),
        columnWidths: const {
          0: FixedColumnWidth(48),
          1: FlexColumnWidth(3),
          2: FixedColumnWidth(100),
          3: FixedColumnWidth(100),
          4: FixedColumnWidth(120),
          5: FixedColumnWidth(120),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey.shade100),
            children: const [
              Padding(padding: EdgeInsets.all(8), child: Text('No.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
              Padding(padding: EdgeInsets.all(8), child: Text('Name of Owner', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              Padding(padding: EdgeInsets.all(8), child: Text('Markings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
              Padding(padding: EdgeInsets.all(8), child: Text('Heads', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
              Padding(padding: EdgeInsets.all(8), child: Text('Carcass Wt (kg)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
              Padding(padding: EdgeInsets.all(8), child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
            ],
          ),
          ...dealers.map((d) {
            final h = headsByMarking[d.markings.toUpperCase()] ?? headsByMarking[d.name.toUpperCase()] ?? 0;
            final w = wtByMarking[d.markings.toUpperCase()] ?? wtByMarking[d.name.toUpperCase()] ?? 0;
            final hasSlaughter = h > 0;
            return TableRow(
              decoration: BoxDecoration(color: hasSlaughter ? const Color(0xFFF0FFF4) : Colors.white),
              children: [
                Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4), child: Text('${d.dealerNumber}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8), child: Text(d.name, style: TextStyle(fontSize: 12, fontWeight: hasSlaughter ? FontWeight.bold : FontWeight.normal))),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                    child: Text(d.markings, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                  ),
                ),
                Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4), child: Text(hasSlaughter ? '$h' : '—', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: hasSlaughter ? FontWeight.bold : FontWeight.normal, color: hasSlaughter ? const Color(0xFF2D6A4F) : Colors.grey))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4), child: Text(hasSlaughter ? NumberFormat('#,##0.0').format(w) : '—', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
                Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4), child: Text(hasSlaughter ? 'Processed' : 'No Entry', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: hasSlaughter ? const Color(0xFF38A169) : Colors.grey.shade400))),
              ],
            );
          }),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  2. MONTHLY DEALER LOG TAB (31-Day Matrix)
  // ═══════════════════════════════════════════════════════════
  Widget _buildMonthlyDealerLogTab() {
    final monthStr = DateFormat('MMMM yyyy').format(_monthlyLogMonth);
    final daysInMonth = DateTime(_monthlyLogMonth.year, _monthlyLogMonth.month + 1, 0).day;

    final dealersService = RegularDealersService.instance;
    final allDealers = dealersService.allDealers;

    // Filter requests for month
    final monthReqs = _allRequests.where((r) {
      final dtStr = r['scheduled_date'] ?? r['created_at'];
      if (dtStr == null) return false;
      try {
        final dt = DateTime.parse(dtStr.toString());
        return dt.year == _monthlyLogMonth.year && dt.month == _monthlyLogMonth.month;
      } catch (_) {
        return false;
      }
    }).toList();

    int totalMonthHeads = monthReqs.fold(0, (a, b) => a + (int.tryParse((b['animal_count'] ?? 1).toString()) ?? 1));

    final tally = _computeMonthlyDealerTally(_monthlyLogMonth);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Banner (Date & Export controlled by Unified Toolbar above)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Meat Dealer Licensing – Monthly Log', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
              const SizedBox(height: 4),
              Text('Tabaco City Abattoir Office 31-Day Production Matrix • $monthStr', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            ],
          ),
        ),
        const SizedBox(height: 20),

        _buildResponsiveKpiRow([
          _buildKpiCard('Total Heads (Month)', '$totalMonthHeads heads', const Color(0xFF2D6A4F), Icons.pets),
          _buildKpiCard('Market Dealers', '${dealersService.marketDealers.length} registered', const Color(0xFF2B6CB0), Icons.storefront),
          _buildKpiCard('Barangay Dealers', '${dealersService.barangayDealers.length} registered', const Color(0xFFD69E2E), Icons.home_work),
          _buildKpiCard('Days Covered', '$daysInMonth days', const Color(0xFF805AD5), Icons.calendar_month),
        ]),
        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final int windowSize = constraints.maxWidth >= 980
                  ? 7
                  : (constraints.maxWidth >= 760
                      ? 5
                      : (constraints.maxWidth >= 520 ? 4 : 3));
              final int clampedStart = _dealerLogStartDay.clamp(1, daysInMonth);
              final int endDay = min(clampedStart + windowSize - 1, daysInMonth);
              final List<int> visibleDays = [
                for (int d = clampedStart; d <= endDay; d++) d,
              ];
              final bool canPrev = clampedStart > 1;
              final bool canNext = endDay < daysInMonth;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Monthly Dealer 31-Day Tally Overview',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2D3748)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Showing ${allDealers.length} registered dealers • Name, Mark & Section stay pinned',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                      // Day-window pager (< Days 1–7 of 30 >)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.chevron_left_rounded, size: 20),
                              tooltip: 'Previous days',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                              onPressed: canPrev
                                  ? () => setState(() {
                                        _dealerLogStartDay = max(1, clampedStart - windowSize);
                                      })
                                  : null,
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                'Days $clampedStart–$endDay of $daysInMonth',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.chevron_right_rounded, size: 20),
                              tooltip: 'Next days',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                              onPressed: canNext
                                  ? () => setState(() {
                                        _dealerLogStartDay = min(daysInMonth, endDay + 1);
                                      })
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Table(
                    border: TableBorder(
                      horizontalInside: BorderSide(color: Colors.grey.shade200),
                      top: BorderSide(color: Colors.grey.shade200),
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    columnWidths: {
                      0: const FixedColumnWidth(42),
                      1: const FlexColumnWidth(2.6),
                      2: const FlexColumnWidth(1.0),
                      3: const FlexColumnWidth(1.2),
                      for (int i = 0; i < visibleDays.length; i++)
                        4 + i: const FlexColumnWidth(0.65),
                      4 + visibleDays.length: const FlexColumnWidth(0.85),
                    },
                    children: [
                      TableRow(
                        decoration: BoxDecoration(color: Colors.grey.shade100),
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                            child: Text('No.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                            child: Text('Name of Owner', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                            child: Text('Mark', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                            child: Text('Section', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                          ...visibleDays.map(
                            (d) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                              child: Text(
                                '$d',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1B4332)),
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                            child: Text('Total', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
                      ...allDealers.map((d) {
                        final key = d.name.trim().toLowerCase();
                        final dayMap = tally[key] ?? const <int, int>{};
                        final monthTotal = dayMap.values.fold<int>(0, (a, b) => a + b);
                        return TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                              child: Text('${d.dealerNumber}', style: const TextStyle(fontSize: 12)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                              child: Text(
                                d.name,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                              child: Text(
                                d.markings,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E3A8A)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                              child: Text(
                                d.category.toUpperCase(),
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            ...visibleDays.map((day) {
                              final count = dayMap[day] ?? 0;
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                                child: Text(
                                  count > 0 ? '$count' : '—',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: count > 0 ? FontWeight.w700 : FontWeight.normal,
                                    color: count > 0 ? const Color(0xFF2D6A4F) : Colors.grey.shade400,
                                  ),
                                ),
                              );
                            }),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                              child: Text(
                                monthTotal > 0 ? '$monthTotal' : '—',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: monthTotal > 0 ? const Color(0xFF0F172A) : Colors.grey.shade400,
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  3. NMIS REPORTS & TRANSMITTAL TAB
  // ═══════════════════════════════════════════════════════════
  Widget _buildNmisReportsTab() {
    final monthStr = DateFormat('MMMM yyyy').format(_monthlyLogMonth);
    final dealersService = RegularDealersService.instance;
    final nmic = dealersService.nmicSettings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Action Bar
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('National Meat Inspection Service (NMIS) Regulatory Reports',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
              const SizedBox(height: 4),
              Text('Form No. NMIS-POSM-F-034 • Official Transmittal & Compliance Suite • $monthStr',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const Divider(height: 24),
              // Filter selectors (responsive Wrap)
              Wrap(
                spacing: 16,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Report Form: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: _selectedNmicFormType,
                        items: const [
                          DropdownMenuItem(value: 'Weekly Summary', child: Text('Weekly Summary Report (All Species)')),
                          DropdownMenuItem(value: 'Species Transaction', child: Text('Service Transaction Description (Per Species)')),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _selectedNmicFormType = v);
                        },
                      ),
                    ],
                  ),
                  if (_selectedNmicFormType == 'Species Transaction')
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('Species: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ...['HOG', 'CATTLE', 'CARABAO', 'GOAT'].map((sp) {
                          final isSel = _selectedNmicSpecies == sp;
                          return ChoiceChip(
                            label: Text(sp),
                            selected: isSel,
                            onSelected: (_) => setState(() => _selectedNmicSpecies = sp),
                            selectedColor: const Color(0xFF2D6A4F),
                            labelStyle: TextStyle(color: isSel ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 12),
                          );
                        }),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Compliance Info Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('NMIS Official Establishment Details & Transmittal Config',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.email_outlined, size: 16, color: Color(0xFF1E3A8A)),
                    label: const Text(
                      'NMIC Email Settings',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                    onPressed: _openEmailConfigDialog,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF1E3A8A)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildInfoItem('License to Operate', nmic.ltoNumber)),
                  Expanded(child: _buildInfoItem('Establishment', nmic.establishmentName)),
                  Expanded(child: _buildInfoItem('POSMS Head', nmic.nmicOfficerName)),
                  Expanded(child: _buildInfoItem('Default Recipient Email', nmic.nmicEmail)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildInfoItem('Inspection Officer', nmic.dmioOfficerName)),
                  Expanded(child: _buildInfoItem('Plant Representative', nmic.plantRepresentative)),
                  Expanded(child: _buildInfoItem('Fee Basis', nmic.feeBasisDetails.isNotEmpty ? nmic.feeBasisDetails : 'City Ordinance No. 2018-012')),
                  Expanded(
                    child: _buildInfoItem(
                      'Email Delivery Method',
                      'Gmail Web (1-Click Direct)',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // NMIS Transmissions Audit Log Table
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('NMIS Transmissions & Audit Dispatch Log', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
                  Text('Soft copies logged for weekly physical inspection compliance', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
              const SizedBox(height: 12),
              if (_nmicTransmissionsList.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text('No transmissions recorded yet. Use "Send Transmittal & Form to NMIC" to email reports.',
                        style: TextStyle(color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
                  ),
                )
              else
                Table(
                  border: TableBorder.all(color: Colors.grey.shade200),
                  children: [
                    TableRow(
                      decoration: BoxDecoration(color: Colors.grey.shade100),
                      children: const [
                        Padding(padding: EdgeInsets.all(8), child: Text('Date & Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        Padding(padding: EdgeInsets.all(8), child: Text('Report Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        Padding(padding: EdgeInsets.all(8), child: Text('Period', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        Padding(padding: EdgeInsets.all(8), child: Text('Recipient Email', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        Padding(padding: EdgeInsets.all(8), child: Text('Sent By', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        Padding(padding: EdgeInsets.all(8), child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      ],
                    ),
                    ..._nmicTransmissionsList.map((t) {
                      return TableRow(
                        children: [
                          Padding(padding: const EdgeInsets.all(8), child: Text(t['created_at']?.toString().split('T').first ?? '', style: const TextStyle(fontSize: 12))),
                          Padding(padding: const EdgeInsets.all(8), child: Text(t['report_type'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          Padding(padding: const EdgeInsets.all(8), child: Text(t['period_label'] ?? '', style: const TextStyle(fontSize: 12))),
                          Padding(padding: const EdgeInsets.all(8), child: Text(t['recipient_email'] ?? '', style: const TextStyle(fontSize: 12))),
                          Padding(padding: const EdgeInsets.all(8), child: Text(t['sent_by'] ?? 'Admin', style: const TextStyle(fontSize: 12))),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(4)),
                              child: Text('Transmitted', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade800), textAlign: TextAlign.center),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  4. CUSTOMER SLAUGHTER RECORDS TAB (Audit Trail)
  // ═══════════════════════════════════════════════════════════
  Widget _buildCustomerHistoricalRecordsTab() {
    final dealersService = RegularDealersService.instance;
    final allDealers = dealersService.allDealers;
    final filtered = _getFilteredCustomerRecords();

    int heads = filtered.fold(0, (a, b) => a + (int.tryParse((b['animal_count'] ?? 1).toString()) ?? 1));
    double wt = filtered.fold(0.0, (a, b) => a + (double.tryParse((b['carcass_weight'] ?? 0).toString()) ?? 0));
    double fees = filtered.fold(0.0, (a, b) => a + _calcRequestFee(b));

    // Find active dealer details if selected
    RegularDealer? activeDealer;
    if (_selectedCustomerFilter != null) {
      activeDealer = dealersService.findDealerByName(_selectedCustomerFilter!) ??
          dealersService.findDealerByMarking(_selectedCustomerFilter!);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header & Customer Filter (Date & Export controlled by Unified Toolbar above)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Customer Slaughter Historical Audit Records',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
              const SizedBox(height: 4),
              Text('Individual dealer slaughter totals required for NMIC inspection audit • ${_getActivePeriodLabel()}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const Divider(height: 24),
              DropdownButtonFormField<String>(
                initialValue: _selectedCustomerFilter,
                decoration: const InputDecoration(
                  labelText: 'Select Customer / Regular Dealer',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Customers / Dealers')),
                  ...allDealers.map((d) => DropdownMenuItem(
                        value: d.name,
                        child: Text('${d.name} [Mark: ${d.markings}] (${d.category.toUpperCase()})'),
                      )),
                ],
                onChanged: (v) => setState(() => _selectedCustomerFilter = v),
              ),
              if (activeDealer != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FFF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF9AE6B4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified, color: Color(0xFF2D6A4F), size: 20),
                      const SizedBox(width: 8),
                      Text('Dealer: ${activeDealer.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFF1E3A8A), borderRadius: BorderRadius.circular(4)),
                        child: Text('Official Mark: ${activeDealer.markings}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                      const SizedBox(width: 12),
                      Text('Classification: ${activeDealer.category.toUpperCase()} SECTION', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                      const Spacer(),
                      const Text('Marking Permanently Locked', style: TextStyle(color: Color(0xFF2D6A4F), fontWeight: FontWeight.bold, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),

        Row(
          children: [
            _buildKpiCard('Total Animals Slaughtered', '$heads heads', const Color(0xFF2D6A4F), Icons.pets),
            const SizedBox(width: 16),
            _buildKpiCard('Total Carcass Weight', '${NumberFormat("#,##0.0").format(wt)} kg', const Color(0xFF2B6CB0), Icons.scale),
            const SizedBox(width: 16),
            _buildKpiCard('Total Inspection Fees', NumberFormat('₱#,##0.00').format(fees), const Color(0xFFD69E2E), Icons.payments),
          ],
        ),
        const SizedBox(height: 20),

        // Transactions Table
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Detailed Slaughter Transactions (${filtered.length} records)',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
              const SizedBox(height: 12),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text('No slaughter transactions found for the selected customer and timeframe.', style: TextStyle(color: Colors.grey.shade500, fontStyle: FontStyle.italic))),
                )
              else
                Table(
                  border: TableBorder.all(color: Colors.grey.shade200),
                  children: [
                    TableRow(
                      decoration: BoxDecoration(color: Colors.grey.shade100),
                      children: const [
                        Padding(padding: EdgeInsets.all(8), child: Text('Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        Padding(padding: EdgeInsets.all(8), child: Text('Reference #', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        Padding(padding: EdgeInsets.all(8), child: Text('Species', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        Padding(padding: EdgeInsets.all(8), child: Text('Heads', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
                        Padding(padding: EdgeInsets.all(8), child: Text('Carcass Wt (kg)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
                        Padding(padding: EdgeInsets.all(8), child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
                        Padding(padding: EdgeInsets.all(8), child: Text('Fee Paid', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.right)),
                      ],
                    ),
                    ...filtered.take(30).map((r) {
                      final dt = r['scheduled_date'] ?? r['created_at'] ?? '';
                      final ref = r['reference_no']?.toString() ?? (r['id'] != null ? 'MI-2026-${r['id'].toString().padLeft(3, '0')}' : '—');
                      final sp = r['livestock_type'] ?? 'Hog';
                      final count = r['animal_count'] ?? 1;
                      final weight = r['carcass_weight'] ?? 0;
                      final st = r['status'] ?? 'Completed';
                      final fee = _calcRequestFee(r);
                      return TableRow(
                        children: [
                          Padding(padding: const EdgeInsets.all(8), child: Text(dt.toString().split('T').first, style: const TextStyle(fontSize: 12))),
                          Padding(padding: const EdgeInsets.all(8), child: Text(ref, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          Padding(padding: const EdgeInsets.all(8), child: Text(sp.toString(), style: const TextStyle(fontSize: 12))),
                          Padding(padding: const EdgeInsets.all(8), child: Text('$count', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
                          Padding(padding: const EdgeInsets.all(8), child: Text(NumberFormat('#,##0.0').format(double.tryParse('$weight') ?? 0), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
                          Padding(padding: const EdgeInsets.all(8), child: Text(st.toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Color(0xFF2D6A4F)))),
                          Padding(padding: const EdgeInsets.all(8), child: Text(NumberFormat('₱#,##0.00').format(fee), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                        ],
                      );
                    }),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  5. NMIC TRANSMITTAL LETTER & EMAIL MODAL DIALOG
  // ═══════════════════════════════════════════════════════════
  Future<void> _openNmicTransmittalDialog({
    required String reportType,
    required String periodLabel,
    required Future<Uint8List> Function() getPdfBytes,
  }) async {
    final dealersService = RegularDealersService.instance;
    await dealersService.init();
    final nmic = dealersService.nmicSettings;

    final emailCtrl = TextEditingController(text: nmic.nmicEmail);
    final subjectCtrl = TextEditingController(
        text: 'Official Transmittal: $reportType ($periodLabel) - Tabaco City Slaughterhouse');
    final bodyCtrl = TextEditingController(
      text: 'Good day ${nmic.nmicOfficerName},\n\n'
          'Pursuant to Republic Act No. 9296 (Meat Inspection Code of the Philippines) as amended by RA 10536, '
          'the Tabaco City Slaughterhouse (License To Operate: ${nmic.ltoNumber}) hereby officially transmits '
          'the soft copy of the $reportType covering $periodLabel.\n\n'
          'Please find the certified soft copy PDF report attached for your regulatory review and POSMS recording. '
          'Physical hard copies and original receipts are prepared and available on-site for the upcoming weekly inspection.\n\n'
          'Respectfully submitted,\n'
          '${nmic.plantRepresentative}\n'
          '${nmic.plantRepTitle}\n'
          'Tabaco City Slaughterhouse',
    );

    if (!mounted) return;

    bool isSending = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.mark_email_read_outlined, color: Color(0xFF1E3A8A)),
              SizedBox(width: 10),
              Text('Send Transmittal & Reports to NMIS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: AdminResponsive.dialogWidth(context, 580),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Color(0xFF1E3A8A), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Direct 1-click transmission: generates the certified PDF report and emails it directly with the PDF attached — no manual file download or browser email compose required.',
                            style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailCtrl,
                    enabled: !isSending,
                    decoration: const InputDecoration(
                      labelText: 'NMIC Recipient Email',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: subjectCtrl,
                    enabled: !isSending,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: const [WordsCapitalizationFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Transmittal Subject',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.subject),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bodyCtrl,
                    enabled: !isSending,
                    maxLines: 7,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: const [SentencesCapitalizationFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Transmittal Letter Message',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.attach_file, size: 18, color: Colors.grey),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('Auto-Attached PDF: ${reportType.replaceAll(" ", "_")}_$periodLabel.pdf',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSending ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Download PDF'),
              onPressed: isSending
                  ? null
                  : () async {
                      final bytes = await getPdfBytes();
                      await Printing.sharePdf(bytes: bytes, filename: '${reportType.replaceAll(" ", "_")}_$periodLabel.pdf');
                    },
            ),
            ElevatedButton.icon(
              icon: isSending
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, size: 16),
              label: Text(isSending ? 'Sending...' : 'Send to NMIS'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2D6A4F), foregroundColor: Colors.white),
              onPressed: isSending
                  ? null
                  : () async {
                      final recipient = emailCtrl.text.trim();
                      final subject = subjectCtrl.text.trim();
                      final body = bodyCtrl.text.trim();
                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(ctx);

                      if (recipient.isEmpty) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Please enter recipient email address'), backgroundColor: Colors.redAccent),
                        );
                        return;
                      }

                      setDialogState(() => isSending = true);
                      try {
                        await AppSettingsService.instance.ensureAdminAuthSession();
                        final pdfBytes = await getPdfBytes();
                        final filename = '${reportType.replaceAll(" ", "_")}_$periodLabel.pdf';
                        final result = await dealersService.sendReportViaResend(
                          recipientEmail: recipient,
                          subject: subject,
                          body: body,
                          pdfBytes: pdfBytes,
                          filename: filename,
                          reportType: reportType,
                          periodLabel: periodLabel,
                        );

                        if (result['success'] == true) {
                          final updatedList = await dealersService.getTransmissions();
                          if (mounted) setState(() => _nmicTransmissionsList = updatedList);
                          if (navigator.canPop()) navigator.pop();
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Report sent directly to $recipient with PDF attached!'),
                              backgroundColor: const Color(0xFF2D6A4F),
                            ),
                          );
                        } else {
                          setDialogState(() => isSending = false);
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(result['error']?.toString() ?? 'Failed to send report directly to NMIS.'),
                              backgroundColor: Colors.redAccent,
                              duration: const Duration(seconds: 6),
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isSending = false);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Error sending report: $e'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResponsiveKpiRow(List<Widget> cards) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Row(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                cards[i],
              ],
            ],
          );
        }
        // 2-column grid on medium screens, 1-column on very narrow screens
        final cols = constraints.maxWidth >= 520 ? 2 : 1;
        final List<Widget> rows = [];
        for (int i = 0; i < cards.length; i += cols) {
          final slice = cards.sublist(i, min(i + cols, cards.length));
          rows.add(
            Row(
              children: [
                for (int j = 0; j < slice.length; j++) ...[
                  if (j > 0) const SizedBox(width: 12),
                  slice[j],
                ],
                if (slice.length < cols) const Spacer(),
              ],
            ),
          );
          if (i + cols < cards.length) rows.add(const SizedBox(height: 12));
        }
        return Column(children: rows);
      },
    );
  }

  Widget _buildKpiCard(String title, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.05),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: icon == Icons.pets
                  ? _CowHeadIcon(size: 22, color: color)
                  : Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 2),
                  Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2D3748))),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  MEAT DEALERS DIRECTORY & EMAIL CONFIG
  // ════════════════════════════════════════════
  Map<String, int> _calcDealerLifetimeHeads() {
    final Map<String, int> map = {};
    for (var r in _allRequests) {
      final name = (r['customer_name'] ?? '').toString().trim().toLowerCase();
      if (name.isEmpty) continue;
      final count = int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1;
      map[name] = (map[name] ?? 0) + count;
    }
    return map;
  }

  void _openEmailConfigDialog() {
    final dealersService = RegularDealersService.instance;
    final nmic = dealersService.nmicSettings;
    final recipientCtrl = TextEditingController(text: nmic.nmicEmail);
    final officerCtrl = TextEditingController(text: nmic.nmicOfficerName);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.mark_email_read_outlined, color: Color(0xFF1E3A8A), size: 24),
            SizedBox(width: 10),
            Text('NMIC Recipient Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: AdminResponsive.dialogWidth(context, 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: const [
                    Icon(Icons.check_circle_outline, color: Color(0xFF2D6A4F), size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Direct 1-Click Gmail Dispatch is active. No API keys or third-party service required. You can customize the default recipient email below.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF1B5E20), height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: recipientCtrl,
                decoration: const InputDecoration(
                  labelText: 'Default NMIC Recipient Email *',
                  hintText: 'e.g. jonhpaulmarbella123@gmail.com or nmic.region5@da.gov.ph',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: officerCtrl,
                textCapitalization: TextCapitalization.words,
                inputFormatters: const [WordsCapitalizationFormatter()],
                decoration: const InputDecoration(
                  labelText: 'NMIC POSMS Head / Officer Name',
                  hintText: 'DR. BEJAEE C. DE DIOS',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Save Settings'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A), foregroundColor: Colors.white),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final r = recipientCtrl.text.trim();
              final o = officerCtrl.text.trim();

              if (r.isNotEmpty) nmic.nmicEmail = r;
              if (o.isNotEmpty) nmic.nmicOfficerName = o;

              await dealersService.saveNmicSettings(nmic);
              if (mounted) setState(() {});
              if (ctx.mounted) Navigator.pop(ctx);

              messenger.showSnackBar(
                const SnackBar(
                  content: Text('NMIC Recipient Settings saved successfully!'),
                  backgroundColor: Color(0xFF2D6A4F),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _openRegisterDealerDialog({RegularDealer? editDealer}) {
    final dealersService = RegularDealersService.instance;
    final isEditing = editDealer != null;
    final nameCtrl = TextEditingController(text: editDealer?.name ?? '');
    final markingCtrl = TextEditingController(text: editDealer?.markings ?? '');
    final phoneCtrl = TextEditingController(text: editDealer?.phone ?? '');
    String category = editDealer?.category ?? 'barangay';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(isEditing ? Icons.edit : Icons.person_add_alt_1, color: const Color(0xFF2D6A4F)),
              const SizedBox(width: 8),
              Text(
                isEditing ? 'Edit Meat Dealer Record' : 'Register New Meat Dealer',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Meat Dealer Full Name *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: const [WordsCapitalizationFormatter()],
                    onChanged: (val) {
                      if (!isEditing && val.trim().isNotEmpty && markingCtrl.text.isEmpty) {
                        markingCtrl.text = dealersService.suggestMarkingForName(val);
                      }
                    },
                    decoration: const InputDecoration(
                      hintText: 'e.g. Jonathan Bino, Vangie Marbella...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Category / Designation *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Barangay Meat Dealer'),
                        selected: category == 'barangay',
                        onSelected: (_) => setDialogState(() => category = 'barangay'),
                        selectedColor: const Color(0xFFD69E2E).withValues(alpha: 0.2),
                        labelStyle: TextStyle(
                          color: category == 'barangay' ? const Color(0xFFB7791F) : Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Market Meat Dealer'),
                        selected: category == 'market',
                        onSelected: (_) => setDialogState(() => category = 'market'),
                        selectedColor: const Color(0xFF2B6CB0).withValues(alpha: 0.2),
                        labelStyle: TextStyle(
                          color: category == 'market' ? const Color(0xFF2B6CB0) : Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Permanent Assigned Marking *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      TextButton.icon(
                        icon: const Icon(Icons.auto_awesome, size: 14),
                        label: const Text('Auto-Suggest', style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          if (nameCtrl.text.trim().isNotEmpty) {
                            setDialogState(() {
                              markingCtrl.text = dealersService.suggestMarkingForName(nameCtrl.text);
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  TextField(
                    controller: markingCtrl,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: const [UpperCaseTextFormatter()],
                    decoration: const InputDecoration(
                      hintText: 'e.g. JB, VM, JDC-2 (Permanent on carcass)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Contact Phone Number (Optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [PhoneNumberFormatter()],
                    decoration: const InputDecoration(
                      hintText: 'e.g. 0917-123-4567',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.check, size: 16),
              label: Text(isEditing ? 'Save Changes' : 'Register Dealer'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2D6A4F), foregroundColor: Colors.white),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(ctx);
                final name = nameCtrl.text.trim();
                final marking = markingCtrl.text.trim();
                final phone = phoneCtrl.text.trim();

                if (name.isEmpty) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Please enter dealer name'), backgroundColor: Colors.redAccent),
                  );
                  return;
                }
                if (marking.isEmpty) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Please enter or auto-suggest a permanent marking'), backgroundColor: Colors.redAccent),
                  );
                  return;
                }
                if (phone.isNotEmpty && !PhoneNumberFormatter.isValidExact11(phone)) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Contact phone number must be exactly 11 digits (e.g. 0917-123-4567).'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                  return;
                }

                final cleanMarking = marking.toUpperCase().trim();
                final existingWithMarking = dealersService.findDealerByMarking(cleanMarking);
                if (existingWithMarking != null && (!isEditing || existingWithMarking.id != editDealer.id)) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Marking "$cleanMarking" is already assigned to ${existingWithMarking.name}. Please enter or auto-suggest a unique marking.'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                  return;
                }

                final cleanName = name.toUpperCase().trim();
                final existingWithName = dealersService.findDealerByName(cleanName);
                if (!isEditing && existingWithName != null && existingWithName.category == category) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Meat Dealer "$cleanName" is already registered under ${category.toUpperCase()} category (${existingWithName.markings}).'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                  return;
                }

                try {
                  if (isEditing) {
                    final updated = editDealer.copyWith(
                      name: cleanName,
                      markings: cleanMarking,
                      category: category,
                      phone: phone.isNotEmpty ? phone : null,
                      clearPhone: phone.isEmpty,
                    );
                    await dealersService.updateDealer(updated);
                  } else {
                    await dealersService.addDealerManually(
                      name: cleanName,
                      markings: cleanMarking,
                      category: category,
                      phone: phone.isNotEmpty ? phone : null,
                    );
                  }

                  if (mounted) setState(() {});
                  navigator.pop();

                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(isEditing ? 'Dealer updated successfully!' : 'Meat Dealer $cleanName registered successfully!'),
                      backgroundColor: const Color(0xFF2D6A4F),
                    ),
                  );
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Registration error: $e'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteDealer(RegularDealer dealer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Remove Meat Dealer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to remove ${dealer.name} (${dealer.markings}) from the Meat Dealers Directory?',
              style: const TextStyle(fontSize: 14, color: Color(0xFF2D3748), fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.redAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This removes the dealer from the Meat Dealers Directory and frees their permanent marking. Historical slaughter requests, payments, and NMIS reports will remain intact.',
                      style: TextStyle(fontSize: 11.5, color: Colors.red.shade900, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await RegularDealersService.instance.deleteDealer(dealer.id);
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Removed ${dealer.name} from Meat Dealers Directory'),
              backgroundColor: const Color(0xFF0F5132),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to remove dealer: ${e.toString().replaceFirst('Exception: ', '')}'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  List<RegularDealer> _getFilteredDealers() {
    final allDealers = RegularDealersService.instance.allDealers;
    final q = _dealerSearchQuery.toLowerCase().trim();
    return allDealers.where((d) {
      final matchesQuery = q.isEmpty ||
          d.name.toLowerCase().contains(q) ||
          d.markings.toLowerCase().contains(q);

      bool matchesCat = true;
      if (_dealerCategoryFilter == 'Market') {
        matchesCat = d.category == 'market';
      } else if (_dealerCategoryFilter == 'Barangay') {
        matchesCat = d.category == 'barangay';
      } else if (_dealerCategoryFilter == 'New') {
        matchesCat = d.isNew;
      }

      return matchesQuery && matchesCat;
    }).toList();
  }

  Widget _buildMeatDealersDirectoryTab() {
    final dealersService = RegularDealersService.instance;
    final allDealers = dealersService.allDealers;
    final headsMap = _calcDealerLifetimeHeads();

    final filteredDealers = _getFilteredDealers();

    final totalDealers = allDealers.length;
    final marketCount = dealersService.marketDealers.length;
    final brgyCount = dealersService.barangayDealers.length;
    final newCount = allDealers.where((d) => d.isNew).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Card with Actions
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Official Meat Dealers Directory & Registration Roster',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D3748)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Official registry of regular and newly enrolled meat dealers, permanent carcass markings, categories, and lifetime slaughter records.',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.person_add, size: 16),
                label: const Text('+ Register Meat Dealer'),
                onPressed: () => _openRegisterDealerDialog(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D6A4F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // KPI Summary Cards
        Row(
          children: [
            _buildKpiCard('Total Registered Dealers', '$totalDealers dealers', const Color(0xFF2D6A4F), Icons.people_alt_outlined),
            const SizedBox(width: 16),
            _buildKpiCard('Market Dealers', '$marketCount dealers', const Color(0xFF2B6CB0), Icons.storefront),
            const SizedBox(width: 16),
            _buildKpiCard('Barangay Dealers', '$brgyCount dealers', const Color(0xFFD69E2E), Icons.home_work_outlined),
            const SizedBox(width: 16),
            _buildKpiCard('New Dealers (Last 30 Days)', '$newCount newly registered', const Color(0xFF38A169), Icons.fiber_new_rounded),
          ],
        ),
        const SizedBox(height: 20),

        // Dealer Role Change Requests Panel (Barangay <-> Market 2-Step Verification)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _roleChangeRequests.isNotEmpty
                  ? const Color(0xFFFDE68A)
                  : const Color(0xFFE2E8F0),
              width: _roleChangeRequests.isNotEmpty ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _roleChangeRequests.isNotEmpty
                          ? const Color(0xFFFEF3C7)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.swap_horiz_rounded,
                      color: _roleChangeRequests.isNotEmpty
                          ? const Color(0xFFB45309)
                          : const Color(0xFF475569),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Dealer Role Change Requests (${_roleChangeRequests.length})',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Approve Barangay ↔ Market switch requests. Approved dealers must complete formal role verification in the mobile app before their role updates.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _loadingRoleChanges ? null : _loadRoleChangeRequests,
                    icon: _loadingRoleChanges
                        ? const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 15),
                    label: const Text('Refresh', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0F5132),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
              if (_roleChangeRequests.isEmpty && !_loadingRoleChanges) ...[
                const SizedBox(height: 12),
                Text(
                  'No pending Barangay ↔ Market role change requests right now.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
                ),
              ] else if (_roleChangeRequests.isNotEmpty) ...[
                const SizedBox(height: 14),
                ..._roleChangeRequests.map((req) {
                  final name = (req['customer_name'] ?? 'Dealer').toString();
                  final fromRole = (req['from_role'] ?? 'barangay').toString().toLowerCase();
                  final toRole = (req['requested_role'] ?? 'market').toString().toLowerCase();
                  final reason = (req['reason'] ?? '').toString().trim();
                  final status = (req['status'] ?? 'pending').toString();
                  final isAwaitingVerification = status == 'approved_awaiting_verification';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isAwaitingVerification ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isAwaitingVerification ? const Color(0xFF86EFAC) : const Color(0xFFFCD34D),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF0F172A)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFCBD5E1)),
                                    ),
                                    child: Text(
                                      '${fromRole == 'market' ? 'Market' : 'Barangay'} → ${toRole == 'market' ? 'Market' : 'Barangay'}',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                                    ),
                                  ),
                                ],
                              ),
                              if (reason.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Reason: $reason',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (isAwaitingVerification)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF4ADE80)),
                            ),
                            child: const Text(
                              'Approved • Awaiting Customer Verification',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF166534)),
                            ),
                          )
                        else
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OutlinedButton(
                                onPressed: () => _handleRoleChangeDecision(req, approve: false),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red.shade700,
                                  side: BorderSide(color: Colors.red.shade300),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                child: const Text('Reject', style: TextStyle(fontSize: 12)),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: () => _handleRoleChangeDecision(req, approve: true),
                                icon: const Icon(Icons.check_rounded, size: 15),
                                label: const Text('Approve Switch', style: TextStyle(fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2D6A4F),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Filter & Search Controls
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search by dealer name or permanent marking...',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  ),
                  onChanged: (v) => setState(() => _dealerSearchQuery = v),
                ),
              ),
              const SizedBox(width: 16),
              const Text('Filter Category:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(width: 8),
              AnimatedSelectDropdown<String>(
                value: _dealerCategoryFilter,
                items: const ['All', 'Market', 'Barangay', 'New'],
                labelBuilder: (v) {
                  switch (v) {
                    case 'Market':
                      return 'Market Dealers';
                    case 'Barangay':
                      return 'Barangay Dealers';
                    case 'New':
                      return 'New Dealers (30 Days)';
                    default:
                      return 'All Dealers';
                  }
                },
                minMenuWidth: 200,
                backgroundColor: const Color(0xFFF7FAFC),
                borderColor: const Color(0xFFE2E8F0),
                textColor: const Color(0xFF1E293B),
                iconColor: const Color(0xFF2D6A4F),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                onChanged: (v) => setState(() => _dealerCategoryFilter = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Data Table Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Meat Dealers Registry Table (${filteredDealers.length} records)',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2D3748)),
                  ),
                  const Text('Click "Edit" to modify contact or marking details', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 820;
                  return Table(
                    border: TableBorder(
                      horizontalInside: BorderSide(color: Colors.grey.shade200),
                      top: BorderSide(color: Colors.grey.shade200),
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    columnWidths: isCompact
                        ? const {
                            0: FixedColumnWidth(34),
                            1: FlexColumnWidth(2.2),
                            2: FlexColumnWidth(1.1),
                            3: FlexColumnWidth(1.1),
                            4: FlexColumnWidth(1.4),
                          }
                        : const {
                            0: FixedColumnWidth(36),
                            1: FlexColumnWidth(2.1),
                            2: FlexColumnWidth(1.0),
                            3: FlexColumnWidth(1.0),
                            4: FlexColumnWidth(1.3),
                            5: FlexColumnWidth(1.1),
                            6: FlexColumnWidth(1.2),
                            7: FlexColumnWidth(1.3),
                          },
                    children: [
                      TableRow(
                        decoration: BoxDecoration(color: Colors.grey.shade100),
                        children: [
                          const Padding(padding: EdgeInsets.all(10), child: Text('#', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          const Padding(padding: EdgeInsets.all(10), child: Text('Meat Dealer Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          const Padding(padding: EdgeInsets.all(10), child: Text('Mark', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          const Padding(padding: EdgeInsets.all(10), child: Text('Category', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          if (!isCompact) ...[
                            const Padding(padding: EdgeInsets.all(10), child: Text('Contact', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                            const Padding(padding: EdgeInsets.all(10), child: Text('Lifetime Heads', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                            const Padding(padding: EdgeInsets.all(10), child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          ],
                          const Padding(padding: EdgeInsets.all(10), child: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        ],
                      ),
                      ...filteredDealers.asMap().entries.map((entry) {
                        final idx = entry.key + 1;
                        final d = entry.value;
                        final heads = headsMap[d.name.toLowerCase().trim()] ?? 0;
                        final isPendingMarking = d.markings.trim().isEmpty || d.markings.trim().toUpperCase() == 'PENDING';

                        return TableRow(
                          children: [
                            Padding(padding: const EdgeInsets.all(10), child: Text(idx.toString(), style: const TextStyle(fontSize: 12, color: Colors.grey))),
                            Padding(padding: const EdgeInsets.all(10), child: Text(d.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF2D3748)), overflow: TextOverflow.ellipsis)),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isPendingMarking ? Colors.grey.shade100 : const Color(0xFFE6F9F0),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: isPendingMarking ? Colors.grey.shade300 : const Color(0xFF2D6A4F).withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  isPendingMarking ? '—' : d.markings,
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: isPendingMarking ? Colors.grey.shade600 : const Color(0xFF2D6A4F)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: d.category == 'market' ? const Color(0xFFEBF8FF) : const Color(0xFFFEFCBF),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  d.category == 'market' ? 'Market' : 'Barangay',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: d.category == 'market' ? const Color(0xFF2B6CB0) : const Color(0xFFB7791F)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            if (!isCompact) ...[
                              Padding(padding: const EdgeInsets.all(10), child: Text(d.phone != null && d.phone!.isNotEmpty ? d.phone! : '—', style: const TextStyle(fontSize: 11.5), overflow: TextOverflow.ellipsis)),
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                  children: [
                                    const _PigIcon(size: 15, color: Color(0xFF2D6A4F)),
                                    const SizedBox(width: 4),
                                    Flexible(child: Text('$heads heads', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                  children: [
                                    Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: d.isActive ? Colors.green : Colors.grey)),
                                    const SizedBox(width: 5),
                                    Flexible(child: Text(d.isActive ? 'Active' : 'Inactive', style: const TextStyle(fontSize: 11, color: Colors.grey), overflow: TextOverflow.ellipsis)),
                                  ],
                                ),
                              ),
                            ],
                            Padding(
                              padding: const EdgeInsets.all(6),
                              child: Wrap(
                                spacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  OutlinedButton(
                                    onPressed: () => _openRegisterDealerDialog(editDealer: d),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      minimumSize: const Size(0, 28),
                                    ),
                                    child: const Text('Edit', style: TextStyle(fontSize: 11)),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                    tooltip: 'Remove Dealer',
                                    splashRadius: 16,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    onPressed: () => _confirmDeleteDealer(d),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }),
                    ],
                  );
                },
              ),
              if (filteredDealers.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text('No meat dealers match the selected search or filter.', style: TextStyle(color: Colors.grey)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  DONUT CHART PAINTER
// ═══════════════════════════════════════════════════════════
class _AnimatedCommoditiesDonut extends StatefulWidget {
  final List<String> labels;
  final List<int> values;
  final List<Color> colors;
  final String periodKey;

  const _AnimatedCommoditiesDonut({
    required this.labels,
    required this.values,
    required this.colors,
    required this.periodKey,
  });

  @override
  State<_AnimatedCommoditiesDonut> createState() => _AnimatedCommoditiesDonutState();
}

class _AnimatedCommoditiesDonutState extends State<_AnimatedCommoditiesDonut>
    with TickerProviderStateMixin {
  late final AnimationController _sweepCtrl;
  late final Animation<double> _sweepAnim;
  late final AnimationController _hoverCtrl;
  late final Animation<double> _hoverAnim;

  int? _hoveredIndex;
  int? _pinnedIndex;
  int? _lastActiveIndex;

  int? get _activeIndex => _hoveredIndex ?? _pinnedIndex;

  @override
  void initState() {
    super.initState();
    _sweepCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _sweepAnim = CurvedAnimation(parent: _sweepCtrl, curve: Curves.easeOutCubic);

    _hoverCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _hoverAnim = CurvedAnimation(parent: _hoverCtrl, curve: Curves.easeOutCubic);

    _sweepCtrl.forward();
  }

  @override
  void didUpdateWidget(covariant _AnimatedCommoditiesDonut oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.periodKey != widget.periodKey) {
      _hoveredIndex = null;
      _pinnedIndex = null;
      _lastActiveIndex = null;
      _hoverCtrl.value = 0.0;
      _sweepCtrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _sweepCtrl.dispose();
    _hoverCtrl.dispose();
    super.dispose();
  }

  void _setActiveHover(int? idx) {
    if (_hoveredIndex == idx) return;
    setState(() {
      _hoveredIndex = idx;
      if (_activeIndex != null) {
        _lastActiveIndex = _activeIndex;
        _hoverCtrl.forward();
      } else {
        _hoverCtrl.reverse();
      }
    });
  }

  void _togglePin(int? idx) {
    setState(() {
      if (idx == null || _pinnedIndex == idx) {
        _pinnedIndex = null;
      } else {
        _pinnedIndex = idx;
      }
      if (_activeIndex != null) {
        _lastActiveIndex = _activeIndex;
        _hoverCtrl.forward();
      } else {
        _hoverCtrl.reverse();
      }
    });
  }

  int? _hitTestSlice(Offset localPosition, Size size) {
    final total = widget.values.fold(0, (a, b) => a + b);
    if (total <= 0) return null;

    final center = Offset(size.width / 2, size.height / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    final dist = sqrt(dx * dx + dy * dy);

    final outerRadius = min(size.width, size.height) / 2 - 10;
    final innerRadius = outerRadius * 0.50;
    if (dist < innerRadius || dist > outerRadius + 10) return null;

    double angle = atan2(dy, dx) + pi / 2;
    if (angle < 0) angle += 2 * pi;

    double cumulative = 0;
    for (int i = 0; i < widget.values.length; i++) {
      final sweep = (widget.values[i] / total) * 2 * pi;
      if (angle >= cumulative && angle <= cumulative + sweep) {
        return i;
      }
      cumulative += sweep;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.values.fold(0, (a, b) => a + b);
    final activeIdx = _activeIndex;
    const chartSize = 220.0;

    return Column(
      children: [
        Center(
          child: SizedBox(
            width: chartSize,
            height: chartSize,
            child: MouseRegion(
              cursor: activeIdx != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
              onHover: (event) => _setActiveHover(_hitTestSlice(event.localPosition, const Size(chartSize, chartSize))),
              onExit: (_) => _setActiveHover(null),
              child: GestureDetector(
                onTapUp: (details) {
                  final hit = _hitTestSlice(details.localPosition, const Size(chartSize, chartSize));
                  _togglePin(hit);
                },
                child: AnimatedBuilder(
                  animation: Listenable.merge([_sweepAnim, _hoverAnim]),
                  builder: (context, _) {
                    final progress = _sweepAnim.value;
                    final displayTotal = (total * progress).round();
                    final painterActiveIdx = _activeIndex ?? (_hoverAnim.value > 0 ? _lastActiveIndex : null);

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(chartSize, chartSize),
                          painter: _DonutChartPainter(
                            values: widget.values,
                            colors: widget.colors,
                            progress: progress,
                            activeIndex: painterActiveIdx,
                            hoverProgress: _hoverAnim.value,
                          ),
                        ),
                        IgnorePointer(
                          child: SizedBox(
                            width: chartSize * 0.50,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              transitionBuilder: (child, anim) => FadeTransition(
                                opacity: anim,
                                child: ScaleTransition(
                                  scale: Tween<double>(begin: 0.92, end: 1.0).animate(anim),
                                  child: child,
                                ),
                              ),
                              child: activeIdx != null && activeIdx < widget.labels.length
                                  ? Column(
                                      key: ValueKey('slice_$activeIdx'),
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          widget.labels[activeIdx],
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: widget.colors[activeIdx % widget.colors.length],
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${widget.values[activeIdx]}',
                                          style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF0F172A),
                                            height: 1.1,
                                          ),
                                        ),
                                        Text(
                                          '${((widget.values[activeIdx] / total) * 100).toStringAsFixed(1)}%',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      key: const ValueKey('total'),
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '$displayTotal',
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF0F172A),
                                            height: 1.1,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          total == 1 ? 'Total Head' : 'Total Heads',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: List.generate(widget.labels.length, (idx) {
            final label = widget.labels[idx];
            final val = widget.values[idx];
            final color = widget.colors[idx % widget.colors.length];
            final pct = total > 0 ? (val / total) * 100 : 0.0;
            final isHighlighted = activeIdx == idx;
            final isDimmed = activeIdx != null && !isHighlighted;

            return MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => _setActiveHover(idx),
              onExit: (_) => _setActiveHover(null),
              child: GestureDetector(
                onTap: () => _togglePin(idx),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isHighlighted ? color.withValues(alpha: 0.12) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isHighlighted ? color : const Color(0xFFE2E8F0),
                      width: isHighlighted ? 1.4 : 1,
                    ),
                  ),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: isDimmed ? 0.52 : 1.0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$label: $val (${pct.toStringAsFixed(0)}%)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w500,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final List<int> values;
  final List<Color> colors;
  final double progress;
  final int? activeIndex;
  final double hoverProgress;

  _DonutChartPainter({
    required this.values,
    required this.colors,
    this.progress = 1.0,
    this.activeIndex,
    this.hoverProgress = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold(0, (a, b) => a + b);
    if (total == 0 || progress <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = min(size.width, size.height) / 2 - 12;
    final baseStrokeWidth = baseRadius * 0.44;
    final maxSweep = 2 * pi * progress;

    double startAngle = -pi / 2;
    double drawnSweep = 0.0;
    final dividerAngles = <double>[];

    for (int i = 0; i < values.length; i++) {
      final fullSliceSweep = (values[i] / total) * 2 * pi;
      final remaining = maxSweep - drawnSweep;
      if (remaining <= 0) break;

      final sweepAngle = min(fullSliceSweep, remaining);
      final isHighlighted = activeIndex == i;
      final isDimmed = activeIndex != null && !isHighlighted && hoverProgress > 0;

      final popOffset = isHighlighted ? 7.0 * hoverProgress : 0.0;
      final extraStroke = isHighlighted ? 4.5 * hoverProgress : 0.0;
      final midAngle = startAngle + sweepAngle / 2;
      final sliceCenter = Offset(
        center.dx + cos(midAngle) * popOffset,
        center.dy + sin(midAngle) * popOffset,
      );
      final sliceRadius = baseRadius - baseStrokeWidth / 2;
      final rect = Rect.fromCircle(center: sliceCenter, radius: sliceRadius);

      final baseColor = colors[i % colors.length];
      final color = isDimmed
          ? baseColor.withValues(alpha: 1.0 - (0.42 * hoverProgress))
          : baseColor;

      if (isHighlighted && hoverProgress > 0.05) {
        final glowPaint = Paint()
          ..color = baseColor.withValues(alpha: 0.22 * hoverProgress)
          ..style = PaintingStyle.stroke
          ..strokeWidth = baseStrokeWidth + extraStroke + 6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
        canvas.drawArc(rect, startAngle, sweepAngle, false, glowPaint);
      }

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = baseStrokeWidth + extraStroke
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);

      if (values.length > 1) {
        dividerAngles.add(startAngle);
      }

      startAngle += sweepAngle;
      drawnSweep += sweepAngle;
    }

    // Crisp white radial dividers between slices
    if (values.length > 1 && progress > 0.15) {
      final dividerPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4;
      final innerR = baseRadius - baseStrokeWidth - 2;
      final outerR = baseRadius + 10;
      for (final angle in dividerAngles) {
        final p1 = Offset(center.dx + cos(angle) * innerR, center.dy + sin(angle) * innerR);
        final p2 = Offset(center.dx + cos(angle) * outerR, center.dy + sin(angle) * outerR);
        canvas.drawLine(p1, p2, dividerPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.colors != colors ||
        oldDelegate.progress != progress ||
        oldDelegate.activeIndex != activeIndex ||
        oldDelegate.hoverProgress != hoverProgress;
  }
}

class _PigIcon extends StatelessWidget {
  final double size;
  final Color color;

  const _PigIcon({this.size = 16, this.color = const Color(0xFF2D6A4F)});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PigIconPainter(color: color),
    );
  }
}

class _PigIconPainter extends CustomPainter {
  final Color color;

  _PigIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final cutoutPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.08;

    // Left and right pig ears
    final leftEar = Path()
      ..moveTo(w * 0.14, h * 0.36)
      ..lineTo(w * 0.12, h * 0.10)
      ..lineTo(w * 0.36, h * 0.22)
      ..close();
    final rightEar = Path()
      ..moveTo(w * 0.86, h * 0.36)
      ..lineTo(w * 0.88, h * 0.10)
      ..lineTo(w * 0.64, h * 0.22)
      ..close();
    canvas.drawPath(leftEar, fillPaint);
    canvas.drawPath(rightEar, fillPaint);

    // Pig head
    final headRect = Rect.fromCenter(
      center: Offset(w * 0.5, h * 0.56),
      width: w * 0.78,
      height: h * 0.68,
    );
    canvas.drawOval(headRect, fillPaint);

    // Eyes
    canvas.drawCircle(Offset(w * 0.34, h * 0.44), w * 0.055, cutoutPaint);
    canvas.drawCircle(Offset(w * 0.66, h * 0.44), w * 0.055, cutoutPaint);

    // Snout
    final snoutRect = Rect.fromCenter(
      center: Offset(w * 0.5, h * 0.65),
      width: w * 0.44,
      height: h * 0.28,
    );
    canvas.drawOval(snoutRect, cutoutPaint);
    canvas.drawOval(snoutRect, strokePaint);

    // Nostrils
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.42, h * 0.65), width: w * 0.07, height: h * 0.11),
      fillPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.58, h * 0.65), width: w * 0.07, height: h * 0.11),
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _PigIconPainter oldDelegate) => oldDelegate.color != color;
}

/// Clean outline cow/cattle head vector icon matching the livestock reference.
class _CowHeadIcon extends StatelessWidget {
  final double size;
  final Color color;

  const _CowHeadIcon({this.size = 22, this.color = const Color(0xFF2D6A4F)});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _CowHeadIconPainter(color: color),
    );
  }
}

class _CowHeadIconPainter extends CustomPainter {
  final Color color;

  _CowHeadIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 24.0;
    final sy = size.height / 24.0;
    canvas.save();
    canvas.scale(sx, sy);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.65
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Left & right upward-curving horns
    final leftHorn = Path()
      ..moveTo(7.4, 8.2)
      ..cubicTo(5.6, 6.8, 5.2, 4.6, 6.4, 3.0)
      ..cubicTo(6.8, 4.5, 7.6, 5.8, 9.2, 6.5);
    canvas.drawPath(leftHorn, stroke);

    final rightHorn = Path()
      ..moveTo(16.6, 8.2)
      ..cubicTo(18.4, 6.8, 18.8, 4.6, 17.6, 3.0)
      ..cubicTo(17.2, 4.5, 16.4, 5.8, 14.8, 6.5);
    canvas.drawPath(rightHorn, stroke);

    // Top crown connecting horns
    final crown = Path()
      ..moveTo(8.8, 6.6)
      ..quadraticBezierTo(12.0, 5.6, 15.2, 6.6);
    canvas.drawPath(crown, stroke);

    // Left & right leaf-shaped ears
    final leftEar = Path()
      ..moveTo(7.3, 8.8)
      ..cubicTo(5.2, 7.6, 3.2, 8.0, 2.0, 9.2)
      ..cubicTo(3.1, 11.4, 5.4, 11.8, 7.1, 10.6);
    canvas.drawPath(leftEar, stroke);

    final rightEar = Path()
      ..moveTo(16.7, 8.8)
      ..cubicTo(18.8, 7.6, 20.8, 8.0, 22.0, 9.2)
      ..cubicTo(20.9, 11.4, 18.6, 11.8, 16.9, 10.6);
    canvas.drawPath(rightEar, stroke);

    // Outer face cheeks tapering down to muzzle
    final faceSides = Path()
      ..moveTo(7.4, 8.2)
      ..cubicTo(7.0, 11.2, 7.8, 14.0, 8.8, 16.2)
      ..moveTo(16.6, 8.2)
      ..cubicTo(17.0, 11.2, 16.2, 14.0, 15.2, 16.2);
    canvas.drawPath(faceSides, stroke);

    // Inner brow-to-muzzle bridge contour lines (signature reference detail)
    final innerContours = Path()
      ..moveTo(7.5, 9.1)
      ..cubicTo(9.7, 10.2, 10.3, 12.6, 9.6, 15.6)
      ..moveTo(16.5, 9.1)
      ..cubicTo(14.3, 10.2, 13.7, 12.6, 14.4, 15.6);
    canvas.drawPath(innerContours, stroke);

    // Rounded snout / muzzle
    final muzzle = Path()
      ..moveTo(8.6, 16.5)
      ..cubicTo(8.5, 14.8, 15.5, 14.8, 15.4, 16.5)
      ..cubicTo(15.7, 18.7, 14.4, 19.6, 12.0, 19.6)
      ..cubicTo(9.6, 19.6, 8.3, 18.7, 8.6, 16.5)
      ..close();
    canvas.drawPath(muzzle, stroke);

    // Lower chin/lip curve
    final chin = Path()
      ..moveTo(9.8, 19.6)
      ..quadraticBezierTo(12.0, 21.1, 14.2, 19.6);
    canvas.drawPath(chin, stroke);

    // Eyes (small angled ovals)
    canvas.save();
    canvas.translate(8.8, 11.7);
    canvas.rotate(0.45);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 1.0, height: 1.5), fill);
    canvas.restore();

    canvas.save();
    canvas.translate(15.2, 11.7);
    canvas.rotate(-0.45);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 1.0, height: 1.5), fill);
    canvas.restore();

    // Nostrils (angled teardrops inside muzzle)
    canvas.save();
    canvas.translate(10.5, 17.5);
    canvas.rotate(-0.55);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 0.9, height: 1.5), fill);
    canvas.restore();

    canvas.save();
    canvas.translate(13.5, 17.5);
    canvas.rotate(0.55);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 0.9, height: 1.5), fill);
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CowHeadIconPainter oldDelegate) => oldDelegate.color != color;
}

import 'dart:typed_data';
import 'dart:async';
import 'dart:math';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import 'illegal_slaughter_reports_view.dart';
import '../services/report_pdf_generator.dart';
import '../services/regular_dealers_service.dart';
import '../services/nmic_report_pdf_generator.dart';
import '../utils/text_capitalization_formatters.dart';

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
  String _reportType = 'Daily Report'; // 'Daily Report', 'Weekly Report', 'Monthly Report'
  late String _activeTab;

  // Selected date reference for Daily / Weekly / Monthly
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDate = DateTime.now();

  // Real-time alert polling state for Illegal Slaughter Reports
  Timer? _alertTimer;
  int _unreviewedIllegalReports = 0;
  Map<String, dynamic>? _latestIllegalReport;

  // NMIC & Abattoir Official Reports state
  DateTime _nmicReportDate = DateTime.now();
  DateTime _monthlyLogMonth = DateTime(DateTime.now().year, DateTime.now().month);
  String _selectedNmicSpecies = 'HOG';
  String _selectedNmicFormType = 'Weekly Summary';
  String? _selectedCustomerFilter;
  String _customerPeriodFilter = 'This Month';
  List<Map<String, dynamic>> _nmicTransmissionsList = [];
  String _dealerSearchQuery = '';
  String _dealerCategoryFilter = 'All'; // 'All', 'Market', 'Barangay', 'New'

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab ?? 'Analytics';
    _loadData();
    _loadIllegalReportAlerts();
    RegularDealersService.instance.init().then((_) {
      RegularDealersService.instance.getTransmissions().then((list) {
        if (mounted) setState(() => _nmicTransmissionsList = list);
      });
    });
    _alertTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _loadIllegalReportAlerts();
    });
  }

  @override
  void didUpdateWidget(ReportsRecordsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != null && widget.initialTab != oldWidget.initialTab) {
      setState(() {
        _activeTab = widget.initialTab!;
      });
    }
  }

  @override
  void dispose() {
    _alertTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadIllegalReportAlerts() async {
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
            'location': r['location'] ?? 'Tabaco City',
            'reporter_name': r['reporter_name'] ?? 'Citizen',
            'created_at': r['incident_date'] ?? r['created_at'],
          };
        }
      }

      try {
        final notifs = await supabase
            .from('notifications')
            .select('id, type, reference_no, data, created_at')
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
              'location': data['location'] ?? 'Tabaco City',
              'reporter_name': data['reporter_name'] ?? 'Citizen',
              'created_at': n['created_at'],
            };
          }
        }
      } catch (_) {}

      int count = 0;
      Map<String, dynamic>? latest;
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
          latest ??= rep;
        }
      }

      if (mounted) {
        setState(() {
          _unreviewedIllegalReports = count;
          _latestIllegalReport = latest;
        });
      }
    } catch (_) {}
  }

  // ════════════════════════════════════════════
  //  LOAD DATA (ALL REQUESTS ENRICHED)
  // ════════════════════════════════════════════
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
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

  double _calcRequestFee(Map<String, dynamic> req) {
    final payment = req['payment'] as Map<String, dynamic>?;
    if (payment != null) {
      final amt = double.tryParse((payment['total_amount'] ?? payment['amount'] ?? 0).toString()) ?? 0;
      if (amt > 0) return amt;
    }
    final reqAmt = double.tryParse((req['total_amount'] ?? req['total_fee'] ?? 0).toString()) ?? 0;
    if (reqAmt > 0) return reqAmt;

    final weight = _carcassWeight(req);
    if (weight > 0) {
      return (weight * 5.0) + 250.0;
    }
    return 0.0;
  }

  bool _isHealthIssue(Map<String, dynamic> r) {
    final status = (r['status'] ?? '').toString().toLowerCase();
    final anti = (r['anti_mortem'] ?? '').toString().toLowerCase();
    final post = (r['post_mortem'] ?? '').toString().toLowerCase();
    final condReason = (r['condemnation_reason'] ?? '').toString().trim();
    final vetFindings = (r['veterinary_findings'] ?? '').toString().trim();

    if (anti == 'failed' || status == 'anti_mortem_failed' || status == 'taken_back') return true;
    if (post == 'failed' || status == 'post_mortem_failed' || status == 'condemned') return true;
    if (condReason.isNotEmpty && condReason != 'null') return true;
    if (vetFindings.isNotEmpty && vetFindings != 'null' && anti != 'passed') return true;
    return false;
  }

  bool _isProcessed(Map<String, dynamic> r) {
    if (_isHealthIssue(r)) return false;
    final status = (r['status'] ?? '').toString().toLowerCase();
    final post = (r['post_mortem'] ?? '').toString().toLowerCase();
    final anti = (r['anti_mortem'] ?? '').toString().toLowerCase();

    if (post == 'passed') return true;
    if (['releasable', 'paid', 'released', 'completed'].contains(status)) return true;
    if (status == 'slaughter_started' && anti == 'passed') return true;
    return false;
  }

  bool _isUninspected(Map<String, dynamic> r) {
    if (_isHealthIssue(r)) return false;
    if (_isProcessed(r)) return false;
    return true;
  }

  DateTime _activeDate() => _selectedDate ?? DateTime.now();

  DateTimeRange _getActiveDateRange() {
    final base = _activeDate();
    if (_reportType == 'Daily Report') {
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
    if (_reportType == 'Daily Report') {
      return DateFormat('EEEE, MMMM d, yyyy').format(base);
    } else if (_reportType == 'Weekly Report') {
      final range = _getActiveDateRange();
      return 'Week of ${DateFormat('MMM d').format(range.start)} – ${DateFormat('MMM d, yyyy').format(range.end)}';
    } else {
      return DateFormat('MMMM yyyy').format(base);
    }
  }

  DateTime? _getRequestDate(Map<String, dynamic> r) {
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

  // Navigation handlers
  void _prevPeriod() {
    setState(() {
      final cur = _activeDate();
      if (_reportType == 'Daily Report') {
        _selectedDate = cur.subtract(const Duration(days: 1));
      } else if (_reportType == 'Weekly Report') {
        _selectedDate = cur.subtract(const Duration(days: 7));
      } else {
        _selectedDate = DateTime(cur.year, cur.month - 1, 1);
      }
      _calendarMonth = DateTime(_selectedDate!.year, _selectedDate!.month);
    });
  }

  void _nextPeriod() {
    setState(() {
      final cur = _activeDate();
      if (_reportType == 'Daily Report') {
        _selectedDate = cur.add(const Duration(days: 1));
      } else if (_reportType == 'Weekly Report') {
        _selectedDate = cur.add(const Duration(days: 7));
      } else {
        _selectedDate = DateTime(cur.year, cur.month + 1, 1);
      }
      _calendarMonth = DateTime(_selectedDate!.year, _selectedDate!.month);
    });
  }

  void _resetToCurrentPeriod() {
    setState(() {
      _selectedDate = DateTime.now();
      _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
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
    final postMortem = req['post_mortem']?.toString();
    final notes = req['process_notes']?.toString() ?? '';
    if (postMortem == 'Failed') return 'Condemned';
    if (notes.isNotEmpty && notes != 'null') return notes;
    return 'Passed Inspection';
  }

  // ════════════════════════════════════════════
  //  PDF EXPORT ACTIONS
  // ════════════════════════════════════════════
  Future<void> _exportActiveReport() async {
    // Naturally exports everything in a single PDF:
    // Sections 1, 2, and 3, plus Total Revenue and Livestock Processed
    await _exportReportBySection('all', 'Complete_Report');
  }

  void _showExportOptionsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2D6A4F).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.picture_as_pdf, color: Color(0xFF2D6A4F), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Export Report Options', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(_getActivePeriodLabel(), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildExportOptionTile(
              icon: Icons.file_copy_outlined,
              color: const Color(0xFF1B4332),
              title: 'Complete Slaughterhouse Report',
              subtitle: 'Includes Total Revenue, Processed, Health Issues & Uninspected',
              onTap: () {
                Navigator.pop(ctx);
                _exportReportBySection('all', 'Complete_Report');
              },
            ),
            const Divider(height: 20),
            _buildExportOptionTile(
              icon: Icons.assignment_outlined,
              color: const Color(0xFF2D6A4F),
              title: '1. Production Report Only',
              subtitle: 'Incoming Livestock & Carcass Production (Passed Inspection)',
              onTap: () {
                Navigator.pop(ctx);
                _exportReportBySection('production', 'Production_Report');
              },
            ),
            const SizedBox(height: 10),
            _buildExportOptionTile(
              icon: Icons.health_and_safety_outlined,
              color: const Color(0xFFC53030),
              title: '2. Health Issues & Condemnations Only',
              subtitle: 'Ante-mortem rejections, pathology & post-mortem condemnations',
              onTap: () {
                Navigator.pop(ctx);
                _exportReportBySection('health_issues', 'Health_Issues_Report');
              },
            ),
            const SizedBox(height: 10),
            _buildExportOptionTile(
              icon: Icons.cancel_outlined,
              color: const Color(0xFF4A5568),
              title: '3. Uninspected Livestock Report Only',
              subtitle: 'Registrations cancelled, withdrawn, or awaiting inspection',
              onTap: () {
                Navigator.pop(ctx);
                _exportReportBySection('uninspected', 'Uninspected_Report');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _buildExportOptionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
            ),
            const Icon(Icons.download, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
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
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now());
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(
        children: [
          _buildHeader(dateStr),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF2D6A4F)))
                : RefreshIndicator(
                    onRefresh: _loadData,
                    color: const Color(0xFF2D6A4F),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_unreviewedIllegalReports > 0) ...[
                            _buildIllegalReportUrgentAlertBanner(),
                            const SizedBox(height: 20),
                          ],
                          _buildFilterBar(),
                          const SizedBox(height: 20),
                          _buildSummaryCards(),
                          const SizedBox(height: 24),
                          _buildTabButtons(),
                          const SizedBox(height: 24),
                          if (_activeTab == 'Analytics') ...[
                            _buildCalendarAndChart(),
                            const SizedBox(height: 24),
                            _buildOperationsRecordsSection(),
                            const SizedBox(height: 24),
                            _buildHealthIssuesSection(),
                            const SizedBox(height: 24),
                            _buildUninspectedSection(),
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
                          ] else ...[
                            _buildReportIllegalSection(),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  HEADER
  // ════════════════════════════════════════════
  Widget _buildHeader(String dateStr) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Reports & Records',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
              const SizedBox(height: 2),
              Text('Daily, weekly, monthly reports, revenue & animal health surveillance',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(dateStr, style: const TextStyle(fontSize: 12, color: Color(0xFF4A5568))),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  FILTER & TIMEFRAME NAVIGATOR BAR
  // ════════════════════════════════════════════
  Widget _buildFilterBar() {
    final periodLabel = _getActivePeriodLabel();
    String quickResetText = 'Today';
    if (_reportType == 'Weekly Report') quickResetText = 'This Week';
    if (_reportType == 'Monthly Report') quickResetText = 'This Month';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dropdownChip(
                value: _reportType,
                items: ['Daily Report', 'Weekly Report', 'Monthly Report'],
                onChanged: (v) => setState(() => _reportType = v),
              ),
              const SizedBox(width: 14),
              // Timeframe Navigation Buttons
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
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 20),
                      onPressed: _prevPeriod,
                      splashRadius: 18,
                      tooltip: 'Previous period',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _activeDate(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                        );
                        if (picked != null) {
                          setState(() {
                            _selectedDate = picked;
                            _calendarMonth = DateTime(picked.year, picked.month);
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_outlined, size: 14, color: Color(0xFF2D6A4F)),
                            const SizedBox(width: 6),
                            Text(
                              periodLabel,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2D3748),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 20),
                      onPressed: _nextPeriod,
                      splashRadius: 18,
                      tooltip: 'Next period',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: _resetToCurrentPeriod,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF2D6A4F),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                child: Text(quickResetText, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed: _exportActiveReport,
                icon: const Icon(Icons.picture_as_pdf, size: 16, color: Colors.white),
                label: Text(
                  'Export $_reportType',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D6A4F),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.horizontal(left: Radius.circular(8)),
                  ),
                ),
              ),
              Container(
                height: 46,
                decoration: const BoxDecoration(
                  color: Color(0xFF1B4332),
                  borderRadius: BorderRadius.horizontal(right: Radius.circular(8)),
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                  tooltip: 'Export options (individual sections)',
                  onPressed: _showExportOptionsDialog,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dropdownChip({required String value, required List<String> items, required ValueChanged<String> onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF2F7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.grey, size: 18),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))).toList(),
          onChanged: (val) {
            if (val != null) onChanged(val);
          },
        ),
      ),
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

    return Row(
      children: [
        _summaryCard(
          label: 'Total Revenue',
          value: '\u20b1 ${NumberFormat('#,##0.00').format(totalRevenue)}',
          accent: const Color(0xFF1B4332),
          changeText: 'Fees collected for processed livestock',
          changeColor: const Color(0xFF2D6A4F),
          icon: Icons.payments_outlined,
          iconColor: const Color(0xFF1B4332),
        ),
        const SizedBox(width: 16),
        _summaryCard(
          label: 'Livestock Processed',
          value: '$livestockProcessed Heads',
          accent: const Color(0xFF2D6A4F),
          changeText: '${processed.length} operations passed inspection',
          changeColor: const Color(0xFF2D6A4F),
          showDot: true,
          dotColor: const Color(0xFF2D6A4F),
        ),
        const SizedBox(width: 16),
        _summaryCard(
          label: 'Health Issues / Condemned',
          value: '${healthIssues.length} Cases',
          accent: const Color(0xFFC53030),
          changeText: healthIssues.isEmpty ? 'Clean record (100% Passed)' : 'Listed separately below',
          changeColor: const Color(0xFFC53030),
          icon: Icons.health_and_safety_outlined,
          iconColor: const Color(0xFFC53030),
        ),
        const SizedBox(width: 16),
        _summaryCard(
          label: 'Did Not Undergo Inspection',
          value: '${uninspected.length} Cases',
          accent: const Color(0xFF4A5568),
          changeText: uninspected.isEmpty ? 'None (all underwent inspection)' : 'Pending / cancelled / withdrawn',
          changeColor: const Color(0xFF718096),
          icon: Icons.pending_actions_outlined,
          iconColor: const Color(0xFF4A5568),
        ),
      ],
    );
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
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
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
      ),
    );
  }

  // ════════════════════════════════════════════
  //  TAB BUTTONS
  // ════════════════════════════════════════════
  Widget _buildTabButtons() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _tabButton('Analytics', _activeTab == 'Analytics'),
          const SizedBox(width: 8),
          _tabButton('Daily Production (Abattoir)', _activeTab == 'Daily Production (Abattoir)'),
          const SizedBox(width: 8),
          _tabButton('Monthly Dealer Log', _activeTab == 'Monthly Dealer Log'),
          const SizedBox(width: 8),
          _tabButton('NMIS Reports & Transmittal', _activeTab == 'NMIS Reports & Transmittal'),
          const SizedBox(width: 8),
          _tabButton('Customer Records', _activeTab == 'Customer Records'),
          const SizedBox(width: 8),
          _tabButton('Meat Dealers Directory', _activeTab == 'Meat Dealers Directory'),
          const SizedBox(width: 8),
          _tabButton(
            'Report Illegal',
            _activeTab == 'Report Illegal',
            badgeCount: _unreviewedIllegalReports,
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String label, bool isActive, {int badgeCount = 0}) {
    return OutlinedButton(
      onPressed: () => setState(() => _activeTab = label),
      style: OutlinedButton.styleFrom(
        backgroundColor: isActive ? const Color(0xFF2D6A4F).withValues(alpha: 0.08) : Colors.white,
        foregroundColor: isActive ? const Color(0xFF2D6A4F) : const Color(0xFF4A5568),
        side: BorderSide(
          color: isActive ? const Color(0xFF2D6A4F) : Colors.grey.shade300,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: isActive ? FontWeight.w600 : FontWeight.w500)),
          if (badgeCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$badgeCount',
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIllegalReportUrgentAlertBanner() {
    final ref = _latestIllegalReport?['reference_no'] ?? 'Report';
    final loc = _latestIllegalReport?['location'] ?? 'Location not specified';
    final reporter = _latestIllegalReport?['reporter_name'] ?? 'Citizen';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFDC2626).withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFDC2626).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '🚨 New Illegal Slaughter Whistleblower Report ($_unreviewedIllegalReports Pending)',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF991B1B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('ALERT', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Ref: $ref • Location: $loc • Reporter: $reporter',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C)),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => setState(() => _activeTab = 'Report Illegal'),
            icon: const Icon(Icons.arrow_forward, size: 15),
            label: const Text('Go to Report Illegal', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  CALENDAR + DONUT CHART
  // ════════════════════════════════════════════
  Widget _buildCalendarAndChart() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildCalendarCard()),
        const SizedBox(width: 24),
        Expanded(child: _buildDonutChartCard()),
      ],
    );
  }

  Widget _buildCalendarCard() {
    final month = _calendarMonth;
    final monthStr = DateFormat('MMMM yyyy').format(month);
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);
    final startWeekday = firstDay.weekday % 7;
    final daysInMonth = lastDay.day;

    final cells = <Widget>[];
    for (int i = 0; i < startWeekday; i++) {
      final prevMonthLastDay = DateTime(month.year, month.month, 0).day;
      cells.add(_calendarDay((prevMonthLastDay - startWeekday + i + 1).toString(), isOtherMonth: true));
    }
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(month.year, month.month, d);
      final isSelected = _selectedDate != null &&
          _selectedDate!.year == date.year &&
          _selectedDate!.month == date.month &&
          _selectedDate!.day == date.day;
      final isToday = DateTime.now().year == date.year &&
          DateTime.now().month == date.month &&
          DateTime.now().day == date.day;
      cells.add(_calendarDay(d.toString(), isSelected: isSelected, isToday: isToday, onTap: () {
        setState(() {
          _selectedDate = date;
        });
      }));
    }

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
          const Text('Date Selection', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
          const SizedBox(height: 4),
          Text('Select date to jump Daily / Weekly / Monthly report timeframe', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => setState(() {
                  _calendarMonth = DateTime(month.year, month.month - 1);
                }),
                icon: const Icon(Icons.chevron_left, size: 20),
                splashRadius: 18,
              ),
              Text(monthStr, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              IconButton(
                onPressed: () => setState(() {
                  _calendarMonth = DateTime(month.year, month.month + 1);
                }),
                icon: const Icon(Icons.chevron_right, size: 20),
                splashRadius: 18,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa']
                .map((d) => Expanded(
                      child: Center(
                        child: Text(d, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 6),
          ...List.generate(
            ((cells.length + 6) ~/ 7),
            (row) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: List.generate(7, (col) {
                  final idx = row * 7 + col;
                  return Expanded(child: idx < cells.length ? cells[idx] : const SizedBox.shrink());
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _calendarDay(String day, {bool isSelected = false, bool isToday = false, bool isOtherMonth = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(2),
        height: 36,
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF2D6A4F)
              : isToday
                  ? const Color(0xFF2D6A4F).withValues(alpha: 0.1)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            day,
            style: TextStyle(
              fontSize: 13,
              fontWeight: (isSelected || isToday) ? FontWeight.bold : FontWeight.w500,
              color: isSelected
                  ? Colors.white
                  : isOtherMonth
                      ? Colors.grey.shade300
                      : const Color(0xFF2D3748),
            ),
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
          else ...[
            Center(
              child: SizedBox(
                width: 200,
                height: 200,
                child: CustomPaint(
                  painter: _DonutChartPainter(
                    values: dist.values.toList(),
                    colors: mappedColors,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: dist.entries.toList().asMap().entries.map((entry) {
                final idx = entry.key;
                final e = entry.value;
                final color = mappedColors[idx];
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('${e.key}: ${e.value} heads', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  ],
                );
              }).toList(),
            ),
          ],
        ],
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
    final scrollController = ScrollController();

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
                IconButton(
                  onPressed: () => _exportReportBySection('production', 'Production_Report'),
                  icon: const Icon(Icons.download, size: 20, color: Color(0xFF2D6A4F)),
                  splashRadius: 20,
                  tooltip: 'Export Production Report PDF',
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
                final availableWidth = constraints.maxWidth;
                final tableWidth = max(1050.0, availableWidth);
                final colSpacing = (availableWidth > 1400)
                    ? 32.0
                    : (availableWidth > 1100 ? 22.0 : 16.0);

                return Scrollbar(
                  controller: scrollController,
                  thumbVisibility: false,
                  trackVisibility: false,
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
                    ),
                    child: SingleChildScrollView(
                      controller: scrollController,
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: tableWidth),
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(const Color(0xFFF7FAFC)),
                          dataRowMinHeight: 52,
                          dataRowMaxHeight: 68,
                          columnSpacing: colSpacing,
                          columns: const [
                            DataColumn(label: Text('Reference', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                            DataColumn(label: Text('Customer Name', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                            DataColumn(label: Text('Section', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                            DataColumn(label: Text('Commodity', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                            DataColumn(label: Text('Heads', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                            DataColumn(label: Text('Carcass Weight', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                            DataColumn(label: Text('Revenue (PHP)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                            DataColumn(label: Text('Inspector', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                            DataColumn(label: Text('Status / Remarks', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                          ],
                          rows: records.map((req) {
                            final ref = _refNo(req);
                            final type = req['request_type']?.toString() ?? '';
                            final isBarangay = type == 'barangay';
                            final livestock = req['livestock_type']?.toString() ?? '\u2014';
                            final animalCount = req['animal_count'] ?? 1;
                            final weight = _carcassWeight(req);
                            final fee = _calcRequestFee(req);
                            final inspector = req['inspector_name']?.toString() ?? '\u2014';
                            final remark = _remarkForRequest(req);

                            return DataRow(cells: [
                              DataCell(Text(ref, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12))),
                              DataCell(Text(req['customer_name']?.toString() ?? '\u2014', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                              DataCell(_buildTypeBadge(isBarangay ? 'Barangay' : 'Market')),
                              DataCell(Text(livestock, style: const TextStyle(fontSize: 12))),
                              DataCell(Text('$animalCount', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                              DataCell(Text(weight > 0 ? '${weight.toStringAsFixed(1)} kg' : '\u2014', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                              DataCell(Text(fee > 0 ? '\u20b1 ${NumberFormat('#,##0.00').format(fee)}' : '\u2014',
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF1B4332)))),
                              DataCell(Text(inspector, style: const TextStyle(fontSize: 12, color: Color(0xFF4A5568)))),
                              DataCell(Text(remark, style: const TextStyle(fontSize: 11, color: Color(0xFF2D6A4F), fontWeight: FontWeight.w500))),
                            ]);
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
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
    final scrollController = ScrollController();

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
                        'Ante-mortem rejection, pathology detected, or post-mortem carcass condemnation',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _exportReportBySection('health_issues', 'Health_Issues_Report'),
                  icon: const Icon(Icons.download, size: 20, color: Color(0xFFC53030)),
                  splashRadius: 20,
                  tooltip: 'Export Health Issues & Condemnations Report PDF',
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
                final availableWidth = constraints.maxWidth;
                final tableWidth = max(1050.0, availableWidth);
                final colSpacing = (availableWidth > 1400)
                    ? 32.0
                    : (availableWidth > 1100 ? 22.0 : 16.0);

                return Scrollbar(
                  controller: scrollController,
                  thumbVisibility: false,
                  trackVisibility: false,
                  child: SingleChildScrollView(
                    controller: scrollController,
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: tableWidth),
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(const Color(0xFFFFF5F5)),
                        dataRowMinHeight: 52,
                        dataRowMaxHeight: 70,
                        columnSpacing: colSpacing,
                        columns: const [
                          DataColumn(label: Text('Reference', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF9B2C2C)))),
                          DataColumn(label: Text('Customer Name', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                          DataColumn(label: Text('Livestock / Heads', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                          DataColumn(label: Text('Inspection Stage', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                          DataColumn(label: Text('Veterinary Findings / Health Issues', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                          DataColumn(label: Text('Action Taken / Disposition', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                        ],
                        rows: healthIssues.map((req) {
                          final ref = _refNo(req);
                          final name = req['customer_name']?.toString() ?? '\u2014';
                          final livestock = '${req['livestock_type'] ?? 'Unknown'} (${req['animal_count'] ?? 1} head)';

                          final anti = (req['anti_mortem'] ?? '').toString();
                          final post = (req['post_mortem'] ?? '').toString();
                          final status = (req['status'] ?? '').toString();

                          String stage = 'Ante-Mortem';
                          String disposition = 'Ante-Mortem Failed — Taken Back';

                          if (post == 'Failed' || status == 'condemned' || status == 'post_mortem_failed') {
                            stage = 'Post-Mortem Inspection';
                            disposition = 'Carcass Condemned';
                          } else if (anti == 'Failed' || status == 'anti_mortem_failed' || status == 'taken_back') {
                            stage = 'Ante-Mortem Inspection';
                            disposition = 'Rejected / Taken Back by Owner';
                          }

                          String findings = req['veterinary_findings']?.toString() ??
                              req['condemnation_reason']?.toString() ??
                              req['process_notes']?.toString() ??
                              'Health abnormality detected';
                          if (findings.isEmpty || findings == 'null') {
                            findings = 'Did not meet health & inspection standards';
                          }

                          return DataRow(cells: [
                            DataCell(Text(ref, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF9B2C2C)))),
                            DataCell(Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                            DataCell(Text(livestock, style: const TextStyle(fontSize: 12))),
                            DataCell(Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFED7D7),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(stage, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFC53030))),
                            )),
                            DataCell(Text(findings, style: const TextStyle(fontSize: 12, color: Color(0xFF742A2A)))),
                            DataCell(Text(disposition, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF9B2C2C)))),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  SECTION 3: CASES THAT DID NOT UNDERGO INSPECTION (SEPARATE LIST)
  // ════════════════════════════════════════════
  Widget _buildUninspectedSection() {
    final periodReqs = _getRequestsInActivePeriod();
    final uninspected = periodReqs.where(_isUninspected).toList();
    final scrollController = ScrollController();

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
              color: Color(0xFFF7FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A5568),
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
                        'Cases Involving Livestock That Did Not Undergo Inspection (${uninspected.length})',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2D3748)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Registrations that were cancelled, withdrawn, or are still awaiting arrival & inspection',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _exportReportBySection('uninspected', 'Uninspected_Report'),
                  icon: Icon(Icons.download, size: 20, color: Colors.grey.shade600),
                  splashRadius: 20,
                  tooltip: 'Export Uninspected Livestock Report PDF',
                ),
              ],
            ),
          ),
          if (uninspected.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_outline, color: Color(0xFF2D6A4F), size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'All registered livestock underwent inspection as scheduled.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = constraints.maxWidth;
                final tableWidth = max(1050.0, availableWidth);
                final colSpacing = (availableWidth > 1400)
                    ? 32.0
                    : (availableWidth > 1100 ? 22.0 : 16.0);

                return Scrollbar(
                  controller: scrollController,
                  thumbVisibility: false,
                  trackVisibility: false,
                  child: SingleChildScrollView(
                    controller: scrollController,
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: tableWidth),
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(const Color(0xFFEDF2F7)),
                        dataRowMinHeight: 52,
                        dataRowMaxHeight: 68,
                        columnSpacing: colSpacing,
                        columns: const [
                          DataColumn(label: Text('Reference', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                          DataColumn(label: Text('Customer Name', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                          DataColumn(label: Text('Livestock / Heads', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                          DataColumn(label: Text('Scheduled Date', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                          DataColumn(label: Text('Registration Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                          DataColumn(label: Text('Reason / Remarks', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                        ],
                        rows: uninspected.map((req) {
                          final ref = _refNo(req);
                          final name = req['customer_name']?.toString() ?? '\u2014';
                          final livestock = '${req['livestock_type'] ?? 'Unknown'} (${req['animal_count'] ?? 1} head)';
                          final sched = req['preferred_date']?.toString() ?? req['created_at']?.toString() ?? '\u2014';
                          final schedFmt = sched.length > 10 ? sched.substring(0, 10) : sched;
                          final status = (req['status'] ?? 'Pending').toString();

                          String reason = 'Inspection pending or omitted before slaughter';
                          if (status == 'cancelled') {
                            reason = 'Booking cancelled by customer prior to arrival';
                          } else if (status == 'rejected') {
                            reason = 'Registration rejected during document verification';
                          } else if (status == 'pending' || status == 'approved') {
                            reason = 'Awaiting animal arrival & ante-mortem inspection';
                          }

                          return DataRow(cells: [
                            DataCell(Text(ref, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12))),
                            DataCell(Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                            DataCell(Text(livestock, style: const TextStyle(fontSize: 12))),
                            DataCell(Text(schedFmt, style: const TextStyle(fontSize: 12))),
                            DataCell(Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(status.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4A5568))),
                            )),
                            DataCell(Text(reason, style: const TextStyle(fontSize: 12, color: Color(0xFF718096)))),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ),
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

  // ════════════════════════════════════════════
  //  REPORT ILLEGAL SECTION
  // ════════════════════════════════════════════
  Widget _buildReportIllegalSection() {
    return IllegalSlaughterReportsView(
      onReportsUpdated: _loadIllegalReportAlerts,
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
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Expanded(
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
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(DateFormat('yyyy-MM-dd').format(_nmicReportDate)),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _nmicReportDate,
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) setState(() => _nmicReportDate = picked);
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.picture_as_pdf, size: 16),
                label: const Text('Export Official PDF'),
                onPressed: () async {
                  final pdfBytes = await NmicReportPdfGenerator.generateDailyProductionReport(
                    date: _nmicReportDate,
                    requests: _allRequests,
                  );
                  await Printing.layoutPdf(onLayout: (_) => pdfBytes);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D6A4F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.send_rounded, size: 16),
                label: const Text('Send to NMIC via Email'),
                onPressed: () {
                  _openNmicTransmittalDialog(
                    reportType: 'Daily Production Report',
                    periodLabel: DateFormat('MMMM d, yyyy').format(_nmicReportDate),
                    getPdfBytes: () => NmicReportPdfGenerator.generateDailyProductionReport(
                      date: _nmicReportDate,
                      requests: _allRequests,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A8A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
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
            border: Border.all(color: Colors.grey.shade200),
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
            border: Border.all(color: Colors.grey.shade200),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Action Bar
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Meat Dealer Licensing – Monthly Log', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
                    const SizedBox(height: 4),
                    Text('Tabaco City Abattoir Office 31-Day Production Matrix • $monthStr', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() => _monthlyLogMonth = DateTime(_monthlyLogMonth.year, _monthlyLogMonth.month - 1)),
              ),
              Text(monthStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(() => _monthlyLogMonth = DateTime(_monthlyLogMonth.year, _monthlyLogMonth.month + 1)),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.print, size: 16),
                label: const Text('Export Landscape PDF'),
                onPressed: () async {
                  final pdfBytes = await NmicReportPdfGenerator.generateMonthlyDealerLog(
                    month: _monthlyLogMonth,
                    requests: _allRequests,
                  );
                  await Printing.layoutPdf(onLayout: (_) => pdfBytes);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D6A4F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.send_rounded, size: 16),
                label: const Text('Send to NMIC via Email'),
                onPressed: () {
                  _openNmicTransmittalDialog(
                    reportType: 'Monthly Dealer Log',
                    periodLabel: monthStr,
                    getPdfBytes: () => NmicReportPdfGenerator.generateMonthlyDealerLog(
                      month: _monthlyLogMonth,
                      requests: _allRequests,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A8A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        Row(
          children: [
            _buildKpiCard('Total Heads (Month)', '$totalMonthHeads heads', const Color(0xFF2D6A4F), Icons.pets),
            const SizedBox(width: 16),
            _buildKpiCard('Market Dealers', '${dealersService.marketDealers.length} registered', const Color(0xFF2B6CB0), Icons.storefront),
            const SizedBox(width: 16),
            _buildKpiCard('Barangay Dealers', '${dealersService.barangayDealers.length} registered', const Color(0xFFD69E2E), Icons.home_work),
            const SizedBox(width: 16),
            _buildKpiCard('Days Covered', '$daysInMonth days', const Color(0xFF805AD5), Icons.calendar_month),
          ],
        ),
        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Monthly Dealer 31-Day Tally Overview', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
                  Text('Showing all ${allDealers.length} registered dealers', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final availableWidth = constraints.maxWidth;
                  final tableWidth = max(1200.0, availableWidth);

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: tableWidth),
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                        columns: [
                          const DataColumn(label: Text('No.', style: TextStyle(fontWeight: FontWeight.bold))),
                          const DataColumn(label: Text('Name of Owner', style: TextStyle(fontWeight: FontWeight.bold))),
                          const DataColumn(label: Text('Mark', style: TextStyle(fontWeight: FontWeight.bold))),
                          const DataColumn(label: Text('Section', style: TextStyle(fontWeight: FontWeight.bold))),
                          ...List.generate(daysInMonth, (i) => DataColumn(label: Text('${i + 1}'))),
                        ],
                        rows: allDealers.take(20).map((d) {
                          return DataRow(cells: [
                            DataCell(Text('${d.dealerNumber}')),
                            DataCell(Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                            DataCell(Text(d.markings, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)))),
                            DataCell(Text(d.category.toUpperCase())),
                            ...List.generate(daysInMonth, (_) => const DataCell(Text('—'))),
                          ]);
                        }).toList(),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Center(
                child: Text('Preview showing top 20 rows. Click "Export Landscape PDF" to print the complete 31-day matrix.',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey.shade600)),
              ),
            ],
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
            border: Border.all(color: Colors.grey.shade200),
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
                        const Text('National Meat Inspection Service (NMIS) Regulatory Reports',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
                        const SizedBox(height: 4),
                        Text('Form No. NMIS-POSM-F-034 • Official Transmittal & Compliance Suite',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                    label: const Text('Export Selected NMIS Form'),
                    onPressed: () async {
                      Uint8List pdfBytes;
                      if (_selectedNmicFormType == 'Weekly Summary') {
                        pdfBytes = await NmicReportPdfGenerator.generateNmisWeeklySummary(
                          month: _monthlyLogMonth,
                          requests: _allRequests,
                        );
                      } else {
                        pdfBytes = await NmicReportPdfGenerator.generateNmisServiceTransactionReport(
                          month: _monthlyLogMonth,
                          species: _selectedNmicSpecies,
                          requests: _allRequests,
                        );
                      }
                      await Printing.layoutPdf(onLayout: (_) => pdfBytes);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2D6A4F),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Send Transmittal & Form to NMIC'),
                    onPressed: () {
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
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              // Filter selectors
              Row(
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
                  const SizedBox(width: 24),
                  if (_selectedNmicFormType == 'Species Transaction') ...[
                    const Text('Species: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(width: 8),
                    ...['HOG', 'CATTLE', 'CARABAO', 'GOAT'].map((sp) {
                      final isSel = _selectedNmicSpecies == sp;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(sp),
                          selected: isSel,
                          onSelected: (_) => setState(() => _selectedNmicSpecies = sp),
                          selectedColor: const Color(0xFF2D6A4F),
                          labelStyle: TextStyle(color: isSel ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      );
                    }),
                  ],
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
            border: Border.all(color: Colors.grey.shade200),
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
            border: Border.all(color: Colors.grey.shade200),
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

    // Filter requests by customer
    List<Map<String, dynamic>> filtered = _allRequests;
    if (_selectedCustomerFilter != null && _selectedCustomerFilter!.isNotEmpty) {
      final query = _selectedCustomerFilter!.toUpperCase().trim();
      filtered = filtered.where((r) {
        final name = (r['customer_name'] ?? r['owner_name'] ?? '').toString().toUpperCase().trim();
        final mark = (r['customer_marking'] ?? r['animal_tag'] ?? r['tag_id'] ?? '').toString().toUpperCase().trim();
        return name == query || mark == query || name.contains(query);
      }).toList();
    }

    // Filter by period
    final now = DateTime.now();
    if (_customerPeriodFilter == 'This Week') {
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      filtered = filtered.where((r) {
        final dt = DateTime.tryParse((r['scheduled_date'] ?? r['created_at']).toString());
        return dt != null && dt.isAfter(startOfWeek);
      }).toList();
    } else if (_customerPeriodFilter == 'This Month') {
      filtered = filtered.where((r) {
        final dt = DateTime.tryParse((r['scheduled_date'] ?? r['created_at']).toString());
        return dt != null && dt.year == now.year && dt.month == now.month;
      }).toList();
    } else if (_customerPeriodFilter == 'This Year') {
      filtered = filtered.where((r) {
        final dt = DateTime.tryParse((r['scheduled_date'] ?? r['created_at']).toString());
        return dt != null && dt.year == now.year;
      }).toList();
    }

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
        // Action Bar & Filters
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
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
                        const Text('Customer Slaughter Historical Audit Records',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
                        const SizedBox(height: 4),
                        Text('Individual dealer slaughter totals required for NMIC inspection audit',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                    label: const Text('Export Customer Record (PDF)'),
                    onPressed: () async {
                      if (_selectedCustomerFilter == null || _selectedCustomerFilter!.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please select a customer or dealer first')),
                        );
                        return;
                      }
                      final pdfBytes = await NmicReportPdfGenerator.generateCustomerSlaughterHistoryReport(
                        customerName: activeDealer?.name ?? _selectedCustomerFilter!,
                        marking: activeDealer?.markings ?? 'TAG',
                        periodLabel: _customerPeriodFilter,
                        requests: filtered,
                      );
                      await Printing.layoutPdf(onLayout: (_) => pdfBytes);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2D6A4F),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                children: [
                  // Customer selector
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
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
                  ),
                  const SizedBox(width: 16),
                  // Period selector
                  ...['This Week', 'This Month', 'This Year', 'All Time'].map((p) {
                    final isSel = _customerPeriodFilter == p;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(p),
                        selected: isSel,
                        onSelected: (_) => setState(() => _customerPeriodFilter = p),
                        selectedColor: const Color(0xFF2D6A4F),
                        labelStyle: TextStyle(color: isSel ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
                      ),
                    );
                  }),
                ],
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
            border: Border.all(color: Colors.grey.shade200),
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

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.mark_email_read_outlined, color: Color(0xFF1E3A8A)),
            const SizedBox(width: 10),
            const Text('Send Transmittal & Reports to NMIC', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 580,
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
                          'Sending official soft copy to NMIC. This fulfills the digital report requirement so only hard copies are required during weekly physical inspections.',
                          style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'NMIC Recipient Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: subjectCtrl,
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
                        child: Text('Attached: ${reportType.replaceAll(" ", "_")}_$periodLabel.pdf (Soft Copy)',
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Download Soft Copy PDF'),
            onPressed: () async {
              final bytes = await getPdfBytes();
              await Printing.sharePdf(bytes: bytes, filename: '${reportType.replaceAll(" ", "_")}_$periodLabel.pdf');
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Send to NMIC via Gmail'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2D6A4F), foregroundColor: Colors.white),
            onPressed: () async {
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

              await _sendViaGmail(
                recipient: recipient,
                subject: subject,
                body: body,
                reportType: reportType,
                periodLabel: periodLabel,
                getPdfBytes: getPdfBytes,
                messenger: messenger,
                navigator: navigator,
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _sendViaGmail({
    required String recipient,
    required String subject,
    required String body,
    required String reportType,
    required String periodLabel,
    required Future<Uint8List> Function() getPdfBytes,
    required ScaffoldMessengerState messenger,
    required NavigatorState navigator,
  }) async {
    final dealersService = RegularDealersService.instance;
    // 1. Download soft copy PDF so the user can easily attach it
    try {
      final bytes = await getPdfBytes();
      await Printing.sharePdf(bytes: bytes, filename: '${reportType.replaceAll(" ", "_")}_$periodLabel.pdf');
    } catch (_) {}

    // 2. Open Gmail Web in new tab with pre-filled fields
    final gmailUrl = 'https://mail.google.com/mail/?view=cm&fs=1'
        '&to=${Uri.encodeComponent(recipient)}'
        '&su=${Uri.encodeComponent(subject)}'
        '&body=${Uri.encodeComponent(body)}';

    try {
      await launchUrl(Uri.parse(gmailUrl), mode: LaunchMode.externalApplication);
    } catch (_) {}

    await dealersService.logNmicTransmission(
      reportType: reportType,
      periodLabel: periodLabel,
      recipientEmail: recipient,
      transmittalSubject: subject,
      transmittalBody: body,
    );

    final updatedList = await dealersService.getTransmissions();
    if (mounted) setState(() => _nmicTransmissionsList = updatedList);

    if (navigator.canPop()) {
      navigator.pop();
    }
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Opened Gmail Web! Attach the downloaded PDF report to complete sending.'),
        backgroundColor: Color(0xFF2D6A4F),
      ),
    );
  }

  Widget _buildKpiCard(String title, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 22),
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
          width: 480,
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
                    decoration: const InputDecoration(
                      hintText: '0912 345 6789',
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

                if (isEditing) {
                  final updated = editDealer.copyWith(
                    name: name.toUpperCase(),
                    markings: marking.toUpperCase(),
                    category: category,
                    phone: phone.isNotEmpty ? phone : null,
                    clearPhone: phone.isEmpty,
                  );
                  await dealersService.updateDealer(updated);
                } else {
                  await dealersService.addDealerManually(
                    name: name,
                    markings: marking,
                    category: category,
                    phone: phone.isNotEmpty ? phone : null,
                  );
                }

                if (mounted) setState(() {});
                navigator.pop();

                messenger.showSnackBar(
                  SnackBar(
                    content: Text(isEditing ? 'Dealer updated successfully!' : 'Meat Dealer $name registered successfully!'),
                    backgroundColor: const Color(0xFF2D6A4F),
                  ),
                );
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
              style: const TextStyle(fontSize: 14, color: Color(0xFF2D3748)),
            ),
            const SizedBox(height: 10),
            Text(
              dealer.isNew
                  ? 'This newly enrolled dealer will be permanently removed from the directory.'
                  : 'This regular dealer will be removed from the directory listing.',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await RegularDealersService.instance.deleteDealer(dealer.id);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed ${dealer.name} from Meat Dealers Directory'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Widget _buildMeatDealersDirectoryTab() {
    final dealersService = RegularDealersService.instance;
    final allDealers = dealersService.allDealers;
    final headsMap = _calcDealerLifetimeHeads();

    final filteredDealers = allDealers.where((d) {
      final q = _dealerSearchQuery.toLowerCase().trim();
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
            border: Border.all(color: Colors.grey.shade200),
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
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                    label: const Text('Export Directory (PDF)'),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        final bytes = await NmicReportPdfGenerator.generateDealersDirectoryPdf(
                          dealers: filteredDealers,
                          dealerHeadsCount: headsMap,
                        );
                        await Printing.sharePdf(bytes: bytes, filename: 'NMIS_Meat_Dealers_Directory.pdf');
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(content: Text('Failed to generate PDF: $e'), backgroundColor: Colors.redAccent),
                        );
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2D6A4F),
                      side: const BorderSide(color: Color(0xFF2D6A4F)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(width: 10),
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

        // Filter & Search Controls
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
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
              DropdownButton<String>(
                value: _dealerCategoryFilter,
                items: const [
                  DropdownMenuItem(value: 'All', child: Text('All Dealers')),
                  DropdownMenuItem(value: 'Market', child: Text('Market Dealers')),
                  DropdownMenuItem(value: 'Barangay', child: Text('Barangay Dealers')),
                  DropdownMenuItem(value: 'New', child: Text('New Dealers (30 Days)')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _dealerCategoryFilter = v);
                },
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
            border: Border.all(color: Colors.grey.shade200),
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
                  final availableWidth = constraints.maxWidth;
                  final tableWidth = max(900.0, availableWidth);
                  final colSpacing = (availableWidth > 1400)
                      ? 34.0
                      : (availableWidth > 1100 ? 26.0 : 18.0);

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: tableWidth),
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                        columnSpacing: colSpacing,
                        columns: const [
                          DataColumn(label: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Meat Dealer Name', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Permanent Marking', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Category', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Contact', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Lifetime Heads', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Status / Badge', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: filteredDealers.asMap().entries.map((entry) {
                          final idx = entry.key + 1;
                          final d = entry.value;
                          final heads = headsMap[d.name.toLowerCase().trim()] ?? 0;

                          return DataRow(cells: [
                            DataCell(Text(idx.toString(), style: const TextStyle(fontSize: 12, color: Colors.grey))),
                            DataCell(
                              Text(
                                d.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF2D3748)),
                              ),
                            ),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE6F9F0),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF2D6A4F).withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  d.markings,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF2D6A4F)),
                                ),
                              ),
                            ),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: d.category == 'market' ? const Color(0xFFEBF8FF) : const Color(0xFFFEFCBF),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  d.category == 'market' ? 'Market' : 'Barangay',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: d.category == 'market' ? const Color(0xFF2B6CB0) : const Color(0xFFB7791F),
                                  ),
                                ),
                              ),
                            ),
                            DataCell(Text(d.phone != null && d.phone!.isNotEmpty ? d.phone! : '—', style: const TextStyle(fontSize: 12))),
                            DataCell(
                              Row(
                                children: [
                                  const Icon(Icons.pets, size: 14, color: Color(0xFF2D6A4F)),
                                  const SizedBox(width: 4),
                                  Text('$heads heads', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            DataCell(
                              Row(
                                children: [
                                  if (d.isNew)
                                    Container(
                                      margin: const EdgeInsets.only(right: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDEF7EC),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: const Color(0xFF31C48D)),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.star, size: 11, color: Color(0xFF046C4E)),
                                          SizedBox(width: 2),
                                          Text('New Dealer', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF046C4E))),
                                        ],
                                      ),
                                    ),
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: d.isActive ? Colors.green : Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(d.isActive ? 'Active' : 'Inactive', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  OutlinedButton(
                                    onPressed: () => _openRegisterDealerDialog(editDealer: d),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      minimumSize: const Size(0, 30),
                                    ),
                                    child: const Text('Edit', style: TextStyle(fontSize: 11)),
                                  ),
                                  const SizedBox(width: 6),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                    tooltip: 'Remove Dealer',
                                    splashRadius: 18,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                    onPressed: () => _confirmDeleteDealer(d),
                                  ),
                                ],
                              ),
                            ),
                          ]);
                        }).toList(),
                      ),
                    ),
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
class _DonutChartPainter extends CustomPainter {
  final List<int> values;
  final List<Color> colors;

  _DonutChartPainter({required this.values, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold(0, (a, b) => a + b);
    if (total == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;
    final strokeWidth = radius * 0.45;
    final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    double startAngle = -pi / 2;
    for (int i = 0; i < values.length; i++) {
      final sweepAngle = (values[i] / total) * 2 * pi;
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.colors != colors;
  }
}

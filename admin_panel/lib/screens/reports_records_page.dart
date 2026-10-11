import 'dart:async';
import 'dart:math';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import 'illegal_slaughter_reports_view.dart';
import '../services/report_pdf_generator.dart';

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

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab ?? 'Analytics';
    _loadData();
    _loadIllegalReportAlerts();
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
          const SizedBox(width: 12),
          IconButton(
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_forward, size: 26),
            color: const Color(0xFF2D3748),
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
    return Row(
      children: [
        _tabButton('Analytics', _activeTab == 'Analytics'),
        const SizedBox(width: 8),
        _tabButton(
          'Report Illegal',
          _activeTab == 'Report Illegal',
          badgeCount: _unreviewedIllegalReports,
        ),
      ],
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
            Scrollbar(
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
                    constraints: const BoxConstraints(minWidth: 1050),
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(const Color(0xFFF7FAFC)),
                      dataRowMinHeight: 52,
                      dataRowMaxHeight: 68,
                      columnSpacing: 22,
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
            Scrollbar(
              controller: scrollController,
              thumbVisibility: false,
              trackVisibility: false,
              child: SingleChildScrollView(
                controller: scrollController,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 1050),
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFFFF5F5)),
                    dataRowMinHeight: 52,
                    dataRowMaxHeight: 70,
                    columnSpacing: 22,
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
            Scrollbar(
              controller: scrollController,
              thumbVisibility: false,
              trackVisibility: false,
              child: SingleChildScrollView(
                controller: scrollController,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 1050),
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFEDF2F7)),
                    dataRowMinHeight: 52,
                    dataRowMaxHeight: 68,
                    columnSpacing: 22,
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

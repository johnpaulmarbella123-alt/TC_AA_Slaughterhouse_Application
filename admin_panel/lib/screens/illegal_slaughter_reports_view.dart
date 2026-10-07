import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/illegal_slaughter_pdf_generator.dart';

class IllegalSlaughterReportsView extends StatefulWidget {
  final VoidCallback? onReportsUpdated;
  const IllegalSlaughterReportsView({super.key, this.onReportsUpdated});

  @override
  State<IllegalSlaughterReportsView> createState() => _IllegalSlaughterReportsViewState();
}

class _IllegalSlaughterReportsViewState extends State<IllegalSlaughterReportsView> {
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  Timer? _pollingTimer;
  List<Map<String, dynamic>> _reports = [];

  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadReports();
    // Auto-poll every 4 seconds to sync updates in real-time
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _loadReports(silent: true);
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  int get _pendingCount => _reports.where((r) {
        final s = normalizeStatus(r['status']);
        return s == 'Pending Review';
      }).length;

  // ═══════════════════════════════════════════════════════════
  // STATUS NORMALIZATION & BADGE HELPERS
  // ═══════════════════════════════════════════════════════════
  static String normalizeStatus(String? rawStatus) {
    if (rawStatus == null || rawStatus.trim().isEmpty) return 'Pending Review';
    final s = rawStatus.trim().toLowerCase();
    if (s == 'pending' || s == 'unreviewed' || s == 'submitted' || s == 'new' ||
        s == 'pending review' || s == 'pending_review' || s == 'under review' ||
        s == 'under_review') {
      return 'Pending Review';
    }
    if (s == 'acknowledged' || s == 'verified' || s == 'validated') {
      return 'Acknowledged';
    }
    if (s == 'investigating' || s == 'under investigation' ||
        s == 'under_investigation' || s == 'inspection' || s == 'dispatched') {
      return 'Investigating';
    }
    if (s == 'report compiled' || s == 'report_compiled' || s == 'compiled' ||
        s == 'filed' || s == 'resolved' || s == 'closed' || s == 'completed' ||
        s == 'endorsed' || s == 'action taken' || s == 'action_taken') {
      return 'Report Compiled';
    }
    return rawStatus;
  }

  static Color getStatusBgColor(String status) {
    switch (normalizeStatus(status)) {
      case 'Pending Review':
        return const Color(0xFFFEF3C7); // Warm light yellow
      case 'Acknowledged':
        return const Color(0xFFDBEAFE); // Soft sky blue
      case 'Investigating':
        return const Color(0xFFFCE7F3); // Soft pink / lavender
      case 'Report Compiled':
        return const Color(0xFFD1FAE5); // Mint green
      default:
        return const Color(0xFFF1F5F9);
    }
  }

  static Color getStatusTextColor(String status) {
    switch (normalizeStatus(status)) {
      case 'Pending Review':
        return const Color(0xFFB45309); // Amber brown
      case 'Acknowledged':
        return const Color(0xFF1D4ED8); // Royal blue
      case 'Investigating':
        return const Color(0xFFC026D3); // Magenta / pink-purple
      case 'Report Compiled':
        return const Color(0xFF059669); // Forest mint green
      default:
        return const Color(0xFF475569);
    }
  }

  static String formatTableDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'No date';
    try {
      final dt = DateTime.parse(raw).toLocal();
      if (raw.length == 10 && !raw.contains('T')) {
        return DateFormat('MMM d, yyyy').format(dt);
      }
      return DateFormat('MMM d, yyyy h:mm a').format(dt);
    } catch (_) {
      return raw;
    }
  }

  static String formatDetailDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'No date';
    try {
      final dt = DateTime.parse(raw).toLocal();
      if (raw.length == 10 && !raw.contains('T')) {
        return DateFormat('MMMM d, yyyy').format(dt);
      }
      return DateFormat('MMMM d, yyyy - h:mm a').format(dt);
    } catch (_) {
      return raw;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // DATA FETCHING
  // ═══════════════════════════════════════════════════════════
  Future<void> _loadReports({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);

    try {
      final List<Map<String, dynamic>> loaded = [];

      // 1. Fetch genuine filed records from 'reports' table in Supabase
      try {
        final reportsData = await supabase.from('reports').select();
        for (var r in (reportsData as List)) {
          final m = Map<String, dynamic>.from(r);
          final idStr = m['id']?.toString() ?? '';
          final shortId = idStr.length >= 8 ? idStr.substring(0, 8).toUpperCase() : idStr.toUpperCase();
          final year = (m['incident_date'] ?? '2026').toString().split('-').first;

          m['reference_no'] = m['reference_no'] ?? 'RPT-$year-$shortId';
          m['source'] = m['source'] ?? 'Mobile App';
          m['status'] = normalizeStatus(m['status']?.toString() ?? 'Pending Review');
          m['created_at'] = m['created_at'] ?? m['incident_date'] ?? DateTime.now().toIso8601String();
          final isAnon = m['is_anonymous'] == true;
          m['reporter_name'] = isAnon ? 'Anonymous' : (m['reporter_name'] ?? 'Citizen');
          loaded.add(m);
        }
      } catch (e) {
        debugPrint('Reports table fetch error: $e');
      }

      // 2. Fetch notifications table to merge workflow updates or add mobile reports
      try {
        final notifData = await supabase
            .from('notifications')
            .select()
            .inFilter('type', [
              'admin_illegal_report',
              'report_filed',
              'report_investigating',
              'report_status_update',
              'report_resolved',
            ])
            .order('created_at', ascending: true);

        for (var n in (notifData as List)) {
          final data = n['data'] is Map ? Map<String, dynamic>.from(n['data']) : <String, dynamic>{};
          String refNo = n['reference_no']?.toString() ?? data['reference_no']?.toString() ?? '';
          if (refNo.isEmpty) {
            final idStr = (data['report_id'] ?? n['id'] ?? '').toString();
            if (idStr.isNotEmpty) {
              final shortId = idStr.length >= 8 ? idStr.substring(0, 8).toUpperCase() : idStr.toUpperCase();
              final year = (data['incident_date'] ?? '2026').toString().split('-').first;
              refNo = 'RPT-$year-$shortId';
            }
          }
          if (refNo.isEmpty) continue;
          if (refNo.startsWith('REP-2024') || refNo.startsWith('ISR-2024')) continue;

          final existingIdx = loaded.indexWhere((item) {
            final itemRef = (item['reference_no'] ?? '').toString();
            final itemId = (item['id'] ?? '').toString();
            final nReportId = (data['report_id'] ?? '').toString();
            if (itemRef.isNotEmpty && refNo.isNotEmpty && itemRef == refNo) return true;
            if (itemId.isNotEmpty && nReportId.isNotEmpty && itemId == nReportId) return true;
            if (itemId.length >= 8 && refNo.contains(itemId.substring(0, 8).toUpperCase())) return true;
            if (nReportId.length >= 8 && itemRef.contains(nReportId.substring(0, 8).toUpperCase())) return true;
            return false;
          });

          if (existingIdx >= 0) {
            final current = loaded[existingIdx];
            if (data['status'] != null) current['status'] = normalizeStatus(data['status'].toString());
            if (data['assigned_to'] != null) current['assigned_to'] = data['assigned_to'];
            if (data['findings'] != null) current['findings'] = data['findings'];
            if (data['endorsed_to'] != null) current['endorsed_to'] = data['endorsed_to'];
            if (data['resolved_at'] != null) current['resolved_at'] = data['resolved_at'];
            if (data['location'] != null && (current['location'] == null || current['location'] == 'Tabaco City' || current['location'] == '')) {
              current['location'] = data['location'];
            }
            if (data['description'] != null && (current['description'] == null || current['description'] == '')) {
              current['description'] = data['description'];
            }
            if (data['photo_url'] != null && (current['photo_url'] == null || current['photo_url'] == '')) {
              current['photo_url'] = data['photo_url'];
            }
            if (data['reporter_name'] != null && (current['reporter_name'] == null || current['reporter_name'] == 'Citizen')) {
              current['reporter_name'] = data['reporter_name'];
            }
            if (data['contact_number'] != null && current['contact_number'] == null) {
              current['contact_number'] = data['contact_number'];
            }
            current['notification_id'] = n['id'];
          } else {
            // Report from mobile notification not yet in loaded list (e.g. RLS on reports table)
            final isAnon = data['is_anonymous'] == true || n['is_anonymous'] == true;
            loaded.add({
              'id': data['report_id'] ?? n['id'],
              'reference_no': refNo,
              'user_id': isAnon ? null : (data['user_id'] ?? n['user_id']),
              'location': (data['location'] != null && data['location'].toString().trim().isNotEmpty)
                  ? data['location'].toString().trim()
                  : 'Tabaco City',
              'incident_date': data['incident_date']?.toString() ?? n['created_at']?.toString() ?? DateTime.now().toIso8601String(),
              'description': (data['description'] != null && data['description'].toString().trim().isNotEmpty)
                  ? data['description'].toString().trim()
                  : (n['message']?.toString() ?? ''),
              'photo_url': data['photo_url']?.toString(),
              'is_anonymous': isAnon,
              'reporter_name': isAnon
                  ? 'Anonymous'
                  : ((data['reporter_name'] != null && data['reporter_name'].toString().trim().isNotEmpty)
                      ? data['reporter_name'].toString().trim()
                      : 'Citizen'),
              'contact_number': isAnon ? null : data['contact_number']?.toString(),
              'status': normalizeStatus(data['status']?.toString() ?? 'Pending Review'),
              'priority': data['priority']?.toString() ?? 'High',
              'assigned_to': data['assigned_to']?.toString(),
              'findings': data['findings']?.toString(),
              'endorsed_to': data['endorsed_to']?.toString(),
              'resolved_at': data['resolved_at']?.toString(),
              'created_at': data['created_at']?.toString() ?? n['created_at']?.toString() ?? DateTime.now().toIso8601String(),
              'source': 'Mobile App',
              'notification_id': n['id'],
            });
          }
        }
      } catch (e) {
        debugPrint('Notifications table fetch note: $e');
      }

      // 3. Sort by incident date descending
      loaded.sort((a, b) {
        final da = a['incident_date']?.toString() ?? a['created_at']?.toString() ?? '';
        final db = b['incident_date']?.toString() ?? b['created_at']?.toString() ?? '';
        return db.compareTo(da);
      });

      // 4. Exclude any mock items
      loaded.removeWhere((item) {
        final ref = (item['reference_no'] ?? '').toString();
        return ref.startsWith('REP-2024') || ref.startsWith('ISR-2024');
      });

      if (mounted) {
        setState(() {
          _reports = loaded;
          _isLoading = false;
        });
        widget.onReportsUpdated?.call();
      }
    } catch (e) {
      debugPrint('Error loading illegal slaughter reports: $e');
      if (mounted && !silent) setState(() => _isLoading = false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // CENTER POPUP MODAL WITH BLURRED BACKDROP
  // ═══════════════════════════════════════════════════════════
  void _openReportCenterModal(Map<String, dynamic> report) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close Report Action Dialog',
      barrierColor: Colors.black.withValues(alpha: 0.38),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogCtx, anim1, anim2) {
        return Center(
          child: _ReportActionCenterModal(
            initialReport: report,
            supabase: supabase,
            onReportUpdated: () {
              _loadReports(silent: true);
              widget.onReportsUpdated?.call();
            },
          ),
        );
      },
      transitionBuilder: (dialogCtx, anim1, anim2, child) {
        final curvedVal = CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic).value;
        return BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 5.5 * curvedVal,
            sigmaY: 5.5 * curvedVal,
          ),
          child: FadeTransition(
            opacity: anim1,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1.0).animate(
                CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  // MAIN BUILD
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    // Filter reports based on search
    final query = _searchCtrl.text.trim().toLowerCase();
    final filteredReports = _reports.where((r) {
      if (query.isEmpty) return true;
      final ref = (r['reference_no'] ?? '').toString().toLowerCase();
      final loc = (r['location'] ?? '').toString().toLowerCase();
      final rep = (r['reporter_name'] ?? '').toString().toLowerCase();
      final desc = (r['description'] ?? '').toString().toLowerCase();
      final stat = (r['status'] ?? '').toString().toLowerCase();
      return ref.contains(query) ||
          loc.contains(query) ||
          rep.contains(query) ||
          desc.contains(query) ||
          stat.contains(query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top App Bar row with Warning icon + Title & Search
        _buildTopBar(),
        const SizedBox(height: 28),

        // Incoming Mobile Reports sub-header with real-time pending alert badge
        _buildSubHeader(),
        const SizedBox(height: 18),

        // Clean Full-Width Table Card
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(60),
              child: CircularProgressIndicator(color: Color(0xFF0F172A)),
            ),
          )
        else
          _buildReportsTableCard(filteredReports),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TOP APP BAR (Icon + Title + Search bar)
  // ═══════════════════════════════════════════════════════════
  Widget _buildTopBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Red warning icon + Illegal Slaughter Reports
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFEF4444), // Coral Red Hazard
                size: 26,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Illegal Slaughter Reports',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),

        // Search Input (matching top-right search box)
        Container(
          width: 280,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              prefixIcon: const Icon(
                Icons.search,
                size: 18,
                color: Color(0xFF94A3B8),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 18),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16, color: Color(0xFF94A3B8)),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {});
                      },
                    )
                  : null,
              hintText: 'Search reports...',
              hintStyle: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
              border: InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // SUB-HEADER
  // ═══════════════════════════════════════════════════════════
  Widget _buildSubHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Incoming Mobile Reports',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            if (_pendingCount > 0) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.notifications_active, size: 11, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      '$_pendingCount New Tip${_pendingCount > 1 ? 's' : ''}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Manage and investigate hot meat tips submitted by customers.',
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // TABLE CARD (Matching user's Screenshot 1)
  // ═══════════════════════════════════════════════════════════
  Widget _buildReportsTableCard(List<Map<String, dynamic>> reports) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Report ID / Date',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Text(
                    'Location',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Reporter',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Status',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
                SizedBox(
                  width: 50,
                  child: Text(
                    'Action',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Table Rows
          if (reports.isEmpty)
            Padding(
              padding: const EdgeInsets.all(48),
              child: Column(
                children: const [
                  Icon(Icons.inbox_outlined, size: 40, color: Color(0xFF94A3B8)),
                  SizedBox(height: 12),
                  Text(
                    'No reports found',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Try adjusting your search criteria or wait for incoming citizen tips.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: reports.length,
              separatorBuilder: (context, index) => const Divider(
                height: 1,
                thickness: 1,
                color: Color(0xFFF1F5F9),
              ),
              itemBuilder: (context, index) {
                final report = reports[index];
                return _buildTableRow(report);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTableRow(Map<String, dynamic> report) {
    final ref = report['reference_no'] ?? 'REP-UNKNOWN';
    final dateStr = formatTableDate(report['incident_date'] ?? report['created_at']);
    final location = report['location'] ?? 'Location not specified';
    final isAnon = report['is_anonymous'] == true || report['reporter_name'] == 'Anonymous';
    final reporterName = isAnon ? 'Anonymous' : (report['reporter_name'] ?? 'Citizen');
    final status = normalizeStatus(report['status']);

    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: () => _openReportCenterModal(report),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        color: Colors.white,
        child: Row(
          children: [
            // Column 1: Report ID / Date
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ref,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time_outlined,
                        size: 13,
                        color: Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        dateStr,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Column 2: Location
            Expanded(
              flex: 4,
              child: Text(
                location,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF334155),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            // Column 3: Reporter
            Expanded(
              flex: 2,
              child: Text(
                reporterName,
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: isAnon ? FontStyle.italic : FontStyle.normal,
                  color: isAnon ? const Color(0xFF94A3B8) : const Color(0xFF334155),
                  fontWeight: isAnon ? FontWeight.w400 : FontWeight.w500,
                ),
              ),
            ),

            // Column 4: Status (Pill Badge)
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: getStatusBgColor(status),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: getStatusTextColor(status),
                    ),
                  ),
                ),
              ),
            ),

            // Column 5: Action (Arrow button)
            SizedBox(
              width: 50,
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: const Icon(
                    Icons.arrow_forward,
                    size: 18,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// REPORT ACTION CENTER MODAL (CENTER POPUP WITH BLURRED BG)
// ═══════════════════════════════════════════════════════════
class _ReportActionCenterModal extends StatefulWidget {
  final Map<String, dynamic> initialReport;
  final SupabaseClient supabase;
  final VoidCallback onReportUpdated;

  const _ReportActionCenterModal({
    required this.initialReport,
    required this.supabase,
    required this.onReportUpdated,
  });

  @override
  State<_ReportActionCenterModal> createState() => _ReportActionCenterModalState();
}

class _ReportActionCenterModalState extends State<_ReportActionCenterModal> {
  late Map<String, dynamic> _report;
  final TextEditingController _findingsCtrl = TextEditingController();
  String _selectedAgency = 'NMIS (National Meat Inspection Service)';
  bool _isSubmittingAction = false;
  bool _isEditingCompiled = false;
  bool _isExportingPdf = false;

  final List<String> _agencyOptions = [
    'NMIS (National Meat Inspection Service)',
    'City Veterinary Office',
    'Philippine National Police (PNP)',
    'Barangay Captain / Local Officials',
    'City Legal Office',
  ];

  @override
  void initState() {
    super.initState();
    _report = Map<String, dynamic>.from(widget.initialReport);
    _findingsCtrl.text = _report['findings'] ?? '';
    if (_report['endorsed_to'] != null && _agencyOptions.contains(_report['endorsed_to'])) {
      _selectedAgency = _report['endorsed_to'];
    }
  }

  @override
  void dispose() {
    _findingsCtrl.dispose();
    super.dispose();
  }

  Future<void> _updateStatus(
    String newStatus, {
    String? findings,
    String? endorsedTo,
  }) async {
    final ref = _report['reference_no'] ?? 'Report';
    final isAnon = _report['is_anonymous'] == true;
    final userId = _report['user_id'];

    setState(() => _isSubmittingAction = true);

    // Optimistically update
    setState(() {
      _report['status'] = newStatus;
      if (findings != null) _report['findings'] = findings;
      if (endorsedTo != null) _report['endorsed_to'] = endorsedTo;
      if (newStatus == 'Report Compiled') {
        _report['resolved_at'] = DateTime.now().toIso8601String();
      }
    });

    try {
      final updateData = <String, dynamic>{
        'status': newStatus,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (findings != null) updateData['findings'] = findings;
      if (endorsedTo != null) updateData['endorsed_to'] = endorsedTo;
      if (newStatus == 'Report Compiled') {
        updateData['resolved_at'] = DateTime.now().toIso8601String();
      }

      // 1. Update reports table
      try {
        final rId = _report['id']?.toString() ?? _report['report_id']?.toString();
        final repUpdate = <String, dynamic>{
          'status': newStatus,
          if (ref.isNotEmpty && ref != 'Report') 'reference_no': ref,
        };
        if (rId != null && rId.length > 10) {
          try {
            await widget.supabase.from('reports').update(repUpdate).eq('id', rId);
          } catch (_) {}
        }
        if (ref.isNotEmpty && ref != 'Report') {
          try {
            await widget.supabase.from('reports').update(repUpdate).eq('reference_no', ref);
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('Reports table update fallback: $e');
      }

      // 2. Mark and update ALL notifications matching reference_no as read and updated
      try {
        await widget.supabase.from('notifications').update({
          'is_read': true,
          'data': {
            ..._report,
            ...updateData,
          },
        }).eq('reference_no', ref);
      } catch (_) {}

      try {
        final notifId = _report['notification_id'];
        if (notifId != null) {
          await widget.supabase.from('notifications').update({
            'is_read': true,
            'data': {
              ..._report,
              ...updateData,
            },
          }).eq('id', notifId);
        }
      } catch (_) {}

      // 3. Dispatch status update notification for citizen whistleblowers
      try {
        String msg = '';
        if (newStatus == 'Acknowledged') {
          msg = 'Your hot meat tip ($ref) has been officially acknowledged by the City Slaughterhouse administration.';
        } else if (newStatus == 'Investigating') {
          msg = 'An on-site inspection team has been dispatched to investigate report ($ref).';
        } else if (newStatus == 'Report Compiled') {
          msg = 'Investigation findings have been documented and officially endorsed to $endorsedTo.';
        }

        await widget.supabase.from('notifications').insert({
          if (!isAnon && userId != null) 'user_id': userId,
          'title': '🚨 Illegal Slaughter Status: $newStatus',
          'message': msg,
          'is_read': false,
          'type': 'report_status_update',
          'reference_no': ref,
          'data': {
            'reference_no': ref,
            'status': newStatus,
            'updated_at': DateTime.now().toIso8601String(),
            if (findings != null) 'findings': findings,
            if (endorsedTo != null) 'endorsed_to': endorsedTo,
          },
        });
      } catch (e) {
        debugPrint('Notification broadcast note: $e');
      }

      widget.onReportUpdated();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Report $ref updated to "$newStatus"!'),
            backgroundColor: _IllegalSlaughterReportsViewState.getStatusTextColor(newStatus),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error transitioning status: $e');
    } finally {
      if (mounted) setState(() => _isSubmittingAction = false);
    }
  }

  Future<void> _exportPdfReport() async {
    setState(() => _isExportingPdf = true);
    try {
      final pdfBytes = await IllegalSlaughterPdfGenerator.generate(report: _report);
      final ref = _report['reference_no'] ?? 'Report';
      await Printing.layoutPdf(
        name: 'Illegal_Slaughter_Report_$ref.pdf',
        onLayout: (format) async => pdfBytes,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating PDF: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }

  void _confirmDeleteReport() {
    final ref = _report['reference_no'] ?? 'Report';
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Report?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
        content: Text('Are you sure you want to permanently delete report $ref? This will remove it from the database.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.of(dCtx).pop();
              try {
                final rId = _report['id']?.toString() ?? _report['report_id']?.toString();
                if (rId != null && rId.length > 10) {
                  try {
                    await widget.supabase.from('reports').delete().eq('id', rId);
                  } catch (_) {}
                }
                await widget.supabase.from('reports').delete().eq('reference_no', ref);
                await widget.supabase.from('notifications').delete().eq('reference_no', ref);
                final notifId = _report['notification_id'];
                if (notifId != null) {
                  await widget.supabase.from('notifications').delete().eq('id', notifId);
                }
              } catch (_) {}
              widget.onReportUpdated();
              if (mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Report $ref has been deleted.'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ref = _report['reference_no'] ?? 'REP-UNKNOWN';
    final status = _IllegalSlaughterReportsViewState.normalizeStatus(_report['status']);
    final dateFormatted = _IllegalSlaughterReportsViewState.formatDetailDate(
      _report['incident_date'] ?? _report['created_at'],
    );
    final location = _report['location'] ?? 'Location not specified';
    final description = _report['description'] ?? 'No description provided.';
    final isAnon = _report['is_anonymous'] == true || _report['reporter_name'] == 'Anonymous';
    final reporterName = isAnon ? 'Anonymous Submission' : (_report['reporter_name'] ?? 'Citizen');
    final contactNum = _report['contact_number'];
    final photoUrl = _report['photo_url']?.toString();

    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth < 620 ? screenWidth * 0.94 : 560.0;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Modal Header: [REP-2024-001] [Status Pill]  ...... [Delete] [✕] ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              child: Row(
                children: [
                  Text(
                    ref,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: _IllegalSlaughterReportsViewState.getStatusBgColor(status),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _IllegalSlaughterReportsViewState.getStatusTextColor(status),
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFEF4444)),
                    tooltip: 'Delete Report',
                    splashRadius: 18,
                    onPressed: _confirmDeleteReport,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                    splashRadius: 18,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),

            // ── Modal Body (Scrollable) ──
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // SECTION 1: SUBMISSION DETAILS
                    const Text(
                      'SUBMISSION DETAILS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Evidence Image Container
                    _buildEvidenceBox(photoUrl),
                    const SizedBox(height: 14),

                    // Incident Details Card (Date, Location, Description, Reporter)
                    _buildIncidentCard(
                      dateFormatted: dateFormatted,
                      location: location,
                      description: description,
                      isAnon: isAnon,
                      reporterName: reporterName,
                      contactNum: contactNum,
                    ),
                    const SizedBox(height: 24),

                    // SECTION 2: ADMIN WORKFLOW
                    const Text(
                      'ADMIN WORKFLOW',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 3-Step Guided Stepper
                    _buildStepper(status),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // EVIDENCE BOX
  // ═══════════════════════════════════════════════════════════
  Widget _buildEvidenceBox(String? photoUrl) {
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return Container(
        height: 190,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              photoUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildPlaceholderEvidence(),
            ),
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.photo_camera, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'Evidence Photo',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _buildPlaceholderEvidence();
  }

  Widget _buildPlaceholderEvidence() {
    return Container(
      height: 170,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.image_outlined, size: 16, color: Color(0xFF94A3B8)),
              SizedBox(width: 6),
              Text(
                'Evidence',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.photo_outlined, size: 36, color: Color(0xFFCBD5E1)),
                  SizedBox(height: 6),
                  Text(
                    'No photo evidence uploaded',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // INCIDENT DETAILS CARD
  // ═══════════════════════════════════════════════════════════
  Widget _buildIncidentCard({
    required String dateFormatted,
    required String location,
    required String description,
    required bool isAnon,
    required String reporterName,
    String? contactNum,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date & Time
          Row(
            children: const [
              Icon(Icons.access_time, size: 14, color: Color(0xFF64748B)),
              SizedBox(width: 6),
              Text(
                'Date & Time',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            dateFormatted,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 14),

          // Location
          Row(
            children: const [
              Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF64748B)),
              SizedBox(width: 6),
              Text(
                'Location',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            location,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 14),

          // Description
          const Text(
            'Description',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text(
              description,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF334155),
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 14),

          const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 12),

          // Reporter Information
          const Text(
            'Reporter Information',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                isAnon ? Icons.shield_outlined : Icons.person_outline,
                size: 16,
                color: const Color(0xFF64748B),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  reporterName + (contactNum != null && contactNum.isNotEmpty ? ' ($contactNum)' : ''),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 3-STEP ADMIN WORKFLOW STEPPER
  // ═══════════════════════════════════════════════════════════
  Widget _buildStepper(String currentStatus) {
    final isAcknowledged = currentStatus == 'Acknowledged' ||
        currentStatus == 'Investigating' ||
        currentStatus == 'Report Compiled';
    final isInvestigating = currentStatus == 'Investigating' || currentStatus == 'Report Compiled';
    final isCompiled = currentStatus == 'Report Compiled';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── STEP 1: Acknowledge Report ──
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStepCircle(
              isCompleted: isAcknowledged,
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '1. Acknowledge Report',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Mark this report as received by the admin team.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  if (currentStatus == 'Pending Review') ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 38,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A), // Dark Navy
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _isSubmittingAction
                            ? null
                            : () => _updateStatus('Acknowledged'),
                        child: _isSubmittingAction
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text(
                                'Acknowledge Now',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),

        // Connecting Line
        Padding(
          padding: const EdgeInsets.only(left: 11),
          child: Container(
            width: 2,
            height: currentStatus == 'Pending Review' ? 44 : 32,
            color: const Color(0xFFE2E8F0),
          ),
        ),

        // ── STEP 2: Start Investigation ──
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStepCircle(
              isCompleted: isInvestigating,
              color: const Color(0xFFD946EF), // Magenta
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '2. Start Investigation',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Assign inspectors to verify the claims on-site.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  if (currentStatus == 'Acknowledged') ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 38,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF000B8), // Bright Magenta
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _isSubmittingAction
                            ? null
                            : () => _updateStatus('Investigating'),
                        child: _isSubmittingAction
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text(
                                'Begin Investigation',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),

        // Connecting Line
        Padding(
          padding: const EdgeInsets.only(left: 11),
          child: Container(
            width: 2,
            height: currentStatus == 'Acknowledged' ? 44 : 32,
            color: const Color(0xFFE2E8F0),
          ),
        ),

        // ── STEP 3: Compile Formal Report ──
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStepCircle(
              isCompleted: isCompiled,
              color: const Color(0xFF10B981), // Mint / Green
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '3. Compile Formal Report',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Document findings and forward to authorities.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),

                  // If currently Investigating: Show input card + File button
                  if (currentStatus == 'Investigating') ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Investigation Findings',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF334155),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _findingsCtrl,
                            maxLines: 4,
                            style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
                            decoration: InputDecoration(
                              hintText: 'Enter details from the on-site visit...',
                              hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                              fillColor: Colors.white,
                              filled: true,
                              isDense: true,
                              contentPadding: const EdgeInsets.all(12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          const Text(
                            'Forward To',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF334155),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedAgency,
                                isExpanded: true,
                                icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF64748B)),
                                style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
                                items: _agencyOptions.map((agency) {
                                  return DropdownMenuItem<String>(
                                    value: agency,
                                    child: Text(agency),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _selectedAgency = val);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Complete & File Report Button
                          SizedBox(
                            width: double.infinity,
                            height: 42,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.assignment_turned_in_outlined, size: 18),
                              label: _isSubmittingAction
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text(
                                      'Complete & File Report',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF34D399), // Mint Green
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: _isSubmittingAction
                                  ? null
                                  : () {
                                      final findings = _findingsCtrl.text.trim();
                                      _updateStatus(
                                        'Report Compiled',
                                        findings: findings.isEmpty
                                            ? 'Investigation completed and verified on-site.'
                                            : findings,
                                        endorsedTo: _selectedAgency,
                                      );
                                    },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ── If Report Compiled: Show completed dossier card + ACTIONS ──
                  if (currentStatus == 'Report Compiled') ...[
                    const SizedBox(height: 14),
                    if (!_isEditingCompiled) ...[
                      // Summary Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: const [
                                Icon(Icons.check_circle, size: 18, color: Color(0xFF16A34A)),
                                SizedBox(width: 8),
                                Text(
                                  'Report Completed & Officially Filed',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF15803D),
                                  ),
                                ),
                              ],
                            ),
                            if (_report['findings'] != null && _report['findings'].toString().isNotEmpty) ...[
                              const SizedBox(height: 10),
                              const Text(
                                'Investigation Findings:',
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_report['findings']}',
                                style: const TextStyle(fontSize: 12.5, color: Color(0xFF1E293B), height: 1.35),
                              ),
                            ],
                            if (_report['endorsed_to'] != null) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Text(
                                    'Forwarded To: ',
                                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                                  ),
                                  Expanded(
                                    child: Text(
                                      '${_report['endorsed_to']}',
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF15803D),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Report Compiled ACTIONS ──
                      // 1. Primary Action: Print / Download Official PDF Report
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: ElevatedButton.icon(
                          icon: _isExportingPdf
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                          label: Text(
                            _isExportingPdf ? 'Preparing Document...' : 'Print / Export Official Dossier (PDF)',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A), // Dark navy
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: _isExportingPdf ? null : _exportPdfReport,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // 2. Secondary Actions: Edit Findings & Reopen Investigation
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.edit_note, size: 18),
                              label: const Text('Edit Findings', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF334155),
                                side: const BorderSide(color: Color(0xFFCBD5E1)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () {
                                setState(() {
                                  _findingsCtrl.text = _report['findings'] ?? '';
                                  _isEditingCompiled = true;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.refresh, size: 16, color: Color(0xFFC026D3)),
                              label: const Text('Reopen Case', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFFC026D3))),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFF0ABFC)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () {
                                _updateStatus('Investigating');
                              },
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      // ── Edit Mode for Compiled Report ──
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Edit Investigation Findings',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF334155),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _findingsCtrl,
                              maxLines: 4,
                              style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
                              decoration: InputDecoration(
                                hintText: 'Update findings from the case...',
                                fillColor: Colors.white,
                                filled: true,
                                isDense: true,
                                contentPadding: const EdgeInsets.all(12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Forward To',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF334155),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFCBD5E1)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedAgency,
                                  isExpanded: true,
                                  icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF64748B)),
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
                                  items: _agencyOptions.map((agency) {
                                    return DropdownMenuItem<String>(
                                      value: agency,
                                      child: Text(agency),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) setState(() => _selectedAgency = val);
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF10B981),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () {
                                      _updateStatus(
                                        'Report Compiled',
                                        findings: _findingsCtrl.text.trim(),
                                        endorsedTo: _selectedAgency,
                                      );
                                      setState(() => _isEditingCompiled = false);
                                    },
                                    child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () => setState(() => _isEditingCompiled = false),
                                  child: const Text('Cancel'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStepCircle({
    required bool isCompleted,
    required Color color,
  }) {
    if (isCompleted) {
      return Icon(
        Icons.check_circle_outline,
        color: color,
        size: 24,
      );
    }
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFCBD5E1), width: 2),
      ),
    );
  }
}

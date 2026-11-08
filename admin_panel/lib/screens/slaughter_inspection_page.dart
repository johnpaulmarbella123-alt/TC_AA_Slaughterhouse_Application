import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../services/notification_service.dart';
import '../services/inspection_documents_pdf_generator.dart';
import '../services/app_settings_service.dart';

class SlaughterInspectionPage extends StatefulWidget {
  const SlaughterInspectionPage({super.key});
  @override
  State<SlaughterInspectionPage> createState() => _SlaughterInspectionPageState();
}

class _SlaughterInspectionPageState extends State<SlaughterInspectionPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _barangayRequests = [];
  List<Map<String, dynamic>> _marketRequests = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _filterStage = 'All';
  Timer? _pollingTimer;
  RealtimeChannel? _realtimeChannel;
  final Set<String> _shownAnteMortemAlertIds = {};

  @override
  void initState() {
    super.initState();
    _loadRequests();
    _subscribeRealtime();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAnteMortemAlerts();
    });
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        _loadRequests(silent: true);
        _checkAnteMortemAlerts();
      }
    });
  }

  void _subscribeRealtime() {
    try {
      _realtimeChannel = supabase.channel('public:slaughter_inspection_realtime')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'requests',
          callback: (payload) {
            if (mounted) _loadRequests(silent: true);
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'slaughter_inspection',
          callback: (payload) {
            if (mounted) _loadRequests(silent: true);
          },
        )
        ..subscribe();
    } catch (e) {
      debugPrint('Realtime subscription error in SlaughterInspection: $e');
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    if (_realtimeChannel != null) {
      supabase.removeChannel(_realtimeChannel!);
    }
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      if (AppSettingsService.instance.hasActiveStaffSession ||
          supabase.auth.currentSession == null) {
        await AppSettingsService.instance.ensureAdminAuthSession();
      }
      // Fetch requests that are past Document Verification (doc_verified) or in slaughter phases.
      final data = await supabase
          .from('requests')
          .select('*, slaughter_inspection(*)')
          .inFilter('status', ['doc_verified', 'slaughter_started', 'releasable', 'delay_error', 'completed', 'anti_mortem_failed', 'pickup_scheduled', 'taken_back', 'post_mortem_failed', 'condemned', 'mic_generated'])
          .order('created_at', ascending: false);

      // Seamlessly sync response from system_settings ante_mortem_alerts & pickup_penalty_tracking
      Map<String, dynamic> alerts = {};
      Map<String, dynamic> trackingMap = {};
      try {
        final settingsRows = await supabase
            .from('system_settings')
            .select('key, value')
            .inFilter('key', ['ante_mortem_alerts', 'pickup_penalty_tracking']);
        for (final row in List<Map<String, dynamic>>.from(settingsRows)) {
          if (row['key'] == 'ante_mortem_alerts' && row['value'] is Map) {
            alerts = Map<String, dynamic>.from(row['value']);
          } else if (row['key'] == 'pickup_penalty_tracking' && row['value'] is Map) {
            trackingMap = Map<String, dynamic>.from(row['value']);
          }
        }
      } catch (_) {}
      
      final activeRequests = List<Map<String, dynamic>>.from(data).map((r) {
        final idStr = r['id'].toString();
        if (alerts.containsKey(idStr) && alerts[idStr] is Map) {
          final alertChoice = alerts[idStr]['choice']?.toString();
          if (alertChoice != null && alertChoice.isNotEmpty) {
            if (r['anti_mortem_response'] == null || r['anti_mortem_response'].toString().isEmpty) {
              r['anti_mortem_response'] = alertChoice;
              r['anti_mortem_response_at'] = alerts[idStr]['responded_at'];
              supabase.from('requests').update({
                'anti_mortem_response': alertChoice,
                'anti_mortem_response_at': alerts[idStr]['responded_at'] ?? DateTime.now().toIso8601String(),
              }).eq('id', r['id']).then((_) {}).catchError((_) {});
            }
          }
        }

        final inspectionList = r['slaughter_inspection'];
        Map<String, dynamic>? inspection;
        if (inspectionList is List && inspectionList.isNotEmpty) {
          inspection = inspectionList.first as Map<String, dynamic>;
        } else if (inspectionList is Map) {
          inspection = inspectionList as Map<String, dynamic>;
        }
        
        if (inspection != null) {
          r['anti_mortem'] = inspection['anti_mortem'];
          r['process_stage'] = inspection['process_stage'];
          r['post_mortem'] = inspection['post_mortem'];
          r['carcass_weight'] = inspection['carcass_weight'];
          r['inspector_name'] = inspection['inspector_name'];
          r['process_notes'] = inspection['process_notes'];
          r['condemnation_reason'] = inspection['condemnation_reason'];
          r['veterinary_findings'] = inspection['veterinary_findings'];
          r['inspection_created_at'] = inspection['created_at'];
        }
        if (trackingMap.containsKey(idStr) && trackingMap[idStr] is Map) {
          final t = trackingMap[idStr] as Map;
          r['penalty_fee'] = t['penalty_fee'];
          r['penalty_reason'] = t['penalty_reason'];
          r['actual_date'] = t['actual_date'];
          r['is_warning_only'] = t['is_warning_only'];
          r['offense_level'] = t['offense_level'];
        }
        return r;
      }).toList();
      
      if (mounted) {
        setState(() {
          _barangayRequests = activeRequests.where((r) => r['request_type'] == 'barangay').toList();
          _marketRequests = activeRequests.where((r) => r['request_type'] == 'market').toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('SlaughterInspection load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _refNo(Map<String, dynamic> req) =>
      'MI-${DateTime.now().year}-${req['id'].toString().padLeft(3, '0')}';

  String _formatDate(dynamic v) {
    if (v == null) return '—';
    try {
      return DateFormat('M/d/yyyy').format(DateTime.parse(v.toString()));
    } catch (_) {
      return v.toString();
    }
  }

  List<Map<String, dynamic>> _filteredList(List<Map<String, dynamic>> list) {
    final q = _searchController.text.toLowerCase().trim();
    return list.where((r) {
      final name = (r['customer_name'] ?? '').toString().toLowerCase();
      final ref = _refNo(r).toLowerCase();
      final stage = (r['process_stage'] ?? '').toString();
      
      bool matchesSearch = q.isEmpty || name.contains(q) || ref.contains(q);
      bool matchesFilter = _filterStage == 'All' || stage == _filterStage;
      
      return matchesSearch && matchesFilter;
    }).toList();
  }

  void _openUpdateDialog(Map<String, dynamic> request) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateProcessDialog(
        request: request,
        supabase: supabase,
        onDone: _loadRequests,
      ),
    );
  }

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
                    onRefresh: _loadRequests,
                    color: const Color(0xFF2D6A4F),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFilterRow(),
                          const SizedBox(height: 24),
                          _buildStatsCards(),
                          const SizedBox(height: 32),
                          _buildTableCard(
                            title: 'Barangay Slaughter & Inspection Records',
                            subtitle: 'Track slaughter process stages and post-mortem inspection results',
                            requests: _filteredList(_barangayRequests),
                          ),
                          const SizedBox(height: 24),
                          _buildTableCard(
                            title: 'Market Slaughter & Inspection Records',
                            subtitle: 'Track slaughter process stages and post-mortem inspection results',
                            requests: _filteredList(_marketRequests),
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
              const Text('Slaughter & Inspection',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
              const SizedBox(height: 2),
              Text('Process logging, post-mortem inspection, MIC generation',
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

  Widget _buildFilterRow() {
    return Row(
      children: [
        SizedBox(
          width: 300,
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search by reference number...',
              hintStyle: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: Color(0xFFA0AEC0), size: 20),
              filled: true,
              fillColor: const Color(0xFFEDF2F7),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFEDF2F7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _filterStage,
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
              items: ['All', 'Separate Facility (Weighing)', 'Ante-Mortem', 'Preparation', 'Stunning', 'Bleeding', 'Scalding/Plucking', 'Evisceration', 'Post-Mortem Inspection', 'Weighing', 'Complete', 'Technical Error/Delay']
                  .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13))))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _filterStage = val);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsCards() {
    int inProcess = 0, complete = 0, micGen = 0, total = 0;
    for (var r in [..._barangayRequests, ..._marketRequests]) {
      total++;
      final stage = r['process_stage']?.toString() ?? '';
      if (stage == 'Complete') {
        complete++;
      } else {
        inProcess++;
      }
      if ((r['status'] ?? '') == 'mic_generated' || (r['process_notes']?.toString().contains('MIC Generated') ?? false) || r['status'] == 'paid' || r['status'] == 'released') micGen++;
    }

    return Row(
      children: [
        _statCard('In Process', inProcess.toString(), Colors.blue),
        const SizedBox(width: 16),
        _statCard('Complete', complete.toString(), Colors.green),
        const SizedBox(width: 16),
        _statCard('MIC Generated', micGen.toString(), Colors.green, icon: Icons.check_circle_outline),
        const SizedBox(width: 16),
        _statCard('Today\'s Total', total.toString(), Colors.orange),
      ],
    );
  }

  Widget _statCard(String label, String value, Color accent, {IconData? icon}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                if (icon != null) Icon(icon, size: 16, color: accent)
                else Container(width: 10, height: 10, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
          ],
        ),
      ),
    );
  }

  Widget _buildTableCard({required String title, required String subtitle, required List<Map<String, dynamic>> requests}) {
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final tableWidth = math.max(1150.0, availableWidth);
              final colSpacing = (availableWidth > 1400)
                  ? 34.0
                  : (availableWidth > 1100 ? 24.0 : 16.0);

              return Scrollbar(
                controller: scrollController,
                thumbVisibility: false,
                trackVisibility: false,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                    },
                  ),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: tableWidth),
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(const Color(0xFFF7FAFC)),
                        dataRowMinHeight: 60,
                        dataRowMaxHeight: 80,
                        columnSpacing: colSpacing,
                columns: const [
                  DataColumn(label: Text('Reference #', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  DataColumn(label: Text('Customer', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  DataColumn(label: Text('Livestock', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  DataColumn(label: Text('Schedule/\nActual', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  DataColumn(label: Text('Process Stage', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  DataColumn(label: Text('Post-Mortem', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  DataColumn(label: Text('Customer\nResponse', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  DataColumn(label: Text('MIC', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                ],
                rows: requests.map((req) {
                  final ref = _refNo(req);
                  final stage = req['process_stage'] ?? 'Pending';
                  final postMortem = req['post_mortem'] ?? 'PENDING';
                  final status = req['status'] ?? '';
                  final isDelayed = status == 'delay_error';
                  final isAntiMortemFailed = status == 'anti_mortem_failed' || status == 'pickup_scheduled' || status == 'taken_back';
                  final isPostMortemFailed = status == 'post_mortem_failed';
                  final isCondemnedStatus = status == 'condemned';
                  final isCondemned = req['condemnation_reason'] != null || isCondemnedStatus;
                  final isCondemnationAcknowledged = req['condemnation_acknowledged'] == true || isCondemnedStatus;
                  final customerResponse = req['anti_mortem_response']?.toString();
                  final isSeparateFacility = (req['anti_mortem']?.toString() == 'Separate Facility') ||
                      stage.contains('Separate Facility') ||
                      (req['process_notes']?.toString().contains('SEPARATE FACILITY') ?? false);

                  bool isScheduledForFutureDate() {
                    final pref = req['preferred_date']?.toString();
                    if (pref == null || pref.isEmpty) return false;
                    try {
                      final date = DateTime.parse(pref);
                      final today = DateTime.now();
                      final todayMidnight = DateTime(today.year, today.month, today.day);
                      final reqMidnight = DateTime(date.year, date.month, date.day);
                      return reqMidnight.isAfter(todayMidnight);
                    } catch (_) {
                      return false;
                    }
                  }
                  final bool isFuture = isScheduledForFutureDate();

                  return DataRow(cells: [
                    DataCell(Text(ref, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12))),
                    DataCell(Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(req['customer_name']?.toString() ?? '—', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        _buildSpecialInstructionBadge(
                          context,
                          req['special_instruction']?.toString(),
                          customerName: req['customer_name']?.toString(),
                          refNo: ref,
                        ),
                      ],
                    )),
                    DataCell(Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${req['animal_count']} head(s) • ${req['livestock_type'] ?? ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 3),
                        if (req['marking'] != null && req['marking'].toString().trim().isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFF81C784), width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.label_outline, size: 11, color: Color(0xFF2E7D32)),
                                const SizedBox(width: 3),
                                Text(
                                  'Tag: ${req['marking']}',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)),
                                ),
                              ],
                            ),
                          )
                        else
                          Text('No tag', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                      ],
                    )),
                    DataCell(() {
                      final scheduleDate = _formatDate(req['preferred_date']);
                      final rescheduledDate = req['rescheduled_date'];
                      if (rescheduledDate != null) {
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(scheduleDate, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, decoration: TextDecoration.lineThrough, color: Colors.grey.shade400)),
                            Text('New: ${_formatDate(rescheduledDate)}', style: TextStyle(fontSize: 11, color: Colors.blue.shade600, fontWeight: FontWeight.w500)),
                          ],
                        );
                      }
                      if (isDelayed) {
                        // If delayed due to a technical error, the actual date recorded
                        // is the date the processing actually took place (today or the recorded delay date),
                        // not the scheduled date shifted forward.
                        DateTime actualDate = DateTime.now();
                        if (req['actual_date'] != null) {
                          actualDate = DateTime.tryParse(req['actual_date'].toString())?.toLocal() ?? actualDate;
                        } else {
                          final match = RegExp(r'Technical delay \((\d{4}-\d{2}-\d{2})\)').firstMatch(req['process_notes']?.toString() ?? '');
                          if (match != null) {
                            actualDate = DateTime.tryParse(match.group(1)!) ?? actualDate;
                          } else if (req['inspection_created_at'] != null) {
                            actualDate = DateTime.tryParse(req['inspection_created_at'].toString())?.toLocal() ?? actualDate;
                          }
                        }
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(scheduleDate, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                            Text('Actual: ${_formatDate(actualDate.toIso8601String())}', style: TextStyle(fontSize: 11, color: Colors.red.shade400, fontWeight: FontWeight.w500)),
                          ],
                        );
                      }
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(scheduleDate, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          Text('Actual: $scheduleDate', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        ],
                      );
                    }()),
                    DataCell(Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildBadge(
                          stage,
                          stage == 'Complete'
                              ? Colors.green
                              : (stage.contains('Separate Facility')
                                  ? const Color(0xFFC2410C)
                                  : ((stage == 'Ante-Mortem' || stage == 'Anti-Mortem') ? Colors.red : Colors.grey)),
                        ),
                        if (isSeparateFacility && !stage.contains('Separate Facility')) ...[
                          const SizedBox(height: 2),
                          const Text(
                            '⚡ Separate Facility',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFC2410C)),
                          ),
                        ],
                      ],
                    )),
                    DataCell(Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildBadge(postMortem.toString().toUpperCase(), postMortem == 'PASSED' ? Colors.grey : (postMortem == 'FAILED' ? Colors.red : Colors.grey), outline: true),
                        if (isCondemned) const Text('Condemned!', style: TextStyle(fontSize: 10, color: Colors.red)),
                      ],
                    )),
                    // Customer Response column
                    DataCell(
                      (isPostMortemFailed || isCondemnedStatus)
                          ? (isCondemnationAcknowledged
                              ? _buildBadge('Slip Received & Concluded', Colors.green, light: true)
                              : _buildBadge('Awaiting Slip Review', Colors.orange, light: true))
                          : isAntiMortemFailed
                              ? (customerResponse == null
                                  ? _buildBadge('Awaiting', Colors.orange, light: true)
                                  : customerResponse == 'confine'
                                      ? GestureDetector(
                                          onTap: () => _openAntiMortemResponseDialog(req),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              _buildBadge('Confine', Colors.blue, light: true),
                                              const SizedBox(height: 2),
                                              Text('Tap to manage', style: TextStyle(fontSize: 9, color: Colors.blue.shade400)),
                                            ],
                                          ),
                                        )
                                      : GestureDetector(
                                          onTap: () => _openAntiMortemResponseDialog(req),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              _buildBadge('Take Back', Colors.deepOrange, light: true),
                                              const SizedBox(height: 2),
                                              if (req['pickup_approved'] == true)
                                                _buildBadge('Approved', Colors.green, light: true)
                                              else
                                                Text('Tap to approve', style: TextStyle(fontSize: 9, color: Colors.deepOrange.shade400)),
                                            ],
                                          ),
                                        ))
                              : isDelayed
                                  ? (customerResponse == null
                                      ? _buildBadge('Awaiting Fee Response', Colors.orange, light: true)
                                      : customerResponse == 'accept_penalty'
                                          ? GestureDetector(
                                              onTap: () => _openAntiMortemResponseDialog(req),
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  _buildBadge('Fee Accepted (₱500)', Colors.green, light: true),
                                                  const SizedBox(height: 2),
                                                  Text('Tap to manage', style: TextStyle(fontSize: 9, color: Colors.green.shade600)),
                                                ],
                                              ),
                                            )
                                          : GestureDetector(
                                              onTap: () => _openAntiMortemResponseDialog(req),
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  _buildBadge('Take Back', Colors.deepOrange, light: true),
                                                  const SizedBox(height: 2),
                                                  if (req['pickup_approved'] == true)
                                                    _buildBadge('Approved', Colors.green, light: true)
                                                  else
                                                    Text('Tap to approve', style: TextStyle(fontSize: 9, color: Colors.deepOrange.shade400)),
                                                ],
                                              ),
                                            ))
                                  : const Text('—', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ),
                    DataCell(
                      isCondemnedStatus
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.blueGrey.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle_outline, color: Colors.blueGrey.shade700, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Operation Concluded',
                                    style: TextStyle(fontSize: 10, color: Colors.blueGrey.shade800, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            )
                          : isAntiMortemFailed
                              ? _buildAntiMortemStatusBadge(req, status, customerResponse)
                              : isPostMortemFailed
                                  ? Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.warning_amber_rounded, color: Colors.red.shade600, size: 16),
                                            const SizedBox(width: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.red.shade50,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: Colors.red.shade200),
                                              ),
                                              child: Text(
                                                'Post-Mortem Failed',
                                                style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    )
                              : isDelayed
                                  ? Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 16),
                                            const SizedBox(width: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.shade50,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: Colors.orange.shade200),
                                              ),
                                              child: Text(
                                                'Facility Technical Delay',
                                                style: TextStyle(fontSize: 10, color: Colors.orange.shade800, fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Facility Delay (₱0 Penalty)',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade700,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    )
                                  : (req['is_warning_only'] == true ||
                                          (req['penalty_fee'] == 0.0 && req['penalty_reason'] != null) ||
                                          (req['process_notes'] ?? '').toString().contains('1ST OFFENSE'))
                                      ? Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 15),
                                                const SizedBox(width: 4),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: Colors.amber.shade50,
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(color: Colors.amber.shade300),
                                                  ),
                                                  child: Text(
                                                    '1st Offense Warning',
                                                    style: TextStyle(fontSize: 10, color: Colors.amber.shade900, fontWeight: FontWeight.w600),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Fee Waived (₱0.00)',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.amber.shade900,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        )
                                  : (req['penalty_fee'] != null && (double.tryParse(req['penalty_fee'].toString()) ?? 0.0) > 0)
                                      ? Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.event_busy, color: Colors.red.shade600, size: 15),
                                                const SizedBox(width: 4),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: Colors.red.shade50,
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(color: Colors.red.shade200),
                                                  ),
                                                  child: Text(
                                                    'Repeat Slot Penalty',
                                                    style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.w600),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Wasted Slot Fee: ₱${req['penalty_fee']}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.red.shade700,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        )
                                  : isFuture && status == 'doc_verified'
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEDE9FE),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: const Color(0xFFDDD6FE)),
                                          ),
                                          child: const Text(
                                            'AWAITING ARRIVAL',
                                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF6D28D9)),
                                          ),
                                        )
                                      : _buildBadge(status == 'releasable' ? 'Releasable' : (status == 'mic_generated' ? 'MIC Generated' : (status == 'doc_verified' ? 'SLAUGHTER' : status.toUpperCase())), (status == 'releasable' || status == 'mic_generated') ? Colors.green : Colors.orange, light: true),
                    ),
                    DataCell(
                      (isPostMortemFailed || isCondemnedStatus || postMortem.toString().toUpperCase() == 'FAILED' || isAntiMortemFailed)
                          ? _buildBadge('Failed', Colors.red, light: true)
                          : (status == 'mic_generated' || (req['process_notes']?.toString().contains('MIC Generated') ?? false) || status == 'paid' || status == 'released')
                              ? OutlinedButton.icon(
                                  onPressed: () => showDialog(
                                    context: context,
                                    builder: (_) => _MICDialog(
                                      request: req,
                                      supabase: supabase,
                                      onDone: _loadRequests,
                                    ),
                                  ),
                                  icon: const Icon(Icons.print, size: 14, color: Color(0xFF2D6A4F)),
                                  label: const Text('Printed / View', style: TextStyle(fontSize: 11, color: Color(0xFF2D6A4F), fontWeight: FontWeight.bold)),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: Colors.green.shade600),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                    minimumSize: const Size(0, 28),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  ),
                                )
                              : status == 'releasable'
                                  ? ElevatedButton.icon(
                                      onPressed: () => showDialog(
                                        context: context,
                                        builder: (_) => _MICDialog(
                                          request: req,
                                          supabase: supabase,
                                          onDone: _loadRequests,
                                        ),
                                      ),
                                      icon: const Icon(Icons.download, size: 14, color: Colors.white),
                                      label: const Text('Generate', style: TextStyle(fontSize: 11, color: Colors.white)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green.shade600,
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                        minimumSize: const Size(0, 28),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                      ),
                                    )
                                  : _buildBadge('Pending', Colors.blue, light: true),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          isFuture && status == 'doc_verified'
                              ? Tooltip(
                                  message: 'Livestock scheduled for a future date. Ante-mortem inspection cannot be logged until animal arrives at the facility.',
                                  child: OutlinedButton(
                                    onPressed: null,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      minimumSize: const Size(0, 32),
                                      side: BorderSide(color: Colors.grey.shade300),
                                      disabledForegroundColor: Colors.grey.shade400,
                                    ),
                                    child: const Text('Pending Arrival', style: TextStyle(fontSize: 11.5)),
                                  ),
                                )
                              : OutlinedButton(
                                  onPressed: () => _openUpdateDialog(req),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    minimumSize: const Size(0, 32),
                                    side: BorderSide(color: Colors.grey.shade300),
                                  ),
                                  child: const Text('Update', style: TextStyle(fontSize: 12, color: Color(0xFF4A5568))),
                                ),
                          if (isPostMortemFailed || isCondemnedStatus || isCondemned) ...[
                            const SizedBox(width: 6),
                            OutlinedButton(
                              onPressed: () => showDialog(
                                context: context,
                                builder: (_) => _CondemnationSlipDialog(
                                  request: req,
                                  condemnationReason: req['condemnation_reason']?.toString() ?? 'Condemned after post-mortem inspection',
                                  inspectorName: req['inspector_name']?.toString() ?? 'Meat Inspector',
                                  carcassWeight: req['carcass_weight']?.toString() ?? '',
                                  supabase: supabase,
                                  onDone: _loadRequests,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                minimumSize: const Size(0, 32),
                                side: BorderSide(color: Colors.red.shade300),
                              ),
                              child: Text('Slip', style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                            ),
                          ],
                          if (isAntiMortemFailed) ...[
                            const SizedBox(width: 6),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.fact_check_outlined, size: 13),
                              onPressed: () => _showClearConfinementDialog(req),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E855A),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                minimumSize: const Size(0, 32),
                              ),
                              label: const Text('Evaluate Confinement', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ] else if (isDelayed) ...[
                            const SizedBox(width: 6),
                            if (status == 'pickup_scheduled')
                              ElevatedButton.icon(
                                icon: const Icon(Icons.handshake_outlined, size: 13),
                                onPressed: () => _showConfirmTakenBackDialog(req),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFC0392B),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  minimumSize: const Size(0, 32),
                                ),
                                label: const Text('Confirm Handover', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              )
                            else
                              OutlinedButton(
                                onPressed: () => _openAntiMortemResponseDialog(req),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  minimumSize: const Size(0, 32),
                                  side: BorderSide(color: Colors.blue.shade300),
                                ),
                                child: Text(
                                  customerResponse != null ? 'Respond' : 'Record Decision',
                                  style: TextStyle(fontSize: 12, color: Colors.blue.shade600),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
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

  Widget _buildSpecialInstructionBadge(BuildContext context, String? instruction, {String? customerName, String? refNo}) {
    if (instruction == null || instruction.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final text = instruction.trim();

    return Tooltip(
      message: 'Customer Special Note: $text\n(Click to view details)',
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(6),
      ),
      child: InkWell(
        onTap: () => _showSpecialInstructionDialog(context, text, customerName: customerName, refNo: refNo),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.6)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.assignment_outlined, size: 12, color: Color(0xFFB45309)),
              SizedBox(width: 4),
              Text(
                'Special Note',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFB45309),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSpecialInstructionDialog(BuildContext context, String text, {String? customerName, String? refNo}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.assignment_outlined, color: Color(0xFFB45309), size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Customer Special Instructions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (refNo != null || customerName != null) ...[
              Row(
                children: [
                  if (refNo != null)
                    Text(refNo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF2D6A4F))),
                  if (refNo != null && customerName != null)
                    const Text(' • ', style: TextStyle(color: Colors.grey)),
                  if (customerName != null)
                    Text(customerName, style: const TextStyle(fontSize: 13, color: Color(0xFF4A5568), fontWeight: FontWeight.w500)),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Text(
                text,
                style: const TextStyle(fontSize: 13.5, color: Color(0xFF78350F), height: 1.4),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2D6A4F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _openAntiMortemResponseDialog(Map<String, dynamic> request) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AntiMortemResponseDialog(
        request: request,
        supabase: supabase,
        onDone: _loadRequests,
      ),
    );
  }

  Future<void> _acknowledgeAnteMortemAlert(String reqId) async {
    try {
      final alertRow = await supabase
          .from('system_settings')
          .select('value')
          .eq('key', 'ante_mortem_alerts')
          .maybeSingle();
      if (alertRow != null && alertRow['value'] is Map) {
        final alerts = Map<String, dynamic>.from(alertRow['value']);
        if (alerts.containsKey(reqId) && alerts[reqId] is Map) {
          alerts[reqId]['acknowledged'] = true;
          await supabase.from('system_settings').upsert({
            'key': 'ante_mortem_alerts',
            'value': alerts,
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _checkAnteMortemAlerts() async {
    try {
      // 1. Check system_settings ante_mortem_alerts for instant notifications
      try {
        final alertRow = await supabase
            .from('system_settings')
            .select('value')
            .eq('key', 'ante_mortem_alerts')
            .maybeSingle();
        if (alertRow != null && alertRow['value'] is Map) {
          final alerts = Map<String, dynamic>.from(alertRow['value']);
          for (final entry in alerts.entries) {
            final idStr = entry.key;
            final alert = entry.value as Map<String, dynamic>;
            if (alert['acknowledged'] == true) continue;
            if (_shownAnteMortemAlertIds.contains(idStr)) continue;

            final req = [..._barangayRequests, ..._marketRequests].firstWhere(
              (r) => r['id'].toString() == idStr,
              orElse: () => <String, dynamic>{},
            );
            if (req.isNotEmpty) {
              _shownAnteMortemAlertIds.add(idStr);
              if (mounted) {
                _showAnteMortemAlertModal(req, alert['choice']?.toString() ?? 'accept_penalty');
              }
              return;
            }
          }
        }
      } catch (_) {}

      // 2. Direct requests table query fallback
      final data = await supabase
          .from('requests')
          .select('id, customer_name, livestock_type, animal_count, status, anti_mortem_response, anti_mortem_response_at')
          .inFilter('status', ['anti_mortem_failed', 'delay_error'])
          .not('anti_mortem_response', 'is', null)
          .order('anti_mortem_response_at', ascending: false)
          .limit(5);

      for (final req in data) {
        final idStr = req['id'].toString();
        final response = req['anti_mortem_response']?.toString();
        if (response != null && response.isNotEmpty && !_shownAnteMortemAlertIds.contains(idStr)) {
          _shownAnteMortemAlertIds.add(idStr);
          if (mounted) {
            _showAnteMortemAlertModal(req, response);
          }
          break;
        }
      }
    } catch (_) {}
  }

  void _showAnteMortemAlertModal(Map<String, dynamic> req, String choice) {
    final ref = _refNo(req);
    final customer = req['customer_name'] ?? 'Customer';
    final livestock = req['livestock_type'] ?? 'Livestock';
    final count = req['animal_count'] ?? 1;
    final isPenaltyAccepted = choice == 'accept_penalty';
    final isConfine = choice == 'confine';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isPenaltyAccepted
                  ? Icons.receipt_long
                  : (isConfine ? Icons.medical_services_outlined : Icons.assignment_return_outlined),
              color: isPenaltyAccepted
                  ? const Color(0xFF16A34A)
                  : (isConfine ? const Color(0xFFD97706) : const Color(0xFFC0392B)),
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isPenaltyAccepted
                    ? 'Technical Delay: Reschedule Accepted'
                    : 'Ante-Mortem Decision Received',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isPenaltyAccepted
                      ? const Color(0xFFECFDF5)
                      : (isConfine ? const Color(0xFFFFFBEB) : const Color(0xFFFEF2F2)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isPenaltyAccepted
                        ? const Color(0xFFA7F3D0)
                        : (isConfine ? const Color(0xFFFCD34D) : const Color(0xFFFCA5A5)),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order: $ref | $customer', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text('Livestock: $livestock ($count head)', style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Text('Customer Response: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        Expanded(
                          child: Text(
                            isPenaltyAccepted
                                ? 'ACCEPTED ₱500 PENALTY & RESCHEDULE'
                                : (isConfine ? 'CONFINE IN SLAUGHTERHOUSE' : 'TAKE LIVESTOCK BACK'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isPenaltyAccepted
                                  ? const Color(0xFF15803D)
                                  : (isConfine ? const Color(0xFFB45309) : const Color(0xFFDC2626)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                isPenaltyAccepted
                    ? 'The customer accepted the ₱500 legal finality fee to keep livestock in the facility for resumed slaughter. Please select the rescheduled date.'
                    : (isConfine
                        ? 'The customer agreed to confine the animal in the corral under observation. Once cleared by the veterinarian, you can resume slaughter.'
                        : 'The customer chose to retrieve their livestock. Please set the pickup schedule so the customer knows when to collect the animal at the corral.'),
                style: const TextStyle(fontSize: 13, color: Color(0xFF4A5568)),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _acknowledgeAnteMortemAlert(req['id'].toString());
            },
            child: const Text('Dismiss'),
          ),
          ElevatedButton.icon(
            icon: Icon(
              isPenaltyAccepted
                  ? Icons.calendar_month
                  : (isConfine ? Icons.check : Icons.schedule),
              size: 16,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _acknowledgeAnteMortemAlert(req['id'].toString());
              if (isPenaltyAccepted) {
                _openAntiMortemResponseDialog(req);
              } else if (isConfine) {
                _showClearConfinementDialog(req);
              } else {
                _openAntiMortemResponseDialog(req);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isPenaltyAccepted
                  ? const Color(0xFF2563EB)
                  : (isConfine ? const Color(0xFF1E855A) : const Color(0xFFC0392B)),
              foregroundColor: Colors.white,
            ),
            label: Text(
              isPenaltyAccepted
                  ? 'Set Rescheduled Date'
                  : (isConfine ? 'Manage Confinement' : 'Set Pickup Schedule'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAntiMortemStatusBadge(Map<String, dynamic> req, String status, String? customerResponse) {
    if (status == 'taken_back') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFE6F9F0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2D6A4F).withValues(alpha: 0.3)),
        ),
        child: const Text('Taken Back (Released)', style: TextStyle(fontSize: 10, color: Color(0xFF2D6A4F), fontWeight: FontWeight.w600)),
      );
    }
    if (status == 'pickup_scheduled') {
      final pickupStr = req['pickup_time']?.toString();
      DateTime? dt;
      if (pickupStr != null) dt = DateTime.tryParse(pickupStr);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFEBF8FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFBEE3F8)),
        ),
        child: Text(
          dt != null ? 'Pickup: ${DateFormat('MMM d, h:mm a').format(dt)}' : 'Pickup Scheduled',
          style: const TextStyle(fontSize: 10, color: Color(0xFF2B6CB0), fontWeight: FontWeight.w600),
        ),
      );
    }
    if (customerResponse == 'confine' || status == 'anti_mortem_failed' || status == 'confined') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFCD34D)),
        ),
        child: const Text('Confined (Under Observation)', style: TextStyle(fontSize: 10, color: Color(0xFFB45309), fontWeight: FontWeight.w600)),
      );
    }
    if (customerResponse == 'take_back') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFCA5A5)),
        ),
        child: const Text('Take Back Requested', style: TextStyle(fontSize: 10, color: Color(0xFFDC2626), fontWeight: FontWeight.w600)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: const Text('Ante-Mortem Failed', style: TextStyle(fontSize: 10, color: Color(0xFFC53030), fontWeight: FontWeight.w600)),
    );
  }

  void _showClearConfinementDialog(Map<String, dynamic> req) {
    final ref = _refNo(req);
    final customer = req['customer_name'] ?? 'Customer';
    final livestock = req['livestock_type'] ?? 'Livestock';
    final count = req['animal_count'] ?? 1;
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.local_hospital_outlined, color: Color(0xFF185FA5), size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Evaluate Confined Livestock',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This livestock was placed in facility confinement after failing ante-mortem inspection. Update its veterinary evaluation below:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFCD34D)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order: $ref | $customer', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF92400E))),
                    const SizedBox(height: 4),
                    Text('Livestock: $livestock ($count head)', style: const TextStyle(fontSize: 12, color: Color(0xFF92400E))),
                    const SizedBox(height: 4),
                    const Text('Current Status: Confined (Awaiting Inspector Evaluation)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFB45309))),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Inspector Remarks / Condemnation Reason',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF2D3748)),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: reasonCtrl,
                maxLines: 2,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Enter clearance notes or reason if condemning livestock...',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12.5),
                  filled: true,
                  fillColor: const Color(0xFFF7FAFC),
                  contentPadding: const EdgeInsets.all(10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.gpp_bad_outlined, size: 16),
            onPressed: () async {
              final reason = reasonCtrl.text.trim().isNotEmpty
                  ? reasonCtrl.text.trim()
                  : 'Condemned following ante-mortem confinement evaluation';
              Navigator.pop(ctx);
              await _condemnConfinedLivestock(req, reason);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC0392B),
              foregroundColor: Colors.white,
            ),
            label: const Text('Condemn Livestock'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow, size: 16),
            onPressed: () async {
              final notes = reasonCtrl.text.trim();
              Navigator.pop(ctx);
              await _clearConfinementAndResumeSlaughter(req, notes: notes);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E855A),
              foregroundColor: Colors.white,
            ),
            label: const Text('Cleared & Resume Slaughter'),
          ),
        ],
      ),
    );
  }

  Future<void> _condemnConfinedLivestock(Map<String, dynamic> req, String reason) async {
    try {
      final reqId = req['id'];
      final userId = req['user_id'];
      final livestockType = req['livestock_type'] ?? 'Livestock';
      final animalCount = req['animal_count'] ?? 1;
      final defaultInspector = AppSettingsService.instance.configuredInspectors.isNotEmpty
          ? AppSettingsService.instance.configuredInspectors.first
          : 'Official Meat Inspector';
      final inspectorName = (req['inspector_name']?.toString().trim().isNotEmpty == true)
          ? req['inspector_name'].toString().trim()
          : defaultInspector;

      await supabase.from('requests').update({
        'status': 'post_mortem_failed',
      }).eq('id', reqId);

      final existingInsp = await supabase
          .from('slaughter_inspection')
          .select('id')
          .eq('request_id', reqId)
          .maybeSingle();

      final inspData = {
        'request_id': reqId,
        'anti_mortem': 'Failed',
        'post_mortem': 'Failed',
        'process_stage': 'Condemned',
        'inspector_name': inspectorName,
        'condemnation_reason': reason,
        'process_notes': 'Condemned after facility confinement evaluation: $reason',
      };
      if (existingInsp != null) {
        await supabase.from('slaughter_inspection').update(inspData).eq('request_id', reqId);
      } else {
        await supabase.from('slaughter_inspection').insert(inspData);
      }

      await NotificationService.sendNotificationSafely(
        supabase,
        userId: userId,
        title: '$livestockType — Condemned Following Confinement',
        message: 'Following veterinary confinement and re-evaluation, your $animalCount head(s) of $livestockType was deemed unfit for slaughter and must be condemned ($reason). Please review the official condemnation slip.',
        type: 'post_mortem_failed',
        data: {
          'request_id': reqId,
          'customer_name': req['customer_name'],
          'livestock_type': livestockType,
          'condemnation_reason': reason,
          'inspector_name': inspectorName,
          'animal_count': animalCount,
          'carcass_weight': req['carcass_weight']?.toString() ?? '',
          'process_notes': reason,
        },
      );

      await _loadRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(children: [
              Icon(Icons.gpp_bad_outlined, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Confined livestock marked as Condemned. Customer notified with Condemnation Slip.'),
            ]),
            backgroundColor: Color(0xFFC0392B),
          ),
        );
        showDialog(
          context: context,
          builder: (_) => _CondemnationSlipDialog(
            request: req,
            condemnationReason: reason,
            inspectorName: inspectorName,
            carcassWeight: req['carcass_weight']?.toString() ?? '',
            supabase: supabase,
            onDone: _loadRequests,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error condemning livestock: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _clearConfinementAndResumeSlaughter(Map<String, dynamic> req, {String notes = ''}) async {
    try {
      final reqId = req['id'];
      final userId = req['user_id'];
      final livestockType = req['livestock_type'] ?? 'Livestock';
      final animalCount = req['animal_count'] ?? 1;
      final refNo = _refNo(req);

      // 1. Update requests status to slaughter_started
      await supabase.from('requests').update({
        'status': 'slaughter_started',
      }).eq('id', reqId);

      // 2. Update slaughter_inspection
      final existingInsp = await supabase.from('slaughter_inspection').select('id').eq('request_id', reqId).maybeSingle();
      final defaultInspector = AppSettingsService.instance.configuredInspectors.isNotEmpty
          ? AppSettingsService.instance.configuredInspectors.first
          : 'Official Meat Inspector';
      final resolvedNotes = notes.isNotEmpty
          ? 'Cleared after confinement and observation: $notes'
          : 'Cleared after confinement and observation. Resumed active slaughter at Stunning stage.';
      final inspData = {
        'request_id': reqId,
        'anti_mortem': 'Passed',
        'process_stage': 'Stunning',
        'inspector_name': defaultInspector,
        'process_notes': resolvedNotes,
      };
      if (existingInsp != null) {
        await supabase.from('slaughter_inspection').update(inspData).eq('request_id', reqId);
      } else {
        await supabase.from('slaughter_inspection').insert(inspData);
      }

      // 3. Notify customer
      await NotificationService.sendNotificationSafely(
        supabase,
        userId: userId,
        title: '$livestockType — Cleared & Ready for Slaughter',
        message: 'Your $animalCount head(s) of $livestockType ($refNo) has been cleared by the veterinarian and is now ready for slaughter. Slaughter operations have resumed at the Stunning stage.',
        type: 'slaughter_started',
        data: {
          'request_id': reqId,
          'reference_no': refNo,
          'livestock_type': livestockType,
          'process_stage': 'Stunning',
        },
      );

      _loadRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Livestock cleared! Moved to active slaughter queue (Stunning). Customer notified.'),
            ]),
            backgroundColor: Color(0xFF1E855A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing confinement: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showConfirmTakenBackDialog(Map<String, dynamic> req) {
    final ref = _refNo(req);
    final customer = req['customer_name'] ?? 'Customer';
    final livestock = req['livestock_type'] ?? 'Livestock';
    final count = req['animal_count'] ?? 1;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.handshake_outlined, color: Color(0xFFC0392B), size: 24),
            SizedBox(width: 8),
            Text('Confirm Animal Handover', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Confirm that the customer or authorized representative has physically taken back $count head(s) of $livestock at the slaughterhouse corral.',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF5F5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFEB2B2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order: $ref | $customer', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF991B1B))),
                    const SizedBox(height: 4),
                    Text('Livestock: $livestock ($count head)', style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B))),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.done_all, size: 16),
            onPressed: () async {
              Navigator.pop(ctx);
              await _confirmAnimalTakenBack(req);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC0392B),
              foregroundColor: Colors.white,
            ),
            label: const Text('Confirm Animal Handover Complete'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAnimalTakenBack(Map<String, dynamic> req) async {
    try {
      final reqId = req['id'];
      final userId = req['user_id'];
      final livestockType = req['livestock_type'] ?? 'Livestock';
      final refNo = _refNo(req);
      final formattedTime = DateFormat('h:mm a, MMMM d, yyyy').format(DateTime.now());

      await supabase.from('requests').update({
        'status': 'taken_back',
        'released_at': DateTime.now().toIso8601String(),
      }).eq('id', reqId);

      await NotificationService.sendNotificationSafely(
        supabase,
        userId: userId,
        title: '$livestockType — Handover Complete',
        message: 'Your $livestockType ($refNo) was officially released and handed over to you at the slaughterhouse corral at $formattedTime. Thank you!',
        type: 'taken_back',
        data: {
          'request_id': reqId,
          'reference_no': refNo,
          'livestock_type': livestockType,
          'verified_at': formattedTime,
        },
      );

      _loadRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(children: [
              Icon(Icons.verified, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Livestock handover confirmed! Status set to Taken Back.'),
            ]),
            backgroundColor: Color(0xFFC0392B),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error confirming handover: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildBadge(String text, Color color, {bool outline = false, bool light = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: outline ? Colors.transparent : (light ? color.withValues(alpha: 0.1) : color),
        border: outline ? Border.all(color: color) : null,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: outline ? color : (light ? color : Colors.white))),
    );
  }
}

class _UpdateProcessDialog extends StatefulWidget {
  final Map<String, dynamic> request;
  final SupabaseClient supabase;
  final VoidCallback onDone;

  const _UpdateProcessDialog({required this.request, required this.supabase, required this.onDone});

  @override
  State<_UpdateProcessDialog> createState() => _UpdateProcessDialogState();
}

class _UpdateProcessDialogState extends State<_UpdateProcessDialog> {
  bool _isLoading = false;
  late String _antiMortem;
  late String _processStage;
  late String _postMortem;
  final _carcassCtrl = TextEditingController();
  final _inspectorCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  late List<String> _inspectors;
  String? _selectedInspector;

  bool _healthIssueDetected = false;
  final _condemnationCtrl = TextEditingController();

  bool _technicalError = false;
  final _delayReasonCtrl = TextEditingController();
  bool _isMissedSchedule = false;
  int _customerPriorMissedCount = 0;
  String _emergencyCause = 'Heat Stroke';
  final List<String> _emergencyCauses = const [
    'Heat Stroke',
    'Transit Stress',
    'Accidental / Transit Injury',
    'Other Non-Infectious Cause',
  ];

  (double min, double max) _getAcceptableWeightRange(String? type, int count) {
    final t = (type ?? '').toLowerCase();
    final heads = count > 0 ? count : 1;
    if (t.contains('cattle') || t.contains('cow') || t.contains('carabao')) {
      return (100.0 * heads, 500.0 * heads);
    } else if (t.contains('goat') || t.contains('sheep')) {
      return (10.0 * heads, 40.0 * heads);
    } else if (t.contains('poultry') || t.contains('chicken')) {
      return (0.8 * heads, 5.0 * heads);
    }
    // Default to Hog / Swine / Pig
    return (40.0 * heads, 160.0 * heads);
  }

  bool _isWeightInRange(double weight, String? type, int count) {
    final range = _getAcceptableWeightRange(type, count);
    return weight >= range.$1 && weight <= range.$2;
  }

  void _checkAutoDetermination() {
    final count = int.tryParse(widget.request['animal_count']?.toString() ?? '1') ?? 1;
    final type = widget.request['livestock_type']?.toString();
    final weight = double.tryParse(_carcassCtrl.text.trim());

    // 1. If Ante-Mortem is Separate Facility, bypass standard floor stages to 'Separate Facility (Weighing)'
    if (_antiMortem == 'Separate Facility') {
      if (_processStage != 'Complete') {
        _processStage = 'Separate Facility (Weighing)';
      }
    } else if (_antiMortem == 'Passed') {
      if ((_processStage == 'Ante-Mortem' || _processStage == 'Anti-Mortem') || _processStage == 'Preparation') {
        _processStage = 'Stunning';
      }
    }

    // 2. Only auto-mark Complete if weight is entered & within acceptable range AND Post-Mortem passes
    if (weight != null && _isWeightInRange(weight, type, count) && _postMortem == 'Passed') {
      _processStage = 'Complete';
    } else if (_processStage == 'Complete' && (weight == null || !_isWeightInRange(weight, type, count))) {
      // Revert if weight is removed or not acceptable
      _processStage = _antiMortem == 'Separate Facility' ? 'Separate Facility (Weighing)' : 'Weighing';
    }
  }

  @override
  void initState() {
    super.initState();
    final req = widget.request;
    final validAntiMortem = ['Pending', 'Passed', 'Failed', 'Separate Facility'];
    final rawAntiMortem = req['anti_mortem']?.toString() ?? 'Pending';
    _antiMortem = validAntiMortem.contains(rawAntiMortem) ? rawAntiMortem : 'Pending';
    final validStages = ['Separate Facility (Weighing)', 'Ante-Mortem', 'Preparation', 'Stunning', 'Bleeding', 'Scalding/Plucking', 'Evisceration', 'Post-Mortem Inspection', 'Weighing', 'Complete', 'Technical Error/Delay'];
    final reqStage = req['process_stage'] ?? 'Preparation';
    _processStage = validStages.contains(reqStage) ? reqStage : 'Preparation';
    _postMortem = req['post_mortem'] ?? 'Pending';
    if (req['carcass_weight'] != null) _carcassCtrl.text = req['carcass_weight'].toString();

    final rawNotes = (req['process_notes'] ?? '').toString();
    final causeMatch = RegExp(r'Cause:\s*([^\]]+)').firstMatch(rawNotes);
    if (causeMatch != null) {
      final parsedCause = causeMatch.group(1)?.trim() ?? '';
      if (_emergencyCauses.contains(parsedCause)) {
        _emergencyCause = parsedCause;
      }
    }

    // Built-in inspector name based on staff accounts & roles
    _inspectors = AppSettingsService.instance.configuredInspectors;
    final existingInspector = req['inspector_name']?.toString().trim();
    if (existingInspector != null && existingInspector.isNotEmpty && _inspectors.contains(existingInspector)) {
      _selectedInspector = existingInspector;
    } else if (_inspectors.isNotEmpty) {
      _selectedInspector = _inspectors.first;
    } else {
      _selectedInspector = existingInspector ?? (_inspectors.isNotEmpty ? _inspectors.first : 'Official Meat Inspector');
    }
    _inspectorCtrl.text = _selectedInspector ?? '';

    if (req['process_notes'] != null) _notesCtrl.text = req['process_notes'].toString();
    if (req['condemnation_reason'] != null) {
      _healthIssueDetected = true;
      _condemnationCtrl.text = req['condemnation_reason'].toString();
    }
    if (req['delay_reason'] != null) {
      _delayReasonCtrl.text = req['delay_reason'].toString();
    } else {
      final notes = (req['process_notes'] ?? '').toString();
      final match = RegExp(r'Technical delay\s*(?:\([^)]*\))?:\s*(.*)').firstMatch(notes);
      if (match != null) {
        _delayReasonCtrl.text = match.group(1) ?? '';
      }
    }
    _technicalError = _processStage == 'Technical Error/Delay';

    final prefDateStr = req['preferred_date']?.toString();
    if (prefDateStr != null && prefDateStr.isNotEmpty) {
      try {
        final sched = DateTime.parse(prefDateStr);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final schedDate = DateTime(sched.year, sched.month, sched.day);
        if (schedDate.isBefore(today) && req['rescheduled_date'] == null) {
          _isMissedSchedule = true;
        }
      } catch (_) {}
    }
    if (req['penalty_fee'] != null && (double.tryParse(req['penalty_fee'].toString()) ?? 0.0) > 0) {
      _isMissedSchedule = true;
    }
    if (req['is_warning_only'] == true || (req['process_notes'] ?? '').toString().contains('1ST OFFENSE')) {
      _isMissedSchedule = true;
    }

    _loadCustomerMissedScheduleHistory();

    _carcassCtrl.addListener(() {
      if (mounted) {
        setState(() {
          _checkAutoDetermination();
        });
      }
    });
  }

  Future<void> _loadCustomerMissedScheduleHistory() async {
    if (!mounted) return;
    try {
      final customerKey = (widget.request['user_id'] ??
              widget.request['contact_number'] ??
              widget.request['customer_name'] ??
              '')
          .toString()
          .trim();
      final currentReqId = widget.request['id']?.toString() ?? '';

      final row = await widget.supabase
          .from('system_settings')
          .select('value')
          .eq('key', 'customer_missed_schedule_history')
          .maybeSingle();

      if (row != null && row['value'] is Map) {
        final histMap = Map<String, dynamic>.from(row['value']);
        if (customerKey.isNotEmpty && histMap.containsKey(customerKey)) {
          final cData = histMap[customerKey];
          if (cData is Map) {
            final records = (cData['records'] as List?) ?? [];
            final priorRecords = records
                .where((rec) => rec['request_id']?.toString() != currentReqId)
                .toList();
            if (mounted) {
              setState(() {
                _customerPriorMissedCount = priorRecords.length;
              });
            }
          } else if (cData is num) {
            if (mounted) {
              setState(() {
                _customerPriorMissedCount = cData.toInt();
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading customer missed schedule history: $e');
    }
  }

  Future<void> _updateProcess({bool notifyDelay = false}) async {
    final weight = double.tryParse(_carcassCtrl.text.trim());

    if (_processStage == 'Complete' && !notifyDelay) {
      if (weight == null || weight <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Warning: Carcass weight is required before marking as Complete.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      final reqId = widget.request['id'];
      final userId = widget.request['user_id'];
      // refNo could be used in future for logging
      // final refNo = 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';

      // Validate inputs if needed...
      
      final customerKey = (widget.request['user_id'] ??
              widget.request['contact_number'] ??
              widget.request['customer_name'] ??
              '')
          .toString()
          .trim();
      final isRepeatOffense = _customerPriorMissedCount >= 1;
      final offenseLevel = isRepeatOffense ? (_customerPriorMissedCount + 1) : 1;
      final double computedPenaltyFee = _isMissedSchedule ? (isRepeatOffense ? 500.0 : 0.0) : 0.0;

      String newStatus = widget.request['status'];
      String? notifTitle;
      String? notifMessage;
      String? notifType;
      Map<String, dynamic>? notifData;

      // If anti-mortem failed, automatically place in confinement awaiting inspector evaluation
      if (_antiMortem == 'Failed') {
        newStatus = 'anti_mortem_failed';
        _processStage = 'Ante-Mortem';
        final livestockType = widget.request['livestock_type'] ?? 'Livestock';
        final vetFindings = _notesCtrl.text.isNotEmpty ? _notesCtrl.text : 'Health issue detected during ante-mortem inspection';
        notifTitle = '$livestockType — Placed in Confinement (Ante-Mortem Failed)';
        notifMessage = 'Ante-mortem inspection failed. Your livestock has been placed in facility confinement while awaiting an update from the inspector on whether it can still be slaughtered or if it must be condemned.';
        notifType = 'anti_mortem_failed';
        notifData = {
          'request_id': reqId,
          'livestock_type': livestockType,
          'veterinary_findings': vetFindings,
          'inspector_name': _inspectorCtrl.text,
          'animal_count': widget.request['animal_count'],
        };
      } else if (notifyDelay) {
        newStatus = 'delay_error';
        _processStage = 'Technical Error/Delay';
        final livestockType = widget.request['livestock_type'] ?? 'Livestock';
        final delayReason = _delayReasonCtrl.text.trim();
        final reasonSuffix = delayReason.isNotEmpty ? ': $delayReason' : '';
        notifTitle = '$livestockType Operation Delayed (Facility Delay)';
        notifMessage = '$livestockType slaughter was delayed due to an internal slaughterhouse technical issue$reasonSuffix. No penalty fee will be charged to you (₱0.00 penalty). You may choose to keep your livestock in the facility for resumed processing or arrange retrieval at no charge.';
        notifType = 'operation_failed';
        notifData = {
          'request_id': reqId,
          'livestock_type': livestockType,
          'reason': delayReason,
          'penalty_fee': 0.0,
          'is_delayed': true,
          'actual_date': DateTime.now().toLocal().toIso8601String().split('T')[0],
        };
      } else if (_postMortem == 'Failed') {
        newStatus = 'post_mortem_failed';
        _processStage = 'Post-Mortem Inspection'; // Optional: keep it descriptive
        final livestockType = widget.request['livestock_type'] ?? 'Livestock';
        final reason = _healthIssueDetected ? _condemnationCtrl.text : 'Condemned after slaughter';
        notifTitle = '$livestockType — Post-Mortem Failed';
        notifMessage = 'Health issues were found during post-mortem inspection after slaughter. Please review condemnation slip.';
        notifType = 'post_mortem_failed';
        notifData = {
          'request_id': reqId,
          'customer_name': widget.request['customer_name'],
          'livestock_type': livestockType,
          'condemnation_reason': reason,
          'inspector_name': _inspectorCtrl.text,
          'animal_count': widget.request['animal_count'],
          'carcass_weight': _carcassCtrl.text,
          'process_notes': _notesCtrl.text,
        };
      } else if (_processStage == 'Complete' && _postMortem != 'Failed') {
        newStatus = 'releasable';
        final livestockType = widget.request['livestock_type'] ?? 'Livestock';
        final animalCount = widget.request['animal_count'] ?? 1;
        final refNo = 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';
        final weight = _carcassCtrl.text.trim();
        final weightInfo = weight.isNotEmpty ? ' with a carcass weight of $weight kg' : '';

        final isMarket = (widget.request['request_type'] ?? '').toString().toLowerCase() == 'market';
        if (isMarket) {
          notifTitle = 'Meat Ready for Delivery — Payment Required';
          notifMessage = 'Your $animalCount head(s) of $livestockType ($refNo) has been successfully slaughtered and passed post-mortem inspection$weightInfo. Market delivery is scheduled — please settle payment via GCash or cashier to clear your carcass for delivery dispatch.';
        } else {
          notifTitle = 'Meat Ready for Collection — Payment Required';
          notifMessage = 'Your $animalCount head(s) of $livestockType ($refNo) has been successfully slaughtered and passed post-mortem inspection$weightInfo. Under Cash-on-Pickup, please settle payment at the cashier counter upon arrival before carcass release. Reminder: Claim before 5:00 PM to avoid cold storage preservation fees.';
        }
        notifType = 'slaughter_completed';
        notifData = {
          'request_id': reqId,
          'livestock_type': livestockType,
          'animal_count': animalCount,
          'carcass_weight': double.tryParse(_carcassCtrl.text),
          'inspector_name': _inspectorCtrl.text,
          'post_mortem': _postMortem,
          'process_stage': _processStage,
          'penalty_fee': computedPenaltyFee,
          'is_warning_only': !isRepeatOffense,
          'offense_level': offenseLevel,
        };
      } else if (_antiMortem == 'Separate Facility') {
        newStatus = 'slaughter_started';
        final livestockType = widget.request['livestock_type'] ?? 'Livestock';
        final animalCount = widget.request['animal_count'] ?? 1;
        final refNo = 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';
        notifTitle = 'Separate Facility — Emergency Slaughter';
        notifMessage =
            'Your $animalCount head(s) of $livestockType ($refNo) arrived deceased due to $_emergencyCause (non-infectious) and is being processed immediately in the Separate Facility, bypassing the standard slaughterhouse queue.';
        notifType = 'separate_facility_slaughter';
        notifData = {
          'request_id': reqId,
          'livestock_type': livestockType,
          'animal_count': animalCount,
          'emergency_cause': _emergencyCause,
          'facility': 'Separate Facility',
        };
      }

      await widget.supabase.from('requests').update({
        'status': newStatus,
        if (_antiMortem == 'Failed') ...{
          'anti_mortem_response': 'confine',
          'anti_mortem_response_at': DateTime.now().toIso8601String(),
        } else if (notifyDelay) ...{
          'anti_mortem_response': null,
          'anti_mortem_response_at': null,
        },
      }).eq('id', reqId);

      final nowStr = DateTime.now().toLocal().toIso8601String().split('T')[0];

      // Persist Missed Schedule / Wasted Slot penalty or clear facility delay penalty in system_settings
      try {
        final settingsRow = await widget.supabase
            .from('system_settings')
            .select('value')
            .eq('key', 'pickup_penalty_tracking')
            .maybeSingle();
        Map<String, dynamic> trackMap = {};
        if (settingsRow != null && settingsRow['value'] is Map) {
          trackMap = Map<String, dynamic>.from(settingsRow['value']);
        }
        if (_isMissedSchedule) {
          final reqTrack = Map<String, dynamic>.from(trackMap[reqId.toString()] ?? {});
          reqTrack['penalty_fee'] = computedPenaltyFee;
          reqTrack['penalty_reason'] = isRepeatOffense
              ? 'Repeat Missed Schedule (#$offenseLevel) / Wasted Slot Penalty'
              : '1st Offense Missed Schedule (Warning Notice)';
          reqTrack['is_warning_only'] = !isRepeatOffense;
          reqTrack['offense_level'] = offenseLevel;
          reqTrack['actual_date'] = nowStr;
          trackMap[reqId.toString()] = reqTrack;
          await widget.supabase.from('system_settings').upsert({
            'key': 'pickup_penalty_tracking',
            'value': trackMap,
          });

          // Also record customer offense in customer_missed_schedule_history
          try {
            final histRow = await widget.supabase
                .from('system_settings')
                .select('value')
                .eq('key', 'customer_missed_schedule_history')
                .maybeSingle();
            Map<String, dynamic> allHist = {};
            if (histRow != null && histRow['value'] is Map) {
              allHist = Map<String, dynamic>.from(histRow['value']);
            }
            final cEntry = Map<String, dynamic>.from((allHist[customerKey] as Map?) ?? {});
            final recordsList = List<Map<String, dynamic>>.from((cEntry['records'] as List?) ?? []);
            recordsList.removeWhere((r) => r['request_id']?.toString() == reqId.toString());
            recordsList.add({
              'request_id': reqId,
              'reference_no': 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}',
              'scheduled_date': widget.request['preferred_date'],
              'actual_date': nowStr,
              'offense_level': offenseLevel,
              'action': isRepeatOffense ? 'penalty_charged' : 'warning_issued',
              'penalty_fee': computedPenaltyFee,
              'recorded_at': DateTime.now().toIso8601String(),
            });
            cEntry['count'] = recordsList.length;
            cEntry['records'] = recordsList;
            if (customerKey.isNotEmpty) {
              allHist[customerKey] = cEntry;
              await widget.supabase.from('system_settings').upsert({
                'key': 'customer_missed_schedule_history',
                'value': allHist,
              });
            }
          } catch (histErr) {
            debugPrint('Error updating customer_missed_schedule_history: $histErr');
          }
        } else if (notifyDelay && trackMap.containsKey(reqId.toString())) {
          trackMap.remove(reqId.toString());
          await widget.supabase.from('system_settings').upsert({
            'key': 'pickup_penalty_tracking',
            'value': trackMap,
          });
        }
      } catch (trackErr) {
        debugPrint('Error updating pickup_penalty_tracking: $trackErr');
      }

      final delayReason = _delayReasonCtrl.text.trim();
      String processNotes = _notesCtrl.text.trim();
      if (_isMissedSchedule && !processNotes.contains('MISSED SCHEDULE')) {
        final missedTag = isRepeatOffense
            ? '[REPEAT OFFENSE (#$offenseLevel): MISSED SCHEDULE PENALTY ₱500.00 | Actual: $nowStr]'
            : '[1ST OFFENSE: MISSED SCHEDULE FORMAL WARNING (₱0.00 WAIVED) | Actual: $nowStr]';
        processNotes = processNotes.isEmpty ? missedTag : '$missedTag | $processNotes';
      }
      if (_antiMortem == 'Separate Facility' && !processNotes.contains('SEPARATE FACILITY')) {
        final prefix =
            '[SEPARATE FACILITY - EMERGENCY SLAUGHTER | Cause: $_emergencyCause] Livestock arrived deceased due to non-infectious cause ($_emergencyCause). Routed to Separate Facility for immediate slaughter.';
        processNotes = processNotes.isEmpty ? prefix : '$prefix | $processNotes';
      }
      if (notifyDelay && delayReason.isNotEmpty) {
        processNotes = processNotes.isEmpty
            ? 'Technical delay ($nowStr): $delayReason'
            : '$processNotes | Technical delay ($nowStr): $delayReason';
      }

      final existing = await widget.supabase.from('slaughter_inspection').select('id').eq('request_id', reqId).maybeSingle();
      final inspectionData = {
        'request_id': reqId,
        'anti_mortem': _antiMortem,
        'process_stage': _processStage,
        'post_mortem': _postMortem,
        'carcass_weight': double.tryParse(_carcassCtrl.text),
        'inspector_name': _inspectorCtrl.text,
        'process_notes': processNotes,
        'condemnation_reason': _healthIssueDetected ? _condemnationCtrl.text : null,
        'veterinary_findings': _antiMortem == 'Failed' ? _notesCtrl.text : null,
      };

      if (existing != null) {
        await widget.supabase.from('slaughter_inspection').update(inspectionData).eq('request_id', reqId);
      } else {
        await widget.supabase.from('slaughter_inspection').insert(inspectionData);
      }

      // Safely dispatch customer notification without blocking the update
      if (notifTitle != null && notifMessage != null && notifType != null) {
        await NotificationService.sendNotificationSafely(
          widget.supabase,
          userId: userId,
          title: notifTitle,
          message: notifMessage,
          type: notifType,
          data: notifData,
        );
      }

      // If missed schedule occurred, send dedicated Schedule Notice
      if (_isMissedSchedule) {
        final prefStr = widget.request['preferred_date']?.toString() ?? 'scheduled date';
        String schedDisplay = prefStr;
        try {
          schedDisplay = DateFormat('MMMM d, yyyy').format(DateTime.parse(prefStr));
        } catch (_) {}
        final refNum = 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';

        if (!isRepeatOffense) {
          await NotificationService.sendNotificationSafely(
            widget.supabase,
            userId: userId,
            title: '⚠️ Schedule Notice: 1st Offense Warning (Fee Waived)',
            message: 'You missed your reserved slaughter schedule for $refNum on $schedDisplay. Under Tabaco City abattoir guidelines, grace is granted for your 1st offense with ₱0.00 penalty. Please ensure livestock arrives on your scheduled date in future bookings, as repeat missed schedules will automatically incur a ₱500.00 Wasted Slot Penalty.',
            type: 'missed_schedule_warning',
            referenceNo: refNum,
            data: {
              'request_id': reqId,
              'reference_no': refNum,
              'offense_level': 1,
              'penalty_fee': 0.0,
              'is_warning_only': true,
              'scheduled_date': prefStr,
              'actual_date': nowStr,
            },
          );
        } else {
          await NotificationService.sendNotificationSafely(
            widget.supabase,
            userId: userId,
            title: '⛔ Missed Schedule Penalty Applied (₱500.00)',
            message: 'You missed your reserved slaughter schedule for $refNum on $schedDisplay. Having previously received a formal warning, an automatic ₱500.00 Wasted Slot Penalty has been charged to your bill (Repeat Offense #$offenseLevel).',
            type: 'missed_schedule_penalty',
            referenceNo: refNum,
            data: {
              'request_id': reqId,
              'reference_no': refNum,
              'offense_level': offenseLevel,
              'penalty_fee': 500.0,
              'is_warning_only': false,
              'scheduled_date': prefStr,
              'actual_date': nowStr,
            },
          );
        }
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onDone();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Process updated successfully'), backgroundColor: Colors.green.shade600),
        );
        // Auto-show Condemnation Slip if post-mortem failed
        if (_postMortem == 'Failed' || _healthIssueDetected) {
          final ctx = context;
          Future.delayed(const Duration(milliseconds: 300), () {
            if (ctx.mounted) {
              showDialog(
                context: ctx,
                builder: (_) => _CondemnationSlipDialog(
                  request: widget.request,
                  condemnationReason: _condemnationCtrl.text,
                  inspectorName: _inspectorCtrl.text,
                  carcassWeight: _carcassCtrl.text,
                  supabase: widget.supabase,
                  onDone: widget.onDone,
                ),
              );
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = 'MI-${DateTime.now().year}-${widget.request['id'].toString().padLeft(3, '0')}';
    final cust = widget.request['customer_name']?.toString() ?? 'Unknown';
    final type = widget.request['request_type'] == 'market' ? 'Market' : 'Barangay';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Update Slaughter Process', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Update the process stage and inspection results.', style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: _buildLabelValue('Reference Number', ref)),
                  Expanded(child: _buildLabelValue('Customer', cust)),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _buildLabelValue('Request Type', type)),
                  Expanded(
                    child: _buildLabelValue(
                      'Livestock Tag / Marking',
                      widget.request['marking']?.toString().isNotEmpty == true
                          ? widget.request['marking'].toString()
                          : '—',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              
              if ((widget.request['special_instruction'] ?? '').toString().trim().isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFF59E0B)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.speaker_notes, color: Color(0xFFB45309), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Customer Special Instructions:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                color: Color(0xFF92400E),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              (widget.request['special_instruction'] ?? '').toString().trim(),
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF78350F),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              const Text('Ante-Mortem Result', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A5568))),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _antiMortem,
                    items: ['Pending', 'Passed', 'Failed', 'Separate Facility'].map((e) => DropdownMenuItem(
                      value: e,
                      child: Text(
                        e == 'Separate Facility'
                            ? 'Separate Facility (Died in Transit — Non-Infectious)'
                            : e,
                        style: TextStyle(
                          fontWeight: e == 'Separate Facility' ? FontWeight.bold : FontWeight.normal,
                          color: e == 'Separate Facility' ? const Color(0xFFC2410C) : Colors.black87,
                        ),
                      ),
                    )).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _antiMortem = v;
                          _checkAutoDetermination();
                        });
                      }
                    },
                  ),
                ),
              ),
              if (_antiMortem == 'Separate Facility') ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFEA580C)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.bolt_rounded, color: Color(0xFFC2410C), size: 18),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Separate Facility — Immediate Slaughter (Bypassing Standard Floor Stages)',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF9A3412)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Livestock arrived deceased due to stress, heat stroke, or accidental (non-infectious) causes. Enter Carcass Weight & Post-Mortem result to complete.',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFFC2410C), height: 1.35),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Non-Infectious Cause of Death *',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF9A3412)),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFED7AA)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _emergencyCause,
                            items: _emergencyCauses
                                .map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13))))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _emergencyCause = v);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Process Stage', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A5568))),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _processStage,
                              items: ['Separate Facility (Weighing)', 'Ante-Mortem', 'Preparation', 'Stunning', 'Bleeding', 'Scalding/Plucking', 'Evisceration', 'Post-Mortem Inspection', 'Weighing', 'Complete', 'Technical Error/Delay'].map((e) => DropdownMenuItem(
                                value: e, 
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: e == 'Technical Error/Delay' ? Colors.redAccent : Colors.transparent,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(e, style: TextStyle(color: e == 'Technical Error/Delay' ? Colors.white : Colors.black87)),
                                ),
                              )).toList(),
                              onChanged: (v) => setState(() {
                                if (v == 'Complete') {
                                  final weight = double.tryParse(_carcassCtrl.text.trim());
                                  if (weight == null || weight <= 0) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Warning: Carcass weight is required before marking as Complete.'),
                                        backgroundColor: Colors.orange,
                                      ),
                                    );
                                    _processStage = 'Weighing';
                                    return;
                                  }
                                }
                                _processStage = v!;
                                if (_processStage == 'Technical Error/Delay') {
                                  _technicalError = true;
                                } else {
                                  _technicalError = false;
                                }
                                if (_processStage == 'Complete' && _postMortem == 'Pending') {
                                  _postMortem = 'Passed';
                                }
                              }),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Carcass Weight (kg)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A5568))),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _carcassCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                            hintText: 'e.g. 75.0',
                          ),
                        ),
                        const SizedBox(height: 6),
                        Builder(
                          builder: (context) {
                            final count = int.tryParse(widget.request['animal_count']?.toString() ?? '1') ?? 1;
                            final type = widget.request['livestock_type']?.toString() ?? 'Livestock';
                            final range = _getAcceptableWeightRange(type, count);
                            final w = double.tryParse(_carcassCtrl.text.trim());
                            if (w == null) {
                              return Text(
                                'Acceptable range: ${range.$1.toStringAsFixed(0)}–${range.$2.toStringAsFixed(0)} kg ($count head $type)',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              );
                            }
                            final inRange = _isWeightInRange(w, type, count);
                            return Row(
                              children: [
                                Icon(
                                  inRange ? Icons.check_circle_outline : Icons.info_outline,
                                  size: 13,
                                  color: inRange ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    inRange
                                        ? 'Within acceptable range (${range.$1.toStringAsFixed(0)}–${range.$2.toStringAsFixed(0)} kg)'
                                        : 'Outside typical range (${range.$1.toStringAsFixed(0)}–${range.$2.toStringAsFixed(0)} kg)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: inRange ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),

                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Post-Mortem Result', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A5568))),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _postMortem,
                              items: ['Pending', 'Passed', 'Failed'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                              onChanged: (v) {
                              if (v != null) {
                                setState(() {
                                  _postMortem = v;
                                  _checkAutoDetermination();
                                });
                              }
                            },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Inspector Name', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A5568))),
                        const SizedBox(height: 6),
                        _buildInspectorField(),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Process Notes', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A5568))),
              const SizedBox(height: 6),
              TextField(
                controller: _notesCtrl,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 24),

              // Health Issue / Condemnation
              Row(
                children: [
                  Checkbox(
                    value: _healthIssueDetected,
                    onChanged: (v) => setState(() => _healthIssueDetected = v!),
                  ),
                  const Expanded(
                    child: Text(
                      'Health issue detected - Generate Condemnation Slip', 
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                    )
                  ),
                ],
              ),
              if (_healthIssueDetected)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.grey.shade500, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text('A condemnation slip will be automatically generated and printed.', style: TextStyle(color: Colors.grey.shade600, fontSize: 12))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('Condemnation Details *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _condemnationCtrl,
                        decoration: InputDecoration(
                          hintText: 'Describe the Health issue (e.g., liver abscess, lung lesion, etc...)',
                          hintStyle: const TextStyle(color: Colors.black, fontSize: 13),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),

              // Technical Error Section
              GestureDetector(
                onTap: () => setState(() {
                  _technicalError = !_technicalError;
                  if (_technicalError) {
                    _processStage = 'Technical Error/Delay';
                  } else if (_processStage == 'Technical Error/Delay') {
                    _processStage = 'Preparation';
                  }
                }),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      child: Icon(_technicalError ? Icons.cancel : Icons.cancel_outlined, color: Colors.red, size: 24),
                    ),
                    const Expanded(
                      child: Text('Technical Error / Issue', style: TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold))
                    ),
                  ],
                ),
              ),
              if (_technicalError)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('The customer will be notified that their livestock slaughter has been delayed due to an internal slaughterhouse technical issue. No penalty fee will be charged (₱0.00).', style: TextStyle(color: Color(0xFFC2410C), fontSize: 12)),
                      const SizedBox(height: 16),
                      const Text('Reason for Delay *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _delayReasonCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Describe the technical error or reason for delay...',
                          hintStyle: const TextStyle(color: Colors.black, fontSize: 13),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('Slaughterhouse Facility Delay: ₱0.00 Penalty Fee (No charge to customer for facility delay).', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF15803D))),
                    ],
                  ),
                ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),

              // Missed Schedule / Wasted Slot Penalty Section
              Builder(
                builder: (context) {
                  final schedPref = widget.request['preferred_date']?.toString();
                  String schedDisplay = 'scheduled date';
                  if (schedPref != null && schedPref.isNotEmpty) {
                    try {
                      schedDisplay = DateFormat('MMMM d, yyyy').format(DateTime.parse(schedPref));
                    } catch (_) {
                      schedDisplay = schedPref;
                    }
                  }
                  final bool isRepeat = _customerPriorMissedCount >= 1;
                  final Color cardBg = !_isMissedSchedule
                      ? const Color(0xFFF9FAFB)
                      : (isRepeat ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB));
                  final Color cardBorder = !_isMissedSchedule
                      ? Colors.grey.shade300
                      : (isRepeat ? const Color(0xFFEF4444) : const Color(0xFFFDE68A));
                  final Color primaryTextColor = !_isMissedSchedule
                      ? Colors.black87
                      : (isRepeat ? const Color(0xFF991B1B) : const Color(0xFF92400E));
                  final Color checkboxActiveColor = isRepeat ? const Color(0xFFDC2626) : const Color(0xFFD97706);

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: _isMissedSchedule,
                              activeColor: checkboxActiveColor,
                              onChanged: (v) => setState(() => _isMissedSchedule = v ?? false),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                !_isMissedSchedule
                                    ? 'Missed Schedule / Wasted Slot Check'
                                    : (isRepeat
                                        ? 'Missed Schedule (Repeat Offense #${_customerPriorMissedCount + 1} — ₱500.00 Penalty)'
                                        : 'Missed Schedule (1st Offense — Formal Warning)'),
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: primaryTextColor,
                                ),
                              ),
                            ),
                            if (_isMissedSchedule)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isRepeat ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isRepeat ? const Color(0xFFFCA5A5) : const Color(0xFFFCD34D),
                                  ),
                                ),
                                child: Text(
                                  isRepeat ? '₱500.00 Penalty' : '₱0.00 Fee Waived',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isRepeat ? const Color(0xFFB91C1C) : const Color(0xFFB45309),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 36, right: 8, bottom: 4),
                          child: Text(
                            !_isMissedSchedule
                                ? 'Check if the customer arrived on a date later than their scheduled reservation ($schedDisplay).'
                                : (isRepeat
                                    ? 'Repeat Violation: Customer has $_customerPriorMissedCount previous missed schedule violation(s) on record. Under abattoir regulations, the statutory ₱500.00 Wasted Slot Penalty is automatically added to their cashiering bill.'
                                    : '1st Offense Grace Policy: The customer failed to arrive on their scheduled slot ($schedDisplay). Valid excuses are granted grace with ₱0 penalty fee on their 1st offense. A formal warning notice will be issued to their mobile account explaining that subsequent missed bookings will incur an automatic ₱500 penalty.'),
                            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16)),
                    child: const Text('Cancel', style: TextStyle(color: Colors.black87)),
                  ),
                  const SizedBox(width: 12),
                  if (_technicalError)
                    ElevatedButton(
                      onPressed: _isLoading ? null : () => _updateProcess(notifyDelay: true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC2410C),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Notify Facility Delay (₱0 Fee)', style: TextStyle(color: Colors.white)),
                    )
                  else
                    ElevatedButton(
                      onPressed: _isLoading ? null : () => _updateProcess(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Update Process', style: TextStyle(color: Colors.white)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabelValue(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildInspectorField() {
    // If only one inspector is configured in the system, show automatically with no other options
    if (_inspectors.length <= 1) {
      final name = _selectedInspector ?? (_inspectors.isNotEmpty ? _inspectors.first : 'Official Meat Inspector');
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_user_outlined, size: 18, color: Color(0xFF2D6A4F)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2D3748),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFE6F9F0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Inspector',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A8C62),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // If multiple inspectors (e.g. 2, 3, or more) are configured, all are available for selection
    final currentValue = _inspectors.contains(_selectedInspector)
        ? _selectedInspector
        : _inspectors.first;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: currentValue,
          icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF4A5568)),
          items: _inspectors.map((inspectorName) {
            return DropdownMenuItem<String>(
              value: inspectorName,
              child: Row(
                children: [
                  const Icon(Icons.person_outline, size: 16, color: Color(0xFF2D6A4F)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      inspectorName,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedInspector = val;
                _inspectorCtrl.text = val;
              });
            }
          },
        ),
      ),
    );
  }
}

class _MICDialog extends StatefulWidget {
  final Map<String, dynamic> request;
  final SupabaseClient supabase;
  final VoidCallback onDone;

  const _MICDialog({
    required this.request,
    required this.supabase,
    required this.onDone,
  });

  @override
  State<_MICDialog> createState() => _MICDialogState();
}

class _MICDialogState extends State<_MICDialog> {
  bool _isPrinting = false;

  Future<void> _printAndProcessMIC() async {
    setState(() => _isPrinting = true);
    try {
      final pdfBytes = await InspectionDocumentsPdfGenerator.generateMIC(
        request: widget.request,
      );
      final reqId = widget.request['id'];
      final certNo = 'MIC-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';

      // 1. Open print page
      await Printing.layoutPdf(
        name: 'MIC_$certNo.pdf',
        onLayout: (format) async => pdfBytes,
      );

      // 2. Automatically update database status to mic_generated if not already paid or released
      final currentStatus = widget.request['status']?.toString();
      final isAlreadyReleased = currentStatus == 'released' || widget.request['released_at'] != null;
      final isAlreadyPaid = currentStatus == 'paid';

      if (!isAlreadyReleased && !isAlreadyPaid) {
        await widget.supabase.from('requests').update({
          'status': 'mic_generated',
        }).eq('id', reqId);
      }

      final existing = await widget.supabase.from('slaughter_inspection').select('id, process_notes').eq('request_id', reqId).maybeSingle();
      if (existing != null) {
        String notes = (existing['process_notes'] ?? '').toString();
        if (!notes.contains('MIC Generated')) {
          notes = notes.isEmpty ? 'MIC Generated' : '$notes | MIC Generated';
        }
        await widget.supabase.from('slaughter_inspection').update({
          'process_stage': 'Complete',
          'process_notes': notes,
        }).eq('request_id', reqId);
      }

      // 3. Notify customer safely
      final userId = widget.request['user_id']?.toString() ?? widget.request['customer_id']?.toString();
      if (userId != null && userId.isNotEmpty) {
        await NotificationService.sendNotificationSafely(
          widget.supabase,
          userId: userId,
          title: 'Meat Inspection Certificate Ready',
          message: 'Your Meat Inspection Certificate ($certNo) has been issued and printed. Meat is ready for releasing.',
          type: 'mic_generated',
          data: {
            'request_id': reqId,
            'certificate_number': certNo,
            'status': 'mic_generated',
          },
        );
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onDone();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Meat Inspection Certificate ($certNo) printed and marked as processed!'),
            backgroundColor: const Color(0xFF2D6A4F),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error printing MIC: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final certNo = 'MIC-${DateTime.now().year}-${widget.request['id'].toString().padLeft(3, '0')}';
    final refNo = 'MI-${DateTime.now().year}-${widget.request['id'].toString().padLeft(3, '0')}';
    final customerName = widget.request['customer_name']?.toString() ?? '—';
    final livestock = widget.request['livestock_type']?.toString() ?? '—';
    final slaughterDate = widget.request['rescheduled_date'] ?? widget.request['preferred_date'];
    
    final antiMortem = widget.request['anti_mortem']?.toString().toUpperCase() ?? 'PENDING';
    final postMortem = widget.request['post_mortem']?.toString().toUpperCase() ?? 'PENDING';
    final inspector = widget.request['inspector_name']?.toString() ?? '—';

    String formatDate(dynamic v) {
      if (v == null) return '—';
      try {
        return DateFormat('dd/MM/yyyy').format(DateTime.parse(v.toString()));
      } catch (_) {
        return v.toString();
      }
    }

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Image.asset('assets/images/logo1.png', width: 70, height: 70, errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 70)),
                  const Text('MEAT INSPECTION CERTIFICATE', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Image.asset('assets/images/logo2.png', width: 70, height: 70, errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 70)),
                ],
              ),
              const SizedBox(height: 32),
              Text('Certificated Number: $certNo', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              Text('Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 24),
              Text('Customer: $customerName', style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 4),
              Text('Reference Number: $refNo', style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 4),
              Text('Livestock Type: $livestock', style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 4),
              Text('Slaughter Date: ${formatDate(slaughterDate)}', style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 32),
              Text('ANTE-MORTEM INSPECTION: $antiMortem', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              Text('POST-MORTEM INSPECTION: $postMortem', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              Text('Inspector: $inspector', style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 32),
              const Text(
                'This Certificate of Inspection and Approval verifies that the meat '
                'product has undergone a comprehensive and systematic examination. '
                'The findings confirm that the product fully adheres to all prescribed '
                'health and sanitation standards, food safety regulations, and quality '
                'controls currently in effect. Consequently, this approval is granted, '
                'certifying the meat as fit for consumption by the general public.',
                style: TextStyle(height: 1.6, fontSize: 14),
                textAlign: TextAlign.justify,
              ),
              const SizedBox(height: 32),
              const Text('Facility: Tabaco City Slaughterhouse', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 40),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: _isPrinting ? null : _printAndProcessMIC,
                  icon: _isPrinting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.print, size: 18, color: Colors.white),
                  label: Text(_isPrinting ? 'Printing...' : 'Print', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D6A4F),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CondemnationSlipDialog extends StatefulWidget {
  final Map<String, dynamic> request;
  final String condemnationReason;
  final String inspectorName;
  final String carcassWeight;
  final SupabaseClient supabase;
  final VoidCallback onDone;

  const _CondemnationSlipDialog({
    required this.request,
    required this.condemnationReason,
    required this.inspectorName,
    required this.carcassWeight,
    required this.supabase,
    required this.onDone,
  });

  @override
  State<_CondemnationSlipDialog> createState() => _CondemnationSlipDialogState();
}

class _CondemnationSlipDialogState extends State<_CondemnationSlipDialog> {
  bool _isPrinting = false;

  Future<void> _printAndProcessCondemnationSlip() async {
    setState(() => _isPrinting = true);
    try {
      final pdfBytes = await InspectionDocumentsPdfGenerator.generateCondemnationSlip(
        request: widget.request,
        condemnationReason: widget.condemnationReason,
        inspectorName: widget.inspectorName,
        carcassWeight: widget.carcassWeight,
      );
      final reqId = widget.request['id'];
      final refNo = 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';

      // 1. Open print page
      await Printing.layoutPdf(
        name: 'Condemnation_Slip_$refNo.pdf',
        onLayout: (format) async => pdfBytes,
      );

      // 2. Automatically update database status to condemned and concluded
      await widget.supabase.from('requests').update({
        'status': 'condemned',
      }).eq('id', reqId);

      final existing = await widget.supabase.from('slaughter_inspection').select('id').eq('request_id', reqId).maybeSingle();
      if (existing != null) {
        await widget.supabase.from('slaughter_inspection').update({
          'post_mortem': 'Failed',
          'process_stage': 'Post-Mortem Inspection',
          'condemnation_reason': widget.condemnationReason,
        }).eq('request_id', reqId);
      } else {
        await widget.supabase.from('slaughter_inspection').insert({
          'request_id': reqId,
          'post_mortem': 'Failed',
          'process_stage': 'Post-Mortem Inspection',
          'condemnation_reason': widget.condemnationReason,
        });
      }

      // 3. Notify customer safely
      final userId = widget.request['user_id']?.toString() ?? widget.request['customer_id']?.toString();
      if (userId != null && userId.isNotEmpty) {
        final livestock = widget.request['livestock_type'] ?? 'Livestock';
        await NotificationService.sendNotificationSafely(
          widget.supabase,
          userId: userId,
          title: 'Slaughter Condemned — Condemnation Slip Issued',
          message: 'A condemnation slip has been issued for your livestock ($livestock). The slaughter operation has been concluded.',
          type: 'condemnation_slip',
          data: {
            'request_id': reqId,
            'condemnation_reason': widget.condemnationReason,
            'status': 'condemned',
          },
        );
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onDone();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Condemnation slip printed and operation marked concluded!'),
            backgroundColor: Color(0xFF2D6A4F),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error printing slip: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customerName = widget.request['customer_name']?.toString() ?? '—';
    final livestock = widget.request['livestock_type']?.toString() ?? '—';
    final animalCount = widget.request['animal_count']?.toString() ?? '—';
    final dateNow = DateFormat('dd/MM/yyyy').format(DateTime.now());
    final timeNow = DateFormat('hh:mm a').format(DateTime.now());

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        width: 650,
        padding: const EdgeInsets.all(32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Header with logos
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Image.asset('assets/images/logo1.png', width: 60, height: 60,
                      errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 60)),
                  const Column(
                    children: [
                      Text('Republic of the Philippines', style: TextStyle(fontSize: 12)),
                      Text('Province of Albay', style: TextStyle(fontSize: 12)),
                      Text('CITY OF TABACO', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Image.asset('assets/images/logo2.png', width: 60, height: 60,
                      errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 60)),
                ],
              ),
              const SizedBox(height: 20),

              // Info fields
              Row(
                children: [
                  Expanded(
                    child: _infoLine('Name of Establishment:', 'Tabaco City Slaughterhouse'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: _infoLine('City:', 'Tabaco City')),
                  const SizedBox(width: 16),
                  Expanded(child: _infoLine('Province:', 'Albay')),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: _infoLine('Date:', dateNow)),
                  const SizedBox(width: 16),
                  Expanded(child: _infoLine('Time:', timeNow)),
                ],
              ),
              const SizedBox(height: 24),

              // Title
              const Text(
                'CONDEMNATION SLIP',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2),
              ),
              const SizedBox(height: 16),

              // Legal text
              const Text(
                'Pursuant to Republic Act No. 7394, otherwise known as the Consumer Act of the Philippines '
                'under Article 10 and 17; and Republic Act 9296 "The Meat Inspection Code of the Philippines" and '
                'the Department of Agriculture Administrative Order No. 7, Rules, and Regulations of RA 9296 series '
                'of 2005; and NMIS Administrative Order No. 6 the following meat/meat products/processed meat is '
                'hereby condemned.',
                style: TextStyle(fontSize: 11, height: 1.5),
                textAlign: TextAlign.justify,
              ),
              const SizedBox(height: 20),

              // Table
              Table(
                border: TableBorder.all(color: Colors.black87, width: 1),
                columnWidths: const {
                  0: FlexColumnWidth(2),
                  1: FlexColumnWidth(1.5),
                  2: FlexColumnWidth(2),
                },
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: Color(0xFFF5F5F5)),
                    children: [
                      _tableHeader('FOOD ANIMAL/MEAT/MEAT\nPRODUCTS/PROCESS MEAT'),
                      _tableHeader('QUANTITY/WEIGHT'),
                      _tableHeader('CAUSE OF CONDEMNATION'),
                    ],
                  ),
                  TableRow(
                    children: [
                      _tableCell(livestock),
                      _tableCell('$animalCount head(s)${widget.carcassWeight.isNotEmpty ? '\n${widget.carcassWeight}kg' : ''}'),
                      _tableCell(widget.condemnationReason.isNotEmpty ? widget.condemnationReason : '—'),
                    ],
                  ),
                  // Empty rows for additional entries
                  TableRow(children: [_tableCell(''), _tableCell(''), _tableCell('')]),
                  TableRow(children: [_tableCell(''), _tableCell(''), _tableCell('')]),
                ],
              ),
              const SizedBox(height: 28),

              // Signatures
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Condemned by:', style: TextStyle(fontSize: 12)),
                        const SizedBox(height: 28),
                        Container(
                          width: 200,
                          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black54))),
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(widget.inspectorName.isNotEmpty ? widget.inspectorName : '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        const Text('Veterinarian/Meat Control Officer/Meat Inspector', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500)),
                        const Text('(Signature Over Printed Name)', style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Conforme:', style: TextStyle(fontSize: 12)),
                        const SizedBox(height: 28),
                        Container(
                          width: 200,
                          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black54))),
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(customerName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        const Text('Name of Owner/Representative', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500)),
                        const Text('(Signature Over Printed Name)', style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Disposed by / Witness
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Disposed by:', style: TextStyle(fontSize: 12)),
                        const SizedBox(height: 28),
                        Container(
                          width: 200,
                          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black54))),
                          padding: const EdgeInsets.only(bottom: 2),
                        ),
                        const Text('Veterinarian/Meat Control Officer/Meat Inspector', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500)),
                        const Text('(Signature Over Printed Name)', style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Witness:', style: TextStyle(fontSize: 12)),
                        const SizedBox(height: 28),
                        Container(
                          width: 200,
                          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black54))),
                          padding: const EdgeInsets.only(bottom: 2),
                        ),
                        const Text('(Signature Over Printed Name)', style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Print button
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: _isPrinting ? null : _printAndProcessCondemnationSlip,
                  icon: _isPrinting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.print, size: 18, color: Colors.white),
                  label: Text(_isPrinting ? 'Printing...' : 'Print', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D6A4F),
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoLine(String label, String value) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        const SizedBox(width: 4),
        Expanded(
          child: Container(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black54))),
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ),
        ),
      ],
    );
  }

  Widget _tableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
    );
  }

  Widget _tableCell(String text) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(text, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  ANTE-MORTEM RESPONSE DIALOG
//  Admin handles the customer's response (confine or take back)
// ═══════════════════════════════════════════════════════════
class _AntiMortemResponseDialog extends StatefulWidget {
  final Map<String, dynamic> request;
  final SupabaseClient supabase;
  final VoidCallback onDone;

  const _AntiMortemResponseDialog({
    required this.request,
    required this.supabase,
    required this.onDone,
  });

  @override
  State<_AntiMortemResponseDialog> createState() => _AntiMortemResponseDialogState();
}

class _AntiMortemResponseDialogState extends State<_AntiMortemResponseDialog> {
  bool _isLoading = false;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  final _notesCtrl = TextEditingController();
  late String _manualDecision;

  bool get _isTechnicalDelay {
    final status = widget.request['status']?.toString();
    final stage = widget.request['process_stage']?.toString();
    final insp = widget.request['slaughter_inspection'];
    String? inspStage;
    if (insp is Map) inspStage = insp['process_stage']?.toString();
    return status == 'delay_error' ||
        stage == 'Technical Error/Delay' ||
        inspStage == 'Technical Error/Delay';
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.request['anti_mortem_response']?.toString() ?? '';
    if (existing.isNotEmpty) {
      _manualDecision = existing;
    } else {
      _manualDecision = _isTechnicalDelay ? 'accept_penalty' : 'confine';
    }
  }

  String get _response {
    final existing = widget.request['anti_mortem_response']?.toString() ?? '';
    return existing.isNotEmpty ? existing : _manualDecision;
  }

  bool get _hasCustomerAppResponse =>
      (widget.request['anti_mortem_response']?.toString() ?? '').isNotEmpty;
  bool get _isPenaltyAccepted => _response == 'accept_penalty';
  bool get _isConfine => _response == 'confine';
  bool get _isTakeBack => _response == 'take_back';

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) setState(() => _selectedDate = date);
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
    );
    if (time != null) setState(() => _selectedTime = time);
  }

  Future<void> _markDelayResolvedAndReleasable() async {
    setState(() => _isLoading = true);
    try {
      final reqId = widget.request['id'];
      final userId = widget.request['user_id'];
      final livestockType = widget.request['livestock_type'] ?? 'Livestock';
      final animalCount = widget.request['animal_count'] ?? 1;
      final refNo = 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';

      // 1. Update request status to releasable
      await widget.supabase.from('requests').update({
        'status': 'releasable',
      }).eq('id', reqId);

      // 2. Update slaughter_inspection to Complete & Passed
      final existing = await widget.supabase.from('slaughter_inspection').select('id').eq('request_id', reqId).maybeSingle();
      final defaultInspector = AppSettingsService.instance.configuredInspectors.isNotEmpty
          ? AppSettingsService.instance.configuredInspectors.first
          : 'Official Meat Inspector';
      final existingInsp = widget.request['inspector_name']?.toString().trim();
      final resolvedInsp = (existingInsp != null && existingInsp.isNotEmpty) ? existingInsp : defaultInspector;

      final inspectionData = {
        'request_id': reqId,
        'anti_mortem': 'Passed',
        'process_stage': 'Complete',
        'post_mortem': 'Passed',
        'inspector_name': resolvedInsp,
        'process_notes': _notesCtrl.text.isNotEmpty
            ? _notesCtrl.text
            : 'Technical delay resolved. Resumed slaughter completed successfully.',
      };
      if (existing != null) {
        await widget.supabase.from('slaughter_inspection').update(inspectionData).eq('request_id', reqId);
      } else {
        await widget.supabase.from('slaughter_inspection').insert(inspectionData);
      }

      // 3. Notify customer
      final isMarketOrder = (widget.request['request_type'] ?? '').toString().toLowerCase() == 'market';
      final delayTitle = isMarketOrder
          ? '$livestockType — Slaughter Complete & Ready for Delivery'
          : '$livestockType — Slaughter Complete & Ready for Collection';
      final delayMessage = isMarketOrder
          ? 'Your $animalCount head(s) of $livestockType ($refNo) slaughter has resumed and completed successfully. Market delivery is scheduled — please settle payment via GCash or cashier to clear your carcass for delivery dispatch.'
          : 'Your $animalCount head(s) of $livestockType ($refNo) slaughter has resumed and completed successfully. Under Cash-on-Pickup, please settle payment at the cashier counter upon arrival before carcass handover. Reminder: Claim before 5:00 PM to avoid cold storage preservation fees.';

      await NotificationService.sendNotificationSafely(
        widget.supabase,
        userId: userId,
        title: delayTitle,
        message: delayMessage,
        type: 'slaughter_completed',
        data: {
          'request_id': reqId,
          'livestock_type': livestockType,
          'penalty_fee': (widget.request['penalty_fee'] != null && (double.tryParse(widget.request['penalty_fee'].toString()) ?? 0.0) > 0)
              ? (double.tryParse(widget.request['penalty_fee'].toString()) ?? 500.0)
              : 0.0,
        },
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onDone();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Operation delay resolved! Status set to Releasable.'),
            backgroundColor: Colors.green.shade600,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submit() async {
    final reqId = widget.request['id'];
    final userId = widget.request['user_id'];
    final livestockType = widget.request['livestock_type'] ?? 'Livestock';

    if (_isTakeBack) {
      if (_selectedDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a pickup date'), backgroundColor: Colors.orange),
        );
        return;
      }
      setState(() => _isLoading = true);
      try {
        DateTime pickupDateTime = _selectedDate!;
        if (_selectedTime != null) {
          pickupDateTime = DateTime(
            _selectedDate!.year, _selectedDate!.month, _selectedDate!.day,
            _selectedTime!.hour, _selectedTime!.minute,
          );
        }
        final dateStr = DateFormat('MMMM d, yyyy').format(_selectedDate!);
        final timeStr = _selectedTime != null ? _selectedTime!.format(context) : '8:00 AM';

        await widget.supabase.from('requests').update({
          'anti_mortem_response': 'take_back',
          'anti_mortem_response_at': DateTime.now().toIso8601String(),
          'status': 'pickup_scheduled',
          'pickup_approved': true,
          'pickup_time': pickupDateTime.toIso8601String(),
        }).eq('id', reqId);

        final penaltyWaivedNote = _isTechnicalDelay ? ' Technical delay penalty fee has been waived.' : '';
        await NotificationService.sendNotificationSafely(
          widget.supabase,
          userId: userId,
          title: '$livestockType — Pickup Scheduled',
          message: 'Your livestock pickup has been scheduled for $dateStr at $timeStr at the Tabaco City Slaughterhouse corral.$penaltyWaivedNote Please present your reference # and valid ID upon arrival.',
          type: 'pickup_approved',
          data: {
            'request_id': reqId,
            'livestock_type': livestockType,
            'pickup_date': _selectedDate!.toIso8601String(),
            'pickup_time': timeStr,
            'admin_notes': _notesCtrl.text,
            'penalty_fee': 0.0,
          },
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Pickup scheduled for $dateStr at $timeStr. Customer notified.'), backgroundColor: Colors.green.shade600),
          );
          Navigator.pop(context);
          widget.onDone();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    } else if (_isPenaltyAccepted && _isTechnicalDelay) {
      if (_selectedDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a rescheduled slaughter date'), backgroundColor: Colors.orange),
        );
        return;
      }
      setState(() => _isLoading = true);
      try {
        final dateStr = DateFormat('MMMM d, yyyy').format(_selectedDate!);
        await widget.supabase.from('requests').update({
          'anti_mortem_response': 'accept_penalty',
          'anti_mortem_response_at': DateTime.now().toIso8601String(),
          'rescheduled_date': _selectedDate!.toIso8601String().split('T')[0],
        }).eq('id', reqId);

        await NotificationService.sendNotificationSafely(
          widget.supabase,
          userId: userId,
          title: '$livestockType — Rescheduled Slaughter Confirmed',
          message: 'Your slaughter operation has been rescheduled for $dateStr following the facility technical delay. No penalty fee is charged for facility delay (₱0.00).',
          type: 'confine_confirmed',
          data: {
            'request_id': reqId,
            'livestock_type': livestockType,
            'new_date': _selectedDate!.toIso8601String(),
            'admin_notes': _notesCtrl.text,
            'penalty_fee': 0.0,
          },
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Resumed slaughter date set to $dateStr. Customer notified.'), backgroundColor: Colors.green.shade600),
          );
          Navigator.pop(context);
          widget.onDone();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    } else if (_isConfine) {
      setState(() => _isLoading = true);
      try {
        await widget.supabase.from('requests').update({
          'anti_mortem_response': 'confine',
          'anti_mortem_response_at': DateTime.now().toIso8601String(),
          'status': 'confined',
        }).eq('id', reqId);

        await NotificationService.sendNotificationSafely(
          widget.supabase,
          userId: userId,
          title: '$livestockType — Confinement Under Observation',
          message: 'Your livestock has been placed into quarantine/confinement at the slaughterhouse under veterinary observation (₱0 penalty). You will be notified once cleared.',
          type: 'confine_confirmed',
          data: {
            'request_id': reqId,
            'livestock_type': livestockType,
            'admin_notes': _notesCtrl.text,
            'penalty_fee': 0.0,
          },
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: const Text('Livestock placed in confinement. Customer notified.'), backgroundColor: Colors.blue.shade700),
          );
          Navigator.pop(context);
          widget.onDone();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = 'MI-${DateTime.now().year}-${widget.request['id'].toString().padLeft(3, '0')}';
    final cust = widget.request['customer_name']?.toString() ?? 'Unknown';
    final livestock = widget.request['livestock_type']?.toString() ?? '—';
    final respondedAt = widget.request['anti_mortem_response_at'];

    final headerIcon = _isTechnicalDelay
        ? (_isPenaltyAccepted ? Icons.calendar_month : Icons.undo)
        : (_isConfine ? Icons.local_hospital : Icons.undo);
    final headerColor = _isTechnicalDelay
        ? (_isPenaltyAccepted ? Colors.green.shade600 : Colors.deepOrange.shade600)
        : (_isConfine ? Colors.blue.shade600 : Colors.deepOrange.shade600);
    final headerBg = _isTechnicalDelay
        ? (_isPenaltyAccepted ? Colors.green.shade50 : Colors.deepOrange.shade50)
        : (_isConfine ? Colors.blue.shade50 : Colors.deepOrange.shade50);

    final titleText = _isTechnicalDelay
        ? (_isPenaltyAccepted
            ? 'Technical Delay: Reschedule Slaughter (₱500 Fee)'
            : 'Technical Delay: Take Livestock Back')
        : (_isConfine
            ? 'Customer Chose: Confine'
            : 'Customer Chose: Take Back');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: headerBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(headerIcon, color: headerColor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titleText,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Ref: $ref • $cust • ${_isTechnicalDelay ? "Technical Delay" : "Ante-Mortem Inspection"}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Manual Entry when customer has not responded via app
              if (!_hasCustomerAppResponse) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.phone_in_talk, size: 16, color: Colors.amber.shade900),
                          const SizedBox(width: 8),
                          Text(
                            'Walk-In / Phone Decision Entry (Customer has not responded via App)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_isTechnicalDelay)
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'accept_penalty',
                              label: Text('Reschedule (₱500 Fee)', style: TextStyle(fontSize: 12)),
                              icon: Icon(Icons.calendar_month, size: 14),
                            ),
                            ButtonSegment(
                              value: 'take_back',
                              label: Text('Take Back', style: TextStyle(fontSize: 12)),
                              icon: Icon(Icons.undo, size: 14),
                            ),
                          ],
                          selected: {_manualDecision == 'accept_penalty' || _manualDecision == 'take_back' ? _manualDecision : 'accept_penalty'},
                          onSelectionChanged: (s) => setState(() => _manualDecision = s.first),
                        )
                      else
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'confine',
                              label: Text('Confine (Observation)', style: TextStyle(fontSize: 12)),
                              icon: Icon(Icons.local_hospital, size: 14),
                            ),
                          ],
                          selected: const {'confine'},
                          onSelectionChanged: (s) => setState(() => _manualDecision = 'confine'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Customer response summary card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _isTechnicalDelay
                      ? (_isPenaltyAccepted ? Colors.green.shade50 : Colors.deepOrange.shade50)
                      : (_isConfine ? Colors.blue.shade50 : Colors.deepOrange.shade50),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _isTechnicalDelay
                        ? (_isPenaltyAccepted ? Colors.green.shade200 : Colors.deepOrange.shade200)
                        : (_isConfine ? Colors.blue.shade200 : Colors.deepOrange.shade200),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isTechnicalDelay
                              ? (_isPenaltyAccepted ? Icons.receipt_long : Icons.undo)
                              : (_isConfine ? Icons.local_hospital : Icons.undo),
                          size: 18,
                          color: _isTechnicalDelay
                              ? (_isPenaltyAccepted ? Colors.green.shade700 : Colors.deepOrange.shade700)
                              : (_isConfine ? Colors.blue.shade700 : Colors.deepOrange.shade700),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isTechnicalDelay
                                ? (_isPenaltyAccepted
                                    ? 'Reschedule Slaughter (₱0 Facility Delay Penalty)'
                                    : 'Take Livestock Back (₱0 Facility Delay)')
                                : (_isConfine
                                    ? 'Confine in Slaughterhouse (Quarantine / Observation)'
                                    : 'Take Livestock Back (₱0 Charge)'),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _isTechnicalDelay
                                  ? (_isPenaltyAccepted ? Colors.green.shade700 : Colors.deepOrange.shade700)
                                  : (_isConfine ? Colors.blue.shade700 : Colors.deepOrange.shade700),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _detailRow('Livestock:', livestock),
                    _detailRow('Customer:', cust),
                    if (_isTechnicalDelay && _isPenaltyAccepted)
                      _detailRow('Terms:', 'Customer agrees to ₱500 legal finality fee to reschedule operation.')
                    else if (_isTechnicalDelay && _isTakeBack)
                      _detailRow('Terms:', 'Livestock returned to customer. Technical delay penalty is waived (₱0).')
                    else if (!_isTechnicalDelay && _isConfine)
                      _detailRow('Terms:', 'Livestock placed in corral for veterinary observation (₱0 fee). Admin can resume slaughter once cleared.')
                    else if (!_isTechnicalDelay && _isTakeBack)
                      _detailRow('Terms:', 'Livestock returned to customer. No processing or penalty fee (₱0).'),
                    if (respondedAt != null)
                      _detailRow('Responded:', DateFormat('MMM d, yyyy h:mm a').format(DateTime.parse(respondedAt.toString()))),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Action section
              Text(
                _isTechnicalDelay
                    ? (_isPenaltyAccepted
                        ? 'Set Rescheduled Slaughter Date'
                        : 'Schedule Livestock Pickup')
                    : (_isConfine
                        ? 'Confirm Slaughterhouse Confinement'
                        : 'Schedule Livestock Pickup'),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF4A5568)),
              ),
              const SizedBox(height: 4),
              Text(
                _isTechnicalDelay
                    ? (_isPenaltyAccepted
                        ? 'Select the date when this livestock slaughter will resume. The ₱500 legal finality fee will be applied to the customer\'s bill.'
                        : 'Approve a date and time for the customer to pick up their livestock. Technical delay penalty is waived (₱0).')
                    : (_isConfine
                        ? 'Confirm that this livestock is placed in facility confinement for veterinary observation. No penalty fee will be charged. Once cleared by the veterinarian, click "Cleared & Ready for Slaughter" on the table to resume.'
                        : 'Approve a date and time for the customer to pick up their livestock. (₱0 fee applies).'),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),

              // Date picker (for reschedule or pickup)
              if (_isTakeBack || (_isTechnicalDelay && _isPenaltyAccepted)) ...[
                InkWell(
                  onTap: _pickDate,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 18, color: Color(0xFF4A5568)),
                        const SizedBox(width: 10),
                        Text(
                          _selectedDate != null
                              ? DateFormat('MMMM d, yyyy').format(_selectedDate!)
                              : (_isTakeBack ? 'Select pickup date...' : 'Select rescheduled slaughter date...'),
                          style: TextStyle(
                            fontSize: 14,
                            color: _selectedDate != null ? Colors.black87 : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // Time picker (only for take back pickup)
              if (_isTakeBack) ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickTime,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time, size: 18, color: Color(0xFF4A5568)),
                        const SizedBox(width: 10),
                        Text(
                          _selectedTime != null
                              ? _selectedTime!.format(context)
                              : 'Select pickup time...',
                          style: TextStyle(
                            fontSize: 14,
                            color: _selectedTime != null ? Colors.black87 : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 12),
              const Text('Admin Notes (optional)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A5568))),
              const SizedBox(height: 6),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Add any notes for the customer...',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
              ),

              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                    child: const Text('Cancel', style: TextStyle(color: Colors.black87)),
                  ),
                  if (_isTechnicalDelay && _isPenaltyAccepted)
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _markDelayResolvedAndReleasable,
                      icon: const Icon(Icons.check_circle, size: 16, color: Colors.white),
                      label: const Text('Resolve & Set Releasable', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2D6A4F),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _submit,
                    icon: _isLoading
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Icon(
                            _isTakeBack
                                ? Icons.schedule
                                : (_isTechnicalDelay ? Icons.calendar_month : Icons.local_hospital),
                            size: 16,
                            color: Colors.white,
                          ),
                    label: Text(
                      _isLoading
                          ? 'Saving...'
                          : _isTakeBack
                              ? 'Schedule Pickup & Notify'
                              : (_isTechnicalDelay
                                  ? 'Set Rescheduled Date & Notify'
                                  : 'Confirm Confinement & Notify'),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isTakeBack
                          ? const Color(0xFFC0392B)
                          : (_isTechnicalDelay ? const Color(0xFF2563EB) : const Color(0xFF1E855A)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    ),
  );
}

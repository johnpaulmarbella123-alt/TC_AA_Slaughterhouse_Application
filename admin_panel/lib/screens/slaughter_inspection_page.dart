import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../services/notification_service.dart';
import '../services/inspection_documents_pdf_generator.dart';

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

  @override
  void initState() {
    super.initState();
    _loadRequests();
    _subscribeRealtime();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _loadRequests(silent: true);
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
      // Fetch requests that are past Document Verification (doc_verified) or in slaughter phases.
      final data = await supabase
          .from('requests')
          .select('*, slaughter_inspection(*)')
          .inFilter('status', ['doc_verified', 'slaughter_started', 'releasable', 'delay_error', 'completed', 'anti_mortem_failed', 'post_mortem_failed', 'condemned', 'mic_generated'])
          .order('created_at', ascending: false);
      
      final activeRequests = List<Map<String, dynamic>>.from(data).map((r) {
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
              items: ['All', 'Anti-Mortem', 'Preparation', 'Stunning', 'Bleeding', 'Scalding/Plucking', 'Evisceration', 'Post-Mortem Inspection', 'Weighing', 'MIC', 'Complete', 'Technical Error/Delay']
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
          Scrollbar(
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
                constraints: const BoxConstraints(minWidth: 1200),
                child: DataTable(
                headingRowColor: WidgetStateProperty.all(const Color(0xFFF7FAFC)),
                dataRowMinHeight: 60,
                dataRowMaxHeight: 80,
                columnSpacing: 30,
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
                  final isAntiMortemFailed = status == 'anti_mortem_failed';
                  final isPostMortemFailed = status == 'post_mortem_failed';
                  final isCondemnedStatus = status == 'condemned';
                  final isCondemned = req['condemnation_reason'] != null || isCondemnedStatus;
                  final isCondemnationAcknowledged = req['condemnation_acknowledged'] == true || isCondemnedStatus;
                  final customerResponse = req['anti_mortem_response']?.toString();

                  return DataRow(cells: [
                    DataCell(Text(ref, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12))),
                    DataCell(Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(req['customer_name']?.toString() ?? '—', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        Text('09xx', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      ],
                    )),
                    DataCell(Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${req['animal_count']} head(s)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        Text('${req['livestock_type'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
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
                    DataCell(_buildBadge(
                      stage,
                      stage == 'Complete' ? Colors.green : (stage == 'Anti-Mortem' ? Colors.red : Colors.grey),
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
                                      : customerResponse == 'accept_penalty' || customerResponse == 'confine'
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
                          : isAntiMortemFailed || isPostMortemFailed
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
                                            isAntiMortemFailed ? 'Anti-Mortem Failed' : 'Post-Mortem Failed',
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
                                                'Delay due to technical error',
                                                style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          customerResponse == 'take_back'
                                              ? 'Penalty: Waived'
                                              : 'Penalty: ₱${req['penalty_fee'] ?? '500.00'}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: customerResponse == 'take_back' ? Colors.grey.shade700 : Colors.red.shade700,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
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
                          OutlinedButton(
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
                          if ((isAntiMortemFailed || isDelayed) && customerResponse != null) ...[
                            const SizedBox(width: 6),
                            OutlinedButton(
                              onPressed: () => _openAntiMortemResponseDialog(req),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                minimumSize: const Size(0, 32),
                                side: BorderSide(color: Colors.blue.shade300),
                              ),
                              child: Text('Respond', style: TextStyle(fontSize: 12, color: Colors.blue.shade600)),
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

  bool _healthIssueDetected = false;
  final _condemnationCtrl = TextEditingController();

  bool _technicalError = false;
  final _delayReasonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final req = widget.request;
    _antiMortem = req['anti_mortem'] ?? 'Pending';
    final validStages = ['Anti-Mortem', 'Preparation', 'Stunning', 'Bleeding', 'Scalding/Plucking', 'Evisceration', 'Post-Mortem Inspection', 'Weighing', 'MIC', 'Complete', 'Technical Error/Delay'];
    final reqStage = req['process_stage'] ?? 'Preparation';
    _processStage = validStages.contains(reqStage) ? reqStage : 'Preparation';
    _postMortem = req['post_mortem'] ?? 'Pending';
    if (req['carcass_weight'] != null) _carcassCtrl.text = req['carcass_weight'].toString();
    if (req['inspector_name'] != null) _inspectorCtrl.text = req['inspector_name'].toString();
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
  }

  Future<void> _updateProcess({bool notifyDelay = false}) async {
    setState(() => _isLoading = true);
    try {
      final reqId = widget.request['id'];
      final userId = widget.request['user_id'];
      // refNo could be used in future for logging
      // final refNo = 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';

      // Validate inputs if needed...
      
      String newStatus = widget.request['status'];
      String? notifTitle;
      String? notifMessage;
      String? notifType;
      Map<String, dynamic>? notifData;

      // If anti-mortem failed, set to anti_mortem_failed and notify with options
      if (_antiMortem == 'Failed') {
        newStatus = 'anti_mortem_failed';
        _processStage = 'Anti-Mortem';
        final livestockType = widget.request['livestock_type'] ?? 'Livestock';
        final vetFindings = _notesCtrl.text.isNotEmpty ? _notesCtrl.text : 'Health issue detected during ante-mortem inspection';
        notifTitle = '$livestockType — Health Issue Detected';
        notifMessage = 'Ante-mortem inspection failed. Your livestock did not pass health inspection.';
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
        notifTitle = '$livestockType Operation Delayed';
        notifMessage = '$livestockType slaughter was delayed due to a technical error$reasonSuffix. A legal finality fee of ₱500.00 will be applied. Please review and respond in your app.';
        notifType = 'operation_failed';
        notifData = {
          'request_id': reqId,
          'livestock_type': livestockType,
          'reason': delayReason,
          'penalty_fee': 500.0,
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

        notifTitle = 'Slaughter Operation Complete';
        notifMessage = 'Your $animalCount head(s) of $livestockType ($refNo) has been successfully slaughtered and passed post-mortem inspection$weightInfo. The meat is now releasable.';
        notifType = 'slaughter_completed';
        notifData = {
          'request_id': reqId,
          'livestock_type': livestockType,
          'animal_count': animalCount,
          'carcass_weight': double.tryParse(_carcassCtrl.text),
          'inspector_name': _inspectorCtrl.text,
          'post_mortem': _postMortem,
          'process_stage': _processStage,
        };
      }

      await widget.supabase.from('requests').update({
        'status': newStatus,
        if (notifyDelay) ...{
          'anti_mortem_response': null,
          'anti_mortem_response_at': null,
        },
      }).eq('id', reqId);

      final nowStr = DateTime.now().toLocal().toIso8601String().split('T')[0];
      final delayReason = _delayReasonCtrl.text.trim();
      String processNotes = _notesCtrl.text.trim();
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
              const SizedBox(height: 12),
              _buildLabelValue('Request Type', type),
              const SizedBox(height: 20),
              
              const Text('Anti-Mortem Result', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A5568))),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _antiMortem,
                    items: ['Pending', 'Passed', 'Failed'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setState(() => _antiMortem = v!),
                  ),
                ),
              ),
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
                              items: ['Anti-Mortem', 'Preparation', 'Stunning', 'Bleeding', 'Scalding/Plucking', 'Evisceration', 'Post-Mortem Inspection', 'Weighing', 'MIC', 'Complete', 'Technical Error/Delay'].map((e) => DropdownMenuItem(
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
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          ),
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
                              onChanged: (v) => setState(() => _postMortem = v!),
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
                        TextField(
                          controller: _inspectorCtrl,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          ),
                        ),
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
                      const Text('The customer will be automatically notified that their livestock slaughter has been delayed and a legal finality fee of ₱500.00 will be charged.', style: TextStyle(color: Colors.red, fontSize: 12)),
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
                      const Text('Legal Finality Fee: ₱500.00 will be automatically added to the customer\'s payment for livestock remaining under operation.', style: TextStyle(fontSize: 12)),
                    ],
                  ),
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
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Notify Customer and Apply fee', style: TextStyle(color: Colors.white)),
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
              Text('ANTI-MORTEM INSPECTION: $antiMortem', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
//  ANTI-MORTEM RESPONSE DIALOG
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

  String get _response => widget.request['anti_mortem_response']?.toString() ?? '';
  bool get _isPenaltyAccepted => _response == 'accept_penalty';
  bool get _isConfine => _response == 'confine' || _isPenaltyAccepted;
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
      final inspectionData = {
        'request_id': reqId,
        'anti_mortem': 'Passed',
        'process_stage': 'Complete',
        'post_mortem': 'Passed',
        'inspector_name': 'Admin Inspector',
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
      await NotificationService.sendNotificationSafely(
        widget.supabase,
        userId: userId,
        title: '$livestockType — Slaughter Complete & Releasable',
        message: 'Your $animalCount head(s) of $livestockType ($refNo) slaughter has resumed and completed successfully. The meat is now releasable. Penalty fee of ₱500.00 is reflected on your receipt.',
        type: 'slaughter_completed',
        data: {
          'request_id': reqId,
          'livestock_type': livestockType,
          'penalty_fee': 500.0,
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
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a date'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final reqId = widget.request['id'];
      final userId = widget.request['user_id'];
      final livestockType = widget.request['livestock_type'] ?? 'Livestock';
      final dateStr = DateFormat('MMMM d, yyyy').format(_selectedDate!);

      if (_isConfine) {
        // Admin sets new slaughter date for confined or penalty-accepted livestock
        await widget.supabase.from('requests').update({
          'rescheduled_date': _selectedDate!.toIso8601String().split('T')[0],
        }).eq('id', reqId);

        await NotificationService.sendNotificationSafely(
          widget.supabase,
          userId: userId,
          title: _isPenaltyAccepted
              ? '$livestockType — Rescheduled Slaughter Confirmed'
              : '$livestockType — Confinement Confirmed',
          message: _isPenaltyAccepted
              ? 'Your slaughter operation has been rescheduled for $dateStr following the technical delay. Legal finality fee of ₱500.00 will be added to your payment.'
              : 'Your livestock has been confined at the slaughterhouse. New slaughter schedule: $dateStr.',
          type: 'confine_confirmed',
          data: {
            'request_id': reqId,
            'livestock_type': livestockType,
            'new_date': _selectedDate!.toIso8601String(),
            'admin_notes': _notesCtrl.text,
            'penalty_fee': _isPenaltyAccepted ? 500.0 : null,
          },
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_isPenaltyAccepted
                  ? 'Resumed slaughter date set to $dateStr. Customer notified.'
                  : 'New slaughter date set to $dateStr. Customer notified.'),
              backgroundColor: Colors.green.shade600,
            ),
          );
        }
      } else if (_isTakeBack) {
        // Admin approves pickup time
        DateTime pickupDateTime = _selectedDate!;
        if (_selectedTime != null) {
          pickupDateTime = DateTime(
            _selectedDate!.year, _selectedDate!.month, _selectedDate!.day,
            _selectedTime!.hour, _selectedTime!.minute,
          );
        }

        final timeStr = _selectedTime != null
            ? _selectedTime!.format(context)
            : '8:00 AM';

        await widget.supabase.from('requests').update({
          'status': 'taken_back',
          'pickup_approved': true,
          'pickup_time': pickupDateTime.toIso8601String(),
        }).eq('id', reqId);

        await NotificationService.sendNotificationSafely(
          widget.supabase,
          userId: userId,
          title: '$livestockType — Pickup Approved',
          message: 'Your livestock pickup has been approved. Please pick up on $dateStr at $timeStr at Tabaco City Slaughterhouse.',
          type: 'pickup_approved',
          data: {
            'request_id': reqId,
            'livestock_type': livestockType,
            'pickup_date': _selectedDate!.toIso8601String(),
            'pickup_time': timeStr,
            'admin_notes': _notesCtrl.text,
          },
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Pickup approved for $dateStr at $timeStr. Customer notified.'), backgroundColor: Colors.green.shade600),
          );
        }
      }

      if (mounted) {
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

  @override
  Widget build(BuildContext context) {
    final ref = 'MI-${DateTime.now().year}-${widget.request['id'].toString().padLeft(3, '0')}';
    final cust = widget.request['customer_name']?.toString() ?? 'Unknown';
    final livestock = widget.request['livestock_type']?.toString() ?? '—';
    final respondedAt = widget.request['anti_mortem_response_at'];

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
                      color: _isConfine ? Colors.blue.shade50 : Colors.deepOrange.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isConfine ? Icons.local_hospital : Icons.undo,
                      color: _isConfine ? Colors.blue.shade600 : Colors.deepOrange.shade600,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isPenaltyAccepted
                              ? 'Customer Chose: Accept Penalty (₱500)'
                              : _isConfine
                                  ? 'Customer Chose: Confine'
                                  : 'Customer Chose: Take Back',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text('Ref: $ref • $cust', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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

              // Customer response summary card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _isPenaltyAccepted
                      ? Colors.green.shade50
                      : _isConfine
                          ? Colors.blue.shade50
                          : Colors.deepOrange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _isPenaltyAccepted
                        ? Colors.green.shade200
                        : _isConfine
                            ? Colors.blue.shade200
                            : Colors.deepOrange.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isPenaltyAccepted
                              ? Icons.receipt_long
                              : _isConfine
                                  ? Icons.local_hospital
                                  : Icons.undo,
                          size: 18,
                          color: _isPenaltyAccepted
                              ? Colors.green.shade700
                              : _isConfine
                                  ? Colors.blue.shade700
                                  : Colors.deepOrange.shade700,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isPenaltyAccepted
                              ? 'Penalty Fee Accepted (₱500.00)'
                              : _isConfine
                                  ? 'Confine in Slaughterhouse'
                                  : 'Take Livestock Back',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _isPenaltyAccepted
                                ? Colors.green.shade700
                                : _isConfine
                                    ? Colors.blue.shade700
                                    : Colors.deepOrange.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _detailRow('Livestock:', livestock),
                    _detailRow('Customer:', cust),
                    if (_isPenaltyAccepted)
                      _detailRow('Terms:', 'Agreed to ₱500 legal finality fee to keep animal in facility'),
                    if (respondedAt != null)
                      _detailRow('Responded:', DateFormat('MMM d, yyyy h:mm a').format(DateTime.parse(respondedAt.toString()))),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Action section
              Text(
                _isPenaltyAccepted
                    ? 'Set Resumption Slaughter Date'
                    : _isConfine
                        ? 'Set New Slaughter Date'
                        : 'Approve Pickup Time',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF4A5568)),
              ),
              const SizedBox(height: 4),
              Text(
                _isPenaltyAccepted
                    ? 'Select the date when this livestock slaughter will resume. The customer accepted the ₱500 fee and will be notified of the schedule.'
                    : _isConfine
                        ? 'Select a new date for when this confined livestock can be slaughtered. The customer will be notified.'
                        : 'Approve a date and time for the customer to pick up their livestock. They will be notified.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),

              // Date picker
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
                            : 'Select date...',
                        style: TextStyle(
                          fontSize: 14,
                          color: _selectedDate != null ? Colors.black87 : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Time picker (only for take back)
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
                              : 'Select time...',
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
                  if (_isPenaltyAccepted)
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
                        : Icon(_isConfine ? Icons.event_available : Icons.check_circle_outline, size: 16, color: Colors.white),
                    label: Text(
                      _isConfine ? 'Set Date & Notify' : 'Approve & Notify',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isConfine ? Colors.blue.shade600 : Colors.green.shade600,
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
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    ),
  );
}

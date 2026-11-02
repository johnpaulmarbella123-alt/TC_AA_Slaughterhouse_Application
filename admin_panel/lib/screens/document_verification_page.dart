import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/document_upload_helper.dart';
import '../services/notification_service.dart';

class DocumentVerificationPage extends StatefulWidget {
  const DocumentVerificationPage({super.key});
  @override
  State<DocumentVerificationPage> createState() => _DocumentVerificationPageState();
}

class _DocumentVerificationPageState extends State<DocumentVerificationPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _barangayRequests = [];
  List<Map<String, dynamic>> _marketRequests = [];
  List<Map<String, dynamic>> _verifiedRequests = [];
  List<Map<String, dynamic>> _cancelledRequests = [];
  bool _isLoading = true;
  final ScrollController _barangayScrollCtrl = ScrollController();
  final ScrollController _marketScrollCtrl = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  RealtimeChannel? _realtimeChannel;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _loadRequests();
    _subscribeRealtime();
    // Auto-poll every 3 seconds so approved requests appear automatically
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _loadRequests(silent: true);
    });
  }

  void _subscribeRealtime() {
    try {
      _realtimeChannel = supabase.channel('public:doc_verification_realtime')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'requests',
          callback: (payload) {
            if (mounted) _loadRequests(silent: true);
          },
        )
        ..subscribe();
    } catch (e) {
      debugPrint('Realtime subscription error in DocVerification: $e');
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    if (_realtimeChannel != null) {
      supabase.removeChannel(_realtimeChannel!);
    }
    _barangayScrollCtrl.dispose();
    _marketScrollCtrl.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);
    try {
      final all = await supabase.from('requests').select().order('created_at', ascending: false);
      final approved = all.where((r) => r['status'] == 'approved').toList();
      final verified = all.where((r) => r['status'] == 'doc_verified').toList();
      final cancelled = all.where((r) => r['status'] == 'cancelled').toList();
      if (mounted) {
        setState(() {
          _barangayRequests = List<Map<String, dynamic>>.from(approved.where((r) => r['request_type'] == 'barangay'));
          _marketRequests = List<Map<String, dynamic>>.from(approved.where((r) => r['request_type'] == 'market'));
          _verifiedRequests = List<Map<String, dynamic>>.from(verified);
          _cancelledRequests = List<Map<String, dynamic>>.from(cancelled);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('DocVerification load error: ${e.toString()}');
      if (mounted && !silent) {
        setState(() => _isLoading = false);
      }
    }
  }
  Future<void> _rejectRequest(Map<String, dynamic> req) async {
    final reason = await showDialog<String>(context: context, builder: (_) => const _DocRejectDialog());
    if (reason == null) return;
    try {
      await supabase.from('requests').update({'status': 'cancelled'}).eq('id', req['id']);
      final userId = req['user_id'];
      final refNo = _refNo(req);
      final msg = reason.isNotEmpty
          ? 'Your request ($refNo) was cancelled: $reason. Please resubmit with correct documents.'
          : 'Your request ($refNo) was cancelled due to document issues. Please resubmit with correct documents.';
      await NotificationService.sendNotificationSafely(
        supabase,
        userId: userId,
        title: 'Document Verification Failed',
        message: msg,
        type: 'doc_rejected',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [Icon(Icons.info_outline, color: Colors.white, size: 20), SizedBox(width: 8), Text('Request cancelled — customer notified to resubmit')]),
          backgroundColor: const Color(0xFFE53E3E), behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));
        _loadRequests();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.redAccent));
    }
  }

  void _openVerifyDialog(Map<String, dynamic> req) {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => _VerifyDocumentsDialog(request: req, supabase: supabase, onDone: _loadRequests));
  }

  String _refNo(Map<String, dynamic> req) =>
      'MI-${DateTime.now().year}-${req['id'].toString().padLeft(3, '0')}';

  String _formatDate(dynamic v) {
    if (v == null) return '—';
    try { return DateFormat('MM/dd/yyyy').format(DateTime.parse(v.toString())); } catch (_) { return v.toString(); }
  }

  List<Map<String, dynamic>> _filteredList(List<Map<String, dynamic>> list) {
    final q = _searchController.text.toLowerCase().trim();
    if (q.isEmpty) return list;
    return list.where((r) {
      final name = (r['customer_name'] ?? '').toString().toLowerCase();
      final ref = _refNo(r).toLowerCase();
      return name.contains(q) || ref.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now());
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(children: [
        _buildHeader(dateStr),
        Expanded(child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2D6A4F)))
          : RefreshIndicator(onRefresh: _loadRequests, color: const Color(0xFF2D6A4F),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _buildStatsRow(),
                  const SizedBox(height: 24),
                  _buildTable(title: 'Barangay Requests — Document Verification', subtitle: 'Verify: Barangay Certificate, Proof of Ownership, and Veterinary Health Certificate (if available)', requests: _filteredList(_barangayRequests), scrollCtrl: _barangayScrollCtrl, isBarangay: true),
                  const SizedBox(height: 24),
                  _buildTable(title: 'Market Request — Document Verification', subtitle: 'Verify: Proof of Ownership, Business Permit, and Veterinary Health Certificate (if available)', requests: _filteredList(_marketRequests), scrollCtrl: _marketScrollCtrl, isBarangay: false),
                ]),
              ))),
      ]),
    );
  }
  Widget _buildHeader(String dateStr) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Document Verification', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
          const SizedBox(height: 2),
          Text('Permits and certificates verification', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        ]),
        const Spacer(),
        SizedBox(width: 280, child: TextField(
          controller: _searchController, onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Search by reference or customer...', hintStyle: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 13),
            prefixIcon: const Icon(Icons.search, color: Color(0xFFA0AEC0), size: 20),
            filled: true, fillColor: const Color(0xFFF7FAFC), contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF2D6A4F), width: 1.5)),
          ),
        )),
        const SizedBox(width: 16),
        Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)), child: Text(dateStr, style: const TextStyle(fontSize: 12, color: Color(0xFF4A5568)))),
        const SizedBox(width: 12),
        IconButton(onPressed: () => Navigator.maybePop(context), icon: const Icon(Icons.arrow_forward, size: 26), color: const Color(0xFF2D3748)),
      ]),
    );
  }

  Widget _buildStatsRow() {
    final tM = _marketRequests.length; final tB = _barangayRequests.length;
    final aM = _verifiedRequests.where((r) => r['request_type'] == 'market').length;
    final aB = _verifiedRequests.where((r) => r['request_type'] == 'barangay').length;
    final rM = _cancelledRequests.where((r) => r['request_type'] == 'market').length;
    final rB = _cancelledRequests.where((r) => r['request_type'] == 'barangay').length;
    return Row(children: [
      Expanded(child: _statCard(icon: Icons.description_outlined, iconColor: const Color(0xFF4A5568), iconBg: const Color(0xFFF7FAFC), label: 'Total Documents', m: tM, b: tB, bc: Colors.grey.shade200)),
      const SizedBox(width: 16),
      Expanded(child: _statCard(icon: Icons.hourglass_top_rounded, iconColor: const Color(0xFFDD6B20), iconBg: const Color(0xFFFFFAF0), label: 'Pending Review', m: tM, b: tB, bc: const Color(0xFFFBD38D))),
      const SizedBox(width: 16),
      Expanded(child: _statCard(icon: Icons.check_circle_outline, iconColor: const Color(0xFF38A169), iconBg: const Color(0xFFF0FFF4), label: 'Approved', m: aM, b: aB, bc: const Color(0xFF9AE6B4))),
      const SizedBox(width: 16),
      Expanded(child: _statCard(icon: Icons.cancel_outlined, iconColor: const Color(0xFFE53E3E), iconBg: const Color(0xFFFFF5F5), label: 'Rejected', m: rM, b: rB, bc: const Color(0xFFFEB2B2))),
    ]);
  }

  Widget _statCard({required IconData icon, required Color iconColor, required Color iconBg, required String label, required int m, required int b, required Color bc}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: bc)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: iconColor, size: 20)), const Spacer()]),
        const SizedBox(height: 12),
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A5568))),
        const SizedBox(height: 6),
        Text('In Market – ${m.toString()}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        Text('In Barangay – ${b.toString()}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
      ]),
    );
  }
  Widget _buildTable({required String title, required String subtitle, required List<Map<String, dynamic>> requests, required ScrollController scrollCtrl, required bool isBarangay}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(24, 20, 24, 4), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ])),
        const SizedBox(height: 8),
        requests.isEmpty
          ? Padding(padding: const EdgeInsets.all(32), child: Center(child: Column(children: [Icon(Icons.inbox_outlined, size: 40, color: Colors.grey.shade300), const SizedBox(height: 8), Text('No requests pending document verification', style: TextStyle(color: Colors.grey.shade400, fontSize: 13))])))
          : Scrollbar(
              controller: scrollCtrl, thumbVisibility: true, trackVisibility: true,
              child: SingleChildScrollView(
                controller: scrollCtrl, scrollDirection: Axis.horizontal,
                child: Padding(padding: const EdgeInsets.only(bottom: 16), child: DataTable(
                  headingRowColor: WidgetStateProperty.all(const Color(0xFFF7FAFC)),
                  headingTextStyle: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF4A5568), fontSize: 12),
                  dataTextStyle: const TextStyle(color: Color(0xFF2D3748), fontSize: 12),
                  columnSpacing: 30, horizontalMargin: 20,
                  columns: const [
                    DataColumn(label: Text('Reference #')), DataColumn(label: Text('Customer')),
                    DataColumn(label: Text('Livestock')), DataColumn(label: Text('Markings')),
                    DataColumn(label: Text('Required Documents')), DataColumn(label: Text('Schedule Date')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: requests.map((req) => DataRow(cells: [
                    DataCell(Text(_refNo(req), style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF2D6A4F)))),
                    DataCell(Text(req['customer_name'] ?? '—')),
                    DataCell(Text('${(req['animal_count'] ?? 0)} head(s)\n${(req['livestock_type'] ?? '')}')),
                    DataCell(Text(req['marking'] ?? '—')),
                    DataCell(SizedBox(width: 250, child: _buildDocBadges(req, isBarangay))),
                    DataCell(SizedBox(width: 100, child: Text(_formatDate(req['preferred_date'])))),
                    DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                      _actionBtn(label: 'Verify', color: const Color(0xFF276749), bgColor: const Color(0xFFF0FFF4), borderColor: const Color(0xFF9AE6B4), onTap: () => _openVerifyDialog(req)),
                      const SizedBox(width: 6),
                      _actionBtn(label: 'Reject', color: const Color(0xFFE53E3E), bgColor: const Color(0xFFFFF5F5), borderColor: const Color(0xFFFEB2B2), onTap: () => _rejectRequest(req)),
                    ])),
                  ])).toList(),
                )),
              ),
            ),
      ]),
    );
  }

  Widget _buildDocBadges(Map<String, dynamic> req, bool isBarangay) {
    final docs = <MapEntry<String, bool>>[];
    void addIfPresent(String? val, String label) {
      if (val != null && val.toString().trim().isNotEmpty) {
        final isHardCopy = val.toString().startsWith('hard_copy://');
        docs.add(MapEntry(isHardCopy ? '$label (Hard Copy)' : label, isHardCopy));
      }
    }

    if (isBarangay) addIfPresent(req['barangay_certificate']?.toString(), 'Barangay Certificate');
    if (!isBarangay) addIfPresent(req['business_permit']?.toString(), 'Business Permit');
    addIfPresent(req['proof_of_ownership']?.toString(), 'Proof of Ownership');
    addIfPresent(req['vet_certificate']?.toString(), 'Vet Health Certificate');

    if (docs.isEmpty) return Text('—', style: TextStyle(color: Colors.grey.shade400));
    return Wrap(direction: Axis.vertical, spacing: 3, children: docs.map((entry) => Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(
        entry.value ? Icons.folder_special_outlined : Icons.insert_drive_file_outlined,
        size: 12,
        color: entry.value ? const Color(0xFF276749) : Colors.grey.shade500,
      ),
      const SizedBox(width: 4),
      Text(
        entry.key,
        style: TextStyle(
          fontSize: 11,
          fontWeight: entry.value ? FontWeight.w600 : FontWeight.normal,
          color: entry.value ? const Color(0xFF276749) : const Color(0xFF4A5568),
        ),
      ),
    ])).toList());
  }

  Widget _actionBtn({required String label, required Color color, required Color bgColor, required Color borderColor, required VoidCallback onTap}) {
    return Material(color: bgColor, borderRadius: BorderRadius.circular(6),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(6),
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: borderColor)),
          child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)))));
  }
}
// ═══════════════════════════════════════════════════════════
//  VERIFY DOCUMENTS DIALOG
// ═══════════════════════════════════════════════════════════
class _VerifyDocumentsDialog extends StatefulWidget {
  final Map<String, dynamic> request;
  final dynamic supabase;
  final VoidCallback onDone;
  const _VerifyDocumentsDialog({required this.request, required this.supabase, required this.onDone});
  @override
  State<_VerifyDocumentsDialog> createState() => _VerifyDocumentsDialogState();
}

class _VerifyDocumentsDialogState extends State<_VerifyDocumentsDialog> {
  final _notesCtrl = TextEditingController();
  final Map<String, bool> _verifiedMap = {};
  final Map<String, String> _docUrls = {};
  final Map<String, bool> _uploadingMap = {};
  bool _isSaving = false;
  late final bool _isOnlineCustomer;

  @override
  void initState() {
    super.initState();
    final bCert = widget.request['barangay_certificate']?.toString() ?? '';
    final pOwn = widget.request['proof_of_ownership']?.toString() ?? '';
    final bPermit = widget.request['business_permit']?.toString() ?? '';
    final isBarangay = widget.request['request_type'] == 'barangay';

    final hasPermit = isBarangay
        ? (bCert.isNotEmpty && !bCert.startsWith('hard_copy://'))
        : (bPermit.isNotEmpty && !bPermit.startsWith('hard_copy://'));
    final hasOwnership = pOwn.isNotEmpty && !pOwn.startsWith('hard_copy://');

    // Online submissions always have both required documents compiled digitally
    // before reaching Document Verification
    _isOnlineCustomer = hasPermit && hasOwnership;

    _buildDocMap();
  }

  @override
  void dispose() { _notesCtrl.dispose(); super.dispose(); }

  void _buildDocMap() {
    final req = widget.request;
    final isBarangay = req['request_type'] == 'barangay';
    final isOnline = _isOnlineCustomer;

    if (isBarangay) {
      final v = (req['barangay_certificate'] ?? '').toString();
      if (!isOnline || v.isNotEmpty) {
        _docUrls['Barangay Certificate'] = v;
        _verifiedMap['Barangay Certificate'] = v.startsWith('hard_copy://');
      }
    } else {
      final v = (req['business_permit'] ?? '').toString();
      if (!isOnline || v.isNotEmpty) {
        _docUrls['Business Permit'] = v;
        _verifiedMap['Business Permit'] = v.startsWith('hard_copy://');
      }
    }
    final own = (req['proof_of_ownership'] ?? '').toString();
    if (!isOnline || own.isNotEmpty) {
      _docUrls['Proof of Ownership'] = own;
      _verifiedMap['Proof of Ownership'] = own.startsWith('hard_copy://');
    }

    final vet = (req['vet_certificate'] ?? '').toString();
    if (!isOnline || vet.isNotEmpty) {
      _docUrls['Veterinary Health Certificate'] = vet;
      _verifiedMap['Veterinary Health Certificate'] = vet.startsWith('hard_copy://');
    }
  }

  String _docColumnName(String docLabel) {
    switch (docLabel) {
      case 'Barangay Certificate': return 'barangay_certificate';
      case 'Business Permit': return 'business_permit';
      case 'Proof of Ownership': return 'proof_of_ownership';
      case 'Veterinary Health Certificate': return 'vet_certificate';
      default: return '';
    }
  }

  String _docUrl(String docLabel) => _docUrls[docLabel] ?? '';

  Future<void> _saveDocValue(String docLabel, String value, String successMessage) async {
    final reqId = widget.request['id'];
    final colName = _docColumnName(docLabel);
    await widget.supabase
        .from('requests')
        .update({colName: value})
        .eq('id', reqId);

    widget.request[colName] = value;

    if (mounted) {
      setState(() {
        _docUrls[docLabel] = value;
        _verifiedMap[docLabel] = true;
        _uploadingMap[docLabel] = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: const Color(0xFF38A169),
        ),
      );
    }
  }

  Future<void> _captureWalkInDoc(String docLabel) async {
    try {
      setState(() => _uploadingMap[docLabel] = true);
      final reqId = widget.request['id'];
      final colName = _docColumnName(docLabel);
      final picked = await DocumentUploadHelper.captureFromCameraAndUpload(
        context,
        widget.supabase as SupabaseClient,
        docLabel: docLabel,
        prefix: 'req_${reqId}_$colName',
      );
      if (picked == null) {
        if (mounted) setState(() => _uploadingMap[docLabel] = false);
        return;
      }

      await _saveDocValue(
        docLabel,
        picked.url,
        '$docLabel photo captured and attached to record!',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingMap[docLabel] = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to capture $docLabel: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _uploadWalkInDoc(String docLabel) async {
    try {
      setState(() => _uploadingMap[docLabel] = true);
      final reqId = widget.request['id'];
      final colName = _docColumnName(docLabel);
      final picked = await DocumentUploadHelper.pickAndUpload(
        widget.supabase as SupabaseClient,
        prefix: 'req_${reqId}_$colName',
      );
      if (picked == null) {
        if (mounted) setState(() => _uploadingMap[docLabel] = false);
        return;
      }

      await _saveDocValue(
        docLabel,
        picked.url,
        '$docLabel uploaded and attached to record!',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingMap[docLabel] = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload $docLabel: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _markHardCopyFiled(String docLabel) async {
    try {
      setState(() => _uploadingMap[docLabel] = true);
      final stamp = DateFormat('MMM d, yyyy h:mm a').format(DateTime.now());
      final value = 'hard_copy://Filed on $stamp';
      await _saveDocValue(
        docLabel,
        value,
        '$docLabel marked as Physical Hard Copy on File ($stamp)!',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingMap[docLabel] = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to record hard copy for $docLabel: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _openDoc(String url) async {
    if (url.isEmpty) return;
    if (url.startsWith('data:image/')) {
      final commaIdx = url.indexOf(',');
      if (commaIdx != -1 && mounted) {
        final bytes = base64Decode(url.substring(commaIdx + 1));
        await showDialog(
          context: context,
          builder: (ctx) => Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Document Preview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                  ),
                  Flexible(
                    child: InteractiveViewer(
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
        return;
      }
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try { if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (e) { debugPrint('URL launch error: ${e.toString()}'); }
  }

  Future<void> _saveRecord() async {
    setState(() => _isSaving = true);
    try {
      final req = widget.request;
      final refNo = 'MI-${DateTime.now().year}-${req['id'].toString().padLeft(3, '0')}';
      await widget.supabase.from('requests').update({'status': 'doc_verified'}).eq('id', req['id']);
      final userId = req['user_id'];
      await NotificationService.sendNotificationSafely(
        widget.supabase,
        userId: userId,
        title: 'Documents Verified',
        message: 'Your documents for request $refNo have been verified. Your request is now proceeding to the next stage.',
        type: 'doc_verified',
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onDone();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [Icon(Icons.check_circle, color: Colors.white, size: 20), SizedBox(width: 8), Text('Documents verified — request progressed')]),
          backgroundColor: const Color(0xFF38A169), behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.redAccent));
    }
  }
  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    final isBarangay = req['request_type'] == 'barangay';
    final refNo = 'MI-${DateTime.now().year}-${req['id'].toString().padLeft(3, '0')}';
    final dateStr = req['preferred_date'] != null ? DateFormat('MM/dd/yyyy').format(DateTime.parse(req['preferred_date'])) : '—';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        width: MediaQuery.of(context).size.width * 0.92,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Verify Documents — ${isBarangay ? 'In Barangay' : 'In Market'}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
          const SizedBox(height: 4),
          Text('Review and verify all required documents for ${req['customer_name'] ?? 'Customer'}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF718096))),
          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFFF7FAFC), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
            child: Row(children: [
              Expanded(child: _metaItem('Scheduled Date', dateStr)),
              Expanded(child: _metaItem('Reference #', refNo)),
              Expanded(child: _metaItem('Customer', req['customer_name'] ?? '—')),
              Expanded(child: _metaItem('Request Type', isBarangay ? 'Barangay' : 'Market')),
            ]),
          ),
          const SizedBox(height: 20),

          const Text('Document Verification Checklist', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF2D3748))),
          const SizedBox(height: 12),

          if (_verifiedMap.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFFAF0), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFFBD38D))),
              child: const Row(children: [Icon(Icons.warning_amber_rounded, color: Color(0xFFDD6B20), size: 18), SizedBox(width: 8), Expanded(child: Text('No documents were uploaded for this request.', style: TextStyle(fontSize: 13, color: Color(0xFFDD6B20))))]),
            )
          else
            ..._verifiedMap.entries.map((e) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _docCard(e.key, e.value))),

          const SizedBox(height: 16),
          const Text('Verification Notes', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2D3748))),
          const SizedBox(height: 8),
          TextField(
            controller: _notesCtrl, maxLines: 3, style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Add any notes about the documents...', hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              filled: true, fillColor: const Color(0xFFF7FAFC), contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF2D6A4F), width: 1.5)),
            ),
          ),
          const SizedBox(height: 24),

          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton(
              onPressed: _isSaving ? null : () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), side: BorderSide(color: Colors.grey.shade300), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), foregroundColor: const Color(0xFF4A5568)),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _isSaving ? null : _saveRecord,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A202C), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 0),
              child: _isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Save Record'),
            ),
          ]),
        ])),
      ),
    );
  }

  Widget _metaItem(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF718096))),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A202C))),
    ]);
  }

  Widget _docCard(String docLabel, bool isVerified) {
    final url = _docUrl(docLabel);
    final hasDoc = url.isNotEmpty;
    final isHardCopy = url.startsWith('hard_copy://');
    final hardCopyDetail = isHardCopy ? url.replaceFirst('hard_copy://', '') : '';
    final isUploading = _uploadingMap[docLabel] == true;
    final isOnline = _isOnlineCustomer;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isVerified ? const Color(0xFF9AE6B4) : Colors.grey.shade200),
        color: isVerified ? const Color(0xFFF0FFF4) : Colors.white,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(
                isVerified
                    ? Icons.check_circle
                    : (isHardCopy
                        ? Icons.folder_special_outlined
                        : (hasDoc ? Icons.insert_drive_file_outlined : Icons.description_outlined)),
                size: 16,
                color: isVerified ? const Color(0xFF38A169) : const Color(0xFF4A5568),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  docLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isVerified ? const Color(0xFF276749) : const Color(0xFF2D3748),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isOnline) ...[
                if (!hasDoc)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFFFFAF0), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFBD38D))),
                    child: const Text('Walk-In: Attach or Log Hard Copy', style: TextStyle(fontSize: 10, color: Color(0xFFDD6B20), fontWeight: FontWeight.w700)),
                  ),
                if (isHardCopy) ...[
                  const SizedBox(width: 6),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 240),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6FFFA),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF81E6D9)),
                    ),
                    child: Text(
                      hardCopyDetail.isNotEmpty ? 'Hard Copy ($hardCopyDetail)' : 'Hard Copy on File',
                      style: const TextStyle(fontSize: 10, color: Color(0xFF234E52), fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
              if (isVerified) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFC6F6D5), borderRadius: BorderRadius.circular(10)),
                  child: const Text('Verified', style: TextStyle(fontSize: 10, color: Color(0xFF276749), fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
        ),
        Divider(height: 1, color: Colors.grey.shade100),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SizedBox(
                width: double.infinity,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // LEFT SIDE: View Document or Walk-in intake tools
                    if (isOnline) ...[
                      if (hasDoc && !isHardCopy)
                        OutlinedButton.icon(
                          onPressed: () => _openDoc(url),
                          icon: const Icon(Icons.image_outlined, size: 14),
                          label: const Text('View Document', style: TextStyle(fontSize: 11.5)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF4A5568),
                            side: BorderSide(color: Colors.grey.shade300),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                        )
                      else
                        const SizedBox.shrink(),
                    ] else ...[
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (hasDoc && !isHardCopy)
                              OutlinedButton.icon(
                                onPressed: () => _openDoc(url),
                                icon: const Icon(Icons.image_outlined, size: 14),
                                label: const Text('View Document', style: TextStyle(fontSize: 11.5)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF4A5568),
                                  side: BorderSide(color: Colors.grey.shade300),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                              ),
                            OutlinedButton.icon(
                              onPressed: isUploading ? null : () => _captureWalkInDoc(docLabel),
                              icon: const Icon(Icons.camera_alt_outlined, size: 14),
                              label: const Text('Take Photo', style: TextStyle(fontSize: 11.5)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF2D6A4F),
                                side: const BorderSide(color: Color(0xFF9AE6B4)),
                                backgroundColor: const Color(0xFFF0FFF4),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: isUploading ? null : () => _uploadWalkInDoc(docLabel),
                              icon: isUploading
                                  ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Icon(hasDoc && !isHardCopy ? Icons.sync : Icons.upload_file, size: 14),
                              label: Text(
                                isUploading ? 'Saving...' : (hasDoc && !isHardCopy ? 'Replace File' : 'Upload File'),
                                style: const TextStyle(fontSize: 11.5),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF2B6CB0),
                                side: const BorderSide(color: Color(0xFF90CDF4)),
                                backgroundColor: const Color(0xFFEBF8FF),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: isUploading ? null : () => _markHardCopyFiled(docLabel),
                              icon: Icon(
                                isHardCopy ? Icons.folder_special : Icons.folder_open_outlined,
                                size: 14,
                              ),
                              label: Text(
                                isHardCopy ? 'Hard Copy Filed ✓' : 'Hard Copy Filed',
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF744210),
                                side: BorderSide(
                                  color: isHardCopy ? const Color(0xFFD69E2E) : const Color(0xFFF6E05E),
                                ),
                                backgroundColor: isHardCopy ? const Color(0xFFFEFCBF) : const Color(0xFFFFFAF0),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // RIGHT SIDE: Verify action
                    OutlinedButton(
                      onPressed: !hasDoc ? null : () => setState(() => _verifiedMap[docLabel] = !isVerified),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF276749),
                        backgroundColor: isVerified ? const Color(0xFFC6F6D5) : Colors.white,
                        side: const BorderSide(color: Color(0xFF9AE6B4)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      child: Text(
                        isVerified ? '✓ Verified' : 'Mark as Verified',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
// ═══════════════════════════════════════════════════════════
//  REJECT DIALOG
// ═══════════════════════════════════════════════════════════
class _DocRejectDialog extends StatefulWidget {
  const _DocRejectDialog();
  @override
  State<_DocRejectDialog> createState() => _DocRejectDialogState();
}

class _DocRejectDialogState extends State<_DocRejectDialog> {
  final _ctrl = TextEditingController(
    text: 'Your documents could not be verified. Please resubmit with the correct and valid documents.',
  );

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFFFFF5F5), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.block, color: Color(0xFFE53E3E), size: 22)),
        const SizedBox(width: 12),
        const Expanded(child: Text('Reject & Cancel Request', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF2D3748)))),
      ]),
      content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFF5F5), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFFEB2B2))),
          child: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFE53E3E), size: 16),
            SizedBox(width: 8),
            Expanded(child: Text('This will cancel the request and notify the customer via mobile app to resubmit with correct documents.', style: TextStyle(fontSize: 12, color: Color(0xFF9B2335)))),
          ]),
        ),
        const SizedBox(height: 14),
        const Text('Reason for rejection (sent to customer):', style: TextStyle(fontSize: 13, color: Color(0xFF718096))),
        const SizedBox(height: 8),
        TextField(
          controller: _ctrl, maxLines: 3, style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            filled: true, fillColor: const Color(0xFFF7FAFC),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE53E3E), width: 1.5)),
          ),
        ),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Color(0xFF718096)))),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE53E3E), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 0),
          child: const Text('Reject & Notify Customer'),
        ),
      ],
    );
  }
}
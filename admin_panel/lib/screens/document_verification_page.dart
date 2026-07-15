import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

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

  @override
  void initState() { super.initState(); _loadRequests(); }

  @override
  void dispose() {
    _barangayScrollCtrl.dispose();
    _marketScrollCtrl.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    try {
      final all = await supabase.from('requests').select().order('created_at', ascending: false);
      final approved = all.where((r) => r['status'] == 'approved').toList();
      final verified = all.where((r) => r['status'] == 'doc_verified').toList();
      final cancelled = all.where((r) => r['status'] == 'cancelled').toList();
      setState(() {
        _barangayRequests = List<Map<String, dynamic>>.from(approved.where((r) => r['request_type'] == 'barangay'));
        _marketRequests = List<Map<String, dynamic>>.from(approved.where((r) => r['request_type'] == 'market'));
        _verifiedRequests = List<Map<String, dynamic>>.from(verified);
        _cancelledRequests = List<Map<String, dynamic>>.from(cancelled);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('DocVerification load error: ' + e.toString());
      setState(() => _isLoading = false);
    }
  }
  Future<void> _rejectRequest(Map<String, dynamic> req) async {
    final reason = await showDialog<String>(context: context, builder: (_) => const _DocRejectDialog());
    if (reason == null) return;
    try {
      await supabase.from('requests').update({'status': 'cancelled'}).eq('id', req['id']);
      final userId = req['user_id'];
      if (userId != null) {
        final refNo = _refNo(req);
        final msg = reason.isNotEmpty
            ? 'Your request (' + refNo + ') was cancelled: ' + reason + '. Please resubmit with correct documents.'
            : 'Your request (' + refNo + ') was cancelled due to document issues. Please resubmit with correct documents.';
        await supabase.from('notifications').insert({'user_id': userId, 'title': 'Document Verification Failed', 'message': msg, 'is_read': false, 'type': 'doc_rejected'});
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [Icon(Icons.info_outline, color: Colors.white, size: 20), SizedBox(width: 8), Text('Request cancelled — customer notified to resubmit')]),
          backgroundColor: const Color(0xFFE53E3E), behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));
        _loadRequests();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ' + e.toString()), backgroundColor: Colors.redAccent));
    }
  }

  void _openVerifyDialog(Map<String, dynamic> req) {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => _VerifyDocumentsDialog(request: req, supabase: supabase, onDone: _loadRequests));
  }

  String _refNo(Map<String, dynamic> req) =>
      'MI-' + DateTime.now().year.toString() + '-' + req['id'].toString().padLeft(3, '0');

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
        Text('In Market – ' + m.toString(), style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        Text('In Barangay – ' + b.toString(), style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
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
                    DataCell(Text((req['animal_count'] ?? 0).toString() + ' head(s)\n' + (req['livestock_type'] ?? ''))),
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
    final docs = <String>[];
    if (isBarangay && req['barangay_certificate'] != null) docs.add('Barangay Certificate');
    if (!isBarangay && req['business_permit'] != null) docs.add('Business Permit');
    if (req['proof_of_ownership'] != null) docs.add('Proof of Ownership');
    if (req['vet_certificate'] != null) docs.add('Vet Health Certificate');
    if (docs.isEmpty) return Text('—', style: TextStyle(color: Colors.grey.shade400));
    return Wrap(direction: Axis.vertical, spacing: 3, children: docs.map((d) => Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.insert_drive_file_outlined, size: 12, color: Colors.grey.shade500),
      const SizedBox(width: 4),
      Text(d, style: const TextStyle(fontSize: 11, color: Color(0xFF4A5568))),
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
  bool _isSaving = false;

  @override
  void initState() { super.initState(); _buildDocMap(); }

  @override
  void dispose() { _notesCtrl.dispose(); super.dispose(); }

  void _buildDocMap() {
    final req = widget.request;
    final isBarangay = req['request_type'] == 'barangay';
    if (isBarangay && req['barangay_certificate'] != null) _verifiedMap['Barangay Certificate'] = false;
    if (!isBarangay && req['business_permit'] != null) _verifiedMap['Business Permit'] = false;
    if (req['proof_of_ownership'] != null) _verifiedMap['Proof of Ownership'] = false;
    if (req['vet_certificate'] != null) _verifiedMap['Veterinary Health Certificate'] = false;
  }

  String _docUrl(String docLabel) {
    final req = widget.request;
    switch (docLabel) {
      case 'Barangay Certificate': return req['barangay_certificate'] ?? '';
      case 'Business Permit': return req['business_permit'] ?? '';
      case 'Proof of Ownership': return req['proof_of_ownership'] ?? '';
      case 'Veterinary Health Certificate': return req['vet_certificate'] ?? '';
      default: return '';
    }
  }

  Future<void> _openDoc(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try { if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (e) { debugPrint('URL launch error: ' + e.toString()); }
  }

  Future<void> _saveRecord() async {
    setState(() => _isSaving = true);
    try {
      final req = widget.request;
      final refNo = 'MI-' + DateTime.now().year.toString() + '-' + req['id'].toString().padLeft(3, '0');
      await widget.supabase.from('requests').update({'status': 'doc_verified'}).eq('id', req['id']);
      final userId = req['user_id'];
      if (userId != null) {
        await widget.supabase.from('notifications').insert({'user_id': userId, 'title': 'Documents Verified', 'message': 'Your documents for request ' + refNo + ' have been verified. Your request is now proceeding to the next stage.', 'is_read': false, 'type': 'doc_verified'});
      }
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ' + e.toString()), backgroundColor: Colors.redAccent));
    }
  }
  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    final isBarangay = req['request_type'] == 'barangay';
    final refNo = 'MI-' + DateTime.now().year.toString() + '-' + req['id'].toString().padLeft(3, '0');
    final dateStr = req['preferred_date'] != null ? DateFormat('MM/dd/yyyy').format(DateTime.parse(req['preferred_date'])) : '—';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 580, padding: const EdgeInsets.all(28),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Verify Documents — ' + (isBarangay ? 'In Barangay' : 'In Market'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
          const SizedBox(height: 4),
          Text('Review and verify all required documents for ' + (req['customer_name'] ?? 'Customer'),
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
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isVerified ? const Color(0xFF9AE6B4) : Colors.grey.shade200),
        color: isVerified ? const Color(0xFFF0FFF4) : Colors.white,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Row(children: [
          Icon(isVerified ? Icons.check_circle : Icons.insert_drive_file_outlined, size: 16, color: isVerified ? const Color(0xFF38A169) : const Color(0xFF4A5568)),
          const SizedBox(width: 8),
          Text(docLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isVerified ? const Color(0xFF276749) : const Color(0xFF2D3748))),
          if (isVerified) ...[
            const SizedBox(width: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: const Color(0xFFC6F6D5), borderRadius: BorderRadius.circular(10)), child: const Text('Verified', style: TextStyle(fontSize: 10, color: Color(0xFF276749), fontWeight: FontWeight.w700))),
          ],
        ])),
        Divider(height: 1, color: Colors.grey.shade100),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Row(children: [
          OutlinedButton.icon(
            onPressed: () => _openDoc(_docUrl(docLabel)),
            icon: const Icon(Icons.image_outlined, size: 15),
            label: const Text('View Document', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF4A5568), side: BorderSide(color: Colors.grey.shade300), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
          ),
          const Spacer(),
          OutlinedButton(
            onPressed: () => setState(() => _verifiedMap[docLabel] = !isVerified),
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF276749), backgroundColor: isVerified ? const Color(0xFFC6F6D5) : Colors.white, side: const BorderSide(color: Color(0xFF9AE6B4)), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
            child: Text(isVerified ? '✓ Verified' : 'Mark as Verified', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ])),
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
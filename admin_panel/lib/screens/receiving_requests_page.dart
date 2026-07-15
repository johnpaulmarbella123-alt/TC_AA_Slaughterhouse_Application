import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ReceivingRequestsPage extends StatefulWidget {
  const ReceivingRequestsPage({super.key});

  @override
  State<ReceivingRequestsPage> createState() => _ReceivingRequestsPageState();
}

class _ReceivingRequestsPageState extends State<ReceivingRequestsPage> {
  final supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _approvedRequests = [];
  List<Map<String, dynamic>> _pendingBarangay = [];
  List<Map<String, dynamic>> _pendingMarket = [];
  bool _isLoading = true;
  int _pendingTabIndex = 0; // 0 = Barangay, 1 = Market

  // Add scroll controllers for horizontal scrolling
  final ScrollController _approvedScrollController = ScrollController();
  final ScrollController _pendingScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _approvedScrollController.dispose();
    _pendingScrollController.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════
  //  LOAD DATA
  // ════════════════════════════════════════════
  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    try {
      final user = supabase.auth.currentUser;
      debugPrint('═══ ADMIN LOAD REQUESTS ═══');
      debugPrint('Admin user: ${user?.email} | role: ${user?.userMetadata?['role']}');

      // First try loading ALL requests (no status filter) to see if we can access the table at all
      final allRequests = await supabase
          .from('requests')
          .select()
          .order('created_at', ascending: false);
      
      debugPrint('Total requests in DB: ${allRequests.length}');
      for (final r in allRequests) {
        debugPrint('  → id=${r['id']} | status=${r['status']} | type=${r['request_type']} | customer=${r['customer_name']}');
      }

      final approved = allRequests.where((r) => r['status'] == 'approved').toList();
      final pendingAll = allRequests.where((r) => r['status'] == 'pending').toList();

      debugPrint('Approved: ${approved.length} | Pending: ${pendingAll.length}');

      setState(() {
        _approvedRequests = List<Map<String, dynamic>>.from(approved);
        _pendingBarangay = List<Map<String, dynamic>>.from(
          pendingAll.where((r) => r['request_type'] == 'barangay'),
        );
        _pendingMarket = List<Map<String, dynamic>>.from(
          pendingAll.where((r) => r['request_type'] == 'market'),
        );
        _isLoading = false;
      });

      debugPrint('Barangay pending: ${_pendingBarangay.length} | Market pending: ${_pendingMarket.length}');
      debugPrint('═══ LOAD COMPLETE ═══');
    } catch (e) {
      debugPrint('═══ ERROR loading requests: $e ═══');
      setState(() => _isLoading = false);
    }
  }

  // ════════════════════════════════════════════
  //  APPROVE REQUEST
  // ════════════════════════════════════════════
  Future<void> _approveRequest(Map<String, dynamic> request) async {
    try {
      // 1. Update request status
      await supabase
          .from('requests')
          .update({'status': 'approved'})
          .eq('id', request['id']);

      // 2. Format the preferred date for the notification message
      String dateStr = 'your requested date';
      if (request['preferred_date'] != null) {
        try {
          final date = DateTime.parse(request['preferred_date']);
          dateStr = DateFormat('MMMM d, yyyy').format(date);
        } catch (_) {
          dateStr = request['preferred_date'].toString();
        }
      }

      // 3. Send notification to customer
      await supabase.from('notifications').insert({
        'user_id': request['user_id'],
        'title': 'Approved Request',
        'message':
            'Your slaughter request has been approved for $dateStr to bring your animals',
        'is_read': false,
        'type': 'request_approved',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Request approved — notification sent to customer'),
              ],
            ),
            backgroundColor: const Color(0xFF38A169),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }

      _loadRequests();
    } catch (e) {
      debugPrint('Error approving request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error approving request: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // ════════════════════════════════════════════
  //  REJECT REQUEST
  // ════════════════════════════════════════════
  Future<void> _rejectRequest(Map<String, dynamic> request) async {
    // Show confirmation dialog
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _RejectDialog(),
    );

    if (reason == null) return; // User cancelled

    try {
      // 1. Update request status
      await supabase
          .from('requests')
          .update({'status': 'rejected'})
          .eq('id', request['id']);

      // 2. Send notification to customer
      await supabase.from('notifications').insert({
        'user_id': request['user_id'],
        'title': 'Request Rejected',
        'message': reason.isNotEmpty
            ? reason
            : 'Request denied — fully booked. Please select another date.',
        'is_read': false,
        'type': 'request_rejected',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Request rejected — notification sent to customer'),
              ],
            ),
            backgroundColor: const Color(0xFFE53E3E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }

      _loadRequests();
    } catch (e) {
      debugPrint('Error rejecting request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error rejecting request: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // ════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(now);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(
        children: [
          // ─── TOP HEADER ───
          _buildHeader(dateStr),
          // ─── CONTENT ───
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF2D6A4F),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadRequests,
                    color: const Color(0xFF2D6A4F),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSearchAndActions(),
                          const SizedBox(height: 24),
                          _buildApprovedSection(),
                          const SizedBox(height: 32),
                          _buildNewRequestsSection(),
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
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
      child: Row(
        children: [
          const Text(
            'Receiving & Inspection',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A202C),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              dateStr,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF4A5568),
              ),
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_forward, size: 28),
            color: const Color(0xFF2D3748),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  SEARCH + NEW ENTRY BUTTON
  // ════════════════════════════════════════════
  Widget _buildSearchAndActions() {
    return Row(
      children: [
        // Search
        SizedBox(
          width: 320,
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search by reference or customer...',
              hintStyle: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: Color(0xFFA0AEC0)),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF2D6A4F), width: 1.5),
              ),
            ),
          ),
        ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: () => _showNewReceivingEntryDialog(),
          icon: const Icon(Icons.add, size: 20),
          label: const Text('New Receiving Entry'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A202C),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 0,
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════
  //  APPROVED REQUESTS SECTION
  // ════════════════════════════════════════════
  Widget _buildApprovedSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Approve Request',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A202C),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Animals received for inspection with ante-mortem examination results',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Table
          _approvedRequests.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.inbox_outlined, size: 40, color: Colors.grey.shade300),
                        const SizedBox(height: 8),
                        Text(
                          'No approved requests yet',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                )
              : Scrollbar(
                  controller: _approvedScrollController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  child: SingleChildScrollView(
                    controller: _approvedScrollController,
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(const Color(0xFFF7FAFC)),
                    headingTextStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4A5568),
                      fontSize: 13,
                    ),
                    dataTextStyle: const TextStyle(
                      color: Color(0xFF2D3748),
                      fontSize: 13,
                    ),
                    columnSpacing: 50,
                    horizontalMargin: 24,
                    columns: const [
                      DataColumn(label: Text('Reference #')),
                      DataColumn(label: Text('City/Brgy.')),
                      DataColumn(label: Text('Customer')),
                      DataColumn(label: Text('Livestock')),
                      DataColumn(label: Text('Type')),
                      DataColumn(label: Text('Marking')),
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: _approvedRequests.map((req) {
                      final refNo = _buildRefNo(req);
                      return DataRow(cells: [
                        DataCell(Text(refNo, style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Text('${req['municipality'] ?? ''}/ ${req['barangay'] ?? ''}')),
                        DataCell(Text(req['customer_name'] ?? '')),
                        DataCell(Text(
                          '${req['animal_count'] ?? 0} head(s)\n${req['livestock_type'] ?? ''}',
                        )),
                        DataCell(_buildTypeBadge(req['request_type'])),
                        DataCell(Text(req['marking'] ?? '—')),
                        DataCell(Text(_formatDate(req['preferred_date']))),
                        DataCell(
                          OutlinedButton(
                            onPressed: () {
                              // TODO: Update entry
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              side: BorderSide(color: Colors.grey.shade300),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              foregroundColor: const Color(0xFF2D3748),
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                            child: const Text('Update'),
                          ),
                        ),
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
  //  NEW REQUESTS SECTION (BARANGAY / MARKET TABS)
  // ════════════════════════════════════════════
  Widget _buildNewRequestsSection() {
    final searchQuery = _searchController.text.toLowerCase();

    List<Map<String, dynamic>> currentList =
        _pendingTabIndex == 0 ? _pendingBarangay : _pendingMarket;

    // Apply search filter
    if (searchQuery.isNotEmpty) {
      currentList = currentList.where((r) {
        final name = (r['customer_name'] ?? '').toString().toLowerCase();
        final refNo = _buildRefNo(r).toLowerCase();
        return name.contains(searchQuery) || refNo.contains(searchQuery);
      }).toList();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tabs
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              children: [
                _buildTab('Barangay New (${_pendingBarangay.length})', 0),
                const SizedBox(width: 8),
                _buildTab('Market New (${_pendingMarket.length})', 1),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Section header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _pendingTabIndex == 0
                      ? 'Barangay New Requests'
                      : 'Market New Requests',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A202C),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _pendingTabIndex == 0
                      ? 'Verify information and assign tags to approve requests from barangay'
                      : 'Verify information and assign tags to approve requests from market',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Table
          currentList.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.inbox_outlined, size: 40, color: Colors.grey.shade300),
                        const SizedBox(height: 8),
                        Text(
                          'No pending requests',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                )
              : Scrollbar(
                  controller: _pendingScrollController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  child: SingleChildScrollView(
                    controller: _pendingScrollController,
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(const Color(0xFFF7FAFC)),
                    headingTextStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4A5568),
                      fontSize: 13,
                    ),
                    dataTextStyle: const TextStyle(
                      color: Color(0xFF2D3748),
                      fontSize: 13,
                    ),
                    columnSpacing: 20,
                    horizontalMargin: 24,
                    columns: [
                      const DataColumn(label: Text('Reference #')),
                      const DataColumn(label: Text('Customer Name')),
                      const DataColumn(label: Text('Municipality')),
                      const DataColumn(label: Text('Barangay')),
                      if (_pendingTabIndex == 1)
                        const DataColumn(label: Text('Store Name')),
                      const DataColumn(label: Text('Livestock')),
                      const DataColumn(label: Text('Marking')),
                      const DataColumn(label: Text('Document')),
                      const DataColumn(label: Text('Status')),
                      const DataColumn(label: Text('Action')),
                    ],
                    rows: currentList.map((req) {
                      final refNo = _buildRefNo(req);
                      return DataRow(cells: [
                        DataCell(Text(refNo, style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Text(req['customer_name'] ?? '')),
                        DataCell(Text(req['municipality'] ?? '')),
                        DataCell(Text(req['barangay'] ?? '')),
                        if (_pendingTabIndex == 1)
                          DataCell(Text(req['market_name'] ?? '—')),
                        DataCell(Text(
                          '${req['animal_count'] ?? 0} head(s)\n${req['livestock_type'] ?? ''}',
                        )),
                        DataCell(Text(req['marking'] ?? '—')),
                        DataCell(_buildDocumentBadges(req)),
                        DataCell(_buildStatusBadge('Pending')),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildActionButton(
                                label: 'Reject',
                                color: const Color(0xFFE53E3E),
                                bgColor: const Color(0xFFFFF5F5),
                                onTap: () => _rejectRequest(req),
                              ),
                              const SizedBox(width: 6),
                              _buildActionButton(
                                label: 'Approve',
                                color: Colors.white,
                                bgColor: const Color(0xFF38A169),
                                onTap: () => _approveRequest(req),
                              ),
                            ],
                          ),
                        ),
                      ]);
                    }).toList(),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  HELPER WIDGETS
  // ════════════════════════════════════════════

  Widget _buildTab(String label, int index) {
    final isActive = _pendingTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _pendingTabIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFF7FAFC) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? Colors.grey.shade300 : Colors.grey.shade200,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            color: isActive ? const Color(0xFF2D3748) : const Color(0xFF718096),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeBadge(String? type) {
    final isBarangay = type == 'barangay';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isBarangay
            ? const Color(0xFFE6FFFA)
            : const Color(0xFFEBF4FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isBarangay ? 'Barangay' : 'Market',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isBarangay
              ? const Color(0xFF234E52)
              : const Color(0xFF2B6CB0),
        ),
      ),
    );
  }

  Widget _buildAntiMortemBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF38A169),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'PASSED',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor;
    switch (status.toLowerCase()) {
      case 'approved':
        bgColor = const Color(0xFFC6F6D5);
        textColor = const Color(0xFF22543D);
        break;
      case 'rejected':
        bgColor = const Color(0xFFFED7D7);
        textColor = const Color(0xFF822727);
        break;
      default:
        bgColor = const Color(0xFFFEFCBF);
        textColor = const Color(0xFF744210);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildDocumentBadges(Map<String, dynamic> req) {
    final List<Widget> badges = [];

    if (req['barangay_certificate'] != null) {
      badges.add(_docBadge('Barangay Cert'));
    }
    if (req['business_permit'] != null) {
      badges.add(_docBadge('Business Permit'));
    }
    if (req['proof_of_ownership'] != null) {
      badges.add(_docBadge('Proof of Ownership'));
    }
    if (req['vet_certificate'] != null) {
      badges.add(_docBadge('Vet Certificate'));
    }

    if (badges.isEmpty) {
      return const Text('—', style: TextStyle(color: Color(0xFFA0AEC0)));
    }

    return Wrap(spacing: 4, runSpacing: 4, children: badges);
  }

  Widget _docBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, color: Color(0xFF4A5568)),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  DATA HELPERS
  // ════════════════════════════════════════════
  String _buildRefNo(Map<String, dynamic> req) {
    final id = req['id'];
    final year = DateTime.now().year;
    return 'MI-$year-${id.toString().padLeft(3, '0')}';
  }

  String _formatDate(dynamic dateVal) {
    if (dateVal == null) return '—';
    try {
      final date = DateTime.parse(dateVal.toString());
      return DateFormat('dd/MM/yyyy').format(date);
    } catch (_) {
      return dateVal.toString();
    }
  }

  // ════════════════════════════════════════════
  //  NEW RECEIVING ENTRY DIALOG
  // ════════════════════════════════════════════
  void _showNewReceivingEntryDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _NewReceivingEntryDialog(
        supabase: supabase,
        onSaved: _loadRequests,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  NEW RECEIVING ENTRY DIALOG
// ═══════════════════════════════════════════════════════════
class _NewReceivingEntryDialog extends StatefulWidget {
  final dynamic supabase;
  final VoidCallback onSaved;
  const _NewReceivingEntryDialog({required this.supabase, required this.onSaved});

  @override
  State<_NewReceivingEntryDialog> createState() => _NewReceivingEntryDialogState();
}

class _NewReceivingEntryDialogState extends State<_NewReceivingEntryDialog> {
  bool _isBarangay = true;
  bool _isSaving = false;

  final _customerNameCtrl = TextEditingController();
  final _animalCountCtrl = TextEditingController();
  final _stallNumberCtrl = TextEditingController();
  final _storeNameCtrl = TextEditingController();
  final _markingCtrl = TextEditingController();

  // PSGC API address state
  List _provinces = [];
  List _municipalities = [];
  List _barangays = [];
  String? _selectedProvince;
  String? _selectedProvinceCode;
  String? _selectedMunicipality;
  String? _selectedMunicipalityCode;
  String? _selectedBarangay;
  bool _isLoadingProvinces = false;
  bool _isLoadingMunicipalities = false;
  bool _isLoadingBarangays = false;

  String? _selectedAnimalType;
  final List<String> _animalTypes = ['Cattle', 'Carabao', 'Hog', 'Goat', 'Sheep', 'Horse'];

  @override
  void initState() {
    super.initState();
    _loadProvinces();
  }

  Future<void> _loadProvinces() async {
    setState(() => _isLoadingProvinces = true);
    try {
      final response = await http.get(
        Uri.parse('https://psgc.gitlab.io/api/provinces'),
      );
      if (response.statusCode == 200) {
        setState(() {
          _provinces = jsonDecode(response.body);
        });
      }
    } catch (e) {
      debugPrint('Error loading provinces: $e');
    } finally {
      setState(() => _isLoadingProvinces = false);
    }
  }

  Future<void> _loadMunicipalities(String provinceCode) async {
    setState(() {
      _isLoadingMunicipalities = true;
      _municipalities = [];
      _barangays = [];
      _selectedMunicipality = null;
      _selectedMunicipalityCode = null;
      _selectedBarangay = null;
    });
    try {
      final response = await http.get(
        Uri.parse('https://psgc.gitlab.io/api/provinces/$provinceCode/cities-municipalities/'),
      );
      if (response.statusCode == 200) {
        setState(() {
          _municipalities = jsonDecode(response.body);
        });
      }
    } catch (e) {
      debugPrint('Error loading municipalities: $e');
    } finally {
      setState(() => _isLoadingMunicipalities = false);
    }
  }

  Future<void> _loadBarangays(String municipalityCode) async {
    setState(() {
      _isLoadingBarangays = true;
      _barangays = [];
      _selectedBarangay = null;
    });
    try {
      final response = await http.get(
        Uri.parse('https://psgc.gitlab.io/api/cities-municipalities/$municipalityCode/barangays/'),
      );
      if (response.statusCode == 200) {
        setState(() {
          _barangays = jsonDecode(response.body);
        });
      }
    } catch (e) {
      debugPrint('Error loading barangays: $e');
    } finally {
      setState(() => _isLoadingBarangays = false);
    }
  }

  @override
  void dispose() {
    _customerNameCtrl.dispose();
    _animalCountCtrl.dispose();
    _stallNumberCtrl.dispose();
    _storeNameCtrl.dispose();
    _markingCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveRecord() async {
    if (_customerNameCtrl.text.trim().isEmpty ||
        _selectedAnimalType == null ||
        _animalCountCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all required fields')),
      );
      return;
    }

    if (_isBarangay &&
        (_selectedProvince == null ||
            _selectedMunicipality == null ||
            _selectedBarangay == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select Province, Municipality, and Barangay')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await widget.supabase.from('requests').insert({
        'request_type': _isBarangay ? 'barangay' : 'market',
        'customer_name': _customerNameCtrl.text.trim(),
        'livestock_type': _selectedAnimalType,
        'animal_count': int.tryParse(_animalCountCtrl.text.trim()) ?? 0,
        'province': _isBarangay ? _selectedProvince : null,
        'municipality': _isBarangay ? _selectedMunicipality : null,
        'barangay': _isBarangay ? _selectedBarangay : null,
        'market_stall_number': _isBarangay ? null : _stallNumberCtrl.text.trim(),
        'market_name': _isBarangay ? null : _storeNameCtrl.text.trim(),
        'marking': _markingCtrl.text.trim(),
        'preferred_date': DateTime.now().toIso8601String().split('T')[0], // today's date
        'status': 'approved', // walk-in: goes directly to approved
      });

      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('New receiving entry saved successfully'),
            ]),
            backgroundColor: const Color(0xFF38A169),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving record: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──
              const Text(
                'New Animal Receiving & Inspection',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A202C)),
              ),
              const SizedBox(height: 4),
              const Text(
                'Enter customer and animal details for the new receiving entry.',
                style: TextStyle(fontSize: 13, color: Color(0xFF718096)),
              ),
              const SizedBox(height: 24),

              // ── Request Type Toggle ──
              const Text('Request Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2D3748))),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildTypeButton('Barangay', 'For barangay customer', true)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTypeButton('Market', 'For market customer', false)),
                ],
              ),
              const SizedBox(height: 20),

              // ── Customer Name ──
              _buildLabel('Customer Name'),
              const SizedBox(height: 6),
              _buildTextField(_customerNameCtrl, 'Enter customer name'),
              const SizedBox(height: 16),

              // ── Animal Type / Count / Weight ──
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Animal Type'),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          value: _selectedAnimalType,
                          hint: const Text('Select Type', style: TextStyle(fontSize: 13)),
                          decoration: _dropdownDecoration(),
                          items: _animalTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                          onChanged: (v) => setState(() => _selectedAnimalType = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Animal Count'),
                        const SizedBox(height: 6),
                        _buildTextField(_animalCountCtrl, 'e.g. 5', keyboardType: TextInputType.number),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Location / Market fields (conditional) ──
              if (_isBarangay) ..._buildBarangayFields()
              else ..._buildMarketFields(),
              const SizedBox(height: 16),

              // ── Marking ──
              _buildLabel('Marking'),
              const SizedBox(height: 6),
              _buildTextField(_markingCtrl, 'Make a tagname for the livestock..'),
              const SizedBox(height: 28),

              // ── Actions ──
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      foregroundColor: const Color(0xFF4A5568),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveRecord,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A202C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Save Record'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBarangayFields() {
    return [
      // Province
      _buildLabel('Province'),
      const SizedBox(height: 6),
      _isLoadingProvinces
          ? const SizedBox(
              height: 48,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2D6A4F))),
            )
          : DropdownButtonFormField<String>(
              value: _selectedProvince,
              isExpanded: true,
              hint: const Text('Select Province', style: TextStyle(fontSize: 13)),
              decoration: _dropdownDecoration(),
              items: _provinces.map<DropdownMenuItem<String>>((p) {
                return DropdownMenuItem<String>(
                  value: p['name'] as String,
                  child: Text(p['name'] as String, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                );
              }).toList(),
              onChanged: (value) {
                final selected = _provinces.firstWhere((p) => p['name'] == value);
                setState(() {
                  _selectedProvince = value;
                  _selectedProvinceCode = selected['code'] as String;
                });
                _loadMunicipalities(_selectedProvinceCode!);
              },
            ),
      const SizedBox(height: 16),

      // Municipality
      _buildLabel('City / Municipality'),
      const SizedBox(height: 6),
      _isLoadingMunicipalities
          ? const SizedBox(
              height: 48,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2D6A4F))),
            )
          : DropdownButtonFormField<String>(
              value: _selectedMunicipality,
              isExpanded: true,
              hint: const Text('Select Municipality', style: TextStyle(fontSize: 13)),
              decoration: _dropdownDecoration(),
              items: _municipalities.map<DropdownMenuItem<String>>((m) {
                return DropdownMenuItem<String>(
                  value: m['name'] as String,
                  child: Text(m['name'] as String, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                );
              }).toList(),
              onChanged: _selectedProvince == null
                  ? null
                  : (value) {
                      final selected = _municipalities.firstWhere((m) => m['name'] == value);
                      setState(() {
                        _selectedMunicipality = value;
                        _selectedMunicipalityCode = selected['code'] as String;
                      });
                      _loadBarangays(_selectedMunicipalityCode!);
                    },
            ),
      const SizedBox(height: 16),

      // Barangay
      _buildLabel('Barangay'),
      const SizedBox(height: 6),
      _isLoadingBarangays
          ? const SizedBox(
              height: 48,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2D6A4F))),
            )
          : DropdownButtonFormField<String>(
              value: _selectedBarangay,
              isExpanded: true,
              hint: const Text('Select Barangay', style: TextStyle(fontSize: 13)),
              decoration: _dropdownDecoration(),
              items: _barangays.map<DropdownMenuItem<String>>((b) {
                return DropdownMenuItem<String>(
                  value: b['name'] as String,
                  child: Text(b['name'] as String, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                );
              }).toList(),
              onChanged: _selectedMunicipality == null
                  ? null
                  : (value) {
                      setState(() => _selectedBarangay = value);
                    },
            ),
    ];
  }

  List<Widget> _buildMarketFields() {
    return [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabel('Stall Number'),
                const SizedBox(height: 6),
                _buildTextField(_stallNumberCtrl, 'Enter stall number'),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabel('Store Name'),
                const SizedBox(height: 6),
                _buildTextField(_storeNameCtrl, 'Enter store name'),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  Widget _buildTypeButton(String label, String sub, bool isBarangay) {
    final isActive = _isBarangay == isBarangay;
    return GestureDetector(
      onTap: () => setState(() => _isBarangay = isBarangay),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: isActive
              ? (isBarangay ? const Color(0xFFEBFFF5) : const Color(0xFFEBF4FF))
              : Colors.white,
          border: Border.all(
            color: isActive
                ? (isBarangay ? const Color(0xFF38A169) : const Color(0xFF3182CE))
                : Colors.grey.shade300,
            width: isActive ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isActive
                    ? (isBarangay ? const Color(0xFF276749) : const Color(0xFF2B6CB0))
                    : const Color(0xFF718096),
              ),
            ),
            Text(
              sub,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2D3748)));
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String hint, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
        filled: true,
        fillColor: const Color(0xFFF7FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF2D6A4F), width: 1.5)),
      ),
    );
  }

  InputDecoration _dropdownDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFFF7FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF2D6A4F), width: 1.5)),
    );
  }
}
class _RejectDialog extends StatefulWidget {
  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _controller = TextEditingController(
    text: 'Request denied — fully booked. Please select another date.',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF5F5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.block, color: Color(0xFFE53E3E), size: 22),
          ),
          const SizedBox(width: 12),
          const Text(
            'Reject Request',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D3748),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Reason for rejection (this will be sent to the customer):',
              style: TextStyle(fontSize: 13, color: Color(0xFF718096)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 3,
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFFF7FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE53E3E), width: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Color(0xFF718096))),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE53E3E),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
          child: const Text('Reject & Notify'),
        ),
      ],
    );
  }
}

import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class MeatReleasingPage extends StatefulWidget {
  const MeatReleasingPage({super.key});
  @override
  State<MeatReleasingPage> createState() => _MeatReleasingPageState();
}

class _MeatReleasingPageState extends State<MeatReleasingPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _marketRequests = [];
  List<Map<String, dynamic>> _barangayRequests = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();
  String _filterStatus = 'All';

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════
  //  LOAD REQUESTS (paid / released)
  // ════════════════════════════════════════════
  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    try {
      final data = await supabase
          .from('requests')
          .select('*, slaughter_inspection(*), payments(*)')
          .inFilter('status', ['paid', 'released'])
          .order('created_at', ascending: false);

      final enriched = List<Map<String, dynamic>>.from(data).map((r) {
        // Flatten slaughter_inspection
        final inspectionList = r['slaughter_inspection'];
        if (inspectionList is List && inspectionList.isNotEmpty) {
          final insp = inspectionList.first as Map<String, dynamic>;
          r['carcass_weight'] = insp['carcass_weight'];
        } else if (inspectionList is Map) {
          r['carcass_weight'] = inspectionList['carcass_weight'];
        }
        // Flatten payments
        final paymentsList = r['payments'];
        if (paymentsList is List && paymentsList.isNotEmpty) {
          r['payment'] = paymentsList.first as Map<String, dynamic>;
        } else if (paymentsList is Map) {
          r['payment'] = paymentsList;
        }
        return r;
      }).toList();

      setState(() {
        _marketRequests = enriched.where((r) => r['request_type'] == 'market').toList();
        _barangayRequests = enriched.where((r) => r['request_type'] == 'barangay').toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('MeatReleasing load error: $e');
      setState(() => _isLoading = false);
    }
  }

  // ════════════════════════════════════════════
  //  HELPERS
  // ════════════════════════════════════════════
  String _refNo(Map<String, dynamic> req) =>
      'MI-${DateTime.now().year}-${req['id'].toString().padLeft(3, '0')}';

  String _micNumber(Map<String, dynamic> req) {
    final type = (req['request_type'] ?? 'market').toString().toUpperCase();
    return 'MIC-$type-${req['id'].toString().padLeft(3, '0')}';
  }

  double _carcassWeight(Map<String, dynamic> req) {
    final w = req['carcass_weight'];
    if (w == null) return 0;
    return double.tryParse(w.toString()) ?? 0;
  }

  String _releaseStatus(Map<String, dynamic> req) {
    return req['status'] == 'released' ? 'Released' : 'Ready';
  }

  String _deliveryAddress(Map<String, dynamic> req) {
    final parts = <String>[];
    if (req['address'] != null && req['address'].toString().isNotEmpty) parts.add(req['address'].toString());
    if (req['barangay'] != null && req['barangay'].toString().isNotEmpty) parts.add(req['barangay'].toString());
    if (req['municipality'] != null && req['municipality'].toString().isNotEmpty) parts.add(req['municipality'].toString());
    if (req['province'] != null && req['province'].toString().isNotEmpty) parts.add(req['province'].toString());
    return parts.isNotEmpty ? parts.join(', ') : 'No address provided';
  }

  List<Map<String, dynamic>> _filteredList(List<Map<String, dynamic>> list) {
    final q = _searchController.text.toLowerCase().trim();
    return list.where((r) {
      final name = (r['customer_name'] ?? '').toString().toLowerCase();
      final ref = _refNo(r).toLowerCase();
      final status = _releaseStatus(r);

      bool matchesSearch = q.isEmpty || name.contains(q) || ref.contains(q);
      bool matchesFilter = _filterStatus == 'All' || status == _filterStatus;

      return matchesSearch && matchesFilter;
    }).toList();
  }

  // ════════════════════════════════════════════
  //  CONFIRM RELEASE ACTION
  // ════════════════════════════════════════════
  Future<void> _confirmRelease(Map<String, dynamic> req, String releasedBy, String? driverName, String? notes, String releaseType) async {
    try {
      final reqId = req['id'];
      final userId = req['user_id'];

      // Update request status & release metadata
      final updateData = <String, dynamic>{
        'status': 'released',
        'released_by': releasedBy,
        'released_at': DateTime.now().toIso8601String(),
        'release_notes': notes,
        'release_type': releaseType,
      };
      if (driverName != null && driverName.isNotEmpty) {
        updateData['driver_name'] = driverName;
      }

      await supabase.from('requests').update(updateData).eq('id', reqId);

      // Send notification to customer
      if (userId != null) {
        final isDelivery = releaseType == 'delivery';
        await supabase.from('notifications').insert({
          'user_id': userId,
          'title': isDelivery ? 'Meat Out for Delivery' : 'Meat Ready for Pickup',
          'message': isDelivery
              ? 'Your meat order is now out for delivery! The driver is on the way to your address.'
              : 'Your meat order is ready for pickup at the Tabaco City Slaughterhouse. Please collect your order at your earliest convenience.',
          'is_read': false,
          'type': isDelivery ? 'meat_delivery' : 'meat_pickup',
          'data': {
            'request_id': reqId,
            'release_type': releaseType,
          },
        });
      }

      _loadRequests();
      if (mounted) {
        Navigator.of(context).pop(); // Close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(releaseType == 'delivery'
                  ? 'Meat released for delivery!'
                  : 'Meat released for pickup!'),
            ]),
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
                    onRefresh: _loadRequests,
                    color: const Color(0xFF2D6A4F),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSummaryCards(),
                          const SizedBox(height: 24),
                          _buildFilterRow(),
                          const SizedBox(height: 24),
                          _buildTableCard(
                            title: 'Market Customer Delivery',
                            subtitle: 'Market customers receive order via delivery service',
                            requests: _filteredList(_marketRequests),
                            isMarket: true,
                          ),
                          const SizedBox(height: 24),
                          _buildTableCard(
                            title: 'Barangay Customer Delivery',
                            subtitle: 'Barangay customers receive order via Pickup',
                            requests: _filteredList(_barangayRequests),
                            isMarket: false,
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
              const Text('Meat Releasing',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
              const SizedBox(height: 2),
              Text('Ready for pickup, collection information',
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
  //  SUMMARY CARDS
  // ════════════════════════════════════════════
  Widget _buildSummaryCards() {
    final allReqs = [..._marketRequests, ..._barangayRequests];

    double totalRevenue = 0;
    double amountPending = 0;
    int paidToday = 0;
    int outstanding = 0;

    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    for (var r in allReqs) {
      final payment = r['payment'] as Map<String, dynamic>?;
      final amount = double.tryParse((payment?['total_amount'] ?? 0).toString()) ?? 0;

      if (r['status'] == 'released') {
        totalRevenue += amount;
      } else {
        amountPending += amount;
        outstanding++;
      }

      // Check if paid today
      final createdAt = payment?['created_at']?.toString() ?? '';
      if (createdAt.startsWith(todayStr)) {
        paidToday++;
      }
    }

    return Row(
      children: [
        _summaryCard(
          label: 'Total Revenue',
          value: totalRevenue.toStringAsFixed(2),
          icon: Icons.currency_exchange,
          accent: const Color(0xFF2D6A4F),
          isAmount: true,
        ),
        const SizedBox(width: 16),
        _summaryCard(
          label: 'Amount Pending',
          value: amountPending.toStringAsFixed(2),
          icon: Icons.currency_exchange,
          accent: Colors.orange,
          isAmount: true,
        ),
        const SizedBox(width: 16),
        _summaryCard(
          label: 'Paid Today',
          value: paidToday.toString(),
          icon: Icons.check_circle_outline,
          accent: const Color(0xFF2D6A4F),
        ),
        const SizedBox(width: 16),
        _summaryCard(
          label: 'Outstanding',
          value: outstanding.toString(),
          accent: Colors.red,
          showDot: true,
        ),
      ],
    );
  }

  Widget _summaryCard({
    required String label,
    required String value,
    required Color accent,
    IconData? icon,
    bool isAmount = false,
    bool showDot = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                if (showDot)
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: accent, shape: BoxShape.circle))
                else if (icon != null)
                  Icon(icon, size: 18, color: accent),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (isAmount) Text('\u20b1', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: accent)),
                if (isAmount) const SizedBox(width: 2),
                Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: accent)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  FILTER ROW
  // ════════════════════════════════════════════
  Widget _buildFilterRow() {
    return Row(
      children: [
        SizedBox(
          width: 340,
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search by reference or customer...',
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
              value: _filterStatus,
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
              items: ['All', 'Ready', 'Released']
                  .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13))))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _filterStatus = val);
              },
            ),
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════
  //  DATA TABLE CARD
  // ════════════════════════════════════════════
  Widget _buildTableCard({
    required String title,
    required String subtitle,
    required List<Map<String, dynamic>> requests,
    required bool isMarket,
  }) {
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
                  constraints: const BoxConstraints(minWidth: 1100),
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF7FAFC)),
                    dataRowMinHeight: 60,
                    dataRowMaxHeight: 80,
                    columnSpacing: 24,
                    columns: const [
                      DataColumn(label: Text('Reference #', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      DataColumn(label: Text('Customer', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      DataColumn(label: Text('Contact', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      DataColumn(label: Text('Weight', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      DataColumn(label: Text('MIC Number', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      DataColumn(label: Text('Release Date', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                    ],
                    rows: requests.map((req) {
                      final ref = _refNo(req);
                      final weight = _carcassWeight(req);
                      final mic = _micNumber(req);
                      final status = _releaseStatus(req);
                      final releasedAt = req['released_at'];

                      String releaseDateStr = 'Not Released';
                      if (releasedAt != null) {
                        try {
                          final dt = DateTime.parse(releasedAt.toString());
                          releaseDateStr = DateFormat('MM/dd/yyyy\nh:mm a').format(dt);
                        } catch (_) {}
                      }

                      return DataRow(cells: [
                        DataCell(Text(ref, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12))),
                        DataCell(Text(req['customer_name']?.toString() ?? '\u2014', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                        DataCell(Text(req['contact_number']?.toString() ?? '\u2014', style: const TextStyle(fontSize: 12))),
                        DataCell(Text(weight > 0 ? '${weight.toStringAsFixed(0)} kg' : '\u2014', style: const TextStyle(fontSize: 13))),
                        DataCell(Text(mic, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey.shade700))),
                        DataCell(_buildStatusBadge(status)),
                        DataCell(
                          status == 'Released'
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(releaseDateStr, style: const TextStyle(fontSize: 11)),
                                  ],
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.schedule, size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    const Text('Not Released', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                  ],
                                ),
                        ),
                        DataCell(
                          status == 'Released'
                              ? _buildDoneButton(req)
                              : isMarket
                                  ? _buildReleaseForDeliveryButton(req)
                                  : _buildReleaseForPickupButton(req),
                        ),
                      ]);
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
          if (requests.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text('No requests found', style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  STATUS BADGE
  // ════════════════════════════════════════════
  Widget _buildStatusBadge(String status) {
    final isReleased = status == 'Released';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: isReleased
            ? Colors.orange.shade50
            : const Color(0xFFE6F9F0),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isReleased ? Colors.orange.shade200 : const Color(0xFF2D6A4F).withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isReleased ? Colors.orange.shade700 : const Color(0xFF2D6A4F),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  ACTION BUTTONS
  // ════════════════════════════════════════════
  Widget _buildReleaseForDeliveryButton(Map<String, dynamic> req) {
    return OutlinedButton(
      onPressed: () => _showReleaseDialog(req, isDelivery: true),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF2D6A4F),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(0, 34),
        side: const BorderSide(color: Color(0xFF2D6A4F)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: const Text('Release for Delivery', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildReleaseForPickupButton(Map<String, dynamic> req) {
    return OutlinedButton(
      onPressed: () => _showReleaseDialog(req, isDelivery: false),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF2D6A4F),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(0, 34),
        side: const BorderSide(color: Color(0xFF2D6A4F)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: const Text('Release for Pickup', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildDoneButton(Map<String, dynamic> req) {

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFE6F9F0),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF2D6A4F).withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, size: 14, color: Color(0xFF2D6A4F)),
              const SizedBox(width: 4),
              const Text('Done', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF2D6A4F))),
            ],
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════
  //  RELEASE DIALOG
  // ════════════════════════════════════════════
  void _showReleaseDialog(Map<String, dynamic> req, {required bool isDelivery}) {
    final releaseByCtrl = TextEditingController();
    final driverNameCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final weight = _carcassWeight(req);
    final ref = _refNo(req);
    final livestock = req['livestock_type']?.toString() ?? '\u2014';
    final animalCount = req['animal_count'] ?? 1;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 520,
            padding: const EdgeInsets.all(28),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    isDelivery ? 'Release for Delivery' : 'Release for Pickup',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A202C)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Confirm release of meat for ${req['customer_name'] ?? 'Customer'}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 24),

                  // Info Row
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Reference Number', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
                            const SizedBox(height: 4),
                            Text(ref, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Customer', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
                            const SizedBox(height: 4),
                            Text(req['customer_name']?.toString() ?? '\u2014', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
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
                            const Text('Livestock', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
                            const SizedBox(height: 4),
                            Text('$livestock ($animalCount)', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Carcass Weight', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
                            const SizedBox(height: 4),
                            Text(weight > 0 ? '${weight.toStringAsFixed(0)} kg' : '\u2014', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Delivery Address (market only)
                  if (isDelivery) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6F9F0),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF2D6A4F).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on, color: Color(0xFF2D6A4F), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Delivery Address:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF2D6A4F))),
                                const SizedBox(height: 2),
                                Text(_deliveryAddress(req), style: const TextStyle(fontSize: 13, color: Color(0xFF2D6A4F))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Release By
                  const Text('Release By', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: releaseByCtrl,
                    decoration: InputDecoration(
                      hintText: 'Enter your name...',
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Driver Name (delivery only)
                  if (isDelivery) ...[
                    const Text('Driver Name', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: driverNameCtrl,
                      decoration: InputDecoration(
                        hintText: 'Enter name...',
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
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
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Notes
                  const Text('Notes (Optional)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Any additional notes...',
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF4A5568),
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        ),
                        child: const Text('Cancel', style: TextStyle(fontSize: 13)),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () {
                          if (releaseByCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter your name in "Release By"'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                            return;
                          }
                          _confirmRelease(
                            req,
                            releaseByCtrl.text.trim(),
                            isDelivery ? driverNameCtrl.text.trim() : null,
                            notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null,
                            isDelivery ? 'delivery' : 'pickup',
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2D3748),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        ),
                        child: const Text('Confirm Release', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

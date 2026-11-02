import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../services/notification_service.dart';
import '../services/app_settings_service.dart';

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
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _loadRequests();
    // Auto-poll every 3 seconds so paid orders appear automatically
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _loadRequests(silent: true);
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════
  //  LOAD REQUESTS (paid / released)
  // ════════════════════════════════════════════
  Future<void> _loadRequests({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final data = await supabase
          .from('requests')
          .select('*, slaughter_inspection(*), payments(*)')
          .inFilter('status', ['paid', 'released', 'releasable', 'mic_generated', 'payment_pending', 'out_for_delivery'])
          .order('created_at', ascending: false);

      // Fetch system_settings for 'authorized_representatives' fallback if needed
      Map<String, dynamic> repMap = {};
      try {
        final repRow = await supabase
            .from('system_settings')
            .select('value')
            .eq('key', 'authorized_representatives')
            .maybeSingle();
        if (repRow != null && repRow['value'] is Map) {
          repMap = Map<String, dynamic>.from(repRow['value']);
        }
      } catch (_) {}

      final enriched = List<Map<String, dynamic>>.from(data).map((r) {
        final reqIdStr = r['id'].toString();
        if (repMap.containsKey(reqIdStr) && (r['authorized_person_name'] == null || r['authorized_person_name'].toString().isEmpty)) {
          final savedRep = repMap[reqIdStr] as Map<String, dynamic>?;
          if (savedRep != null) {
            r['authorized_person_name'] = savedRep['name'];
            r['authorized_person_contact'] = savedRep['contact'];
            r['authorized_person_relationship'] = savedRep['relationship'];
            r['authorized_person_id_type'] = savedRep['id_type'];
            r['authorized_person_id_num'] = savedRep['id_num'];
          }
        }
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

      if (mounted) {
        setState(() {
          _marketRequests = enriched.where((r) => r['request_type'] == 'market').toList();
          _barangayRequests = enriched.where((r) => r['request_type'] == 'barangay').toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('MeatReleasing load error: $e');
      if (mounted && !silent) setState(() => _isLoading = false);
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

  DateTime _getPickupDeadline(Map<String, dynamic> req) {
    DateTime baseDate = DateTime.now();
    final payment = req['payment'] as Map<String, dynamic>?;
    final createdStr = payment?['updated_at'] ?? payment?['created_at'] ?? req['created_at'];
    if (createdStr != null) {
      final parsed = DateTime.tryParse(createdStr.toString());
      if (parsed != null) baseDate = parsed.toLocal();
    }
    return DateTime(baseDate.year, baseDate.month, baseDate.day, 17, 0, 0);
  }

  bool _isPickupOverdue(Map<String, dynamic> req) {
    if (req['status'] == 'released') return false;
    if (req['request_type'] != 'barangay') return false;
    final deadline = _getPickupDeadline(req);
    return DateTime.now().isAfter(deadline);
  }

  bool _isPaid(Map<String, dynamic> req) {
    if (req['status'] == 'released') return true;
    final payment = req['payment'] as Map<String, dynamic>?;
    final payStatus = payment?['status']?.toString().toLowerCase();
    final reqStatus = req['status']?.toString().toLowerCase();
    return payStatus == 'paid' || reqStatus == 'paid';
  }

  String _releaseStatus(Map<String, dynamic> req) {
    if (req['status'] == 'released') return 'Released';
    if (req['status'] == 'out_for_delivery') {
      if (!_isPaid(req)) {
        return 'Out for Delivery (Unpaid)';
      }
      return 'Out for Delivery';
    }
    if (req['request_type'] == 'market' && !_isPaid(req)) {
      return 'Awaiting Payment Verification';
    }
    if (req['request_type'] == 'barangay' && !_isPaid(req)) {
      return 'Awaiting Cashier Payment';
    }
    return 'Ready';
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
      bool matchesFilter;
      if (_filterStatus == 'All') {
        matchesFilter = true;
      } else if (_filterStatus == 'Awaiting Payment') {
        matchesFilter = status.contains('Awaiting') || status.contains('Unpaid');
      } else {
        matchesFilter = status == _filterStatus;
      }

      return matchesSearch && matchesFilter;
    }).toList();
  }

  // ════════════════════════════════════════════
  //  CONFIRM RELEASE ACTION
  // ════════════════════════════════════════════
  Future<void> _confirmRelease({
    required Map<String, dynamic> req,
    required String releasedBy,
    required String dispatcherStaffId,
    required String claimantName,
    required String claimantType,
    required String claimantIdRef,
    required bool coldStorageFeeCollected,
    required String releaseType,
    String? driverName,
    String? notes,
  }) async {
    try {
      final reqId = req['id'];
      final userId = req['user_id'];
      final ref = _refNo(req);

      final fullNotes = [
        'Claimant: $claimantName ($claimantType${claimantType == "Customer" ? " - Owner Direct" : " | ID: ${claimantIdRef.isNotEmpty ? claimantIdRef : 'Verified'}"})',
        'Dispatcher/Clerk: $releasedBy (Staff ID: ${dispatcherStaffId.isNotEmpty ? dispatcherStaffId : "EMP-01"})',
        if (coldStorageFeeCollected) 'Cold storage fee of \u20b1150.00 collected by clerk ($releasedBy).',
        if (notes != null && notes.isNotEmpty) notes,
      ].join(' | ');

      final updateData = <String, dynamic>{
        'status': 'released',
        'released_by': releasedBy,
        'dispatcher_staff_id': dispatcherStaffId,
        'claimant_name': claimantName,
        'claimant_type': claimantType,
        'claimant_id_num': claimantType == 'Customer' ? 'Owner Direct' : claimantIdRef,
        'released_at': DateTime.now().toIso8601String(),
        'release_notes': fullNotes,
        'release_type': releaseType,
      };
      if (driverName != null && driverName.isNotEmpty) {
        updateData['driver_name'] = driverName;
      }

      final baseUpdateData = <String, dynamic>{
        'status': 'released',
        'released_by': releasedBy,
        'released_at': DateTime.now().toIso8601String(),
        'release_notes': fullNotes,
        'release_type': releaseType,
      };
      if (driverName != null && driverName.isNotEmpty) {
        baseUpdateData['driver_name'] = driverName;
      }

      try {
        await supabase.from('requests').update(updateData).eq('id', reqId);
      } catch (err) {
        debugPrint('Extended columns not present in requests table, falling back to base schema: $err');
        await supabase.from('requests').update(baseUpdateData).eq('id', reqId);
      }

      // Send immutable confirmation notification to customer's mobile app
      final isDelivery = releaseType == 'delivery';
      final formattedTime = DateFormat('h:mm a, MMMM d, yyyy').format(DateTime.now());

      await NotificationService.sendNotificationSafely(
        supabase,
        userId: userId,
        title: isDelivery ? 'Meat Delivery Handover Confirmed' : 'Meat Handover Confirmed',
        message: isDelivery
            ? 'Your meat order (Ref: $ref) has been safely delivered to your stall by driver $driverName at $formattedTime. Verified by clerk $releasedBy (Staff ID: $dispatcherStaffId).'
            : 'Your meat order (Ref: $ref) was officially verified and released to $claimantType "$claimantName" (ID: $claimantIdRef) at $formattedTime. Verified by Meat Releasing Clerk $releasedBy (Staff ID: $dispatcherStaffId). Thank you!',
        type: 'meat_released_confirmed',
        data: {
          'request_id': reqId,
          'reference_no': ref,
          'claimant_name': claimantName,
          'claimant_type': claimantType,
          'claimant_id_ref': claimantIdRef,
          'released_by': releasedBy,
          'dispatcher_staff_id': dispatcherStaffId,
          'release_type': releaseType,
          'cold_storage_fee': coldStorageFeeCollected ? 150 : 0,
          'verified_at': formattedTime,
        },
      );

      _loadRequests();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.verified, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(isDelivery
                  ? 'Delivery confirmed & verified! Customer notified.'
                  : 'Meat handover verified & released! Customer notified.'),
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
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => _loadRequests(),
            icon: const Icon(Icons.refresh, size: 20),
            color: const Color(0xFF2D3748),
          ),
          const SizedBox(width: 4),
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
              items: ['All', 'Ready', 'Awaiting Payment', 'Out for Delivery', 'Released']
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
                        DataCell(_buildStatusBadge(status, isOverdue: _isPickupOverdue(req))),
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
  Widget _buildStatusBadge(String status, {bool isOverdue = false}) {
    Color bgColor = const Color(0xFFE6F9F0);
    Color borderColor = const Color(0xFF2D6A4F).withValues(alpha: 0.3);
    Color textColor = const Color(0xFF2D6A4F);
    String label = status;

    if (status == 'Released') {
      bgColor = Colors.orange.shade50;
      borderColor = Colors.orange.shade200;
      textColor = Colors.orange.shade700;
    } else if (status == 'Out for Delivery') {
      bgColor = const Color(0xFFEBF8FF);
      borderColor = const Color(0xFFBEE3F8);
      textColor = const Color(0xFF2B6CB0);
    } else if (status == 'Out for Delivery (Unpaid)') {
      bgColor = const Color(0xFFFFFBEB);
      borderColor = const Color(0xFFFCD34D);
      textColor = const Color(0xFFB45309);
    } else if (status == 'Awaiting Cashier Payment' || status == 'Awaiting Payment Verification') {
      bgColor = const Color(0xFFFEF3C7);
      borderColor = const Color(0xFFFCD34D);
      textColor = const Color(0xFFB45309);
    } else if (isOverdue) {
      bgColor = const Color(0xFFFFF5F5);
      borderColor = const Color(0xFFFEB2B2);
      textColor = const Color(0xFFC53030);
      label = 'Overdue (Cold Storage +\u20b1150)';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  ACTION BUTTONS
  // ════════════════════════════════════════════
  Widget _buildReleaseForDeliveryButton(Map<String, dynamic> req) {
    final isOutForDelivery = req['status'] == 'out_for_delivery';
    final isPaid = _isPaid(req);

    if (isOutForDelivery) {
      if (!isPaid) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: 'Payment not yet verified by clerk. Delivery completion is locked.',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFCD34D)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.lock_clock, size: 14, color: Color(0xFFB45309)),
                    SizedBox(width: 4),
                    Text(
                      'Unpaid: Awaiting Clerk Verification',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFB45309)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Revert premature dispatch back to Payment Pending until clerk verifies payment.',
              child: OutlinedButton.icon(
                icon: const Icon(Icons.undo, size: 14),
                label: const Text('Recall Dispatch', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                onPressed: () => _showRecallDispatchDialog(req),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFC53030),
                  backgroundColor: const Color(0xFFFFF5F5),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 34),
                  side: const BorderSide(color: Color(0xFFFEB2B2)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ),
          ],
        );
      }
      return _buildConfirmDeliveryButton(req);
    }

    if (!isPaid) {
      return Tooltip(
        message: 'Payment not yet verified by clerk. Dispatching delivery van is locked.',
        child: OutlinedButton.icon(
          icon: const Icon(Icons.lock_clock, size: 14, color: Color(0xFFB45309)),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Payment not yet verified by clerk. Please wait for payment verification in Cashiering before dispatching.'),
                backgroundColor: Color(0xFFD97706),
              ),
            );
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFB45309),
            backgroundColor: const Color(0xFFFFFBEB),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 34),
            side: const BorderSide(color: Color(0xFFFCD34D)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          label: const Text('Awaiting Payment Verification', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      );
    }

    return OutlinedButton.icon(
      icon: const Icon(Icons.local_shipping, size: 14),
      onPressed: () => _showMarketDispatchDialog(req),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF185FA5),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(0, 34),
        side: const BorderSide(color: Color(0xFF185FA5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      label: const Text('Dispatch Van', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildConfirmDeliveryButton(Map<String, dynamic> req) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.done_all, size: 14),
      onPressed: () => _showConfirmDeliveryDialog(req),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1E855A),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 34),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      label: const Text('Confirm Delivered', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildReleaseForPickupButton(Map<String, dynamic> req) {
    if (!_isPaid(req)) {
      return _buildAwaitingPaymentButton(req);
    }
    return OutlinedButton(
      onPressed: () => _showReleaseDialog(req, isDelivery: false),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF2D6A4F),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(0, 34),
        side: const BorderSide(color: Color(0xFF2D6A4F)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: const Text('Verify Handover', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildAwaitingPaymentButton(Map<String, dynamic> req) {
    return Tooltip(
      message: 'Claimant must settle cash payment at the Cashier window first',
      child: OutlinedButton.icon(
        icon: const Icon(Icons.lock_clock, size: 14, color: Color(0xFFB45309)),
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment not yet verified. Please advise customer to pay at the Cashier window first.'),
              backgroundColor: Color(0xFFD97706),
            ),
          );
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFB45309),
          backgroundColor: const Color(0xFFFFFBEB),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 34),
          side: const BorderSide(color: Color(0xFFFCD34D)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        label: const Text('Awaiting Payment', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      ),
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
  //  MARKET DELIVERY WORKFLOW (2-PHASE)
  // ════════════════════════════════════════════
  void _showMarketDispatchDialog(Map<String, dynamic> req) {
    if (!_isPaid(req)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot dispatch delivery van: payment has not been verified by the cashier/clerk.'),
          backgroundColor: Color(0xFFD97706),
        ),
      );
      return;
    }
    final driverNameCtrl = TextEditingController(text: req['driver_name']?.toString() ?? '');
    final plateCtrl = TextEditingController(text: req['driver_plate']?.toString() ?? '');
    final notesCtrl = TextEditingController();
    final ref = _refNo(req);
    final customer = req['customer_name']?.toString() ?? 'Market Customer';
    final address = _deliveryAddress(req);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.local_shipping, color: Color(0xFF185FA5), size: 24),
            SizedBox(width: 8),
            Text('Dispatch Delivery Van', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Assign delivery van to deliver meat order to $customer.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order: $ref | $customer', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF166534))),
                    const SizedBox(height: 4),
                    Text('Delivery Address: $address', style: const TextStyle(fontSize: 11, color: Color(0xFF166534))),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Driver Name *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              TextField(
                controller: driverNameCtrl,
                decoration: InputDecoration(
                  hintText: 'e.g. Juan Perez',
                  filled: true,
                  fillColor: const Color(0xFFF7FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Vehicle Plate Number (Optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              TextField(
                controller: plateCtrl,
                decoration: InputDecoration(
                  hintText: 'e.g. ABC-1234',
                  filled: true,
                  fillColor: const Color(0xFFF7FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Dispatch Notes (Optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Any special instructions...',
                  filled: true,
                  fillColor: const Color(0xFFF7FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            icon: const Icon(Icons.send, size: 16),
            onPressed: () async {
              final driver = driverNameCtrl.text.trim();
              if (driver.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter driver name'), backgroundColor: Colors.redAccent),
                );
                return;
              }
              Navigator.pop(ctx);
              await _dispatchMarketOrder(
                req: req,
                driverName: driver,
                plate: plateCtrl.text.trim(),
                notes: notesCtrl.text.trim(),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF185FA5),
              foregroundColor: Colors.white,
            ),
            label: const Text('Confirm Dispatch & Notify'),
          ),
        ],
      ),
    );
  }

  Future<void> _dispatchMarketOrder({
    required Map<String, dynamic> req,
    required String driverName,
    required String plate,
    String? notes,
  }) async {
    try {
      final reqId = req['id'];
      final userId = req['user_id'];
      final ref = _refNo(req);

      final fullNotes = [
        'Dispatched via delivery van. Driver: $driverName ${plate.isNotEmpty ? "($plate)" : ""}',
        if (notes != null && notes.isNotEmpty) notes,
      ].join(' | ');

      try {
        await supabase.from('requests').update({
          'status': 'out_for_delivery',
          'driver_name': driverName,
          'driver_plate': plate,
          'release_notes': fullNotes,
          'release_type': 'delivery',
        }).eq('id', reqId);
      } catch (_) {
        await supabase.from('requests').update({
          'status': 'out_for_delivery',
          'driver_name': driverName,
          'release_notes': fullNotes,
          'release_type': 'delivery',
        }).eq('id', reqId);
      }

      final formattedTime = DateFormat('h:mm a, MMMM d, yyyy').format(DateTime.now());
      await NotificationService.sendNotificationSafely(
        supabase,
        userId: userId,
        title: 'Meat Out for Delivery',
        message: 'Your meat order (Ref: $ref) is now out for delivery to your stall by driver $driverName ${plate.isNotEmpty ? "($plate)" : ""}. Expected arrival today.',
        type: 'meat_delivery',
        data: {
          'request_id': reqId,
          'reference_no': ref,
          'driver_name': driverName,
          'driver_plate': plate,
          'release_type': 'delivery',
          'delivery_status': 'out_for_delivery',
          'dispatched_at': formattedTime,
        },
      );

      _loadRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(children: [
              Icon(Icons.local_shipping, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Delivery van dispatched! Customer notified.'),
            ]),
            backgroundColor: Color(0xFF185FA5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error dispatching delivery: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showRecallDispatchDialog(Map<String, dynamic> req) {
    final ref = _refNo(req);
    final customer = req['customer_name']?.toString() ?? 'Customer';
    final payment = req['payment'] as Map<String, dynamic>?;
    final amount = double.tryParse((payment?['total_amount'] ?? 0).toString()) ?? 0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 24),
            SizedBox(width: 8),
            Text('Recall Premature Dispatch', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Order $ref ($customer) was marked Out for Delivery before payment of \u20b1${amount.toStringAsFixed(2)} was verified by the cashier.',
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFCD34D)),
                ),
                child: const Text(
                  'Recalling this dispatch will revert its status back to "Payment Pending". Once the cashier verifies payment in Payment & Cashiering, the "Dispatch Van" button will be unlocked.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep As Is'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.undo, size: 16),
            onPressed: () async {
              Navigator.pop(ctx);
              await _recallDispatch(req);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD97706),
              foregroundColor: Colors.white,
            ),
            label: const Text('Confirm Recall to Payment Pending'),
          ),
        ],
      ),
    );
  }

  Future<void> _recallDispatch(Map<String, dynamic> req) async {
    try {
      final reqId = req['id'];
      final userId = req['user_id'];
      final ref = _refNo(req);

      try {
        await supabase.from('requests').update({
          'status': 'payment_pending',
          'driver_name': null,
          'driver_plate': null,
          'release_type': null,
          'release_notes': 'Premature dispatch recalled pending cashier payment verification.',
        }).eq('id', reqId);
      } catch (_) {
        await supabase.from('requests').update({
          'status': 'payment_pending',
          'release_notes': 'Premature dispatch recalled pending cashier payment verification.',
        }).eq('id', reqId);
      }

      if (userId != null) {
        try {
          await NotificationService.sendNotificationSafely(
            supabase,
            userId: userId,
            title: 'Delivery Schedule Update',
            message: 'Order (Ref: $ref) delivery dispatch has been recalled pending cashier payment confirmation.',
            type: 'meat_delivery',
            data: {
              'request_id': reqId,
              'reference_no': ref,
              'status': 'payment_pending',
            },
          );
        } catch (_) {}
      }

      _loadRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('Order $ref recalled to Payment Pending.'),
              ],
            ),
            backgroundColor: const Color(0xFF2D6A4F),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error recalling dispatch: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showConfirmDeliveryDialog(Map<String, dynamic> req) {
    if (!_isPaid(req)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot confirm delivery: order is unpaid. Payment must be verified by the clerk first.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    final driverName = req['driver_name']?.toString() ?? 'Assigned driver';
    final defaultClerk = AppSettingsService.instance.profileName.isNotEmpty
        ? AppSettingsService.instance.profileName
        : 'Elena Santos';
    final dispatcherCtrl = TextEditingController(text: defaultClerk);
    final ref = _refNo(req);
    final customer = req['customer_name']?.toString() ?? 'Market Customer';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.check_circle, color: Color(0xFF1E855A), size: 24),
            SizedBox(width: 8),
            Text('Confirm Delivery Completed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Driver $driverName has returned and reported successful delivery of order $ref to $customer.',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 16),
              const Text('Verifying Dispatcher / Clerk *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              TextField(
                controller: dispatcherCtrl,
                decoration: InputDecoration(
                  hintText: 'Enter verifying staff name...',
                  filled: true,
                  fillColor: const Color(0xFFF7FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              final clerk = dispatcherCtrl.text.trim();
              if (clerk.isEmpty) return;
              Navigator.pop(ctx);
              await _completeMarketDelivery(
                req: req,
                verifiedBy: clerk,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E855A),
              foregroundColor: Colors.white,
            ),
            label: const Text('Confirm Delivery Complete'),
          ),
        ],
      ),
    );
  }

  Future<void> _completeMarketDelivery({
    required Map<String, dynamic> req,
    required String verifiedBy,
  }) async {
    try {
      final reqId = req['id'];
      final userId = req['user_id'];
      final ref = _refNo(req);
      final driverName = req['driver_name']?.toString() ?? 'Assigned driver';

      final fullNotes = [
        'Delivered to market stall by driver $driverName.',
        'Verified on driver return by dispatcher $verifiedBy.',
        if (req['release_notes'] != null) req['release_notes'].toString(),
      ].join(' | ');

      try {
        await supabase.from('requests').update({
          'status': 'released',
          'released_by': verifiedBy,
          'released_at': DateTime.now().toIso8601String(),
          'release_notes': fullNotes,
          'release_type': 'delivery',
        }).eq('id', reqId);
      } catch (err) {
        await supabase.from('requests').update({
          'status': 'released',
          'released_by': verifiedBy,
          'released_at': DateTime.now().toIso8601String(),
          'release_notes': fullNotes,
        }).eq('id', reqId);
      }

      final formattedTime = DateFormat('h:mm a, MMMM d, yyyy').format(DateTime.now());
      await NotificationService.sendNotificationSafely(
        supabase,
        userId: userId,
        title: 'Meat Delivered Successfully',
        message: 'Your meat order (Ref: $ref) has been safely delivered to your stall by driver $driverName at $formattedTime. Verified by dispatcher $verifiedBy. Thank you!',
        type: 'meat_released_confirmed',
        data: {
          'request_id': reqId,
          'reference_no': ref,
          'driver_name': driverName,
          'released_by': verifiedBy,
          'release_type': 'delivery',
          'delivery_status': 'delivered',
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
              Text('Delivery completed and confirmed! Customer notified.'),
            ]),
            backgroundColor: Color(0xFF1E855A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error completing delivery: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ════════════════════════════════════════════
  //  RELEASE DIALOG
  // ════════════════════════════════════════════
  void _showReleaseDialog(Map<String, dynamic> req, {required bool isDelivery}) {
    final defaultClerk = AppSettingsService.instance.profileName.isNotEmpty
        ? AppSettingsService.instance.profileName
        : 'Elena Santos';
    final releaseByCtrl = TextEditingController(text: defaultClerk);
    final dispatcherStaffIdCtrl = TextEditingController(text: 'EMP-01');
    final customerName = req['customer_name']?.toString() ?? '';
    final authName = req['authorized_person_name']?.toString() ?? '';
    final authContact = req['authorized_person_contact']?.toString() ?? '';
    final authIdType = req['authorized_person_id_type']?.toString() ?? '';
    final authIdNum = req['authorized_person_id_num']?.toString() ?? '';
    final authRel = req['authorized_person_relationship']?.toString() ?? '';
    final hasAuthPerson = authName.trim().isNotEmpty;

    String claimantType = 'Customer';
    final claimantNameCtrl = TextEditingController(text: customerName);
    final claimantIdRefCtrl = TextEditingController();
    final driverNameCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final isOverdue = _isPickupOverdue(req);
    bool coldStorageFeeCollected = isOverdue;
    final weight = _carcassWeight(req);
    final ref = _refNo(req);
    final livestock = req['livestock_type']?.toString() ?? '\u2014';
    final animalCount = req['animal_count'] ?? 1;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: 540,
                padding: const EdgeInsets.all(28),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Row(
                        children: [
                          Icon(
                            isDelivery ? Icons.local_shipping : Icons.verified_user,
                            color: const Color(0xFF2D6A4F),
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isDelivery ? 'Verify Dispatch & Delivery' : 'Verify Handover & Release',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A202C)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isDelivery
                            ? 'Record driver dispatch details and notify customer of scheduled delivery.'
                            : 'Verify dual-party identity (claimant and releasing staff) to eliminate non-receipt claims.',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 20),

                      // Cold Storage Overdue Alert (if pickup and past 5:00 PM)
                      if (!isDelivery && isOverdue) ...[
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
                              Row(
                                children: const [
                                  Icon(Icons.ac_unit, color: Color(0xFFC53030), size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'Cold Storage Fee Applicable (\u20b1150.00)',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF9B2C2C)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'The 5:00 PM pickup deadline has passed. This carcass was preserved in abattoir cold storage. Collect \u20b1150.00 from the claimant upon release.',
                                style: TextStyle(fontSize: 12, color: Color(0xFF9B2C2C)),
                              ),
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: () => setDialogState(() => coldStorageFeeCollected = !coldStorageFeeCollected),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: coldStorageFeeCollected,
                                      activeColor: const Color(0xFFC53030),
                                      onChanged: (val) => setDialogState(() => coldStorageFeeCollected = val ?? false),
                                    ),
                                    const Expanded(
                                      child: Text(
                                        'Collected \u20b1150.00 Cold Storage Fee from Claimant',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF9B2C2C)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

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
                                Text(customerName.isNotEmpty ? customerName : '\u2014', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Livestock', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
                                const SizedBox(height: 4),
                                Text('$livestock ($animalCount head)', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
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
                      const SizedBox(height: 16),

                      // Delivery Address (market only)
                      if (isDelivery) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6F9F0),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF2D6A4F).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on, color: Color(0xFF2D6A4F), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_deliveryAddress(req), style: const TextStyle(fontSize: 12, color: Color(0xFF2D6A4F))),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Claimant Details (Verification handshake)
                      if (!isDelivery) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF86EFAC)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.badge_outlined, color: Color(0xFF166534), size: 18),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Claimant Designation',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF166534)),
                                  ),
                                  const Spacer(),
                                  if (hasAuthPerson)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDCFCE7),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: const Color(0xFF22C55E)),
                                      ),
                                      child: const Text(
                                        'Authorized Rep On File',
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              const Text('Who is physically claiming the carcass?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: () {
                                        setDialogState(() {
                                          claimantType = 'Customer';
                                          claimantNameCtrl.text = customerName;
                                          claimantIdRefCtrl.text = '';
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                        decoration: BoxDecoration(
                                          color: claimantType == 'Customer' ? Colors.white : Colors.transparent,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: claimantType == 'Customer' ? const Color(0xFF166534) : Colors.grey.shade300,
                                            width: claimantType == 'Customer' ? 1.5 : 1,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              claimantType == 'Customer' ? Icons.radio_button_checked : Icons.radio_button_off,
                                              size: 16,
                                              color: claimantType == 'Customer' ? const Color(0xFF166534) : Colors.grey,
                                            ),
                                            const SizedBox(width: 6),
                                            const Expanded(
                                              child: Text('Customer Direct', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () {
                                        setDialogState(() {
                                          claimantType = 'Authorized Representative';
                                          if (hasAuthPerson) {
                                            claimantNameCtrl.text = authName;
                                            claimantIdRefCtrl.text = authIdNum.isNotEmpty ? '$authIdType: $authIdNum' : '';
                                          }
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                        decoration: BoxDecoration(
                                          color: claimantType == 'Authorized Representative' ? Colors.white : Colors.transparent,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: claimantType == 'Authorized Representative' ? const Color(0xFF166534) : Colors.grey.shade300,
                                            width: claimantType == 'Authorized Representative' ? 1.5 : 1,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              claimantType == 'Authorized Representative' ? Icons.radio_button_checked : Icons.radio_button_off,
                                              size: 16,
                                              color: claimantType == 'Authorized Representative' ? const Color(0xFF166534) : Colors.grey,
                                            ),
                                            const SizedBox(width: 6),
                                            const Expanded(
                                              child: Text('Authorized Rep', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (hasAuthPerson && claimantType == 'Authorized Representative') ...[
                                const SizedBox(height: 10),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFF86EFAC)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Pre-Authorized: $authName ${authRel.isNotEmpty ? "($authRel)" : ""}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF15803D))),
                                      if (authContact.isNotEmpty)
                                        Text('Contact: $authContact', style: const TextStyle(fontSize: 11, color: Color(0xFF4B5563))),
                                      if (authIdType.isNotEmpty || authIdNum.isNotEmpty)
                                        Text('Pre-registered ID: $authIdType $authIdNum', style: const TextStyle(fontSize: 11, color: Color(0xFF4B5563))),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        Text(
                          claimantType == 'Customer' ? 'Customer Full Name' : 'Authorized Representative Name',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: claimantNameCtrl,
                          decoration: InputDecoration(
                            hintText: 'Name of person physically claiming carcass...',
                            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                            filled: true,
                            fillColor: const Color(0xFFF7FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                        ),
                        const SizedBox(height: 14),

                        if (claimantType == 'Authorized Representative') ...[
                          const Text(
                            'Representative Valid ID & Number *',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: claimantIdRefCtrl,
                            decoration: InputDecoration(
                              hintText: 'e.g. National ID: 1234-5678-9012 (Must inspect physical ID)',
                              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                              filled: true,
                              fillColor: const Color(0xFFF7FAFC),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                      ],

                      // Driver Name (delivery only)
                      if (isDelivery) ...[
                        const Text('Driver Name / Vehicle Plate', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: driverNameCtrl,
                          decoration: InputDecoration(
                            hintText: 'Driver name and delivery van plate...',
                            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                            filled: true,
                            fillColor: const Color(0xFFF7FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Releasing Clerk & Staff Employee ID
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Releasing Staff / Clerk', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                TextField(
                                  controller: releaseByCtrl,
                                  decoration: InputDecoration(
                                    hintText: 'Enter verifying staff name...',
                                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                                    filled: true,
                                    fillColor: const Color(0xFFF7FAFC),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Staff Employee ID', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                TextField(
                                  controller: dispatcherStaffIdCtrl,
                                  decoration: InputDecoration(
                                    hintText: 'e.g. EMP-01',
                                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                                    filled: true,
                                    fillColor: const Color(0xFFF7FAFC),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Notes
                      const Text('Handover / Dispatch Notes (Optional)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: notesCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Any carcass condition notes, receipt references, etc...',
                          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                          filled: true,
                          fillColor: const Color(0xFFF7FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 24),

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
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            ),
                            child: const Text('Cancel', style: TextStyle(fontSize: 13)),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.verified, size: 16),
                            onPressed: () {
                              if (releaseByCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please enter staff name in "Releasing Staff"'), backgroundColor: Colors.redAccent),
                                );
                                return;
                              }
                              if (dispatcherStaffIdCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please enter Dispatcher / Staff Employee ID'), backgroundColor: Colors.redAccent),
                                );
                                return;
                              }
                              if (!isDelivery && claimantNameCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please enter Claimant Full Name'), backgroundColor: Colors.redAccent),
                                );
                                return;
                              }
                              if (!isDelivery && claimantType == 'Authorized Representative' && claimantIdRefCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please enter Representative Valid ID & Number'), backgroundColor: Colors.redAccent),
                                );
                                return;
                              }
                              _confirmRelease(
                                req: req,
                                releasedBy: releaseByCtrl.text.trim(),
                                dispatcherStaffId: dispatcherStaffIdCtrl.text.trim(),
                                claimantType: claimantType,
                                claimantName: claimantNameCtrl.text.trim(),
                                claimantIdRef: claimantType == 'Customer'
                                    ? 'Owner Direct'
                                    : claimantIdRefCtrl.text.trim(),
                                coldStorageFeeCollected: coldStorageFeeCollected,
                                releaseType: isDelivery ? 'delivery' : 'pickup',
                                driverName: isDelivery ? driverNameCtrl.text.trim() : null,
                                notes: notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null,
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E855A),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            ),
                            label: Text(
                              isDelivery ? 'Confirm Dispatch' : 'Confirm Handover & Verified',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
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
      },
    );
  }


}

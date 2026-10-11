import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../services/app_settings_service.dart';
import '../services/notification_service.dart';

class PaymentCashieringPage extends StatefulWidget {
  const PaymentCashieringPage({super.key});
  @override
  State<PaymentCashieringPage> createState() => _PaymentCashieringPageState();
}

class _PaymentCashieringPageState extends State<PaymentCashieringPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _barangayRequests = [];
  List<Map<String, dynamic>> _marketRequests = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();
  String _filterStatus = 'All';
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _loadRequests();
    // Auto-poll every 3 seconds so payments made on mobile reflect immediately
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
  //  LOAD REQUESTS (releasable / payment_pending / paid)
  // ════════════════════════════════════════════
  Future<void> _loadRequests({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final data = await supabase
          .from('requests')
          .select('*, slaughter_inspection(*), payments(*)')
          .inFilter('status', ['releasable', 'mic_generated', 'payment_pending', 'paid'])
          .order('created_at', ascending: false);

      final enriched = List<Map<String, dynamic>>.from(data).map((r) {
        // Flatten slaughter_inspection
        final inspectionList = r['slaughter_inspection'];
        if (inspectionList is List && inspectionList.isNotEmpty) {
          final insp = inspectionList.first as Map<String, dynamic>;
          r['carcass_weight'] = insp['carcass_weight'];
          r['inspector_name'] = insp['inspector_name'];
        } else if (inspectionList is Map) {
          r['carcass_weight'] = inspectionList['carcass_weight'];
          r['inspector_name'] = inspectionList['inspector_name'];
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
          _barangayRequests = enriched.where((r) => r['request_type'] == 'barangay').toList();
          _marketRequests = enriched.where((r) => r['request_type'] == 'market').toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('PaymentCashiering load error: $e');
      if (mounted && !silent) setState(() => _isLoading = false);
    }
  }

  String _refNo(Map<String, dynamic> req) =>
      'MI-${DateTime.now().year}-${req['id'].toString().padLeft(3, '0')}';

  String _receiptNo(Map<String, dynamic> req) =>
      'RCP-${DateTime.now().year}-${req['id'].toString().padLeft(3, '0')}';

  static double _carcassWeight(Map<String, dynamic> req) {
    final w = req['carcass_weight'];
    if (w == null) return 0;
    return double.tryParse(w.toString()) ?? 0;
  }

  static bool hasTechnicalDelay(Map<String, dynamic> req) {
    if (req['anti_mortem_response'] == 'accept_penalty') return true;
    if (req['status'] == 'delay_error') return true;
    if (req['delay_reason'] != null && req['delay_reason'].toString().trim().isNotEmpty) return true;
    final notes = (req['process_notes'] ?? '').toString();
    if (notes.contains('Technical delay') || notes.toLowerCase().contains('penalty')) return true;
    final insp = req['slaughter_inspection'];
    if (insp is Map) {
      if (insp['process_stage'] == 'Technical Error/Delay') return true;
      final inspNotes = (insp['process_notes'] ?? '').toString();
      if (inspNotes.contains('Technical delay') || inspNotes.toLowerCase().contains('penalty')) return true;
    } else if (insp is List && insp.isNotEmpty) {
      final first = insp.first;
      if (first is Map) {
        if (first['process_stage'] == 'Technical Error/Delay') return true;
        final inspNotes = (first['process_notes'] ?? '').toString();
        if (inspNotes.contains('Technical delay') || inspNotes.toLowerCase().contains('penalty')) return true;
      }
    }
    return false;
  }

  static Map<String, dynamic> _calcFees(Map<String, dynamic> req) {
    final animalType = (req['livestock_type'] ?? 'hog').toString();
    final rates = AppSettingsService.instance.getFeeRatesForAnimal(animalType);
    final weight = _carcassWeight(req);
    final postMortemFee = weight * rates.postMortemRatePerKg;
    final isDelayed = hasTechnicalDelay(req);
    final penaltyFee = isDelayed ? 500.0 : 0.0;
    final subtotal = rates.vetHealthCertFee +
        rates.permitToSlaughterFee +
        rates.facilityFee +
        rates.corralFee +
        rates.anteMortemFee +
        rates.additionalFee +
        postMortemFee +
        penaltyFee;
    final isBarangay = req['request_type'] == 'barangay';
    final deliveryFee = isBarangay ? 0.0 : rates.deliveryVanFee;
    return {
      'vet_health_cert': rates.vetHealthCertFee,
      'permit_to_slaughter': rates.permitToSlaughterFee,
      'facility': rates.facilityFee,
      'corral': rates.corralFee,
      'ante_mortem': rates.anteMortemFee,
      'post_mortem': postMortemFee,
      'additional_fee': rates.additionalFee,
      'additional_fee_label': rates.additionalFeeLabel,
      'penalty_fee': penaltyFee,
      'is_delayed': isDelayed,
      'subtotal': subtotal,
      'delivery_van': deliveryFee,
      'total': subtotal + deliveryFee,
      'rate_per_kg': rates.postMortemRatePerKg,
    };
  }

  List<Map<String, dynamic>> _filteredList(List<Map<String, dynamic>> list) {
    final q = _searchController.text.toLowerCase().trim();
    return list.where((r) {
      final name = (r['customer_name'] ?? '').toString().toLowerCase();
      final ref = _refNo(r).toLowerCase();
      final paymentStatus = _paymentStatus(r);

      bool matchesSearch = q.isEmpty || name.contains(q) || ref.contains(q);
      bool matchesFilter = _filterStatus == 'All' || paymentStatus == _filterStatus;

      return matchesSearch && matchesFilter;
    }).toList();
  }

  String _paymentStatus(Map<String, dynamic> req) {
    final payment = req['payment'] as Map<String, dynamic>?;
    if (payment != null && payment['status'] == 'paid') return 'Verified';
    if (req['status'] == 'paid') return 'Verified';
    return 'Pending';
  }

  String _paymentMethod(Map<String, dynamic> req) {
    final payment = req['payment'] as Map<String, dynamic>?;
    if (payment != null && payment['payment_method'] != null) {
      return payment['payment_method'].toString();
    }
    return req['payment_method']?.toString() ?? '—';
  }

  // ════════════════════════════════════════════
  //  SEND RECEIPT TO CUSTOMER
  // ════════════════════════════════════════════
  Future<void> _sendReceiptForPayment(Map<String, dynamic> req) async {
    try {
      final reqId = req['id'];
      final userId = req['user_id'];
      final fees = _calcFees(req);
      final receiptNo = _receiptNo(req);
      final refNo = _refNo(req);

      // Upsert payment record
      final existing = await supabase.from('payments').select('id').eq('request_id', reqId).maybeSingle();
      final paymentData = {
        'request_id': reqId,
        'user_id': userId,
        'payment_method': null,
        'total_amount': fees['total'],
        'balance': fees['total'],
        'status': 'pending',
        'cashier_name': null,
        'vet_health_cert_fee': fees['vet_health_cert'],
        'permit_fee': fees['permit_to_slaughter'],
        'facility_fee': fees['facility'],
        'corral_fee': fees['corral'],
        'ante_mortem_fee': fees['ante_mortem'],
        'post_mortem_fee': fees['post_mortem'],
        'delivery_van_fee': fees['delivery_van'],
      };

      if (existing != null) {
        await supabase.from('payments').update(paymentData).eq('request_id', reqId);
      } else {
        await supabase.from('payments').insert(paymentData);
      }

      // Update request status
      await supabase.from('requests').update({'status': 'payment_pending'}).eq('id', reqId);

      // Send notification to customer safely
      await NotificationService.sendNotificationSafely(
        supabase,
        userId: userId,
        title: 'Slaughter Request Receipt Issued',
        message: 'Your slaughter operation request has been successfully processed. A receipt has been generated for your transaction and is now available for viewing.',
        type: 'receipt_issued',
        data: {
          'receipt_no': receiptNo,
          'reference_no': refNo,
          'amount': fees['total'],
          'request_id': reqId,
        },
      );

      _loadRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Receipt sent! Awaiting customer payment...'),
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
                          _buildTopActionBar(),
                          const SizedBox(height: 24),
                          _buildFilterRow(),
                          const SizedBox(height: 24),
                          _buildTableCard(
                            title: 'Barangay — Payment & Cashiering Records',
                            subtitle: 'Fee calculation, payment verification, and receipt management',
                            requests: _filteredList(_barangayRequests),
                          ),
                          const SizedBox(height: 24),
                          _buildTableCard(
                            title: 'Market — Payment & Cashiering Records',
                            subtitle: 'Fee calculation, payment verification, and receipt management',
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
              const Text('Payment & Cashiering',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
              const SizedBox(height: 2),
              Text('Fee calculation, payment recording, receipts',
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
  //  TOP ACTION BAR (Stats + New Payment)
  // ════════════════════════════════════════════
  Widget _buildTopActionBar() {
    final allReqs = [..._barangayRequests, ..._marketRequests];
    int verified = 0, outstanding = 0;
    for (var r in allReqs) {
      if (_paymentStatus(r) == 'Verified') {
        verified++;
      } else {
        outstanding++;
      }
    }

    return Row(
      children: [
        // Stats cards
        _statCard('Verified', verified.toString(), const Color(0xFF2D6A4F), icon: Icons.check_circle_outline),
        const SizedBox(width: 16),
        _statCard('Outstanding', outstanding.toString(), Colors.red),
        const Spacer(),
        // New Payment Process button
        ElevatedButton.icon(
          onPressed: _showNewPaymentDialog,
          icon: const Icon(Icons.add, size: 18, color: Colors.white),
          label: const Text('New Payment Process', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2D3748),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, Color accent, {IconData? icon}) {
    return Container(
      width: 160,
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
              if (icon != null)
                Icon(icon, size: 16, color: accent)
              else
                Container(width: 10, height: 10, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
        ],
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
          width: 300,
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search by reference number or name...',
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
              items: ['All', 'Verified', 'Pending']
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
  //  DATA TABLE
  // ════════════════════════════════════════════
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
                  constraints: const BoxConstraints(minWidth: 1100),
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF7FAFC)),
                    dataRowMinHeight: 60,
                    dataRowMaxHeight: 80,
                    columnSpacing: 24,
                    columns: const [
                      DataColumn(label: Text('Reference #', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      DataColumn(label: Text('Customer', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      DataColumn(label: Text('Livestock', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      DataColumn(label: Text('Weight (kg)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      DataColumn(label: Text('Post-Mortem\nFee', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      DataColumn(label: Text('Payment Method', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                    ],
                    rows: requests.map((req) {
                      final ref = _refNo(req);
                      final weight = _carcassWeight(req);
                      final fees = _calcFees(req);
                      final postMortemFee = fees['post_mortem']!;
                      final status = _paymentStatus(req);
                      final method = _paymentMethod(req);

                      return DataRow(cells: [
                        DataCell(Text(ref, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12))),
                        DataCell(Text(req['customer_name']?.toString() ?? '\u2014', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                        DataCell(Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${req['animal_count'] ?? 1} head(s)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                            Text('${req['livestock_type'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          ],
                        )),
                        DataCell(Text(weight > 0 ? '${weight.toStringAsFixed(0)} kg' : '\u2014', style: const TextStyle(fontSize: 13))),
                        DataCell(Text(weight > 0 ? '\u20b1${postMortemFee.toStringAsFixed(2)}' : '\u2014', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                        DataCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (method != '\u2014') ...[
                              Icon(
                                method == 'Cash' ? Icons.payments_outlined : (method == 'GCash' ? Icons.phone_android : Icons.credit_card),
                                size: 14,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(method, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                          ],
                        )),
                        DataCell(_buildStatusBadge(status)),
                        DataCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _showReceiptDialog(req),
                              icon: const Icon(Icons.receipt_long, size: 14),
                              label: const Text('Details', style: TextStyle(fontSize: 11)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF4A5568),
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                minimumSize: const Size(0, 32),
                                side: BorderSide(color: Colors.grey.shade300),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                            ),
                          ],
                        )),
                      ]);
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
          if (requests.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text('No records found', style: TextStyle(color: Colors.grey, fontSize: 13)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final isVerified = status == 'Verified';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isVerified ? const Color(0xFFE6F9F0) : const Color(0xFFFFF8E5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isVerified ? const Color(0xFF1A8C62) : const Color(0xFFB8860B),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  RECEIPT DIALOG
  // ════════════════════════════════════════════
  void _showReceiptDialog(Map<String, dynamic> req) {
    final fees = _calcFees(req);
    final isBarangay = req['request_type'] == 'barangay';
    final typeLabel = isBarangay ? 'BARANGAY' : 'MARKET';
    final receiptNo = _receiptNo(req);
    final refNo = _refNo(req);
    final status = _paymentStatus(req);
    final method = _paymentMethod(req);
    final weight = _carcassWeight(req);
    final payment = req['payment'] as Map<String, dynamic>?;

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(32),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Center(
                  child: Text(
                    'Payment  Receipt for "$typeLabel"',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 20),

                // Receipt Info
                Text('Receipt Number: $receiptNo', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text('Date: ${DateFormat('M/dd/yyyy').format(DateTime.now())}', style: const TextStyle(fontSize: 13)),
                Text('Time: ${DateFormat('h:mm:ss a').format(DateTime.now())}', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 16),

                // Customer Info
                const Text('CUSTOMER INFORMATION:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                Text('Name: ${req['customer_name'] ?? '\u2014'}', style: const TextStyle(fontSize: 13)),
                Text('Reference: $refNo', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 16),

                // Livestock Info
                const Text('LIVESTOCK INFORMATION:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                Text('Animal Type: ${req['livestock_type'] ?? '\u2014'}', style: const TextStyle(fontSize: 13)),
                Text('Count: ${req['animal_count'] ?? 1}', style: const TextStyle(fontSize: 13)),
                Text('Weight: ${weight > 0 ? '${weight.toStringAsFixed(0)} kg' : '\u2014'}', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 16),

                // Fee Breakdown
                const Text('Payment Calculation Preview', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _feeRow('Veterinary Health Certificate:', '\u20b1${(fees['vet_health_cert'] as double).toStringAsFixed(2)}'),
                _feeRow('Permit to Slaughter:', '\u20b1${(fees['permit_to_slaughter'] as double).toStringAsFixed(2)}'),
                _feeRow('Facility Fee:', '\u20b1${(fees['facility'] as double).toStringAsFixed(2)}'),
                _feeRow('Corral Fee:', '\u20b1${(fees['corral'] as double).toStringAsFixed(2)}'),
                _feeRow('Ante-Mortem Fee:', '\u20b1${(fees['ante_mortem'] as double).toStringAsFixed(2)}'),
                _feeRow('Post-Mortem (${weight.toStringAsFixed(0)} kg @ \u20b1${((fees['rate_per_kg'] as num?)?.toDouble() ?? 5.0).toStringAsFixed(2)}/kg):', '\u20b1${(fees['post_mortem'] as double).toStringAsFixed(2)}'),
                if (((fees['additional_fee'] as num?)?.toDouble() ?? 0.0) > 0)
                  _feeRow(
                    '${fees['additional_fee_label'] ?? 'Additional Surcharge'}:',
                    '\u20b1${((fees['additional_fee'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                  ),
                if (((fees['penalty_fee'] as num?)?.toDouble() ?? 0.0) > 0)
                  _feeRow(
                    'Legal Finality / Penalty Fee (Delayed Operation):',
                    '\u20b1${((fees['penalty_fee'] as num?)?.toDouble() ?? 500.0).toStringAsFixed(2)}',
                    bold: true,
                  ),
                const SizedBox(height: 8),
                Divider(color: Colors.grey.shade300),
                _feeRow('Subtotal:', '\u20b1${(fees['subtotal'] as double).toStringAsFixed(2)}', bold: true),
                if (!isBarangay) _feeRow('Delivery Van Fee:', '\u20b1${(fees['delivery_van'] as double).toStringAsFixed(2)}'),
                const SizedBox(height: 8),
                Divider(color: Colors.grey.shade400),
                const SizedBox(height: 4),
                _feeRow('TOTAL AMOUNT:', '\u20b1${((fees['total'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}', bold: true, large: true),
                const SizedBox(height: 12),
                _feeRow('BALANCE:', status == 'Verified' ? '0' : '\u20b1${((fees['total'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}', bold: true),
                const SizedBox(height: 12),

                // Payment Details
                if (status == 'Verified') ...[
                  Text('Payment Method: ${method.toUpperCase()}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const Text('Status: PAID', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text('Cashier: ${payment?['cashier_name'] ?? 'Admin'}', style: const TextStyle(fontSize: 13)),
                ],
                const SizedBox(height: 16),

                // Footer
                const Text('Thank you!', style: TextStyle(fontSize: 13)),
                const Text('Tabaco City Slaughterhouse', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 20),

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (status != 'Verified' && req['status'] != 'payment_pending')
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _sendReceiptForPayment(req);
                        },
                        icon: const Icon(Icons.send, size: 16, color: Colors.white),
                        label: const Text('Send Receipt to Customer', style: TextStyle(color: Colors.white, fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2D6A4F),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    if (req['status'] == 'payment_pending' && status != 'Verified')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.hourglass_empty, size: 16, color: Colors.orange),
                            SizedBox(width: 8),
                            Text('Awaiting Customer Payment', style: TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    if (status != 'Verified') const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.print, size: 16),
                      label: const Text('Print', style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF2D3748),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        side: const BorderSide(color: Color(0xFF2D3748)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _feeRow(String label, String amount, {bool bold = false, bool large = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: large ? 14 : 13, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(amount, style: TextStyle(fontSize: large ? 14 : 13, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }



  // ════════════════════════════════════════════
  //  NEW PAYMENT ENTRY DIALOG (Walk-in)
  // ════════════════════════════════════════════
  void _showNewPaymentDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NewPaymentEntryDialog(
        supabase: supabase,
        onDone: _loadRequests,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  NEW PAYMENT ENTRY DIALOG (Stateful)
// ═══════════════════════════════════════════════════════════
class _NewPaymentEntryDialog extends StatefulWidget {
  final SupabaseClient supabase;
  final VoidCallback onDone;
  const _NewPaymentEntryDialog({required this.supabase, required this.onDone});
  @override
  State<_NewPaymentEntryDialog> createState() => _NewPaymentEntryDialogState();
}

class _NewPaymentEntryDialogState extends State<_NewPaymentEntryDialog> {
  final _refCtrl = TextEditingController();
  String _customerName = '';
  double _totalAmount = 0;
  double _balanceAmount = 0;
  String _selectedMethod = 'Cash';
  bool _isLoading = false;
  bool _isProcessing = false;
  Map<String, dynamic>? _foundRequest;
  Map<String, dynamic> _fees = {};

  Future<void> _lookupReference() async {
    final refText = _refCtrl.text.trim();
    if (refText.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      // Parse MI-YYYY-XXX -> get the ID part
      final parts = refText.split('-');
      int? requestId;
      if (parts.length == 3) {
        requestId = int.tryParse(parts[2]);
      }

      if (requestId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid reference number format (MI-YYYY-XXX)'), backgroundColor: Colors.orange),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      final data = await widget.supabase
          .from('requests')
          .select('*, slaughter_inspection(*)')
          .eq('id', requestId)
          .maybeSingle();

      if (data == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No request found with that reference'), backgroundColor: Colors.orange),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      // Flatten inspection data
      final inspList = data['slaughter_inspection'];
      if (inspList is List && inspList.isNotEmpty) {
        data['carcass_weight'] = (inspList.first as Map)['carcass_weight'];
      }

      // Calculate fees dynamically based on configured animal rates
      final fees = _PaymentCashieringPageState._calcFees(data);
      final total = fees['total']!;

      setState(() {
        _foundRequest = data;
        _customerName = data['customer_name']?.toString() ?? '';
        _totalAmount = total;
        _balanceAmount = total;
        _fees = fees;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Lookup error: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _processPayment() async {
    if (_foundRequest == null) return;
    setState(() => _isProcessing = true);
    try {
      final req = _foundRequest!;
      final reqId = req['id'];
      final userId = req['user_id'];
      final receiptNo = 'RCP-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';
      final refNo = 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';

      // Check existing payment
      final existing = await widget.supabase.from('payments').select('id').eq('request_id', reqId).maybeSingle();
      final paymentData = {
        'request_id': reqId,
        'user_id': userId,
        'receipt_number': receiptNo,
        'payment_method': _selectedMethod,
        'total_amount': _fees['total'],
        'balance': 0,
        'status': 'paid',
        'cashier_name': 'Admin',
        'vet_health_cert_fee': _fees['vet_health_cert'],
        'permit_fee': _fees['permit_to_slaughter'],
        'facility_fee': _fees['facility'],
        'corral_fee': _fees['corral'],
        'ante_mortem_fee': _fees['ante_mortem'],
        'post_mortem_fee': _fees['post_mortem'],
        'delivery_van_fee': _fees['delivery_van'],
      };

      if (existing != null) {
        await widget.supabase.from('payments').update(paymentData).eq('request_id', reqId);
      } else {
        await widget.supabase.from('payments').insert(paymentData);
      }

      await widget.supabase.from('requests').update({'status': 'paid'}).eq('id', reqId);

      // Send notification safely
      await NotificationService.sendNotificationSafely(
        widget.supabase,
        userId: userId,
        title: 'Slaughter Request Receipt Issued',
        message: 'Your slaughter operation request has been successfully processed. A receipt has been generated for your transaction and is now available for viewing.',
        type: 'receipt_issued',
        data: {
          'receipt_no': receiptNo,
          'reference_no': refNo,
          'amount': _fees['total'],
          'request_id': reqId,
        },
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onDone();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Payment processed successfully'),
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
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('New Payment  Entry', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Enter  payment detail to process a new transaction', style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 24),

              // Reference Number & Customer Name
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(text: const TextSpan(
                          text: 'Reference Number ',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2D3748)),
                          children: [TextSpan(text: '*', style: TextStyle(color: Colors.red))],
                        )),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _refCtrl,
                          onSubmitted: (_) => _lookupReference(),
                          decoration: InputDecoration(
                            hintText: 'MI-2025-001',
                            hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                            filled: true,
                            fillColor: const Color(0xFFF7FAFC),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                            suffixIcon: _isLoading
                                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                                : IconButton(icon: const Icon(Icons.search, size: 20), onPressed: _lookupReference),
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
                        RichText(text: const TextSpan(
                          text: 'Customer Name ',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2D3748)),
                          children: [TextSpan(text: '*', style: TextStyle(color: Colors.red))],
                        )),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            _customerName.isNotEmpty ? _customerName : '\u2014',
                            style: TextStyle(fontSize: 14, color: _customerName.isNotEmpty ? Colors.black87 : Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Total Amount & Balance Amount
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(text: const TextSpan(
                          text: 'Total Amount ',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2D3748)),
                          children: [TextSpan(text: '*', style: TextStyle(color: Colors.red))],
                        )),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            _totalAmount > 0 ? _totalAmount.toStringAsFixed(2) : '0.00',
                            style: const TextStyle(fontSize: 14),
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
                        RichText(text: const TextSpan(
                          text: 'Balance Amount ',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2D3748)),
                          children: [TextSpan(text: '*', style: TextStyle(color: Colors.red))],
                        )),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            _balanceAmount > 0 ? _balanceAmount.toStringAsFixed(2) : '0.00',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Payment Method
              RichText(text: const TextSpan(
                text: 'Payment Method ',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2D3748)),
                children: [TextSpan(text: '*', style: TextStyle(color: Colors.red))],
              )),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedMethod,
                    isExpanded: true,
                    hint: const Text('Select payment method', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    items: ['Cash', 'GCash', 'Card']
                        .map((m) => DropdownMenuItem(
                              value: m,
                              child: Row(
                                children: [
                                  Icon(
                                    m == 'Cash' ? Icons.payments_outlined : (m == 'GCash' ? Icons.phone_android : Icons.credit_card),
                                    size: 18,
                                    color: Colors.grey.shade600,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(m, style: const TextStyle(fontSize: 14)),
                                ],
                              ),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedMethod = v);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Process Button
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _foundRequest != null && !_isProcessing ? _processPayment : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2D3748),
                      disabledBackgroundColor: Colors.grey.shade300,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isProcessing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Process Payment', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

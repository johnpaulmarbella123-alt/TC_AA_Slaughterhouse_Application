import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ViewStatusUpdateScreen extends StatefulWidget {
  final Map<String, dynamic>? initialRequest;
  final Function(int)? onNavigateToTab;

  const ViewStatusUpdateScreen({
    super.key,
    this.initialRequest,
    this.onNavigateToTab,
  });

  @override
  State<ViewStatusUpdateScreen> createState() => _ViewStatusUpdateScreenState();
}

class _ViewStatusUpdateScreenState extends State<ViewStatusUpdateScreen> {
  final supabase = Supabase.instance.client;
  Map<String, dynamic>? _request;
  Map<String, dynamic>? _inspection;
  Map<String, dynamic>? _payment;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _request = widget.initialRequest;
    _loadRequestDetails();
  }

  Future<void> _loadRequestDetails() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      int? targetId;
      if (_request != null && _request!['id'] != null) {
        targetId = int.tryParse(_request!['id'].toString());
      }

      var query = supabase
          .from('requests')
          .select('*, slaughter_inspection(*), payments(*)');

      final List<dynamic> rows;
      if (targetId != null) {
        rows = await query.eq('id', targetId).limit(1);
      } else {
        rows = await query
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
            .limit(1);
      }

      if (rows.isNotEmpty) {
        final row = rows.first as Map<String, dynamic>;
        _request = row;

        // Extract inspection
        final inspData = row['slaughter_inspection'];
        if (inspData is List && inspData.isNotEmpty) {
          _inspection = inspData.first as Map<String, dynamic>;
        } else if (inspData is Map) {
          _inspection = Map<String, dynamic>.from(inspData);
        }

        // Extract payment
        final payData = row['payments'];
        if (payData is List && payData.isNotEmpty) {
          _payment = payData.first as Map<String, dynamic>;
        } else if (payData is Map) {
          _payment = Map<String, dynamic>.from(payData);
        }
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading request details: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatDateTime(dynamic dtStr) {
    if (dtStr == null) return '';
    try {
      final dt = DateTime.parse(dtStr.toString()).toLocal();
      return DateFormat('yyyy-MM-dd  hh:mm a').format(dt);
    } catch (_) {
      return dtStr.toString();
    }
  }

  String _formatDate(dynamic dtStr) {
    if (dtStr == null) return '';
    try {
      final dt = DateTime.parse(dtStr.toString());
      return DateFormat('MMM d, yyyy').format(dt);
    } catch (_) {
      return dtStr.toString();
    }
  }

  String _buildRefNo(Map<String, dynamic>? req) {
    if (req == null) return 'REF-2025-001';
    if (req['reference_no'] != null && req['reference_no'].toString().isNotEmpty) {
      return req['reference_no'].toString();
    }
    final id = req['id'] ?? 1;
    final year = req['created_at'] != null
        ? DateTime.tryParse(req['created_at'].toString())?.year ?? DateTime.now().year
        : DateTime.now().year;
    return 'REF-$year-${id.toString().padLeft(3, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'View Status Update',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        automaticallyImplyLeading: false,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1E855A)),
            )
          : _request == null
              ? _buildEmptyState()
              : _buildContent(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 50, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'No active request found',
            style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onNavigateToTab?.call(1);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E855A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Submit Request', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final req = _request!;
    final refNo = _buildRefNo(req);
    final livestockType = (req['livestock_type'] ?? 'Pig').toString();
    final animalCount = req['animal_count'] ?? 1;
    final preferredDate = req['preferred_date'] ?? req['created_at'];
    final dateStr = _formatDate(preferredDate);

    // Weight determination
    String weightStr = 'Pending';
    double carcassWeightNum = 0.0;
    if (_inspection != null && _inspection!['carcass_weight'] != null) {
      final cw = _inspection!['carcass_weight'];
      carcassWeightNum = double.tryParse(cw.toString()) ?? 0.0;
      weightStr = '${carcassWeightNum.toStringAsFixed(0)}kg';
    } else if (req['live_weight'] != null) {
      final lw = req['live_weight'];
      carcassWeightNum = double.tryParse(lw.toString()) ?? 0.0;
      weightStr = '${carcassWeightNum.toStringAsFixed(0)}kg';
    }

    // Official Fee Schedule Calculation
    const double vetHealthCertFee = 50.0;
    const double permitToSlaughterFee = 60.0;
    const double facilityFee = 60.0;
    const double corralFee = 40.0;
    const double anteMortemFee = 40.0;
    const double postMortemRatePerKg = 5.0;
    const double baseFixedFees = vetHealthCertFee + permitToSlaughterFee + facilityFee + corralFee + anteMortemFee; // ₱250.00

    final double postMortemFee = carcassWeightNum * postMortemRatePerKg;
    final bool isMarket = req['request_type'] == 'market' || req['release_type'] == 'delivery';
    final double deliveryFee = isMarket ? 60.0 : 0.0;
    final double calculatedTotal = baseFixedFees + postMortemFee + deliveryFee;

    double totalAmount = calculatedTotal;
    if (_payment != null && _payment!['amount'] != null) {
      totalAmount = double.tryParse(_payment!['amount'].toString()) ?? calculatedTotal;
    }

    final String feeStr = '₱${totalAmount.toStringAsFixed(2)}';
    final bool isPaid = req['status'] == 'paid' || (_payment != null && _payment!['status'] == 'paid');

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── TOP ACTION BAR: BACK & SUBMIT NEW REQUEST ───────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: Row(
                    children: [
                      Icon(Icons.arrow_back, size: 20, color: Colors.black87),
                      SizedBox(width: 4),
                      Text(
                        'Back',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onNavigateToTab?.call(1); // Navigate to Requests tab
                },
                icon: const Icon(Icons.add, size: 16, color: Colors.black87),
                label: const Text(
                  'Submit New Request',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  side: BorderSide(color: Colors.grey.shade300),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── CARD 1: REQUEST DETAILS ──────────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  refNo,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Animal Type',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            livestockType,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Animal Count',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$animalCount',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Request Date:',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateStr,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Right Column
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'weight',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            weightStr,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 28),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'slaughter fee',
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                              ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => _showFeeBreakdown(
                                  baseFixedFees: baseFixedFees,
                                  weight: carcassWeightNum,
                                  postMortemFee: postMortemFee,
                                  deliveryFee: deliveryFee,
                                  total: totalAmount,
                                  isPaid: isPaid,
                                ),
                                child: Icon(Icons.info_outline, size: 14, color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            feeStr,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E855A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isPaid ? 'Paid' : 'Total to pay',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isPaid ? const Color(0xFF1E855A) : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── CARD 2: TRACK PROCESS ─────────────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Track Process',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Monitoring a workflow's status and progress.",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 22),
                _buildProcessTimeline(),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildProcessTimeline() {
    final status = (_request?['status'] ?? '').toString().toLowerCase();
    final createdAt = _request?['created_at'];

    // Map status into stage completion level:
    // 0: Request Received
    // 1: Document Verified
    // 2: Slaughter Inspection
    // 3: Slaughter Operation
    // 4: Processing Complete
    // 5: Ready for Pickup
    int currentStageIndex = 0;
    if (['doc_verified', 'doc_approved'].contains(status)) {
      currentStageIndex = 1;
    } else if (status == 'slaughter_started' || status == 'in_progress') {
      currentStageIndex = 3;
    } else if (status == 'releasable') {
      currentStageIndex = 4;
    } else if (['payment_pending', 'paid', 'released', 'completed'].contains(status)) {
      currentStageIndex = 5;
    } else if (_inspection != null) {
      currentStageIndex = 2;
    } else if (status == 'approved') {
      currentStageIndex = 0;
    }

    final reqTimeStr = _formatDateTime(createdAt);
    DateTime baseDate = DateTime.tryParse(createdAt?.toString() ?? '') ?? DateTime.now();

    final steps = [
      _ProcessStep(
        title: 'Request Received',
        time: reqTimeStr.isNotEmpty
            ? reqTimeStr
            : DateFormat('yyyy-MM-dd  hh:mm a').format(baseDate),
        isCompleted: true, // If approved, request is received
      ),
      _ProcessStep(
        title: 'Document Verified',
        time: currentStageIndex >= 1
            ? DateFormat('yyyy-MM-dd  hh:mm a')
                .format(baseDate.add(const Duration(minutes: 40)))
            : '',
        isCompleted: currentStageIndex >= 1,
      ),
      _ProcessStep(
        title: 'Slaughter Inspection',
        time: currentStageIndex >= 2
            ? DateFormat('yyyy-MM-dd  hh:mm a')
                .format(baseDate.add(const Duration(hours: 24)))
            : '',
        isCompleted: currentStageIndex >= 2,
      ),
      _ProcessStep(
        title: 'Slaughter Operation',
        time: currentStageIndex >= 3
            ? DateFormat('yyyy-MM-dd  hh:mm a')
                .format(baseDate.add(const Duration(hours: 38)))
            : '',
        isCompleted: currentStageIndex >= 3,
      ),
      _ProcessStep(
        title: 'Processing Complete',
        time: currentStageIndex >= 4
            ? DateFormat('yyyy-MM-dd  hh:mm a')
                .format(baseDate.add(const Duration(hours: 41)))
            : '',
        isCompleted: currentStageIndex >= 4,
      ),
      _ProcessStep(
        title: 'Ready for Pickup',
        time: currentStageIndex >= 5
            ? DateFormat('yyyy-MM-dd  hh:mm a')
                .format(baseDate.add(const Duration(hours: 42)))
            : '',
        isCompleted: currentStageIndex >= 5,
      ),
    ];

    return Column(
      children: List.generate(steps.length, (index) {
        final step = steps[index];
        final isLast = index == steps.length - 1;
        final nextStepCompleted =
            !isLast && steps[index + 1].isCompleted;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Indicator column: Circle + Vertical connector
            Column(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: step.isCompleted
                        ? const Color(0xFF2E7D32)
                        : Colors.white,
                    border: Border.all(
                      color: step.isCompleted
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFF81C784),
                      width: 2,
                    ),
                  ),
                  child: step.isCompleted
                      ? Center(
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : null,
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 38,
                    color: nextStepCompleted
                        ? const Color(0xFF81C784)
                        : const Color(0xFFC8E6C9),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            // Title & Timestamp
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      step.time.isNotEmpty ? step.time : 'Pending',
                      style: TextStyle(
                        fontSize: 11,
                        color: step.time.isNotEmpty
                            ? Colors.grey.shade600
                            : Colors.grey.shade400,
                      ),
                    ),
                    if (!isLast) const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  void _showFeeBreakdown({
    required double baseFixedFees,
    required double weight,
    required double postMortemFee,
    required double deliveryFee,
    required double total,
    required bool isPaid,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.receipt_long, color: Color(0xFF1E855A), size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'Slaughter Fee Breakdown',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _breakdownRow('Veterinary Health Cert.', '₱50.00'),
            _breakdownRow('Permit to Slaughter', '₱60.00'),
            _breakdownRow('Facility Fee', '₱60.00'),
            _breakdownRow('Corral Fee', '₱40.00'),
            _breakdownRow('Ante-Mortem Inspection', '₱40.00'),
            if (weight > 0)
              _breakdownRow(
                'Post-Mortem (${weight.toStringAsFixed(0)}kg × ₱5/kg)',
                '₱${postMortemFee.toStringAsFixed(2)}',
              ),
            if (deliveryFee > 0)
              _breakdownRow('Delivery Van Fee', '₱${deliveryFee.toStringAsFixed(2)}'),
            const Divider(height: 20),
            _breakdownRow(
              'Total Amount to Pay',
              '₱${total.toStringAsFixed(2)}',
              isBold: true,
              color: const Color(0xFF1E855A),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isPaid ? const Color(0xFFE8F5E9) : const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isPaid
                    ? 'Status: Payment Cleared (Paid)'
                    : 'Status: Pending payment at cashier upon releasing',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isPaid ? const Color(0xFF1E855A) : const Color(0xFFB78103),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Color(0xFF1E855A))),
          ),
        ],
      ),
    );
  }

  Widget _breakdownRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isBold ? Colors.black87 : Colors.grey.shade700,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isBold ? 14 : 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: color ?? (isBold ? Colors.black : Colors.grey.shade800),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProcessStep {
  final String title;
  final String time;
  final bool isCompleted;

  _ProcessStep({
    required this.title,
    required this.time,
    required this.isCompleted,
  });
}

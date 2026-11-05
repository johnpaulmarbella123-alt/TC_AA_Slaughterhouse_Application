import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dashed_line.dart';
import 'payment.dart' show kMintHeader;
import 'select_payment_screen.dart';

const kAccentGreen = Color(0xFF1BC47D);

// Fee constants (must match admin panel)
const double _kVetHealthCertFee = 50.0;
const double _kPermitToSlaughterFee = 60.0;
const double _kFacilityFee = 60.0;
const double _kCorralFee = 40.0;
const double _kAnteMortemFee = 40.0;
const double _kPostMortemRatePerKg = 5.0;
const double _kDeliveryVanFee = 60.0;

class ReceiptDetailScreen extends StatefulWidget {
  /// Pass the request ID to load dynamic receipt data.
  /// If null, tries to load the first available payment for the current user.
  final dynamic requestId;

  const ReceiptDetailScreen({super.key, this.requestId});

  @override
  State<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends State<ReceiptDetailScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isProcessing = false;

  // Dynamic data
  Map<String, dynamic>? _request;
  Map<String, dynamic>? _payment;
  Map<String, double> _fees = {};

  @override
  void initState() {
    super.initState();
    _loadReceiptData();
  }

  Future<void> _loadReceiptData() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      Map<String, dynamic>? requestData;

      if (widget.requestId != null) {
        // Load specific request
        requestData = await supabase
            .from('requests')
            .select('*, slaughter_inspection(*), payments(*)')
            .eq('id', widget.requestId)
            .maybeSingle();
      } else {
        // Load latest payment for current user
        final payments = await supabase
            .from('payments')
            .select('request_id')
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
            .limit(1);

        if (payments.isNotEmpty) {
          final reqId = payments[0]['request_id'];
          requestData = await supabase
              .from('requests')
              .select('*, slaughter_inspection(*), payments(*)')
              .eq('id', reqId)
              .maybeSingle();
        }
      }

      if (requestData != null) {
        // Flatten slaughter_inspection
        final inspList = requestData['slaughter_inspection'];
        if (inspList is List && inspList.isNotEmpty) {
          requestData['carcass_weight'] = (inspList.first as Map<String, dynamic>)['carcass_weight'];
        } else if (inspList is Map) {
          requestData['carcass_weight'] = inspList['carcass_weight'];
        }

        // Flatten payment
        final payList = requestData['payments'];
        Map<String, dynamic>? paymentData;
        if (payList is List && payList.isNotEmpty) {
          paymentData = payList.first as Map<String, dynamic>;
        } else if (payList is Map) {
          paymentData = payList as Map<String, dynamic>;
        }

        // Fallback for authorized representative from system_settings if column empty in requests
        if (requestData['authorized_person_name'] == null || requestData['authorized_person_name'].toString().isEmpty) {
          try {
            final repRow = await supabase
                .from('system_settings')
                .select('value')
                .eq('key', 'authorized_representatives')
                .maybeSingle();
            if (repRow != null && repRow['value'] is Map) {
              final repMap = Map<String, dynamic>.from(repRow['value']);
              final saved = repMap[requestData['id'].toString()] as Map<String, dynamic>?;
              if (saved != null) {
                requestData['authorized_person_name'] = saved['name'];
                requestData['authorized_person_contact'] = saved['contact'];
                requestData['authorized_person_relationship'] = saved['relationship'];
                requestData['authorized_person_id_type'] = saved['id_type'];
                requestData['authorized_person_id_num'] = saved['id_num'];
              }
            }
          } catch (_) {}
        }

        // Calculate fees
        final weight = double.tryParse((requestData['carcass_weight'] ?? 0).toString()) ?? 0;
        final postMortemFee = weight * _kPostMortemRatePerKg;
        final isBarangay = requestData['request_type'] == 'barangay';
        final deliveryFee = isBarangay ? 0.0 : _kDeliveryVanFee;

        final isTakeBack = requestData['anti_mortem_response'] == 'take_back' ||
            requestData['status'] == 'taken_back' ||
            requestData['status'] == 'pickup_scheduled';
        final isAnteMortemFail = requestData['anti_mortem_response'] == 'confine' ||
            requestData['status'] == 'confined' ||
            requestData['status'] == 'anti_mortem_failed';
        final hasExplicitPenalty = requestData['penalty_fee'] != null &&
            (double.tryParse(requestData['penalty_fee'].toString()) ?? 0.0) > 0;
        final isDelayed = !isTakeBack && !isAnteMortemFail && (hasExplicitPenalty ||
            requestData['anti_mortem_response'] == 'accept_penalty' ||
            requestData['status'] == 'delay_error' ||
            (requestData['delay_reason'] != null && requestData['delay_reason'].toString().isNotEmpty) ||
            (requestData['process_notes'] ?? '').toString().contains('Technical delay') ||
            (requestData['process_notes'] ?? '').toString().toLowerCase().contains('penalty'));
        final penaltyFee = isDelayed ? 500.0 : 0.0;
        final isPaid = (paymentData?['status'] == 'paid') || (requestData['status'] == 'paid');
        DateTime baseDate = DateTime.now();
        final createdStr = paymentData?['receipt_sent_at'] ?? paymentData?['updated_at'] ?? paymentData?['created_at'];
        if (createdStr != null) {
          final parsed = DateTime.tryParse(createdStr.toString());
          if (parsed != null) baseDate = parsed.toLocal();
        }
        DateTime dueDate = DateTime(baseDate.year, baseDate.month, baseDate.day, 17, 0, 0);
        if (baseDate.isAfter(dueDate)) {
          dueDate = dueDate.add(const Duration(days: 1));
        }
        final isOverdue = !isPaid && DateTime.now().isAfter(dueDate);
        final overduePenalty = isOverdue ? 100.0 : 0.0;
        final subtotal = _kVetHealthCertFee + _kPermitToSlaughterFee + _kFacilityFee + _kCorralFee + _kAnteMortemFee + postMortemFee + penaltyFee + overduePenalty;

        final totalFromPay = paymentData?['total_amount'] != null
            ? double.tryParse(paymentData!['total_amount'].toString())
            : null;

        setState(() {
          _request = requestData;
          _payment = paymentData;
          if (paymentData != null && totalFromPay != null) {
            final vanFee = double.tryParse((paymentData['delivery_van_fee'] ?? deliveryFee).toString()) ?? deliveryFee;
            _fees = {
              'vet_health_cert': double.tryParse((paymentData['vet_health_cert_fee'] ?? _kVetHealthCertFee).toString()) ?? _kVetHealthCertFee,
              'permit_to_slaughter': double.tryParse((paymentData['permit_fee'] ?? _kPermitToSlaughterFee).toString()) ?? _kPermitToSlaughterFee,
              'facility': double.tryParse((paymentData['facility_fee'] ?? _kFacilityFee).toString()) ?? _kFacilityFee,
              'corral': double.tryParse((paymentData['corral_fee'] ?? _kCorralFee).toString()) ?? _kCorralFee,
              'ante_mortem': double.tryParse((paymentData['ante_mortem_fee'] ?? _kAnteMortemFee).toString()) ?? _kAnteMortemFee,
              'post_mortem': double.tryParse((paymentData['post_mortem_fee'] ?? postMortemFee).toString()) ?? postMortemFee,
              'penalty_fee': penaltyFee,
              'overdue_penalty': overduePenalty,
              'subtotal': totalFromPay - vanFee,
              'delivery_van': vanFee,
              'total': totalFromPay,
            };
          } else {
            _fees = {
              'vet_health_cert': _kVetHealthCertFee,
              'permit_to_slaughter': _kPermitToSlaughterFee,
              'facility': _kFacilityFee,
              'corral': _kCorralFee,
              'ante_mortem': _kAnteMortemFee,
              'post_mortem': postMortemFee,
              'penalty_fee': penaltyFee,
              'overdue_penalty': overduePenalty,
              'subtotal': subtotal,
              'delivery_van': deliveryFee,
              'total': subtotal + deliveryFee,
            };
          }
        });
      }
    } catch (e) {
      debugPrint('ReceiptDetail load error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _refNo() {
    if (_request == null) return 'MI-0000-000';
    return 'MI-${DateTime.now().year}-${_request!['id'].toString().padLeft(3, '0')}';
  }

  String _receiptNo() {
    if (_payment != null && _payment!['receipt_number'] != null) {
      return _payment!['receipt_number'].toString();
    }
    if (_request == null) return 'RCP-0000-000';
    return 'RCP-${DateTime.now().year}-${_request!['id'].toString().padLeft(3, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 50, 16, 20),
            color: kMintHeader,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Payment", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                SizedBox(height: 2),
                Text("View and manage your payment receipt",
                    style: TextStyle(fontSize: 11, color: Color(0xFF2C2C2A))),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: kAccentGreen))
                : _request == null
                    ? _buildNoData()
                    : _buildReceiptContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildNoData() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('No receipt data available', style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildReceiptContent() {
    final req = _request!;
    final weight = double.tryParse((req['carcass_weight'] ?? 0).toString()) ?? 0;
    final isBarangay = req['request_type'] == 'barangay';
    final isPaid = _payment != null && _payment!['status'] == 'paid';
    // Customer already chose a method, but the admin hasn't verified it yet.
    final isAwaitingVerification = !isPaid &&
        _payment != null &&
        (_payment!['payment_method']?.toString().trim().isNotEmpty ?? false);
    final total = _fees['total'] ?? 0;
    DateTime baseDate = DateTime.now();
    final createdStr = _payment?['receipt_sent_at'] ?? _payment?['updated_at'] ?? _payment?['created_at'];
    if (createdStr != null) {
      final parsed = DateTime.tryParse(createdStr.toString());
      if (parsed != null) baseDate = parsed.toLocal();
    }
    DateTime dueDate = DateTime(baseDate.year, baseDate.month, baseDate.day, 17, 0, 0);
    if (baseDate.isAfter(dueDate)) {
      dueDate = dueDate.add(const Duration(days: 1));
    }
    final now = DateTime.now();
    final isOverdue = !isPaid && !isAwaitingVerification && now.isAfter(dueDate);
    final isWithin1HourOfDue = !isPaid && !isAwaitingVerification && !isOverdue && now.isAfter(dueDate.subtract(const Duration(hours: 1)));

    return Transform.translate(
      offset: const Offset(0, -12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 6),
                    const Text("Payment Receipt",
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 14),
                Center(
                  child: Column(
                    children: [
                      const Text("Receipt", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text("Reference #: ${_refNo()}",
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),

                      Text(_receiptNo(),
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),

                      if (!isPaid && !isAwaitingVerification) ...[
                        const SizedBox(height: 4),
                        Text("Due Date: ${DateFormat('M/dd/yyyy').format(dueDate)} • 5:00 PM",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: (isOverdue || isWithin1HourOfDue) ? const Color(0xFFC53030) : const Color(0xFF2D3748),
                            )),
                        if (isWithin1HourOfDue) ...[
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3CD),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE2A03F), width: 1.5),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.timer_outlined, color: Color(0xFF975A16), size: 16),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'URGENT: Less than 1 hour left until 5:00 PM deadline! Please pay immediately to avoid the \u20b1100.00 overdue penalty.',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF7A4A00)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: isOverdue ? const Color(0xFFFFF5F5) : const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isOverdue ? const Color(0xFFFEB2B2) : const Color(0xFFFBD38D),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isOverdue ? Icons.error_outline : Icons.warning_amber_rounded,
                                  color: isOverdue ? const Color(0xFFC53030) : const Color(0xFFC05621),
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    isOverdue
                                        ? 'OVERDUE: Payment deadline expired at 5:00 PM. A penalty of \u20b1100.00 has been applied.'
                                        : 'Notice: Payment must be made immediately on or before 5:00 PM today. If the due date passes without payment, an automatic overdue penalty of \u20b1100.00 will be added.',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: isOverdue ? const Color(0xFF9B2C2C) : const Color(0xFF975A16),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],

                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const DashedLine(),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(req['customer_name']?.toString() ?? '—',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                _kv("Livestock:", req['livestock_type']?.toString() ?? '—'),
                _kv("Count:", '${req['animal_count'] ?? 1} head(s)'),
                if (weight > 0) _kv("Weight:", '${weight.toStringAsFixed(0)} kg'),
                const SizedBox(height: 14),
                const DashedLine(),
                const SizedBox(height: 14),
                const Text("Payment Calculation Preview",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _lineItem("Veterinary Health Certificate:", "\u20b1${_fees['vet_health_cert']?.toStringAsFixed(2) ?? '0.00'}"),
                _lineItem("Permit to Slaughter:", "\u20b1${_fees['permit_to_slaughter']?.toStringAsFixed(2) ?? '0.00'}"),
                _lineItem("Facility Fee:", "\u20b1${_fees['facility']?.toStringAsFixed(2) ?? '0.00'}"),
                _lineItem("Corral Fee:", "\u20b1${_fees['corral']?.toStringAsFixed(2) ?? '0.00'}"),
                _lineItem("Ante-Mortem:", "\u20b1${_fees['ante_mortem']?.toStringAsFixed(2) ?? '0.00'}"),
                _lineItem("Post-Mortem (${weight.toStringAsFixed(0)} kg \u20b1${_kPostMortemRatePerKg.toStringAsFixed(2)}/kg):", "\u20b1${_fees['post_mortem']?.toStringAsFixed(2) ?? '0.00'}"),
                if (((_fees['overdue_penalty'] as num?)?.toDouble() ?? 0.0) > 0)
                  _lineItem(
                    "Overdue Payment Penalty (Past 5:00 PM):",
                    "\u20b1${((_fees['overdue_penalty'] as num?)?.toDouble() ?? 100.0).toStringAsFixed(2)}",
                  ),
                if (((_fees['penalty_fee'] as num?)?.toDouble() ?? 0.0) > 0)
                  _lineItem(
                    "Legal Finality Fee (Delayed Operation):",
                    "\u20b1${((_fees['penalty_fee'] as num?)?.toDouble() ?? 500.0).toStringAsFixed(2)}",
                  ),
                const SizedBox(height: 8),
                Divider(color: Colors.grey.shade300),
                const SizedBox(height: 4),
                _kv("Subtotal:", "\u20b1${_fees['subtotal']?.toStringAsFixed(2) ?? '0.00'}"),
                if (!isBarangay) _kv("Delivery Van Fee:", "\u20b1${_fees['delivery_van']?.toStringAsFixed(2) ?? '0.00'}"),
                const SizedBox(height: 14),
                const DashedLine(),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("TOTAL AMOUNT:", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    Text("\u20b1${total.toStringAsFixed(2)}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                if (isPaid) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("BALANCE:", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const Text("0", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildPostPaymentReferenceCard(),
                  const SizedBox(height: 10),
                  if (isBarangay)
                    _buildAuthorizedRepresentativeCard(req)
                  else
                    _buildMarketDeliveryInfoCard(),
                  const SizedBox(height: 12),
                  const Text("Thank you!", style: TextStyle(fontSize: 12)),
                  const Text("Tabaco City Slaughterhouse", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                ],
                if (isAwaitingVerification) ...[
                  const SizedBox(height: 10),
                  if (isBarangay)
                    _buildAuthorizedRepresentativeCard(req)
                  else
                    _buildMarketDeliveryInfoCard(),
                ],
                const SizedBox(height: 16),
                if (isAwaitingVerification) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3CD),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFFD97A)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.hourglass_top, size: 18, color: Color(0xFF856404)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Waiting for Cashier Payment",
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF856404))),
                              const SizedBox(height: 2),
                              Text(
                                _payment!['payment_method'].toString() == 'GCash'
                                    ? "Your GCash payment is being verified by the cashier. You'll be notified once confirmed."
                                    : "Cash-on-Pickup selected. Please settle payment at the cashier counter upon arrival before carcass release.",
                                style: const TextStyle(fontSize: 11, color: Color(0xFF856404)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (!isPaid) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE1F5EE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text("Please review the receipt before proceeding with payment",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 10, color: Color(0xFF0F6E56))),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 46,
                    child: ElevatedButton(
                      onPressed: _isProcessing ? null : _handleProceedToPayment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAccentGreen,
                        foregroundColor: const Color(0xFF04342C),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _isProcessing
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFF04342C)),
                            )
                          : const Text("Proceed to Payment",
                              style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ] else ...[
                  // Paid state — show success badge
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE1F5EE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle, size: 16, color: Color(0xFF0F6E56)),
                          SizedBox(width: 6),
                          Text("Payment Complete",
                              style: TextStyle(fontSize: 12, color: Color(0xFF0F6E56), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleProceedToPayment() async {
    final user = supabase.auth.currentUser;
    if (user == null || _request == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login first')),
      );
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final success = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SelectPaymentScreen(
            request: _request!,
            fees: _fees,
            receiptNo: _receiptNo(),
          ),
        ),
      );

      if (success == true) {
        if (mounted) {
          // Submission complete — go directly back to the payment page
          Navigator.pop(context, true);
          return;
        }
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  static Widget _kv(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      );

  static Widget _lineItem(String label, String amount) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(child: Text(label, style: const TextStyle(fontSize: 12))),
            const SizedBox(width: 8),
            Text(amount, style: const TextStyle(fontSize: 12)),
          ],
        ),
      );

  Widget _buildPostPaymentReferenceCard() {
    final payment = _payment ?? {};
    final txRef = (payment['transaction_ref']?.toString().isNotEmpty == true)
        ? payment['transaction_ref'].toString()
        : ((payment['receipt_number']?.toString().isNotEmpty == true)
            ? payment['receipt_number'].toString()
            : _receiptNo());
    final method = (payment['payment_method']?.toString().toUpperCase() ?? 'CASH');
    final cashier = payment['cashier_name']?.toString() ?? 'Tabaco City Slaughterhouse Admin';
    final paidAtStr = payment['paid_at'] ?? payment['updated_at'] ?? payment['created_at'];
    DateTime paidAt = DateTime.now();
    if (paidAtStr != null) {
      final p = DateTime.tryParse(paidAtStr.toString());
      if (p != null) paidAt = p.toLocal();
    }
    final formattedPaidDate = DateFormat('MMMM d, yyyy • h:mm a').format(paidAt);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFA5D6A7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified, color: Color(0xFF2E7D32), size: 18),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Payment Completed & Verified',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFC8E6C9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('PAID', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: Colors.green.shade200),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Official Payment Reference #', style: TextStyle(fontSize: 10, color: Color(0xFF388E3C), fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    SelectableText(
                      txRef,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20), letterSpacing: 0.5),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.copy, size: 16, color: Color(0xFF2E7D32)),
                tooltip: 'Copy Reference',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: txRef));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Row(children: [
                        Icon(Icons.check_circle, color: Colors.white, size: 16),
                        SizedBox(width: 8),
                        Text('Payment reference copied to clipboard!'),
                      ]),
                      duration: Duration(seconds: 2),
                      backgroundColor: Color(0xFF2E7D32),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          _receiptMetaRow('Method', method),
          _receiptMetaRow('Verified By', cashier),
          _receiptMetaRow('Payment Time', formattedPaidDate),
        ],
      ),
    );
  }

  Widget _receiptMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label:', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF2D3748)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarketDeliveryInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.local_shipping, size: 20, color: Color(0xFF166534)),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Direct Market Delivery',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF166534)),
                ),
                SizedBox(height: 2),
                Text(
                  'Your meat order will be delivered directly to your market stall via refrigerated van. No pick-up authorization required.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF166534)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthorizedRepresentativeCard(Map<String, dynamic> req) {
    final authName = (req['authorized_person_name'] ?? '').toString().trim();
    final authContact = (req['authorized_person_contact'] ?? '').toString().trim();
    final authIdType = (req['authorized_person_id_type'] ?? '').toString().trim();
    final authIdNum = (req['authorized_person_id_num'] ?? '').toString().trim();
    final authRel = (req['authorized_person_relationship'] ?? '').toString().trim();
    final hasAuth = authName.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasAuth ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hasAuth ? const Color(0xFF86EFAC) : Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(hasAuth ? Icons.verified_user : Icons.badge_outlined, size: 18, color: hasAuth ? const Color(0xFF16A34A) : const Color(0xFF475569)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Meat Pickup Authorization',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: hasAuth ? const Color(0xFF15803D) : const Color(0xFF1E293B),
                  ),
                ),
              ),
              if (hasAuth)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(4)),
                  child: const Text('Authorized', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF166534))),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (hasAuth) ...[
            Text('Designated Representative: $authName${authRel.isNotEmpty ? " ($authRel)" : ""}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            if (authContact.isNotEmpty)
              Text('Contact: $authContact', style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
            if (authIdType.isNotEmpty || authIdNum.isNotEmpty)
              Text('Valid ID: $authIdType — $authIdNum', style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _showAuthorizedPersonSheet(context, req),
              icon: const Icon(Icons.edit, size: 12),
              label: const Text('Change Representative', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF15803D),
                side: const BorderSide(color: Color(0xFF86EFAC)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: const Size(0, 30),
              ),
            ),
          ] else ...[
            Text('Primary Claimant: ${req['customer_name'] ?? 'You (Account Owner)'}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text('Unable to pick up in person? Assign an authorized person with valid ID to claim the meat on your behalf.', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => _showAuthorizedPersonSheet(context, req),
              icon: const Icon(Icons.person_add_alt_1, size: 13),
              label: const Text('Assign Authorized Person', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF15803D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: const Size(0, 32),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                elevation: 0,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showAuthorizedPersonSheet(BuildContext context, Map<String, dynamic> req) {
    final nameCtrl = TextEditingController(text: req['authorized_person_name']?.toString() ?? '');
    final contactCtrl = TextEditingController(text: req['authorized_person_contact']?.toString() ?? '');
    final idNumCtrl = TextEditingController(text: req['authorized_person_id_num']?.toString() ?? '');
    String selectedIdType = (req['authorized_person_id_type']?.toString().isNotEmpty == true)
        ? req['authorized_person_id_type'].toString()
        : 'Philippine National ID (PhilSys)';
    String selectedRelationship = (req['authorized_person_relationship']?.toString().isNotEmpty == true)
        ? req['authorized_person_relationship'].toString()
        : 'Spouse';

    const idTypes = [
      'Philippine National ID (PhilSys)',
      'Driver\'s License',
      'UMID',
      'Passport',
      'SSS / GSIS ID',
      'Voter\'s ID',
      'Postal ID',
      'PRC ID',
      'Barangay ID',
      'Other Valid Government ID',
    ];

    const relationships = [
      'Spouse',
      'Sibling',
      'Child / Parent',
      'Relative',
      'Driver / Transporter',
      'Employee / Assistant',
      'Other Authorized Person',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.badge, color: Color(0xFF15803D), size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Assign Authorized Representative',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A202C)),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Provide details of the person authorized to pick up the carcass at the slaughterhouse. They must present this valid ID to the releasing clerk upon collection.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    _sheetLabel('Representative Full Name *'),
                    TextField(
                      controller: nameCtrl,
                      decoration: _sheetInputDecoration('e.g. Juan Dela Cruz'),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    _sheetLabel('Contact / Mobile Number *'),
                    TextField(
                      controller: contactCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: _sheetInputDecoration('e.g. 09171234567'),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    _sheetLabel('Relationship to Customer *'),
                    DropdownButtonFormField<String>(
                      initialValue: relationships.contains(selectedRelationship) ? selectedRelationship : relationships.first,
                      isExpanded: true,
                      decoration: _sheetInputDecoration(''),
                      items: relationships.map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 13)))).toList(),
                      onChanged: (v) => setSheetState(() => selectedRelationship = v ?? 'Other'),
                    ),
                    const SizedBox(height: 12),
                    _sheetLabel('Valid ID Type Presented *'),
                    DropdownButtonFormField<String>(
                      initialValue: idTypes.contains(selectedIdType) ? selectedIdType : idTypes.first,
                      isExpanded: true,
                      decoration: _sheetInputDecoration(''),
                      items: idTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13)))).toList(),
                      onChanged: (v) => setSheetState(() => selectedIdType = v ?? 'Valid ID'),
                    ),
                    const SizedBox(height: 12),
                    _sheetLabel('Valid ID Number *'),
                    TextField(
                      controller: idNumCtrl,
                      decoration: _sheetInputDecoration('Enter ID Card Number'),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF15803D),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () async {
                          final name = nameCtrl.text.trim();
                          final contact = contactCtrl.text.trim();
                          final idNum = idNumCtrl.text.trim();
                          if (name.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter representative full name'), backgroundColor: Colors.orange),
                            );
                            return;
                          }
                          try {
                            // 1. Try updating requests directly (if migration columns exist)
                            try {
                              await supabase.from('requests').update({
                                'authorized_person_name': name,
                                'authorized_person_contact': contact,
                                'authorized_person_relationship': selectedRelationship,
                                'authorized_person_id_type': selectedIdType,
                                'authorized_person_id_num': idNum,
                              }).eq('id', req['id']);
                            } catch (_) {}

                            // 2. Also persist to system_settings 'authorized_representatives' as universal fallback
                            try {
                              final existing = await supabase
                                  .from('system_settings')
                                  .select('value')
                                  .eq('key', 'authorized_representatives')
                                  .maybeSingle();
                              Map<String, dynamic> currentMap = {};
                              if (existing != null && existing['value'] is Map) {
                                currentMap = Map<String, dynamic>.from(existing['value']);
                              }
                              currentMap[req['id'].toString()] = {
                                'name': name,
                                'contact': contact,
                                'relationship': selectedRelationship,
                                'id_type': selectedIdType,
                                'id_num': idNum,
                              };
                              await supabase.from('system_settings').upsert({
                                'key': 'authorized_representatives',
                                'value': currentMap,
                                'updated_at': DateTime.now().toIso8601String(),
                              });
                            } catch (_) {}

                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            _loadReceiptData();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Row(children: [
                                  Icon(Icons.check_circle, color: Colors.white, size: 18),
                                  SizedBox(width: 8),
                                  Text('Authorized representative saved for meat pickup!'),
                                ]),
                                backgroundColor: Color(0xFF15803D),
                              ),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error saving representative: $e'), backgroundColor: Colors.red),
                            );
                          }
                        },
                        child: const Text('Save & Confirm Authorization', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _sheetLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
  );

  InputDecoration _sheetInputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF15803D), width: 1.5)),
  );
}
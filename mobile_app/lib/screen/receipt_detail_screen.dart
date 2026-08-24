import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

        // Calculate fees
        final weight = double.tryParse((requestData['carcass_weight'] ?? 0).toString()) ?? 0;
        final postMortemFee = weight * _kPostMortemRatePerKg;
        final subtotal = _kVetHealthCertFee + _kPermitToSlaughterFee + _kFacilityFee + _kCorralFee + _kAnteMortemFee + postMortemFee;
        final isBarangay = requestData['request_type'] == 'barangay';
        final deliveryFee = isBarangay ? 0.0 : _kDeliveryVanFee;

        setState(() {
          _request = requestData;
          _payment = paymentData;
          _fees = {
            'vet_health_cert': _kVetHealthCertFee,
            'permit_to_slaughter': _kPermitToSlaughterFee,
            'facility': _kFacilityFee,
            'corral': _kCorralFee,
            'ante_mortem': _kAnteMortemFee,
            'post_mortem': postMortemFee,
            'subtotal': subtotal,
            'delivery_van': deliveryFee,
            'total': subtotal + deliveryFee,
          };
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
    final total = _fees['total'] ?? 0;

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
                  const SizedBox(height: 8),
                  Text("Payment Method: ${_payment!['payment_method']?.toString().toUpperCase() ?? 'CASH'}",
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const Text("Status: PAID", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1A8C62))),
                  const SizedBox(height: 4),
                  Text("Cashier: ${_payment!['cashier_name'] ?? 'Admin'}",
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 12),
                  const Text("Thank you!", style: TextStyle(fontSize: 12)),
                  const Text("Tabaco City Slaughterhouse", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                ],
                const SizedBox(height: 16),
                if (!isPaid) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE1F5EE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text("Please review the receipt before proceeding with payment",
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
      // Refresh the receipt data to show the PAID state
      _loadReceiptData();
    }
  }

  static Widget _kv(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      );

  static Widget _lineItem(String label, String amount) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: Text(label, style: const TextStyle(fontSize: 12))),
            Text(amount, style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
}
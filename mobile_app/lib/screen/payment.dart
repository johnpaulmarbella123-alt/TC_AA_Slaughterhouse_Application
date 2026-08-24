import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'receipt_detail_screen.dart';

const kMintHeader = Color(0xFF8FDCB8);

class PaymentContent extends StatefulWidget {
  const PaymentContent({super.key});

  @override
  State<PaymentContent> createState() => _PaymentContentState();
}

class _PaymentContentState extends State<PaymentContent> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _payments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Query payments for the current user, joined with requests
      final data = await supabase
          .from('payments')
          .select('*, requests!inner(id, customer_name, livestock_type, animal_count, request_type, preferred_date, carcass_weight)')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      setState(() {
        _payments = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Payment load error: $e');
      // Fallback: try loading without join if relation not set up
      try {
        final user = supabase.auth.currentUser;
        if (user == null) {
          setState(() => _isLoading = false);
          return;
        }
        final data = await supabase
            .from('payments')
            .select()
            .eq('user_id', user.id)
            .order('created_at', ascending: false);
        setState(() {
          _payments = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      } catch (e2) {
        debugPrint('Payment fallback load error: $e2');
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatDate(dynamic dateVal) {
    if (dateVal == null) return '—';
    try {
      final dt = DateTime.parse(dateVal.toString());
      final months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return dateVal.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
            decoration: const BoxDecoration(color: Color(0xFFC8E6C9)),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Payment",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 2),
                Text("View and manage your payment transactions.",
                    style: TextStyle(fontSize: 11, color: Colors.black87)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: Color(0xFF3ECFA3))),
            )
          else if (_payments.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text('No payment records yet',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text('Payments will appear here after processing',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                  ],
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: _payments.map((payment) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ReceiptCard(
                      payment: payment,
                      formatDate: _formatDate,
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  final Map<String, dynamic> payment;
  final String Function(dynamic) formatDate;

  const _ReceiptCard({required this.payment, required this.formatDate});

  @override
  Widget build(BuildContext context) {
    final requestId = payment['request_id']?.toString() ?? '000';
    final receiptNo = payment['receipt_number']?.toString() ?? 'RCP-${DateTime.now().year}-${requestId.padLeft(3, '0')}';
    final total = double.tryParse((payment['total_amount'] ?? 0).toString()) ?? 0;
    final status = payment['status']?.toString() ?? 'pending';
    final isPaid = status == 'paid';
    final method = payment['payment_method']?.toString() ?? '';

    // Try to get request data from join
    final requestData = payment['requests'] as Map<String, dynamic>?;
    final livestockType = requestData?['livestock_type']?.toString() ?? '';
    final scheduleDate = requestData?['preferred_date'];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (livestockType.isNotEmpty)
                      Text(livestockType,
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 2),
                    Text("Receipt #$receiptNo",
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isPaid ? const Color(0xFFE4F8F0) : const Color(0xFFFAC775),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isPaid ? 'Paid' : 'Pending Payment',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: isPaid ? const Color(0xFF0F6E56) : const Color(0xFF633806),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _LabelValue(
                  label: "Schedule date:", value: formatDate(scheduleDate)),
              _LabelValue(
                  label: "Amount:",
                  value: "\u20b1${total.toStringAsFixed(2)}",
                  alignEnd: true),
            ],
          ),
          if (isPaid && method.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  method == 'Cash'
                      ? Icons.payments_outlined
                      : (method == 'GCash'
                          ? Icons.phone_android
                          : Icons.credit_card),
                  size: 14,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 4),
                Text('Paid via $method',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          ReceiptDetailScreen(requestId: requestId)),
                );
              },
              icon: const Icon(Icons.visibility_outlined, size: 15),
              label: Text(
                isPaid ? "View Receipt" : "View Receipt & Pay",
                style: const TextStyle(fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black87,
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabelValue extends StatelessWidget {
  final String label;
  final String value;
  final bool alignEnd;
  const _LabelValue(
      {required this.label, required this.value, this.alignEnd = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        const SizedBox(height: 2),
        Text(value,
            style:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
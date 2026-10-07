import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'receipt_detail_screen.dart';

const kMintHeader = Color(0xFF8FDCB8);

class PaymentContent extends StatefulWidget {
  final ValueNotifier<int>? refreshTrigger;
  const PaymentContent({super.key, this.refreshTrigger});

  @override
  State<PaymentContent> createState() => _PaymentContentState();
}

class _PaymentContentState extends State<PaymentContent> with WidgetsBindingObserver {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _payments = [];
  bool _isLoading = true;
  RealtimeChannel? _paymentsChannel;
  RealtimeChannel? _requestsChannel;
  Timer? _autoSyncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPayments();
    _subscribeRealtime();
    widget.refreshTrigger?.addListener(_onRefreshTriggered);

    // Auto-sync every 2 seconds in the background so transactions update automatically
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) _loadPayments(silent: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSyncTimer?.cancel();
    widget.refreshTrigger?.removeListener(_onRefreshTriggered);
    if (_paymentsChannel != null) {
      supabase.removeChannel(_paymentsChannel!);
    }
    if (_requestsChannel != null) {
      supabase.removeChannel(_requestsChannel!);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _loadPayments(silent: true);
    }
  }

  void _onRefreshTriggered() {
    _loadPayments(silent: false);
  }

  void _subscribeRealtime() {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    // Listen to payments changes
    _paymentsChannel = supabase
        .channel('public:payments_realtime_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'payments',
          callback: (_) {
            if (mounted) _loadPayments(silent: true);
          },
        )
        .subscribe();

    // Listen to requests changes
    _requestsChannel = supabase
        .channel('public:requests_realtime_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'requests',
          callback: (_) {
            if (mounted) _loadPayments(silent: true);
          },
        )
        .subscribe();
  }

  Future<void> _loadPayments({bool silent = false}) async {
    if (!silent && _payments.isEmpty) {
      if (mounted) setState(() => _isLoading = true);
    }
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // 1. Fetch payments joined with requests
      final data = await supabase
          .from('payments')
          .select('*, requests(id, customer_name, livestock_type, animal_count, request_type, preferred_date, status)')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      final paymentsList = List<Map<String, dynamic>>.from(data);

      // 2. Also check if any completed/released requests don't have a payments record
      final existingReqIds = paymentsList
          .map((p) => p['request_id'])
          .where((id) => id != null)
          .toSet();

      final completedReqs = await supabase
          .from('requests')
          .select('id, customer_name, livestock_type, animal_count, request_type, preferred_date, status, created_at')
          .eq('user_id', user.id)
          .inFilter('status', ['paid', 'released', 'completed']);

      final List<Map<String, dynamic>> combined = List<Map<String, dynamic>>.from(paymentsList);
      for (final req in (completedReqs as List)) {
        if (!existingReqIds.contains(req['id'])) {
          combined.add({
            'id': -req['id'],
            'request_id': req['id'],
            'user_id': user.id,
            'receipt_number': 'RCP-${DateTime.now().year}-${req['id'].toString().padLeft(3, '0')}',
            'payment_method': 'Cash',
            'total_amount': 0.0,
            'status': 'paid',
            'created_at': req['created_at'],
            'requests': req,
          });
        }
      }

      // Sort by created_at descending
      combined.sort((a, b) {
        final dateA = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime(2000);
        final dateB = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime(2000);
        return dateB.compareTo(dateA);
      });

      if (mounted) {
        setState(() {
          _payments = combined;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Payment load error: $e');
      if (mounted && _payments.isEmpty) {
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

    // Try to get request data from join (handle Map or List)
    Map<String, dynamic>? requestData;
    final reqField = payment['requests'];
    if (reqField is List && reqField.isNotEmpty) {
      requestData = reqField.first as Map<String, dynamic>;
    } else if (reqField is Map) {
      requestData = reqField as Map<String, dynamic>;
    }
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
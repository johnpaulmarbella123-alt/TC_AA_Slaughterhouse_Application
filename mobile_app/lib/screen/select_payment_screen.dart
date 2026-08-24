import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

class SelectPaymentScreen extends StatefulWidget {
  final Map<String, dynamic> request;
  final Map<String, double> fees;
  final String receiptNo;

  const SelectPaymentScreen({
    super.key,
    required this.request,
    required this.fees,
    required this.receiptNo,
  });

  @override
  State<SelectPaymentScreen> createState() => _SelectPaymentScreenState();
}

class _SelectPaymentScreenState extends State<SelectPaymentScreen>
    with WidgetsBindingObserver {
  final supabase = Supabase.instance.client;
  bool _isProcessing = false;
  String _selectedMethod = 'Cash on Pickup'; // 'GCash' or 'Cash on Pickup'

  // PayMongo state
  String? _paymongoLinkId;
  bool _isPolling = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  /// When user returns to app from browser, check payment status
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _paymongoLinkId != null) {
      _checkPaymentStatus();
    }
  }

  // ═══════════════════════════════════════════════════
  //  CASH PAYMENT (existing flow, unchanged)
  // ═══════════════════════════════════════════════════
  Future<void> _processPayment(String method) async {
    setState(() => _isProcessing = true);
    try {
      final reqId = widget.request['id'];

      // Update payment record
      await supabase.from('payments').update({
        'payment_method': method == 'GCash' ? 'GCash' : 'Cash',
        'status': 'paid',
        'balance': 0,
      }).eq('request_id', reqId);

      // Update requests record
      await supabase.from('requests').update({
        'status': 'paid',
      }).eq('id', reqId);

      if (!mounted) return;
      _showSuccessDialog(method);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ═══════════════════════════════════════════════════
  //  GCASH PAYMENT VIA PAYMONGO
  // ═══════════════════════════════════════════════════
  Future<void> _handleGCash() async {
    setState(() => _isProcessing = true);

    try {
      final total = widget.fees['total'] ?? 0;
      final reqId = widget.request['id'];
      final customerName = widget.request['customer_name'] ?? 'Customer';

      // Step 1: Call Supabase Edge Function to create PayMongo payment link
      final supabaseUrl = supabase.rest.url.replaceAll('/rest/v1', '');
      final functionUrl = '$supabaseUrl/functions/v1/create-gcash-payment';

      final response = await http.post(
        Uri.parse(functionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${supabase.auth.currentSession?.accessToken ?? ''}',
          'apikey': supabase.rest.headers['apikey'] ?? '',
        },
        body: jsonEncode({
          'amount': total,
          'description': 'Slaughter Service Payment - $customerName (${widget.receiptNo})',
          'request_id': reqId,
        }),
      );

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? error['details'] ?? 'Failed to create payment link');
      }

      final data = jsonDecode(response.body);
      final checkoutUrl = data['checkout_url'] as String;
      final linkId = data['link_id'] as String;

      setState(() {
        _paymongoLinkId = linkId;
      });

      // Step 2: Save the PayMongo link_id to the payment record for tracking
      await supabase.from('payments').update({
        'payment_method': 'GCash',
      }).eq('request_id', reqId);

      // Step 3: Open PayMongo checkout page in browser
      final uri = Uri.parse(checkoutUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Could not open payment page. Please try again.');
      }

      // Step 4: Start polling for payment status (user will pay in browser)
      _startPolling();

    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('GCash Error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════
  //  POLL PAYMENT STATUS
  // ═══════════════════════════════════════════════════
  void _startPolling() {
    _isPolling = true;
    // Poll every 5 seconds for up to 10 minutes
    int attempts = 0;
    const maxAttempts = 120; // 10 minutes

    _pollTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      attempts++;
      if (attempts > maxAttempts || !_isPolling) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _isPolling = false;
          });
        }
        return;
      }
      await _checkPaymentStatus();
    });
  }

  Future<void> _checkPaymentStatus() async {
    if (_paymongoLinkId == null) return;

    try {
      final supabaseUrl = supabase.rest.url.replaceAll('/rest/v1', '');
      final functionUrl =
          '$supabaseUrl/functions/v1/create-gcash-payment?link_id=$_paymongoLinkId';

      final response = await http.get(
        Uri.parse(functionUrl),
        headers: {
          'Authorization': 'Bearer ${supabase.auth.currentSession?.accessToken ?? ''}',
          'apikey': supabase.rest.headers['apikey'] ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final status = data['status'] as String?;

        if (status == 'paid') {
          // Payment successful!
          _pollTimer?.cancel();
          _isPolling = false;
          _paymongoLinkId = null;

          // Update database
          final reqId = widget.request['id'];
          await supabase.from('payments').update({
            'payment_method': 'GCash',
            'status': 'paid',
            'balance': 0,
          }).eq('request_id', reqId);

          await supabase.from('requests').update({
            'status': 'paid',
          }).eq('id', reqId);

          if (mounted) {
            setState(() => _isProcessing = false);
            _showSuccessDialog('GCash');
          }
        }
      }
    } catch (e) {
      debugPrint('Poll error: $e');
    }
  }

  // ═══════════════════════════════════════════════════
  //  SUCCESS DIALOG
  // ═══════════════════════════════════════════════════
  void _showSuccessDialog(String method) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Color(0xFFE4F8F0),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle,
                  color: Color(0xFF1A8C62), size: 32),
            ),
            const SizedBox(height: 14),
            Text(
              method == 'GCash'
                  ? 'GCash Payment Successful!'
                  : 'Payment on pickup was Successful!',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            if (method == 'GCash') ...[
              const SizedBox(height: 8),
              Text(
                'Paid via GCash • PayMongo',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx); // Close dialog
                Navigator.pop(context, true); // Go back, passing success
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0056B3),
                foregroundColor: Colors.white,
                minimumSize: const Size(120, 36),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.fees['total'] ?? 0;
    // Extract schedule date
    final scheduleDate = widget.request['preferred_date'];
    String formattedDate = '\u2014';
    if (scheduleDate != null) {
      try {
        final dt = DateTime.parse(scheduleDate.toString());
        final months = [
          'January', 'February', 'March', 'April', 'May', 'June',
          'July', 'August', 'September', 'October', 'November', 'December'
        ];
        formattedDate = '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
      } catch (_) {}
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 50, 16, 20),
            color: const Color(0xFF8FDCB8),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Payment",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                SizedBox(height: 2),
                Text("Manage your account settings and preferences",
                    style:
                        TextStyle(fontSize: 11, color: Color(0xFF2C2C2A))),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    // Header
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Text('Select Payment Method',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Toggle Button — GCash now ENABLED
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F0F0),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            // ── GCash Toggle ──
                            Expanded(
                              child: GestureDetector(
                                onTap: _isProcessing
                                    ? null
                                    : () => setState(
                                        () => _selectedMethod = 'GCash'),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: _selectedMethod == 'GCash'
                                        ? Colors.white
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: _selectedMethod == 'GCash'
                                        ? [
                                            BoxShadow(
                                                color: Colors.black
                                                    .withOpacity(0.05),
                                                blurRadius: 4)
                                          ]
                                        : null,
                                  ),
                                  child: Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.phone_android,
                                            size: 16,
                                            color:
                                                _selectedMethod == 'GCash'
                                                    ? const Color(0xFF007DFE)
                                                    : Colors.grey),
                                        const SizedBox(width: 4),
                                        Text('GCash',
                                            style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                                color: _selectedMethod ==
                                                        'GCash'
                                                    ? const Color(0xFF007DFE)
                                                    : Colors.grey)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // ── Cash Toggle ──
                            Expanded(
                              child: GestureDetector(
                                onTap: _isProcessing
                                    ? null
                                    : () => setState(() =>
                                        _selectedMethod = 'Cash on Pickup'),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color:
                                        _selectedMethod == 'Cash on Pickup'
                                            ? Colors.white
                                            : Colors.transparent,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow:
                                        _selectedMethod == 'Cash on Pickup'
                                            ? [
                                                BoxShadow(
                                                    color: Colors.black
                                                        .withOpacity(0.05),
                                                    blurRadius: 4)
                                              ]
                                            : null,
                                  ),
                                  child: Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.payments_outlined,
                                            size: 16,
                                            color: _selectedMethod ==
                                                    'Cash on Pickup'
                                                ? Colors.black87
                                                : Colors.grey),
                                        const SizedBox(width: 4),
                                        Text('Cash',
                                            style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                                color: _selectedMethod ==
                                                        'Cash on Pickup'
                                                    ? Colors.black87
                                                    : Colors.grey)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Content Area
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: _selectedMethod == 'GCash'
                                ? const Color(0xFFD6EEFF)
                                : const Color(0xFFA5F3CA),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.all(20),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(
                                  _selectedMethod == 'GCash'
                                      ? Icons.phone_android
                                      : Icons.payments_outlined,
                                  size: 32,
                                  color: _selectedMethod == 'GCash'
                                      ? const Color(0xFF007DFE)
                                      : const Color(0xFF0F6E56),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _selectedMethod == 'GCash'
                                      ? 'GCash via PayMongo'
                                      : _selectedMethod,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _selectedMethod == 'GCash'
                                      ? 'Pay instantly using your GCash account'
                                      : 'Pay when you pick up your Meat',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: _selectedMethod == 'GCash'
                                          ? const Color(0xFF004A99)
                                          : const Color(0xFF2C2C2A)),
                                ),
                                const SizedBox(height: 24),

                                // Amount Card
                                Container(
                                  width: double.infinity,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    children: [
                                      const Text('Amount to Pay',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey)),
                                      const SizedBox(height: 4),
                                      Text(
                                          '\u20b1${total.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 8),
                                      const Text('Pickup Date',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey)),
                                      Text(formattedDate,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Important Notes
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: _selectedMethod == 'GCash'
                                        ? const Color(0xFFB8DCFF)
                                        : const Color(0xFF8FF0B8),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Important:',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color:
                                                  _selectedMethod == 'GCash'
                                                      ? const Color(
                                                          0xFF004A99)
                                                      : const Color(
                                                          0xFF0F6E56))),
                                      const SizedBox(height: 8),
                                      if (_selectedMethod ==
                                          'Cash on Pickup') ...[
                                        _bulletPoint(
                                            'Please bring exact amount'),
                                        _bulletPoint(
                                            'Payment is due on pickup day'),
                                        _bulletPoint(
                                            'Cash only for pickup payment'),
                                        _bulletPoint(
                                            'Show this receipt number for reference'),
                                      ] else ...[
                                        _bulletPoint(
                                            'You will be redirected to PayMongo to pay via GCash',
                                            isGCash: true),
                                        _bulletPoint(
                                            'Complete the payment in your browser',
                                            isGCash: true),
                                        _bulletPoint(
                                            'Return to this app after paying — status will update automatically',
                                            isGCash: true),
                                        _bulletPoint(
                                            'Do not close this app while paying',
                                            isGCash: true),
                                      ],
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 24),

                                // Processing indicator when polling
                                if (_isPolling) ...[
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF3CD),
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      border: Border.all(
                                          color: const Color(0xFFFFD97A)),
                                    ),
                                    child: const Row(
                                      children: [
                                        SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              color: Color(0xFF856404),
                                              strokeWidth: 2),
                                        ),
                                        SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            'Waiting for GCash payment confirmation...\nReturn here after completing payment.',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF856404)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],

                                // Confirm Button
                                SizedBox(
                                  width: double.infinity,
                                  height: 46,
                                  child: ElevatedButton(
                                    onPressed: _isProcessing
                                        ? null
                                        : () => _selectedMethod == 'GCash'
                                            ? _handleGCash()
                                            : _processPayment(
                                                'Cash on Pickup'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          _selectedMethod == 'GCash'
                                              ? const Color(0xFF007DFE)
                                              : const Color(0xFF0F6E56),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                    child: _isProcessing
                                        ? const SizedBox(
                                            height: 18,
                                            width: 18,
                                            child:
                                                CircularProgressIndicator(
                                                    color: Colors.white,
                                                    strokeWidth: 2))
                                        : Text(
                                            _selectedMethod == 'GCash'
                                                ? 'Pay with GCash'
                                                : 'Confirm Cash Payment',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600),
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _selectedMethod == 'GCash'
                                      ? 'Secure payment powered by PayMongo'
                                      : 'By confirming, you agree to pay cash on pickup',
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: _selectedMethod == 'GCash'
                                          ? const Color(0xFF004A99)
                                          : const Color(0xFF0F6E56)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bulletPoint(String text, {bool isGCash = false}) {
    final color = isGCash ? const Color(0xFF004A99) : const Color(0xFF0F6E56);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('\u2022 ', style: TextStyle(fontSize: 11, color: color)),
          Expanded(
              child:
                  Text(text, style: TextStyle(fontSize: 11, color: color))),
        ],
      ),
    );
  }
}

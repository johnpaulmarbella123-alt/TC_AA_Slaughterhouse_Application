import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

  // Only two payment options: 'Online' or 'Cash'
  String _selectedMethod = 'Online';

  // PayMongo state & concurrency guard
  String? _paymongoLinkId;
  bool _isPolling = false;
  bool _isCheckingStatus = false;
  bool _isHandlingSuccess = false;
  bool _hasInsertedNotification = false;
  String? _confirmedPaymentMethod;
  double? _confirmedTotal;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreSavedPaymongoLink();
  }

  Future<void> _restoreSavedPaymongoLink() async {
    try {
      final reqId = widget.request['id'];
      if (reqId == null) return;
      final prefs = await SharedPreferences.getInstance();
      String? savedLink = prefs.getString('paymongo_link_$reqId');

      if (savedLink == null || savedLink.isEmpty) {
        final payRow = await supabase
            .from('payments')
            .select('transaction_ref, status')
            .eq('request_id', reqId)
            .maybeSingle();
        if (payRow != null &&
            payRow['status'] != 'paid' &&
            payRow['transaction_ref'] != null &&
            (payRow['transaction_ref'].toString().startsWith('link_') ||
             payRow['transaction_ref'].toString().startsWith('cs_'))) {
          savedLink = payRow['transaction_ref'].toString();
        }
      }
      if (savedLink != null && savedLink.isNotEmpty && mounted) {
        setState(() {
          _paymongoLinkId = savedLink;
        });
        await _checkPaymentStatus();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    if (_isHandlingSuccess && !_hasInsertedNotification) {
      _sendPaymentConfirmedNotificationOnce();
    }
    try {
      closeInAppWebView();
    } catch (_) {}
    super.dispose();
  }

  /// When user returns to app from browser, check payment status immediately
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _paymongoLinkId != null && !_isHandlingSuccess) {
      _checkPaymentStatus();
    }
  }

  // ═══════════════════════════════════════════════════
  //  CASH ON PICKUP — submitted for cashier verification
  // ═══════════════════════════════════════════════════
  Future<void> _processPayment(String method) async {
    setState(() => _isProcessing = true);
    try {
      final reqId = widget.request['id'];

      await supabase.from('payments').update({
        'payment_method': 'Cash',
        'status': 'pending',
      }).eq('request_id', reqId);

      if (!mounted) return;
      _showSubmittedDialog(method);
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
  //  ONLINE PAYMENT VIA PAYMONGO (Handles GCash, Maya, Cards, GrabPay on Portal)
  // ═══════════════════════════════════════════════════
  Future<void> _handleOnlinePayment() async {
    setState(() => _isProcessing = true);

    try {
      final total = widget.fees['total'] ?? 0;
      final reqId = widget.request['id'];
      final customerName = widget.request['customer_name'] ?? 'Customer';

      // Call Supabase Edge Function to create PayMongo payment link
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
          'description': 'Slaughter Service Online Payment - $customerName (${widget.receiptNo})',
          'request_id': reqId,
        }),
      );

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? error['details'] ?? 'Failed to create online payment link');
      }

      final data = jsonDecode(response.body);
      final checkoutUrl = data['checkout_url'] as String;
      final linkId = data['link_id'] as String;

      setState(() {
        _paymongoLinkId = linkId;
      });

      // Persist link_id locally and in transaction_ref
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('paymongo_link_$reqId', linkId);
      } catch (_) {}
      try {
        await supabase.from('payments').update({
          'transaction_ref': linkId,
        }).eq('request_id', reqId);
      } catch (_) {}

      // Open PayMongo checkout page where user chooses GCash, Maya, Cards, or GrabPay
      final uri = Uri.parse(checkoutUrl);
      try {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.inAppBrowserView,
        );
        if (!launched) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (launchError) {
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (_) {
          throw Exception('Could not open payment page. Please try again.');
        }
      }

      // Start polling for payment status
      _startPolling();

    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment Error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════
  //  POLL PAYMENT STATUS & CONCURRENCY GUARD
  // ═══════════════════════════════════════════════════
  void _startPolling() {
    _isPolling = true;
    int attempts = 0;
    const maxAttempts = 300; // 10 minutes (300 * 2s)

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      attempts++;
      if (attempts > maxAttempts || !_isPolling || _isHandlingSuccess) {
        timer.cancel();
        if (mounted && !_isHandlingSuccess) {
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
    // If already handling success, already checking, or no link ID, exit immediately
    if (_isHandlingSuccess || _isCheckingStatus || _paymongoLinkId == null) return;
    _isCheckingStatus = true;
    final linkId = _paymongoLinkId;

    try {
      final supabaseUrl = supabase.rest.url.replaceAll('/rest/v1', '');
      final functionUrl =
          '$supabaseUrl/functions/v1/create-gcash-payment?link_id=$linkId';

      final response = await http.get(
        Uri.parse(functionUrl),
        headers: {
          'Authorization': 'Bearer ${supabase.auth.currentSession?.accessToken ?? ''}',
          'apikey': supabase.rest.headers['apikey'] ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final status = data['status']?.toString().toLowerCase();
        final detectedMethodRaw = data['detected_method']?.toString();
        final paymentsList = data['payments'];
        bool hasPaidEntry = false;
        String? detectedFromPayments;

        if (paymentsList is List && paymentsList.isNotEmpty) {
          for (final p in paymentsList) {
            if (p is Map) {
              final pData = p['data'];
              final pDataAttr = (pData is Map) ? pData['attributes'] : null;
              final pAttr = p['attributes'];
              final rawStatus = p['status'] ??
                  ((pDataAttr is Map) ? pDataAttr['status'] : null) ??
                  ((pAttr is Map) ? pAttr['status'] : null);
              if (rawStatus?.toString().toLowerCase() == 'paid') {
                hasPaidEntry = true;
                final srcRaw = (pAttr is Map && pAttr['source'] is Map ? pAttr['source']['type'] : null) ??
                    (pDataAttr is Map && pDataAttr['source'] is Map ? pDataAttr['source']['type'] : null) ??
                    p['source'] ??
                    '';
                final srcType = srcRaw.toString().toLowerCase();
                if (srcType.contains('gcash')) {
                  detectedFromPayments = 'GCash';
                } else if (srcType.contains('maya')) {
                  detectedFromPayments = 'Maya';
                } else if (srcType.contains('card') || srcType.contains('visa') || srcType.contains('mastercard')) {
                  detectedFromPayments = 'Card';
                } else if (srcType.contains('grab')) {
                  detectedFromPayments = 'GrabPay';
                }
                break;
              }
            }
          }
        }

        if (status == 'paid' || hasPaidEntry) {
          // Mutex lock to prevent duplicate notifications or calls
          _isHandlingSuccess = true;
          _pollTimer?.cancel();

          if (mounted) {
            setState(() {
              _isPolling = false;
              _isProcessing = false;
              _paymongoLinkId = null;
            });
          } else {
            _isPolling = false;
            _isProcessing = false;
            _paymongoLinkId = null;
          }

          // Automatically dismiss in-app browser view
          try {
            await closeInAppWebView();
          } catch (e) {
            debugPrint('Could not close in-app browser: $e');
          }

          final reqId = widget.request['id'];
          final total = (widget.fees['total'] ?? 0).toDouble();

          // Resolve the exact payment channel detected from PayMongo
          String finalMethod = detectedFromPayments ??
              (detectedMethodRaw != null && detectedMethodRaw != 'Online (PayMongo)' ? detectedMethodRaw : null) ??
              'GCash';

          _confirmedPaymentMethod = finalMethod;
          _confirmedTotal = total;

          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('paymongo_link_$reqId');
          } catch (_) {}

          // 1. Record payment method and transaction link, leaving status for Clerk Verification
          try {
            await supabase.from('payments').update({
              'payment_method': finalMethod,
              'transaction_ref': linkId,
              'receipt_number': widget.receiptNo,
            }).eq('request_id', reqId);
          } catch (_) {}

          if (mounted) {
            _showPaidSuccessDialog(finalMethod, total);
          }
          return;
        }
      }

      // Check database fallback
      if (_isHandlingSuccess) return;
      final reqId = widget.request['id'];
      final payRow = await supabase
          .from('payments')
          .select('status, payment_method')
          .eq('request_id', reqId)
          .maybeSingle();
      final dbPaid = payRow != null && payRow['status'] == 'paid';
      if (dbPaid) {
        _isHandlingSuccess = true;
        _pollTimer?.cancel();
        final total = (widget.fees['total'] ?? 0).toDouble();
        final methodLabel = payRow['payment_method']?.toString() ?? 'Online Payment';
        _confirmedPaymentMethod = methodLabel;
        _confirmedTotal = total;

        if (mounted) {
          setState(() {
            _isPolling = false;
            _isProcessing = false;
            _paymongoLinkId = null;
          });
          _showPaidSuccessDialog(methodLabel, total);
        }
      }
    } catch (e) {
      debugPrint('Poll error: $e');
    } finally {
      _isCheckingStatus = false;
    }
  }

  // ═══════════════════════════════════════════════════
  //  SEND PAYMENT SUBMITTED NOTIFICATION (ONCE ON DONE)
  // ═══════════════════════════════════════════════════
  Future<void> _sendPaymentConfirmedNotificationOnce() async {
    if (_hasInsertedNotification) return;
    _hasInsertedNotification = true;

    final userId = widget.request['user_id'] ?? supabase.auth.currentUser?.id;
    if (userId == null) return;

    final reqId = widget.request['id'];
    final refNo = 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';
    final method = _confirmedPaymentMethod ?? 'Online Payment';
    final total = _confirmedTotal ?? (widget.fees['total'] ?? 0).toDouble();

    try {
      final existingNotif = await supabase
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('type', 'payment_submitted')
          .ilike('message', '%${widget.receiptNo}%')
          .maybeSingle();

      if (existingNotif == null) {
        await supabase.from('notifications').insert({
          'user_id': userId,
          'title': '$method Payment Submitted',
          'message':
              'Your online payment of \u20b1${total.toStringAsFixed(2)} via $method (Receipt ${widget.receiptNo}, Ref: $refNo) has been submitted and is awaiting Clerk verification.',
          'type': 'payment_submitted',
          'is_read': false,
        });
        debugPrint('Single payment submitted notification inserted for ${widget.receiptNo}');
      }
    } catch (notifErr) {
      debugPrint('Notification insert error on Done: $notifErr');
    }
  }

  // ═══════════════════════════════════════════════════
  //  PAID SUCCESS DIALOG (Awaiting Clerk Verification)
  // ═══════════════════════════════════════════════════
  void _showPaidSuccessDialog(String method, double total) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                color: Color(0xFFE0F2FE),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mark_email_read_outlined,
                  color: Color(0xFF0284C7), size: 32),
            ),
            const SizedBox(height: 14),
            const Text(
              'Payment Submitted!',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Your $method payment of \u20b1${total.toStringAsFixed(2)} has been submitted!\n\nAwaiting Slaughterhouse Clerk verification before receipt & meat release authorization are issued.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () async {
                // Insert exactly one notification when user taps Done
                await _sendPaymentConfirmedNotificationOnce();
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
                if (mounted) {
                  Navigator.pop(context, true); // Return true to land cleanly on Payment History
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                minimumSize: const Size(140, 40),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  CASH AWAITING VERIFICATION DIALOG
  // ═══════════════════════════════════════════════════
  void _showSubmittedDialog(String method) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                color: Color(0xFFFFF3CD),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.hourglass_top,
                  color: Color(0xFF856404), size: 32),
            ),
            const SizedBox(height: 14),
            const Text(
              'Cash on Pickup Selected',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Please pay the exact amount at the slaughterhouse cashier on pickup day. Your payment will be confirmed upon cashier receipt.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F6E56),
                foregroundColor: Colors.white,
                minimumSize: const Size(140, 40),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.fees['total'] ?? 0;
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

    final isOnline = _selectedMethod == 'Online';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FA),
      appBar: AppBar(
        title: const Text('Select Payment Method',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Amount Summary Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total Amount Due',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              const SizedBox(height: 4),
                              Text('\u20b1${total.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F6E56))),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('Receipt No.',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                              const SizedBox(height: 2),
                              Text(widget.receiptNo,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87)),
                              const SizedBox(height: 4),
                              Text('Scheduled: $formattedDate',
                                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                    const Text('Available Payment Methods',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(height: 10),

                    // ── OPTION 1: ONLINE PAYMENT (PAYMONGO) ──
                    InkWell(
                      onTap: _isProcessing
                          ? null
                          : () => setState(() => _selectedMethod = 'Online'),
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isOnline ? const Color(0xFFF0FDF4) : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isOnline ? const Color(0xFF2D6A4F) : Colors.grey.shade200,
                            width: isOnline ? 2 : 1,
                          ),
                          boxShadow: isOnline
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF2D6A4F).withOpacity(0.08),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  )
                                ]
                              : null,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: isOnline ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.account_balance_wallet_outlined,
                                    color: isOnline ? const Color(0xFF15803D) : Colors.grey.shade700,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Text(
                                            'Online Payment',
                                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFE0E7FF),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text('Online Gateway',
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFF3730A3))),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Choose GCash, Maya, Card, or GrabPay at checkout',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                                Radio<String>(
                                  value: 'Online',
                                  groupValue: _selectedMethod,
                                  activeColor: const Color(0xFF2D6A4F),
                                  onChanged: _isProcessing
                                      ? null
                                      : (v) => setState(() => _selectedMethod = v!),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Channel badges (handled on PayMongo)
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _channelBadge('GCash', const Color(0xFF007DFE)),
                                _channelBadge('Maya', const Color(0xFF10B981)),
                                _channelBadge('Visa / Mastercard', const Color(0xFF1E3A8A)),
                                _channelBadge('GrabPay', const Color(0xFF00B14F)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── OPTION 2: CASH ON PICKUP ──
                    InkWell(
                      onTap: _isProcessing
                          ? null
                          : () => setState(() => _selectedMethod = 'Cash'),
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: !isOnline ? const Color(0xFFF0FDF4) : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: !isOnline ? const Color(0xFF2D6A4F) : Colors.grey.shade200,
                            width: !isOnline ? 2 : 1,
                          ),
                          boxShadow: !isOnline
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF2D6A4F).withOpacity(0.08),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  )
                                ]
                              : null,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: !isOnline ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.payments_outlined,
                                color: !isOnline ? const Color(0xFF15803D) : Colors.grey.shade700,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Cash on Pickup',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Pay over-the-counter at slaughterhouse cashier',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                            Radio<String>(
                              value: 'Cash',
                              groupValue: _selectedMethod,
                              activeColor: const Color(0xFF2D6A4F),
                              onChanged: _isProcessing
                                  ? null
                                  : (v) => setState(() => _selectedMethod = v!),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Important Instructions Container
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isOnline ? const Color(0xFFEFF6FF) : const Color(0xFFFEFCE8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isOnline ? const Color(0xFFBFDBFE) : const Color(0xFFFEF08A),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isOnline ? Icons.info_outline : Icons.schedule_outlined,
                                size: 16,
                                color: isOnline ? const Color(0xFF1D4ED8) : const Color(0xFF854D0E),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isOnline ? 'Online Payment Instructions:' : 'Cash on Pickup Terms:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isOnline ? const Color(0xFF1D4ED8) : const Color(0xFF854D0E),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (isOnline) ...[
                            _infoBullet('Tap below to open the secure online payment portal in your browser.', isOnline: true),
                            _infoBullet('Select GCash, Maya, GrabPay, or enter your Card details on the checkout page.', isOnline: true),
                            _infoBullet('Once authorized, return to this app — payment will confirm automatically and record your chosen payment method.', isOnline: true),
                          ] else ...[
                            _infoBullet('Payment is settled directly at the slaughterhouse cashier window.', isOnline: false),
                            _infoBullet('Please bring the exact amount (\u20b1${total.toStringAsFixed(2)}) on your pickup date.', isOnline: false),
                            _infoBullet('Present your receipt number (${widget.receiptNo}) to claim inspected meat.', isOnline: false),
                          ],
                        ],
                      ),
                    ),

                    // Polling progress indicator
                    if (_isPolling) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFCD34D)),
                        ),
                        child: const Row(
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Color(0xFFB45309),
                                strokeWidth: 2,
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Awaiting online payment confirmation...\nPlease return here after completing checkout.',
                                style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Bottom Action Button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    offset: const Offset(0, -2),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isProcessing
                      ? null
                      : () => isOnline
                          ? _handleOnlinePayment()
                          : _processPayment('Cash on Pickup'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D6A4F),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 1,
                  ),
                  child: _isProcessing
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.2,
                          ),
                        )
                      : Text(
                          isOnline
                              ? 'Proceed to Online Payment (\u20b1${total.toStringAsFixed(2)})'
                              : 'Confirm Cash on Pickup',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _channelBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _infoBullet(String text, {required bool isOnline}) {
    final color = isOnline ? const Color(0xFF1E40AF) : const Color(0xFF713F12);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('\u2022 ', style: TextStyle(fontSize: 12, color: color)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: color, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

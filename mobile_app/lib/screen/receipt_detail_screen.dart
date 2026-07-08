import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dashed_line.dart';
import 'payment.dart' show kMintHeader;

const kAccentGreen = Color(0xFF1BC47D);

class ReceiptDetailScreen extends StatefulWidget {
  const ReceiptDetailScreen({super.key});

  @override
  State<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends State<ReceiptDetailScreen> {
  bool _isProcessing = false;
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
                Text("Manage your account settings and preferences",
                    style: TextStyle(fontSize: 11, color: Color(0xFF2C2C2A))),
              ],
            ),
          ),
          Expanded(
            child: Transform.translate(
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
                        const Center(
                          child: Column(
                            children: [
                              Text("Receipt", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                              SizedBox(height: 4),
                              Text("Reference #: MI-2025-001",
                                  style: TextStyle(fontSize: 11, color: Colors.grey)),
                              Text("October 25, 2025",
                                  style: TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        const DashedLine(),
                        const SizedBox(height: 14),
                        const Align(
                          alignment: Alignment.centerRight,
                          child: Text("John David", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(height: 8),
                        _kv("Livestock:", "Pig"),
                        _kv("Date:", "October 25, 2025"),
                        const SizedBox(height: 14),
                        const DashedLine(),
                        const SizedBox(height: 14),
                        const Text("Payment Calculation Preview",
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        _lineItem("Veterinary Health Certificate:", "₱50.00"),
                        _lineItem("Permit to Slaughter:", "₱60.00"),
                        _lineItem("Facility Fee:", "₱60.00"),
                        _lineItem("Corral Fee:", "₱40.00"),
                        _lineItem("Ante-Mortem:", "₱40.00"),
                        _lineItem("Post-Mortem (75 kg ₱5.00/kg):", "₱375.00"),
                        const SizedBox(height: 8),
                        Divider(color: Colors.grey.shade300),
                        const SizedBox(height: 4),
                        _kv("Subtotal:", "₱625.00"),
                        _kv("Delivery Van Fee:", "₱60"),
                        const SizedBox(height: 14),
                        const DashedLine(),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text("TOTAL AMOUNT:", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                            Text("₱685.00", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 16),
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
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleProceedToPayment() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login first')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      await supabase.from('notifications').insert({
        'user_id': user.id,
        'title': 'Receipt issued — ready for payment',
        'message':
            'Your receipt #RCP-2025-001 has been generated. Amount: \u20B1685.00',
        'is_read': false,
        'type': 'receipt_issued',
        'data': {
          'receipt_no': 'RCP-2025-001',
          'amount': 685.00,
        },
      });

      if (!mounted) return;

      // Show success state
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
              const Text('Payment Initiated!',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              const Text(
                'A receipt notification has been sent. You can view it in the Notifications tab.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx); // close dialog
                Navigator.pop(context); // back to payment list
              },
              child: const Text('Done',
                  style: TextStyle(color: Color(0xFF0A3D2E), fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
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
            Text(label, style: const TextStyle(fontSize: 12)),
            Text(amount, style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
}
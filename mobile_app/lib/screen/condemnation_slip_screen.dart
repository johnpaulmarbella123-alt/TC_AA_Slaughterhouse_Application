import 'package:flutter/material.dart';
import 'dashed_line.dart';
import 'payment.dart' show kMintHeader;
/// Detail screen for post-mortem / condemnation slips.
///
/// All fields come from the notification's `data` JSON map.
/// Missing keys gracefully fall back to 'N/A'.
class CondemnationSlipScreen extends StatelessWidget {
  final Map<String, dynamic> data;

  const CondemnationSlipScreen({super.key, required this.data});

  String _val(String key, [String fallback = 'N/A']) =>
      (data[key] ?? fallback).toString();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          // ── HEADER ──────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 50, 16, 20),
            color: kMintHeader,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Condemnation Slip",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                SizedBox(height: 2),
                Text("Post-mortem inspection result",
                    style: TextStyle(fontSize: 11, color: Color(0xFF2C2C2A))),
              ],
            ),
          ),

          // ── BODY CARD ───────────────────────────────────────
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
                        // Back + title row
                        Row(
                          children: [
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: const Icon(Icons.arrow_back, size: 18),
                              onPressed: () => Navigator.pop(context),
                            ),
                            const SizedBox(width: 6),
                            const Text("Condemnation Details",
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Status badge
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFCEAEA),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.cancel,
                                    size: 16, color: Color(0xFFC0392B)),
                                SizedBox(width: 6),
                                Text("Condemned",
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFA32D2D))),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Reference & date
                        Center(
                          child: Column(
                            children: [
                              Text("Ref: ${_val('reference_no')}",
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                              const SizedBox(height: 2),
                              Text("Date: ${_val('date')}",
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        const DashedLine(),
                        const SizedBox(height: 14),

                        // Customer & livestock info
                        const Text("Livestock Information",
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        _kv("Customer:", _val('customer_name')),
                        _kv("Livestock Type:", _val('livestock_type')),
                        _kv("Animal Count:", _val('animal_count', '1')),
                        _kv("Weight:", _val('weight')),
                        const SizedBox(height: 14),
                        const DashedLine(),
                        const SizedBox(height: 14),

                        // Inspection result
                        const Text("Inspection Result",
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        _kv("Inspector:", _val('inspector')),
                        _kv("Reason:", _val('reason')),
                        const SizedBox(height: 8),

                        // Remarks box
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFFE8C77B)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.info_outline,
                                      size: 14, color: Color(0xFF854F0B)),
                                  SizedBox(width: 6),
                                  Text("Remarks",
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF854F0B))),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _val('remarks',
                                    'No additional remarks provided.'),
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF854F0B)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        const DashedLine(),
                        const SizedBox(height: 14),

                        // Disposition
                        const Text("Disposition",
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        _kv("Action Taken:",
                            _val('disposition', 'Condemned & disposed')),
                        const SizedBox(height: 16),

                        // Info banner
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFCEAEA),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Text(
                                "This animal did not pass post-mortem inspection",
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFFA32D2D))),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Back button
                        SizedBox(
                          height: 46,
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.black87,
                              side: BorderSide(color: Colors.grey.shade300),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text("Back to Notifications",
                                style:
                                    TextStyle(fontWeight: FontWeight.w600)),
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

  static Widget _kv(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.end),
            ),
          ],
        ),
      );
}

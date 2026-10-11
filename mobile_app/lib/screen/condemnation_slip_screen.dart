import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Detail screen for post-mortem / condemnation slips.
///
/// Designed to look like the official government document.
/// All fields come from the notification's `data` JSON map or the requests DB.
/// Once the customer views/receives this slip, the operation is concluded.
class CondemnationSlipScreen extends StatefulWidget {
  final Map<String, dynamic> data;

  const CondemnationSlipScreen({super.key, required this.data});

  @override
  State<CondemnationSlipScreen> createState() => _CondemnationSlipScreenState();
}

class _CondemnationSlipScreenState extends State<CondemnationSlipScreen> {
  late Map<String, dynamic> _data;
  bool _isConcluding = false;

  @override
  void initState() {
    super.initState();
    _data = Map<String, dynamic>.from(widget.data);
    _markCondemnationReceivedAndFetchDetails();
  }

  Future<void> _markCondemnationReceivedAndFetchDetails() async {
    final reqId = _data['request_id'];
    if (reqId == null) return;

    try {
      final supabase = Supabase.instance.client;
      // When the customer opens the condemnation slip, record receipt and conclude operation
      await supabase.from('requests').update({
        'status': 'condemned',
      }).eq('id', reqId);

      await supabase.from('slaughter_inspection').update({
        'process_stage': 'Operation Concluded',
      }).eq('request_id', reqId);

      // Fetch additional fields if missing
      final reqRow = await supabase
          .from('requests')
          .select('*, slaughter_inspection(*)')
          .eq('id', reqId)
          .maybeSingle();

      if (reqRow != null && mounted) {
        setState(() {
          if (_data['customer_name'] == null || _data['customer_name'].toString().isEmpty) {
            _data['customer_name'] = reqRow['customer_name'] ?? '';
          }
          if (_data['livestock_type'] == null || _data['livestock_type'].toString().isEmpty) {
            _data['livestock_type'] = reqRow['livestock_type'] ?? '';
          }
          if (_data['animal_count'] == null) {
            _data['animal_count'] = reqRow['animal_count'] ?? 1;
          }
          final inspList = reqRow['slaughter_inspection'];
          Map<String, dynamic>? insp;
          if (inspList is List && inspList.isNotEmpty) {
            insp = inspList.first as Map<String, dynamic>;
          } else if (inspList is Map) {
            insp = inspList as Map<String, dynamic>;
          }
          if (insp != null) {
            if (_data['inspector_name'] == null || _data['inspector_name'].toString().isEmpty) {
              _data['inspector_name'] = insp['inspector_name'] ?? '';
            }
            if (_data['condemnation_reason'] == null || _data['condemnation_reason'].toString().isEmpty) {
              _data['condemnation_reason'] = insp['condemnation_reason'] ?? '';
            }
            if (_data['carcass_weight'] == null) {
              _data['carcass_weight'] = insp['carcass_weight'];
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error marking condemnation slip as received: $e');
    }
  }

  Future<void> _concludeOperation() async {
    setState(() => _isConcluding = true);
    final reqId = _data['request_id'];
    if (reqId != null) {
      try {
        await Supabase.instance.client.from('requests').update({
          'status': 'condemned',
        }).eq('id', reqId);

        await Supabase.instance.client.from('slaughter_inspection').update({
          'process_stage': 'Operation Concluded',
        }).eq('request_id', reqId);
      } catch (e) {
        debugPrint('Error updating request to concluded: $e');
      }
    }

    if (mounted) {
      setState(() => _isConcluding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Condemnation slip received. Slaughter operation concluded.'),
          backgroundColor: Color(0xFFC0392B),
        ),
      );
      Navigator.pop(context, true);
    }
  }

  String _val(String key, [String fallback = '']) =>
      (_data[key] ?? fallback).toString();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade200,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: const Text('Condemnation Slip', style: TextStyle(color: Colors.black, fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Container(
          // Paper-like styling
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── HEADER WITH LOGOS ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left Logo (Dept of Agriculture)
                  Image.asset('assets/images/logo1.png', width: 45, height: 45,
                    errorBuilder: (context, error, stackTrace) => _fallbackLogo(Icons.account_balance),
                  ),
                  const Expanded(
                    child: Column(
                      children: [
                        Text("Republic of the Philippines", style: TextStyle(fontSize: 10)),
                        Text("Province of Albay", style: TextStyle(fontSize: 10)),
                        Text("CITY OF TABACO", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  // Right Logo (City of Tabaco)
                  Image.asset('assets/images/logo2.png', width: 45, height: 45,
                    errorBuilder: (context, error, stackTrace) => _fallbackLogo(Icons.location_city),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // ── ESTABLISHMENT INFO ──
              _buildFormRow("Name of Establishment:", "Tabaco City Slaughterhouse"),
              Row(
                children: [
                  Expanded(child: _buildFormRow("City:", "Tabaco City")),
                  const SizedBox(width: 12),
                  Expanded(child: _buildFormRow("Province:", "Albay")),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _buildFormRow("Date:", _val('date', DateTime.now().toString().split(' ')[0]))),
                  const SizedBox(width: 12),
                  Expanded(child: _buildFormRow("Time:", "")),
                ],
              ),
              const SizedBox(height: 24),
              
              // ── TITLE ──
              const Center(
                child: Text(
                  "CONDEMNATION SLIP",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ),
              const SizedBox(height: 12),
              
              // ── PARAGRAPH ──
              const Text(
                "Pursuant to Republic Act No. 7394, otherwise known as the Consumer Act of the Philippines under Article 10 and 17; and Republic Act 9296 \"The Meat Inspection Code of the Philippines\" and the Department of Agriculture Administrative Order No. 7, Rules, and Regulations of RA 9296 series of 2005; and NMIS Administrative Order No. 6 the following meat/meat products/processed meat is hereby condemned.",
                style: TextStyle(fontSize: 9, height: 1.5, fontWeight: FontWeight.w500),
                textAlign: TextAlign.justify,
              ),
              const SizedBox(height: 16),
              
              // ── TABLE ──
              Table(
                border: TableBorder.all(color: Colors.black, width: 0.5),
                columnWidths: const {
                  0: FlexColumnWidth(1.2),
                  1: FlexColumnWidth(1.0),
                  2: FlexColumnWidth(1.2),
                },
                children: [
                  const TableRow(
                    children: [
                      Padding(
                        padding: EdgeInsets.all(6.0),
                        child: Text("FOOD ANIMAL/MEAT/MEAT PRODUCTS/PROCESS MEAT", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                      ),
                      Padding(
                        padding: EdgeInsets.all(6.0),
                        child: Text("QUANTITY/WEIGHT", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                      ),
                      Padding(
                        padding: EdgeInsets.all(6.0),
                        child: Text("CAUSE OF CONDEMNATION", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                      ),
                    ],
                  ),
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(6.0),
                        child: Text(_val('livestock_type', 'Livestock'), style: const TextStyle(fontSize: 9), textAlign: TextAlign.center),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(6.0),
                        child: Text(
                          "${_val('animal_count', '1')} head(s)${_val('carcass_weight').isNotEmpty ? '\n${_val('carcass_weight')} kg' : ''}",
                          style: const TextStyle(fontSize: 9),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(6.0),
                        child: Text(_val('condemnation_reason', 'Failed Post-Mortem Inspection'), style: const TextStyle(fontSize: 9), textAlign: TextAlign.center),
                      ),
                    ],
                  ),
                  const TableRow(children: [SizedBox(height: 20), SizedBox(height: 20), SizedBox(height: 20)]),
                  const TableRow(children: [SizedBox(height: 20), SizedBox(height: 20), SizedBox(height: 20)]),
                ],
              ),
              const SizedBox(height: 24),
              
              // ── SIGNATURES ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text("Condemned by:", style: TextStyle(fontSize: 9)),
                        const SizedBox(height: 24),
                        _buildSignatureLine(_val('inspector_name', '')),
                        const Text("Veterinarian/Meat Control Officer/Meat Inspector", style: TextStyle(fontSize: 7), textAlign: TextAlign.center),
                        const Text("(Signature Over Printed Name)", style: TextStyle(fontSize: 7), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text("Conforme:", style: TextStyle(fontSize: 9)),
                        const SizedBox(height: 24),
                        _buildSignatureLine(_val('customer_name', '')),
                        const Text("Name of Owner/Representative", style: TextStyle(fontSize: 7), textAlign: TextAlign.center),
                        const Text("(Signature Over Printed Name)", style: TextStyle(fontSize: 7), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text("Disposed by:", style: TextStyle(fontSize: 9)),
                        const SizedBox(height: 24),
                        _buildSignatureLine(""),
                        const Text("Veterinarian/Meat Control Officer/Meat Inspector", style: TextStyle(fontSize: 7), textAlign: TextAlign.center),
                        const Text("(Signature Over Printed Name)", style: TextStyle(fontSize: 7), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text("Witness:", style: TextStyle(fontSize: 9)),
                        const SizedBox(height: 24),
                        _buildSignatureLine(""),
                        const Text("(Signature Over Printed Name)", style: TextStyle(fontSize: 7), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Action Button
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: _isConcluding ? null : _concludeOperation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC0392B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    elevation: 1,
                  ),
                  icon: _isConcluding
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text(
                    "Acknowledge & Conclude Operation",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackLogo(IconData icon) {
    return Container(
      width: 45,
      height: 45,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade400, width: 0.5),
      ),
      child: Icon(icon, size: 24, color: Colors.grey.shade400),
    );
  }

  Widget _buildFormRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 9)),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(bottom: 2),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.black, width: 0.5)),
              ),
              child: Text(value, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignatureLine(String name) {
    return Column(
      children: [
        Text(name, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        Container(height: 0.5, color: Colors.black, width: double.infinity, margin: const EdgeInsets.only(top: 2, bottom: 2)),
      ],
    );
  }
}

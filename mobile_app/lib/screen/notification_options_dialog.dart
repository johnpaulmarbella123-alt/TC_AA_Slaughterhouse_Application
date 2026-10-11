import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Dialog shown when the user taps "View Options" on
/// `anti_mortem_failed` or `operation_failed` notifications.
///
/// For **anti_mortem_failed**: Shows a full-screen modal dialog matching the
/// mockup design with "Take Livestock Back" and "Confine in Slaughterhouse"
/// options.
///
/// For **operation_failed**: Shows the existing bottom-sheet with reschedule
/// and contact options.
class NotificationOptionsDialog {
  static void show({
    required BuildContext context,
    required String notifType,
    required Map<String, dynamic> data,
    required String title,
    required VoidCallback onReschedule,
  }) {
    final tLower = title.toLowerCase();
    final isDelay = tLower.contains('delay') ||
        data['is_delayed'] == true ||
        (notifType == 'operation_failed' &&
            data['reason'] != null &&
            data['reason'].toString().isNotEmpty);

    if (notifType == 'anti_mortem_failed') {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => _AntiMortemDialog(
          data: data,
          title: title,
          onDone: () {
            Navigator.pop(ctx);
          },
        ),
      );
    } else if (isDelay) {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => _DelayedOperationDialog(
          data: data,
          title: title,
          onDone: () {
            Navigator.pop(ctx);
          },
        ),
      );
    } else {
      // operation_failed / health_issue — keep existing bottom-sheet
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _OperationFailedSheet(
          data: data,
          title: title,
          onReschedule: () {
            Navigator.pop(ctx);
            onReschedule();
          },
        ),
      );
    }
  }
}

// ══════════════════════════════════════════════════════════════
//  ANTE-MORTEM FAILED DIALOG  (matches the UI mockup)
// ══════════════════════════════════════════════════════════════
class _AntiMortemDialog extends StatefulWidget {
  final Map<String, dynamic> data;
  final String title;
  final VoidCallback onDone;

  const _AntiMortemDialog({
    required this.data,
    required this.title,
    required this.onDone,
  });

  @override
  State<_AntiMortemDialog> createState() => _AntiMortemDialogState();
}

class _AntiMortemDialogState extends State<_AntiMortemDialog> {
  bool _isSubmitting = false;

  String _val(String key, [String fallback = 'N/A']) =>
      (widget.data[key] ?? fallback).toString();

  Future<void> _submitChoice(String choice) async {
    setState(() => _isSubmitting = true);
    try {
      final supabase = Supabase.instance.client;
      final requestId = widget.data['request_id'];

      if (requestId != null) {
        await supabase.from('requests').update({
          'anti_mortem_response': choice,
          'anti_mortem_response_at': DateTime.now().toIso8601String(),
        }).eq('id', requestId);
      }

      if (mounted) {
        widget.onDone();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              choice == 'confine'
                  ? 'Your livestock will be confined. You\'ll be notified of the new schedule.'
                  : 'Pickup requested. The admin will approve your pickup time.',
            ),
            backgroundColor: const Color(0xFF2D6A4F),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final livestockType = _val('livestock_type', 'Livestock');
    final vetFindings = _val('veterinary_findings',
        'Animal shows signs of illness. Not suitable for processing per NMIS standards.');
    final inspector = _val('inspector_name', 'Veterinary Inspector');

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── HEADER ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ante-Mortem Inspection Failed',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A202C),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'What would you like to do?',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 16, color: Colors.grey),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── RED HEALTH INSPECTION CARD ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFCEAEA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE8B4B4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Badge header
                    Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(
                            color: Color(0xFFC0392B),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.warning_amber_rounded,
                              size: 14, color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Health Inspection Failed',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFC0392B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$livestockType failed the ante-mortem inspection',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF8B3A3A)),
                    ),
                    const SizedBox(height: 12),

                    // Veterinary findings
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Veterinarian\'s Findings:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6B2020),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            vetFindings,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6B2020),
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Inspector: $inspector',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF8B5E5E),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── INFO BANNER ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF9E6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE8D78A)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Color(0xFF8B7A2B)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your livestock did not pass the ante-mortem inspection. Please choose one of the following options:',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B5E1A),
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── CHOOSE AN OPTION LABEL ──
              const Text(
                'Choose an option:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF4A5568),
                ),
              ),
              const SizedBox(height: 10),

              // ── OPTION 1: TAKE LIVESTOCK BACK ──
              _OptionTile(
                icon: Icons.undo_rounded,
                iconBg: const Color(0xFFFFF3E5),
                iconColor: const Color(0xFFD4820A),
                title: 'Take Livestock Back',
                subtitle: 'Take your livestock home. No processing charge will be applied.',
                isSubmitting: _isSubmitting,
                onTap: () => _submitChoice('take_back'),
              ),
              const SizedBox(height: 10),

              // ── OPTION 2: CONFINE IN SLAUGHTERHOUSE ──
              _OptionTile(
                icon: Icons.local_hospital_rounded,
                iconBg: const Color(0xFFE6F1FB),
                iconColor: const Color(0xFF185FA5),
                title: 'Confine in Slaughterhouse',
                subtitle: 'Leave livestock in facility for quarantine and monitoring.',
                isSubmitting: _isSubmitting,
                onTap: () => _submitChoice('confine'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final Color iconBg, iconColor;
  final String title, subtitle;
  final bool isSubmitting;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.isSubmitting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isSubmitting ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 10, color: Colors.grey, height: 1.3)),
                ],
              ),
            ),
            isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.chevron_right,
                    color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  DELAYED OPERATION DIALOG  (Technical Error / Penalty Fee)
// ══════════════════════════════════════════════════════════════
class _DelayedOperationDialog extends StatefulWidget {
  final Map<String, dynamic> data;
  final String title;
  final VoidCallback onDone;

  const _DelayedOperationDialog({
    required this.data,
    required this.title,
    required this.onDone,
  });

  @override
  State<_DelayedOperationDialog> createState() => _DelayedOperationDialogState();
}

class _DelayedOperationDialogState extends State<_DelayedOperationDialog> {
  bool _isSubmitting = false;
  String? _existingResponse;

  String _val(String key, [String fallback = 'N/A']) =>
      (widget.data[key] ?? fallback).toString();

  @override
  void initState() {
    super.initState();
    _loadExistingResponse();
  }

  Future<void> _loadExistingResponse() async {
    final requestId = widget.data['request_id'];
    if (requestId != null) {
      try {
        final supabase = Supabase.instance.client;
        final res = await supabase
            .from('requests')
            .select('anti_mortem_response')
            .eq('id', requestId)
            .maybeSingle();
        if (res != null && res['anti_mortem_response'] != null) {
          if (mounted) {
            setState(() {
              _existingResponse = res['anti_mortem_response']?.toString();
            });
          }
        }
      } catch (e) {
        debugPrint('Error loading existing response: $e');
      }
    }
  }

  Future<void> _submitChoice(String choice) async {
    setState(() => _isSubmitting = true);
    try {
      final supabase = Supabase.instance.client;
      final requestId = widget.data['request_id'];

      if (requestId != null) {
        await supabase.from('requests').update({
          'anti_mortem_response': choice,
          'anti_mortem_response_at': DateTime.now().toIso8601String(),
        }).eq('id', requestId);
      }

      if (mounted) {
        setState(() {
          _existingResponse = choice;
          _isSubmitting = false;
        });
        widget.onDone();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              choice == 'accept_penalty'
                  ? 'Penalty fee of ₱500.00 accepted. Livestock remains in facility.'
                  : 'Take-back requested. The admin will schedule your pickup time.',
            ),
            backgroundColor: const Color(0xFF2D6A4F),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final livestockType = _val('livestock_type', 'Livestock');
    final reason = _val('reason', 'Technical issue encountered during facility slaughtering process.');

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── HEADER ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Slaughter Operation Delayed',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A202C),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Technical error encountered',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 16, color: Colors.grey),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── RED / ORANGE DELAY CARD ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFCEAEA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE8B4B4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(
                            color: Color(0xFFC0392B),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.warning_amber_rounded,
                              size: 14, color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Operation Delayed',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFC0392B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$livestockType slaughter operation was delayed due to a technical error.',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF8B3A3A)),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Reason for Delay:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6B2020),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            reason,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6B2020),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── PENALTY FEE NOTICE CARD ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF9E6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE8D78A)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.receipt_long, size: 16, color: Color(0xFF8B7A2B)),
                        SizedBox(width: 8),
                        Text(
                          'Legal Finality / Penalty Fee: ₱500.00',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF6B5E1A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'If you keep your livestock in the facility for resumed slaughter, a legal finality fee of ₱500.00 will be charged. Alternatively, you may retrieve your livestock with no fee.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6B5E1A),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── CURRENT RESPONSE STATUS OR CHOICES ──
              if (_existingResponse != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _existingResponse == 'accept_penalty'
                        ? const Color(0xFFE4F8F0)
                        : const Color(0xFFFFF3E5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _existingResponse == 'accept_penalty'
                          ? const Color(0xFF1A8C62).withValues(alpha: 0.3)
                          : const Color(0xFFD4820A).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _existingResponse == 'accept_penalty'
                            ? Icons.check_circle
                            : Icons.undo_rounded,
                        color: _existingResponse == 'accept_penalty'
                            ? const Color(0xFF1A8C62)
                            : const Color(0xFFD4820A),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _existingResponse == 'accept_penalty'
                                  ? 'You Accepted the Penalty Fee'
                                  : 'You Requested Take Back',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _existingResponse == 'accept_penalty'
                                    ? const Color(0xFF0A3D2E)
                                    : const Color(0xFF854F0B),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _existingResponse == 'accept_penalty'
                                  ? 'Your livestock remains in the facility. Slaughter will be scheduled.'
                                  : 'Administration will schedule your livestock pickup time.',
                              style: TextStyle(
                                fontSize: 10,
                                color: _existingResponse == 'accept_penalty'
                                    ? const Color(0xFF0A3D2E)
                                    : const Color(0xFF854F0B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: () => setState(() => _existingResponse = null),
                    child: const Text('Change Response', style: TextStyle(fontSize: 12, color: Color(0xFF185FA5))),
                  ),
                ),
              ] else ...[
                const Text(
                  'Please respond to proceed:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4A5568),
                  ),
                ),
                const SizedBox(height: 10),

                // ── OPTION 1: ACCEPT PENALTY FEE ──
                _OptionTile(
                  icon: Icons.check_circle_outline,
                  iconBg: const Color(0xFFE4F8F0),
                  iconColor: const Color(0xFF1A8C62),
                  title: 'Accept Penalty Fee (₱500.00)',
                  subtitle: 'Keep livestock in facility for processing. ₱500.00 will be added to your payment.',
                  isSubmitting: _isSubmitting,
                  onTap: () => _submitChoice('accept_penalty'),
                ),
                const SizedBox(height: 10),

                // ── OPTION 2: TAKE LIVESTOCK BACK ──
                _OptionTile(
                  icon: Icons.undo_rounded,
                  iconBg: const Color(0xFFFFF3E5),
                  iconColor: const Color(0xFFD4820A),
                  title: 'Take Livestock Back (No Fee)',
                  subtitle: 'Retrieve livestock from facility. No penalty or slaughter fee will be charged.',
                  isSubmitting: _isSubmitting,
                  onTap: () => _submitChoice('take_back'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  OPERATION FAILED SHEET  (preserved from original)
// ══════════════════════════════════════════════════════════════
class _OperationFailedSheet extends StatelessWidget {
  final Map<String, dynamic> data;
  final String title;
  final VoidCallback onReschedule;

  const _OperationFailedSheet({
    required this.data,
    required this.title,
    required this.onReschedule,
  });

  String _val(String key, [String fallback = 'N/A']) =>
      (data[key] ?? fallback).toString();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header icon + title
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Color(0xFFFCEAEA),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline,
                    color: Color(0xFFC0392B), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Operation Failed",
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(title,
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Details card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF9F9F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Details",
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _detailRow("Operation:", _val('operation', 'Slaughter')),
                _detailRow("Reason:", _val('reason')),
                _detailRow("Reference:", _val('reference_no')),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Option buttons
          _optionButton(
            icon: Icons.calendar_today,
            label: "Reschedule Request",
            subtitle: "Submit a new request with a different date",
            color: const Color(0xFF1E855A),
            onTap: onReschedule,
          ),
          const SizedBox(height: 10),
          _optionButton(
            icon: Icons.support_agent,
            label: "Contact Administrator",
            subtitle: "tabacocityslaughterhouse@gmail.com",
            color: const Color(0xFF185FA5),
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      "Contact: tabacocityslaughterhouse@gmail.com\nPhone: +63 917 123 4567"),
                  duration: Duration(seconds: 4),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            Flexible(
              child: Text(value,
                  style: const TextStyle(fontSize: 11),
                  textAlign: TextAlign.end),
            ),
          ],
        ),
      );

  Widget _optionButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style:
                          const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );
  }
}

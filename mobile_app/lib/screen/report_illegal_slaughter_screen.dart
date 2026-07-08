import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Full-screen page for reporting illegal slaughter activities.
class ReportIllegalSlaughterScreen extends StatelessWidget {
  const ReportIllegalSlaughterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          // ── HEADER ──────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 70, 16, 20),
            color: const Color(0xFFC8E6C9),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Report Illegal Slaughter",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600)),
                      SizedBox(height: 2),
                      Text(
                          "Help us maintain food safety standards by reporting illegal or unauthorized slaughtering operations.",
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF6B6B6B))),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── BODY ────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // ── WHAT TO REPORT ────────────────────────────
                  _InfoCard(
                    icon: Icons.description_outlined,
                    iconColor: const Color(0xFF1565C0),
                    title: "What to Report",
                    bgColor: const Color(0xFFE8F0FE),
                    items: const [
                      "Slaughtering without proper permits",
                      "Unsanitary slaughtering conditions",
                      "No veterinary inspection",
                      "Illegal meat trade operations",
                      "Violations of animal welfare standards",
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── YOUR PROTECTION ───────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE4F8F0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: const BoxDecoration(
                                color: Color(0xFF1E855A),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.verified_user,
                                  size: 16, color: Colors.white),
                            ),
                            const SizedBox(width: 10),
                            const Text("Your Protection",
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0A3D2E))),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "Reports can be filed anonymously. Your identity will be protected, and you will receive updates via your reference number. All reports are treated with strict confidentiality.",
                          style: TextStyle(
                              fontSize: 12, color: Color(0xFF2D6A4F)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── FILE A REPORT BUTTON ──────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => const _ReportFormSheet(),
                        );
                      },
                      icon: const Icon(Icons.warning_amber_rounded, size: 20),
                      label: const Text("File a Report",
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── EMERGENCY CONTACT ─────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.phone, size: 18, color: Color(0xFF1E855A)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Emergency Hotline",
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                              Text(
                                  "For immediate threats: Contact Tabaco City Slaughterhouse Office",
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// INFO CARD — reusable for "What to Report"
// ═══════════════════════════════════════════════════════════════════
class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Color bgColor;
  final List<String> items;

  const _InfoCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.bgColor,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: iconColor)),
            ],
          ),
          const SizedBox(height: 10),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("• ",
                        style: TextStyle(fontSize: 13, color: iconColor)),
                    Expanded(
                      child: Text(item,
                          style: TextStyle(fontSize: 12, color: iconColor)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// REPORT FORM BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════
class _ReportFormSheet extends StatefulWidget {
  const _ReportFormSheet();

  @override
  State<_ReportFormSheet> createState() => _ReportFormSheetState();
}

class _ReportFormSheetState extends State<_ReportFormSheet> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  final _locationCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _isAnonymous = false;
  bool _isSubmitting = false;
  File? _evidencePhoto;
  String? _evidenceFileName;

  @override
  void dispose() {
    _locationCtrl.dispose();
    _dateCtrl.dispose();
    _descriptionCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // ── PICK DATE ──────────────────────────────────────────────
  Future<void> _pickDate() async {
    // Dismiss keyboard first to avoid layout conflicts
    FocusScope.of(context).unfocus();

    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      useRootNavigator: true, // render above the bottom sheet to avoid overlay lag
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFD32F2F),
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      _dateCtrl.text =
          "${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}";
    }
  }

  // ── PICK EVIDENCE PHOTO ────────────────────────────────────
  Future<void> _pickEvidence() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final XFile? image = await _picker.pickImage(
      source: source,
      imageQuality: 70,
    );
    if (image == null) return;

    setState(() {
      _evidencePhoto = File(image.path);
      _evidenceFileName = image.name;
    });
  }

  // ── SUBMIT REPORT ──────────────────────────────────────────
  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) return;

    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login first')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // 1. Upload photo if attached
      String? photoUrl;
      if (_evidencePhoto != null) {
        final fileName =
            "${DateTime.now().millisecondsSinceEpoch}_evidence.jpg";
        final filePath = "${user.id}/$fileName";

        await supabase.storage
            .from('report-evidence')
            .upload(filePath, _evidencePhoto!);

        photoUrl = supabase.storage
            .from('report-evidence')
            .getPublicUrl(filePath);
      }

      // 2. Convert date dd/mm/yyyy → yyyy-mm-dd
      final parts = _dateCtrl.text.split('/');
      final isoDate =
          "${parts[2]}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}";

      // 3. Insert report
      final report = await supabase
          .from('reports')
          .insert({
            'user_id': user.id,
            'location': _locationCtrl.text.trim(),
            'incident_date': isoDate,
            'description': _descriptionCtrl.text.trim(),
            'photo_url': photoUrl,
            'is_anonymous': _isAnonymous,
            'reporter_name':
                _isAnonymous ? 'Anonymous' : _nameCtrl.text.trim(),
            'contact_number':
                _isAnonymous ? null : _phoneCtrl.text.trim(),
            'status': 'pending',
          })
          .select()
          .single();

      // 4. Generate reference number
      final refNo =
          "RPT-${DateTime.now().year}-${report['id'].toString().substring(0, 8).toUpperCase()}";

      // 5. Update the report with reference number
      await supabase
          .from('reports')
          .update({'reference_no': refNo})
          .eq('id', report['id']);

      // 6. Create notification
      try {
        await supabase.from('notifications').insert({
          'user_id': user.id,
          'title': 'Report filed successfully',
          'message':
              'Your illegal slaughter report has been submitted.\nRef: $refNo',
          'is_read': false,
          'type': 'report_filed',
        });
      } catch (_) {
        // Don't block on notification failure
      }

      if (!mounted) return;

      // 7. Show success dialog
      Navigator.pop(context); // close bottom sheet
      _showSuccessDialog(context, refNo);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error submitting report: $e'),
            backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSuccessDialog(BuildContext ctx, String refNo) {
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Color(0xFFFFEBEE),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle,
                  color: Color(0xFFD32F2F), size: 32),
            ),
            const SizedBox(height: 14),
            const Text('Report Submitted!',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'Your report has been filed and will be investigated.\n\nReference: $refNo',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            const Text(
              'Save this reference number for tracking.',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E855A)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dCtx); // close dialog
              Navigator.pop(ctx); // back to requests
            },
            child: const Text('Done',
                style: TextStyle(
                    color: Color(0xFF0A3D2E), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title row
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFD32F2F), size: 22),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text("File Illegal Slaughter Report",
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Info banner
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  "Please provide as much detail as possible. All fields are important for proper investigation.",
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 16),

              // ── LOCATION ────────────────────────────────────
              _label("Location of Incident", required: true),
              const SizedBox(height: 6),
              TextFormField(
                controller: _locationCtrl,
                decoration: _inputDeco(
                  "Exact address or landmark",
                  prefixIcon: Icons.location_on_outlined,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),

              // ── DATE ────────────────────────────────────────
              _label("Date of Incident", required: true),
              const SizedBox(height: 6),
              TextFormField(
                controller: _dateCtrl,
                readOnly: true,
                onTap: _pickDate,
                decoration: _inputDeco(
                  "dd/mm/yyyy",
                  prefixIcon: Icons.calendar_today,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),

              // ── DESCRIPTION ─────────────────────────────────
              _label("Description of Violation", required: true),
              const SizedBox(height: 6),
              TextFormField(
                controller: _descriptionCtrl,
                maxLines: 3,
                decoration: _inputDeco(
                  "Describe what you observed, including specific violations, number of animals, conditions, etc.",
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),

              // ── PHOTO EVIDENCE (OPTIONAL) ───────────────────
              _label("Photo Evidence", required: false),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _pickEvidence,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: _evidencePhoto != null
                      ? Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.file(_evidencePhoto!,
                                  width: 48, height: 48, fit: BoxFit.cover),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _evidenceFileName ?? 'evidence.jpg',
                                    style: const TextStyle(fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const Text("Tap to change",
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close,
                                  size: 16, color: Colors.grey),
                              onPressed: () => setState(() {
                                _evidencePhoto = null;
                                _evidenceFileName = null;
                              }),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Icon(Icons.camera_alt,
                                size: 20, color: Colors.grey.shade400),
                            const SizedBox(width: 10),
                            const Text(
                              "Attach photo evidence (optional)",
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),

              // ── ANONYMOUS CHECKBOX ──────────────────────────
              Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: _isAnonymous,
                      onChanged: (v) =>
                          setState(() => _isAnonymous = v ?? false),
                      activeColor: const Color(0xFF1E855A),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text("Submit anonymously",
                      style: TextStyle(fontSize: 13)),
                ],
              ),
              const SizedBox(height: 14),

              // ── NAME ────────────────────────────────────────
              _label("Your Name", required: !_isAnonymous),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameCtrl,
                enabled: !_isAnonymous,
                decoration: _inputDeco(
                  "Full name",
                  fillColor: _isAnonymous
                      ? Colors.grey.shade200
                      : Colors.grey.shade50,
                ),
                validator: (v) {
                  if (_isAnonymous) return null;
                  return (v == null || v.trim().isEmpty)
                      ? 'Required'
                      : null;
                },
              ),
              const SizedBox(height: 14),

              // ── CONTACT NUMBER ──────────────────────────────
              _label("Contact Number", required: !_isAnonymous),
              const SizedBox(height: 6),
              TextFormField(
                controller: _phoneCtrl,
                enabled: !_isAnonymous,
                keyboardType: TextInputType.phone,
                decoration: _inputDeco(
                  "+63 XXX XXX XXXX",
                  fillColor: _isAnonymous
                      ? Colors.grey.shade200
                      : Colors.grey.shade50,
                ),
                validator: (v) {
                  if (_isAnonymous) return null;
                  return (v == null || v.trim().isEmpty)
                      ? 'Required'
                      : null;
                },
              ),
              const SizedBox(height: 14),

              // ── WARNING NOTE ────────────────────────────────
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE8C77B)),
                ),
                child: RichText(
                  text: const TextSpan(
                    style: TextStyle(fontSize: 11, color: Color(0xFF854F0B)),
                    children: [
                      TextSpan(
                          text: "Note: ",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD32F2F))),
                      TextSpan(
                          text:
                              "False reporting is a serious offense and may result in legal action. Please ensure all information provided is accurate and truthful."),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── BUTTONS ─────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black87,
                        side: BorderSide(color: Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text("Cancel"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSubmitting ? null : _submitReport,
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send, size: 16),
                      label: const Text("Submit Report",
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ── HELPERS ─────────────────────────────────────────────────
  Widget _label(String text, {required bool required}) {
    return RichText(
      text: TextSpan(
        text: text,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black87),
        children: [
          if (required)
            const TextSpan(
                text: " *", style: TextStyle(color: Color(0xFFD32F2F))),
        ],
      ),
    );
  }

  InputDecoration _inputDeco(String hint,
      {IconData? prefixIcon, Color? fillColor}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
      filled: true,
      fillColor: fillColor ?? Colors.grey.shade50,
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, size: 18, color: Colors.grey)
          : null,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFD32F2F)),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFD32F2F)),
      ),
    );
  }
}

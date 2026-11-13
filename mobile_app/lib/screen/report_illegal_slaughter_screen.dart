import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/text_capitalization_formatters.dart';

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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── YOUR PROTECTION BANNER ─────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE4F8F0),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Whistleblower Protection (R.A. 10173)",
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0A3D2E))),
                              SizedBox(height: 3),
                              Text(
                                "Reports can be filed anonymously. Your identity is strictly encrypted and protected. All reports are first reviewed by the abattoir administrator.",
                                style: TextStyle(
                                    fontSize: 11, color: Color(0xFF2D6A4F), height: 1.35),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── FILE GENERAL REPORT BUTTON ────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 48,
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
                      label: const Text("File a General Report",
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── SECTION: 4 MAJOR VIOLATIONS ───────────────
                  const Text(
                    "Violation Guide (What to Look For)",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Tap any category below to inspect statutory violations and report directly:",
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 12),

                  // Card 1: Dog & Cat Meat Trade
                  _ExpandableViolationCard(
                    title: "1. The Dog and Cat Meat Trade",
                    lawReference: "Anti-Rabies Act (RA 9482) & Animal Welfare Act (RA 8485)",
                    icon: Icons.pets_outlined,
                    accentColor: const Color(0xFFB91C1C),
                    bgColor: const Color(0xFFFEF2F2),
                    whatToLookFor:
                        "Holding pens with multiple dogs or cats, transport in cramped wire cages, or clandestine slaughter for meat.",
                    whyIllegal:
                        "The Anti-Rabies Act (RA 9482) and Animal Welfare Act (RA 8485) strictly ban the killing, trading, and selling of dogs and cats for human consumption.",
                    whoToReportTo:
                        "Philippine National Police (PNP) for immediate rescue/arrest and Animal Welfare NGOs (like PAWS or AKF).",
                    onReport: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const _ReportFormSheet(
                          initialCategory: "The Dog and Cat Meat Trade",
                        ),
                      );
                    },
                  ),

                  // Card 2: Hot Meat Operations
                  _ExpandableViolationCard(
                    title: "2. 'Hot Meat' Operations (Mane-mane)",
                    lawReference: "Meat Inspection Code of the Philippines (RA 9296 / RA 10536)",
                    icon: Icons.restaurant_outlined,
                    accentColor: const Color(0xFFC2410C),
                    bgColor: const Color(0xFFFFF7ED),
                    whatToLookFor:
                        "Slaughtering livestock (pigs, cows, goats) in backyards, hidden warehouses, or abandoned areas instead of official facilities, usually late at night or early morning.",
                    whyIllegal:
                        "All meat intended for public sale must undergo official ante/post-mortem examination. Uninspected 'hot meat' poses massive public health risks (African Swine Fever, Anthrax, bacterial contamination).",
                    whoToReportTo:
                        "Tabaco City Slaughterhouse / City Veterinary Office (CVO) & National Meat Inspection Service (NMIS).",
                    onReport: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const _ReportFormSheet(
                          initialCategory: '"Hot Meat" Operations (Clandestine Slaughter)',
                        ),
                      );
                    },
                  ),

                  // Card 3: Prohibited Livestock (Carabao / Horse)
                  _ExpandableViolationCard(
                    title: "3. Slaughter of Prohibited Livestock",
                    lawReference: "Executive Order 626-A & Bureau of Animal Industry (BAI) Rules",
                    icon: Icons.agriculture_outlined,
                    accentColor: const Color(0xFF4338CA),
                    bgColor: const Color(0xFFEEF2FF),
                    whatToLookFor:
                        "The slaughter of healthy, working carabaos (water buffaloes) or horses for meat without specialized municipal permits.",
                    whyIllegal:
                        "EO 626-A protects carabaos to ensure they are preserved for agricultural work. Carabaos can generally only be slaughtered if old, infertile, or critically injured with strict BAI clearance. Commercial horse slaughter is barred under welfare standards.",
                    whoToReportTo:
                        "National Meat Inspection Service (NMIS) and the Bureau of Animal Industry (BAI).",
                    onReport: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const _ReportFormSheet(
                          initialCategory: "Slaughter of Prohibited Livestock (Carabao/Horse)",
                        ),
                      );
                    },
                  ),

                  // Card 4: Severe Cruelty & Torture
                  _ExpandableViolationCard(
                    title: "4. Severe Cruelty & Torture During Slaughter",
                    lawReference: "The Animal Welfare Act of 1998 (RA 8485 / RA 10631)",
                    icon: Icons.warning_rounded,
                    accentColor: const Color(0xFF991B1B),
                    bgColor: const Color(0xFFFEF2F2),
                    whatToLookFor:
                        "Methods that cause prolonged pain, such as bludgeoning, burning animals alive, bleeding them out without proper stunning, or slaughtering pregnant livestock.",
                    whyIllegal:
                        "The Animal Welfare Act mandates humane handling and slaughter methods. Only approved, painless stunning methods are allowed in accredited slaughterhouses.",
                    whoToReportTo:
                        "Philippine National Police (PNP) and Bureau of Animal Industry (BAI).",
                    onReport: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const _ReportFormSheet(
                          initialCategory: "Severe Animal Cruelty & Torture During Slaughter",
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 18),

                  // ── DIRECT AUTHORITY ESCALATION DIRECTORY ────
                  const _AuthorityHotlinesCard(),
                  const SizedBox(height: 24),
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
// EXPANDABLE VIOLATION CARD
// ═══════════════════════════════════════════════════════════════════
class _ExpandableViolationCard extends StatefulWidget {
  final String title;
  final String lawReference;
  final IconData icon;
  final Color accentColor;
  final Color bgColor;
  final String whatToLookFor;
  final String whyIllegal;
  final String whoToReportTo;
  final VoidCallback onReport;

  const _ExpandableViolationCard({
    required this.title,
    required this.lawReference,
    required this.icon,
    required this.accentColor,
    required this.bgColor,
    required this.whatToLookFor,
    required this.whyIllegal,
    required this.whoToReportTo,
    required this.onReport,
  });

  @override
  State<_ExpandableViolationCard> createState() => _ExpandableViolationCardState();
}

class _ExpandableViolationCardState extends State<_ExpandableViolationCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isExpanded ? widget.accentColor.withValues(alpha: 0.6) : Colors.grey.shade200,
          width: _isExpanded ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: widget.bgColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(widget.icon, color: widget.accentColor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.lawReference,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: Colors.grey.shade600,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
            if (_isExpanded) ...[
              const Divider(height: 1),
              Container(
                padding: const EdgeInsets.all(14),
                color: const Color(0xFFFAFAFA),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _detailSection(
                      label: "What to look for",
                      content: widget.whatToLookFor,
                      icon: Icons.visibility_outlined,
                      color: const Color(0xFF475569),
                    ),
                    const SizedBox(height: 10),
                    _detailSection(
                      label: "Why it's illegal",
                      content: widget.whyIllegal,
                      icon: Icons.gavel_outlined,
                      color: const Color(0xFF991B1B),
                    ),
                    const SizedBox(height: 10),
                    _detailSection(
                      label: "Who to report to",
                      content: widget.whoToReportTo,
                      icon: Icons.shield_outlined,
                      color: const Color(0xFF1E855A),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton.icon(
                        onPressed: widget.onReport,
                        icon: const Icon(Icons.campaign_rounded, size: 18),
                        label: const Text(
                          "Report This Violation",
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.accentColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailSection({
    required String label,
    required String content,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Padding(
          padding: const EdgeInsets.only(left: 19),
          child: Text(
            content,
            style: const TextStyle(
              fontSize: 11.5,
              color: Color(0xFF334155),
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// DIRECT AUTHORITY ESCALATION DIRECTORY
// ═══════════════════════════════════════════════════════════════════
class _AuthorityHotlinesCard extends StatelessWidget {
  const _AuthorityHotlinesCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.emergency_outlined, size: 20, color: Color(0xFFDC2626)),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Direct Authority Escalation Directory",
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                    Text(
                      "Contact relevant agencies directly for urgent crimes or regional jurisdiction.",
                      style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 1. PNP
          _hotlineRow(
            icon: Icons.local_police_outlined,
            iconColor: const Color(0xFF1D4ED8),
            agency: "Philippine National Police (PNP)",
            scope: "Ongoing crimes, animal torture, emergency raids, police blotter",
            actionText: "SMS: Text PNP <Msg> to 2920 • Dial Emergency",
          ),
          const Divider(height: 16),
          // 2. NMIS
          _hotlineRow(
            icon: Icons.verified_outlined,
            iconColor: const Color(0xFFD97706),
            agency: "National Meat Inspection Service (NMIS)",
            scope: "Commercial hot meat, uninspected transit (ADR Form No. 1 / RTOC)",
            actionText: "Tel: (02) 8924-7980 • Email: nmis@nmis.gov.ph",
          ),
          const Divider(height: 16),
          // 3. Tabaco CVO / Slaughterhouse
          _hotlineRow(
            icon: Icons.location_city_outlined,
            iconColor: const Color(0xFF059669),
            agency: "Tabaco City Veterinary Office & Abattoir",
            scope: "Slaughterhouse receiving desk & local abattoir administration",
            actionText: "Visit Slaughterhouse Office • Open 24/7 Receiving",
          ),
        ],
      ),
    );
  }

  Widget _hotlineRow({
    required IconData icon,
    required Color iconColor,
    required String agency,
    required String scope,
    required String actionText,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(agency, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              const SizedBox(height: 1),
              Text(scope, style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    actionText,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF000000),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// REPORT FORM BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════
class _ReportFormSheet extends StatefulWidget {
  final String? initialCategory;
  const _ReportFormSheet({this.initialCategory});

  @override
  State<_ReportFormSheet> createState() => _ReportFormSheetState();
}

class _ReportFormSheetState extends State<_ReportFormSheet> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  static const List<String> _violationCategories = [
    'The Dog and Cat Meat Trade',
    '"Hot Meat" Operations (Clandestine Slaughter)',
    'Slaughter of Prohibited Livestock (Carabao/Horse)',
    'Severe Animal Cruelty & Torture During Slaughter',
    'General / Other Illegal Slaughter Violation',
  ];
  late String _selectedCategory;

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
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory != null &&
            _violationCategories.contains(widget.initialCategory)
        ? widget.initialCategory!
        : _violationCategories.first;
  }

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

      final fullDescription = '[Category: $_selectedCategory] ${_descriptionCtrl.text.trim()}';

      // 3. Insert report
      final report = await supabase
          .from('reports')
          .insert({
            'user_id': _isAnonymous ? null : user.id,
            'location': _locationCtrl.text.trim(),
            'incident_date': isoDate,
            'description': fullDescription,
            'photo_url': photoUrl,
            'is_anonymous': _isAnonymous,
            'reporter_name':
                _isAnonymous ? 'Anonymous' : _nameCtrl.text.trim(),
            'contact_number':
                _isAnonymous ? null : _phoneCtrl.text.trim(),
            'status': 'Submitted',
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

      // 6. Create notifications
      final isSevere = _selectedCategory.contains('Cruelty') || _selectedCategory.contains('Dog and Cat');
      final reportPayload = {
        'reference_no': refNo,
        'report_id': report['id'],
        'location': _locationCtrl.text.trim(),
        'incident_date': isoDate,
        'violation_category': _selectedCategory,
        'description': fullDescription,
        'photo_url': photoUrl,
        'is_anonymous': _isAnonymous,
        'reporter_name':
            _isAnonymous ? 'Anonymous' : _nameCtrl.text.trim(),
        'contact_number':
            _isAnonymous ? null : _phoneCtrl.text.trim(),
        'status': 'Pending Review',
        'priority': isSevere ? 'Severe' : 'Moderate',
        'severity_level': isSevere ? 'Severe' : 'Moderate',
        'created_at': DateTime.now().toIso8601String(),
      };

      try {
        // A. Insert admin alert notification so admin panel immediately detects the new report
        await supabase.from('notifications').insert({
          'user_id': null, // broadcast to all abattoir staff / admins
          'title': '🚨 New Illegal Slaughter Tip: $_selectedCategory ($refNo)',
          'message':
              'New citizen report filed for $_selectedCategory.\nRef: $refNo\nLocation: ${_locationCtrl.text.trim()}',
          'is_read': false,
          'type': 'admin_illegal_report',
          'reference_no': refNo,
          'data': {
            ...reportPayload,
            if (_isAnonymous) 'user_id': null,
          },
        });

        // B. If NOT anonymous, send explicit customer submission confirmation to customer's personal notifications feed
        if (!_isAnonymous) {
          await supabase.from('notifications').insert({
            'user_id': user.id,
            'title': '✅ Report Submission Confirmed ($refNo)',
            'message':
                'Your illegal slaughter report regarding "$_selectedCategory" has been safely submitted to Tabaco City Slaughterhouse & City Veterinary Office.\n\nReference: $refNo\nStatus: Pending Review\nLocation: ${_locationCtrl.text.trim()}\n\nOur veterinary inspectors are conducting initial triage. You will receive updates as the investigation progresses.',
            'is_read': false,
            'type': 'report_filed',
            'reference_no': refNo,
            'data': reportPayload,
          });
        }
      } catch (e) {
        debugPrint('Notification insert error: $e');
      }

      if (!mounted) return;

      // 7. Show success confirmation dialog
      Navigator.pop(context); // close bottom sheet
      _showSuccessDialog(context, refNo, _isAnonymous);
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

  void _showSuccessDialog(BuildContext ctx, String refNo, bool isAnonymous) {
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        contentPadding: const EdgeInsets.fromLTRB(18, 22, 18, 16),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: isAnonymous ? const Color(0xFFEFF6FF) : const Color(0xFFF0FDF4),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isAnonymous ? const Color(0xFFBFDBFE) : const Color(0xFFBBF7D0),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  isAnonymous ? Icons.shield_outlined : Icons.check_circle_outline,
                  color: isAnonymous ? const Color(0xFF2563EB) : const Color(0xFF16A34A),
                  size: 30,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isAnonymous ? 'Protected Anonymous Submission' : 'Report Submitted Successfully!',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isAnonymous
                    ? 'Your identity has been fully protected. The abattoir inspection team has received your report for triage.'
                    : 'Your report has been received by the Tabaco City Slaughterhouse & City Veterinary Office.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), height: 1.35),
              ),
              const SizedBox(height: 14),

              // Reference Number Container with 1-tap Copy (Auto-scaling to prevent any overflow)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    const Text(
                      'TRACKING REFERENCE NUMBER',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 5),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            refNo,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: refNo));
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text('Copied reference number: $refNo'),
                                  duration: const Duration(seconds: 2),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFBFDBFE)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.copy, size: 12, color: Color(0xFF2563EB)),
                                  SizedBox(width: 4),
                                  Text(
                                    'Copy',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF2563EB),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Dynamic Advisory Note
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isAnonymous ? const Color(0xFFFFFBEB) : const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isAnonymous ? const Color(0xFFFDE68A) : const Color(0xFFBBF7D0),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isAnonymous ? Icons.lock_outline : Icons.notifications_active_outlined,
                      size: 15,
                      color: isAnonymous ? const Color(0xFFD97706) : const Color(0xFF16A34A),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isAnonymous
                            ? 'Privacy Note: To ensure total confidentiality, no notifications are linked to your user account. Keep your reference code if you wish to follow up via hotlines.'
                            : 'Notification Active: A submission confirmation has been added to your Notifications tab. You will receive updates as the investigation progresses.',
                        style: TextStyle(
                          fontSize: 11,
                          color: isAnonymous ? const Color(0xFF92400E) : const Color(0xFF166534),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () {
                Navigator.pop(dCtx); // close dialog
                Navigator.pop(ctx); // back to previous screen
              },
              child: const Text('Done', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
            ),
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

              // ── VIOLATION CATEGORY ──────────────────────────
              _label("Violation Category", required: true),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCategory,
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down, color: Color(0xFFD32F2F)),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                    items: _violationCategories.map((cat) {
                      return DropdownMenuItem<String>(
                        value: cat,
                        child: Text(cat, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedCategory = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // ── LOCATION ────────────────────────────────────
              _label("Location of Incident", required: true),
              const SizedBox(height: 6),
              TextFormField(
                controller: _locationCtrl,
                textCapitalization: TextCapitalization.words,
                inputFormatters: const [WordsCapitalizationFormatter()],
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
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: const [SentencesCapitalizationFormatter()],
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
                      onChanged: (v) {
                        setState(() {
                          _isAnonymous = v ?? false;
                          if (_isAnonymous) {
                            _nameCtrl.clear();
                            _phoneCtrl.clear();
                          }
                        });
                      },
                      activeColor: const Color(0xFF1E855A),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text("Submit anonymously",
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                ],
              ),
              const SizedBox(height: 14),

              if (_isAnonymous) ...[
                // Anonymity Protection Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFA5D6A7)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.security, size: 22, color: Color(0xFF1E855A)),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Identity Protected (Confidential)",
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0A3D2E)),
                            ),
                            SizedBox(height: 3),
                            Text(
                              "Your name and contact number will NOT be collected or stored. Slaughterhouse admins will only see 'Anonymous Whistleblower'.",
                              style: TextStyle(
                                  fontSize: 11, color: Color(0xFF2D6A4F), height: 1.3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ] else ...[
                // ── NAME ────────────────────────────────────────
                _label("Your Name", required: true),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: const [WordsCapitalizationFormatter()],
                  decoration: _inputDeco(
                    "Full name",
                    prefixIcon: Icons.person_outline,
                  ),
                  validator: (v) {
                    if (_isAnonymous) return null;
                    return (v == null || v.trim().isEmpty) ? 'Required' : null;
                  },
                ),
                const SizedBox(height: 14),

                // ── CONTACT NUMBER ──────────────────────────────
                _label("Contact Number", required: true),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: _inputDeco(
                    "+63 XXX XXX XXXX",
                    prefixIcon: Icons.phone_outlined,
                  ),
                  validator: (v) {
                    if (_isAnonymous) return null;
                    return (v == null || v.trim().isEmpty) ? 'Required' : null;
                  },
                ),
                const SizedBox(height: 14),
              ],

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

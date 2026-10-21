import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'report_illegal_slaughter_screen.dart';
import '../services/document_verifier.dart';

class RequestsContent extends StatefulWidget {
  const RequestsContent({super.key});

  @override
  State<RequestsContent> createState() => _RequestsContentState();
}

const List<Map<String, String>> albayMunicipalities = [
  {"code": "050517000", "name": "City of Tabaco"},
  {"code": "050501000", "name": "Bacacay"},
  {"code": "050502000", "name": "Camalig"},
  {"code": "050503000", "name": "Daraga"},
  {"code": "050504000", "name": "Guinobatan"},
  {"code": "050505000", "name": "Jovellar"},
  {"code": "050506000", "name": "City of Legazpi"},
  {"code": "050507000", "name": "Libon"},
  {"code": "050508000", "name": "City of Ligao"},
  {"code": "050509000", "name": "Malilipot"},
  {"code": "050510000", "name": "Malinao"},
  {"code": "050511000", "name": "Manito"},
  {"code": "050512000", "name": "Oas"},
  {"code": "050513000", "name": "Pio Duran"},
  {"code": "050514000", "name": "Polangui"},
  {"code": "050515000", "name": "Rapu-Rapu"},
  {"code": "050516000", "name": "Santo Domingo"},
  {"code": "050518000", "name": "Tiwi"},
];

const List<String> tabacoBarangays = [
  "Agnas", "Bacolod", "Bangkilingan", "Bantayan", "Baranghawon", "Basagan", "Basud (Pob.)",
  "Bogñabong", "Bombon (Pob.)", "Bonot", "San Isidro", "Buang", "Buhian", "Cabagñan",
  "Cobo", "Comon", "Cormidal", "Divino Rostro (Pob.)", "Fatima", "Guinobat", "Hacienda",
  "Magapo", "Mariroc", "Matagbac", "Oras", "Oson", "Panal", "Pawa", "Pinagbobong",
  "Quinale Cabasan (Pob.)", "Quinastillojan", "Rawis", "Sagurong", "Salvacion",
  "San Antonio", "San Carlos", "San Juan (Pob.)", "San Lorenzo", "San Ramon",
  "San Roque", "San Vicente", "Santo Cristo (Pob.)", "Sua-Igot", "Tabiguian",
  "Tagas", "Tayhi (Pob.)", "Visita"
];

class _RequestsContentState extends State<RequestsContent> {
  final supabase = Supabase.instance.client;

  // moved out of top-level globals into proper state
  bool isSubmitted = false;
  bool isLoading = false;

  bool isBarangay = true; // Requests is active
  final ImagePicker picker = ImagePicker();

  // --- controllers for the fields that were not wired up before ---
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _animalCountController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _marketStallController = TextEditingController();
  final TextEditingController _marketNameController = TextEditingController();
  final TextEditingController _specialInstructionsController = TextEditingController();
  final TextEditingController _markingController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();

  String? selectedLivestock;

  List municipalities = List.from(albayMunicipalities);
  List barangays = [];

  String? selectedProvince = "Albay";
  String? selectedProvinceCode = "050500000";

  String? selectedMunicipality;
  String? selectedMunicipalityCode;

  String? selectedBarangay;

  String? barangayCertificateUrl;
  String? businessPermitUrl;
  String? ownershipUrl;
  String? vetCertificateUrl;
  String selectedDocType = "Barangay Certificate";

  @override
  void initState() {
    super.initState();
    loadMunicipalities(selectedProvinceCode!);
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _animalCountController.dispose();
    _addressController.dispose();
    _marketStallController.dispose();
    _marketNameController.dispose();
    _specialInstructionsController.dispose();
    _markingController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  // ---------------- SUBMIT ----------------

  Future<void> submitRequest() async {
    // basic validation so you don't send empty junk to Supabase
    if (_customerNameController.text.trim().isEmpty ||
        selectedLivestock == null ||
        _animalCountController.text.trim().isEmpty ||
        selectedProvince == null ||
        selectedMunicipality == null ||
        selectedBarangay == null ||
        _addressController.text.trim().isEmpty ||
        _dateController.text.trim().isEmpty ||
        _markingController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in all required fields (including Livestock Marking)")),
      );
      return;
    }

    if (ownershipUrl == null ||
        (isBarangay && barangayCertificateUrl == null) ||
        (!isBarangay && businessPermitUrl == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please upload all required documents")),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please login first")),
        );
        setState(() => isLoading = false);
        return;
      }

      // Check if marking is already used by an active request
      final markingInput = _markingController.text.trim();
      final conflicting = await supabase
          .from('requests')
          .select('id, marking, status')
          .ilike('marking', markingInput)
          .not('status', 'in', '("completed","cancelled","rejected","released")')
          .limit(1);

      if (conflicting.isNotEmpty) {
        setState(() => isLoading = false);
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 48),
            title: const Text("Marking Already In Use", style: TextStyle(fontWeight: FontWeight.bold)),
            content: Text(
              "The livestock marking '$markingInput' is currently assigned to an active request.\n\n"
              "To prevent animal mix-ups during slaughter and holding, please choose a unique tag or identifier (e.g. $markingInput-1).",
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E855A)),
                child: const Text("Change Marking"),
              ),
            ],
          ),
        );
        return;
      }

      // convert dd/mm/yyyy -> yyyy-mm-dd for a Postgres `date` column
      final parts = _dateController.text.split('/');
      final preferredDateIso =
          "${parts[2]}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}";

      // 1. Insert request with all the fields your schema actually has
      final request = await supabase
          .from('requests')
          .insert({
            'user_id': user.id,
            'request_type': isBarangay ? 'barangay' : 'market',
            'customer_name': _customerNameController.text.trim(),
            'livestock_type': selectedLivestock,
            'animal_count': int.tryParse(_animalCountController.text.trim()) ?? 0,
            'province': selectedProvince,
            'municipality': selectedMunicipality,
            'barangay': selectedBarangay,
            'address': _addressController.text.trim(),
            'market_stall_number':
                isBarangay ? null : _marketStallController.text.trim(),
            'market_name':
                isBarangay ? null : _marketNameController.text.trim(),
            'preferred_date': preferredDateIso,
            'marking': _markingController.text.trim(),
            'special_instruction': _specialInstructionsController.text.trim(),
            'barangay_certificate': barangayCertificateUrl,
            'business_permit': businessPermitUrl,
            'proof_of_ownership': ownershipUrl,
            'vet_certificate': vetCertificateUrl,
            'status': 'pending',
          })
          .select()
          .single();

      // 2. Reference number, e.g. MI-2026-001, built from the new row's id
      final refNo = "MI-${DateTime.now().year}-${request['id'].toString().padLeft(3, '0')}";

      // 3. Insert notification — using the REAL columns from your schema
      //    (title, message, is_read, type) — not 'body' / 'reference_no'
      try {
        await supabase.from('notifications').insert({
          'user_id': user.id,
          'title': 'Request submitted successfully',
          'message':
              'Your slaughter request is being processed. wait for approval\nRef: $refNo',
          'is_read': false,
          'type': 'request_submitted',
        });
        debugPrint('NOTIF INSERT: Success for $refNo');
      } catch (notifError) {
        debugPrint('NOTIF INSERT FAILED: $notifError');
        // Don't block request success — just log the error
      }

      setState(() {
        isSubmitted = true;
        isLoading = false;
      });

      if (!mounted) return;
      _showSuccessBanner(refNo);
      _resetForm();
    } catch (e) {
      setState(() => isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error submitting request: $e")),
      );
    }
  }

  void _resetForm() {
    _customerNameController.clear();
    _animalCountController.clear();
    _addressController.clear();
    _marketStallController.clear();
    _marketNameController.clear();
    _specialInstructionsController.clear();
    _markingController.clear();
    _dateController.clear();
    setState(() {
      selectedLivestock = null;
      selectedProvince = "Albay";
      selectedProvinceCode = "050500000";
      municipalities = List.from(albayMunicipalities);
      selectedMunicipality = null;
      selectedBarangay = null;
      barangayCertificateUrl = null;
      businessPermitUrl = null;
      ownershipUrl = null;
      vetCertificateUrl = null;
    });
  }

  // Success popup styled like the "Request submitted successfully" card
  void _showSuccessBanner(String refNo) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle, color: Color(0xFF1E855A), size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Request submitted successfully",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Your slaughter request is being processed. wait for approved.\nRef: $refNo",
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  "Just now",
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(entry);
    Future.delayed(const Duration(seconds: 4), () {
      entry.remove();
    });
  }

  // ---------------- DOCUMENT PICKER ----------------

  Future<void> _pickDocument(String type) async {
    // 1. Choose source: Camera, Gallery, or Device Files
    final selection = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                "Upload $type",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                child: Text(
                  "Please provide a scanned copy or clear photo of the official document.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFF1E855A)),
                title: const Text("Take Photo"),
                subtitle: const Text("Capture the physical certificate directly"),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Color(0xFF1E855A)),
                title: const Text("Select from Gallery"),
                subtitle: const Text("Choose image from your photo album"),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.folder_open, color: Color(0xFF1E855A)),
                title: const Text("Choose Files"),
                subtitle: const Text("Select image or scanned document file"),
                onTap: () => Navigator.pop(context, 'files'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (selection == null) return;

    File? selectedFile;

    try {
      if (selection == 'camera') {
        final XFile? image = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 70,
        );
        if (image != null) selectedFile = File(image.path);
      } else if (selection == 'gallery') {
        final XFile? image = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 70,
        );
        if (image != null) selectedFile = File(image.path);
      } else if (selection == 'files') {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png'],
        );
        if (result != null && result.files.single.path != null) {
          selectedFile = File(result.files.single.path!);
        }
      }

      if (selectedFile == null) return;
      if (!mounted) return;

      // 2. File size check
      final int fileSize = await selectedFile.length();
      if (fileSize < 10240) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Selected file is too small. Please provide a clear scanned certificate."),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // 3. Display Analyzing Dialog
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            content: Row(
              children: const [
                CircularProgressIndicator(color: Color(0xFF1E855A)),
                SizedBox(width: 20),
                Expanded(
                  child: Text(
                    "Verifying certificate authenticity...",
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // 4. Perform On-Device OCR & Document Verification
      final verification = await DocumentVerifier.verifyCertificate(
        imageFile: selectedFile,
        documentType: type,
      );

      // Dismiss analyzing dialog
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (!mounted) return;

      // 5. If rejected, display clear alert & block upload
      if (!verification.isValid) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 52),
            title: const Text(
              "Certificate Not Detected",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  verification.message,
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Icon(Icons.info_outline, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Photos of people, random objects, animals, or illegible scans cannot be accepted. Please ensure the official header, certificate title, and seal are visible.",
                          style: TextStyle(fontSize: 12, color: Colors.red, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Try Again", style: TextStyle(color: Color(0xFF1E855A))),
              ),
            ],
          ),
        );
        return;
      }

      // 6. If verified, show preview confirmation before final upload
      final bool? proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.verified, color: Color(0xFF1E855A), size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Legitimate Certificate",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    selectedFile!,
                    height: 190,
                    width: double.infinity,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Target: $type",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Detected Official Markers:",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: verification.detectedKeywords.take(6).map((k) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF81C784)),
                      ),
                      child: Text(
                        k,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Click 'Upload' to attach this verified document to your request.",
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E855A),
                foregroundColor: Colors.white,
              ),
              child: const Text("Upload Document"),
            ),
          ],
        ),
      );

      if (proceed != true) return;

      final user = supabase.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please login first")),
        );
        return;
      }

      // 7. Upload to Supabase Storage
      final fileName = "${DateTime.now().millisecondsSinceEpoch}.jpg";
      final filePath = "${user.id}/$fileName";

      await supabase.storage.from('request-documents').upload(filePath, selectedFile);
      final url = supabase.storage.from('request-documents').getPublicUrl(filePath);

      setState(() {
        if (type == "Barangay Certificate") {
          barangayCertificateUrl = url;
        } else if (type == "Business Permit") {
          businessPermitUrl = url;
        } else if (type == "Proof of Ownership") {
          ownershipUrl = url;
        } else if (type == "Health certificate from veterinarian(optional)") {
          vetCertificateUrl = url;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✓ $type verified and uploaded successfully"),
            backgroundColor: const Color(0xFF1E855A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Upload Error: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  Future<void> loadMunicipalities(String provinceCode) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://psgc.gitlab.io/api/provinces/$provinceCode/cities-municipalities/',
        ),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final list = jsonDecode(response.body);
        if (mounted && list is List && list.isNotEmpty) {
          setState(() {
            municipalities = list;
          });
        }
      }
    } catch (e) {
      debugPrint('Notice: using pre-bundled Albay municipalities: $e');
      if (mounted && municipalities.isEmpty) {
        setState(() {
          municipalities = List.from(albayMunicipalities);
        });
      }
    }
  }

  Future<void> loadBarangays(String municipalityCode) async {
    // If Tabaco City or name matches, use instant preloaded barangays
    if (municipalityCode == "050517000" || selectedMunicipality == "City of Tabaco") {
      setState(() {
        barangays = tabacoBarangays.map((name) => {'name': name}).toList();
        selectedBarangay = null;
      });
      return;
    }

    try {
      final response = await http.get(
        Uri.parse(
          'https://psgc.gitlab.io/api/cities-municipalities/$municipalityCode/barangays/',
        ),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final list = jsonDecode(response.body);
        if (mounted && list is List) {
          setState(() {
            barangays = list;
            selectedBarangay = null;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading barangays: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Page Header & Title
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                decoration: const BoxDecoration(
                  color: Color(0xFFC8E6C9), // Light green background
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      "Create New Requests",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "Submit your processing request with required documents.",
                      style: TextStyle(fontSize: 11, color: Colors.black87),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Center(
                child: Text(
                  "Create New Request",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Center(
                child: Text(
                  "Fill details below to quickly submit a service request.",
                  style: TextStyle(
                    fontSize: 12,
                    color: Color.fromARGB(255, 41, 40, 40),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 2. Main Form Container & State Toggle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Custom Toggle
                      Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => isBarangay = true),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isBarangay ? const Color(0xFF1E855A) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Center(
                                    child: Text(
                                      "Barangay",
                                      style: TextStyle(
                                        color: isBarangay ? Colors.white : Colors.black54,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => isBarangay = false),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: !isBarangay ? const Color(0xFF1E855A) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Center(
                                    child: Text(
                                      "Market",
                                      style: TextStyle(
                                        color: !isBarangay ? Colors.white : Colors.black54,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 3. Form Fields
                      _buildTextField(
                        "Customer Name",
                        "Enter customer name",
                        controller: _customerNameController,
                      ),

                      const SizedBox(height: 16),

                      _buildDropdownField(
                        "Livestock Type",
                        ["Pig/Hog", "Cow/Cattle", "Goat", "Sheep", "Carabao", "Poultry"],
                      ),

                      const SizedBox(height: 16),

                      _buildTextField(
                        "Animal Count",
                        "0",
                        isNumber: true,
                        controller: _animalCountController,
                      ),

                      const SizedBox(height: 16),

                      // PROVINCE (Fixed to Albay)
                      TextFormField(
                        initialValue: "Albay",
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: "Province",
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          prefixIcon: const Icon(
                            Icons.location_on_outlined,
                            color: Color(0xFF2D6A4F),
                          ),
                          suffixIcon: const Padding(
                            padding: EdgeInsets.only(right: 12),
                            child: Tooltip(
                              message: "Fixed to Albay (Local facility jurisdiction)",
                              child: Icon(Icons.lock_outline, size: 18, color: Colors.grey),
                            ),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // MUNICIPALITY
                      DropdownButtonFormField<String>(
                        value: selectedMunicipality,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: "Municipality",
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        items: municipalities.map<DropdownMenuItem<String>>((city) {
                          return DropdownMenuItem<String>(
                            value: city['name'],
                            child: Text(
                              city['name'],
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          final selected = municipalities.firstWhere(
                            (m) => m['name'] == value,
                          );

                          setState(() {
                            selectedMunicipality = value;
                            selectedMunicipalityCode = selected['code'];
                          });

                          loadBarangays(selectedMunicipalityCode!);
                        },
                      ),

                      const SizedBox(height: 16),

                      // BARANGAY
                      DropdownButtonFormField<String>(
                        value: selectedBarangay,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: "Barangay",
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        items: barangays.map<DropdownMenuItem<String>>((b) {
                          return DropdownMenuItem<String>(
                            value: b['name'],
                            child: Text(
                              b['name'],
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedBarangay = value;
                          });
                        },
                      ),

                      const SizedBox(height: 16),

                      _buildTextField(
                        "Complete Address",
                        "House No. / Street",
                        controller: _addressController,
                      ),

                      const SizedBox(height: 16),

                      if (!isBarangay) ...[
                        _buildTextField(
                          "Market Stall Number",
                          "Enter stall number",
                          controller: _marketStallController,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          "Market Selection",
                          "Enter Market Name",
                          controller: _marketNameController,
                        ),
                      ],
                      const SizedBox(height: 32),

                      // 4. Preferred Schedule Section
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Preferred Schedule",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildDateField("Preferred Date"),
                      const SizedBox(height: 16),
                      _buildTextField(
                        "Special Instructions (Optional)",
                        "Any specific requests or requirements...",
                        maxLines: 3,
                        controller: _specialInstructionsController,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        "Marking for livestock *",
                        "Enter unique marking (e.g., MK, MK-1)",
                        controller: _markingController,
                      ),
                      const SizedBox(height: 32),

                      // 5. Required Documents Section
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Required Documents",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildUploadBox(),
                      const SizedBox(height: 16),
                      _buildRequiredDocsList(),
                      const SizedBox(height: 32),

                      // 6. Report Illegal Slaughter
                      _buildReportButton(),
                      const SizedBox(height: 32),

                      // 7. Footer Buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isLoading
                                  ? null
                                  : () {
                                      _resetForm();
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey.shade200,
                                foregroundColor: Colors.black87,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text("Cancel"),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isLoading ? null : submitRequest,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E855A),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: isLoading
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text("Submit Requests"),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildTextField(
    String label,
    String hint, {
    bool isNumber = false,
    int maxLines = 1,
    TextEditingController? controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField(String label, List<String> options) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: selectedLivestock,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          hint: const Text("Select type", style: TextStyle(color: Colors.grey, fontSize: 14)),
          items: options.map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value, style: const TextStyle(fontSize: 14)),
            );
          }).toList(),
          onChanged: (newValue) {
            setState(() {
              selectedLivestock = newValue;
            });
          },
        ),
      ],
    );
  }

  Widget _buildDateField(String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        TextField(
          controller: _dateController,
          readOnly: true,
          onTap: () async {
            DateTime? pickedDate = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2101),
              builder: (context, child) {
                return Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: Color(0xFF1E855A),
                      onPrimary: Colors.white,
                      onSurface: Colors.black,
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (pickedDate != null) {
              String formattedDate = "${pickedDate.day.toString().padLeft(2, '0')}/${pickedDate.month.toString().padLeft(2, '0')}/${pickedDate.year}";
              setState(() {
                _dateController.text = formattedDate;
              });
            }
          },
          decoration: InputDecoration(
            hintText: "dd/mm/yyyy",
            hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
            filled: true,
            fillColor: Colors.grey.shade100,
            suffixIcon: const Icon(Icons.calendar_today, size: 18, color: Colors.grey),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildUploadBox() {
    final docOptions = isBarangay
        ? ["Barangay Certificate", "Proof of Ownership", "Health certificate from veterinarian(optional)"]
        : ["Business Permit", "Proof of Ownership", "Health certificate from veterinarian(optional)"];

    if (!docOptions.contains(selectedDocType)) {
      selectedDocType = docOptions.first;
    }

    return CustomPaint(
      painter: DashRectPainter(color: Colors.grey.shade400, strokeWidth: 1, gap: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(Icons.cloud_upload_outlined, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              "Upload proof of ownership, barangay certificate and other required documents",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedDocType,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: "Uploading as",
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: docOptions
                  .map((d) => DropdownMenuItem(
                        value: d,
                        child: Text(d, style: const TextStyle(fontSize: 13)),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() => selectedDocType = value!);
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                _pickDocument(selectedDocType);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                elevation: 0,
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text("Choose files"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequiredDocsList() {
    List<String> docs = isBarangay
        ? ["Barangay Certificate", "Proof of Ownership", "Health certificate from veterinarian(optional)"]
        : ["Business Permit", "Proof of Ownership", "Health certificate from veterinarian(optional)"];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: docs.map((doc) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: Color(0xFF1976D2)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  doc,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF1976D2)),
                ),
              ),
              if ((doc == "Barangay Certificate" && barangayCertificateUrl != null) ||
                  (doc == "Business Permit" && businessPermitUrl != null) ||
                  (doc == "Proof of Ownership" && ownershipUrl != null) ||
                  (doc == "Health certificate from veterinarian(optional)" && vetCertificateUrl != null))
                const Icon(Icons.check_circle, color: Colors.green, size: 18),
            ],
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildReportButton() {
    return OutlinedButton.icon(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ReportIllegalSlaughterScreen(),
          ),
        );
      },
      icon: const Icon(Icons.report_problem_outlined, color: Colors.red),
      label: const Text(
        "Report or Complaint Illegal Slaughter",
        style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.red),
        padding: const EdgeInsets.symmetric(vertical: 16),
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

// --- HELPERS ---

class DashRectPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;

  DashRectPainter({required this.color, required this.strokeWidth, required this.gap});

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    Path path = Path();
    path.addRRect(RRect.fromLTRBR(0, 0, size.width, size.height, const Radius.circular(10)));

    double dashWidth = gap;
    double dashSpace = gap;
    double distance = 0.0;

    for (var i = 0; i < path.computeMetrics().length; i++) {
      var metric = path.computeMetrics().elementAt(i);
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dashWidth),
          paint,
        );
        distance += dashWidth + dashSpace;
      }
      distance = 0.0;
    }
  }

  @override
  bool shouldRepaint(DashRectPainter oldDelegate) => false;
}
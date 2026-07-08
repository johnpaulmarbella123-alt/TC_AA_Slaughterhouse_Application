import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'report_illegal_slaughter_screen.dart';

class RequestsContent extends StatefulWidget {
  const RequestsContent({super.key});

  @override
  State<RequestsContent> createState() => _RequestsContentState();
}

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

  List provinces = [];
  List municipalities = [];
  List barangays = [];

  String? selectedProvince;
  String? selectedProvinceCode;

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
    loadProvinces();
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
        _dateController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in all required fields")),
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
      selectedProvince = null;
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
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text("Take Photo"),
                onTap: () {
                  Navigator.pop(context, ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text("Choose from Gallery"),
                onTap: () {
                  Navigator.pop(context, ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );

    if (source == null) return;

    try {
      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 70,
      );

      if (image == null) return;

      final user = supabase.auth.currentUser;

      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please login first"),
          ),
        );
        return;
      }

      final file = File(image.path);

      final fileName = "${DateTime.now().millisecondsSinceEpoch}.jpg";

      final filePath = "${user.id}/$fileName";

      await supabase.storage.from('request-documents').upload(filePath, file);

      final url = supabase.storage.from('request-documents').getPublicUrl(filePath);

      setState(() {
        if (type == "Barangay Certificate") {
          barangayCertificateUrl = url;
        }

        if (type == "Business Permit") {
          businessPermitUrl = url;
        }

        if (type == "Proof of Ownership") {
          ownershipUrl = url;
        }

        if (type == "Health certificate from veterinarian(optional)") {
          vetCertificateUrl = url;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("$type uploaded successfully"),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Upload Error: $e"),
        ),
      );
    }
  }

  Future<void> loadProvinces() async {
    final response = await http.get(
      Uri.parse('https://psgc.gitlab.io/api/provinces'),
    );

    if (response.statusCode == 200) {
      setState(() {
        provinces = jsonDecode(response.body);
      });
    }
  }

  Future<void> loadMunicipalities(String provinceCode) async {
    final response = await http.get(
      Uri.parse(
        'https://psgc.gitlab.io/api/provinces/$provinceCode/cities-municipalities/',
      ),
    );

    if (response.statusCode == 200) {
      setState(() {
        municipalities = jsonDecode(response.body);
        barangays.clear();
        selectedMunicipality = null;
        selectedBarangay = null;
      });
    }
  }

  Future<void> loadBarangays(String municipalityCode) async {
    final response = await http.get(
      Uri.parse(
        'https://psgc.gitlab.io/api/cities-municipalities/$municipalityCode/barangays/',
      ),
    );

    if (response.statusCode == 200) {
      setState(() {
        barangays = jsonDecode(response.body);
        selectedBarangay = null;
      });
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
                        ["Pig/Hog", "Cow/Cattle", "Goat", "Sheep", "Carabao"],
                      ),

                      const SizedBox(height: 16),

                      _buildTextField(
                        "Animal Count",
                        "0",
                        isNumber: true,
                        controller: _animalCountController,
                      ),

                      const SizedBox(height: 16),

                      // PROVINCE
                      DropdownButtonFormField<String>(
                        value: selectedProvince,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: "Province",
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        items: provinces.map<DropdownMenuItem<String>>((province) {
                          return DropdownMenuItem<String>(
                            value: province['name'],
                            child: Text(
                              province['name'],
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          final selected = provinces.firstWhere(
                            (p) => p['name'] == value,
                          );

                          setState(() {
                            selectedProvince = value;
                            selectedProvinceCode = selected['code'];
                          });

                          loadMunicipalities(selectedProvinceCode!);
                        },
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
                        "Special Instructions",
                        "Any specific requests or requirements...",
                        maxLines: 3,
                        controller: _specialInstructionsController,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        "Marking for livestock",
                        "Enter markings if any",
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
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class RequestsContent extends StatefulWidget {
  const RequestsContent({super.key});

  @override
  State<RequestsContent> createState() => _RequestsContentState();
}

class _RequestsContentState extends State<RequestsContent> {
  final supabase = Supabase.instance.client;
  final ImagePicker picker = ImagePicker();

  bool isBarangay = true;

  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _countController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  String? selectedLivestock;

  String? barangayCertificateUrl;
  String? businessPermitUrl;
  String? ownershipUrl;
  String? vetCertificateUrl;

  // =========================
  // PICK + UPLOAD FILE
  // =========================
  Future<void> _pickDocument(String type) async {
    final XFile? file = await picker.pickImage(source: ImageSource.camera);

    if (file == null) return;

    File imageFile = File(file.path);

    final fileName =
        "${DateTime.now().millisecondsSinceEpoch}_${file.name}";

    final path = "requests/$fileName";

    try {
      await supabase.storage
          .from('request-documents')
          .upload(path, imageFile);

      final url = supabase.storage
          .from('request-documents')
          .getPublicUrl(path);

      setState(() {
        if (type == "Barangay Certificate") {
          barangayCertificateUrl = url;
        } else if (type == "Business Permit") {
          businessPermitUrl = url;
        } else if (type == "Proof of Ownership") {
          ownershipUrl = url;
        } else if (type == "Veterinary Certificate") {
          vetCertificateUrl = url;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$type uploaded successfully")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Upload failed: $e")),
      );
    }
  }

  // =========================
  // SUBMIT REQUEST
  // =========================
  Future<void> _submitRequest() async {
    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please login first")),
        );
        return;
      }

      // VALIDATION
      if (isBarangay) {
        if (barangayCertificateUrl == null || ownershipUrl == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Missing Barangay Certificate or Ownership"),
            ),
          );
          return;
        }
      } else {
        if (businessPermitUrl == null || ownershipUrl == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Missing Business Permit or Ownership"),
            ),
          );
          return;
        }
      }

      // INSERT REQUEST
      await supabase.from('requests').insert({
        'user_id': user.id,
        'request_type': isBarangay ? 'Barangay' : 'Market',
        'livestock_type': selectedLivestock,
        'animal_count': _countController.text,
        'preferred_date': _dateController.text,
        'address': _addressController.text,

        'barangay_certificate': barangayCertificateUrl,
        'business_permit': businessPermitUrl,
        'proof_of_ownership': ownershipUrl,
        'vet_certificate': vetCertificateUrl,

        'status': 'Pending',
      });

      // NOTIFICATION
      await supabase.from('notifications').insert({
        'user_id': user.id,
        'title': 'Request Submitted',
        'message': 'Your slaughter request is now pending review.',
      });

      _showSuccessDialog();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Success"),
        content: const Text(
          "Your request has been submitted successfully.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 20),

              ToggleButtons(
                isSelected: [isBarangay, !isBarangay],
                onPressed: (index) {
                  setState(() {
                    isBarangay = index == 0;
                  });
                },
                children: const [
                  Padding(
                    padding: EdgeInsets.all(10),
                    child: Text("Barangay"),
                  ),
                  Padding(
                    padding: EdgeInsets.all(10),
                    child: Text("Market"),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              TextField(
                controller: _nameController,
                decoration:
                    const InputDecoration(labelText: "Customer Name"),
              ),

              TextField(
                controller: _countController,
                decoration:
                    const InputDecoration(labelText: "Animal Count"),
              ),

              TextField(
                controller: _addressController,
                decoration:
                    const InputDecoration(labelText: "Address"),
              ),

              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: () => _pickDocument(
                  isBarangay
                      ? "Barangay Certificate"
                      : "Business Permit",
                ),
                child: const Text("Upload Main Document"),
              ),

              ElevatedButton(
                onPressed: _submitRequest,
                child: const Text("Submit Request"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
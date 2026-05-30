import 'package:flutter/material.dart';

class RequestsContent extends StatefulWidget {
  const RequestsContent({super.key});

  @override
  State<RequestsContent> createState() => _RequestsContentState();
}

class _RequestsContentState extends State<RequestsContent> {
  bool isBarangay = true; // Requests is active

  final TextEditingController _dateController = TextEditingController();
  String? selectedLivestock;

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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                decoration: const BoxDecoration(
                  color: Color(0xFFC0EABE), // Light green background
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      "Create New Requests",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      "Submit your processing request with required documents",
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Center(
                child: Text(
                  "Create New Request",
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Center(
                child: Text(
                  "Fill details below to quickly submit a service request.",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
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
                        height: 50,
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
                                    borderRadius: BorderRadius.circular(25),
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
                                    borderRadius: BorderRadius.circular(25),
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
                      _buildTextField("Customer Name", "Enter customer name"),
                      const SizedBox(height: 16),
                      _buildDropdownField("Livestock Type", ["Pig/Hog", "Cow/Cattle", "Goat", "Sheep", "Carabao"]),
                      const SizedBox(height: 16),
                      _buildTextField("Animal Count", "0", isNumber: true),
                      const SizedBox(height: 16),
                      _buildTextField("Complete Address", "Enter complete address"),
                      const SizedBox(height: 16),

                      if (isBarangay) ...[
                        _buildTextField("Municipality", "Enter municipality"),
                        const SizedBox(height: 16),
                        _buildTextField("Barangay", "Enter barangay"),
                      ] else ...[
                        _buildTextField("Market Stall Number", "Enter stall number"),
                        const SizedBox(height: 16),
                        _buildTextField("Market Selection", "Select or enter market"),
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
                      _buildTextField("Special Instructions", "Any specific requests or requirements...", maxLines: 3),
                      const SizedBox(height: 16),
                      _buildTextField("Marking for livestock", "Enter markings if any"),
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
                              onPressed: () {},
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
                              onPressed: () {},
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E855A),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text("Submit Requests"),
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

  Widget _buildTextField(String label, String hint, {bool isNumber = false, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        TextField(
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
            filled: true,
            fillColor: Colors.grey.shade100,
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
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
    return CustomPaint(
      painter: DashRectPainter(color: Colors.grey.shade400, strokeWidth: 1, gap: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
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
            ElevatedButton(
              onPressed: () {},
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
        ? ["Barangay Certificate", "Proof of Ownership", "Health certificate from veterinarian"]
        : ["Business Permit", "Proof of Ownership", "Health certificate from veterinarian"];

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
              Text(
                doc,
                style: const TextStyle(fontSize: 13, color: Color(0xFF1976D2)),
              ),
            ],
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildReportButton() {
    return OutlinedButton.icon(
      onPressed: () {
        // Navigation to ReportSlaughterScreen
        // Navigator.push(context, MaterialPageRoute(builder: (context) => const ReportSlaughterScreen()));
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

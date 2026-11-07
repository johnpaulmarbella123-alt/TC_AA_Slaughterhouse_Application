import 'package:flutter/material.dart';

class TermsAndConditionsDialog extends StatelessWidget {
  const TermsAndConditionsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── HEADER ──
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
              decoration: const BoxDecoration(
                color: Color(0xFF1E855A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.gavel_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TERMS & CONDITIONS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'AA Slaughterhouse • Tabaco City',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),

            // ── SUBHEADER BANNER ──
            Container(
              color: const Color(0xFFF7FAFC),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: const Row(
                children: [
                  Icon(Icons.verified_user_outlined, size: 16, color: Color(0xFF1E855A)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'City Veterinary Office • In accordance with NMIS',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF4A5568), fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    'Version 1.0',
                    style: TextStyle(fontSize: 11, color: Color(0xFF718096), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),

            // ── SCROLLABLE BODY ──
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Official Title & Preamble
                    const Text(
                      'TERMS AND CONDITIONS AND USER AGREEMENT',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A202C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Operation Management Application for AA Slaughterhouse of Tabaco City\nCity Veterinary Office / Slaughterhouse Management Office, Tabaco City, Albay',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Color(0xFF4A5568),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6F9F0),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF2D6A4F).withValues(alpha: 0.3)),
                      ),
                      child: const Text(
                        'Welcome to the official Operation Management Application for the AA Slaughterhouse of Tabaco City ("System", "Application"). This digital platform is operated by the Local Government Unit (LGU) of Tabaco City in coordination with the City Veterinary Office (CVO) and in strict accordance with the National Meat Inspection Service (NMIS).\n\nBy creating an account, tapping "Sign Up", or using this Application, you ("User", "Client", "Dealer", "Farmer", or "Whistleblower") certify that you have read, understood, and unconditionally agree to be bound by the following Terms and Conditions, as well as the accompanying Data Privacy Statement.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF166534), height: 1.45),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Section 1
                    _buildSectionHeader('1. GENERAL ACCEPTANCE AND ELIGIBILITY'),
                    _buildParagraph('1.1. You must be at least eighteen (18) years of age and legally capable of entering into binding contracts under Philippine laws.'),
                    _buildParagraph('1.2. If registering on behalf of a meat dealership, cooperative, commercial farm, or corporate entity, you represent and warrant that you hold full legal authority to act on their behalf.'),
                    _buildParagraph('1.3. You agree to provide true, accurate, current, and complete personal and business credentials upon registration and to keep this information updated at all times.'),
                    const SizedBox(height: 14),

                    // Section 2
                    _buildSectionHeader('2. LIVESTOCK BOOKING AND STATUTORY PERMITS'),
                    _buildParagraph('2.1. Truthfulness of Documents: When submitting a slaughter reservation, users are required to upload legitimate statutory credentials, including but not limited to the Veterinary Health Certificate (VHC) issued by a licensed veterinarian, the Livestock Shipping Permit issued by the Bureau of Animal Industry (BAI), and Barangay Proof of Ownership/Transfer.'),
                    _buildParagraph('2.2. Penalties for Falsification: Submitting falsified, forged, altered, expired, or fraudulent animal health documents is a criminal offense punishable under the Revised Penal Code of the Philippines and Section 39 of Republic Act No. 9296 as amended by R.A. 10536. Any forged submission will result in immediate booking revocation, account suspension, and formal referral to law enforcement.'),
                    _buildParagraph('2.3. Lairage Capacity & Quotas: Submitting a booking does not guarantee unconditional immediate intake. Intake is subject to daily abattoir holding pen capacity, operational scheduling, and receiving triage validation by slaughterhouse receiving clerks.'),
                    const SizedBox(height: 14),

                    // Section 3
                    _buildSectionHeader('3. ANIMAL WELFARE AND HUMANE HANDLING'),
                    _buildParagraph('3.1. In compliance with Republic Act No. 8485 (The Animal Welfare Act of 1998) as amended by Republic Act No. 10631, users transporting livestock to the Tabaco City Slaughterhouse must practice humane transport, unloading, and holding protocols.'),
                    _buildParagraph('3.2. Cruelty, unlawful starvation, dehydration, physical beating, or neglect during livestock transit and lairage holding will result in immediate disqualification of service and report to animal welfare authorities.'),
                    const SizedBox(height: 14),

                    // Section 4
                    _buildSectionHeader('4. STATUTORY VETERINARY INSPECTION, CONDEMNATION, AND CONFISCATION'),
                    _buildParagraph('4.1. Absolute Veterinary Authority: In accordance with R.A. 9296 and R.A. 10536, all food animals delivered to the abattoir are subject to mandatory clinical ante-mortem (live animal) and post-mortem (carcass and visceral organs) examinations conducted by NMIS-accredited Veterinary Meat Inspectors (VMI) and the Meat Control Officer (MCO).'),
                    _buildParagraph('4.2. Condemnation without Liability: If an animal or any portion of its carcass or internal organs is diagnosed with a dangerous zoonotic pathology, systemic infection, or chemical/biological residue rendering it unfit for human consumption, the Meat Inspector possesses the statutory duty to issue a Condemnation Slip and immediately seize, denature, and incinerate/bury the condemned material.'),
                    _buildParagraph('4.3. The City Government of Tabaco, its slaughterhouse management, and veterinary inspectors bear zero financial or compensatory liability for legally condemned livestock or confiscated unwholesome meat.'),
                    const SizedBox(height: 14),

                    // Section 5
                    _buildSectionHeader('5. MUNICIPAL FEES, GCASH DIGITAL CHECKOUT, AND REFUNDS'),
                    _buildParagraph('5.1. Fee Schedule: All slaughter fees (including slaughterhouse service dues, ante-mortem and post-mortem inspection fees, corral holding charges, and per-kilogram carcass processing rates) are computed strictly pursuant to the validated Municipal Revenue Code and Slaughterhouse Ordinances of Tabaco City.'),
                    _buildParagraph('5.2. Payment Channels: Payments may be tendered over-the-counter in cash or digitally through the integrated PayMongo GCash checkout gateway.'),
                    _buildParagraph('5.3. Finality of Collections: Once animals undergo slaughter floor operations and official municipal receipts (OR / RCP-YYYY-XXX) are issued, payment collections are final, non-refundable, and remitted to the City Treasury of Tabaco.'),
                    const SizedBox(height: 14),

                    // Section 6
                    _buildSectionHeader('6. GATE PASS VALIDATION AND MEAT DISPATCH'),
                    _buildParagraph('6.1. Dressed meat and edible offal will only be released from the loading dock upon presentation of a validated, paid Gate Pass QR Code.'),
                    _buildParagraph('6.2. Meat handlers and transport drivers must ensure that delivery vehicles comply with hygienic meat transport requirements to preserve cold-chain and sanitary safety once meat leaves the slaughterhouse premises.'),
                    const SizedBox(height: 14),

                    // Section 7
                    _buildSectionHeader('7. ILLEGAL SLAUGHTER ("HOT MEAT") WHISTLEBLOWER DISCLOSURES'),
                    _buildParagraph('7.1. Good-Faith Civic Reporting: The application provides a civic whistleblower channel enabling citizens to report clandestine backyard slaughtering and illegal meat distribution ("karne kontrabando").'),
                    _buildParagraph('7.2. Truthfulness and Malicious Claims: Reports must be made in good faith with factual narratives, valid GPS coordinates, and honest photographic evidence. Intentionally filing malicious, fabricated, or libelous claims against innocent competitors or neighbors is strictly prohibited and subjects the sender to civil and criminal liability under the Cybercrime Prevention Act of 2012 (R.A. 10175).'),
                    const SizedBox(height: 14),

                    // Section 8
                    _buildSectionHeader('8. DATA PRIVACY AND PROTECTION (R.A. 10173)'),
                    _buildParagraph('8.1. Data Collection: The System collects personal information (name, address, mobile number, email, GPS location for reports) and official documents solely for regulatory compliance, booking execution, cashiering, and identity verification.'),
                    _buildParagraph('8.2. Data Confidentiality: All personal data is encrypted in transit (TLS 1.3) and stored securely using Supabase database infrastructure adhering to ISO/IEC 27001 standards. Data will never be sold, leased, or distributed to unauthorized third parties.'),
                    _buildParagraph('8.3. Regulatory Data Sharing: You acknowledge that statutory inspection logs, health certificates, and carcass records are submitted to the National Meat Inspection Service (NMIS) and Tabaco City LGU for official public health auditing.'),
                    const SizedBox(height: 14),

                    // Section 9
                    _buildSectionHeader('9. DISCLAIMER OF WARRANTIES AND LIMITATION OF LIABILITY'),
                    _buildParagraph('9.1. The System is provided on an "as-is" and "as-available" basis. While the proponents and slaughterhouse administration endeavor to ensure 99.5% uptime, uninterrupted availability is not warranted during unforeseen telecom outages, cloud server disruptions, or natural disasters.'),
                    _buildParagraph('9.2. Slaughterhouse administrators reserve the right to suspend or terminate accounts that breach these terms, manipulate data, or violate veterinary health laws.'),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // ── FOOTER ACTIONS ──
            const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E855A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    child: const Text(
                      'I Understand & Agree',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1E855A),
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildParagraph(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF2D3748),
          height: 1.45,
        ),
      ),
    );
  }
}


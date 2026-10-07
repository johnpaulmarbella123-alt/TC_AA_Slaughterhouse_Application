import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HowItWorksScreen extends StatelessWidget {
  const HowItWorksScreen({super.key});

  final Color primaryGreen = const Color(0xFF218358);
  final Color darkGreen = const Color(0xFF14532D);
  final Color lightGreenBg = const Color(0xFFE8F5E9);

  bool _checkIsLoggedIn() {
    try {
      return Supabase.instance.client.auth.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  void _handleMainAction(BuildContext context) {
    if (_checkIsLoggedIn()) {
      Navigator.pushNamedAndRemoveUntil(context, '/HOME', (route) => false);
    } else {
      Navigator.pushNamed(context, '/LOGIN');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
      backgroundColor: const Color(0xFFF7F9FA),
      appBar: AppBar(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "How It Works",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            letterSpacing: 0.3,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(54),
          child: Container(
            color: Colors.white,
            child: TabBar(
              labelColor: primaryGreen,
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: primaryGreen,
              indicatorWeight: 3.5,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
              tabs: const [
                Tab(
                  icon: Icon(Icons.format_list_numbered, size: 20),
                  text: "Steps",
                ),
                Tab(
                  icon: Icon(Icons.grid_view_rounded, size: 20),
                  text: "Features",
                ),
                Tab(
                  icon: Icon(Icons.help_outline_rounded, size: 20),
                  text: "FAQ",
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        children: [
          _buildStepByStepTab(),
          _buildFeaturesTab(),
          _buildFaqTab(),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          child: ElevatedButton(
            onPressed: () => _handleMainAction(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 2,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _checkIsLoggedIn() ? Icons.description_outlined : Icons.login_rounded,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  _checkIsLoggedIn() ? "Go to Requests" : "Get Started / Log In",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // TAB 1: STEP-BY-STEP PROCEDURE
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildStepByStepTab() {
    final steps = [
      {
        "step": "1",
        "title": "Create Account & Sign In",
        "description":
            "Register using your mobile number or email address. Verify your phone via OTP to keep your account safe, and complete your basic profile information.",
        "icon": Icons.person_add_alt_1_rounded,
        "tip": "Keep your phone number updated for real-time SMS notifications."
      },
      {
        "step": "2",
        "title": "Submit a Slaughter Request",
        "description":
            "Go to the 'Requests' tab. Choose your livestock type (Pig/Hog, Cattle, Carabao, Goat, or Sheep), enter the head count, slaughter date, and address / stall destination.",
        "icon": Icons.assignment_turned_in_rounded,
        "tip": "Fill in any animal markings or special instructions for easy identification."
      },
      {
        "step": "3",
        "title": "Upload Clearances & Permits",
        "description":
            "Attach clear photos of required legal certificates: Barangay Clearance, Veterinary Health Certificate, and Proof of Livestock Ownership.",
        "icon": Icons.upload_file_rounded,
        "tip": "Clear photos ensure fast approval without administrative delays."
      },
      {
        "step": "4",
        "title": "Ante-Mortem & Facility Inspection",
        "description":
            "Bring livestock to the Tabaco City Class 'AA' Slaughterhouse. Certified government meat inspectors conduct thorough health and sanitation checks.",
        "icon": Icons.health_and_safety_rounded,
        "tip": "Livestock must arrive on your scheduled date for inspection."
      },
      {
        "step": "5",
        "title": "Live Status Updates & Alerts",
        "description":
            "Track your request live in the 'Notify' tab. Receive instant status changes from 'Pending', 'In-Inspection', 'Slaughtered', to 'Ready for Pick-up'.",
        "icon": Icons.notifications_active_rounded,
        "tip": "Check for condemnation slips if any part was found unfit for consumption."
      },
      {
        "step": "6",
        "title": "Digital Payment & Meat Release",
        "description":
            "Review your itemized invoice (ante/post-mortem fees, slaughter fees, corral fees). Pay conveniently via GCash, PayMongo, or over-the-counter cash, and claim your inspected meat.",
        "icon": Icons.receipt_long_rounded,
        "tip": "Download or view your official digital e-receipt anytime in the app."
      },
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
      children: [
        // Intro Header Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [primaryGreen, darkGreen],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: primaryGreen.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_stories_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Step-by-Step Guide",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      "Simple and hassle-free guide from booking to safe meat release.",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Steps List
        ...List.generate(steps.length, (index) {
          final s = steps[index];
          final isLast = index == steps.length - 1;

          return Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Step Badge
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: primaryGreen,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: primaryGreen.withOpacity(0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    s["step"] as String,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // Card Content
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.grey.shade200,
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              s["icon"] as IconData,
                              color: primaryGreen,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s["title"] as String,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          s["description"] as String,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: lightGreenBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.lightbulb_outline,
                                size: 16,
                                color: darkGreen,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  s["tip"] as String,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: darkGreen,
                                  ),
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
        }),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // TAB 2: FEATURES & WHAT CAN BE DONE
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildFeaturesTab() {
    final features = [
      {
        "title": "Online Slaughter Booking",
        "desc":
            "Request official livestock slaughtering anytime from anywhere. Specify species, head count, stall numbers, and dates without waiting in physical queues.",
        "icon": Icons.event_note_rounded,
        "color": const Color(0xFF2E7D32),
      },
      {
        "title": "Clearance & Document Upload",
        "desc":
            "Upload Veterinary Health Certificates, Barangay Clearances, and Ownership documents straight from your camera or gallery with instant preview.",
        "icon": Icons.file_present_rounded,
        "color": const Color(0xFF1565C0),
      },
      {
        "title": "Real-time Status Tracking",
        "desc":
            "Monitor every milestone of your livestock: inspection arrival, ante-mortem pass, slaughter line, post-mortem clearance, and meat pick-up availability.",
        "icon": Icons.stream_rounded,
        "color": const Color(0xFFE65100),
      },
      {
        "title": "Instant Notifications",
        "desc":
            "Receive live notifications directly on your phone as soon as the meat inspector or admin accepts, reviews, or completes your transaction.",
        "icon": Icons.notifications_active_rounded,
        "color": const Color(0xFF6A1B9A),
      },
      {
        "title": "Online & Cash Payments",
        "desc":
            "Transparent automatic fee computation with breakdowns for slaughter fees, corrals, and inspections. Pay via GCash, PayMongo, or cash at counter.",
        "icon": Icons.account_balance_wallet_rounded,
        "color": const Color(0xFF00838F),
      },
      {
        "title": "Official Digital Receipts",
        "desc":
            "View and present official electronic receipts and condemnation slips for full legal compliance and bookkeeping.",
        "icon": Icons.receipt_rounded,
        "color": const Color(0xFF455A64),
      },
      {
        "title": "Report Illegal Slaughter",
        "desc":
            "Protect the public against unsafe meat! Report illegal backyard or unauthorized slaughtering with location details and evidence photos.",
        "icon": Icons.report_problem_rounded,
        "color": const Color(0xFFC62828),
      },
      {
        "title": "Facility Gallery & Reviews",
        "desc":
            "Inspect Tabaco City's Class 'AA' machines, hoist stations, and hygienic facilities. Share your ratings and feedback to improve city services.",
        "icon": Icons.star_rate_rounded,
        "color": const Color(0xFFF9A825),
      },
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
      children: [
        const Text(
          "What Can You Do in this App?",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "Everything you need for seamless, hygienic, and legal livestock processing.",
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        ...features.map((f) {
          final iconColor = f["color"] as Color;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    f["icon"] as IconData,
                    color: iconColor,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f["title"] as String,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        f["desc"] as String,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade700,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // TAB 3: FAQ (FREQUENTLY ASKED QUESTIONS)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _buildFaqTab() {
    final faqs = [
      {
        "q": "What livestock species can be processed?",
        "a":
            "Tabaco City 'AA' Slaughterhouse processes Hogs (Pigs), Cattle (Cows), Carabao, Goats, and Sheep according to NMIS standards."
      },
      {
        "q": "What legal documents are required before slaughter?",
        "a":
            "You need to provide:\n1. Barangay Certificate of Ownership or Transfer\n2. Veterinary Health Certificate\n3. Shipping / Movement Permit (if transported from another municipality/province)."
      },
      {
        "q": "What happens during Ante-Mortem inspection?",
        "a":
            "Certified government meat inspectors examine live animals before slaughter to ensure they are healthy, rested, disease-free, and fit for human food production."
      },
      {
        "q": "What is a Condemnation Slip?",
        "a":
            "If any organ or whole carcass is deemed unfit for consumption due to disease or contamination, a digital Condemnation Slip is issued detailing the reason and weight condemned."
      },
      {
        "q": "What payment methods are supported?",
        "a":
            "You can pay online via GCash and PayMongo e-wallets, or pay in person via over-the-counter Cash at the Slaughterhouse billing window."
      },
      {
        "q": "Why is Class 'AA' certification important?",
        "a":
            "Class 'AA' slaughterhouses meet strict national standards set by the National Meat Inspection Service (NMIS), allowing safe meat distribution across city borders."
      },
      {
        "q": "How can I report illegal slaughter?",
        "a":
            "Navigate to the 'Requests' tab and tap 'Report Illegal Slaughter' or use the citizen report button. You can upload photos and provide address details to protect our community."
      },
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
      children: [
        const Text(
          "Frequently Asked Questions",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "Quick answers to common questions about using the app and services.",
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        ...faqs.map(
          (faq) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Theme(
              data: ThemeData(dividerColor: Colors.transparent),
              child: ExpansionTile(
                iconColor: primaryGreen,
                collapsedIconColor: Colors.grey.shade600,
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                title: Text(
                  faq["q"]!,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(
                      faq["a"]!,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import '../screen/requests.dart';
import '../screen/notify.dart';
import '../screen/payment.dart';
import '../screen/profile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedTab = 0; // 0=About, 1=Gallery, 2=Review
  int _bottomNavIndex = 0; // 0=Home, 1=Requests, 2=Notify, 3=Payment, 4=Profile

  void _onBottomNavTap(int index) {
    setState(() {
      _bottomNavIndex = index;
    });
  }

  // Feature Functions as requested
  void request() {
    _onBottomNavTap(1);
  }

  void notify() {
    _onBottomNavTap(2);
  }

  void payment() {
    _onBottomNavTap(3);
  }

  void profile() {
    _onBottomNavTap(4);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── TOP NAV BAR ──────────────────────────────────────────────
            Container(
              color: const Color(0xFFC0EABE),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Logo
                  Container(
                    width: 33,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFD9D9D9),
                      image: const DecorationImage(
                        image: AssetImage(
                          'assets/images/logo1.png',
                        ),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  // Profile avatar
                  GestureDetector(
                    onTap: profile,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        image: const DecorationImage(
                          image: AssetImage(
                            'assets/images/bino.jpg',
                          ),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── SCROLLABLE BODY ──────────────────────────────────────────
            Expanded(
              child: _buildBodyContent(),
            ),

            // ── BOTTOM NAVIGATION BAR ─────────────────────────────────────
            Container(
              color: const Color(0xFFD9D9D9),
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _navItem(Icons.home, "Home", _bottomNavIndex == 0, () => _onBottomNavTap(0)),
                  _navItem(Icons.description_outlined, "Requests", _bottomNavIndex == 1, request),
                  _navItem(Icons.notifications_none, "Notify", _bottomNavIndex == 2, notify),
                  _navItem(Icons.payment_outlined, "Payment", _bottomNavIndex == 3, payment),
                  _navItem(Icons.person_outline, "Profile", _bottomNavIndex == 4, profile),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyContent() {
    switch (_bottomNavIndex) {
      case 0:
        return _buildHomeContent();
      case 1:
        return const RequestsContent();
      case 2:
        return const NotifyPage();
      case 3:
        return const PaymentContent();
      case 4:
        return const ProfileContent();
      default:
        return _buildHomeContent();
    }
  }

  Widget _buildHomeContent() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── HERO BANNER ────────────────────────────────────
          Stack(
            children: [
              SizedBox(
                height: 274,
                width: double.infinity,
                child: Image.asset(
                  'assets/images/BG.jpeg',
                  fit: BoxFit.cover,
                ),
              ),
              Container(
                height: 274,
                width: double.infinity,
                color: Colors.black.withOpacity(0.35),
              ),
              Positioned.fill(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Welcome to \nTabaco City Slaughterhouse!",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Livestock Slaughter Service",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Professional and hygienic livestock\nprocessing at your convenience",
                      style: TextStyle(color: Colors.white, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: request,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E855A),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 35, vertical: 10),
                        elevation: 4,
                      ),
                      child: const Text(
                        "Get New Requests",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── OUR FULL OPERATION MACHINE ─────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: const Text(
              "Our full Operation Machine",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 110,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                _machineCard(
                  "assets/images/pic1.jpeg",
                  "Livestock processing facility",
                ),
                const SizedBox(width: 8),
                _machineCard(
                  "assets/images/pic2.jpeg",
                  "Weighing station",
                ),
                const SizedBox(width: 8),
                _machineCard(
                  "assets/images/pic3.jpeg",
                  "Sanitizing Station",
                ),
                const SizedBox(width: 8),
                _machineCard(
                  "assets/images/pic4.jpeg",
                  "Shackeys and trolleys",
                ),
                const SizedBox(width: 8),
                _machineCard(
                  "assets/images/pic5.jpeg",
                  "Stainless steel table",
                ),
                const SizedBox(width: 8),
                _machineCard(
                  "assets/images/pic6.jpeg",
                  ""
                ),
                 const SizedBox(width: 8),
                _machineCard(
                  "assets/images/pic7.jpeg",
                  "Stainless steel sink"
                ),
                 const SizedBox(width: 8),
                _machineCard(
                  "assets/images/pic8.jpeg",
                  "Overhead conveyor rail"
                ),
                 const SizedBox(width: 8),
                _machineCard(
                  "assets/images/pic9.jpeg",
                  "Hoist station"
                ),
                 const SizedBox(width: 8),
                _machineCard(
                  "assets/images/pic10.jpeg",
                  "viscera(Inspection Table)"
                ),
                 const SizedBox(width: 8),
                _machineCard(
                  "assets/images/pic11.jpeg",
                  "Drainage"
                ),
                   const SizedBox(width: 8),
                _machineCard(
                  "assets/images/pic12.jpeg",
                  "Overhead conveyor rail system"
                ),
                   const SizedBox(width: 8),
                _machineCard(
                  "assets/images/pic13.jpeg",
                  "Utility Cart"
                ),
                   const SizedBox(width: 8),
                _machineCard(
                  "assets/images/pic14.jpeg",
                  "Scalding tanks"
                ),
                   const SizedBox(width: 8),
                _machineCard(
                  "assets/images/pic15.jpeg",
                  "Worker's lift platform"
                ),
                   const SizedBox(width: 8),
                _machineCard(
                  "assets/images/pic16.jpeg",
                  "Cummins diesel generator"
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── OUR SERVICE ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: const Text(
              "Our Service",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 100,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                _serviceCard(
                  "assets/images/pic6.jpeg",
                  "Pig/Hog",
                  "Hog Slaughter",
                ),
                _serviceCard(
                  "assets/images/pic7.jpeg",
                  "Cow",
                  "Cattle Slaughter",
                ),
                _serviceCard(
                  "assets/images/pic8.jpeg",
                  "Goat",
                  "Goat Slaughter",
                ),
                _serviceCard(
                  "assets/images/pic9.jpeg",
                  "Sheep",
                  "Sheep Slaughter",
                ),
                _serviceCard(
                  "assets/images/pic10.jpeg",
                  "Carabao",
                  "Carabao Slaughter",
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── ABOUT / GALLERY / REVIEW TABS ─────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 90),
            child: Row(
              children: [
                _tabItem("About", 0),
                const SizedBox(width: 40),
                _tabItem("Gallery", 1),
                const SizedBox(width: 40),
                _tabItem("Review", 2),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ── LOCATION & HOURS ──────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 37),
            child: Row(
              children: [
                const Icon(Icons.location_on, color: Color(0xFF008000), size: 23),
                const SizedBox(width: 4),
                const SizedBox(
                  width: 89,
                  child: Text(
                    "Zone 1  San Carlos, Tabaco City",
                    style: TextStyle(fontSize: 10),
                  ),
                ),
                const SizedBox(width: 18),
                const Icon(Icons.access_time, color: Color(0xFF008000), size: 23),
                const SizedBox(width: 4),
                const Text("Open 24 hours", style: TextStyle(fontSize: 10)),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── ABOUT CONTENT ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "It increases slaughtering capacity from 82 to 350 hogs and from 3 to 12 cattle daily. The city will hire 27 licensed butchers to ensure efficient operations. According to City Veterinarian Dr. Kim Ronan Romero, the new slaughterhouse will improve food safety and cleanliness compared to the old facility. The project has passed final inspection and the city has allocated funds for its operation and maintenance.",
              style: const TextStyle(fontSize: 11, color: Colors.black87),
            ),
          ),

          const SizedBox(height: 20),

          // ── CONTACT US ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const Text(
              "Contact Us",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(height: 10),
          _contactCard(Icons.phone, "Phone", "+63 917 123 4567"),
          const SizedBox(height: 8),
          _contactCard(Icons.email_outlined, "Email", "tabacocityslaughterhouse@gmail.com"),

          const SizedBox(height: 16),

          // ── HOW IT WORKS ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text(
                  "How it works? click ",
                  style: TextStyle(fontSize: 13),
                ),
                GestureDetector(
                  onTap: () {},
                  child: const Text(
                    "Here!",
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF008000),
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── OUR VALUES ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const Text(
              "Our Values",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _valueCard(Icons.shield, const Color(0xFF1E855A), "Safety first",
                    "Strict hygiene and safety protocols"),
                _valueCard(Icons.emoji_events, const Color(0xFFD4A017), "Excellence",
                    "Professional service every time"),
                _valueCard(Icons.people, const Color(0xFF1E855A), "Community",
                    "Supporting local farmers"),
                _valueCard(Icons.verified, const Color(0xFF1565C0), "Reliability",
                    "On-time, One day process"),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── BY THE NUMBERS ────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FAF0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Text(
                  "By The Numbers",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _numberStat("6 years", "Years\nExperience"),
                    _numberStat("10", "Happy\nCustomers"),
                    _numberStat("98%", "Satisfaction\nRate"),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── CERTIFICATE & LICENSES ────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const Text(
              "Certificate & Licenses",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FAF0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _CertItem("NMIS Certificate Facility"),
                _CertItem("FDA Registered"),
                _CertItem("Local Government Unit Permit"),
                _CertItem("Environmental Compliance Certificate"),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── OUR TEAM ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const Text(
              "Our Team",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const Text(
              "Our skilled team of veterinarians, butchers, and support staff are dedicated to providing the highest quality service. All our staff are trained in proper handling techniques and food safety standards.",
              style: TextStyle(fontSize: 11, color: Colors.black87),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _teamCard(Icons.medical_services, const Color(0xFF1E855A), "5 Veterinarians"),
                _teamCard(Icons.person, const Color(0xFF2E7D32), "12 Butchers"),
                _teamCard(Icons.people_alt, const Color(0xFFD4A017), "5 Staffs"),
              ],
            ),
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // ── HELPERS ─────────────────────────────────────────────────────────────

  Widget _machineCard(String imageUrl, String label) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(imageUrl,
              width: 150, height: 90, fit: BoxFit.cover),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }

  Widget _serviceCard(
      String imageUrl, String animal, String label) {
    return Container(
      width: 80,
      margin: const EdgeInsets.only(right: 8),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
            child: Stack(
              children: [
                Image.asset(imageUrl,
                    width: 80, height: 75, fit: BoxFit.cover),
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    color: Colors.black38,
                    child: Text(animal,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(fontSize: 9),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _tabItem(String label, int index) {
    final bool selected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: selected ? const Color(0xFF008000) : Colors.black,
            ),
          ),
          if (selected)
            Container(
              height: 2,
              width: 40,
              color: const Color(0xFF008000),
            ),
        ],
      ),
    );
  }

  Widget _contactCard(IconData icon, String title, String value) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(10),
        color: Colors.white,
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF008000), size: 22),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.black54)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF008000),
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _valueCard(
      IconData icon, Color color, String title, String subtitle) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 4),
            Text(title,
                style: const TextStyle(
                    fontSize: 9, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text(subtitle,
                style: const TextStyle(fontSize: 8, color: Colors.black54),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _numberStat(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF008000))),
        Text(label,
            style: const TextStyle(fontSize: 10, color: Colors.black54),
            textAlign: TextAlign.center),
      ],
    );
  }

  Widget _teamCard(IconData icon, Color color, String label) {
    return Column(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: color.withOpacity(0.15),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _navItem(IconData icon, String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 28,
              color: active ? const Color(0xFF1E855A) : Colors.black54),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              color: active ? const Color(0xFF1E855A) : Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

// ── CERTIFICATE LIST ITEM ────────────────────────────────────────────────────
class _CertItem extends StatelessWidget {
  final String text;
  const _CertItem(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const Icon(Icons.check, color: Color(0xFF008000), size: 16),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
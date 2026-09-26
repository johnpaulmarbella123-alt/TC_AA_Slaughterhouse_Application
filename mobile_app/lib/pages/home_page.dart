import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screen/requests.dart';
import '../screen/notify.dart';
import '../screen/payment.dart';
import '../screen/profile.dart';
import '../screen/gallery.dart';
import '../screen/review.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

// Global notifier so profile page can update the top-bar avatar instantly
final ValueNotifier<String?> globalAvatarUrl = ValueNotifier<String?>(null);

// Global notifier for unread notification count — updated by the HomeScreen
// realtime listener, consumed by the bottom-nav badge. Instant updates.
final ValueNotifier<int> globalUnreadNotifCount = ValueNotifier<int>(0);

class _HomeScreenState extends State<HomeScreen> {
  int _selectedTab = 0;
  int _bottomNavIndex = 0;

  /// Tracks which tabs have been visited so we only build them on first use.
  final Set<int> _visitedTabs = {0}; // Home is always visited

  /// Incremented when user switches to the Notify tab to force a reload.
  final ValueNotifier<int> _notifyRefreshTrigger = ValueNotifier<int>(0);

  /// Realtime subscription for notification count — lives at app level so
  /// the badge updates immediately regardless of which tab is active.
  StreamSubscription<List<Map<String, dynamic>>>? _notifStreamSub;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
    // Listen for avatar changes from any page
    globalAvatarUrl.addListener(_onAvatarUrlChanged);
    // Listen for unread count changes (drives bottom-nav rebuild)
    globalUnreadNotifCount.addListener(_onUnreadCountChanged);

    // Start the app-level realtime listener for notifications.
    // This ensures the badge count updates instantly when admin sends
    // receipts, approvals, etc. — even if the user is on the Home tab.
    _startNotificationListener();

    // Also do an initial fetch so badge is correct on app launch.
    _fetchUnreadCount();

    // Precache the heavy hero image so it's ready when the Home tab renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(const AssetImage('assets/images/BG.jpeg'), context);
    });
  }

  @override
  void dispose() {
    _notifStreamSub?.cancel();
    globalAvatarUrl.removeListener(_onAvatarUrlChanged);
    globalUnreadNotifCount.removeListener(_onUnreadCountChanged);
    _notifyRefreshTrigger.dispose();
    super.dispose();
  }

  // ── APP-LEVEL NOTIFICATION LISTENER ──────────────────────────────────────
  // Subscribes to the notifications table via Supabase Realtime so the
  // unread badge count updates instantly when a new row is inserted or
  // an existing row is updated (e.g. marked as read).

  void _startNotificationListener() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    _notifStreamSub = Supabase.instance.client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .listen((rows) {
          // Count unread notifications from the streamed rows.
          final unread = rows.where((r) {
            final v = r['is_read'];
            if (v is bool) return !v;
            if (v is int) return v == 0;
            if (v is String) return v.toLowerCase() != 'true' && v != '1';
            return true; // default to unread if unknown
          }).length;

          globalUnreadNotifCount.value = unread;
          debugPrint('HOME: Realtime notif stream → $unread unread');
        });
  }

  /// One-shot fetch of the current unread count (for app launch).
  Future<void> _fetchUnreadCount() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final data = await Supabase.instance.client
          .from('notifications')
          .select('id, is_read')
          .eq('user_id', user.id)
          .eq('is_read', false);

      globalUnreadNotifCount.value = (data as List).length;
      debugPrint('HOME: Initial unread count = ${globalUnreadNotifCount.value}');
    } catch (e) {
      debugPrint('HOME: Failed to fetch unread count: $e');
    }
  }

  void _onAvatarUrlChanged() {
    debugPrint('TOP-BAR: globalAvatarUrl changed to ${globalAvatarUrl.value}');
    if (mounted) setState(() {});
  }

  Future<void> _loadAvatar() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('avatar_url')
          .eq('id', user.id)
          .single();
      final url = data['avatar_url'];
      if (url != null) {
        globalAvatarUrl.value = '$url?t=${DateTime.now().millisecondsSinceEpoch}';
      }
      debugPrint('TOP-BAR: Loaded avatar from DB = ${globalAvatarUrl.value}');
    } catch (e) {
      debugPrint('TOP-BAR: Error loading avatar: $e');
    }
  }

  void _onUnreadCountChanged() {
    if (mounted) setState(() {});
  }

  void _onBottomNavTap(int index) {
    setState(() {
      _bottomNavIndex = index;
      _visitedTabs.add(index); // mark tab as visited so it gets built
    });
    // Force NotifyPage to reload when user switches to it
    if (index == 2) {
      _notifyRefreshTrigger.value++;
    }
  }

  void request() => _onBottomNavTap(1);
  void notify() => _onBottomNavTap(2);
  void payment() => _onBottomNavTap(3);
  void profile() => _onBottomNavTap(4);

  @override
  Widget build(BuildContext context) {
    final avatarUrl = globalAvatarUrl.value;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── TOP NAV BAR ──────────────────────────────────────────────
            Container(
              color: const Color(0xFFC0EABE),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 33,
                    height: 34,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFD9D9D9),
                      image: DecorationImage(
                        image: AssetImage('assets/images/logo1.png'),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),

                  // Profile avatar — shows real photo or blank default
                  GestureDetector(
                    onTap: profile,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey.shade200,
                        border: Border.all(color: Colors.grey.shade400, width: 1),
                      ),
                      child: ClipOval(
                        child: avatarUrl != null
                            ? Image.network(
                                avatarUrl,
                                key: ValueKey(avatarUrl),
                                fit: BoxFit.cover,
                                width: 40,
                                height: 40,
                                errorBuilder: (_, error, ___) {
                                  debugPrint('TOP-BAR: Image.network FAILED: $error');
                                  return const Icon(
                                    Icons.person_outline,
                                    size: 24,
                                    color: Colors.grey,
                                  );
                                },
                              )
                            : const Icon(
                                Icons.person_outline,
                                size: 24,
                                color: Colors.grey,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── SCROLLABLE BODY ──────────────────────────────────────────
            Expanded(child: _buildBodyContent()),

            // ── BOTTOM NAVIGATION BAR ─────────────────────────────────────
            Container(
              color: const Color(0xFFD9D9D9),
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _navItem(Icons.home, "Home", _bottomNavIndex == 0, () => _onBottomNavTap(0)),
                  _navItem(Icons.description_outlined, "Requests", _bottomNavIndex == 1, request),
                  _navItem(Icons.notifications_none, "Notify", _bottomNavIndex == 2, notify,
                      badgeCount: globalUnreadNotifCount.value),
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
    // Lazy IndexedStack: only build tabs that have been visited.
    // Unvisited tabs are empty SizedBox placeholders (zero cost).
    final allTabs = <Widget>[
      _buildHomeContent(),                           // 0: Home
      const RequestsContent(),                       // 1: Requests
      NotifyPage(                                    // 2: Notify
        onNavigateToTab: _onBottomNavTap,
        refreshTrigger: _notifyRefreshTrigger,
      ),
      const PaymentContent(),                        // 3: Payment
      const ProfileContent(),                        // 4: Profile
    ];

    return IndexedStack(
      index: _bottomNavIndex,
      children: [
        for (int i = 0; i < allTabs.length; i++)
          _visitedTabs.contains(i) ? allTabs[i] : const SizedBox.shrink(),
      ],
    );
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
                child: Image.asset('assets/images/BG.jpeg', fit: BoxFit.cover),
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
                          fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Livestock Slaughter Service",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
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
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 35, vertical: 10),
                        elevation: 4,
                      ),
                      child: const Text(
                        "Get New Requests",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── OUR FULL OPERATION MACHINE ─────────────────────
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              "Our full Operation Machine",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 110,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                _machineCard("assets/images/pic1.jpeg", "Livestock processing facility"),
                const SizedBox(width: 8),
                _machineCard("assets/images/pic2.jpeg", "Weighing station"),
                const SizedBox(width: 8),
                _machineCard("assets/images/pic3.jpeg", "Sanitizing Station"),
                const SizedBox(width: 8),
                _machineCard("assets/images/pic4.jpeg", "Shackeys and trolleys"),
                const SizedBox(width: 8),
                _machineCard("assets/images/pic5.jpeg", "Stainless steel table"),
                const SizedBox(width: 8),
                _machineCard("assets/images/pic6.jpeg", "Stainless steel cable hoist"),
                const SizedBox(width: 8),
                _machineCard("assets/images/pic7.jpeg", "Stainless steel sink"),
                const SizedBox(width: 8),
                _machineCard("assets/images/pic8.jpeg", "Overhead conveyor rail"),
                const SizedBox(width: 8),
                _machineCard("assets/images/pic9.jpeg", "Hoist station"),
                const SizedBox(width: 8),
                _machineCard("assets/images/pic10.jpeg", "viscera(Inspection Table)"),
                const SizedBox(width: 8),
                _machineCard("assets/images/pic11.jpeg", "Drainage"),
                const SizedBox(width: 8),
                _machineCard("assets/images/pic12.jpeg", "Overhead conveyor rail system"),
                const SizedBox(width: 8),
                _machineCard("assets/images/pic13.jpeg", "Utility Cart"),
                const SizedBox(width: 8),
                _machineCard("assets/images/pic14.jpeg", "Scalding tanks"),
                const SizedBox(width: 8),
                _machineCard("assets/images/pic15.jpeg", "Worker's lift platform"),
                const SizedBox(width: 8),
                _machineCard("assets/images/pic16.jpeg", "Cummins diesel generator"),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── OUR SERVICE ────────────────────────────────────
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              "Our Service",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 100,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                _serviceCard("assets/images/hog.jpg", "Pig/Hog", "Hog Slaughter"),
                _serviceCard("assets/images/cow.jpg", "Cow", "Cattle Slaughter"),
                _serviceCard("assets/images/Goat.jpg", "Goat", "Goat Slaughter"),
                _serviceCard("assets/images/Sheep.jpg", "Sheep", "Sheep Slaughter"),
                _serviceCard("assets/images/Cara.jpg", "Carabao", "Carabao Slaughter"),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── ABOUT / GALLERY / REVIEW TABS ─────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _tabItem("About", 0),
                _tabItem("Gallery", 1),
                _tabItem("Review", 2),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ── TAB CONTENT ───────────────────────────────────
          if (_selectedTab == 1)
            const SizedBox(
              height: 500,
              child: GalleryContent(),
            )
          else if (_selectedTab == 2)
            const ReviewContent()
          else ...[
            // ── ABOUT TAB ─────────────────────────────────

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 37),
              child: Row(
                children: const [
                  Icon(Icons.location_on, color: Color(0xFF008000), size: 23),
                  SizedBox(width: 4),
                  SizedBox(
                    width: 89,
                    child: Text("Zone 1  San Carlos, Tabaco City",
                        style: TextStyle(fontSize: 10)),
                  ),
                  SizedBox(width: 18),
                  Icon(Icons.access_time, color: Color(0xFF008000), size: 23),
                  SizedBox(width: 4),
                  Text("Open 24 hours", style: TextStyle(fontSize: 10)),
                ],
              ),
            ),

            const SizedBox(height: 16),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                "Description",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                "It increases slaughtering capacity from 82 to 350 hogs and from 3 to 12 cattle daily. The city will hire 27 licensed butchers to ensure efficient operations. According to City Veterinarian Dr. Kim Ronan Romero, the new slaughterhouse will improve food safety and cleanliness compared to the old facility. The project has passed final inspection and the city has allocated funds for its operation and maintenance.",
                textAlign: TextAlign.justify,
                style: TextStyle(fontSize: 11, color: Colors.black87),
              ),
            ),

            const SizedBox(height: 20),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                "Contact Us",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            const SizedBox(height: 10),
            _contactCard(Icons.phone, "Phone", "+63 917 123 4567"),
            const SizedBox(height: 8),
            _contactCard(Icons.email_outlined, "Email", "tabacocityslaughterhouse@gmail.com"),

            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text("How it works? click ", style: TextStyle(fontSize: 13)),
                  GestureDetector(
                    onTap: () {},
                    child: const Text(
                      "Here!",
                      style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF008000),
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
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

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
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

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                "Our Team",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                "Our skilled team of veterinarians, butchers, and support staff are dedicated to providing the highest quality service. All our staff are trained in proper handling techniques and food safety standards.",
                textAlign: TextAlign.justify,
                style: TextStyle(fontSize: 11, color: Colors.black87),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _teamCard('assets/images/image 99.png', const Color.fromARGB(255, 7, 7, 205), "5 Veterinarians"),
                  _teamCard('assets/images/image 100.png', const Color(0xFF1E855A), "12 Butchers"),
                  _teamCard('assets/images/image 101.png', const Color(0xFFD4A017), "5 Staffs"),
                ],
              ),
            ),

            const SizedBox(height: 30),
          ], // end About tab
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
          child: Image.asset(imageUrl, width: 150, height: 90, fit: BoxFit.cover,
              cacheWidth: 300), // decode at 2x display size, not full resolution
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }

  Widget _serviceCard(String imageUrl, String animal, String label) {
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
                Image.asset(imageUrl, width: 80, height: 75, fit: BoxFit.cover),
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
              style: const TextStyle(fontSize: 9), textAlign: TextAlign.center),
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
            Container(height: 2, width: 40, color: const Color(0xFF008000)),
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
              Text(title, style: const TextStyle(fontSize: 11, color: Colors.black54)),
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

  Widget _valueCard(IconData icon, Color color, String title, String subtitle) {
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
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
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

  Widget _teamCard(String imagePath, Color color, String label) {
    return Container(
      width: 105,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            imagePath,
            width: 60,
            height: 60,
            color: color,
            colorBlendMode: BlendMode.srcIn,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, bool active, VoidCallback onTap,
      {int badgeCount = 0}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon,
                  size: 28,
                  color: active ? const Color(0xFF1E855A) : Colors.black54),
              if (badgeCount > 0)
                Positioned(
                  right: -6,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
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
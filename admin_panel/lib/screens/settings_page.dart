import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';
import '../services/app_settings_service.dart';
import '../utils/text_capitalization_formatters.dart';

class SettingsPage extends StatefulWidget {
  final int initialTab;

  const SettingsPage({super.key, this.initialTab = 0});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _settingsService = AppSettingsService.instance;

  // ─── 1. FEES & RATES STATE ───
  String _selectedAnimal = 'hog';
  final TextEditingController _facilityFeeCtrl =
      TextEditingController(text: '60.00');
  final TextEditingController _permitFeeCtrl =
      TextEditingController(text: '60.00');
  final TextEditingController _vetCertFeeCtrl =
      TextEditingController(text: '50.00');
  final TextEditingController _corralFeeCtrl =
      TextEditingController(text: '40.00');
  final TextEditingController _anteMortemCtrl =
      TextEditingController(text: '40.00');
  final TextEditingController _postMortemRateCtrl =
      TextEditingController(text: '5.00');
  final TextEditingController _deliveryVanCtrl =
      TextEditingController(text: '60.00');
  final TextEditingController _additionalFeeCtrl =
      TextEditingController(text: '0.00');
  final TextEditingController _additionalFeeLabelCtrl =
      TextEditingController(text: 'Additional Regulatory Surcharge');
  final TextEditingController _testWeightCtrl =
      TextEditingController(text: '75');

  // ─── 2. SLAUGHTER SCHEDULE & CAPACITY STATE ───
  late List<String> _selectedOperatingDays;
  late TextEditingController _openingTimeCtrl;
  late TextEditingController _closingTimeCtrl;
  late TextEditingController _cutoffTimeCtrl;
  late TextEditingController _maxHeadsCtrl;
  late TextEditingController _maxHogCtrl;
  late TextEditingController _maxCattleCtrl;
  late TextEditingController _maxCarabaoCtrl;
  late TextEditingController _maxGoatCtrl;
  late TextEditingController _maxPoultryCtrl;
  late bool _isFacilityOperational;
  late TextEditingController _noticeMsgCtrl;

  // ─── 3. MY PROFILE STATE ───
  late TextEditingController _profileNameCtrl;
  final TextEditingController _currentPasswordCtrl = TextEditingController();
  final TextEditingController _newPasswordCtrl = TextEditingController();
  final TextEditingController _confirmPasswordCtrl = TextEditingController();
  bool _obscureCurrentPass = true;
  bool _obscureNewPass = true;
  bool _obscureConfirmPass = true;
  bool _isUpdatingPassword = false;

  // ─── 4. APPEARANCE STATE ───
  late TextEditingController _headerTitleCtrl;
  late TextEditingController _headerSubtitleCtrl;
  late String _selectedLogoPath;

  // ─── 5. CUSTOMER ACCOUNTS STATE ───
  List<Map<String, dynamic>>? _customerAccounts = [];
  bool _loadingCustomers = false;
  String _customerSearchQuery = '';
  String _customerStatusFilter = 'all'; // 'all' | 'active' | 'deactivated'
  final TextEditingController _customerSearchCtrl = TextEditingController();

  // ─── 6. CUSTOMER REVIEWS STATE ───
  List<Map<String, dynamic>>? _adminReviews = [];
  bool _loadingReviews = false;
  String _reviewSearchQuery = '';
  int? _selectedStarFilter; // null = all
  final TextEditingController _reviewSearchCtrl = TextEditingController();
  double _reviewAverageRating = 0.0;
  Map<int, int>? _reviewRatingCounts = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
  double _reviewBlendedSatisfaction = 0.0;
  int _reviewCompletedOrdersCount = 0;
  int _reviewTotalOrdersCount = 0;

  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentTabIndex = widget.initialTab.clamp(0, 6);
    _tabController = TabController(
      length: 7,
      vsync: this,
      initialIndex: _currentTabIndex,
    );
    _tabController.addListener(() {
      if (_tabController.index != _currentTabIndex && !_tabController.indexIsChanging) {
        setState(() {
          _currentTabIndex = _tabController.index;
        });
      }
    });

    // Initialize fee controllers
    final initialSchedule =
        _settingsService.getFeeRatesForAnimal(_selectedAnimal);
    _facilityFeeCtrl.text = initialSchedule.facilityFee.toStringAsFixed(2);
    _permitFeeCtrl.text = initialSchedule.permitToSlaughterFee.toStringAsFixed(2);
    _vetCertFeeCtrl.text = initialSchedule.vetHealthCertFee.toStringAsFixed(2);
    _corralFeeCtrl.text = initialSchedule.corralFee.toStringAsFixed(2);
    _anteMortemCtrl.text = initialSchedule.anteMortemFee.toStringAsFixed(2);
    _postMortemRateCtrl.text = initialSchedule.postMortemRatePerKg.toStringAsFixed(2);
    _deliveryVanCtrl.text = initialSchedule.deliveryVanFee.toStringAsFixed(2);
    _additionalFeeCtrl.text = initialSchedule.additionalFee.toStringAsFixed(2);
    _additionalFeeLabelCtrl.text = initialSchedule.additionalFeeLabel;

    // Reload latest settings from Supabase (fees, staff, schedule)
    _settingsService.reloadFromSupabase().then((_) {
      if (mounted) {
        _loadAnimalFeeControllers(_selectedAnimal);
        _loadScheduleControllers(_settingsService.scheduleCapacity);
      }
    });

    // Fetch customer accounts, reviews and public metrics
    _loadCustomerAccounts();
    _loadAdminReviews();

    // Initialize schedule controllers
    final sched = _settingsService.scheduleCapacity;
    _selectedOperatingDays = List.from(sched.operatingDays);
    _openingTimeCtrl = TextEditingController(text: sched.openingTime);
    _closingTimeCtrl = TextEditingController(text: sched.closingTime);
    _cutoffTimeCtrl = TextEditingController(text: sched.cutoffTime);
    _maxHeadsCtrl =
        TextEditingController(text: sched.maxHeadsPerDay.toString());
    _maxHogCtrl = TextEditingController(text: sched.maxHogPerDay.toString());
    _maxCattleCtrl =
        TextEditingController(text: sched.maxCattlePerDay.toString());
    _maxCarabaoCtrl =
        TextEditingController(text: sched.maxCarabaoPerDay.toString());
    _maxGoatCtrl = TextEditingController(text: sched.maxGoatPerDay.toString());
    _maxPoultryCtrl =
        TextEditingController(text: sched.maxPoultryPerDay.toString());
    _isFacilityOperational = sched.isOperational;
    _noticeMsgCtrl = TextEditingController(text: sched.noticeMessage);

    // Initialize profile controller
    _profileNameCtrl =
        TextEditingController(text: _settingsService.profileName);

    // Initialize appearance controllers
    _headerTitleCtrl =
        TextEditingController(text: _settingsService.headerTitle);
    _headerSubtitleCtrl =
        TextEditingController(text: _settingsService.headerSubtitle);
    _selectedLogoPath = _settingsService.cityLogoPath;
  }

  @override
  void didUpdateWidget(SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab) {
      final target = widget.initialTab.clamp(0, 6);
      if (_currentTabIndex != target) {
        setState(() {
          _currentTabIndex = target;
        });
        _tabController.animateTo(target);
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _customerSearchCtrl.dispose();
    _facilityFeeCtrl.dispose();
    _permitFeeCtrl.dispose();
    _vetCertFeeCtrl.dispose();
    _corralFeeCtrl.dispose();
    _anteMortemCtrl.dispose();
    _postMortemRateCtrl.dispose();
    _deliveryVanCtrl.dispose();
    _additionalFeeCtrl.dispose();
    _additionalFeeLabelCtrl.dispose();
    _testWeightCtrl.dispose();

    _openingTimeCtrl.dispose();
    _closingTimeCtrl.dispose();
    _cutoffTimeCtrl.dispose();
    _maxHeadsCtrl.dispose();
    _maxHogCtrl.dispose();
    _maxCattleCtrl.dispose();
    _maxCarabaoCtrl.dispose();
    _maxGoatCtrl.dispose();
    _maxPoultryCtrl.dispose();
    _noticeMsgCtrl.dispose();

    _profileNameCtrl.dispose();
    _currentPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();

    _headerTitleCtrl.dispose();
    _headerSubtitleCtrl.dispose();
    _reviewSearchCtrl.dispose();
    super.dispose();
  }

  void _loadAnimalFeeControllers(String animal) {
    setState(() {
      _selectedAnimal = animal;
      final sched = _settingsService.getFeeRatesForAnimal(animal);
      _facilityFeeCtrl.text = sched.facilityFee.toStringAsFixed(2);
      _permitFeeCtrl.text = sched.permitToSlaughterFee.toStringAsFixed(2);
      _vetCertFeeCtrl.text = sched.vetHealthCertFee.toStringAsFixed(2);
      _corralFeeCtrl.text = sched.corralFee.toStringAsFixed(2);
      _anteMortemCtrl.text = sched.anteMortemFee.toStringAsFixed(2);
      _postMortemRateCtrl.text = sched.postMortemRatePerKg.toStringAsFixed(2);
      _deliveryVanCtrl.text = sched.deliveryVanFee.toStringAsFixed(2);
      _additionalFeeCtrl.text = sched.additionalFee.toStringAsFixed(2);
      _additionalFeeLabelCtrl.text = sched.additionalFeeLabel;
    });
  }

  void _loadScheduleControllers(SlaughterScheduleCapacity sched) {
    setState(() {
      _selectedOperatingDays = List.from(sched.operatingDays);
      _openingTimeCtrl.text = sched.openingTime;
      _closingTimeCtrl.text = sched.closingTime;
      _cutoffTimeCtrl.text = sched.cutoffTime;
      _maxHeadsCtrl.text = sched.maxHeadsPerDay.toString();
      _maxHogCtrl.text = sched.maxHogPerDay.toString();
      _maxCattleCtrl.text = sched.maxCattlePerDay.toString();
      _maxCarabaoCtrl.text = sched.maxCarabaoPerDay.toString();
      _maxGoatCtrl.text = sched.maxGoatPerDay.toString();
      _maxPoultryCtrl.text = sched.maxPoultryPerDay.toString();
      _isFacilityOperational = sched.isOperational;
      _noticeMsgCtrl.text = sched.noticeMessage;
    });
  }

  Future<void> _loadAdminReviews() async {
    setState(() => _loadingReviews = true);
    try {
      final client = Supabase.instance.client;
      final data = await client
          .from('reviews')
          .select()
          .order('created_at', ascending: false);
      final reviews = List<Map<String, dynamic>>.from(data);

      final Map<int, int> counts = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
      double totalRating = 0;
      for (var r in reviews) {
        final rating = (r['rating'] as num?)?.toInt() ?? 5;
        counts[rating] = (counts[rating] ?? 0) + 1;
        totalRating += rating;
      }
      final avg = reviews.isEmpty ? 0.0 : (totalRating / reviews.length);

      int completed = 0;
      int total = 0;
      double compRate = 0.0;
      try {
        final reqData = await client.from('requests').select('status');
        final reqList = List<Map<String, dynamic>>.from(reqData);
        for (var r in reqList) {
          final s = (r['status'] ?? '').toString().toLowerCase();
          if (s != 'cancelled' && s != 'rejected') {
            total++;
            if (s == 'released' || s == 'completed') {
              completed++;
            }
          }
        }
        if (total > 0) {
          compRate = (completed / total) * 100.0;
        }
      } catch (err) {
        debugPrint('Could not fetch requests for satisfaction rate: $err');
      }

      final double revScore = reviews.isNotEmpty ? (avg / 5.0) * 100.0 : 0.0;
      final double blended = (0.50 * compRate) + (0.50 * revScore);

      if (mounted) {
        setState(() {
          _adminReviews = reviews;
          _reviewAverageRating = avg;
          _reviewRatingCounts = counts;
          _reviewCompletedOrdersCount = completed;
          _reviewTotalOrdersCount = total;
          _reviewBlendedSatisfaction = blended.clamp(0.0, 100.0);
          _loadingReviews = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading reviews in settings: $e');
      if (mounted) setState(() => _loadingReviews = false);
    }
  }

  Future<void> _saveCurrentAnimalRates() async {
    final facility = double.tryParse(_facilityFeeCtrl.text) ?? 60.0;
    final permit = double.tryParse(_permitFeeCtrl.text) ?? 60.0;
    final vet = double.tryParse(_vetCertFeeCtrl.text) ?? 50.0;
    final corral = double.tryParse(_corralFeeCtrl.text) ?? 40.0;
    final ante = double.tryParse(_anteMortemCtrl.text) ?? 40.0;
    final post = double.tryParse(_postMortemRateCtrl.text) ?? 5.0;
    final van = double.tryParse(_deliveryVanCtrl.text) ?? 60.0;
    final additional = double.tryParse(_additionalFeeCtrl.text) ?? 0.0;
    final additionalLabel = _additionalFeeLabelCtrl.text.trim().isEmpty
        ? 'Additional Regulatory Surcharge'
        : _additionalFeeLabelCtrl.text.trim();

    final updated = AnimalFeeSchedule(
      animalType: _selectedAnimal,
      facilityFee: facility,
      permitToSlaughterFee: permit,
      vetHealthCertFee: vet,
      corralFee: corral,
      anteMortemFee: ante,
      postMortemRatePerKg: post,
      deliveryVanFee: van,
      additionalFee: additional,
      additionalFeeLabel: additionalLabel,
    );

    try {
      await _settingsService.updateFeeSchedule(updated);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Saved fee schedule for ${_selectedAnimal.toUpperCase()} successfully! Customer mobile app and Cashiering are now synced in real-time.'),
            backgroundColor: const Color(0xFF2D6A4F),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save to cloud: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Hot-reload resilience for Flutter Web
    _customerAccounts ??= [];
    _adminReviews ??= [];
    _reviewRatingCounts ??= {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
    if (_tabController.length != 7) {
      _tabController.dispose();
      _tabController = TabController(
        length: 7,
        vsync: this,
        initialIndex: _currentTabIndex.clamp(0, 6),
      );
      _tabController.addListener(() {
        if (_tabController.index != _currentTabIndex && !_tabController.indexIsChanging) {
          setState(() {
            _currentTabIndex = _tabController.index;
          });
        }
      });
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAdmin = _settingsService.isAdmin;

    if (!isAdmin) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(isDark),
            Expanded(child: _buildMyProfileTab(isDark)),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── TOP APP BAR / HEADER ───
          _buildHeader(isDark),

          // ─── TAB NAVIGATION BAR ───
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
                  width: 1,
                ),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              onTap: (index) {
                if (_currentTabIndex != index) {
                  setState(() => _currentTabIndex = index);
                }
              },
              labelColor: const Color(0xFF2D6A4F),
              unselectedLabelColor:
                  isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              indicatorColor: const Color(0xFF2D6A4F),
              indicatorWeight: 3,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              unselectedLabelStyle:
                  const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              tabs: const [
                Tab(icon: Icon(Icons.payments_outlined, size: 20), text: 'Fees & Rates'),
                Tab(icon: Icon(Icons.badge_outlined, size: 20), text: 'Staff Accounts & Roles'),
                Tab(icon: Icon(Icons.schedule_outlined, size: 20), text: 'Schedule & Capacity'),
                Tab(icon: Icon(Icons.person_outline, size: 20), text: 'My Profile'),
                Tab(icon: Icon(Icons.palette_outlined, size: 20), text: 'Appearance'),
                Tab(icon: Icon(Icons.people_outline, size: 20), text: 'Customer Accounts'),
                Tab(icon: Icon(Icons.rate_review_outlined, size: 20), text: 'Customer Reviews'),
              ],
            ),
          ),

          // ─── TAB CONTENT (Instant zero-lag tab switching) ───
          Expanded(
            child: IndexedStack(
              index: _currentTabIndex,
              children: [
                _buildFeesAndRatesTab(isDark),
                _buildStaffRolesTab(isDark),
                _buildScheduleCapacityTab(isDark),
                _buildMyProfileTab(isDark),
                _buildAppearanceTab(isDark),
                _buildCustomerAccountsTab(isDark),
                _buildCustomerReviewsTab(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  TOP HEADER
  // ═══════════════════════════════════════════════════════════
  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF2D6A4F).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.settings,
              color: Color(0xFF2D6A4F),
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'System Settings & Administration',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Configure slaughter fees, staff roles & module access, capacity schedules, administrator profile, and branding.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          // Current Role Indicator Tag
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF2D6A4F).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF2D6A4F).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.admin_panel_settings,
                    color: Color(0xFF2D6A4F), size: 18),
                const SizedBox(width: 8),
                Text(
                  'Current Role: ${_settingsService.currentRole}',
                  style: const TextStyle(
                    color: Color(0xFF2D6A4F),
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  TAB 1: FEES AND RATES
  // ═══════════════════════════════════════════════════════════
  Widget _buildFeesAndRatesTab(bool isDark) {
    final animalOptions = [
      {'key': 'hog', 'label': 'Hog (Swine)', 'icon': '🐖'},
      {'key': 'cattle', 'label': 'Cattle (Cow)', 'icon': '🐂'},
      {'key': 'carabao', 'label': 'Carabao (Water Buffalo)', 'icon': '🐃'},
      {'key': 'goat', 'label': 'Goat (Caprine)', 'icon': '🐐'},
      {'key': 'sheep', 'label': 'Sheep (Ovine)', 'icon': '🐑'},
    ];

    // Compute preview
    final double testWeight = double.tryParse(_testWeightCtrl.text) ?? 75.0;
    final double facility = double.tryParse(_facilityFeeCtrl.text) ?? 0.0;
    final double permit = double.tryParse(_permitFeeCtrl.text) ?? 0.0;
    final double vet = double.tryParse(_vetCertFeeCtrl.text) ?? 0.0;
    final double corral = double.tryParse(_corralFeeCtrl.text) ?? 0.0;
    final double ante = double.tryParse(_anteMortemCtrl.text) ?? 0.0;
    final double postRate = double.tryParse(_postMortemRateCtrl.text) ?? 0.0;
    final double van = double.tryParse(_deliveryVanCtrl.text) ?? 0.0;
    final double additional = double.tryParse(_additionalFeeCtrl.text) ?? 0.0;
    final String additionalLabel = _additionalFeeLabelCtrl.text.trim().isEmpty
        ? 'Additional Regulatory Surcharge'
        : _additionalFeeLabelCtrl.text.trim();
    final double postMortemTotal = testWeight * postRate;
    final double subtotal = facility + permit + vet + corral + ante + postMortemTotal + additional;
    final double marketTotal = subtotal + van;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Notice
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF2D6A4F).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF2D6A4F).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFF2D6A4F), size: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Fee Schedule Integration: All fees configured here are dynamically queried by the Payment & Cashiering module and the customer mobile app. Livestock intakes are calculated based on their registered species and include any administration charges.',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF2D3748),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Animal Selector Pills
          Text(
            'Select Animal Commodity to Configure:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: animalOptions.map((opt) {
              final isSelected = _selectedAnimal == opt['key'];
              return ChoiceChip(
                labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                avatar: Text(opt['icon']!, style: const TextStyle(fontSize: 16)),
                label: Text(
                  opt['label']!,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? Colors.white
                        : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
                  ),
                ),
                selected: isSelected,
                selectedColor: const Color(0xFF2D6A4F),
                backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: isSelected
                        ? const Color(0xFF2D6A4F)
                        : (isDark ? const Color(0xFF334155) : Colors.grey.shade300),
                  ),
                ),
                onSelected: (selected) {
                  if (selected) {
                    _loadAnimalFeeControllers(opt['key']!);
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // 2-Column Layout: Fee Inputs + Live Calculator Preview
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Column 1: Editable Fee Rates
              Expanded(
                flex: 3,
                child: Card(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${_selectedAnimal.toUpperCase()} Rates & Tariff',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF1E293B),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                _settingsService.resetFeesToDefaults();
                                _loadAnimalFeeControllers(_selectedAnimal);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Reset fee rates to standard ordinance defaults.'),
                                    backgroundColor: Color(0xFF475569),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Reset Defaults'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade700,
                                side: BorderSide(color: isDark ? const Color(0xFF334155) : Colors.grey.shade300),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Form Grid
                        _buildFeeInputField('Slaughter / Facility Fee', _facilityFeeCtrl,
                            'City operational & slaughter line fee per head', isDark),
                        const SizedBox(height: 14),
                        _buildFeeInputField('Permit to Slaughter Fee', _permitFeeCtrl,
                            'Municipal regulatory slaughter authorization permit', isDark),
                        const SizedBox(height: 14),
                        _buildFeeInputField('Veterinary Health Certificate Fee', _vetCertFeeCtrl,
                            'Official Veterinary issuance & validation fee', isDark),
                        const SizedBox(height: 14),
                        _buildFeeInputField('Corral / Holding Fee', _corralFeeCtrl,
                            'Ante-mortem holding pen stay fee per head', isDark),
                        const SizedBox(height: 14),
                        _buildFeeInputField('Ante-Mortem Examination Fee', _anteMortemCtrl,
                            'Pre-slaughter clinical health examination fee', isDark),
                        const SizedBox(height: 14),
                        _buildFeeInputField('Post-Mortem Rate (₱ per kg Carcass)', _postMortemRateCtrl,
                            'Rate multiplied by actual carcass dressed weight (kg)', isDark),
                        const SizedBox(height: 14),
                        _buildFeeInputField('Delivery Van Fee (Market Distribution)', _deliveryVanCtrl,
                            'Refrigerated delivery dispatch fee (Market request type only)', isDark),
                        const SizedBox(height: 20),

                        // Additional Charges Section
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDark ? const Color(0xFF334155) : Colors.grey.shade300,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.add_circle_outline, color: Color(0xFF2D6A4F), size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Additional Administrative Charges (${_selectedAnimal.toUpperCase()})',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'If administration adds any specific charge or surcharge for this livestock, specify the description and amount below.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildFeeInputField(
                                'Charge Description / Label',
                                _additionalFeeLabelCtrl,
                                'e.g. Cold Storage Surcharge, Waste Management, Sanitation Fee',
                                isDark,
                                isNumeric: false,
                              ),
                              const SizedBox(height: 12),
                              _buildFeeInputField(
                                'Additional Charge Amount (₱)',
                                _additionalFeeCtrl,
                                'Fee amount added per head (₱0.00 if none)',
                                isDark,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Save Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _saveCurrentAnimalRates,
                            icon: const Icon(Icons.save, size: 18),
                            label: Text('Save ${_selectedAnimal.toUpperCase()} Rates'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2D6A4F),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),

              // Column 2: Live Calculation Preview
              Expanded(
                flex: 2,
                child: Card(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.calculate_outlined,
                                color: Color(0xFF2D6A4F), size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Live Cashiering Preview',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Test fee calculations in real-time as cashier will see them:',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Test Weight Input
                        TextField(
                          controller: _testWeightCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Sample Carcass Weight (kg)',
                            suffixText: 'kg',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 8),

                        _buildPreviewRow('Vet Health Certificate', vet, isDark),
                        _buildPreviewRow('Permit to Slaughter', permit, isDark),
                        _buildPreviewRow('Facility Fee', facility, isDark),
                        _buildPreviewRow('Corral Fee', corral, isDark),
                        _buildPreviewRow('Ante-Mortem Fee', ante, isDark),
                        _buildPreviewRow(
                          'Post-Mortem (${testWeight.toStringAsFixed(0)} kg @ ₱${postRate.toStringAsFixed(2)})',
                          postMortemTotal,
                          isDark,
                        ),
                        if (additional > 0)
                          _buildPreviewRow(additionalLabel, additional, isDark),
                        const Divider(),
                        _buildPreviewRow('Barangay Subtotal (Self Pickup)', subtotal, isDark, isBold: true),
                        _buildPreviewRow('Market Delivery Fee', van, isDark),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D6A4F).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFF2D6A4F).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'TOTAL (Market Intake):',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2D6A4F),
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                '₱${marketTotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2D6A4F),
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeeInputField(
      String label, TextEditingController ctrl, String hint, bool isDark,
      {bool isNumeric = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: isNumeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          textCapitalization: isNumeric
              ? TextCapitalization.none
              : TextCapitalization.words,
          inputFormatters: isNumeric
              ? null
              : const [WordsCapitalizationFormatter()],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixText: isNumeric ? '₱ ' : null,
            prefixIcon: isNumeric
                ? null
                : const Icon(Icons.label_outline, size: 18, color: Color(0xFF2D6A4F)),
            prefixStyle: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
            helperText: hint,
            helperMaxLines: 1,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewRow(String label, double amount, bool isDark,
      {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
              ),
            ),
          ),
          Text(
            '₱${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  TAB 2: STAFF ACCOUNTS AND ROLES
  // ═══════════════════════════════════════════════════════════
  Widget _buildStaffRolesTab(bool isDark) {
    final rolesList = [
      'Admin',
      'Clerk',
      'Inspector',
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Role Simulation / Quick Role Switcher Banner (Admin preview)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF2D6A4F).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF2D6A4F).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.switch_account_outlined,
                    color: Color(0xFF2D6A4F), size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Active Session Role Switcher (Admin Preview Mode)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Preview how the Dashboard and Sidebar look for Clerk or Inspector. When a Clerk or Inspector logs in with their own credentials, they are locked exclusively to their assigned role.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: rolesList.contains(_settingsService.currentRole)
                      ? _settingsService.currentRole
                      : 'Admin',
                  dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                  items: rolesList.map((r) {
                    return DropdownMenuItem(
                      value: r,
                      child: Text(
                        r,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (newRole) {
                    if (newRole != null) {
                      setState(() {
                        _settingsService.setCurrentRole(newRole);
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Active role switched to "$newRole". Dashboard & sidebar modules updated!'),
                          backgroundColor: const Color(0xFF2D6A4F),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Header with Add Staff Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Staff Accounts & Access Permissions',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Provision Clerk and Inspector accounts, assign their roles, and set their exclusive login passwords.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => _showAddStaffDialog(isDark),
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('Add Staff Member'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D6A4F),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Staff Accounts Table
          Card(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: Column(
              children: [
                for (int index = 0;
                    index < _settingsService.staffAccounts.length;
                    index++) ...[
                  if (index > 0)
                    Divider(
                      color: isDark
                          ? const Color(0xFF334155)
                          : Colors.grey.shade200,
                      height: 1,
                    ),
                  _buildStaffRow(
                    _settingsService.staffAccounts[index],
                    isDark,
                    rolesList,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Role Permission Matrix Card
          Card(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Role Access Control Matrix',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Specifies the dedicated dashboard and operational modules visible in the left sidebar for each role:',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildMatrixRow('Admin', 'Executive Dashboard, Reports & Records, Settings & Full Supervisory Oversight', isDark),
                  _buildMatrixRow('Clerk', 'Clerk Pending-Tasks Dashboard, Receiving & New Requests, Document Verification, Payment & Cashiering, Meat Releasing, My Profile', isDark),
                  _buildMatrixRow('Inspector', 'Inspector Pending-Tasks Dashboard, Slaughter & Inspection (Ante/Post-Mortem & MIC), My Profile', isDark),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _roleColor(String role) {
    switch (StaffAccount.normalizeRole(role)) {
      case 'Admin':
        return const Color(0xFF2D6A4F);
      case 'Clerk':
        return const Color(0xFF7C3AED);
      case 'Inspector':
        return const Color(0xFF2563EB);
      default:
        return Colors.grey.shade700;
    }
  }

  Widget _buildMatrixRow(String role, String access, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 140,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _roleColor(role).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              role,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _roleColor(role),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              access,
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddStaffDialog(bool isDark) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    bool obscurePass = true;
    String selectedRole = 'Clerk';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          title: const Text('Add Staff Member'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: const [WordsCapitalizationFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline, size: 18),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Email Address (Login Username)',
                    prefixIcon: Icon(Icons.email_outlined, size: 18),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordCtrl,
                  obscureText: obscurePass,
                  decoration: InputDecoration(
                    labelText: 'Login Password',
                    helperText: 'Used by this staff member to log into their role portal',
                    prefixIcon: const Icon(Icons.lock_outline, size: 18),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePass ? Icons.visibility_off : Icons.visibility,
                        size: 18,
                      ),
                      onPressed: () => setDlgState(() => obscurePass = !obscurePass),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Assigned Role',
                    prefixIcon: Icon(Icons.badge_outlined, size: 18),
                  ),
                  items: [
                    'Admin',
                    'Clerk',
                    'Inspector',
                  ].map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) {
                    if (v != null) setDlgState(() => selectedRole = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final email = emailCtrl.text.trim();
                final password = passwordCtrl.text;
                if (name.isEmpty || email.isEmpty || password.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter Full Name, Email Address, and Login Password.'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                  return;
                }

                Navigator.pop(ctx);

                // 1. Provision live Supabase Auth account using a standalone client instance
                String? generatedUid;
                try {
                  const defaultUrl = 'https://jacgcceaxblwgdxaeaqk.supabase.co';
                  const defaultAnonKey =
                      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImphY2djY2VheGJsd2dkeGFlYXFrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg4MzE4MDMsImV4cCI6MjA5NDQwNzgwM30.UQZJMdhEKQ2KqOmcvqFg8-JWBuR5b9XtjphzAnKeW6c';
                  final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? defaultUrl;
                  final supabaseKey = dotenv.env['SUPABASE_ANON_KEY'] ?? defaultAnonKey;

                  final standaloneClient = SupabaseClient(supabaseUrl, supabaseKey);
                  final authRes = await standaloneClient.auth.signUp(
                    email: email,
                    password: password,
                    data: {
                      'role': selectedRole.toLowerCase(),
                      'full_name': name,
                    },
                  );
                  if (authRes.user != null) {
                    generatedUid = authRes.user!.id;
                    try {
                      await Supabase.instance.client.from('profiles').upsert({
                        'id': authRes.user!.id,
                        'full_name': name,
                        'role': selectedRole.toLowerCase(),
                        'updated_at': DateTime.now().toIso8601String(),
                      });
                    } catch (_) {}
                  }
                } catch (authErr) {
                  debugPrint('Staff Supabase Auth provisioning notice: $authErr');
                }

                final newStaff = StaffAccount(
                  id: generatedUid ?? 'staff-${DateTime.now().millisecondsSinceEpoch}',
                  fullName: name,
                  email: email,
                  role: selectedRole,
                  createdAt: DateTime.now(),
                  password: password,
                );

                await _settingsService.addStaffAccount(newStaff);
                if (mounted) {
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Successfully provisioned $name ($selectedRole)! Account ready for login.'),
                      backgroundColor: const Color(0xFF2D6A4F),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2D6A4F),
                foregroundColor: Colors.white,
              ),
              child: const Text('Add Staff'),
            ),
          ],
        ),
      ),
    );
  }

  void _showResetStaffPasswordDialog(StaffAccount staff, bool isDark) {
    final passCtrl = TextEditingController(text: staff.password ?? '');
    bool obscure = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Text('Set Login Password — ${staff.fullName}'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Role Portal: ${StaffAccount.normalizeRole(staff.role)}\nEmail: ${staff.email}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: passCtrl,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'New Login Password',
                    prefixIcon: const Icon(Icons.key_outlined, size: 18),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility,
                        size: 18,
                      ),
                      onPressed: () => setDlgState(() => obscure = !obscure),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newPass = passCtrl.text.trim();
                if (newPass.isEmpty) return;
                Navigator.pop(ctx);
                await _settingsService.updateStaffPassword(staff.id, newPass);
                if (mounted) {
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Updated login password for ${staff.fullName} (${staff.role}).'),
                      backgroundColor: const Color(0xFF2D6A4F),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2D6A4F),
                foregroundColor: Colors.white,
              ),
              child: const Text('Save Password'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaffRow(StaffAccount staff, bool isDark, List<String> rolesList) {
    final normalizedStaffRole = StaffAccount.normalizeRole(staff.role);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: staff.isActive
                ? const Color(0xFF2D6A4F).withValues(alpha: 0.15)
                : Colors.grey.shade300,
            child: Text(
              staff.fullName.isNotEmpty
                  ? staff.fullName.substring(0, 1).toUpperCase()
                  : 'S',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: staff.isActive
                    ? const Color(0xFF2D6A4F)
                    : Colors.grey.shade600,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Name & Email
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  staff.fullName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  staff.email,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          // Role Selector
          Expanded(
            flex: 3,
            child: DropdownButton<String>(
              value: rolesList.contains(normalizedStaffRole) ? normalizedStaffRole : 'Clerk',
              dropdownColor:
                  isDark ? const Color(0xFF1E293B) : Colors.white,
              underline: const SizedBox(),
              items: rolesList.map((r) {
                return DropdownMenuItem(
                  value: r,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _roleColor(r).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      r,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _roleColor(r),
                      ),
                    ),
                  ),
                );
              }).toList(),
              onChanged: (newRole) async {
                if (newRole != null) {
                  await _settingsService.updateStaffRole(
                      staff.id, newRole);
                  if (mounted) setState(() {});
                }
              },
            ),
          ),
          // Active Status Switch
          Row(
            children: [
              Text(
                staff.isActive ? 'Active' : 'Inactive',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: staff.isActive
                      ? const Color(0xFF16A34A)
                      : Colors.grey,
                ),
              ),
              Switch(
                value: staff.isActive,
                activeThumbColor: const Color(0xFF2D6A4F),
                onChanged: (_) async {
                  await _settingsService.toggleStaffStatus(staff.id);
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
          const SizedBox(width: 4),
          // Set / Reset Password Action
          IconButton(
            icon: const Icon(Icons.key_outlined,
                color: Color(0xFF2D6A4F), size: 20),
            tooltip: 'Set / Reset Login Password',
            onPressed: () => _showResetStaffPasswordDialog(staff, isDark),
          ),
          // Delete Action
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: Colors.redAccent, size: 20),
            tooltip: 'Remove Staff',
            onPressed: () async {
              final staffName = staff.fullName;
              await _settingsService.deleteStaffAccount(staff.id);
              if (!mounted) return;
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Removed $staffName from staff accounts.'),
                  backgroundColor: const Color(0xFF2D6A4F),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  TAB 3: SLAUGHTER SCHEDULE & CAPACITY
  // ═══════════════════════════════════════════════════════════
  Widget _buildScheduleCapacityTab(bool isDark) {
    final daysOfWeek = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Operational Status Card
          Card(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(
                    _isFacilityOperational
                        ? Icons.check_circle
                        : Icons.warning_amber_rounded,
                    color: _isFacilityOperational
                        ? const Color(0xFF16A34A)
                        : Colors.orange,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isFacilityOperational
                              ? 'Facility Status: OPEN FOR OPERATIONS'
                              : 'Facility Status: TEMPORARILY SUSPENDED / HOLIDAY',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: _isFacilityOperational
                                ? const Color(0xFF16A34A)
                                : Colors.orange,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Controls whether customer intakes and mobile submissions are actively accepted.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _isFacilityOperational,
                    activeThumbColor: const Color(0xFF2D6A4F),
                    onChanged: (v) => setState(() => _isFacilityOperational = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Operating Days Selector
          Card(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Slaughterhouse Operating Days',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select days of the week when slaughter intake and processing occur:',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: daysOfWeek.map((day) {
                      final isSelected = _selectedOperatingDays.contains(day);
                      return FilterChip(
                        label: Text(day),
                        selected: isSelected,
                        selectedColor: const Color(0xFF2D6A4F),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedOperatingDays.add(day);
                            } else {
                              _selectedOperatingDays.remove(day);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Operating Hours & Cutoff Times
          Card(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Operating Hours & Intake Cutoff Time',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _openingTimeCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Facility Opening Time (24h or AM/PM)',
                            hintText: '05:00',
                            prefixIcon: Icon(Icons.access_time),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _closingTimeCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Facility Closing Time',
                            hintText: '17:00',
                            prefixIcon: Icon(Icons.access_time),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _cutoffTimeCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Request Cutoff Time',
                            hintText: '15:00',
                            helperText: 'Intakes after this are queued next day',
                            prefixIcon: Icon(Icons.timer_outlined),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Daily Capacity Limits (Total + Per Animal)
          Card(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Daily Processing Capacity Limits (Heads per Day)',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _maxHeadsCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Total Maximum Heads / Day',
                            prefixIcon: Icon(Icons.inventory_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _maxHogCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Max Hogs / Day',
                            prefixText: '🐖 ',
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _maxCattleCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Max Cattle / Day',
                            prefixText: '🐂 ',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _maxCarabaoCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Max Carabao / Day',
                            prefixText: '🐃 ',
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _maxGoatCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Max Goats / Day',
                            prefixText: '🐐 ',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _noticeMsgCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: const [SentencesCapitalizationFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Public Advisory / Schedule Notice Message',
                      hintText: 'Standard operating hours active.',
                      prefixIcon: Icon(Icons.announcement_outlined),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Save Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final newSched = SlaughterScheduleCapacity(
                  operatingDays: _selectedOperatingDays,
                  openingTime: _openingTimeCtrl.text.trim(),
                  closingTime: _closingTimeCtrl.text.trim(),
                  cutoffTime: _cutoffTimeCtrl.text.trim(),
                  maxHeadsPerDay: int.tryParse(_maxHeadsCtrl.text) ?? 100,
                  maxHogPerDay: int.tryParse(_maxHogCtrl.text) ?? 60,
                  maxCattlePerDay: int.tryParse(_maxCattleCtrl.text) ?? 20,
                  maxCarabaoPerDay: int.tryParse(_maxCarabaoCtrl.text) ?? 10,
                  maxGoatPerDay: int.tryParse(_maxGoatCtrl.text) ?? 10,
                  maxPoultryPerDay: int.tryParse(_maxPoultryCtrl.text) ?? 50,
                  isOperational: _isFacilityOperational,
                  noticeMessage: _noticeMsgCtrl.text.trim(),
                );
                try {
                  await _settingsService.updateScheduleCapacity(newSched);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Saved schedule and capacity settings successfully! Synced to cloud database.'),
                        backgroundColor: Color(0xFF2D6A4F),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to save schedule to cloud: $e'),
                        backgroundColor: Colors.red.shade700,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Save Operating Schedule & Capacity'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2D6A4F),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  TAB 4: MY PROFILE
  // ═══════════════════════════════════════════════════════════
  Widget _buildMyProfileTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile Details Card
          Card(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Profile Information',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      // Profile Avatar with change option
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: const Color(0xFF2D6A4F).withValues(alpha: 0.15),
                            backgroundImage: _settingsService.profilePhotoUrl != null
                                ? NetworkImage(_settingsService.profilePhotoUrl!)
                                : null,
                            child: _settingsService.profilePhotoUrl == null
                                ? const Icon(Icons.person,
                                    size: 44, color: Color(0xFF2D6A4F))
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: InkWell(
                              onTap: () => _showChangePhotoDialog(isDark),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF2D6A4F),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.camera_alt,
                                    color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _settingsService.profileName,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _settingsService.profileEmail,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2D6A4F).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Role: ${_settingsService.currentRole}',
                                style: const TextStyle(
                                  color: Color(0xFF2D6A4F),
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
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Edit Name Field
                  TextField(
                    controller: _profileNameCtrl,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: const [WordsCapitalizationFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Full Legal Name',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      final newName = _profileNameCtrl.text.trim();
                      if (newName.isNotEmpty) {
                        _settingsService.updateProfileName(newName);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Profile name updated successfully!'),
                            backgroundColor: Color(0xFF2D6A4F),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.save, size: 18),
                    label: const Text('Save Profile Name'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2D6A4F),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Change Password Card
          Card(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.lock_outline, color: Color(0xFF2D6A4F), size: 22),
                      const SizedBox(width: 10),
                      Text(
                        'Change Password',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D6A4F).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF2D6A4F).withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.account_circle, size: 20, color: Color(0xFF2D6A4F)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Authenticated User: ${_settingsService.profileEmail}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _currentPasswordCtrl,
                    obscureText: _obscureCurrentPass,
                    decoration: InputDecoration(
                      labelText: 'Current / Existing Password',
                      helperText: 'Required: Enter your existing password to verify ownership',
                      prefixIcon: const Icon(Icons.key_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureCurrentPass
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () =>
                            setState(() => _obscureCurrentPass = !_obscureCurrentPass),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _newPasswordCtrl,
                    obscureText: _obscureNewPass,
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      helperText: 'Must be at least 6 characters',
                      prefixIcon: const Icon(Icons.lock_reset),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureNewPass
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () =>
                            setState(() => _obscureNewPass = !_obscureNewPass),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _confirmPasswordCtrl,
                    obscureText: _obscureConfirmPass,
                    decoration: InputDecoration(
                      labelText: 'Confirm New Password',
                      helperText: 'Re-enter your new password to confirm',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirmPass
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () => setState(
                            () => _obscureConfirmPass = !_obscureConfirmPass),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _isUpdatingPassword ? null : _handleChangePassword,
                    icon: _isUpdatingPassword
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.key, size: 18),
                    label: Text(_isUpdatingPassword
                        ? 'Updating...'
                        : 'Update Account Password'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2D6A4F),
                      foregroundColor: Colors.white,
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

  void _showChangePhotoDialog(bool isDark) {
    final urlCtrl = TextEditingController(text: _settingsService.profilePhotoUrl ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        title: const Text('Update Profile Photo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter image URL or select from default officer avatars:'),
            const SizedBox(height: 14),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(
                labelText: 'Image / Photo URL',
                hintText: 'https://...',
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.clear, size: 16),
                  label: const Text('Remove Photo'),
                  onPressed: () {
                    _settingsService.updateProfilePhoto(null);
                    Navigator.pop(ctx);
                    setState(() {});
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final url = urlCtrl.text.trim();
              if (url.isNotEmpty) {
                _settingsService.updateProfilePhoto(url);
                setState(() {});
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save Photo'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleChangePassword() async {
    final currentPass = _currentPasswordCtrl.text;
    final newPass = _newPasswordCtrl.text;
    final confirmPass = _confirmPasswordCtrl.text;

    if (currentPass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your current (existing) password.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (newPass.isEmpty || confirmPass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill out all new password fields.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (newPass.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New password must be at least 6 characters.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (newPass == currentPass) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New password must be different from your existing password.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (newPass != confirmPass) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New passwords do not match.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isUpdatingPassword = true);

    try {
      await _settingsService.changePassword(
        currentPassword: currentPass,
        newPassword: newPass,
      );
      _currentPasswordCtrl.clear();
      _newPasswordCtrl.clear();
      _confirmPasswordCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Password updated successfully! Please use your new password next time you log in.'),
            backgroundColor: Color(0xFF2D6A4F),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      final errorMsg = e
          .toString()
          .replaceAll('Exception: ', '')
          .replaceAll('AuthException: ', '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update password: $errorMsg'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingPassword = false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  TAB 5: APPEARANCE
  // ═══════════════════════════════════════════════════════════
  Widget _buildAppearanceTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Theme Mode Switcher Card
          Card(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Color Theme Mode',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Select light or dark interface theme for the administration console:',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      // Light Mode Card
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            _settingsService.setThemeMode(ThemeMode.light);
                            setState(() {});
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: !isDark
                                    ? const Color(0xFF2D6A4F)
                                    : Colors.grey.shade300,
                                width: !isDark ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.light_mode,
                                  color: !isDark
                                      ? const Color(0xFF2D6A4F)
                                      : Colors.grey.shade600,
                                  size: 26,
                                ),
                                const SizedBox(width: 14),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Light Theme',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: !isDark
                                            ? const Color(0xFF2D6A4F)
                                            : Colors.black87,
                                      ),
                                    ),
                                    Text(
                                      'Clean crisp government styling',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Dark Mode Card
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            _settingsService.setThemeMode(ThemeMode.dark);
                            setState(() {});
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF2D6A4F)
                                    : Colors.grey.shade700,
                                width: isDark ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.dark_mode,
                                  color: isDark
                                      ? const Color(0xFF2D6A4F)
                                      : Colors.grey.shade400,
                                  size: 26,
                                ),
                                const SizedBox(width: 14),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Dark Theme',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: isDark
                                            ? const Color(0xFF40916C)
                                            : Colors.white,
                                      ),
                                    ),
                                    const Text(
                                      'Sleek deep slate color scheme',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white54,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // City Logo & Header Customization Card
          Card(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Header Branding & City Logo',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Customize the logo and title text displayed on the top sidebar of the application:',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Header Text Inputs
                  TextField(
                    controller: _headerTitleCtrl,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: const [WordsCapitalizationFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Header Title Text',
                      hintText: 'Tabaco City Slaughterhouse',
                      prefixIcon: Icon(Icons.title),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _headerSubtitleCtrl,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: const [WordsCapitalizationFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Header Subtitle Text',
                      hintText: 'Management System',
                      prefixIcon: Icon(Icons.subtitles_outlined),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Logo Selection
                  Text(
                    'Select City Logo Asset:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // Logo 1
                      InkWell(
                        onTap: () =>
                            setState(() => _selectedLogoPath = 'assets/images/logo1.png'),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _selectedLogoPath == 'assets/images/logo1.png'
                                  ? const Color(0xFF2D6A4F)
                                  : Colors.grey.shade300,
                              width: _selectedLogoPath == 'assets/images/logo1.png'
                                  ? 2
                                  : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Image.asset('assets/images/logo1.png',
                                  width: 50, height: 50),
                              const SizedBox(height: 6),
                              const Text('Official Seal',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Logo 2
                      InkWell(
                        onTap: () =>
                            setState(() => _selectedLogoPath = 'assets/images/logo2.png'),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _selectedLogoPath == 'assets/images/logo2.png'
                                  ? const Color(0xFF2D6A4F)
                                  : Colors.grey.shade300,
                              width: _selectedLogoPath == 'assets/images/logo2.png'
                                  ? 2
                                  : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Image.asset('assets/images/logo2.png',
                                  width: 50, height: 50),
                              const SizedBox(height: 6),
                              const Text('Alt Badge',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Actions
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          _settingsService.updateAppearance(
                            headerTitle: _headerTitleCtrl.text.trim(),
                            headerSubtitle: _headerSubtitleCtrl.text.trim(),
                            cityLogoPath: _selectedLogoPath,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Appearance updated successfully!'),
                              backgroundColor: Color(0xFF2D6A4F),
                            ),
                          );
                        },
                        icon: const Icon(Icons.save, size: 18),
                        label: const Text('Save Appearance Settings'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2D6A4F),
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 14),
                      OutlinedButton.icon(
                        onPressed: () {
                          _settingsService.resetAppearance();
                          setState(() {
                            _headerTitleCtrl.text = _settingsService.headerTitle;
                            _headerSubtitleCtrl.text = _settingsService.headerSubtitle;
                            _selectedLogoPath = _settingsService.cityLogoPath;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Reset appearance to defaults.'),
                              backgroundColor: Color(0xFF475569),
                            ),
                          );
                        },
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Reset Defaults'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  5. CUSTOMER ACCOUNTS TAB (Registered Mobile Users)
  // ═══════════════════════════════════════════════════════════
  Future<void> _loadCustomerAccounts() async {
    if (mounted) setState(() => _loadingCustomers = true);
    try {
      final client = Supabase.instance.client;
      final profilesData = await client
          .from('profiles')
          .select()
          .order('created_at', ascending: false);

      const staffRoles = {'admin', 'inspector', 'cashier', 'clerk', 'staff'};
      final customers = <Map<String, dynamic>>[];

      // Also fetch request counts & latest barangay/market per user
      final Map<String, Map<String, dynamic>> reqStats = {};
      try {
        final reqs = await client
            .from('requests')
            .select('user_id, request_type, barangay, market_name, stall_number, marking_tag');
        for (final r in List<Map<String, dynamic>>.from(reqs)) {
          final uid = r['user_id']?.toString() ?? '';
          if (uid.isEmpty) continue;
          final entry = reqStats.putIfAbsent(uid, () => {'count': 0});
          entry['count'] = (entry['count'] as int) + 1;
          entry['request_type'] ??= r['request_type'];
          entry['barangay'] ??= r['barangay'];
          entry['market_name'] ??= r['market_name'];
          entry['stall_number'] ??= r['stall_number'];
          entry['marking_tag'] ??= r['marking_tag'];
        }
      } catch (_) {}

      for (final p in List<Map<String, dynamic>>.from(profilesData)) {
        final role = (p['role'] ?? '').toString().toLowerCase().trim();
        if (staffRoles.contains(role)) continue;
        final uid = p['id']?.toString() ?? '';
        final stats = reqStats[uid];
        customers.add({
          ...p,
          '_request_count': stats?['count'] ?? 0,
          '_req_type': stats?['request_type'],
          '_req_barangay': stats?['barangay'],
          '_req_market': stats?['market_name'],
          '_req_stall': stats?['stall_number'],
          '_req_marking': stats?['marking_tag'],
        });
      }

      if (mounted) {
        setState(() {
          _customerAccounts = customers;
          _loadingCustomers = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading customer accounts: $e');
      if (mounted) setState(() => _loadingCustomers = false);
    }
  }

  String _resolveDealerRoleLabel(Map<String, dynamic> c) {
    final confirmed = c['role_confirmed'] == true;
    final cat = (c['dealer_category'] ?? c['_req_type'] ?? '').toString().toLowerCase().trim();
    if (!confirmed && c['_req_type'] == null) {
      return 'Role Not Selected Yet';
    }
    if (cat == 'market') return 'Market Dealer';
    if (cat == 'barangay') return 'Barangay Dealer';
    return 'Role Not Selected Yet';
  }

  String _resolveDealerLocation(Map<String, dynamic> c) {
    final market = (c['_req_market'] ?? '').toString().trim();
    final stall = (c['_req_stall'] ?? '').toString().trim();
    final brgy = (c['_req_barangay'] ?? '').toString().trim();
    final addr = (c['address'] ?? '').toString().trim();
    if (market.isNotEmpty) {
      return stall.isNotEmpty ? '$market (Stall $stall)' : market;
    }
    if (brgy.isNotEmpty) return brgy;
    if (addr.isNotEmpty) return addr;
    return 'No location provided yet';
  }

  Future<void> _toggleCustomerActive(Map<String, dynamic> customer) async {
    final id = customer['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final currentlyActive = customer['is_active'] != false;
    final name = (customer['display_name'] ?? customer['phone'] ?? customer['email'] ?? 'this customer').toString();

    String? reason;
    if (currentlyActive) {
      final reasonCtrl = TextEditingController(text: 'Accumulated multiple penalties');
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Deactivate $name?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Deactivating blocks this customer from logging in or submitting new slaughter requests.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reason (shown to customer)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706), foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Deactivate'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      reason = reasonCtrl.text.trim().isEmpty ? 'Deactivated by Admin' : reasonCtrl.text.trim();
    }

    try {
      await Supabase.instance.client.from('profiles').update({
        'is_active': !currentlyActive,
        'deactivated_at': currentlyActive ? DateTime.now().toUtc().toIso8601String() : null,
        'deactivation_reason': currentlyActive ? reason : null,
      }).eq('id', id);

      await _loadCustomerAccounts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(currentlyActive
                ? '$name has been deactivated.'
                : '$name has been reactivated.'),
            backgroundColor: currentlyActive ? const Color(0xFFD97706) : const Color(0xFF16A34A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update status: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteCustomerAccount(Map<String, dynamic> customer) async {
    final id = customer['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final name = (customer['display_name'] ?? customer['phone'] ?? customer['email'] ?? 'this customer').toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Customer Account?'),
        content: Text(
          'Permanently delete $name? Their profile and authentication login will be removed and they will no longer be able to sign in.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Supabase.instance.client.from('profiles').delete().eq('id', id);
      await _loadCustomerAccounts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name deleted permanently.'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete customer: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildCustomerAccountsTab(bool isDark) {
    final all = _customerAccounts ?? <Map<String, dynamic>>[];
    final activeCount = all.where((c) => c['is_active'] != false).length;
    final deactivatedCount = all.length - activeCount;

    final filtered = all.where((c) {
      final isActive = c['is_active'] != false;
      if (_customerStatusFilter == 'active' && !isActive) return false;
      if (_customerStatusFilter == 'deactivated' && isActive) return false;
      if (_customerSearchQuery.isNotEmpty) {
        final q = _customerSearchQuery.toLowerCase();
        final name = (c['display_name'] ?? '').toString().toLowerCase();
        final email = (c['email'] ?? '').toString().toLowerCase();
        final phone = (c['phone'] ?? '').toString().toLowerCase();
        final addr = _resolveDealerLocation(c).toLowerCase();
        final role = _resolveDealerRoleLabel(c).toLowerCase();
        if (!name.contains(q) && !email.contains(q) && !phone.contains(q) && !addr.contains(q) && !role.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderCol = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final textCol = isDark ? Colors.white : const Color(0xFF0F172A);
    final subCol = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Registered Mobile Customers',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: textCol),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Monitor newly signed-up mobile app users, their selected dealer role & location, and deactivate or remove accounts.',
                      style: TextStyle(fontSize: 13, color: subCol),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _loadingCustomers ? null : _loadCustomerAccounts,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _customerStatChip('Total Registered', all.length.toString(), const Color(0xFF0284C7), cardBg, borderCol, textCol, subCol),
              _customerStatChip('Active Accounts', activeCount.toString(), const Color(0xFF16A34A), cardBg, borderCol, textCol, subCol),
              _customerStatChip('Deactivated', deactivatedCount.toString(), const Color(0xFFD97706), cardBg, borderCol, textCol, subCol),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customerSearchCtrl,
                  onChanged: (v) => setState(() => _customerSearchQuery = v.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search by name, phone, email, barangay/market, or role...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    filled: true,
                    fillColor: cardBg,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderCol)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderCol)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'all', label: Text('All')),
                  ButtonSegment(value: 'active', label: Text('Active')),
                  ButtonSegment(value: 'deactivated', label: Text('Deactivated')),
                ],
                selected: {_customerStatusFilter},
                onSelectionChanged: (s) => setState(() => _customerStatusFilter = s.first),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loadingCustomers)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          else if (filtered.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderCol)),
              child: Center(
                child: Text(
                  all.isEmpty ? 'No mobile customers registered yet.' : 'No customers match your search/filter.',
                  style: TextStyle(color: subCol, fontSize: 14),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final c = filtered[index];
                final isActive = c['is_active'] != false;
                final name = (c['display_name'] ?? '').toString().trim().isNotEmpty
                    ? c['display_name'].toString()
                    : 'Unnamed Customer';
                final contact = [
                  if ((c['phone'] ?? '').toString().trim().isNotEmpty) c['phone'].toString().trim(),
                  if ((c['email'] ?? '').toString().trim().isNotEmpty) c['email'].toString().trim(),
                ].join(' • ');
                final roleLabel = _resolveDealerRoleLabel(c);
                final location = _resolveDealerLocation(c);
                final reqCount = (c['_request_count'] as int?) ?? 0;
                final reason = (c['deactivation_reason'] ?? '').toString().trim();

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isActive ? borderCol : const Color(0xFFF59E0B).withValues(alpha: 0.6)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: isActive ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                        child: Icon(
                          isActive ? Icons.person_outline : Icons.block,
                          color: isActive ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textCol)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: roleLabel == 'Role Not Selected Yet'
                                        ? const Color(0xFFF1F5F9)
                                        : const Color(0xFFE0F2FE),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    roleLabel,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: roleLabel == 'Role Not Selected Yet'
                                          ? const Color(0xFF64748B)
                                          : const Color(0xFF0369A1),
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isActive ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isActive ? 'Active' : 'Deactivated',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: isActive ? const Color(0xFF15803D) : const Color(0xFFB45309),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (contact.isNotEmpty)
                              Text(contact, style: TextStyle(fontSize: 12.5, color: subCol)),
                            const SizedBox(height: 4),
                            Text(
                              'Location: $location  •  Requests: $reqCount',
                              style: TextStyle(fontSize: 12, color: subCol),
                            ),
                            if (!isActive && reason.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Deactivation reason: $reason',
                                style: const TextStyle(fontSize: 12, color: Color(0xFFD97706), fontWeight: FontWeight.w600),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _toggleCustomerActive(c),
                            icon: Icon(isActive ? Icons.pause_circle_outline : Icons.check_circle_outline, size: 16),
                            label: Text(isActive ? 'Deactivate' : 'Reactivate'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isActive ? const Color(0xFFD97706) : const Color(0xFF16A34A),
                              side: BorderSide(color: isActive ? const Color(0xFFD97706) : const Color(0xFF16A34A)),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _deleteCustomerAccount(c),
                            icon: const Icon(Icons.delete_outline, size: 16),
                            label: const Text('Delete'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFDC2626),
                              side: const BorderSide(color: Color(0xFFDC2626)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _customerStatChip(String label, String value, Color accent, Color bg, Color border, Color textCol, Color subCol) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: subCol, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: accent)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  6. CUSTOMER REVIEWS & FEEDBACK TAB
  // ═══════════════════════════════════════════════════════════
  Widget _buildCustomerReviewsTab(bool isDark) {
    final reviews = _adminReviews ?? <Map<String, dynamic>>[];
    final filteredReviews = reviews.where((r) {
      if (_selectedStarFilter != null) {
        final rating = (r['rating'] as num?)?.toInt() ?? 0;
        if (rating != _selectedStarFilter) return false;
      }
      if (_reviewSearchQuery.isNotEmpty) {
        final q = _reviewSearchQuery.toLowerCase();
        final name = (r['reviewer_name'] ?? '').toString().toLowerCase();
        final comment = (r['comment'] ?? '').toString().toLowerCase();
        final service = (r['service_type'] ?? '').toString().toLowerCase();
        if (!name.contains(q) && !comment.contains(q) && !service.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header Card ──
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Customer Reviews & In-App Feedback',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Reviews submitted by registered mobile app customers. Blended dynamically with order completion rates for the official public satisfaction index.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _loadingReviews ? null : _loadAdminReviews,
                icon: _loadingReviews
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2D6A4F),
                  side: const BorderSide(color: Color(0xFF2D6A4F)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Top Summary Cards (Responsive) ──
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 850;
              final cards = [
                _buildReviewMetricCard(
                  isDark: isDark,
                  title: 'Average Customer Rating',
                  value: _reviewAverageRating > 0
                      ? _reviewAverageRating.toStringAsFixed(1)
                      : '0.0',
                  subtitle: '${reviews.length} customer ${reviews.length == 1 ? "review" : "reviews"} recorded',
                  extraWidget: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(5, (index) {
                      final starVal = index + 1;
                      return Icon(
                        starVal <= _reviewAverageRating.round()
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: const Color(0xFFF59E0B),
                        size: 20,
                      );
                    }),
                  ),
                ),
                _buildStarDistributionCard(isDark),
                _buildSatisfactionCard(isDark),
              ];

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 16),
                    Expanded(child: cards[1]),
                    const SizedBox(width: 16),
                    Expanded(child: cards[2]),
                  ],
                );
              } else {
                return Column(
                  children: [
                    cards[0],
                    const SizedBox(height: 14),
                    cards[1],
                    const SizedBox(height: 14),
                    cards[2],
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 24),

          // ── Filter & Search Toolbar Card ──
          Card(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Search input
                      Expanded(
                        child: TextField(
                          controller: _reviewSearchCtrl,
                          onChanged: (val) {
                            setState(() => _reviewSearchQuery = val.trim());
                          },
                          decoration: InputDecoration(
                            hintText: 'Search by customer name, comment, or service...',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade400,
                            ),
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: _reviewSearchCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close, size: 16),
                                    onPressed: () {
                                      _reviewSearchCtrl.clear();
                                      setState(() => _reviewSearchQuery = '');
                                    },
                                  )
                                : null,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            filled: true,
                            fillColor: isDark
                                ? const Color(0xFF0F172A)
                                : const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: isDark
                                    ? const Color(0xFF334155)
                                    : Colors.grey.shade300,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: isDark
                                    ? const Color(0xFF334155)
                                    : Colors.grey.shade300,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFF2D6A4F),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Star Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Text(
                          'Filter by rating: ',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStarFilterChip(
                          label: 'All (${reviews.length})',
                          isSelected: _selectedStarFilter == null,
                          onTap: () => setState(() => _selectedStarFilter = null),
                          isDark: isDark,
                        ),
                        const SizedBox(width: 6),
                        ...[5, 4, 3, 2, 1].map((stars) {
                          final counts = _reviewRatingCounts ?? {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
                          final count = counts[stars] ?? 0;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _buildStarFilterChip(
                              label: '$stars ★ ($count)',
                              isSelected: _selectedStarFilter == stars,
                              onTap: () {
                                setState(() {
                                  _selectedStarFilter =
                                      _selectedStarFilter == stars ? null : stars;
                                });
                              },
                              isDark: isDark,
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Reviews List Section ──
          if (_loadingReviews)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF2D6A4F)),
              ),
            )
          else if (filteredReviews.isEmpty)
            Card(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 54, horizontal: 20),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.rate_review_outlined,
                        size: 56,
                        color: isDark ? const Color(0xFF475569) : Colors.grey.shade400,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        reviews.isEmpty
                            ? 'No customer reviews submitted yet'
                            : 'No customer reviews match your filters',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        reviews.isEmpty
                            ? 'Customer reviews submitted through the mobile app will be displayed and audited here.'
                            : 'Try adjusting your search terms or star rating filter to view more reviews.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Column(
              children: filteredReviews.map((review) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _buildReviewCard(review, isDark),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildStarFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF2D6A4F)
              : (isDark ? const Color(0xFF0F172A) : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF2D6A4F)
                : (isDark ? const Color(0xFF334155) : Colors.grey.shade300),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
          ),
        ),
      ),
    );
  }

  Widget _buildReviewMetricCard({
    required bool isDark,
    required String title,
    required String value,
    required String subtitle,
    Widget? extraWidget,
  }) {
    return Card(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                if (value != '0.0') ...[
                  const SizedBox(width: 4),
                  Text(
                    '/ 5.0',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade500,
                    ),
                  ),
                ],
              ],
            ),
            if (extraWidget != null) ...[
              const SizedBox(height: 6),
              extraWidget,
            ],
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStarDistributionCard(bool isDark) {
    final reviews = _adminReviews ?? [];
    final counts = _reviewRatingCounts ?? {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
    final total = reviews.length;
    return Card(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rating Breakdown',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            ...[5, 4, 3, 2, 1].map((star) {
              final count = counts[star] ?? 0;
              final percent = total > 0 ? (count / total) : 0.0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        '$star★',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xFFCBD5E1) : Colors.grey.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: percent,
                          minHeight: 6,
                          backgroundColor: isDark
                              ? const Color(0xFF334155)
                              : Colors.grey.shade200,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFFF59E0B),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 24,
                      child: Text(
                        '$count',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSatisfactionCard(bool isDark) {
    final compRate = _reviewTotalOrdersCount > 0
        ? (_reviewCompletedOrdersCount / _reviewTotalOrdersCount) * 100.0
        : 0.0;
    final reviewPct = (_reviewAverageRating / 5.0) * 100.0;

    return Card(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'Public Satisfaction Index',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D6A4F).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Live Formula',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2D6A4F),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${_reviewBlendedSatisfaction.toStringAsFixed(0)}%',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: Color(0xFF2D6A4F),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '50% Customer Reviews (${reviewPct.toStringAsFixed(0)}%) + 50% Completed Orders (${compRate.toStringAsFixed(0)}%)',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Automatically synchronized with the Dashboard KPI card.',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: isDark ? const Color(0xFF64748B) : Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review, bool isDark) {
    final name = (review['reviewer_name'] ?? 'Verified Customer').toString();
    final rating = (review['rating'] as num?)?.toInt() ?? 5;
    final comment = (review['comment'] ?? '').toString().trim();
    final service = (review['service_type'] ?? '').toString().trim();
    final helpfulCount = (review['helpful_count'] as num?)?.toInt() ?? 0;

    String dateStr = 'Recently';
    if (review['created_at'] != null) {
      final parsed = DateTime.tryParse(review['created_at'].toString());
      if (parsed != null) {
        dateStr = DateFormat('MMM d, yyyy • h:mm a').format(parsed.toLocal());
      }
    }

    // Customer initials
    final initials = _extractInitials(name);

    return Card(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Reviewer Info Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFF2D6A4F).withValues(alpha: 0.12),
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2D6A4F),
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2D6A4F).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle, size: 11, color: Color(0xFF2D6A4F)),
                                SizedBox(width: 3),
                                Text(
                                  'Customer App',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF2D6A4F),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(5, (idx) {
                              return Icon(
                                idx < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                                color: const Color(0xFFF59E0B),
                                size: 16,
                              );
                            }),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Service tag
                if (service.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF334155)
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 13,
                          color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade700,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          service,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFFCBD5E1) : Colors.grey.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            // Comment text bubble
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
                ),
              ),
              child: Text(
                comment.isNotEmpty ? comment : 'No written feedback provided.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  fontStyle: comment.isEmpty ? FontStyle.italic : FontStyle.normal,
                  color: comment.isEmpty
                      ? (isDark ? const Color(0xFF64748B) : Colors.grey.shade500)
                      : (isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155)),
                ),
              ),
            ),

            // Footer row (helpful counts & audit ID)
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.thumb_up_alt_outlined,
                  size: 14,
                  color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade500,
                ),
                const SizedBox(width: 4),
                Text(
                  '$helpfulCount people found this helpful',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade500,
                  ),
                ),
                const Spacer(),
                if (review['id'] != null)
                  Text(
                    'Review #${review['id']}',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: isDark ? const Color(0xFF64748B) : Colors.grey.shade400,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _extractInitials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'C';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return trimmed.substring(0, 1).toUpperCase();
  }
}

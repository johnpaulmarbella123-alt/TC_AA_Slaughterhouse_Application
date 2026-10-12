import 'package:flutter/material.dart';
import '../services/app_settings_service.dart';

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

  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentTabIndex = widget.initialTab.clamp(0, 4);
    _tabController = TabController(
      length: 5,
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
      final target = widget.initialTab.clamp(0, 4);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
      {'key': 'poultry', 'label': 'Poultry (Fowl)', 'icon': '🐔'},
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
      'Receiving Clerk',
      'Document Verifier',
      'Inspector',
      'Cashier',
      'Releasing Officer',
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Role Simulation / Quick Role Switcher Banner
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
                        'Active Session Role Switcher (Preview Mode)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Switch the active account role to test module visibility in the sidebar. For example, Cashier sees only Dashboard & Payment, while Inspector sees only Dashboard & Slaughter.',
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
                  value: _settingsService.currentRole,
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
                              'Active role switched to "$newRole". Sidebar modules updated accordingly!'),
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
                    'Manage employee user accounts and their operational module access.',
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
                    'Specifies the operational modules visible in the left sidebar for each role:',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildMatrixRow('Admin', 'All Modules + Settings & Configuration', isDark),
                  _buildMatrixRow('Receiving Clerk', 'Dashboard, Receiving & New Requests, My Profile', isDark),
                  _buildMatrixRow('Document Verifier', 'Dashboard, Document Verification, My Profile', isDark),
                  _buildMatrixRow('Inspector', 'Dashboard, Slaughter & Inspection, My Profile', isDark),
                  _buildMatrixRow('Cashier', 'Dashboard, Payment & Cashiering, My Profile', isDark),
                  _buildMatrixRow('Releasing Officer', 'Dashboard, Meat Releasing, My Profile', isDark),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'Admin':
        return const Color(0xFF2D6A4F);
      case 'Receiving Clerk':
        return const Color(0xFF7C3AED);
      case 'Document Verifier':
        return const Color(0xFFD97706);
      case 'Inspector':
        return const Color(0xFF2563EB);
      case 'Cashier':
        return const Color(0xFF059669);
      case 'Releasing Officer':
        return const Color(0xFF0891B2);
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
    String selectedRole = 'Inspector';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          title: const Text('Add Staff Member'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Full Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email Address'),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: const InputDecoration(labelText: 'Assigned Role'),
                  items: [
                    'Admin',
                    'Receiving Clerk',
                    'Document Verifier',
                    'Inspector',
                    'Cashier',
                    'Releasing Officer',
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
                if (name.isNotEmpty && email.isNotEmpty) {
                  final newStaff = StaffAccount(
                    id: 'staff-${DateTime.now().millisecondsSinceEpoch}',
                    fullName: name,
                    email: email,
                    role: selectedRole,
                    createdAt: DateTime.now(),
                  );
                  Navigator.pop(ctx);
                  await _settingsService.addStaffAccount(newStaff);
                  if (mounted) {
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Added $name as $selectedRole and saved to cloud database!'),
                        backgroundColor: const Color(0xFF2D6A4F),
                      ),
                    );
                  }
                }
              },
              child: const Text('Add Staff'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaffRow(StaffAccount staff, bool isDark, List<String> rolesList) {
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
              value: staff.role,
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
          const SizedBox(width: 8),
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
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _maxPoultryCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Max Poultry / Day',
                            prefixText: '🐔 ',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _noticeMsgCtrl,
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
                            'Authenticated Admin: ${_settingsService.profileEmail}',
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
                    decoration: const InputDecoration(
                      labelText: 'Header Title Text',
                      hintText: 'Tabaco City Slaughterhouse',
                      prefixIcon: Icon(Icons.title),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _headerSubtitleCtrl,
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
}

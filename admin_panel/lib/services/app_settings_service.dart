import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ═══════════════════════════════════════════════════════════
//  MODEL: ANIMAL FEE SCHEDULE
// ═══════════════════════════════════════════════════════════
class AnimalFeeSchedule {
  final String animalType; // 'hog', 'cattle', 'carabao', 'goat', 'sheep'
  double facilityFee; // Slaughter / Facility fee
  double permitToSlaughterFee;
  double vetHealthCertFee;
  double corralFee;
  double anteMortemFee;
  double postMortemRatePerKg;
  double deliveryVanFee;
  double additionalFee;
  String additionalFeeLabel;

  AnimalFeeSchedule({
    required this.animalType,
    required this.facilityFee,
    required this.permitToSlaughterFee,
    required this.vetHealthCertFee,
    required this.corralFee,
    required this.anteMortemFee,
    required this.postMortemRatePerKg,
    required this.deliveryVanFee,
    this.additionalFee = 0.0,
    this.additionalFeeLabel = 'Additional Regulatory Surcharge',
  });

  Map<String, dynamic> toJson() => {
        'animalType': animalType,
        'facilityFee': facilityFee,
        'permitToSlaughterFee': permitToSlaughterFee,
        'vetHealthCertFee': vetHealthCertFee,
        'corralFee': corralFee,
        'anteMortemFee': anteMortemFee,
        'postMortemRatePerKg': postMortemRatePerKg,
        'deliveryVanFee': deliveryVanFee,
        'additionalFee': additionalFee,
        'additionalFeeLabel': additionalFeeLabel,
      };

  factory AnimalFeeSchedule.fromJson(Map<String, dynamic> json) =>
      AnimalFeeSchedule(
        animalType: (json['animalType'] ?? 'hog').toString().toLowerCase(),
        facilityFee: (json['facilityFee'] as num?)?.toDouble() ?? 60.0,
        permitToSlaughterFee:
            (json['permitToSlaughterFee'] as num?)?.toDouble() ?? 60.0,
        vetHealthCertFee:
            (json['vetHealthCertFee'] as num?)?.toDouble() ?? 50.0,
        corralFee: (json['corralFee'] as num?)?.toDouble() ?? 40.0,
        anteMortemFee: (json['anteMortemFee'] as num?)?.toDouble() ?? 40.0,
        postMortemRatePerKg:
            (json['postMortemRatePerKg'] as num?)?.toDouble() ?? 5.0,
        deliveryVanFee: (json['deliveryVanFee'] as num?)?.toDouble() ?? 60.0,
        additionalFee: (json['additionalFee'] as num?)?.toDouble() ?? 0.0,
        additionalFeeLabel: json['additionalFeeLabel']?.toString() ??
            'Additional Regulatory Surcharge',
      );

  AnimalFeeSchedule copyWith({
    double? facilityFee,
    double? permitToSlaughterFee,
    double? vetHealthCertFee,
    double? corralFee,
    double? anteMortemFee,
    double? postMortemRatePerKg,
    double? deliveryVanFee,
    double? additionalFee,
    String? additionalFeeLabel,
  }) {
    return AnimalFeeSchedule(
      animalType: animalType,
      facilityFee: facilityFee ?? this.facilityFee,
      permitToSlaughterFee: permitToSlaughterFee ?? this.permitToSlaughterFee,
      vetHealthCertFee: vetHealthCertFee ?? this.vetHealthCertFee,
      corralFee: corralFee ?? this.corralFee,
      anteMortemFee: anteMortemFee ?? this.anteMortemFee,
      postMortemRatePerKg: postMortemRatePerKg ?? this.postMortemRatePerKg,
      deliveryVanFee: deliveryVanFee ?? this.deliveryVanFee,
      additionalFee: additionalFee ?? this.additionalFee,
      additionalFeeLabel: additionalFeeLabel ?? this.additionalFeeLabel,
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  MODEL: STAFF ACCOUNT
// ═══════════════════════════════════════════════════════════
class StaffAccount {
  final String id;
  String fullName;
  String email;
  String role; // 'Admin', 'Receiving Clerk', 'Document Verifier', 'Inspector', 'Cashier', 'Releasing Officer'
  bool isActive;
  DateTime createdAt;
  String? avatarUrl;

  StaffAccount({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    this.isActive = true,
    required this.createdAt,
    this.avatarUrl,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fullName': fullName,
        'email': email,
        'role': role,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
        'avatarUrl': avatarUrl,
      };

  factory StaffAccount.fromJson(Map<String, dynamic> json) => StaffAccount(
        id: json['id']?.toString() ?? UniqueKey().toString(),
        fullName: json['fullName']?.toString() ?? 'Staff Member',
        email: json['email']?.toString() ?? '',
        role: json['role']?.toString() ?? 'Admin',
        isActive: json['isActive'] as bool? ?? true,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
        avatarUrl: json['avatarUrl']?.toString(),
      );
}

// ═══════════════════════════════════════════════════════════
//  MODEL: SLAUGHTER SCHEDULE & CAPACITY
// ═══════════════════════════════════════════════════════════
class SlaughterScheduleCapacity {
  List<String> operatingDays;
  String openingTime; // '05:00'
  String closingTime; // '17:00'
  String cutoffTime; // '15:00'
  int maxHeadsPerDay;
  int maxHogPerDay;
  int maxCattlePerDay;
  int maxCarabaoPerDay;
  int maxGoatPerDay;
  int maxPoultryPerDay;
  bool isOperational;
  String noticeMessage;

  SlaughterScheduleCapacity({
    required this.operatingDays,
    required this.openingTime,
    required this.closingTime,
    required this.cutoffTime,
    required this.maxHeadsPerDay,
    required this.maxHogPerDay,
    required this.maxCattlePerDay,
    required this.maxCarabaoPerDay,
    required this.maxGoatPerDay,
    this.maxPoultryPerDay = 50,
    this.isOperational = true,
    this.noticeMessage = 'Standard operating schedule active.',
  });

  Map<String, dynamic> toJson() => {
        'operatingDays': operatingDays,
        'openingTime': openingTime,
        'closingTime': closingTime,
        'cutoffTime': cutoffTime,
        'maxHeadsPerDay': maxHeadsPerDay,
        'maxHogPerDay': maxHogPerDay,
        'maxCattlePerDay': maxCattlePerDay,
        'maxCarabaoPerDay': maxCarabaoPerDay,
        'maxGoatPerDay': maxGoatPerDay,
        'maxPoultryPerDay': maxPoultryPerDay,
        'isOperational': isOperational,
        'noticeMessage': noticeMessage,
      };

  factory SlaughterScheduleCapacity.fromJson(Map<String, dynamic> json) =>
      SlaughterScheduleCapacity(
        operatingDays: (json['operatingDays'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'],
        openingTime: json['openingTime']?.toString() ?? '05:00',
        closingTime: json['closingTime']?.toString() ?? '17:00',
        cutoffTime: json['cutoffTime']?.toString() ?? '15:00',
        maxHeadsPerDay: (json['maxHeadsPerDay'] as num?)?.toInt() ?? 100,
        maxHogPerDay: (json['maxHogPerDay'] as num?)?.toInt() ?? 60,
        maxCattlePerDay: (json['maxCattlePerDay'] as num?)?.toInt() ?? 20,
        maxCarabaoPerDay: (json['maxCarabaoPerDay'] as num?)?.toInt() ?? 10,
        maxGoatPerDay: (json['maxGoatPerDay'] as num?)?.toInt() ?? 10,
        maxPoultryPerDay: (json['maxPoultryPerDay'] as num?)?.toInt() ?? 50,
        isOperational: json['isOperational'] as bool? ?? true,
        noticeMessage: json['noticeMessage']?.toString() ??
            'Standard operating schedule active.',
      );
}

// ═══════════════════════════════════════════════════════════
//  APP SETTINGS SERVICE (SINGLETON & CHANGENOTIFIER)
// ═══════════════════════════════════════════════════════════
class AppSettingsService extends ChangeNotifier {
  static final AppSettingsService _instance = AppSettingsService._internal();
  static AppSettingsService get instance => _instance;

  AppSettingsService._internal();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  // 1. Fees & Rates per animal type
  final Map<String, AnimalFeeSchedule> _feeSchedules = {
    'hog': AnimalFeeSchedule(
      animalType: 'hog',
      facilityFee: 60.0,
      permitToSlaughterFee: 60.0,
      vetHealthCertFee: 50.0,
      corralFee: 40.0,
      anteMortemFee: 40.0,
      postMortemRatePerKg: 5.0,
      deliveryVanFee: 60.0,
    ),
    'cattle': AnimalFeeSchedule(
      animalType: 'cattle',
      facilityFee: 120.0,
      permitToSlaughterFee: 80.0,
      vetHealthCertFee: 50.0,
      corralFee: 60.0,
      anteMortemFee: 50.0,
      postMortemRatePerKg: 6.0,
      deliveryVanFee: 100.0,
    ),
    'carabao': AnimalFeeSchedule(
      animalType: 'carabao',
      facilityFee: 120.0,
      permitToSlaughterFee: 80.0,
      vetHealthCertFee: 50.0,
      corralFee: 60.0,
      anteMortemFee: 50.0,
      postMortemRatePerKg: 6.0,
      deliveryVanFee: 100.0,
    ),
    'goat': AnimalFeeSchedule(
      animalType: 'goat',
      facilityFee: 40.0,
      permitToSlaughterFee: 40.0,
      vetHealthCertFee: 30.0,
      corralFee: 25.0,
      anteMortemFee: 25.0,
      postMortemRatePerKg: 4.0,
      deliveryVanFee: 40.0,
      additionalFee: 0.0,
      additionalFeeLabel: 'Additional Regulatory Surcharge',
    ),
    'sheep': AnimalFeeSchedule(
      animalType: 'sheep',
      facilityFee: 40.0,
      permitToSlaughterFee: 40.0,
      vetHealthCertFee: 30.0,
      corralFee: 25.0,
      anteMortemFee: 25.0,
      postMortemRatePerKg: 4.0,
      deliveryVanFee: 40.0,
      additionalFee: 0.0,
      additionalFeeLabel: 'Additional Regulatory Surcharge',
    ),
    'poultry': AnimalFeeSchedule(
      animalType: 'poultry',
      facilityFee: 20.0,
      permitToSlaughterFee: 20.0,
      vetHealthCertFee: 15.0,
      corralFee: 10.0,
      anteMortemFee: 10.0,
      postMortemRatePerKg: 2.5,
      deliveryVanFee: 25.0,
      additionalFee: 0.0,
      additionalFeeLabel: 'Additional Regulatory Surcharge',
    ),
  };

  Map<String, AnimalFeeSchedule> get feeSchedules =>
      Map.unmodifiable(_feeSchedules);

  AnimalFeeSchedule getFeeRatesForAnimal(String? animalType) {
    if (animalType == null) return _feeSchedules['hog']!;
    final normalized = animalType.toLowerCase().trim();
    if (_feeSchedules.containsKey(normalized)) {
      return _feeSchedules[normalized]!;
    }
    // Partial matches
    if (normalized.contains('poultry') ||
        normalized.contains('chicken') ||
        normalized.contains('duck') ||
        normalized.contains('turkey') ||
        normalized.contains('fowl')) {
      return _feeSchedules['poultry']!;
    }
    if (normalized.contains('sheep') || normalized.contains('ovine')) {
      return _feeSchedules['sheep'] ?? _feeSchedules['goat']!;
    }
    if (normalized.contains('goat') || normalized.contains('caprine')) {
      return _feeSchedules['goat']!;
    }
    if (normalized.contains('cat') ||
        normalized.contains('cow') ||
        normalized.contains('bovine')) {
      return _feeSchedules['cattle']!;
    }
    if (normalized.contains('cara') || normalized.contains('buffalo')) {
      return _feeSchedules['carabao']!;
    }
    if (normalized.contains('hog') ||
        normalized.contains('pig') ||
        normalized.contains('swine')) {
      return _feeSchedules['hog']!;
    }
    return _feeSchedules['hog']!;
  }

  Future<void> updateFeeSchedule(AnimalFeeSchedule schedule) async {
    _feeSchedules[schedule.animalType.toLowerCase()] = schedule;
    notifyListeners();
    await _saveFeesToPrefs();
  }

  Future<void> resetFeesToDefaults() async {
    _feeSchedules['hog'] = AnimalFeeSchedule(
      animalType: 'hog',
      facilityFee: 60.0,
      permitToSlaughterFee: 60.0,
      vetHealthCertFee: 50.0,
      corralFee: 40.0,
      anteMortemFee: 40.0,
      postMortemRatePerKg: 5.0,
      deliveryVanFee: 60.0,
      additionalFee: 0.0,
      additionalFeeLabel: 'Additional Regulatory Surcharge',
    );
    _feeSchedules['cattle'] = AnimalFeeSchedule(
      animalType: 'cattle',
      facilityFee: 120.0,
      permitToSlaughterFee: 80.0,
      vetHealthCertFee: 50.0,
      corralFee: 60.0,
      anteMortemFee: 50.0,
      postMortemRatePerKg: 6.0,
      deliveryVanFee: 100.0,
      additionalFee: 0.0,
      additionalFeeLabel: 'Additional Regulatory Surcharge',
    );
    _feeSchedules['carabao'] = AnimalFeeSchedule(
      animalType: 'carabao',
      facilityFee: 120.0,
      permitToSlaughterFee: 80.0,
      vetHealthCertFee: 50.0,
      corralFee: 60.0,
      anteMortemFee: 50.0,
      postMortemRatePerKg: 6.0,
      deliveryVanFee: 100.0,
      additionalFee: 0.0,
      additionalFeeLabel: 'Additional Regulatory Surcharge',
    );
    _feeSchedules['goat'] = AnimalFeeSchedule(
      animalType: 'goat',
      facilityFee: 40.0,
      permitToSlaughterFee: 40.0,
      vetHealthCertFee: 30.0,
      corralFee: 25.0,
      anteMortemFee: 25.0,
      postMortemRatePerKg: 4.0,
      deliveryVanFee: 40.0,
      additionalFee: 0.0,
      additionalFeeLabel: 'Additional Regulatory Surcharge',
    );
    _feeSchedules['sheep'] = AnimalFeeSchedule(
      animalType: 'sheep',
      facilityFee: 40.0,
      permitToSlaughterFee: 40.0,
      vetHealthCertFee: 30.0,
      corralFee: 25.0,
      anteMortemFee: 25.0,
      postMortemRatePerKg: 4.0,
      deliveryVanFee: 40.0,
      additionalFee: 0.0,
      additionalFeeLabel: 'Additional Regulatory Surcharge',
    );
    notifyListeners();
    await _saveFeesToPrefs();
  }

  Future<void> _ensureAdminAuth() async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) {
      try {
        await client.auth.signInWithPassword(
          email: 'admin.slaughterhouse@tabaco.gov.ph',
          password: 'AdminPassword123!',
        );
        debugPrint('AppSettingsService: Admin session authenticated.');
      } catch (e) {
        debugPrint('AppSettingsService: Admin auth note: $e');
      }
    }
  }

  Future<void> reloadFromSupabase() async {
    try {
      await _ensureAdminAuth();
      final client = Supabase.instance.client;

      // 1. Reload Fee Schedules
      try {
        final feeRow = await client
            .from('system_settings')
            .select('value')
            .eq('key', 'fee_schedules')
            .maybeSingle();
        if (feeRow != null && feeRow['value'] != null) {
          final rawVal = feeRow['value'];
          final Map<String, dynamic> decoded = rawVal is String
              ? jsonDecode(rawVal) as Map<String, dynamic>
              : Map<String, dynamic>.from(rawVal as Map);
          decoded.forEach((key, val) {
            if (val is Map<String, dynamic>) {
              _feeSchedules[key.toLowerCase()] = AnimalFeeSchedule.fromJson(val);
            } else if (val is Map) {
              _feeSchedules[key.toLowerCase()] =
                  AnimalFeeSchedule.fromJson(Map<String, dynamic>.from(val));
            }
          });
          final prefs = await SharedPreferences.getInstance();
          final map = _feeSchedules.map((k, v) => MapEntry(k, v.toJson()));
          await prefs.setString('app_fees_json', jsonEncode(map));
        }
      } catch (e) {
        debugPrint('reloadFromSupabase fee error: $e');
      }

      // 2. Reload Staff Accounts
      try {
        final staffRow = await client
            .from('system_settings')
            .select('value')
            .eq('key', 'staff_accounts')
            .maybeSingle();
        if (staffRow != null && staffRow['value'] != null) {
          final rawVal = staffRow['value'];
          final List decoded = rawVal is String
              ? jsonDecode(rawVal) as List
              : (rawVal as List);
          _staffAccounts.clear();
          for (var item in decoded) {
            if (item is Map<String, dynamic>) {
              _staffAccounts.add(StaffAccount.fromJson(item));
            } else if (item is Map) {
              _staffAccounts.add(StaffAccount.fromJson(Map<String, dynamic>.from(item)));
            }
          }
          final prefs = await SharedPreferences.getInstance();
          final list = _staffAccounts.map((s) => s.toJson()).toList();
          await prefs.setString('app_staff_json', jsonEncode(list));
          debugPrint('reloadFromSupabase: Loaded ${_staffAccounts.length} staff accounts.');
        }
      } catch (e) {
        debugPrint('reloadFromSupabase staff error: $e');
      }

      // 3. Reload Schedule & Capacity
      try {
        final schedRow = await client
            .from('system_settings')
            .select('value')
            .eq('key', 'schedule_capacity')
            .maybeSingle();
        if (schedRow != null && schedRow['value'] != null) {
          final rawVal = schedRow['value'];
          final Map<String, dynamic> decoded = rawVal is String
              ? jsonDecode(rawVal) as Map<String, dynamic>
              : Map<String, dynamic>.from(rawVal as Map);
          _scheduleCapacity = SlaughterScheduleCapacity.fromJson(decoded);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('app_schedule_json', jsonEncode(_scheduleCapacity.toJson()));
          debugPrint('reloadFromSupabase: Loaded schedule capacity maxHeads=${_scheduleCapacity.maxHeadsPerDay}.');
        }
      } catch (e) {
        debugPrint('reloadFromSupabase schedule error: $e');
      }

      notifyListeners();
    } catch (e) {
      debugPrint('reloadFromSupabase general error: $e');
    }
  }

  // 2. Staff Accounts & Roles
  final List<StaffAccount> _staffAccounts = [
    StaffAccount(
      id: 'staff-1',
      fullName: 'Dr. Roberto Mendoza',
      email: 'admin.mendoza@tabaco.gov.ph',
      role: 'Admin',
      isActive: true,
      createdAt: DateTime(2025, 1, 10),
    ),
    StaffAccount(
      id: 'staff-2',
      fullName: 'Elena Santos',
      email: 'receiving.santos@tabaco.gov.ph',
      role: 'Receiving Clerk',
      isActive: true,
      createdAt: DateTime(2025, 2, 1),
    ),
    StaffAccount(
      id: 'staff-3',
      fullName: 'Mark Angelo Diaz',
      email: 'verifier.diaz@tabaco.gov.ph',
      role: 'Document Verifier',
      isActive: true,
      createdAt: DateTime(2025, 2, 5),
    ),
    StaffAccount(
      id: 'staff-4',
      fullName: 'Dr. Maria Clara Reyes',
      email: 'inspector.reyes@tabaco.gov.ph',
      role: 'Inspector',
      isActive: true,
      createdAt: DateTime(2025, 2, 12),
    ),
    StaffAccount(
      id: 'staff-5',
      fullName: 'Jose Mari Chan',
      email: 'cashier.chan@tabaco.gov.ph',
      role: 'Cashier',
      isActive: true,
      createdAt: DateTime(2025, 2, 15),
    ),
    StaffAccount(
      id: 'staff-6',
      fullName: 'Arthur Pendelton',
      email: 'releasing.arthur@tabaco.gov.ph',
      role: 'Releasing Officer',
      isActive: true,
      createdAt: DateTime(2025, 2, 18),
    ),
  ];

  List<StaffAccount> get staffAccounts => List.unmodifiable(_staffAccounts);

  String _currentRole = 'Admin';
  String get currentRole => _currentRole;

  void setCurrentRole(String role) {
    _currentRole = role;
    notifyListeners();
    _saveProfileToPrefs();
  }

  Future<void> addStaffAccount(StaffAccount staff) async {
    _staffAccounts.add(staff);
    notifyListeners();
    await _saveStaffToPrefs();
  }

  Future<void> toggleStaffStatus(String id) async {
    final idx = _staffAccounts.indexWhere((s) => s.id == id);
    if (idx != -1) {
      _staffAccounts[idx].isActive = !_staffAccounts[idx].isActive;
      notifyListeners();
      await _saveStaffToPrefs();
    }
  }

  Future<void> updateStaffRole(String id, String newRole) async {
    final idx = _staffAccounts.indexWhere((s) => s.id == id);
    if (idx != -1) {
      _staffAccounts[idx].role = newRole;
      notifyListeners();
      await _saveStaffToPrefs();
    }
  }

  Future<void> deleteStaffAccount(String id) async {
    _staffAccounts.removeWhere((s) => s.id == id);
    notifyListeners();
    await _saveStaffToPrefs();
  }

  /// Determines whether a sidebar navigation index is permitted for the active role.
  /// Module indices:
  /// 0: Dashboard
  /// 1: Receiving & New Requests
  /// 2: Document Verification
  /// 3: Slaughter & Inspection
  /// 4: Payment & Cashiering
  /// 5: Meat Releasing
  /// 6: Reports & Records
  /// 7: Settings
  bool isModuleAllowed(int moduleIndex) {
    if (_currentRole == 'Admin') return true;

    // All roles can access Settings (Profile tab) and Dashboard
    if (moduleIndex == 0 || moduleIndex == 7) return true;

    switch (_currentRole) {
      case 'Receiving Clerk':
        return moduleIndex == 1;
      case 'Document Verifier':
        return moduleIndex == 2;
      case 'Inspector':
        return moduleIndex == 3;
      case 'Cashier':
        return moduleIndex == 4;
      case 'Releasing Officer':
        return moduleIndex == 5;
      default:
        return true;
    }
  }

  // 3. Slaughter Schedule & Capacity
  SlaughterScheduleCapacity _scheduleCapacity = SlaughterScheduleCapacity(
    operatingDays: [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday'
    ],
    openingTime: '05:00',
    closingTime: '17:00',
    cutoffTime: '15:00',
    maxHeadsPerDay: 100,
    maxHogPerDay: 60,
    maxCattlePerDay: 20,
    maxCarabaoPerDay: 10,
    maxGoatPerDay: 10,
    maxPoultryPerDay: 50,
    isOperational: true,
    noticeMessage: 'Regular slaughter operations on schedule.',
  );

  SlaughterScheduleCapacity get scheduleCapacity => _scheduleCapacity;

  Future<void> updateScheduleCapacity(SlaughterScheduleCapacity newSchedule) async {
    _scheduleCapacity = newSchedule;
    notifyListeners();
    await _saveScheduleToPrefs();
  }

  // 4. My Profile
  String _profileName = 'Slaughterhouse Administrator';
  String get profileName => _profileName;

  String _profileEmail = 'admin@tabaco.gov.ph';
  String get profileEmail => _profileEmail;

  String? _profilePhotoUrl;
  String? get profilePhotoUrl => _profilePhotoUrl;

  Future<void> updateProfileName(String newName) async {
    _profileName = newName.trim();
    notifyListeners();
    await _saveProfileToPrefs();

    // Sync with Supabase Auth user metadata & profiles table if user is signed in
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(data: {'full_name': _profileName}),
        );
        try {
          await Supabase.instance.client
              .from('profiles')
              .update({'full_name': _profileName}).eq('id', user.id);
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> updateProfilePhoto(String? photoUrl) async {
    _profilePhotoUrl = photoUrl;
    notifyListeners();
    await _saveProfileToPrefs();

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null && photoUrl != null) {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(data: {'avatar_url': photoUrl}),
        );
        try {
          await Supabase.instance.client
              .from('profiles')
              .update({'avatar_url': photoUrl}).eq('id', user.id);
        } catch (_) {}
      }
    } catch (_) {}
  }

  void syncWithAuthUser([User? authUser]) {
    final user = authUser ?? Supabase.instance.client.auth.currentUser;
    if (user != null) {
      if (user.email != null && user.email!.isNotEmpty) {
        _profileEmail = user.email!;
      }
      final meta = user.userMetadata;
      if (meta != null) {
        if (meta['full_name'] != null && meta['full_name'].toString().trim().isNotEmpty) {
          _profileName = meta['full_name'].toString().trim();
        }
        if (meta['avatar_url'] != null && meta['avatar_url'].toString().trim().isNotEmpty) {
          _profilePhotoUrl = meta['avatar_url'].toString().trim();
        }
        if (meta['role'] != null) {
          final r = meta['role'].toString();
          if (r == 'admin') _currentRole = 'Admin';
        }
      }
      notifyListeners();
    }
  }

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null || user.email == null || user.email!.isEmpty) {
      throw const AuthException(
        'No active session found. Please log in again to change password.',
      );
    }

    try {
      // 1. Re-authenticate user with existing password to verify identity and refresh token
      await client.auth.signInWithPassword(
        email: user.email!,
        password: currentPassword,
      );

      // 2. Apply new password
      final response = await client.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      if (response.user == null) {
        throw const AuthException('Failed to update password in Supabase.');
      }

      debugPrint('Password updated successfully for: ${user.email}');
      return true;
    } on AuthException catch (e) {
      debugPrint('Change password auth error: ${e.message}');
      final msg = e.message.toLowerCase();
      if (msg.contains('invalid login credentials') || msg.contains('invalid credentials')) {
        throw const AuthException('The existing / current password you entered is incorrect.');
      }
      rethrow;
    } catch (e) {
      debugPrint('Change password error: $e');
      rethrow;
    }
  }

  // 5. Appearance
  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  String _cityLogoPath = 'assets/images/logo1.png';
  String get cityLogoPath => _cityLogoPath;

  String _headerTitle = 'Tabaco City Slaughterhouse';
  String get headerTitle => _headerTitle;

  String _headerSubtitle = 'Management System';
  String get headerSubtitle => _headerSubtitle;

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_theme_mode', mode == ThemeMode.dark ? 'dark' : 'light');
  }

  Future<void> updateAppearance({
    String? cityLogoPath,
    String? headerTitle,
    String? headerSubtitle,
  }) async {
    if (cityLogoPath != null) _cityLogoPath = cityLogoPath;
    if (headerTitle != null) _headerTitle = headerTitle;
    if (headerSubtitle != null) _headerSubtitle = headerSubtitle;
    notifyListeners();
    await _saveAppearanceToPrefs();
  }

  Future<void> resetAppearance() async {
    _cityLogoPath = 'assets/images/logo1.png';
    _headerTitle = 'Tabaco City Slaughterhouse';
    _headerSubtitle = 'Management System';
    _themeMode = ThemeMode.light;
    notifyListeners();
    await _saveAppearanceToPrefs();
  }

  // ═══════════════════════════════════════════════════════════
  //  PERSISTENCE METHODS
  // ═══════════════════════════════════════════════════════════
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load Theme
      final savedTheme = prefs.getString('app_theme_mode');
      if (savedTheme == 'dark') {
        _themeMode = ThemeMode.dark;
      } else {
        _themeMode = ThemeMode.light;
      }

      // Load Appearance
      final savedLogo = prefs.getString('app_city_logo');
      if (savedLogo != null && savedLogo.isNotEmpty) {
        _cityLogoPath = savedLogo;
      }
      final savedTitle = prefs.getString('app_header_title');
      if (savedTitle != null && savedTitle.isNotEmpty) {
        _headerTitle = savedTitle;
      }
      final savedSubtitle = prefs.getString('app_header_subtitle');
      if (savedSubtitle != null && savedSubtitle.isNotEmpty) {
        _headerSubtitle = savedSubtitle;
      }

      // Load Profile
      final savedProfileName = prefs.getString('app_profile_name');
      if (savedProfileName != null && savedProfileName.isNotEmpty) {
        _profileName = savedProfileName;
      }
      final savedPhotoUrl = prefs.getString('app_profile_photo');
      if (savedPhotoUrl != null && savedPhotoUrl.isNotEmpty) {
        _profilePhotoUrl = savedPhotoUrl;
      }
      final savedRole = prefs.getString('app_current_role');
      if (savedRole != null && savedRole.isNotEmpty) {
        _currentRole = savedRole;
      }

      // Check current Supabase auth user
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        _profileEmail = user.email ?? _profileEmail;
        final meta = user.userMetadata;
        if (meta != null) {
          if (meta['full_name'] != null && _profileName == 'Slaughterhouse Administrator') {
            _profileName = meta['full_name'].toString();
          }
          if (meta['avatar_url'] != null && _profilePhotoUrl == null) {
            _profilePhotoUrl = meta['avatar_url'].toString();
          }
          if (meta['role'] != null) {
            final r = meta['role'].toString();
            if (r == 'admin') _currentRole = 'Admin';
          }
        }
      }

      await _ensureAdminAuth();

      // Load Fees (Try Supabase system_settings first, then local fallback)
      try {
        final feeRow = await Supabase.instance.client
            .from('system_settings')
            .select('value')
            .eq('key', 'fee_schedules')
            .maybeSingle();
        if (feeRow != null && feeRow['value'] != null) {
          final rawVal = feeRow['value'];
          final Map<String, dynamic> decoded = rawVal is String
              ? jsonDecode(rawVal) as Map<String, dynamic>
              : Map<String, dynamic>.from(rawVal as Map);
          decoded.forEach((key, val) {
            if (val is Map<String, dynamic>) {
              _feeSchedules[key.toLowerCase()] = AnimalFeeSchedule.fromJson(val);
            } else if (val is Map) {
              _feeSchedules[key.toLowerCase()] =
                  AnimalFeeSchedule.fromJson(Map<String, dynamic>.from(val));
            }
          });
        } else {
          final feesJsonStr = prefs.getString('app_fees_json');
          if (feesJsonStr != null) {
            final Map<String, dynamic> decoded = jsonDecode(feesJsonStr);
            decoded.forEach((key, val) {
              if (val is Map<String, dynamic>) {
                _feeSchedules[key.toLowerCase()] = AnimalFeeSchedule.fromJson(val);
              }
            });
          }
        }
      } catch (e) {
        final feesJsonStr = prefs.getString('app_fees_json');
        if (feesJsonStr != null) {
          final Map<String, dynamic> decoded = jsonDecode(feesJsonStr);
          decoded.forEach((key, val) {
            if (val is Map<String, dynamic>) {
              _feeSchedules[key.toLowerCase()] = AnimalFeeSchedule.fromJson(val);
            }
          });
        }
      }

      // Load Staff (Try Supabase system_settings first, then local fallback)
      try {
        final staffRow = await Supabase.instance.client
            .from('system_settings')
            .select('value')
            .eq('key', 'staff_accounts')
            .maybeSingle();
        if (staffRow != null && staffRow['value'] != null) {
          final rawVal = staffRow['value'];
          final List decoded = rawVal is String
              ? jsonDecode(rawVal) as List
              : (rawVal as List);
          _staffAccounts.clear();
          for (var item in decoded) {
            if (item is Map<String, dynamic>) {
              _staffAccounts.add(StaffAccount.fromJson(item));
            } else if (item is Map) {
              _staffAccounts.add(StaffAccount.fromJson(Map<String, dynamic>.from(item)));
            }
          }
          final list = _staffAccounts.map((s) => s.toJson()).toList();
          await prefs.setString('app_staff_json', jsonEncode(list));
        } else {
          final staffJsonStr = prefs.getString('app_staff_json');
          if (staffJsonStr != null) {
            final List decoded = jsonDecode(staffJsonStr);
            _staffAccounts.clear();
            for (var item in decoded) {
              if (item is Map<String, dynamic>) {
                _staffAccounts.add(StaffAccount.fromJson(item));
              }
            }
          }
        }
      } catch (e) {
        final staffJsonStr = prefs.getString('app_staff_json');
        if (staffJsonStr != null) {
          final List decoded = jsonDecode(staffJsonStr);
          _staffAccounts.clear();
          for (var item in decoded) {
            if (item is Map<String, dynamic>) {
              _staffAccounts.add(StaffAccount.fromJson(item));
            }
          }
        }
      }

      // Load Schedule (Try Supabase system_settings first, then local fallback)
      try {
        final schedRow = await Supabase.instance.client
            .from('system_settings')
            .select('value')
            .eq('key', 'schedule_capacity')
            .maybeSingle();
        if (schedRow != null && schedRow['value'] != null) {
          final rawVal = schedRow['value'];
          final Map<String, dynamic> decoded = rawVal is String
              ? jsonDecode(rawVal) as Map<String, dynamic>
              : Map<String, dynamic>.from(rawVal as Map);
          _scheduleCapacity = SlaughterScheduleCapacity.fromJson(decoded);
          await prefs.setString('app_schedule_json', jsonEncode(_scheduleCapacity.toJson()));
        } else {
          final scheduleJsonStr = prefs.getString('app_schedule_json');
          if (scheduleJsonStr != null) {
            _scheduleCapacity = SlaughterScheduleCapacity.fromJson(jsonDecode(scheduleJsonStr));
          }
        }
      } catch (e) {
        final scheduleJsonStr = prefs.getString('app_schedule_json');
        if (scheduleJsonStr != null) {
          _scheduleCapacity = SlaughterScheduleCapacity.fromJson(jsonDecode(scheduleJsonStr));
        }
      }

      _initialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('AppSettingsService init error: $e');
      _initialized = true;
    }
  }

  Future<void> _saveFeesToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = _feeSchedules.map((k, v) => MapEntry(k, v.toJson()));
      await prefs.setString('app_fees_json', jsonEncode(map));

      // Persist to Supabase system_settings
      final client = Supabase.instance.client;
      try {
        await _ensureAdminAuth();
        await client.from('system_settings').upsert({
          'key': 'fee_schedules',
          'value': map,
          'updated_at': DateTime.now().toIso8601String(),
        });
        debugPrint('Saved fee_schedules to Supabase system_settings successfully.');
      } catch (authErr) {
        debugPrint('Admin auth upsert error, attempting fallback: $authErr');
        await client.from('system_settings').upsert({
          'key': 'fee_schedules',
          'value': map,
          'updated_at': DateTime.now().toIso8601String(),
        });
        debugPrint('Saved fee_schedules to Supabase system_settings without admin auth.');
      }
    } catch (e) {
      debugPrint('Error saving fees to Supabase: $e');
      rethrow;
    }
  }

  Future<void> _saveStaffToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _staffAccounts.map((s) => s.toJson()).toList();
      await prefs.setString('app_staff_json', jsonEncode(list));

      // Persist to Supabase system_settings
      await _ensureAdminAuth();
      final client = Supabase.instance.client;
      if (client.auth.currentSession != null) {
        await client.from('system_settings').upsert({
          'key': 'staff_accounts',
          'value': list,
          'updated_at': DateTime.now().toIso8601String(),
        });
        debugPrint('Saved staff_accounts to Supabase system_settings successfully.');
      }
    } catch (e) {
      debugPrint('Error saving staff: $e');
    }
  }

  Future<void> _saveScheduleToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_schedule_json', jsonEncode(_scheduleCapacity.toJson()));

      // Persist to Supabase system_settings
      await _ensureAdminAuth();
      final client = Supabase.instance.client;
      if (client.auth.currentSession != null) {
        await client.from('system_settings').upsert({
          'key': 'schedule_capacity',
          'value': _scheduleCapacity.toJson(),
          'updated_at': DateTime.now().toIso8601String(),
        });
        debugPrint('Saved schedule_capacity to Supabase system_settings successfully.');
      }
    } catch (e) {
      debugPrint('Error saving schedule: $e');
    }
  }

  Future<void> _saveProfileToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_profile_name', _profileName);
      if (_profilePhotoUrl != null) {
        await prefs.setString('app_profile_photo', _profilePhotoUrl!);
      }
      await prefs.setString('app_current_role', _currentRole);
    } catch (e) {
      debugPrint('Error saving profile: $e');
    }
  }

  Future<void> _saveAppearanceToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_city_logo', _cityLogoPath);
      await prefs.setString('app_header_title', _headerTitle);
      await prefs.setString('app_header_subtitle', _headerSubtitle);

      // Persist to Supabase system_settings
      await _ensureAdminAuth();
      final client = Supabase.instance.client;
      if (client.auth.currentSession != null) {
        await client.from('system_settings').upsert({
          'key': 'appearance',
          'value': {
            'cityLogoPath': _cityLogoPath,
            'headerTitle': _headerTitle,
            'headerSubtitle': _headerSubtitle,
          },
          'updated_at': DateTime.now().toIso8601String(),
        });
        debugPrint('Saved appearance to Supabase system_settings successfully.');
      }
    } catch (e) {
      debugPrint('Error saving appearance: $e');
    }
  }
}

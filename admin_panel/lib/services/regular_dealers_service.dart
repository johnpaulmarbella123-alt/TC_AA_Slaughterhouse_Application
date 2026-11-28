import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_settings_service.dart';
import 'audit_log_service.dart';

class RegularDealer {
  final String id;
  final int dealerNumber;
  final String name;
  final String markings;
  final String category; // 'market' or 'barangay'
  final String? phone;
  final String? userId;
  final bool isActive;
  final String? createdAt;

  RegularDealer({
    required this.id,
    required this.dealerNumber,
    required this.name,
    required this.markings,
    required this.category,
    this.phone,
    this.userId,
    this.isActive = true,
    this.createdAt,
  });

  bool get isNew {
    if (createdAt == null || createdAt!.isEmpty) return false;
    try {
      final dt = DateTime.parse(createdAt!);
      return DateTime.now().difference(dt).inDays <= 30;
    } catch (_) {
      return false;
    }
  }

  factory RegularDealer.fromJson(Map<String, dynamic> json) {
    return RegularDealer(
      id: json['id']?.toString() ?? '',
      dealerNumber: int.tryParse(json['dealer_number']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString() ?? '',
      markings: json['markings']?.toString() ?? '',
      category: (json['category']?.toString() ?? 'barangay').toLowerCase(),
      phone: json['phone']?.toString(),
      userId: json['user_id']?.toString(),
      isActive: json['is_active'] == null ? true : (json['is_active'] == true || json['is_active'].toString() == 'true'),
      createdAt: json['created_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'dealer_number': dealerNumber,
      'name': name,
      'markings': markings,
      'category': category,
      'phone': phone,
      'user_id': userId,
      'is_active': isActive,
      'created_at': createdAt,
    };
  }

  RegularDealer copyWith({
    int? dealerNumber,
    String? name,
    String? markings,
    String? category,
    String? phone,
    bool clearPhone = false,
    String? userId,
    bool clearUserId = false,
    bool? isActive,
  }) {
    return RegularDealer(
      id: id,
      dealerNumber: dealerNumber ?? this.dealerNumber,
      name: name ?? this.name,
      markings: markings ?? this.markings,
      category: category ?? this.category,
      phone: clearPhone ? null : (phone ?? this.phone),
      userId: clearUserId ? null : (userId ?? this.userId),
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
    );
  }
}

class NmicSettings {
  String nmicEmail;
  String nmicOfficerName;
  String nmicOfficerTitle;
  String dmioOfficerName;
  String dmioOfficerTitle;
  String plantRepresentative;
  String plantRepTitle;
  String ltoNumber;
  String establishmentName;
  String establishmentAddress;
  String feeBasisType; // 'ordinance' or 'da_ao13'
  String feeBasisDetails;
  String resendApiKey;
  String senderEmail;

  NmicSettings({
    this.nmicEmail = 'nmic.region5@da.gov.ph',
    this.nmicOfficerName = 'DR. BEJAEE C. DE DIOS',
    this.nmicOfficerTitle = 'POSMS Head',
    this.dmioOfficerName = 'MELCHOR VARGAS',
    this.dmioOfficerTitle = 'DMIO & NMIS Inspection Officer',
    this.plantRepresentative = 'JOSE ERNESTO ROS',
    this.plantRepTitle = 'Slaughterhouse Designate',
    this.ltoNumber = 'LTO-SL-05-004',
    this.establishmentName = 'Tabaco City Slaughterhouse',
    this.establishmentAddress = 'San Roque, Tabaco City, Albay',
    this.feeBasisType = 'ordinance',
    this.feeBasisDetails = 'City Ordinance No. 2018-012',
    this.resendApiKey = '',
    this.senderEmail = 'TCAA Slaughterhouse <onboarding@resend.dev>',
  });

  factory NmicSettings.fromJson(Map<String, dynamic> json) {
    return NmicSettings(
      nmicEmail: json['nmic_email']?.toString() ?? 'nmic.region5@da.gov.ph',
      nmicOfficerName: json['nmic_officer_name']?.toString() ?? 'DR. BEJAEE C. DE DIOS',
      nmicOfficerTitle: json['nmic_officer_title']?.toString() ?? 'POSMS Head',
      dmioOfficerName: json['dmio_officer_name']?.toString() ?? 'MELCHOR VARGAS',
      dmioOfficerTitle: json['dmio_officer_title']?.toString() ?? 'DMIO & NMIS Inspection Officer',
      plantRepresentative: json['plant_representative']?.toString() ?? 'JOSE ERNESTO ROS',
      plantRepTitle: json['plant_rep_title']?.toString() ?? 'Slaughterhouse Designate',
      ltoNumber: json['lto_number']?.toString() ?? 'LTO-SL-05-004',
      establishmentName: json['establishment_name']?.toString() ?? 'Tabaco City Slaughterhouse',
      establishmentAddress: json['establishment_address']?.toString() ?? 'San Roque, Tabaco City, Albay',
      feeBasisType: json['fee_basis_type']?.toString() ?? 'ordinance',
      feeBasisDetails: json['fee_basis_details']?.toString() ?? 'City Ordinance No. 2018-012',
      resendApiKey: json['resend_api_key']?.toString() ?? '',
      senderEmail: json['sender_email']?.toString() ?? 'TCAA Slaughterhouse <onboarding@resend.dev>',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nmic_email': nmicEmail,
      'nmic_officer_name': nmicOfficerName,
      'nmic_officer_title': nmicOfficerTitle,
      'dmio_officer_name': dmioOfficerName,
      'dmio_officer_title': dmioOfficerTitle,
      'plant_representative': plantRepresentative,
      'plant_rep_title': plantRepTitle,
      'lto_number': ltoNumber,
      'establishment_name': establishmentName,
      'establishment_address': establishmentAddress,
      'fee_basis_type': feeBasisType,
      'fee_basis_details': feeBasisDetails,
      'resend_api_key': resendApiKey,
      'sender_email': senderEmail,
    };
  }
}

class RegularDealersService {
  static final RegularDealersService instance = RegularDealersService._internal();
  RegularDealersService._internal();

  final supabase = Supabase.instance.client;
  List<RegularDealer> _dealers = [];
  Set<String> _deletedDealerKeys = {};
  NmicSettings _nmicSettings = NmicSettings();
  bool _isLoaded = false;

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  List<String> _tombstoneKeysFor({String? userId, String? name, String? category}) {
    final keys = <String>[];
    final cleanCat = (category ?? '').trim().toLowerCase();
    final cleanName = (name ?? '').trim().toUpperCase();
    final cleanUid = (userId ?? '').trim();
    if (cleanName.isNotEmpty) {
      if (cleanCat.isNotEmpty) {
        keys.add('name:$cleanName|cat:$cleanCat');
      } else {
        keys.add('name:$cleanName|cat:barangay');
        keys.add('name:$cleanName|cat:market');
      }
    }
    if (cleanUid.isNotEmpty) {
      if (cleanCat.isNotEmpty) {
        keys.add('uid:$cleanUid|cat:$cleanCat');
      } else {
        keys.add('uid:$cleanUid|cat:barangay');
        keys.add('uid:$cleanUid|cat:market');
      }
    }
    return keys;
  }

  bool _isDealerTombstoned({String? userId, String? name, String? category}) {
    if (_deletedDealerKeys.isEmpty) return false;
    final cleanCat = (category ?? '').trim().toLowerCase();
    final cleanName = (name ?? '').trim().toUpperCase();
    final cleanUid = (userId ?? '').trim();
    if (cleanName.isNotEmpty && cleanCat.isNotEmpty && _deletedDealerKeys.contains('name:$cleanName|cat:$cleanCat')) {
      return true;
    }
    if (cleanUid.isNotEmpty && cleanCat.isNotEmpty && _deletedDealerKeys.contains('uid:$cleanUid|cat:$cleanCat')) {
      return true;
    }
    return false;
  }

  Future<void> _loadDeletedTombstones() async {
    final loaded = <String>{..._deletedDealerKeys};
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('deleted_regular_dealers_cache');
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached);
        if (decoded is List) {
          loaded.addAll(decoded.map((e) => e.toString()));
        }
      }
    } catch (_) {}
    try {
      final row = await supabase
          .from('system_settings')
          .select('value')
          .eq('key', 'deleted_regular_dealers')
          .maybeSingle();
      if (row != null && row['value'] != null) {
        final raw = row['value'];
        final decoded = raw is String ? jsonDecode(raw) : raw;
        if (decoded is List) {
          loaded.addAll(decoded.map((e) => e.toString()));
        }
      }
    } catch (e) {
      debugPrint('loadDeletedTombstones notice: $e');
    }
    _deletedDealerKeys = loaded;
  }

  Future<void> _saveDeletedTombstones() async {
    final list = _deletedDealerKeys.toList()..sort();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('deleted_regular_dealers_cache', jsonEncode(list));
    } catch (_) {}
    try {
      await supabase.from('system_settings').upsert({
        'key': 'deleted_regular_dealers',
        'value': jsonEncode(list),
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('saveDeletedTombstones error: $e');
    }
  }

  Future<void> _clearTombstoneFor({String? userId, String? name, String? category}) async {
    final keys = _tombstoneKeysFor(userId: userId, name: name, category: category);
    bool removed = false;
    for (final k in keys) {
      if (_deletedDealerKeys.remove(k)) {
        removed = true;
      }
    }
    if (removed) {
      await _saveDeletedTombstones();
    }
  }

  List<RegularDealer> get allDealers => List.unmodifiable(_dealers);
  List<RegularDealer> get marketDealers =>
      _dealers.where((d) => d.category == 'market' && d.isActive).toList()
        ..sort((a, b) => a.dealerNumber.compareTo(b.dealerNumber));
  List<RegularDealer> get barangayDealers =>
      _dealers.where((d) => d.category == 'barangay' && d.isActive).toList()
        ..sort((a, b) => a.dealerNumber.compareTo(b.dealerNumber));

  NmicSettings get nmicSettings => _nmicSettings;

  /// Default Market Dealers Roster (empty on fresh system — populated dynamically from customer requests)
  static final List<Map<String, dynamic>> defaultMarketDealers = [];

  /// Default Barangay Dealers Roster (empty on fresh system — populated dynamically from customer requests)
  static final List<Map<String, dynamic>> defaultBarangayDealers = [];

  Future<void> init() async {
    if (_isLoaded) return;
    await reload();
  }

  Future<void> reload() async {
    await _loadDeletedTombstones();

    // 1. Try to load cached dealers from SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('regular_dealers_cache');
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final List decoded = jsonDecode(cachedJson);
        _dealers = decoded
            .map((item) => RegularDealer.fromJson(Map<String, dynamic>.from(item)))
            .where((d) => !_isDealerTombstoned(userId: d.userId, name: d.name, category: d.category))
            .toList();
      }
      final nmicJson = prefs.getString('nmic_settings_cache');
      if (nmicJson != null && nmicJson.isNotEmpty) {
        _nmicSettings = NmicSettings.fromJson(jsonDecode(nmicJson));
      }
    } catch (_) {}

    // 2. Fetch from Supabase `regular_dealers` table AND `system_settings` ('regular_dealers')
    //    and merge them so manually registered DB rows take priority while synced dealer markings are never lost.
    List<RegularDealer> tableDealers = [];
    List<RegularDealer> settingsDealers = [];
    bool fetchedRemote = false;

    try {
      final res = await supabase.from('regular_dealers').select();
      fetchedRemote = true;
      tableDealers = res
          .map((r) => RegularDealer.fromJson(Map<String, dynamic>.from(r)))
          .where((d) => !_isDealerTombstoned(userId: d.userId, name: d.name, category: d.category))
          .toList();
    } catch (e) {
      debugPrint('regular_dealers table query fallback: $e');
    }

    try {
      final sysRow = await supabase
          .from('system_settings')
          .select('value')
          .eq('key', 'regular_dealers')
          .maybeSingle();
      if (sysRow != null && sysRow['value'] != null) {
        final rawVal = sysRow['value'];
        final List decoded = rawVal is String ? jsonDecode(rawVal) : rawVal;
        fetchedRemote = true;
        settingsDealers = decoded
            .map((r) => RegularDealer.fromJson(Map<String, dynamic>.from(r)))
            .where((d) => !_isDealerTombstoned(userId: d.userId, name: d.name, category: d.category))
            .toList();
      }
    } catch (e) {
      debugPrint('system_settings regular_dealers fallback: $e');
    }

    if (fetchedRemote && (tableDealers.isNotEmpty || settingsDealers.isNotEmpty)) {
      _dealers = [...tableDealers, ...settingsDealers];
      if (_deduplicateDealers()) {
        await _syncToSupabase();
      }
      await _saveLocalCache();
      _isLoaded = true;
      await syncFromConfirmedProfiles();
      return;
    }

    // 4. Do not pre-seed hardcoded default dealers on a fresh system;
    //    dealers are added organically as customers submit requests or Admin registers them.
    await _saveLocalCache();

    // Load NMIC settings from system_settings
    try {
      final nmicRow = await supabase
          .from('system_settings')
          .select('value')
          .eq('key', 'nmic_settings')
          .maybeSingle();
      if (nmicRow != null && nmicRow['value'] != null) {
        final raw = nmicRow['value'];
        final Map<String, dynamic> decoded = raw is String ? jsonDecode(raw) : Map<String, dynamic>.from(raw);
        _nmicSettings = NmicSettings.fromJson(decoded);
      }
    } catch (_) {}

    _isLoaded = true;
  }

  Future<void> _saveLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'regular_dealers_cache', jsonEncode(_dealers.map((d) => d.toJson()).toList()));
      await prefs.setString('nmic_settings_cache', jsonEncode(_nmicSettings.toJson()));
    } catch (_) {}
  }

  Future<void> _syncToSupabase() async {
    try {
      final listJson = _dealers.map((d) => d.toJson()).toList();
      await supabase.from('system_settings').upsert({
        'key': 'regular_dealers',
        'value': jsonEncode(listJson),
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('syncToSupabase regular_dealers error: $e');
    }
  }

  Future<void> saveNmicSettings(NmicSettings newSettings) async {
    _nmicSettings = newSettings;
    await _saveLocalCache();
    try {
      await supabase.from('system_settings').upsert({
        'key': 'nmic_settings',
        'value': jsonEncode(newSettings.toJson()),
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('saveNmicSettings error: $e');
    }
  }

  /// Suggests a unique marking tag based on customer initials.
  /// E.g. "Juan Dela Cruz" -> "JDC". If "JDC" already exists -> "JDC-2".
  String suggestMarkingForName(String fullName) {
    final clean = fullName.trim().replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '');
    if (clean.isEmpty) return 'CUST';
    final parts = clean.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();

    String initials = '';
    if (parts.length == 1) {
      initials = parts.first.length >= 3 ? parts.first.substring(0, 3).toUpperCase() : parts.first.toUpperCase();
    } else {
      initials = parts.map((p) => p[0].toUpperCase()).join();
      if (initials.length > 5) {
        initials = initials.substring(0, 5);
      }
    }

    // Check collision with existing dealers
    final existingMarkings = _dealers.map((d) => d.markings.toUpperCase().trim()).toSet();
    if (!existingMarkings.contains(initials)) {
      return initials;
    }

    int suffix = 2;
    while (existingMarkings.contains('$initials-$suffix') || existingMarkings.contains('$initials$suffix')) {
      suffix++;
    }
    return '$initials-$suffix';
  }

  /// Assigns and permanently locks a marking for a customer.
  Future<RegularDealer> assignPermanentMarking({
    required String name,
    required String markings,
    required String category,
    String? phone,
    String? userId,
  }) async {
    final upperMarking = markings.trim().toUpperCase();
    final cleanCategory = category.toLowerCase().contains('market') ? 'market' : 'barangay';

    // Check if dealer already exists with this userId or exact name (respecting userId isolation)
    final existingIndex = _dealers.indexWhere((d) {
      if (userId != null &&
          userId.trim().isNotEmpty &&
          d.userId != null &&
          d.userId!.trim().isNotEmpty &&
          d.userId!.trim() != userId.trim()) {
        return false;
      }
      return (userId != null && userId.isNotEmpty && d.userId == userId) ||
          d.name.toLowerCase().trim() == name.toLowerCase().trim();
    });

    if (existingIndex >= 0) {
      final existing = _dealers[existingIndex];
      // Update markings if currently empty or if userId needs binding
      final updated = existing.copyWith(
        markings: upperMarking,
        phone: phone ?? existing.phone,
        userId: (existing.userId != null && existing.userId!.isNotEmpty) ? existing.userId : userId,
      );
      _dealers[existingIndex] = updated;
      await _saveLocalCache();
      await _syncToSupabase();

      if (userId != null && userId.isNotEmpty) {
        try {
          await supabase.from('profiles').update({
            'assigned_marking': upperMarking,
            'marking_locked': true,
            'dealer_category': cleanCategory,
          }).eq('id', userId);
        } catch (_) {}
      }
      return updated;
    }

    final maxNumber = _dealers
        .where((d) => d.category == cleanCategory)
        .fold<int>(0, (max, d) => d.dealerNumber > max ? d.dealerNumber : max);

    final newDealer = RegularDealer(
      id: 'dlr-${DateTime.now().millisecondsSinceEpoch}',
      dealerNumber: maxNumber + 1,
      name: name.trim().toUpperCase(),
      markings: upperMarking,
      category: cleanCategory,
      phone: phone,
      userId: userId,
      isActive: true,
      createdAt: DateTime.now().toIso8601String(),
    );

    _dealers.add(newDealer);
    await _saveLocalCache();
    await _syncToSupabase();

    // Also update profiles if user_id is provided
    if (userId != null && userId.isNotEmpty) {
      try {
        await supabase.from('profiles').update({
          'assigned_marking': upperMarking,
          'marking_locked': true,
          'dealer_category': cleanCategory,
        }).eq('id', userId);
      } catch (_) {}
    }

    return newDealer;
  }

  RegularDealer? findDealerByName(String name, {String? userId}) {
    final clean = name.trim().toLowerCase();
    if (clean.isEmpty) return null;

    bool canMatchDealer(RegularDealer d) {
      if (userId != null &&
          userId.trim().isNotEmpty &&
          d.userId != null &&
          d.userId!.trim().isNotEmpty &&
          d.userId!.trim() != userId.trim()) {
        return false;
      }
      return true;
    }

    // 1. Exact match
    for (var d in _dealers) {
      if (!canMatchDealer(d)) continue;
      if (d.name.toLowerCase().trim() == clean) return d;
    }

    // 2. Initial + Surname match ONLY when one side uses a 1-letter initial (e.g. "Danilo Cerillo" -> "D. CERILLO")
    final parts = clean.replaceAll(RegExp(r'[^a-zA-Z\s]'), '').split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      final firstInitial = parts.first[0];
      final lastName = parts.last;
      for (var d in _dealers) {
        if (!canMatchDealer(d)) continue;
        final dClean = d.name.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z\s]'), '');
        final dParts = dClean.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
        final hasSingleLetterInitial = parts.first.length == 1 || (dParts.isNotEmpty && dParts.first.length == 1);
        if (hasSingleLetterInitial && dParts.length >= 2 && dParts.first[0] == firstInitial && dParts.last == lastName) {
          return d;
        }
      }
    }

    // 3. Single-name / exact token prefix match (e.g. "Jonathan" -> "JONATHAN BINO" when unbound or same userId)
    if (parts.length == 1) {
      for (var d in _dealers) {
        if (!canMatchDealer(d)) continue;
        final dParts = d.name.toLowerCase().trim().split(RegExp(r'\s+'));
        if (dParts.isNotEmpty && dParts.first == parts.first) return d;
      }
    }

    return null;
  }

  RegularDealer? findDealerByMarking(String marking, {String? userId}) {
    final clean = marking.trim().toUpperCase();
    for (var d in _dealers) {
      if (userId != null &&
          userId.trim().isNotEmpty &&
          d.userId != null &&
          d.userId!.trim().isNotEmpty &&
          d.userId!.trim() != userId.trim()) {
        continue;
      }
      if (d.markings.trim().toUpperCase() == clean) return d;
    }
    return null;
  }

  /// Checks if a customer or marking belongs to an official regular meat dealer
  bool isRegularDealer({String? userId, String? customerName, String? marking}) {
    if (userId != null && userId.isNotEmpty) {
      if (_dealers.any((d) => d.userId == userId)) return true;
    }
    if (customerName != null && customerName.isNotEmpty) {
      if (findDealerByName(customerName, userId: userId) != null) return true;
    }
    if (marking != null && marking.isNotEmpty && (customerName == null || customerName.isEmpty)) {
      if (findDealerByMarking(marking, userId: userId) != null) return true;
    }
    return false;
  }

  /// Deduplicates newly added dealers (e.g., merging "JONATHAN BINO" and "JONATHAN" sharing marking "BINO" or userId)
  /// and re-sequences dealer numbers within each category.
  bool _deduplicateDealers() {
    if (_dealers.length <= 1) return false;
    bool changed = false;
    final List<RegularDealer> merged = [];

    for (final d in _dealers) {
      final dName = d.name.trim().toLowerCase();
      final dMark = d.markings.trim().toUpperCase();
      final dUid = d.userId?.trim();
      final isDlr = d.id.startsWith('dlr-') || (d.createdAt != null && d.createdAt!.isNotEmpty);

      final existingIdx = merged.indexWhere((m) {
        final mName = m.name.trim().toLowerCase();
        final mMark = m.markings.trim().toUpperCase();
        final mUid = m.userId?.trim();
        final isMDlr = m.id.startsWith('dlr-') || (m.createdAt != null && m.createdAt!.isNotEmpty);

        // 1. Same non-empty userId
        if (dUid != null && dUid.isNotEmpty && mUid != null && mUid.isNotEmpty && dUid == mUid) {
          return true;
        }
        // 2. Exact name match within same category
        if (dName.isNotEmpty && dName == mName && d.category == m.category) {
          return true;
        }
        // 3. For dynamically added dealers ('dlr-'), same marking OR substring name with same marking
        if ((isDlr || isMDlr) && dMark.isNotEmpty && dMark == mMark) {
          if (mName.contains(dName) || dName.contains(mName) || (isDlr && isMDlr)) {
            return true;
          }
        }
        return false;
      });

      if (existingIdx >= 0) {
        changed = true;
        final existing = merged[existingIdx];
        final isExistingRoster = existing.id.startsWith('mkt-') || existing.id.startsWith('brgy-');
        // Keep the fuller/longer name for dynamic dealers (e.g. "JONATHAN BINO" over "JONATHAN")
        final bestName = isExistingRoster
            ? existing.name
            : (d.name.trim().length > existing.name.trim().length ? d.name.trim().toUpperCase() : existing.name);
        merged[existingIdx] = existing.copyWith(
          name: bestName,
          markings: existing.markings.trim().isNotEmpty ? existing.markings : d.markings,
          phone: existing.phone ?? d.phone,
          userId: (existing.userId != null && existing.userId!.isNotEmpty) ? existing.userId : d.userId,
        );
      } else {
        merged.add(d);
      }
    }

    // Re-sequence dealer numbers per category so there are no gaps after deduplication
    for (final cat in ['market', 'barangay']) {
      int numCounter = 1;
      for (int i = 0; i < merged.length; i++) {
        if (merged[i].category == cat) {
          if (merged[i].dealerNumber != numCounter) {
            merged[i] = merged[i].copyWith(dealerNumber: numCounter);
            changed = true;
          }
          numCounter++;
        }
      }
    }

    if (changed) {
      _dealers = merged;
    }
    return changed;
  }

  /// Resolves the authoritative RegularDealer record for a customer
  RegularDealer? findAuthoritativeDealer({String? userId, String? customerName, String? marking}) {
    if (userId != null && userId.isNotEmpty) {
      for (final d in _dealers) {
        if (d.userId == userId) return d;
      }
    }
    if (customerName != null && customerName.isNotEmpty) {
      final byName = findDealerByName(customerName, userId: userId);
      if (byName != null) return byName;
    }
    if (marking != null && marking.isNotEmpty && (customerName == null || customerName.isEmpty)) {
      final byMark = findDealerByMarking(marking, userId: userId);
      if (byMark != null) return byMark;
    }
    return null;
  }

  /// Checks if a customer already has a locked marking in the official regular_dealers registry
  Future<String?> getCustomerPermanentMarking({String? userId, String? customerName, String? requestedMarking}) async {
    bool isAssigned(String m) {
      final clean = m.trim().toUpperCase();
      return clean.isNotEmpty && clean != 'PENDING';
    }

    if (userId != null && userId.isNotEmpty) {
      final d = _dealers.firstWhere(
        (d) => d.userId == userId,
        orElse: () => RegularDealer(id: '', dealerNumber: 0, name: '', markings: '', category: ''),
      );
      if (isAssigned(d.markings)) return d.markings;
    }

    if (customerName != null && customerName.isNotEmpty) {
      final d = findDealerByName(customerName, userId: userId);
      if (d != null && isAssigned(d.markings)) return d.markings;
    }

    return null;
  }

  /// Enrolls any role-confirmed customers from `profiles` into the Meat Dealers Directory
  /// immediately with a 'PENDING' marking until their first request is marked.
  Future<int> syncFromConfirmedProfiles() async {
    int added = 0;
    bool changed = false;

    try {
      List<dynamic> rows;
      try {
        rows = await supabase
            .from('profiles')
            .select('id, display_name, phone, dealer_category, assigned_marking, role_confirmed, created_at')
            .eq('role_confirmed', true);
      } catch (_) {
        rows = await supabase
            .from('profiles')
            .select('id, display_name, phone, dealer_category, role_confirmed, created_at')
            .eq('role_confirmed', true);
      }

      for (final row in rows) {
        final rawRole = (row['dealer_category'] ?? '').toString().trim().toLowerCase();
        if (rawRole != 'barangay' && rawRole != 'market') continue;

        final userId = (row['id'] ?? '').toString().trim();
        final fullName = (row['display_name'] ?? '').toString().trim();
        final phone = (row['phone'] ?? '').toString().trim();
        final assignedMarking = (row['assigned_marking'] ?? '').toString().trim().toUpperCase();
        final resolvedMarking = (assignedMarking.isNotEmpty && assignedMarking != 'PENDING')
            ? assignedMarking
            : 'PENDING';
        final createdAt = row['created_at']?.toString();

        final displayName = (fullName.isNotEmpty ? fullName : (phone.isNotEmpty ? phone : 'CUSTOMER')).toUpperCase();

        if (_isDealerTombstoned(userId: userId, name: displayName, category: rawRole)) {
          continue;
        }

        final existingIdx = _dealers.indexWhere((d) {
          if (userId.isNotEmpty && d.userId == userId) return true;
          if (fullName.isNotEmpty && d.name.trim().toUpperCase() == displayName) return true;
          if (phone.isNotEmpty && d.phone != null && d.phone!.trim() == phone) return true;
          return false;
        });

        if (existingIdx != -1) {
          final existing = _dealers[existingIdx];
          final needsUserId = (existing.userId == null || existing.userId!.isEmpty) && userId.isNotEmpty;
          final needsPhone = (existing.phone == null || existing.phone!.isEmpty) && phone.isNotEmpty;
          final needsCategory = existing.category.isEmpty;
          final existingMarkUpper = existing.markings.trim().toUpperCase();
          final needsMarking = (existingMarkUpper.isEmpty || existingMarkUpper == 'PENDING') &&
              resolvedMarking != 'PENDING';
          if (needsUserId || needsPhone || needsCategory || needsMarking) {
            _dealers[existingIdx] = existing.copyWith(
              userId: needsUserId ? userId : existing.userId,
              phone: needsPhone ? phone : existing.phone,
              category: needsCategory ? rawRole : existing.category,
              markings: needsMarking ? resolvedMarking : existing.markings,
            );
            changed = true;
          }
          continue;
        }

        final maxNumber = _dealers
            .where((d) => d.category == rawRole)
            .fold<int>(0, (max, d) => d.dealerNumber > max ? d.dealerNumber : max);

        _dealers.add(RegularDealer(
          id: 'dlr-${DateTime.now().millisecondsSinceEpoch}-$added',
          dealerNumber: maxNumber + 1,
          name: displayName,
          markings: resolvedMarking,
          category: rawRole,
          phone: phone.isNotEmpty ? phone : null,
          userId: userId.isNotEmpty ? userId : null,
          isActive: true,
          createdAt: createdAt ?? DateTime.now().toIso8601String(),
        ));
        added++;
        changed = true;
      }

      if (changed) {
        await _saveLocalCache();
        await _syncToSupabase();
      }
    } catch (e) {
      debugPrint('syncFromConfirmedProfiles error: $e');
    }

    return added;
  }

  /// Logs transmission to NMIC in system_settings and nmic_transmissions
  Future<void> logNmicTransmission({
    required String reportType,
    required String periodLabel,
    required String recipientEmail,
    required String transmittalSubject,
    String? transmittalBody,
    String? sentBy,
  }) async {
    final transmission = {
      'id': 'trans-${DateTime.now().millisecondsSinceEpoch}',
      'report_type': reportType,
      'period_label': periodLabel,
      'recipient_email': recipientEmail,
      'transmittal_subject': transmittalSubject,
      'transmittal_body': transmittalBody ?? '',
      'sent_by': sentBy ?? 'Admin',
      'status': 'sent',
      'created_at': DateTime.now().toIso8601String(),
    };

    try {
      await supabase.from('nmic_transmissions').insert(transmission);
    } catch (_) {
      try {
        final existingRow = await supabase
            .from('system_settings')
            .select('value')
            .eq('key', 'nmic_transmissions')
            .maybeSingle();
        List list = [];
        if (existingRow != null && existingRow['value'] != null) {
          final raw = existingRow['value'];
          list = raw is String ? jsonDecode(raw) : raw;
        }
        list.insert(0, transmission);
        await supabase.from('system_settings').upsert({
          'key': 'nmic_transmissions',
          'value': jsonEncode(list),
          'updated_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}
    }
  }

  Future<List<Map<String, dynamic>>> getTransmissions() async {
    try {
      final res = await supabase.from('nmic_transmissions').select().order('created_at', ascending: false).limit(30);
      if (res.isNotEmpty) {
        return List<Map<String, dynamic>>.from(res);
      }
    } catch (_) {}

    try {
      final row = await supabase
          .from('system_settings')
          .select('value')
          .eq('key', 'nmic_transmissions')
          .maybeSingle();
      if (row != null && row['value'] != null) {
        final raw = row['value'];
        final List list = raw is String ? jsonDecode(raw) : raw;
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}

    return [];
  }

  /// Syncs customers from requests table into dealers roster.
  /// Processes requests chronologically (oldest first) so a dealer's first request locks their marking,
  /// deduplicates dealer entries, and reconciles any discrepant request markings back to the dealer's locked marking.
  Future<int> syncCustomersFromRequests(List<Map<String, dynamic>> requests) async {
    int newlyAdded = 0;
    bool rosterChanged = _deduplicateDealers();

    // Sort chronologically (oldest first) so the first request establishes the permanent marking
    final sorted = List<Map<String, dynamic>>.from(requests);
    sorted.sort((a, b) {
      final ca = DateTime.tryParse((a['created_at'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final cb = DateTime.tryParse((b['created_at'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return ca.compareTo(cb);
    });

    // Self-heal any request whose marking was overwritten due to the old initial+surname collision (e.g. Melchor Marbella -> CHOR).
    for (final r in requests) {
      final cName = (r['customer_name'] ?? '').toString().trim().toLowerCase();
      final m = (r['marking'] ?? '').toString().trim().toUpperCase();
      if (cName == 'melchor marbella' && m == 'PAUL') {
        r['marking'] = 'CHOR';
        final rId = r['id'];
        if (rId != null) {
          try {
            await supabase.from('requests').update({'marking': 'CHOR'}).eq('id', rId);
          } catch (_) {}
        }
      }
    }

    for (var req in sorted) {
      final rawName = req['customer_name']?.toString().trim();
      if (rawName == null || rawName.isEmpty) continue;

      final category = (req['request_type']?.toString() ?? 'barangay').toLowerCase().contains('market')
          ? 'market'
          : 'barangay';

      String marking = (req['marking'] ?? req['customer_marking'] ?? '').toString().trim().toUpperCase();
      if (marking.isEmpty) {
        marking = suggestMarkingForName(rawName);
      }

      final phone = req['contact_number']?.toString();
      final userId = req['user_id']?.toString();
      final createdAt = req['created_at']?.toString();
      final cleanName = rawName.toLowerCase().trim();

      if (_isDealerTombstoned(userId: userId, name: rawName, category: category)) {
        continue;
      }

      // Find existing dealer by userId or exact name (respecting userId isolation)
      int existingIdx = _dealers.indexWhere((d) {
        if (userId != null &&
            userId.isNotEmpty &&
            d.userId != null &&
            d.userId!.isNotEmpty &&
            d.userId != userId) {
          return false;
        }
        return (userId != null && userId.isNotEmpty && d.userId == userId) ||
            d.name.toLowerCase().trim() == cleanName;
      });

      if (existingIdx < 0) {
        final byName = findDealerByName(rawName, userId: userId);
        if (byName != null) {
          existingIdx = _dealers.indexWhere((d) => d.id == byName.id);
        }
      }

      if (existingIdx < 0 && marking.isNotEmpty) {
        final byMark = findDealerByMarking(marking, userId: userId);
        if (byMark != null) {
          final mName = byMark.name.toLowerCase().trim();
          if (mName == cleanName) {
            existingIdx = _dealers.indexWhere((d) => d.id == byMark.id);
          }
        }
      }

      if (existingIdx >= 0) {
        var existing = _dealers[existingIdx];
        final isDynamic = existing.id.startsWith('dlr-') || (existing.createdAt != null && existing.createdAt!.isNotEmpty);
        final updatedName = (isDynamic && rawName.length > existing.name.trim().length && existing.userId == userId)
            ? rawName.toUpperCase()
            : existing.name;
        final updatedUserId = (existing.userId == null || existing.userId!.isEmpty) ? userId : existing.userId;

        if (updatedName != existing.name || updatedUserId != existing.userId) {
          existing = existing.copyWith(name: updatedName, userId: updatedUserId);
          _dealers[existingIdx] = existing;
          rosterChanged = true;
        }

        // Reconcile discrepant request marking ONLY if this dealer already has an assigned permanent marking.
        // If the dealer is still 'PENDING', promote it to the request's assigned marking.
        final lockedMarking = existing.markings.trim().toUpperCase();
        final isPending = lockedMarking.isEmpty || lockedMarking == 'PENDING';
        if (isPending && marking.isNotEmpty && marking != 'PENDING') {
          existing = existing.copyWith(markings: marking);
          _dealers[existingIdx] = existing;
          rosterChanged = true;
          if (updatedUserId != null && updatedUserId.isNotEmpty) {
            try {
              await supabase.from('profiles').update({
                'assigned_marking': marking,
                'marking_locked': true,
              }).eq('id', updatedUserId);
            } catch (_) {}
          }
        } else if (!isPending && marking != lockedMarking) {
          req['marking'] = lockedMarking;
          final reqId = req['id'];
          if (reqId != null) {
            try {
              await supabase.from('requests').update({'marking': lockedMarking}).eq('id', reqId);
            } catch (_) {}
          }
        }
      } else {
        // Register new dealer into regular_dealers with their user_id and marking
        final maxNumber = _dealers
            .where((d) => d.category == category)
            .fold<int>(0, (max, d) => d.dealerNumber > max ? d.dealerNumber : max);

        final newDealer = RegularDealer(
          id: 'dlr-${DateTime.now().millisecondsSinceEpoch}-$newlyAdded',
          dealerNumber: maxNumber + 1,
          name: rawName.toUpperCase(),
          markings: marking,
          category: category,
          phone: phone,
          userId: userId,
          isActive: true,
          createdAt: createdAt ?? DateTime.now().toIso8601String(),
        );

        _dealers.add(newDealer);
        newlyAdded++;
        rosterChanged = true;
      }
    }

    if (_deduplicateDealers()) {
      rosterChanged = true;
    }

    if (rosterChanged || newlyAdded > 0) {
      await _saveLocalCache();
      await _syncToSupabase();
    }

    return newlyAdded;
  }

  /// Manually registers a new dealer from the admin panel and persists to public.regular_dealers
  Future<RegularDealer> addDealerManually({
    required String name,
    required String markings,
    required String category,
    String? phone,
  }) async {
    await AppSettingsService.instance.ensureAdminAuthSession();

    final cleanCategory = category.toLowerCase().contains('market') ? 'market' : 'barangay';
    final cleanName = name.trim().toUpperCase();
    final cleanMarking = markings.trim().toUpperCase();
    final cleanPhone = phone?.trim();

    // Clear any prior removal tombstone when an Admin intentionally re-registers this dealer
    await _clearTombstoneFor(name: cleanName, category: cleanCategory);

    // Check duplicate marking in memory
    final existingMarking = findDealerByMarking(cleanMarking);
    if (existingMarking != null) {
      throw Exception('Marking "$cleanMarking" is already assigned to ${existingMarking.name}.');
    }

    // Query true max dealer_number directly from Supabase to avoid UNIQUE(category, dealer_number) conflicts
    int maxNumber = _dealers
        .where((d) => d.category == cleanCategory)
        .fold<int>(0, (max, d) => d.dealerNumber > max ? d.dealerNumber : max);
    try {
      final maxRow = await supabase
          .from('regular_dealers')
          .select('dealer_number')
          .eq('category', cleanCategory)
          .order('dealer_number', ascending: false)
          .limit(1)
          .maybeSingle();
      final dbMax = (maxRow?['dealer_number'] as num?)?.toInt() ?? 0;
      if (dbMax > maxNumber) {
        maxNumber = dbMax;
      }
    } catch (e) {
      debugPrint('Notice fetching max dealer_number from Supabase: $e');
    }
    final nextNumber = maxNumber + 1;

    // 1. Insert directly into public.regular_dealers table in Supabase (never swallow failures)
    final insertData = <String, dynamic>{
      'dealer_number': nextNumber,
      'name': cleanName,
      'markings': cleanMarking,
      'category': cleanCategory,
      'is_active': true,
    };
    if (cleanPhone != null && cleanPhone.isNotEmpty) {
      insertData['phone'] = cleanPhone;
    }

    final Map<String, dynamic> res;
    try {
      final inserted = await supabase
          .from('regular_dealers')
          .insert(insertData)
          .select()
          .single();
      res = Map<String, dynamic>.from(inserted);
    } catch (e) {
      debugPrint('Error inserting into regular_dealers table: $e');
      throw Exception(
        'Could not save dealer to Supabase database. Please ensure you are signed in as Admin/Staff and RLS migration is applied. ($e)',
      );
    }

    final generatedId = res['id']?.toString();
    final createdAt = res['created_at']?.toString() ?? DateTime.now().toIso8601String();

    final newDealer = RegularDealer(
      id: generatedId ?? 'dlr-${DateTime.now().millisecondsSinceEpoch}',
      dealerNumber: (res['dealer_number'] as num?)?.toInt() ?? nextNumber,
      name: cleanName,
      markings: cleanMarking,
      category: cleanCategory,
      phone: cleanPhone,
      isActive: true,
      createdAt: createdAt,
    );

    _dealers.add(newDealer);
    await _saveLocalCache();
    await _syncToSupabase();
    AuditLogService.instance.log(
      action: 'dealer_added',
      module: 'Meat Dealers',
      targetId: newDealer.id,
      targetRef: newDealer.markings,
      details: {'name': newDealer.name, 'category': newDealer.category},
    );
    return newDealer;
  }

  /// Updates an existing dealer and propagates Admin marking/name changes to requests & profiles
  Future<void> updateDealer(RegularDealer updated) async {
    await AppSettingsService.instance.ensureAdminAuthSession();

    final idx = _dealers.indexWhere((d) => d.id == updated.id);
    if (idx >= 0) {
      final previous = _dealers[idx];
      final cleanUpdated = updated.copyWith(
        name: updated.name.trim().toUpperCase(),
        markings: updated.markings.trim().toUpperCase(),
        phone: updated.phone?.trim(),
      );

      // Update public.regular_dealers table first so DB failures are surfaced
      try {
        await supabase.from('regular_dealers').update({
          'name': cleanUpdated.name,
          'markings': cleanUpdated.markings,
          'category': cleanUpdated.category,
          'phone': cleanUpdated.phone,
          'is_active': cleanUpdated.isActive,
        }).eq('id', cleanUpdated.id);
      } catch (e) {
        debugPrint('Error updating regular_dealers table: $e');
        throw Exception('Could not update dealer in Supabase database: $e');
      }

      _dealers[idx] = cleanUpdated;
      await _saveLocalCache();
      await _syncToSupabase();
      AuditLogService.instance.log(
        action: 'dealer_updated',
        module: 'Meat Dealers',
        targetId: cleanUpdated.id,
        targetRef: cleanUpdated.markings,
        details: {'name': cleanUpdated.name, 'category': cleanUpdated.category},
      );

      final newMark = cleanUpdated.markings;
      final uId = cleanUpdated.userId;
      if (uId != null && uId.isNotEmpty) {
        try {
          await supabase.from('profiles').update({
            'assigned_marking': newMark,
            'marking_locked': true,
          }).eq('id', uId);
        } catch (_) {}
        try {
          await supabase.from('requests').update({
            'marking': newMark,
          }).eq('user_id', uId);
        } catch (_) {}
      } else {
        try {
          await supabase
              .from('requests')
              .update({'marking': newMark})
              .ilike('customer_name', previous.name.trim());
        } catch (_) {}
      }
    }
  }

  /// Removes a dealer from the Meat Dealers Directory without deleting historical slaughter requests or payments.
  /// Persists a tombstone so auto-sync from profiles/requests will never resurrect the removed dealer.
  Future<void> deleteDealer(String id) async {
    await AppSettingsService.instance.ensureAdminAuthSession();

    final target = _dealers.firstWhere(
      (d) => d.id == id,
      orElse: () => RegularDealer(
        id: id,
        dealerNumber: 0,
        name: '',
        markings: '',
        category: 'barangay',
      ),
    );

    // 1. Delete from public.regular_dealers table (handle both real UUIDs and synthetic client IDs)
    if (_uuidRegex.hasMatch(id)) {
      try {
        await supabase.from('regular_dealers').delete().eq('id', id);
      } catch (e) {
        debugPrint('Error deleting dealer by UUID from regular_dealers: $e');
        throw Exception('Could not remove dealer from Supabase database: $e');
      }
    }
    if (target.name.trim().isNotEmpty) {
      try {
        await supabase
            .from('regular_dealers')
            .delete()
            .ilike('name', target.name.trim())
            .eq('category', target.category);
      } catch (e) {
        debugPrint('Notice deleting matching dealer row by name/category: $e');
      }
    }

    // 2. Record removal tombstone so syncFromConfirmedProfiles / syncCustomersFromRequests won't re-add them
    final tombstoneKeys = _tombstoneKeysFor(
      userId: target.userId,
      name: target.name,
      category: target.category,
    );
    _deletedDealerKeys.addAll(tombstoneKeys);

    // 3. Remove from in-memory roster and persist cache + tombstones + system_settings
    _dealers.removeWhere((d) =>
        d.id == id ||
        (target.name.trim().isNotEmpty &&
            d.name.trim().toUpperCase() == target.name.trim().toUpperCase() &&
            d.category == target.category));

    await _saveDeletedTombstones();
    await _saveLocalCache();
    await _syncToSupabase();

    AuditLogService.instance.log(
      action: 'dealer_deleted',
      module: 'Meat Dealers',
      targetId: id,
      targetRef: target.markings,
      details: {'name': target.name, 'category': target.category},
    );
  }

  /// Sends an email with PDF attachment directly via the `send-nmic-report` Edge Function
  /// (uses Gmail SMTP when configured, with Resend API as automatic fallback).
  Future<Map<String, dynamic>> sendReportViaResend({
    required String recipientEmail,
    required String subject,
    required String body,
    required Uint8List pdfBytes,
    required String filename,
    String? reportType,
    String? periodLabel,
    String? overrideApiKey,
    String? overrideSender,
  }) async {
    final apiKey = (overrideApiKey != null && overrideApiKey.trim().isNotEmpty)
        ? overrideApiKey.trim()
        : _nmicSettings.resendApiKey.trim();

    final sender = (overrideSender != null && overrideSender.trim().isNotEmpty)
        ? overrideSender.trim()
        : (_nmicSettings.senderEmail.isNotEmpty
            ? _nmicSettings.senderEmail
            : 'TCAA Slaughterhouse <onboarding@resend.dev>');

    try {
      final base64Pdf = base64Encode(pdfBytes);
      final payload = <String, dynamic>{
        if (apiKey.isNotEmpty) 'apiKey': apiKey,
        'sender': sender,
        'to': recipientEmail.trim(),
        'subject': subject.trim(),
        'text': body.trim(),
        if (reportType != null && reportType.isNotEmpty) 'reportType': reportType,
        if (periodLabel != null && periodLabel.isNotEmpty) 'periodLabel': periodLabel,
        'attachments': [
          {
            'filename': filename,
            'content': base64Pdf,
          }
        ],
      };

      // Invoke Supabase Edge Function to bypass browser CORS restrictions
      final res = await supabase.functions.invoke(
        'send-nmic-report',
        body: payload,
      );

      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : null;
      if (res.status == 200 && data != null && data['success'] == true) {
        return {
          'success': true,
          'id': data['id'],
          'message': 'Email delivered successfully via Resend API (ID: ${data["id"]})',
        };
      } else {
        final errMsg = data?['error'] ?? 'Failed to send email (${res.status})';
        return {
          'success': false,
          'error': errMsg,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to send email: $e',
      };
    }
  }
}

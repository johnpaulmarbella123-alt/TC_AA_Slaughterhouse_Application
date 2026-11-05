import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    String? name,
    String? markings,
    String? category,
    String? phone,
    bool? isActive,
  }) {
    return RegularDealer(
      id: id,
      dealerNumber: dealerNumber,
      name: name ?? this.name,
      markings: markings ?? this.markings,
      category: category ?? this.category,
      phone: phone ?? this.phone,
      userId: userId,
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
  NmicSettings _nmicSettings = NmicSettings();
  bool _isLoaded = false;

  List<RegularDealer> get allDealers => List.unmodifiable(_dealers);
  List<RegularDealer> get marketDealers =>
      _dealers.where((d) => d.category == 'market' && d.isActive).toList()
        ..sort((a, b) => a.dealerNumber.compareTo(b.dealerNumber));
  List<RegularDealer> get barangayDealers =>
      _dealers.where((d) => d.category == 'barangay' && d.isActive).toList()
        ..sort((a, b) => a.dealerNumber.compareTo(b.dealerNumber));

  NmicSettings get nmicSettings => _nmicSettings;

  /// Default 40 Market Dealers Roster
  static final List<Map<String, dynamic>> defaultMarketDealers = [
    {'dealer_number': 1, 'name': 'P. CARDIÑO', 'markings': 'X7', 'category': 'market'},
    {'dealer_number': 2, 'name': 'V. OGENA', 'markings': 'VK', 'category': 'market'},
    {'dealer_number': 3, 'name': 'A. BONDAD', 'markings': '4', 'category': 'market'},
    {'dealer_number': 4, 'name': 'N. CANDANO', 'markings': 'N', 'category': 'market'},
    {'dealer_number': 5, 'name': 'J. BAÑADERA', 'markings': 'BOGS', 'category': 'market'},
    {'dealer_number': 6, 'name': 'A. BONAOBRA', 'markings': 'ABE', 'category': 'market'},
    {'dealer_number': 7, 'name': 'S. MENDOZA', 'markings': 'AM', 'category': 'market'},
    {'dealer_number': 8, 'name': 'G. CAROLINO', 'markings': '11G', 'category': 'market'},
    {'dealer_number': 9, 'name': 'S. ZUBELDIA', 'markings': '11', 'category': 'market'},
    {'dealer_number': 10, 'name': 'J. TABLIZO', 'markings': 'JT', 'category': 'market'},
    {'dealer_number': 11, 'name': 'W. COMPETENTE', 'markings': 'WC', 'category': 'market'},
    {'dealer_number': 12, 'name': 'G. CAROLINO', 'markings': 'GENE', 'category': 'market'},
    {'dealer_number': 13, 'name': 'R. BRONDO', 'markings': 'BR', 'category': 'market'},
    {'dealer_number': 14, 'name': 'R. PIÑON', 'markings': 'RSP', 'category': 'market'},
    {'dealer_number': 15, 'name': 'J. RACINES', 'markings': 'RLG', 'category': 'market'},
    {'dealer_number': 16, 'name': 'F. BANDOJO', 'markings': 'FLORA', 'category': 'market'},
    {'dealer_number': 17, 'name': 'J. SABENORIO', 'markings': 'MATA', 'category': 'market'},
    {'dealer_number': 18, 'name': 'E. BILOLO', 'markings': 'JB', 'category': 'market'},
    {'dealer_number': 19, 'name': 'M. PRIA', 'markings': 'JP', 'category': 'market'},
    {'dealer_number': 20, 'name': 'M. BRAGAIS', 'markings': 'M', 'category': 'market'},
    {'dealer_number': 21, 'name': 'A. ZUBELDIA', 'markings': 'AZ', 'category': 'market'},
    {'dealer_number': 22, 'name': 'J. CARDIÑO', 'markings': '6', 'category': 'market'},
    {'dealer_number': 23, 'name': 'F. BARCENAS', 'markings': 'ND', 'category': 'market'},
    {'dealer_number': 24, 'name': 'C. CARDIÑO', 'markings': 'DC', 'category': 'market'},
    {'dealer_number': 25, 'name': 'W. MAGDAONG', 'markings': 'BETH', 'category': 'market'},
    {'dealer_number': 26, 'name': 'R. CRISTO', 'markings': 'REX', 'category': 'market'},
    {'dealer_number': 27, 'name': 'A. CARDIÑO', 'markings': 'RC', 'category': 'market'},
    {'dealer_number': 28, 'name': 'A. OGENA', 'markings': 'APOL', 'category': 'market'},
    {'dealer_number': 29, 'name': 'M. BENIG', 'markings': 'DOY', 'category': 'market'},
    {'dealer_number': 30, 'name': 'D. BARCENAS', 'markings': 'X', 'category': 'market'},
    {'dealer_number': 31, 'name': 'Y. ELLANA', 'markings': 'GAPO', 'category': 'market'},
    {'dealer_number': 32, 'name': 'L. VILILLA', 'markings': 'LV', 'category': 'market'},
    {'dealer_number': 33, 'name': 'A. OGENA', 'markings': 'APIT', 'category': 'market'},
    {'dealer_number': 34, 'name': 'B. OGENA', 'markings': 'YET', 'category': 'market'},
    {'dealer_number': 35, 'name': 'R. DATOG', 'markings': 'RD', 'category': 'market'},
    {'dealer_number': 36, 'name': 'J. CRISTO', 'markings': 'L3', 'category': 'market'},
    {'dealer_number': 37, 'name': 'R. BORCELIS', 'markings': 'RON', 'category': 'market'},
    {'dealer_number': 38, 'name': 'P. BURCE', 'markings': 'PZ', 'category': 'market'},
    {'dealer_number': 39, 'name': 'J. CAROLINO', 'markings': 'JC', 'category': 'market'},
    {'dealer_number': 40, 'name': 'J. SANTOS', 'markings': 'TCB', 'category': 'market'},
  ];

  /// Default 63 Barangay Dealers Roster
  static final List<Map<String, dynamic>> defaultBarangayDealers = [
    {'dealer_number': 1, 'name': 'A. PAHUYO', 'markings': 'AP', 'category': 'barangay'},
    {'dealer_number': 2, 'name': 'A. BOLATA', 'markings': 'BA', 'category': 'barangay'},
    {'dealer_number': 3, 'name': 'R. CORNEL', 'markings': 'CO', 'category': 'barangay'},
    {'dealer_number': 4, 'name': 'M. BOQUEO', 'markings': 'SMB', 'category': 'barangay'},
    {'dealer_number': 5, 'name': 'S. BAÑADERA', 'markings': 'SALLY', 'category': 'barangay'},
    {'dealer_number': 6, 'name': 'K. BURAO', 'markings': 'KB', 'category': 'barangay'},
    {'dealer_number': 7, 'name': 'J. BORROMEO', 'markings': 'NHEZ', 'category': 'barangay'},
    {'dealer_number': 8, 'name': 'A. CASITAS', 'markings': 'DONG', 'category': 'barangay'},
    {'dealer_number': 9, 'name': 'F. BRON JR.', 'markings': 'F', 'category': 'barangay'},
    {'dealer_number': 10, 'name': 'N. BUERE', 'markings': 'BUERE', 'category': 'barangay'},
    {'dealer_number': 11, 'name': 'C. TERESAS', 'markings': 'AZON', 'category': 'barangay'},
    {'dealer_number': 12, 'name': 'N. BODORAYA', 'markings': 'NB', 'category': 'barangay'},
    {'dealer_number': 13, 'name': 'C. DOLAR', 'markings': 'CCD', 'category': 'barangay'},
    {'dealer_number': 14, 'name': 'N. BOBIS', 'markings': '5C5', 'category': 'barangay'},
    {'dealer_number': 15, 'name': 'S. BORROMEO', 'markings': 'SB', 'category': 'barangay'},
    {'dealer_number': 16, 'name': 'E. BUSQUE', 'markings': 'GIN', 'category': 'barangay'},
    {'dealer_number': 17, 'name': 'P. BRON JR.', 'markings': 'TOM', 'category': 'barangay'},
    {'dealer_number': 18, 'name': 'F. BERCES', 'markings': 'FEL', 'category': 'barangay'},
    {'dealer_number': 19, 'name': 'N. BIBAT', 'markings': 'BIBAT', 'category': 'barangay'},
    {'dealer_number': 20, 'name': 'N. BOTICARIO', 'markings': 'NBB', 'category': 'barangay'},
    {'dealer_number': 21, 'name': 'P. BO', 'markings': 'K', 'category': 'barangay'},
    {'dealer_number': 22, 'name': 'C. BONAOBRA', 'markings': 'CEL', 'category': 'barangay'},
    {'dealer_number': 23, 'name': 'S. BENDITAHAN', 'markings': 'SBJR', 'category': 'barangay'},
    {'dealer_number': 24, 'name': 'B. BORROMEO', 'markings': '777', 'category': 'barangay'},
    {'dealer_number': 25, 'name': 'D. BIEN', 'markings': 'DRB', 'category': 'barangay'},
    {'dealer_number': 26, 'name': 'A. BUENCONSEJO', 'markings': 'LYN', 'category': 'barangay'},
    {'dealer_number': 27, 'name': 'C. PUENLABRADA', 'markings': 'CHITO', 'category': 'barangay'},
    {'dealer_number': 28, 'name': 'S. CEA', 'markings': 'SOLON', 'category': 'barangay'},
    {'dealer_number': 29, 'name': 'M. BORSAL', 'markings': 'LON', 'category': 'barangay'},
    {'dealer_number': 30, 'name': 'J. RACINES', 'markings': 'JET', 'category': 'barangay'},
    {'dealer_number': 31, 'name': 'G. BONGALON', 'markings': 'C2', 'category': 'barangay'},
    {'dealer_number': 32, 'name': 'B. CARULLO', 'markings': 'GBC', 'category': 'barangay'},
    {'dealer_number': 33, 'name': 'A. CLEMENTE JR.', 'markings': 'AU', 'category': 'barangay'},
    {'dealer_number': 34, 'name': 'L. LUMINARIO', 'markings': 'LITO', 'category': 'barangay'},
    {'dealer_number': 35, 'name': 'R. BRAGAIS', 'markings': 'RMB', 'category': 'barangay'},
    {'dealer_number': 36, 'name': 'E. TERESAS', 'markings': 'ET', 'category': 'barangay'},
    {'dealer_number': 37, 'name': 'J. BORROMEO', 'markings': 'TAN', 'category': 'barangay'},
    {'dealer_number': 38, 'name': 'I. GABATAN', 'markings': 'IREEN', 'category': 'barangay'},
    {'dealer_number': 39, 'name': 'S. BALDORADO', 'markings': 'TCB', 'category': 'barangay'},
    {'dealer_number': 40, 'name': 'N. BUBAN', 'markings': 'NEL', 'category': 'barangay'},
    {'dealer_number': 41, 'name': 'C. JARONEL', 'markings': 'CJ', 'category': 'barangay'},
    {'dealer_number': 42, 'name': 'F. BONEO', 'markings': 'IPE', 'category': 'barangay'},
    {'dealer_number': 43, 'name': 'M. BUARA', 'markings': 'ETM', 'category': 'barangay'},
    {'dealer_number': 44, 'name': 'L. DOLAR', 'markings': 'JRS', 'category': 'barangay'},
    {'dealer_number': 45, 'name': 'A. OVERES', 'markings': 'ART', 'category': 'barangay'},
    {'dealer_number': 46, 'name': 'A. BENOYO', 'markings': 'TABA/IPX', 'category': 'barangay'},
    {'dealer_number': 47, 'name': 'M. BONAVENTE', 'markings': 'JM', 'category': 'barangay'},
    {'dealer_number': 48, 'name': 'A. MONTIANO', 'markings': '125', 'category': 'barangay'},
    {'dealer_number': 49, 'name': 'A. BONAVENTE', 'markings': 'VIN', 'category': 'barangay'},
    {'dealer_number': 50, 'name': 'G. BURCE', 'markings': 'GS', 'category': 'barangay'},
    {'dealer_number': 51, 'name': 'C. ALMONTE', 'markings': 'CAJ', 'category': 'barangay'},
    {'dealer_number': 52, 'name': 'F. BUENDIA', 'markings': 'DICK', 'category': 'barangay'},
    {'dealer_number': 53, 'name': 'J. BONGARES', 'markings': 'KXK', 'category': 'barangay'},
    {'dealer_number': 54, 'name': 'V. PEREZ', 'markings': 'VPP', 'category': 'barangay'},
    {'dealer_number': 55, 'name': 'S. BARRA', 'markings': 'Y', 'category': 'barangay'},
    {'dealer_number': 56, 'name': 'D. CERILLO', 'markings': '99', 'category': 'barangay'},
    {'dealer_number': 57, 'name': 'D. DE JESUS', 'markings': 'DAN', 'category': 'barangay'},
    {'dealer_number': 58, 'name': 'J. BUIZON', 'markings': 'KOY', 'category': 'barangay'},
    {'dealer_number': 59, 'name': 'E. BUIZON', 'markings': 'OK', 'category': 'barangay'},
    {'dealer_number': 60, 'name': 'J. BONAOBRA', 'markings': 'RA', 'category': 'barangay'},
    {'dealer_number': 61, 'name': 'J. BORLAGDAN', 'markings': 'NIG', 'category': 'barangay'},
    {'dealer_number': 62, 'name': 'R. QUITASOL', 'markings': 'ARON', 'category': 'barangay'},
    {'dealer_number': 63, 'name': 'J. BUENDIA', 'markings': 'JV-75', 'category': 'barangay'},
  ];

  Future<void> init() async {
    if (_isLoaded) return;
    await reload();
  }

  Future<void> reload() async {
    // 1. Try to load cached dealers from SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('regular_dealers_cache');
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final List decoded = jsonDecode(cachedJson);
        _dealers = decoded.map((item) => RegularDealer.fromJson(Map<String, dynamic>.from(item))).toList();
      }
      final nmicJson = prefs.getString('nmic_settings_cache');
      if (nmicJson != null && nmicJson.isNotEmpty) {
        _nmicSettings = NmicSettings.fromJson(jsonDecode(nmicJson));
      }
    } catch (_) {}

    // 2. Fetch from Supabase `regular_dealers` table
    try {
      final res = await supabase.from('regular_dealers').select();
      if (res.isNotEmpty) {
        _dealers = res.map((r) => RegularDealer.fromJson(Map<String, dynamic>.from(r))).toList();
        await _saveLocalCache();
        _isLoaded = true;
        return;
      }
    } catch (e) {
      debugPrint('regular_dealers table query fallback: $e');
    }

    // 3. Fallback to `system_settings` key 'regular_dealers'
    try {
      final sysRow = await supabase
          .from('system_settings')
          .select('value')
          .eq('key', 'regular_dealers')
          .maybeSingle();
      if (sysRow != null && sysRow['value'] != null) {
        final rawVal = sysRow['value'];
        final List decoded = rawVal is String ? jsonDecode(rawVal) : rawVal;
        if (decoded.isNotEmpty) {
          _dealers = decoded.map((r) => RegularDealer.fromJson(Map<String, dynamic>.from(r))).toList();
          await _saveLocalCache();
          _isLoaded = true;
          return;
        }
      }
    } catch (e) {
      debugPrint('system_settings regular_dealers fallback: $e');
    }

    // 4. If empty, seed default dealers roster
    if (_dealers.isEmpty) {
      _dealers = [
        ...defaultMarketDealers.map((d) => RegularDealer(
              id: 'mkt-${d['dealer_number']}',
              dealerNumber: d['dealer_number'],
              name: d['name'],
              markings: d['markings'],
              category: 'market',
            )),
        ...defaultBarangayDealers.map((d) => RegularDealer(
              id: 'brgy-${d['dealer_number']}',
              dealerNumber: d['dealer_number'],
              name: d['name'],
              markings: d['markings'],
              category: 'barangay',
            )),
      ];
      await _syncToSupabase();
      await _saveLocalCache();
    }

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

    // Check if dealer already exists with this name or marking
    final existingIndex = _dealers.indexWhere((d) =>
        (userId != null && d.userId == userId) ||
        d.markings.toUpperCase().trim() == upperMarking ||
        d.name.toLowerCase().trim() == name.toLowerCase().trim());

    if (existingIndex >= 0) {
      final existing = _dealers[existingIndex];
      // Update markings if currently empty or if userId needs binding
      final updated = existing.copyWith(
        markings: upperMarking,
        phone: phone ?? existing.phone,
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

  RegularDealer? findDealerByName(String name) {
    final clean = name.trim().toLowerCase();
    if (clean.isEmpty) return null;

    // 1. Exact match
    for (var d in _dealers) {
      if (d.name.toLowerCase().trim() == clean) return d;
    }

    // 2. Initial + Surname match (e.g. "Danilo Cerillo" -> "D. CERILLO")
    final parts = clean.replaceAll(RegExp(r'[^a-zA-Z\s]'), '').split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      final firstInitial = parts.first[0];
      final lastName = parts.last;
      for (var d in _dealers) {
        final dClean = d.name.toLowerCase().replaceAll(RegExp(r'[^a-zA-Z\s]'), '');
        final dParts = dClean.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
        if (dParts.length >= 2 && dParts.first[0] == firstInitial && dParts.last == lastName) {
          return d;
        }
      }
    }

    // 3. Substring / contains match
    for (var d in _dealers) {
      final dName = d.name.toLowerCase().trim();
      if (dName.contains(clean) || clean.contains(dName)) return d;
    }

    return null;
  }

  RegularDealer? findDealerByMarking(String marking) {
    final clean = marking.trim().toUpperCase();
    for (var d in _dealers) {
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
      if (findDealerByName(customerName) != null) return true;
    }
    if (marking != null && marking.isNotEmpty) {
      if (findDealerByMarking(marking) != null) return true;
    }
    return false;
  }

  /// Checks if a customer already has a locked marking
  Future<String?> getCustomerPermanentMarking({String? userId, String? customerName, String? requestedMarking}) async {
    if (userId != null && userId.isNotEmpty) {
      try {
        final profile = await supabase
            .from('profiles')
            .select('assigned_marking, marking_locked')
            .eq('id', userId)
            .maybeSingle();
        if (profile != null && profile['assigned_marking'] != null && profile['assigned_marking'].toString().isNotEmpty) {
          return profile['assigned_marking'].toString();
        }
      } catch (_) {}

      final d = _dealers.firstWhere((d) => d.userId == userId, orElse: () => RegularDealer(id: '', dealerNumber: 0, name: '', markings: '', category: ''));
      if (d.markings.isNotEmpty) return d.markings;
    }

    if (customerName != null && customerName.isNotEmpty) {
      final d = findDealerByName(customerName);
      if (d != null && d.markings.isNotEmpty) return d.markings;
    }

    if (requestedMarking != null && requestedMarking.isNotEmpty) {
      final d = findDealerByMarking(requestedMarking);
      if (d != null && d.markings.isNotEmpty) return d.markings;
    }

    return null;
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
  /// If a customer is not yet registered as a dealer, registers them automatically.
  Future<int> syncCustomersFromRequests(List<Map<String, dynamic>> requests) async {
    int newlyAdded = 0;
    for (var req in requests) {
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
      final exists = _dealers.any((d) =>
          d.name.toLowerCase().trim() == cleanName ||
          (userId != null && userId.isNotEmpty && d.userId == userId));

      if (!exists) {
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
      }
    }

    if (newlyAdded > 0) {
      await _saveLocalCache();
      await _syncToSupabase();
    }

    return newlyAdded;
  }

  /// Manually registers a new dealer from the admin panel
  Future<RegularDealer> addDealerManually({
    required String name,
    required String markings,
    required String category,
    String? phone,
  }) async {
    final cleanCategory = category.toLowerCase().contains('market') ? 'market' : 'barangay';
    final maxNumber = _dealers
        .where((d) => d.category == cleanCategory)
        .fold<int>(0, (max, d) => d.dealerNumber > max ? d.dealerNumber : max);

    final newDealer = RegularDealer(
      id: 'dlr-${DateTime.now().millisecondsSinceEpoch}',
      dealerNumber: maxNumber + 1,
      name: name.trim().toUpperCase(),
      markings: markings.trim().toUpperCase(),
      category: cleanCategory,
      phone: phone?.trim(),
      isActive: true,
      createdAt: DateTime.now().toIso8601String(),
    );

    _dealers.add(newDealer);
    await _saveLocalCache();
    await _syncToSupabase();
    return newDealer;
  }

  /// Updates an existing dealer
  Future<void> updateDealer(RegularDealer updated) async {
    final idx = _dealers.indexWhere((d) => d.id == updated.id);
    if (idx >= 0) {
      _dealers[idx] = updated;
      await _saveLocalCache();
      await _syncToSupabase();
    }
  }

  /// Sends an email with PDF attachment via Resend REST API
  Future<Map<String, dynamic>> sendReportViaResend({
    required String recipientEmail,
    required String subject,
    required String body,
    required Uint8List pdfBytes,
    required String filename,
    String? overrideApiKey,
    String? overrideSender,
  }) async {
    final apiKey = (overrideApiKey != null && overrideApiKey.trim().isNotEmpty)
        ? overrideApiKey.trim()
        : _nmicSettings.resendApiKey.trim();

    if (apiKey.isEmpty) {
      return {
        'success': false,
        'error': 'Resend API Key is missing. Please enter your Resend API Key.'
      };
    }

    final sender = (overrideSender != null && overrideSender.trim().isNotEmpty)
        ? overrideSender.trim()
        : (_nmicSettings.senderEmail.isNotEmpty
            ? _nmicSettings.senderEmail
            : 'TCAA Slaughterhouse <onboarding@resend.dev>');

    try {
      final base64Pdf = base64Encode(pdfBytes);
      final payload = {
        'apiKey': apiKey,
        'sender': sender,
        'to': recipientEmail.trim(),
        'subject': subject.trim(),
        'text': body.trim(),
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

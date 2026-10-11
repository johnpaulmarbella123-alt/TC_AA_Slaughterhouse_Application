import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Represents the official fee schedule for an animal type
class LivestockFeeSchedule {
  final String animalType; // 'hog', 'cattle', 'carabao', 'goat', 'sheep'
  final String displayName;
  final double facilityFee;
  final double permitToSlaughterFee;
  final double vetHealthCertFee;
  final double corralFee;
  final double anteMortemFee;
  final double postMortemRatePerKg;
  final double deliveryVanFee;
  final double additionalFee;
  final String additionalFeeLabel;

  const LivestockFeeSchedule({
    required this.animalType,
    required this.displayName,
    this.facilityFee = 60.0,
    this.permitToSlaughterFee = 60.0,
    this.vetHealthCertFee = 50.0,
    this.corralFee = 40.0,
    this.anteMortemFee = 40.0,
    this.postMortemRatePerKg = 5.0,
    this.deliveryVanFee = 60.0,
    this.additionalFee = 0.0,
    this.additionalFeeLabel = 'Additional Administrative Charge',
  });

  /// Guaranteed safe non-null additional fee
  double get safeAdditionalFee =>
      (additionalFee as dynamic) is num ? (additionalFee as num).toDouble() : 0.0;

  /// Total standard fixed fees (facility + permit + vet cert + corral + ante-mortem + additionalFee)
  double get totalFixedFees {
    final double f = (facilityFee as dynamic) is num ? (facilityFee as num).toDouble() : 60.0;
    final double p = (permitToSlaughterFee as dynamic) is num ? (permitToSlaughterFee as num).toDouble() : 60.0;
    final double v = (vetHealthCertFee as dynamic) is num ? (vetHealthCertFee as num).toDouble() : 50.0;
    final double c = (corralFee as dynamic) is num ? (corralFee as num).toDouble() : 40.0;
    final double a = (anteMortemFee as dynamic) is num ? (anteMortemFee as num).toDouble() : 40.0;
    final double add = safeAdditionalFee;
    return f + p + v + c + a + add;
  }

  factory LivestockFeeSchedule.fromJson(String type, String name, Map<String, dynamic> json) {
    double parseDbl(dynamic v, double fallback) {
      if (v == null) return fallback;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? fallback;
    }

    return LivestockFeeSchedule(
      animalType: type.toLowerCase(),
      displayName: name,
      facilityFee: parseDbl(json['facilityFee'], 60.0),
      permitToSlaughterFee: parseDbl(json['permitToSlaughterFee'], 60.0),
      vetHealthCertFee: parseDbl(json['vetHealthCertFee'], 50.0),
      corralFee: parseDbl(json['corralFee'], 40.0),
      anteMortemFee: parseDbl(json['anteMortemFee'], 40.0),
      postMortemRatePerKg: parseDbl(json['postMortemRatePerKg'], 5.0),
      deliveryVanFee: parseDbl(json['deliveryVanFee'], 60.0),
      additionalFee: parseDbl(json['additionalFee'], 0.0),
      additionalFeeLabel: json['additionalFeeLabel']?.toString() ??
          'Additional Administrative Charge',
    );
  }
}

/// Centralized service to fetch and cache official livestock fees from Supabase
class LivestockFeeService extends ChangeNotifier {
  static final LivestockFeeService instance = LivestockFeeService._internal();

  LivestockFeeService._internal();

  final Map<String, LivestockFeeSchedule> _schedules = {
    'hog': const LivestockFeeSchedule(
      animalType: 'hog',
      displayName: 'Pig / Hog',
      facilityFee: 60.0,
      permitToSlaughterFee: 60.0,
      vetHealthCertFee: 50.0,
      corralFee: 40.0,
      anteMortemFee: 40.0,
      postMortemRatePerKg: 5.0,
      deliveryVanFee: 60.0,
      additionalFee: 0.0,
      additionalFeeLabel: 'Additional Administrative Charge',
    ),
    'cattle': const LivestockFeeSchedule(
      animalType: 'cattle',
      displayName: 'Cow / Cattle',
      facilityFee: 120.0,
      permitToSlaughterFee: 80.0,
      vetHealthCertFee: 50.0,
      corralFee: 60.0,
      anteMortemFee: 50.0,
      postMortemRatePerKg: 6.0,
      deliveryVanFee: 100.0,
      additionalFee: 0.0,
      additionalFeeLabel: 'Additional Administrative Charge',
    ),
    'carabao': const LivestockFeeSchedule(
      animalType: 'carabao',
      displayName: 'Carabao (Water Buffalo)',
      facilityFee: 120.0,
      permitToSlaughterFee: 80.0,
      vetHealthCertFee: 50.0,
      corralFee: 60.0,
      anteMortemFee: 50.0,
      postMortemRatePerKg: 6.0,
      deliveryVanFee: 100.0,
      additionalFee: 0.0,
      additionalFeeLabel: 'Additional Administrative Charge',
    ),
    'goat': const LivestockFeeSchedule(
      animalType: 'goat',
      displayName: 'Goat',
      facilityFee: 40.0,
      permitToSlaughterFee: 40.0,
      vetHealthCertFee: 30.0,
      corralFee: 25.0,
      anteMortemFee: 25.0,
      postMortemRatePerKg: 4.0,
      deliveryVanFee: 40.0,
      additionalFee: 0.0,
      additionalFeeLabel: 'Additional Administrative Charge',
    ),
    'sheep': const LivestockFeeSchedule(
      animalType: 'sheep',
      displayName: 'Sheep',
      facilityFee: 40.0,
      permitToSlaughterFee: 40.0,
      vetHealthCertFee: 30.0,
      corralFee: 25.0,
      anteMortemFee: 25.0,
      postMortemRatePerKg: 4.0,
      deliveryVanFee: 40.0,
      additionalFee: 0.0,
      additionalFeeLabel: 'Additional Administrative Charge',
    ),
    'poultry': const LivestockFeeSchedule(
      animalType: 'poultry',
      displayName: 'Poultry (Chicken / Turkey / Duck)',
      facilityFee: 20.0,
      permitToSlaughterFee: 20.0,
      vetHealthCertFee: 15.0,
      corralFee: 10.0,
      anteMortemFee: 10.0,
      postMortemRatePerKg: 2.5,
      deliveryVanFee: 25.0,
      additionalFee: 0.0,
      additionalFeeLabel: 'Additional Administrative Charge',
    ),
  };

  RealtimeChannel? _realtimeChannel;
  bool _isInitialized = false;

  Map<String, LivestockFeeSchedule> get schedules => Map.unmodifiable(_schedules);

  LivestockFeeSchedule getFeeSchedule(String? animal) {
    if (animal == null) return _schedules['hog']!;
    final lower = animal.toLowerCase().trim();
    if (_schedules.containsKey(lower)) {
      return _schedules[lower]!;
    }
    if (lower.contains('hog') || lower.contains('pig') || lower.contains('swine')) {
      return _schedules['hog']!;
    }
    if (lower.contains('cattle') || lower.contains('cow') || lower.contains('bovine')) {
      return _schedules['cattle']!;
    }
    if (lower.contains('cara') || lower.contains('buffalo')) {
      return _schedules['carabao']!;
    }
    if (lower.contains('goat') || lower.contains('caprine')) {
      return _schedules['goat']!;
    }
    if (lower.contains('sheep') || lower.contains('ovine')) {
      return _schedules['sheep']!;
    }
    if (lower.contains('poultry') || lower.contains('chicken') || lower.contains('turkey') || lower.contains('duck') || lower.contains('fowl')) {
      return _schedules['poultry']!;
    }
    return _schedules['hog']!;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // 1. Immediately restore cached fees from SharedPreferences if available
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJsonStr = prefs.getString('cached_livestock_fees');
      if (cachedJsonStr != null) {
        final Map<String, dynamic> val = jsonDecode(cachedJsonStr);
        _applyFeeMap(val);
      }
    } catch (e) {
      debugPrint('LivestockFeeService cache restore error: $e');
    }

    // 2. Fetch latest fees from Supabase & listen for realtime changes
    await fetchFeesFromSupabase();
    _subscribeToRealtime();
  }

  void _applyFeeMap(Map<String, dynamic> val) {
    val.forEach((key, raw) {
      if (raw is Map) {
        final k = key.toLowerCase().trim();
        String displayName;
        switch (k) {
          case 'hog':
            displayName = 'Pig / Hog';
            break;
          case 'cattle':
            displayName = 'Cow / Cattle';
            break;
          case 'carabao':
            displayName = 'Carabao (Water Buffalo)';
            break;
          case 'goat':
            displayName = 'Goat';
            break;
          case 'sheep':
            displayName = 'Sheep';
            break;
          case 'poultry':
            displayName = 'Poultry (Chicken / Turkey / Duck)';
            break;
          default:
            displayName = k.isNotEmpty ? (k[0].toUpperCase() + k.substring(1)) : 'Livestock';
        }

        _schedules[k] = LivestockFeeSchedule.fromJson(
          k,
          displayName,
          Map<String, dynamic>.from(raw),
        );
      }
    });

    if (val.containsKey('poultry') && val['poultry'] is Map) {
      _schedules['poultry'] = LivestockFeeSchedule.fromJson(
        'poultry',
        'Poultry (Chicken / Turkey / Duck)',
        Map<String, dynamic>.from(val['poultry'] as Map),
      );
    }
  }

  Future<void> _ensureAuth() async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) {
      try {
        await client.auth.signInWithPassword(
          email: 'public.viewer@tabaco.gov.ph',
          password: 'ViewerPassword123!',
        );
      } catch (e) {
        debugPrint('LivestockFeeService viewer auth note: $e');
      }
    }
  }

  Future<void> fetchFeesFromSupabase() async {
    try {
      final client = Supabase.instance.client;
      dynamic res;
      try {
        res = await client
            .from('system_settings')
            .select('value')
            .eq('key', 'fee_schedules')
            .maybeSingle();
      } catch (_) {
        await _ensureAuth();
        res = await client
            .from('system_settings')
            .select('value')
            .eq('key', 'fee_schedules')
            .maybeSingle();
      }

      if (res != null && res['value'] != null) {
        final rawVal = res['value'];
        final Map<String, dynamic> val = rawVal is String
            ? jsonDecode(rawVal) as Map<String, dynamic>
            : Map<String, dynamic>.from(rawVal as Map);

        _applyFeeMap(val);

        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('cached_livestock_fees', jsonEncode(val));
        } catch (_) {}

        notifyListeners();
      }
    } catch (e) {
      debugPrint('LivestockFeeService fetch error: $e');
    }
  }

  void _subscribeToRealtime() {
    try {
      _realtimeChannel = Supabase.instance.client
          .channel('public:system_settings_fees')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'system_settings',
            callback: (payload) {
              fetchFeesFromSupabase();
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('LivestockFeeService realtime subscribe error: $e');
    }
  }

  @override
  void dispose() {
    if (_realtimeChannel != null) {
      Supabase.instance.client.removeChannel(_realtimeChannel!);
    }
    super.dispose();
  }
}

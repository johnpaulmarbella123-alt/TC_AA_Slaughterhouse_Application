import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'report_illegal_slaughter_screen.dart';
import 'how_it_works.dart';
import '../services/document_verifier.dart';
import '../utils/text_capitalization_formatters.dart';

class RequestsContent extends StatefulWidget {
  const RequestsContent({super.key});

  @override
  State<RequestsContent> createState() => _RequestsContentState();
}

const List<Map<String, String>> albayMunicipalities = [
  {"code": "050517000", "name": "City of Tabaco"},
  {"code": "050501000", "name": "Bacacay"},
  {"code": "050502000", "name": "Camalig"},
  {"code": "050503000", "name": "Daraga"},
  {"code": "050504000", "name": "Guinobatan"},
  {"code": "050505000", "name": "Jovellar"},
  {"code": "050506000", "name": "City of Legazpi"},
  {"code": "050507000", "name": "Libon"},
  {"code": "050508000", "name": "City of Ligao"},
  {"code": "050509000", "name": "Malilipot"},
  {"code": "050510000", "name": "Malinao"},
  {"code": "050511000", "name": "Manito"},
  {"code": "050512000", "name": "Oas"},
  {"code": "050513000", "name": "Pio Duran"},
  {"code": "050514000", "name": "Polangui"},
  {"code": "050515000", "name": "Rapu-Rapu"},
  {"code": "050516000", "name": "Santo Domingo"},
  {"code": "050518000", "name": "Tiwi"},
];

const List<String> tabacoBarangays = [
  "Agnas", "Bacolod", "Bangkilingan", "Bantayan", "Baranghawon", "Basagan", "Basud (Pob.)",
  "Bogñabong", "Bombon (Pob.)", "Bonot", "San Isidro", "Buang", "Buhian", "Cabagñan",
  "Cobo", "Comon", "Cormidal", "Divino Rostro (Pob.)", "Fatima", "Guinobat", "Hacienda",
  "Magapo", "Mariroc", "Matagbac", "Oras", "Oson", "Panal", "Pawa", "Pinagbobong",
  "Quinale Cabasan (Pob.)", "Quinastillojan", "Rawis", "Sagurong", "Salvacion",
  "San Antonio", "San Carlos", "San Juan (Pob.)", "San Lorenzo", "San Ramon",
  "San Roque", "San Vicente", "Santo Cristo (Pob.)", "Sua-Igot", "Tabiguian",
  "Tagas", "Tayhi (Pob.)", "Visita"
];

class _RequestsContentState extends State<RequestsContent> {
  final supabase = Supabase.instance.client;

  // moved out of top-level globals into proper state
  bool isSubmitted = false;
  bool isLoading = false;

  bool isBarangay = true; // Requests is active
  final ImagePicker picker = ImagePicker();

  // --- controllers for the fields that were not wired up before ---
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _animalCountController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _marketStallController = TextEditingController();
  final TextEditingController _marketNameController = TextEditingController();
  final TextEditingController _specialInstructionsController = TextEditingController();
  final TextEditingController _markingController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();

  String _customerName = '';
  bool _isMarkingLocked = false;
  bool _isCustomerNameLocked = false;
  bool _isRegularDealer = false;
  bool? _isRoleLocked = false;
  bool? _isProfileLoading = true;
  String? _pendingSelectedRole = 'barangay';
  bool get _roleLocked => _isRoleLocked ?? false;
  bool get _profileLoading => _isProfileLoading ?? false;
  String get _selectedRoleKey => _pendingSelectedRole ?? 'barangay';
  StreamSubscription<AuthState>? _authSubscription;

  String? selectedLivestock;

  List municipalities = List.from(albayMunicipalities);
  List barangays = [];

  String? selectedProvince = "Albay";
  String? selectedProvinceCode = "050500000";

  String? selectedMunicipality;
  String? selectedMunicipalityCode;

  String? selectedBarangay;

  String? barangayCertificateUrl;
  String? businessPermitUrl;
  String? ownershipUrl;
  String? vetCertificateUrl;
  String selectedDocType = "Barangay Certificate";

  @override
  void initState() {
    super.initState();
    loadMunicipalities(selectedProvinceCode!);
    _loadCustomerProfile();

    _authSubscription = supabase.auth.onAuthStateChange.listen((data) {
      if (data.session?.user != null) {
        _loadCustomerProfile();
      }
    });
  }

  Future<void> _loadCustomerProfile() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isProfileLoading = false);
        return;
      }

      // 1. Try immediate load from user metadata
      final meta = user.userMetadata;
      String? resolvedName = (meta?['display_name'] ?? meta?['full_name'] ?? meta?['name'])?.toString().trim();
      String? resolvedMarking;
      String? resolvedRole;
      bool isLocked = false;
      bool isCustNameLocked = false;
      bool isRegular = false;
      bool hasAuthoritativeRoleLock =
          meta?['role_confirmed'] == true || meta?['role_confirmed']?.toString() == 'true';
      String? officialDealerName;

      final metaRole = meta?['dealer_category']?.toString().trim().toLowerCase();
      if (hasAuthoritativeRoleLock && (metaRole == 'barangay' || metaRole == 'market')) {
        resolvedRole = metaRole;
      }

      // 2. Fetch latest profile from DB first so we also know display_name / address / dealer_category
      Map<String, dynamic>? profile;
      try {
        final res = await supabase
            .from('profiles')
            .select('display_name, address, assigned_marking, marking_locked, official_dealer_name, customer_type, dealer_category, role_confirmed, barangay, market_name, stall_number, role_document_url')
            .eq('id', user.id)
            .maybeSingle();
        if (res != null) profile = Map<String, dynamic>.from(res);
      } catch (_) {
        try {
          final res = await supabase
              .from('profiles')
              .select('display_name, address, assigned_marking, marking_locked, official_dealer_name, customer_type, dealer_category')
              .eq('id', user.id)
              .maybeSingle();
          if (res != null) profile = Map<String, dynamic>.from(res);
        } catch (_) {
          try {
            final res = await supabase
                .from('profiles')
                .select('display_name, address')
                .eq('id', user.id)
                .maybeSingle();
            if (res != null) profile = Map<String, dynamic>.from(res);
          } catch (_) {}
        }
      }

      if (profile != null) {
        if (profile['display_name'] != null && profile['display_name'].toString().trim().isNotEmpty) {
          resolvedName ??= profile['display_name'].toString().trim();
        }
        if (profile['official_dealer_name'] != null && profile['official_dealer_name'].toString().trim().isNotEmpty) {
          officialDealerName = profile['official_dealer_name'].toString().trim();
        }
        if (profile['assigned_marking'] != null && profile['assigned_marking'].toString().trim().isNotEmpty) {
          resolvedMarking = profile['assigned_marking'].toString().trim().toUpperCase();
        }
        if (profile['marking_locked'] == true || profile['marking_locked'].toString() == 'true') {
          isLocked = true;
        }
        if (profile['customer_type'] == 'regular' || isLocked) {
          isRegular = true;
          isCustNameLocked = true;
        }
        if (profile['role_confirmed'] == true || profile['role_confirmed'].toString() == 'true') {
          hasAuthoritativeRoleLock = true;
        }
        final profCategory = profile['dealer_category']?.toString().trim().toLowerCase();
        // NOTE: `profiles.dealer_category` has a DB column default of 'barangay' on sign-up,
        // so only trust `profCategory` if the user already has a locked marking or confirmed their role.
        if ((isLocked || hasAuthoritativeRoleLock) &&
            (profCategory == 'barangay' || profCategory == 'market')) {
          resolvedRole ??= profCategory;
          hasAuthoritativeRoleLock = true;
        }
        final profBrgy = profile['barangay']?.toString().trim();
        if (profBrgy != null && profBrgy.isNotEmpty) {
          selectedBarangay ??= profBrgy;
        }
        final profMarket = profile['market_name']?.toString().trim();
        if (profMarket != null && profMarket.isNotEmpty && _marketNameController.text.isEmpty) {
          _marketNameController.text = profMarket;
        }
        final profStall = profile['stall_number']?.toString().trim();
        if (profStall != null && profStall.isNotEmpty && _marketStallController.text.isEmpty) {
          _marketStallController.text = profStall;
        }
        final profDocUrl = profile['role_document_url']?.toString().trim();
        if (profDocUrl != null && profDocUrl.isNotEmpty) {
          if (profCategory == 'market') {
            businessPermitUrl ??= profDocUrl;
          } else if (profCategory == 'barangay') {
            barangayCertificateUrl ??= profDocUrl;
          }
        }
      }

      // 3. Check if linked to an official regular dealer in system_settings (authoritative Admin record)
      try {
        final regRow = await supabase
            .from('system_settings')
            .select('value')
            .eq('key', 'regular_dealers')
            .maybeSingle();

        if (regRow != null && regRow['value'] != null) {
          final rawVal = regRow['value'];
          final List<dynamic> regList = rawVal is String
              ? List<dynamic>.from(jsonDecode(rawVal))
              : (rawVal is List ? List<dynamic>.from(rawVal) : []);

          final normCandidateName = (officialDealerName ?? resolvedName ?? '').trim().toLowerCase();
          for (var item in regList) {
            if (item is Map) {
              final uId = (item['user_id'] ?? item['userId'])?.toString().trim();
              final itemName = (item['name'] ?? '').toString().trim();
              final itemMarking = (item['markings'] ?? item['marking'] ?? '').toString().trim().toUpperCase();
              final itemCat = (item['category'] ?? '').toString().trim().toLowerCase();
              if (uId != null && uId.isNotEmpty && uId != user.id) {
                continue; // Belongs to a different user account
              }
              final matchesUser = uId != null && uId.isNotEmpty && uId == user.id;
              final matchesName = (uId == null || uId.isEmpty) &&
                  normCandidateName.isNotEmpty &&
                  itemName.toLowerCase() == normCandidateName;
              if (matchesUser || matchesName) {
                if (itemName.isNotEmpty) officialDealerName = itemName;
                if (itemMarking.isNotEmpty) resolvedMarking = itemMarking;
                if (itemCat == 'barangay' || itemCat == 'market') {
                  resolvedRole = itemCat;
                  hasAuthoritativeRoleLock = true;
                }
                isRegular = true;
                isLocked = true;
                isCustNameLocked = true;
                break;
              }
            }
          }
        }
      } catch (_) {}

      // 4. Always check user's first submitted request for marking or request_type (barangay vs market)
      if (resolvedMarking == null || resolvedMarking.isEmpty || !hasAuthoritativeRoleLock) {
        try {
          final pastReq = await supabase
              .from('requests')
              .select('marking, customer_name, request_type')
              .eq('user_id', user.id)
              .not('status', 'in', '("rejected","cancelled")')
              .order('created_at', ascending: true)
              .limit(1)
              .maybeSingle();
          if (pastReq != null) {
            final m = pastReq['marking']?.toString().trim().toUpperCase();
            if (m != null && m.isNotEmpty) {
              resolvedMarking ??= m;
              isLocked = true;
              isCustNameLocked = true;
              isRegular = true;
            }
            final rType = pastReq['request_type']?.toString().trim().toLowerCase();
            if (rType == 'barangay' || rType == 'market') {
              resolvedRole = rType;
              hasAuthoritativeRoleLock = true;
            }
            final cName = pastReq['customer_name']?.toString().trim();
            if ((officialDealerName == null || officialDealerName.isEmpty) && cName != null && cName.isNotEmpty) {
              officialDealerName = cName;
            }
          }
        } catch (_) {}
      }

      // 5. Fallback to userMetadata assigned_marking if locked earlier
      if ((resolvedMarking == null || resolvedMarking.isEmpty) && meta != null) {
        final metaMark = meta['assigned_marking']?.toString().trim().toUpperCase();
        if (metaMark != null && metaMark.isNotEmpty) {
          resolvedMarking = metaMark;
          isLocked = true;
          isCustNameLocked = true;
          isRegular = true;
        }
      }

      // Reconcile official name
      if (officialDealerName != null && officialDealerName.isNotEmpty) {
        resolvedName = officialDealerName;
      }

      // Fallback if still empty: email username
      if ((resolvedName == null || resolvedName.isEmpty) && user.email != null) {
        resolvedName = user.email!.split('@').first;
      }

      if (resolvedName != null && resolvedName.isNotEmpty && mounted) {
        setState(() {
          _customerName = resolvedName!;
          _customerNameController.text = resolvedName;
          _isCustomerNameLocked = isCustNameLocked;
          _isRegularDealer = isRegular;
        });
      }

      // Also pre-fill address if available and field is empty
      if (profile != null && profile['address'] != null && profile['address'].toString().trim().isNotEmpty) {
        final profileAddress = profile['address'].toString().trim();
        if (_addressController.text.trim().isEmpty && mounted) {
          setState(() {
            _addressController.text = profileAddress;
          });
        }
      }

      // NOTE: Do NOT pre-fill initials for first-time dealers!
      // Only populate _markingController when the user already has a locked marking.
      if (mounted) {
        setState(() {
          if (resolvedMarking != null && resolvedMarking.isNotEmpty) {
            _markingController.text = resolvedMarking;
            _isMarkingLocked = true;
          } else {
            _markingController.clear();
            _isMarkingLocked = false;
          }
          if (hasAuthoritativeRoleLock && (resolvedRole == 'barangay' || resolvedRole == 'market')) {
            _isRoleLocked = true;
            isBarangay = (resolvedRole == 'barangay');
            _pendingSelectedRole = resolvedRole!;
          } else {
            _isRoleLocked = false;
          }
          _isProfileLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading customer profile: $e');
      if (mounted) setState(() => _isProfileLoading = false);
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _customerNameController.dispose();
    _animalCountController.dispose();
    _addressController.dispose();
    _marketStallController.dispose();
    _marketNameController.dispose();
    _specialInstructionsController.dispose();
    _markingController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  // ---------------- SUBMIT ----------------

  Future<void> submitRequest() async {
    // basic validation so you don't send empty junk to Supabase
    if (_customerNameController.text.trim().isEmpty ||
        selectedLivestock == null ||
        _animalCountController.text.trim().isEmpty ||
        selectedProvince == null ||
        selectedMunicipality == null ||
        selectedBarangay == null ||
        _addressController.text.trim().isEmpty ||
        _dateController.text.trim().isEmpty ||
        _markingController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in all required fields (including Livestock Marking)")),
      );
      return;
    }

    if (!isBarangay &&
        (_marketNameController.text.trim().isEmpty ||
            _marketStallController.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter both Market Name and Stall Number for Market requests"),
        ),
      );
      return;
    }

    if (ownershipUrl == null ||
        (isBarangay && barangayCertificateUrl == null) ||
        (!isBarangay && businessPermitUrl == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please upload all required documents")),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please login first")),
        );
        setState(() => isLoading = false);
        return;
      }

      final markingInput = _markingController.text.trim().toUpperCase();

      // For a new dealer entering their own marking on their first request,
      // enforce 1 to 5 alphanumeric characters (letters or numbers).
      if (!_isMarkingLocked) {
        if (!RegExp(r'^[A-Z0-9]{1,5}$').hasMatch(markingInput)) {
          setState(() => isLoading = false);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Livestock Marking must be 1 to 5 letters or numbers (e.g., PAUL, BINO, MK1)."),
            ),
          );
          return;
        }

        // Also check if another registered dealer in system_settings already owns this marking
        try {
          final regRow = await supabase
              .from('system_settings')
              .select('value')
              .eq('key', 'regular_dealers')
              .maybeSingle();
          if (regRow != null && regRow['value'] != null) {
            final rawVal = regRow['value'];
            final List<dynamic> regList = rawVal is String
                ? List<dynamic>.from(jsonDecode(rawVal))
                : (rawVal is List ? List<dynamic>.from(rawVal) : []);
            final normMyName = _customerNameController.text.trim().toLowerCase();
            final takenByOther = regList.any((item) {
              if (item is! Map) return false;
              final m = (item['markings'] ?? item['marking'] ?? '').toString().trim().toUpperCase();
              if (m != markingInput) return false;
              final uId = (item['user_id'] ?? item['userId'])?.toString().trim();
              final iName = (item['name'] ?? '').toString().trim().toLowerCase();
              if (uId != null && uId.isNotEmpty && uId == user.id) return false;
              if (iName == normMyName) return false;
              return true;
            });
            if (takenByOther) {
              setState(() => isLoading = false);
              if (!mounted) return;
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 48),
                  title: const Text("Marking Already Registered", style: TextStyle(fontWeight: FontWeight.bold)),
                  content: Text(
                    "The marking '$markingInput' is already permanently registered to another dealer.\n\n"
                    "Please enter a different unique combination of 1 to 5 letters or numbers.",
                  ),
                  actions: [
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E855A)),
                      child: const Text("Change Marking"),
                    ),
                  ],
                ),
              );
              return;
            }
          }
        } catch (_) {}
      }

      // Check if marking is already used by another user's active request
      final conflicting = await supabase
          .from('requests')
          .select('id, marking, status, user_id')
          .ilike('marking', markingInput)
          .neq('user_id', user.id)
          .not('status', 'in', '("completed","cancelled","rejected","released")')
          .limit(1);

      if (conflicting.isNotEmpty) {
        setState(() => isLoading = false);
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 48),
            title: const Text("Marking Already In Use", style: TextStyle(fontWeight: FontWeight.bold)),
            content: Text(
              "The livestock marking '$markingInput' is currently assigned to another dealer's active request.\n\n"
              "To prevent animal mix-ups during slaughter and holding, please choose a unique marking (1 to 5 letters or numbers).",
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E855A)),
                child: const Text("Change Marking"),
              ),
            ],
          ),
        );
        return;
      }

      // convert dd/mm/yyyy -> yyyy-mm-dd for a Postgres `date` column
      final parts = _dateController.text.split('/');
      final preferredDateIso =
          "${parts[2]}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}";
      final parsedPreferred = DateTime.tryParse(preferredDateIso);
      final nowLocal = DateTime.now();
      final todayStart = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
      if (parsedPreferred == null || parsedPreferred.isBefore(todayStart)) {
        setState(() => isLoading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Preferred date cannot be in the past. Please select today or a future date."),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final finalMarking = markingInput;
      final finalCustomerName = _customerNameController.text.trim();

      // Persist permanent marking & dealer_category in user_metadata & profiles so it stays locked across sessions
      try {
        await supabase.auth.updateUser(
          UserAttributes(
            data: {
              'assigned_marking': finalMarking,
              'marking_locked': true,
              'official_dealer_name': finalCustomerName,
              'dealer_category': isBarangay ? 'barangay' : 'market',
              'role_confirmed': true,
            },
          ),
        );
      } catch (_) {}

      try {
        await supabase.from('profiles').update({
          'assigned_marking': finalMarking,
          'marking_locked': true,
          'dealer_category': isBarangay ? 'barangay' : 'market',
        }).eq('id', user.id);
      } catch (_) {}

      // Also sync into system_settings ('regular_dealers') with strict user_id isolation
      try {
        final regRow = await supabase
            .from('system_settings')
            .select('value')
            .eq('key', 'regular_dealers')
            .maybeSingle();
        List<dynamic> regList = [];
        if (regRow != null && regRow['value'] != null) {
          final rawVal = regRow['value'];
          regList = rawVal is String
              ? List<dynamic>.from(jsonDecode(rawVal))
              : (rawVal is List ? List<dynamic>.from(rawVal) : []);
        }
        final existingIdx = regList.indexWhere((item) {
          if (item is! Map) return false;
          final uId = (item['user_id'] ?? item['userId'])?.toString().trim();
          final iName = (item['name'] ?? '').toString().trim().toLowerCase();
          if (uId != null && uId.isNotEmpty && uId != user.id) return false;
          return (uId != null && uId.isNotEmpty && uId == user.id) ||
              iName == finalCustomerName.toLowerCase();
        });
        final categoryStr = isBarangay ? 'barangay' : 'market';
        if (existingIdx >= 0) {
          final mapItem = Map<String, dynamic>.from(regList[existingIdx] as Map);
          mapItem['user_id'] = user.id;
          if ((mapItem['markings'] ?? '').toString().trim().isEmpty) {
            mapItem['markings'] = finalMarking;
          }
          regList[existingIdx] = mapItem;
        } else {
          int maxNum = 0;
          for (final item in regList) {
            if (item is Map && (item['category'] ?? 'barangay') == categoryStr) {
              final numVal = int.tryParse((item['dealer_number'] ?? '0').toString()) ?? 0;
              if (numVal > maxNum) maxNum = numVal;
            }
          }
          regList.add({
            'id': 'dlr-${DateTime.now().millisecondsSinceEpoch}',
            'dealer_number': maxNum + 1,
            'name': finalCustomerName.toUpperCase(),
            'markings': finalMarking,
            'category': categoryStr,
            'phone': '',
            'user_id': user.id,
            'is_active': true,
            'created_at': DateTime.now().toIso8601String(),
          });
        }
        await supabase.from('system_settings').upsert({
          'key': 'regular_dealers',
          'value': jsonEncode(regList),
          'updated_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}

      // 1. Insert request with all the fields your schema actually has
      final request = await supabase
          .from('requests')
          .insert({
            'user_id': user.id,
            'request_type': isBarangay ? 'barangay' : 'market',
            'customer_name': _customerNameController.text.trim(),
            'livestock_type': selectedLivestock,
            'animal_count': int.tryParse(_animalCountController.text.trim()) ?? 0,
            'province': selectedProvince,
            'municipality': selectedMunicipality,
            'barangay': selectedBarangay,
            'address': _addressController.text.trim(),
            'market_stall_number': !isBarangay ? _marketStallController.text.trim() : null,
            'market_name': !isBarangay ? _marketNameController.text.trim() : null,
            'preferred_date': preferredDateIso,
            'marking': finalMarking,
            'special_instruction': _specialInstructionsController.text.trim(),
            'barangay_certificate': barangayCertificateUrl,
            'business_permit': businessPermitUrl,
            'proof_of_ownership': ownershipUrl,
            'vet_certificate': vetCertificateUrl,
            'status': 'pending',
          })
          .select()
          .single();

      // 2. Reference number, e.g. MI-2026-001, built from the new row's id
      final refNo = "MI-${DateTime.now().year}-${request['id'].toString().padLeft(3, '0')}";

      // 3. Insert notification — using the REAL columns from your schema
      //    (title, message, is_read, type) — not 'body' / 'reference_no'
      try {
        await supabase.from('notifications').insert({
          'user_id': user.id,
          'title': 'Request submitted successfully',
          'message':
              'Your slaughter request is being processed. wait for approval\nRef: $refNo',
          'is_read': false,
          'type': 'request_submitted',
        });
        debugPrint('NOTIF INSERT: Success for $refNo');
      } catch (notifError) {
        debugPrint('NOTIF INSERT FAILED: $notifError');
        // Don't block request success — just log the error
      }

      setState(() {
        isSubmitted = true;
        isLoading = false;
        _isMarkingLocked = true;
        _isCustomerNameLocked = true;
        _isRegularDealer = true;
        _isRoleLocked = true;
        _customerName = finalCustomerName;
        _markingController.text = finalMarking;
      });

      if (!mounted) return;
      _showSuccessBanner(refNo);
      _resetForm();
    } catch (e) {
      setState(() => isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error submitting request: $e")),
      );
    }
  }

  void _resetForm() {
    if (_customerName.isNotEmpty) {
      _customerNameController.text = _customerName;
    } else {
      _customerNameController.clear();
    }
    _animalCountController.clear();
    _addressController.clear();
    _marketStallController.clear();
    _marketNameController.clear();
    _specialInstructionsController.clear();
    if (!_isMarkingLocked) {
      _markingController.clear();
    }
    _dateController.clear();
    setState(() {
      selectedLivestock = null;
      selectedProvince = "Albay";
      selectedProvinceCode = "050500000";
      municipalities = List.from(albayMunicipalities);
      selectedMunicipality = null;
      selectedBarangay = null;
      barangayCertificateUrl = null;
      businessPermitUrl = null;
      ownershipUrl = null;
      vetCertificateUrl = null;
    });
  }

  // Success popup styled like the "Request submitted successfully" card
  void _showSuccessBanner(String refNo) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle, color: Color(0xFF1E855A), size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Request submitted successfully",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Your slaughter request is being processed. wait for approved.\nRef: $refNo",
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  "Just now",
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(entry);
    Future.delayed(const Duration(seconds: 4), () {
      entry.remove();
    });
  }

  // ---------------- DOCUMENT PICKER ----------------

  Future<void> _pickDocument(String type) async {
    // 1. Choose source: Camera, Gallery, or Device Files
    final selection = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                "Upload $type",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                child: Text(
                  "Please provide a scanned copy or clear photo of the official document.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFF1E855A)),
                title: const Text("Take Photo"),
                subtitle: const Text("Capture the physical certificate directly"),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Color(0xFF1E855A)),
                title: const Text("Select from Gallery"),
                subtitle: const Text("Choose image from your photo album"),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.folder_open, color: Color(0xFF1E855A)),
                title: const Text("Choose Files"),
                subtitle: const Text("Select image or scanned document file"),
                onTap: () => Navigator.pop(context, 'files'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (selection == null) return;

    File? selectedFile;
    Uint8List? selectedBytes;

    try {
      if (selection == 'camera') {
        final XFile? image = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 70,
        );
        if (image != null) {
          selectedBytes = await image.readAsBytes();
          if (!kIsWeb) {
            try {
              selectedFile = File(image.path);
            } catch (_) {}
          }
        }
      } else if (selection == 'gallery') {
        final XFile? image = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 70,
        );
        if (image != null) {
          selectedBytes = await image.readAsBytes();
          if (!kIsWeb) {
            try {
              selectedFile = File(image.path);
            } catch (_) {}
          }
        }
      } else if (selection == 'files') {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
          withData: true,
        );
        if (result != null && result.files.isNotEmpty) {
          selectedBytes = result.files.single.bytes;
          if (!kIsWeb && result.files.single.path != null) {
            try {
              selectedFile = File(result.files.single.path!);
              selectedBytes ??= await selectedFile.readAsBytes();
            } catch (_) {}
          }
        }
      }

      if (selectedBytes == null || selectedBytes.isEmpty) return;
      if (!mounted) return;

      // 2. File size check
      final int fileSize = selectedBytes.length;
      if (fileSize < 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Selected file is too small. Please provide a clear scanned certificate."),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // 3. Display Analyzing Dialog
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            content: Row(
              children: const [
                CircularProgressIndicator(color: Color(0xFF1E855A)),
                SizedBox(width: 20),
                Expanded(
                  child: Text(
                    "Verifying certificate authenticity...",
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // 4. Perform On-Device OCR & Document Verification
      final verification = await DocumentVerifier.verifyCertificate(
        imageFile: selectedFile,
        imageBytes: selectedBytes,
        documentType: type,
      );

      // Dismiss analyzing dialog
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (!mounted) return;

      // 5. If rejected, display clear alert & block upload
      if (!verification.isValid) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 52),
            title: const Text(
              "Certificate Not Detected",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  verification.message,
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Icon(Icons.info_outline, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Photos of people, random objects, animals, or illegible scans cannot be accepted. Please ensure the official header, certificate title, and seal are visible.",
                          style: TextStyle(fontSize: 12, color: Colors.red, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Try Again", style: TextStyle(color: Color(0xFF1E855A))),
              ),
            ],
          ),
        );
        return;
      }

      // 6. If verified, show preview confirmation before final upload
      final bool? proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.verified, color: Color(0xFF1E855A), size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Legitimate Certificate",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    selectedBytes!,
                    height: 190,
                    width: double.infinity,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Target: $type",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Detected Official Markers:",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: verification.detectedKeywords.take(6).map((k) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF81C784)),
                      ),
                      child: Text(
                        k,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Click 'Upload' to attach this verified document to your request.",
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E855A),
                foregroundColor: Colors.white,
              ),
              child: const Text("Upload Document"),
            ),
          ],
        ),
      );

      if (proceed != true) return;

      final user = supabase.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please login first")),
        );
        return;
      }

      // 7. Upload to Supabase Storage
      final fileName = "${DateTime.now().millisecondsSinceEpoch}.jpg";
      final filePath = "${user.id}/$fileName";

      await supabase.storage.from('request-documents').uploadBinary(
        filePath,
        selectedBytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
      );
      String url;
      try {
        url = await supabase.storage
            .from('request-documents')
            .createSignedUrl(filePath, 60 * 60 * 24 * 30);
      } catch (_) {
        url = supabase.storage.from('request-documents').getPublicUrl(filePath);
      }

      setState(() {
        if (type == "Barangay Certificate") {
          barangayCertificateUrl = url;
        } else if (type == "Business Permit") {
          businessPermitUrl = url;
        } else if (type == "Proof of Ownership") {
          ownershipUrl = url;
        } else if (type == "Health certificate from veterinarian(optional)") {
          vetCertificateUrl = url;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✓ $type verified and uploaded successfully"),
            backgroundColor: const Color(0xFF1E855A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Upload Error: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  Future<void> loadMunicipalities(String provinceCode) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://psgc.gitlab.io/api/provinces/$provinceCode/cities-municipalities/',
        ),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final list = jsonDecode(response.body);
        if (mounted && list is List && list.isNotEmpty) {
          setState(() {
            municipalities = list;
          });
        }
      }
    } catch (e) {
      debugPrint('Notice: using pre-bundled Albay municipalities: $e');
      if (mounted && municipalities.isEmpty) {
        setState(() {
          municipalities = List.from(albayMunicipalities);
        });
      }
    }
  }

  Future<void> loadBarangays(String municipalityCode) async {
    // If Tabaco City or name matches, use instant preloaded barangays
    if (municipalityCode == "050517000" || selectedMunicipality == "City of Tabaco") {
      setState(() {
        barangays = tabacoBarangays.map((name) => {'name': name}).toList();
        selectedBarangay = null;
      });
      return;
    }

    try {
      final response = await http.get(
        Uri.parse(
          'https://psgc.gitlab.io/api/cities-municipalities/$municipalityCode/barangays/',
        ),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final list = jsonDecode(response.body);
        if (mounted && list is List) {
          setState(() {
            barangays = list;
            selectedBarangay = null;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading barangays: $e');
    }
  }

  Future<void> _showRoleConfirmationDialog() async {
    final bool isChoosingBarangay = _selectedRoleKey == 'barangay';
    final String roleTitle = isChoosingBarangay ? 'Barangay Dealer' : 'Market Dealer';

    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: Color(0xFFFFF8E1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFD97706),
            size: 36,
          ),
        ),
        title: const Text(
          "Confirm Permanent Dealer Role",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF81C784)),
              ),
              child: Row(
                children: [
                  Icon(
                    isChoosingBarangay ? Icons.home_work_outlined : Icons.storefront_outlined,
                    color: const Color(0xFF1E855A),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Selected Role:",
                          style: TextStyle(fontSize: 11, color: Colors.black54),
                        ),
                        Text(
                          roleTitle,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1B5E20),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline, color: Color(0xFFB45309), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Reminder: Once you confirm this choice, your account will be permanently assigned to this dealer role for this and all future bookings. You will not be able to switch between Barangay and Market later.",
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF92400E),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text("Go Back"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E855A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text(
                    "Confirm Role",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      isBarangay = isChoosingBarangay;
      _isRoleLocked = true;
    });

    final user = supabase.auth.currentUser;
    final chosenRole = _selectedRoleKey;
    if (user != null) {
      try {
        await supabase.auth.updateUser(
          UserAttributes(
            data: {
              'dealer_category': chosenRole,
              'role_confirmed': true,
            },
          ),
        );
      } catch (_) {}

      try {
        await supabase.from('profiles').update({
          'dealer_category': chosenRole,
          'role_confirmed': true,
          'barangay': isChoosingBarangay ? selectedBarangay : null,
          'market_name': !isChoosingBarangay ? _marketNameController.text.trim() : null,
          'stall_number': !isChoosingBarangay ? _marketStallController.text.trim() : null,
          'role_document_url': isChoosingBarangay ? barangayCertificateUrl : businessPermitUrl,
        }).eq('id', user.id);
      } catch (_) {}
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Role permanently set to $roleTitle. You may now create your request."),
        backgroundColor: const Color(0xFF1E855A),
      ),
    );
  }

  Widget _buildRoleSelectionView(BuildContext context) {
    final bool isChoosingBarangay = _selectedRoleKey == 'barangay';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stepper indicator: Choose Role -> Create Request -> Submit
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildStepPill("1", "Choose Role", true),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                  ),
                  _buildStepPill("2", "Create Request", false),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                  ),
                  _buildStepPill("3", "Submit", false),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Choose Your Dealer Role",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Since you are new to booking, please select whether you are registering as a Barangay Dealer or a Market Dealer.",
                  style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.35),
                ),
                const SizedBox(height: 18),

                // Option 1: Barangay
                _buildRoleOptionCard(
                  roleKey: 'barangay',
                  title: "Barangay Dealer",
                  subtitle: "For barangay residents, livestock owners, and community meat dealers",
                  requirements: "Requires: Barangay Address, Barangay Certificate, Proof of Ownership, and optional Vet Health Certificate.",
                  icon: Icons.home_work_outlined,
                  isSelected: isChoosingBarangay,
                ),
                const SizedBox(height: 14),

                // Option 2: Market
                _buildRoleOptionCard(
                  roleKey: 'market',
                  title: "Market Dealer",
                  subtitle: "For public market stallholders and commercial meat vendors",
                  requirements: "Requires: Market Name, Stall Number, Business Permit, Proof of Ownership, and optional Vet Health Certificate.",
                  icon: Icons.storefront_outlined,
                  isSelected: !isChoosingBarangay,
                ),
                const SizedBox(height: 18),

                // Required Role Verification Fields & Document Upload
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isChoosingBarangay
                            ? "Barangay Role Requirements"
                            : "Market Role Requirements",
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isChoosingBarangay
                            ? "Select your barangay and upload a valid Barangay Certificate to unlock this role."
                            : "Enter your market name, stall number, and upload a valid Business Permit to unlock this role.",
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 12),
                      if (isChoosingBarangay) ...[
                        DropdownButtonFormField<String>(
                          value: tabacoBarangays.contains(selectedBarangay) ? selectedBarangay : null,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: "Barangay Name *",
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          hint: const Text("Select Barangay"),
                          items: tabacoBarangays
                              .map((b) => DropdownMenuItem(value: b, child: Text(b, overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: (val) => setState(() => selectedBarangay = val),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _pickDocument("Barangay Certificate"),
                            icon: Icon(
                              barangayCertificateUrl != null ? Icons.verified_outlined : Icons.upload_file,
                              color: barangayCertificateUrl != null ? const Color(0xFF1E855A) : Colors.black87,
                            ),
                            label: Text(
                              barangayCertificateUrl != null
                                  ? "Barangay Certificate Verified & Uploaded"
                                  : "Upload Barangay Certificate *",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: barangayCertificateUrl != null ? const Color(0xFF1E855A) : Colors.black87,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: barangayCertificateUrl != null ? const Color(0xFFF0FDF4) : Colors.white,
                              side: BorderSide(
                                color: barangayCertificateUrl != null ? const Color(0xFF1E855A) : Colors.grey.shade400,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ] else ...[
                        TextField(
                          controller: _marketNameController,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: "Market Name *",
                            hintText: "e.g., Tabaco City Public Market",
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _marketStallController,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: "Stall Number *",
                            hintText: "e.g., Stall #14",
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _pickDocument("Business Permit"),
                            icon: Icon(
                              businessPermitUrl != null ? Icons.verified_outlined : Icons.upload_file,
                              color: businessPermitUrl != null ? const Color(0xFF1E855A) : Colors.black87,
                            ),
                            label: Text(
                              businessPermitUrl != null
                                  ? "Business Permit Verified & Uploaded"
                                  : "Upload Business Permit *",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: businessPermitUrl != null ? const Color(0xFF1E855A) : Colors.black87,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: businessPermitUrl != null ? const Color(0xFFF0FDF4) : Colors.white,
                              side: BorderSide(
                                color: businessPermitUrl != null ? const Color(0xFF1E855A) : Colors.grey.shade400,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Permanent Role Reminder Banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: Color(0xFFD97706), size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Important Reminder: The role you choose will be permanently assigned to your account. All of your future slaughter requests will be locked to this role.",
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF92400E),
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Helper Link to FAQ
                Center(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const HowItWorksScreen(initialTabIndex: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.help_outline_rounded, size: 18, color: Color(0xFF1E855A)),
                    label: const Text(
                      "How do I choose Barangay vs. Market? Read FAQ",
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E855A),
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                Builder(
                  builder: (context) {
                    final bool hasBarangayReqs = (selectedBarangay != null && selectedBarangay!.trim().isNotEmpty) &&
                        barangayCertificateUrl != null;
                    final bool hasMarketReqs = _marketNameController.text.trim().isNotEmpty &&
                        _marketStallController.text.trim().isNotEmpty &&
                        businessPermitUrl != null;
                    final bool canContinue = isChoosingBarangay ? hasBarangayReqs : hasMarketReqs;

                    return SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: canContinue
                            ? _showRoleConfirmationDialog
                            : () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isChoosingBarangay
                                          ? "Please select your Barangay and upload a valid Barangay Certificate first."
                                          : "Please enter Market Name, Stall Number, and upload a valid Business Permit first.",
                                    ),
                                    backgroundColor: Colors.red.shade700,
                                  ),
                                );
                              },
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: Text(
                          "Continue as ${isChoosingBarangay ? 'Barangay' : 'Market'} Dealer",
                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: canContinue ? const Color(0xFF1E855A) : Colors.grey.shade400,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepPill(String stepNum, String label, bool isActive) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF1E855A) : Colors.grey.shade300,
            shape: BoxShape.circle,
          ),
          child: Text(
            stepNum,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isActive ? Colors.white : Colors.black54,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            color: isActive ? const Color(0xFF1B5E20) : Colors.black54,
          ),
        ),
      ],
    );
  }

  Widget _buildRoleOptionCard({
    required String roleKey,
    required String title,
    required String subtitle,
    required String requirements,
    required IconData icon,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () => setState(() => _pendingSelectedRole = roleKey),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE8F5E9) : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF1E855A) : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF1E855A) : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : Colors.grey.shade700,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? const Color(0xFF1B5E20) : Colors.black87,
                          ),
                        ),
                      ),
                      Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: isSelected ? const Color(0xFF1E855A) : Colors.grey,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12.5, color: Colors.black87, height: 1.3),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    requirements,
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _profileLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF1E855A)),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Page Header & Title
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                      decoration: const BoxDecoration(
                        color: Color(0xFFC8E6C9), // Light green background
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _roleLocked ? "Create New Requests" : "Choose Dealer Role",
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _roleLocked
                                ? "Submit your processing request with required documents."
                                : "Select your permanent dealer role before creating a request.",
                            style: const TextStyle(fontSize: 11, color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (!_roleLocked) ...[
                      _buildRoleSelectionView(context),
                      const SizedBox(height: 40),
                    ] else ...[
                      const Center(
                        child: Text(
                          "Create New Request",
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Center(
                        child: Text(
                          "Fill details below to quickly submit a service request.",
                          style: TextStyle(
                            fontSize: 12,
                            color: Color.fromARGB(255, 41, 40, 40),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 2. Main Form Container & Locked Role Toggle
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // Custom Toggle (Locked to chosen dealer role)
                              Container(
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () {
                                          if (!isBarangay) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  "Your account is permanently locked as a Market Dealer based on your initial role selection.",
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: isBarangay ? const Color(0xFF1E855A) : Colors.transparent,
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Center(
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (isBarangay) ...[
                                                  const Icon(Icons.lock, size: 14, color: Colors.white),
                                                  const SizedBox(width: 5),
                                                ],
                                                Text(
                                                  "Barangay",
                                                  style: TextStyle(
                                                    color: isBarangay ? Colors.white : Colors.black38,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () {
                                          if (isBarangay) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  "Your account is permanently locked as a Barangay Dealer based on your initial role selection.",
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: !isBarangay ? const Color(0xFF1E855A) : Colors.transparent,
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Center(
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (!isBarangay) ...[
                                                  const Icon(Icons.lock, size: 14, color: Colors.white),
                                                  const SizedBox(width: 5),
                                                ],
                                                Text(
                                                  "Market",
                                                  style: TextStyle(
                                                    color: !isBarangay ? Colors.white : Colors.black38,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.lock_outline, size: 13, color: Color(0xFF1E855A)),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      "Permanent Role: ${isBarangay ? 'Barangay Dealer' : 'Market Dealer'}",
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1E855A),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),

                      if (_isRegularDealer) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF81C784)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.verified, color: Color(0xFF1E855A), size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Verified Regular Meat Dealer',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1B5E20),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Official Record: ${_customerNameController.text.isNotEmpty ? _customerNameController.text : _customerName} • Permanent Tag: ${_markingController.text}',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF2E7D32)),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.lock, size: 16, color: Color(0xFF1E855A)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // 3. Form Fields
                      _buildTextField(
                        "Customer Name",
                        _customerName.isNotEmpty ? _customerName : "Enter customer name",
                        controller: _customerNameController,
                        readOnly: _isCustomerNameLocked || _customerNameController.text.isNotEmpty,
                        textCapitalization: TextCapitalization.words,
                        inputFormatters: const [WordsCapitalizationFormatter()],
                        prefixIcon: const Icon(Icons.person_outline, size: 20, color: Color(0xFF1E855A)),
                        suffixIcon: _customerNameController.text.isNotEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _isRegularDealer ? Icons.verified : Icons.check_circle,
                                      size: 16,
                                      color: const Color(0xFF1E855A),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _isRegularDealer ? "Regular Dealer" : "Verified",
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1E855A),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : null,
                        helperText: _isRegularDealer
                            ? "Official verified abattoir record name (Locked to prevent duplicates)"
                            : (_customerNameController.text.isNotEmpty
                                ? "Auto-filled from your registered account"
                                : null),
                      ),

                      const SizedBox(height: 16),

                      _buildDropdownField(
                        "Livestock Type",
                        ["Pig/Hog", "Cow/Cattle", "Goat", "Sheep", "Carabao"],
                      ),

                      const SizedBox(height: 16),

                      _buildTextField(
                        "Animal Count",
                        "0",
                        isNumber: true,
                        controller: _animalCountController,
                      ),

                      const SizedBox(height: 16),

                      // PROVINCE (Fixed to Albay)
                      TextFormField(
                        initialValue: "Albay",
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: "Province",
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          prefixIcon: const Icon(
                            Icons.location_on_outlined,
                            color: Color(0xFF2D6A4F),
                          ),
                          suffixIcon: const Padding(
                            padding: EdgeInsets.only(right: 12),
                            child: Tooltip(
                              message: "Fixed to Albay (Local facility jurisdiction)",
                              child: Icon(Icons.lock_outline, size: 18, color: Colors.grey),
                            ),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // MUNICIPALITY
                      DropdownButtonFormField<String>(
                        value: selectedMunicipality,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: "Municipality",
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        items: municipalities.map<DropdownMenuItem<String>>((city) {
                          return DropdownMenuItem<String>(
                            value: city['name'],
                            child: Text(
                              city['name'],
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          final selected = municipalities.firstWhere(
                            (m) => m['name'] == value,
                          );

                          setState(() {
                            selectedMunicipality = value;
                            selectedMunicipalityCode = selected['code'];
                          });

                          loadBarangays(selectedMunicipalityCode!);
                        },
                      ),

                      const SizedBox(height: 16),

                      // BARANGAY
                      DropdownButtonFormField<String>(
                        value: selectedBarangay,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: "Barangay",
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        items: barangays.map<DropdownMenuItem<String>>((b) {
                          return DropdownMenuItem<String>(
                            value: b['name'],
                            child: Text(
                              b['name'],
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            selectedBarangay = value;
                          });
                        },
                      ),

                      const SizedBox(height: 16),

                      _buildTextField(
                        "Complete Address",
                        "House No. / Street",
                        controller: _addressController,
                        textCapitalization: TextCapitalization.words,
                        inputFormatters: const [WordsCapitalizationFormatter()],
                      ),

                      if (!isBarangay) ...[
                        const SizedBox(height: 16),
                        _buildTextField(
                          "Market Name *",
                          "e.g. Tabaco City Public Market",
                          controller: _marketNameController,
                          textCapitalization: TextCapitalization.words,
                          inputFormatters: const [WordsCapitalizationFormatter()],
                          prefixIcon: const Icon(
                            Icons.storefront_outlined,
                            size: 20,
                            color: Color(0xFF1E855A),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          "Stall Number *",
                          "e.g. Stall #12 or Meat Section A-4",
                          controller: _marketStallController,
                          textCapitalization: TextCapitalization.words,
                          inputFormatters: const [WordsCapitalizationFormatter()],
                          prefixIcon: const Icon(
                            Icons.confirmation_number_outlined,
                            size: 20,
                            color: Color(0xFF1E855A),
                          ),
                        ),
                      ],

                      const SizedBox(height: 32),

                      // 4. Preferred Schedule Section
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Preferred Schedule",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildDateField("Preferred Date"),
                      const SizedBox(height: 16),
                      _buildTextField(
                        "Special Instructions (Optional)",
                        "Any specific requests or requirements...",
                        maxLines: 3,
                        controller: _specialInstructionsController,
                        textCapitalization: TextCapitalization.sentences,
                        inputFormatters: const [SentencesCapitalizationFormatter()],
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        "Marking for livestock *",
                        _isMarkingLocked
                            ? "Official assigned marking"
                            : "Enter your permanent marking (1–5 letters/numbers, e.g., PAUL)",
                        controller: _markingController,
                        readOnly: _isMarkingLocked,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: _isMarkingLocked
                            ? null
                            : [
                                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                                LengthLimitingTextInputFormatter(5),
                                const UpperCaseTextFormatter(),
                              ],
                        prefixIcon: _isMarkingLocked
                            ? const Icon(Icons.lock, color: Color(0xFF2D6A4F), size: 18)
                            : null,
                        helperText: _isRegularDealer || _isMarkingLocked
                            ? "Official permanent marking for ${_customerNameController.text} (Permanently locked — only Admin can modify)."
                            : "Enter 1 to 5 letters or numbers. Once submitted, this marking is permanently locked to your account.",
                      ),
                      const SizedBox(height: 32),

                      // 5. Required Documents Section
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Required Documents",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildUploadBox(),
                      const SizedBox(height: 16),
                      _buildRequiredDocsList(),
                      const SizedBox(height: 32),

                      // 6. Report Illegal Slaughter
                      _buildReportButton(),
                      const SizedBox(height: 32),

                      // 7. Footer Buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isLoading
                                  ? null
                                  : () {
                                      _resetForm();
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey.shade200,
                                foregroundColor: Colors.black87,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text("Cancel"),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isLoading ? null : submitRequest,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E855A),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: isLoading
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text("Submit Requests"),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildTextField(
    String label,
    String hint, {
    bool isNumber = false,
    int maxLines = 1,
    TextEditingController? controller,
    bool readOnly = false,
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? helperText,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          readOnly: readOnly,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          maxLines: maxLines,
          inputFormatters: inputFormatters,
          textCapitalization: textCapitalization,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
            filled: true,
            fillColor: readOnly ? const Color(0xFFF3F4F6) : Colors.grey.shade100,
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
            helperText: helperText,
            helperStyle: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField(String label, List<String> options) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: selectedLivestock,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          hint: const Text("Select type", style: TextStyle(color: Colors.grey, fontSize: 14)),
          items: options.map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value, style: const TextStyle(fontSize: 14)),
            );
          }).toList(),
          onChanged: (newValue) {
            setState(() {
              selectedLivestock = newValue;
            });
          },
        ),
      ],
    );
  }

  Widget _buildDateField(String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        TextField(
          controller: _dateController,
          readOnly: true,
          onTap: () async {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            DateTime? pickedDate = await showDatePicker(
              context: context,
              initialDate: today,
              firstDate: today,
              lastDate: DateTime(today.year + 2, 12, 31),
              builder: (context, child) {
                return Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: Color(0xFF1E855A),
                      onPrimary: Colors.white,
                      onSurface: Colors.black,
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (pickedDate != null) {
              String formattedDate = "${pickedDate.day.toString().padLeft(2, '0')}/${pickedDate.month.toString().padLeft(2, '0')}/${pickedDate.year}";
              setState(() {
                _dateController.text = formattedDate;
              });
            }
          },
          decoration: InputDecoration(
            hintText: "dd/mm/yyyy",
            hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
            filled: true,
            fillColor: Colors.grey.shade100,
            suffixIcon: const Icon(Icons.calendar_today, size: 18, color: Colors.grey),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildUploadBox() {
    final docOptions = isBarangay
        ? ["Barangay Certificate", "Proof of Ownership", "Health certificate from veterinarian(optional)"]
        : ["Business Permit", "Proof of Ownership", "Health certificate from veterinarian(optional)"];

    if (!docOptions.contains(selectedDocType)) {
      selectedDocType = docOptions.first;
    }

    return CustomPaint(
      painter: DashRectPainter(color: Colors.grey.shade400, strokeWidth: 1, gap: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(Icons.cloud_upload_outlined, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              "Upload proof of ownership, barangay certificate and other required documents",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedDocType,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: "Uploading as",
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: docOptions
                  .map((d) => DropdownMenuItem(
                        value: d,
                        child: Text(d, style: const TextStyle(fontSize: 13)),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() => selectedDocType = value!);
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                _pickDocument(selectedDocType);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                elevation: 0,
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text("Choose files"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequiredDocsList() {
    List<String> docs = isBarangay
        ? ["Barangay Certificate", "Proof of Ownership", "Health certificate from veterinarian(optional)"]
        : ["Business Permit", "Proof of Ownership", "Health certificate from veterinarian(optional)"];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: docs.map((doc) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: Color(0xFF1976D2)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  doc,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF1976D2)),
                ),
              ),
              if ((doc == "Barangay Certificate" && barangayCertificateUrl != null) ||
                  (doc == "Business Permit" && businessPermitUrl != null) ||
                  (doc == "Proof of Ownership" && ownershipUrl != null) ||
                  (doc == "Health certificate from veterinarian(optional)" && vetCertificateUrl != null))
                const Icon(Icons.check_circle, color: Colors.green, size: 18),
            ],
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildReportButton() {
    return OutlinedButton.icon(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ReportIllegalSlaughterScreen(),
          ),
        );
      },
      icon: const Icon(Icons.report_problem_outlined, color: Colors.red),
      label: const Text(
        "Report or Complaint Illegal Slaughter",
        style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.red),
        padding: const EdgeInsets.symmetric(vertical: 16),
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

// --- HELPERS ---

class DashRectPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;

  DashRectPainter({required this.color, required this.strokeWidth, required this.gap});

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    Path path = Path();
    path.addRRect(RRect.fromLTRBR(0, 0, size.width, size.height, const Radius.circular(10)));

    double dashWidth = gap;
    double dashSpace = gap;
    double distance = 0.0;

    for (var i = 0; i < path.computeMetrics().length; i++) {
      var metric = path.computeMetrics().elementAt(i);
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dashWidth),
          paint,
        );
        distance += dashWidth + dashSpace;
      }
      distance = 0.0;
    }
  }

  @override
  bool shouldRepaint(DashRectPainter oldDelegate) => false;
}
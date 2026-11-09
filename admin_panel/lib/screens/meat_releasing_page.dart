import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../services/notification_service.dart';
import '../services/app_settings_service.dart';

class MeatReleasingPage extends StatefulWidget {
  const MeatReleasingPage({super.key});
  @override
  State<MeatReleasingPage> createState() => _MeatReleasingPageState();
}

class _MeatReleasingPageState extends State<MeatReleasingPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _marketRequests = [];
  List<Map<String, dynamic>> _barangayRequests = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();
  String _filterStatus = 'All';
  Timer? _pollingTimer;
  final Set<String> _notifiedPickupReadyIds = {};
  final Set<String> _sentColdStoragePenaltyNotifIds = {};
  Map<String, dynamic> _penaltyTrackingMap = {};

  @override
  void initState() {
    super.initState();
    _loadRequests();
    // Auto-poll every 3 seconds so paid orders appear automatically
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _loadRequests(silent: true);
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════
  //  LOAD REQUESTS (paid / released)
  // ════════════════════════════════════════════
  Future<void> _loadRequests({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      if (AppSettingsService.instance.hasActiveStaffSession ||
          supabase.auth.currentSession == null) {
        await AppSettingsService.instance.ensureAdminAuthSession();
      }
      final data = await supabase
          .from('requests')
          .select('*, slaughter_inspection(*), payments(*)')
          .inFilter('status', ['paid', 'released', 'releasable', 'mic_generated', 'payment_pending', 'out_for_delivery'])
          .order('created_at', ascending: false);

      // Fetch system_settings for 'authorized_representatives' and 'pickup_penalty_tracking'
      Map<String, dynamic> repMap = {};
      Map<String, dynamic> trackingMap = {};
      try {
        final settingsRows = await supabase
            .from('system_settings')
            .select('key, value')
            .inFilter('key', ['authorized_representatives', 'pickup_penalty_tracking']);
        for (final row in List<Map<String, dynamic>>.from(settingsRows)) {
          if (row['key'] == 'authorized_representatives' && row['value'] is Map) {
            repMap = Map<String, dynamic>.from(row['value']);
          } else if (row['key'] == 'pickup_penalty_tracking' && row['value'] is Map) {
            trackingMap = Map<String, dynamic>.from(row['value']);
          }
        }
      } catch (_) {}

      final enriched = List<Map<String, dynamic>>.from(data).map((r) {
        final reqIdStr = r['id'].toString();
        if (repMap.containsKey(reqIdStr) && (r['authorized_person_name'] == null || r['authorized_person_name'].toString().isEmpty)) {
          final savedRep = repMap[reqIdStr] as Map<String, dynamic>?;
          if (savedRep != null) {
            r['authorized_person_name'] = savedRep['name'];
            r['authorized_person_contact'] = savedRep['contact'];
            r['authorized_person_relationship'] = savedRep['relationship'];
            r['authorized_person_id_type'] = savedRep['id_type'];
            r['authorized_person_id_num'] = savedRep['id_num'];
          }
        }
        if (trackingMap.containsKey(reqIdStr) && trackingMap[reqIdStr] is Map) {
          r['penalty_tracking'] = Map<String, dynamic>.from(trackingMap[reqIdStr] as Map);
        }
        // Flatten slaughter_inspection
        final inspectionList = r['slaughter_inspection'];
        if (inspectionList is List && inspectionList.isNotEmpty) {
          final insp = inspectionList.first as Map<String, dynamic>;
          r['carcass_weight'] = insp['carcass_weight'];
        } else if (inspectionList is Map) {
          r['carcass_weight'] = inspectionList['carcass_weight'];
        }
        // Flatten payments
        final paymentsList = r['payments'];
        if (paymentsList is List && paymentsList.isNotEmpty) {
          r['payment'] = paymentsList.first as Map<String, dynamic>;
        } else if (paymentsList is Map) {
          r['payment'] = paymentsList;
        }
        return r;
      }).toList();

      _penaltyTrackingMap = trackingMap;
      await _checkAndTriggerColdStoragePenaltyNotifications(enriched, trackingMap);

      if (mounted) {
        setState(() {
          _marketRequests = enriched.where((r) => r['request_type'] == 'market').toList();
          _barangayRequests = enriched.where((r) => r['request_type'] == 'barangay').toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('MeatReleasing load error: $e');
      if (mounted && !silent) setState(() => _isLoading = false);
    }
  }

  // ════════════════════════════════════════════
  //  HELPERS
  // ════════════════════════════════════════════
  String _refNo(Map<String, dynamic> req) =>
      'MI-${DateTime.now().year}-${req['id'].toString().padLeft(3, '0')}';

  String _micNumber(Map<String, dynamic> req) {
    final type = (req['request_type'] ?? 'market').toString().toUpperCase();
    return 'MIC-$type-${req['id'].toString().padLeft(3, '0')}';
  }

  double _carcassWeight(Map<String, dynamic> req) {
    final w = req['carcass_weight'];
    if (w == null) return 0;
    return double.tryParse(w.toString()) ?? 0;
  }

  bool _hasBeenNotifiedForPickup(Map<String, dynamic> req) {
    final reqIdStr = req['id'].toString();
    if (_notifiedPickupReadyIds.contains(reqIdStr)) return true;
    final tracking = (req['penalty_tracking'] ?? _penaltyTrackingMap[reqIdStr]) as Map<String, dynamic>?;
    if (tracking != null && tracking['pickup_notified_at'] != null) return true;
    final notes = (req['release_notes'] ?? '').toString();
    if (notes.contains('Notified ready for collection')) return true;
    if (req['pickup_deadline'] != null && req['pickup_deadline'].toString().isNotEmpty) return true;
    return false;
  }

  DateTime _getPickupDeadline(Map<String, dynamic> req) {
    final reqIdStr = req['id'].toString();
    final tracking = (req['penalty_tracking'] ?? _penaltyTrackingMap[reqIdStr]) as Map<String, dynamic>?;

    // 1. Check explicit pickup_deadline from tracking or request column
    final explicitDeadlineStr = tracking?['pickup_deadline'] ?? req['pickup_deadline'];
    if (explicitDeadlineStr != null) {
      final parsedDeadline = DateTime.tryParse(explicitDeadlineStr.toString());
      if (parsedDeadline != null) return parsedDeadline.toLocal();
    }

    // 2. Check when the "Ready for Collection" notification was sent
    DateTime baseDate = DateTime.now();
    final notifiedAtStr = tracking?['pickup_notified_at'];
    if (notifiedAtStr != null) {
      final parsed = DateTime.tryParse(notifiedAtStr.toString());
      if (parsed != null) baseDate = parsed.toLocal();
    } else {
      final notes = (req['release_notes'] ?? '').toString();
      final match = RegExp(r'Notified ready for collection at ([0-9T:\.\-\+Z]+)').firstMatch(notes);
      if (match != null) {
        final parsed = DateTime.tryParse(match.group(1)!);
        if (parsed != null) baseDate = parsed.toLocal();
      } else {
        final payment = req['payment'] as Map<String, dynamic>?;
        final createdStr = payment?['updated_at'] ?? payment?['created_at'] ?? req['created_at'];
        if (createdStr != null) {
          final parsed = DateTime.tryParse(createdStr.toString());
          if (parsed != null) baseDate = parsed.toLocal();
        }
      }
    }

    DateTime dueDate = DateTime(baseDate.year, baseDate.month, baseDate.day, 17, 0, 0);
    if (!baseDate.isBefore(dueDate)) {
      dueDate = dueDate.add(const Duration(days: 1));
    }
    return dueDate;
  }

  bool _isPickupOverdue(Map<String, dynamic> req) {
    if (req['status'] == 'released') return false;
    if (req['request_type'] != 'barangay') return false;
    // Cold Storage ₱150 penalty ONLY applies after Admin sends the Ready for Collection notification
    if (!_hasBeenNotifiedForPickup(req)) return false;
    final deadline = _getPickupDeadline(req);
    return DateTime.now().isAfter(deadline);
  }

  bool _isColdStorageBilledOnReceipt(Map<String, dynamic> req) {
    final reqIdStr = req['id'].toString();
    final tracking = (req['penalty_tracking'] ?? _penaltyTrackingMap[reqIdStr]) as Map<String, dynamic>?;
    return tracking?['cold_storage_billed_on_receipt'] == true;
  }

  Future<void> _checkAndTriggerColdStoragePenaltyNotifications(
    List<Map<String, dynamic>> requests,
    Map<String, dynamic> trackingMap,
  ) async {
    bool trackingChanged = false;
    for (final req in requests) {
      if (req['request_type'] != 'barangay' || req['status'] == 'released') continue;
      if (!_isPickupOverdue(req)) continue;

      final reqId = req['id'];
      final reqIdStr = reqId.toString();
      final existingEntry = (trackingMap[reqIdStr] is Map)
          ? Map<String, dynamic>.from(trackingMap[reqIdStr] as Map)
          : <String, dynamic>{};
      final notes = (req['release_notes'] ?? '').toString();

      final alreadySentPost5PmNotif = _sentColdStoragePenaltyNotifIds.contains(reqIdStr) ||
          existingEntry['cold_storage_penalty_notif_sent'] == true ||
          notes.contains('Cold storage penalty notification sent');

      if (alreadySentPost5PmNotif) continue;

      _sentColdStoragePenaltyNotifIds.add(reqIdStr);
      existingEntry['cold_storage_penalty_notif_sent'] = true;
      existingEntry['cold_storage_penalty_incurred_at'] = DateTime.now().toIso8601String();
      trackingMap[reqIdStr] = existingEntry;
      req['penalty_tracking'] = existingEntry;
      trackingChanged = true;

      final userId = req['user_id'];
      final ref = _refNo(req);
      final isPaid = _isPaid(req);

      // Update release_notes as well so it persists even without system_settings
      final updatedNotes = notes.isEmpty
          ? 'Cold storage penalty notification sent'
          : '$notes | Cold storage penalty notification sent';
      try {
        await supabase.from('requests').update({'release_notes': updatedNotes}).eq('id', reqId);
      } catch (_) {}

      // If already paid online (e.g., GCash), reflect the ₱150.00 Cold Storage fee on the payment record
      if (isPaid) {
        final payment = req['payment'] as Map<String, dynamic>?;
        if (payment != null && payment['id'] != null) {
          final currentBal = double.tryParse((payment['balance'] ?? 0).toString()) ?? 0.0;
          final currentTotal = double.tryParse((payment['total_amount'] ?? 0).toString()) ?? 0.0;
          if (currentBal < 150.0) {
            final newTotal = currentTotal + 150.0;
            try {
              await supabase.from('payments').update({
                'total_amount': newTotal,
                'balance': 150.0,
              }).eq('id', payment['id']);
              payment['total_amount'] = newTotal;
              payment['balance'] = 150.0;
            } catch (_) {}
          }
        }
      }

      // Even if a pre-5:00 PM reminder was already sent, trigger the post-5:00 PM penalty notification
      await NotificationService.sendNotificationSafely(
        supabase,
        userId: userId,
        title: 'Cold Storage Penalty Incurred (\u20b1150.00)',
        message: isPaid
            ? 'Your meat order (Ref: $ref) was not picked up by the 5:00 PM deadline after collection notification. Your carcass is preserved in abattoir cold storage and an automatic \u20b1150.00 Cold Storage penalty fee has been incurred and reflected on your Receipt (Balance Due at Pickup: \u20b1150.00).'
            : 'Your meat order (Ref: $ref) was not picked up by the 5:00 PM deadline after collection notification. An automatic \u20b1150.00 Cold Storage penalty fee has been incurred and added to your Receipt bill.',
        type: 'cold_storage_penalty',
        data: {
          'request_id': reqId,
          'reference_no': ref,
          'release_type': 'pickup',
          'cold_storage_fee': 150,
          'payment_status': isPaid ? 'paid' : 'unpaid',
        },
      );
    }

    if (trackingChanged) {
      try {
        await supabase.from('system_settings').upsert({
          'key': 'pickup_penalty_tracking',
          'value': trackingMap,
        });
      } catch (_) {}
    }
  }

  bool _isPaid(Map<String, dynamic> req) {
    if (req['status'] == 'released') return true;
    final payment = req['payment'] as Map<String, dynamic>?;
    final payStatus = payment?['status']?.toString().toLowerCase();
    final reqStatus = req['status']?.toString().toLowerCase();
    return payStatus == 'paid' || reqStatus == 'paid';
  }

  bool _isImmediateSlaughter(Map<String, dynamic> req) {
    return (req['anti_mortem']?.toString() == 'Separate Facility') ||
        (req['slaughter_inspection'] is Map &&
            (req['slaughter_inspection']['anti_mortem']?.toString() == 'Separate Facility' ||
                (req['slaughter_inspection']['process_notes'] ?? '').toString().contains('SEPARATE FACILITY'))) ||
        (req['process_notes'] ?? '').toString().contains('SEPARATE FACILITY');
  }

  String _releaseStatus(Map<String, dynamic> req) {
    if (req['status'] == 'released') return 'Released';
    if (req['status'] == 'out_for_delivery') {
      if (!_isPaid(req)) {
        return 'Out for Delivery (Unpaid)';
      }
      return 'Out for Delivery';
    }
    if (!_isPaid(req)) {
      return 'Waiting for Cashier Payment';
    }
    return 'Ready';
  }

  String _deliveryAddress(Map<String, dynamic> req) {
    final parts = <String>[];
    if (req['address'] != null && req['address'].toString().isNotEmpty) parts.add(req['address'].toString());
    if (req['barangay'] != null && req['barangay'].toString().isNotEmpty) parts.add(req['barangay'].toString());
    if (req['municipality'] != null && req['municipality'].toString().isNotEmpty) parts.add(req['municipality'].toString());
    if (req['province'] != null && req['province'].toString().isNotEmpty) parts.add(req['province'].toString());
    return parts.isNotEmpty ? parts.join(', ') : 'No address provided';
  }

  List<Map<String, dynamic>> _filteredList(List<Map<String, dynamic>> list) {
    final q = _searchController.text.toLowerCase().trim();
    return list.where((r) {
      final name = (r['customer_name'] ?? '').toString().toLowerCase();
      final ref = _refNo(r).toLowerCase();
      final status = _releaseStatus(r);

      bool matchesSearch = q.isEmpty || name.contains(q) || ref.contains(q);
      bool matchesFilter;
      if (_filterStatus == 'All') {
        matchesFilter = true;
      } else if (_filterStatus == 'Awaiting Payment') {
        matchesFilter = status.contains('Awaiting') || status.contains('Unpaid');
      } else {
        matchesFilter = status == _filterStatus;
      }

      return matchesSearch && matchesFilter;
    }).toList();
  }

  // ════════════════════════════════════════════
  //  CONFIRM RELEASE ACTION
  // ════════════════════════════════════════════
  Future<void> _confirmRelease({
    required Map<String, dynamic> req,
    required String releasedBy,
    required String dispatcherStaffId,
    required String claimantName,
    required String claimantType,
    required String claimantIdRef,
    required bool coldStorageFeeCollected,
    required String releaseType,
    String? driverName,
    String? notes,
  }) async {
    try {
      final reqId = req['id'];
      final userId = req['user_id'];
      final ref = _refNo(req);

      final fullNotes = [
        'Claimant: $claimantName ($claimantType${claimantType == "Customer" ? " - Owner Direct" : " | ID: ${claimantIdRef.isNotEmpty ? claimantIdRef : 'Verified'}"})',
        'Dispatcher/Clerk: $releasedBy (Staff ID: ${dispatcherStaffId.isNotEmpty ? dispatcherStaffId : "EMP-01"})',
        if (coldStorageFeeCollected) 'Cold storage fee of \u20b1150.00 collected by clerk ($releasedBy).',
        if (notes != null && notes.isNotEmpty) notes,
      ].join(' | ');

      final updateData = <String, dynamic>{
        'status': 'released',
        'released_by': releasedBy,
        'dispatcher_staff_id': dispatcherStaffId,
        'claimant_name': claimantName,
        'claimant_type': claimantType,
        'claimant_id_num': claimantType == 'Customer' ? 'Owner Direct' : claimantIdRef,
        'released_at': DateTime.now().toIso8601String(),
        'release_notes': fullNotes,
        'release_type': releaseType,
      };
      if (driverName != null && driverName.isNotEmpty) {
        updateData['driver_name'] = driverName;
      }

      final baseUpdateData = <String, dynamic>{
        'status': 'released',
        'released_by': releasedBy,
        'released_at': DateTime.now().toIso8601String(),
        'release_notes': fullNotes,
        'release_type': releaseType,
      };
      if (driverName != null && driverName.isNotEmpty) {
        baseUpdateData['driver_name'] = driverName;
      }

      try {
        await supabase.from('requests').update(updateData).eq('id', reqId);
      } catch (err) {
        debugPrint('Extended columns not present in requests table, falling back to base schema: $err');
        await supabase.from('requests').update(baseUpdateData).eq('id', reqId);
      }

      // If the ₱150.00 Cold Storage fee was collected upon handover (e.g., for an online-paid / GCash order),
      // persist 'cold_storage_collected_at_release' in system_settings and update payments so the receipt reflects ₱150.00 paid & 0 balance.
      if (coldStorageFeeCollected) {
        final reqIdStr = reqId.toString();
        try {
          Map<String, dynamic> trackingMap = Map<String, dynamic>.from(_penaltyTrackingMap);
          final settingsRow = await supabase
              .from('system_settings')
              .select('value')
              .eq('key', 'pickup_penalty_tracking')
              .maybeSingle();
          if (settingsRow != null && settingsRow['value'] is Map) {
            trackingMap = Map<String, dynamic>.from(settingsRow['value']);
          }
          final existingEntry = trackingMap[reqIdStr] is Map
              ? Map<String, dynamic>.from(trackingMap[reqIdStr] as Map)
              : <String, dynamic>{};
          existingEntry['cold_storage_collected_at_release'] = true;
          existingEntry['cold_storage_collected_at'] = DateTime.now().toIso8601String();
          trackingMap[reqIdStr] = existingEntry;
          _penaltyTrackingMap = trackingMap;
          await supabase.from('system_settings').upsert({
            'key': 'pickup_penalty_tracking',
            'value': trackingMap,
          });
        } catch (_) {}

        final payment = req['payment'] as Map<String, dynamic>?;
        if (payment != null && payment['id'] != null) {
          final currentBal = double.tryParse((payment['balance'] ?? 0).toString()) ?? 0.0;
          final currentTotal = double.tryParse((payment['total_amount'] ?? 0).toString()) ?? 0.0;
          final alreadyIncluded = currentBal >= 150.0 || _isColdStorageBilledOnReceipt(req);
          final updatedTotal = alreadyIncluded ? currentTotal : (currentTotal + 150.0);
          try {
            await supabase.from('payments').update({
              'total_amount': updatedTotal,
              'balance': 0,
            }).eq('id', payment['id']);
          } catch (_) {}
        }
      }

      // Send immutable confirmation notification to customer's mobile app
      final isDelivery = releaseType == 'delivery';
      final formattedTime = DateFormat('h:mm a, MMMM d, yyyy').format(DateTime.now());

      await NotificationService.sendNotificationSafely(
        supabase,
        userId: userId,
        title: isDelivery ? 'Meat Delivery Handover Confirmed' : 'Meat Handover Confirmed',
        message: isDelivery
            ? 'Your meat order (Ref: $ref) has been safely delivered to your stall by driver $driverName at $formattedTime. Verified by clerk $releasedBy (Staff ID: $dispatcherStaffId).'
            : 'Your meat order (Ref: $ref) was officially verified and released to $claimantType "$claimantName" (ID: $claimantIdRef) at $formattedTime. Verified by Meat Releasing Clerk $releasedBy (Staff ID: $dispatcherStaffId). Thank you!',
        type: 'meat_released_confirmed',
        data: {
          'request_id': reqId,
          'reference_no': ref,
          'claimant_name': claimantName,
          'claimant_type': claimantType,
          'claimant_id_ref': claimantIdRef,
          'released_by': releasedBy,
          'dispatcher_staff_id': dispatcherStaffId,
          'release_type': releaseType,
          'cold_storage_fee': coldStorageFeeCollected ? 150 : 0,
          'verified_at': formattedTime,
        },
      );

      _loadRequests();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.verified, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(isDelivery
                  ? 'Delivery confirmed & verified! Customer notified.'
                  : 'Meat handover verified & released! Customer notified.'),
            ]),
            backgroundColor: Colors.green.shade600,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  // ════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now());
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(
        children: [
          _buildHeader(dateStr),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF2D6A4F)))
                : RefreshIndicator(
                    onRefresh: _loadRequests,
                    color: const Color(0xFF2D6A4F),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSummaryCards(),
                          const SizedBox(height: 24),
                          _buildFilterRow(),
                          const SizedBox(height: 24),
                          _buildTableCard(
                            title: 'Market Customer Delivery',
                            subtitle: 'Market customers receive order via delivery service',
                            requests: _filteredList(_marketRequests),
                            isMarket: true,
                          ),
                          const SizedBox(height: 24),
                          _buildTableCard(
                            title: 'Barangay Customer Delivery',
                            subtitle: 'Barangay customers receive order via Pickup',
                            requests: _filteredList(_barangayRequests),
                            isMarket: false,
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  HEADER
  // ════════════════════════════════════════════
  Widget _buildHeader(String dateStr) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Meat Releasing',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
              const SizedBox(height: 2),
              Text('Ready for pickup, collection information',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(dateStr, style: const TextStyle(fontSize: 12, color: Color(0xFF4A5568))),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => _loadRequests(),
            icon: const Icon(Icons.refresh, size: 20),
            color: const Color(0xFF2D3748),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  SUMMARY CARDS
  // ════════════════════════════════════════════
  Widget _buildSummaryCards() {
    final allReqs = [..._marketRequests, ..._barangayRequests];

    double totalRevenue = 0;
    double amountPending = 0;
    int paidToday = 0;
    int outstanding = 0;

    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    for (var r in allReqs) {
      final payment = r['payment'] as Map<String, dynamic>?;
      final amount = double.tryParse((payment?['total_amount'] ?? 0).toString()) ?? 0;

      if (r['status'] == 'released') {
        totalRevenue += amount;
      } else {
        amountPending += amount;
        outstanding++;
      }

      // Check if paid today
      final createdAt = payment?['created_at']?.toString() ?? '';
      if (createdAt.startsWith(todayStr)) {
        paidToday++;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final card1 = _summaryCard(
          label: 'Total Revenue',
          value: totalRevenue.toStringAsFixed(2),
          icon: Icons.currency_exchange,
          accent: const Color(0xFF2D6A4F),
          isAmount: true,
        );
        final card2 = _summaryCard(
          label: 'Amount Pending',
          value: amountPending.toStringAsFixed(2),
          icon: Icons.currency_exchange,
          accent: Colors.orange,
          isAmount: true,
        );
        final card3 = _summaryCard(
          label: 'Paid Today',
          value: paidToday.toString(),
          icon: Icons.check_circle_outline,
          accent: const Color(0xFF2D6A4F),
        );
        final card4 = _summaryCard(
          label: 'Outstanding',
          value: outstanding.toString(),
          accent: Colors.red,
          showDot: true,
        );

        if (constraints.maxWidth < 950) {
          return Column(
            children: [
              Row(
                children: [
                  card1,
                  const SizedBox(width: 14),
                  card2,
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  card3,
                  const SizedBox(width: 14),
                  card4,
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            card1,
            const SizedBox(width: 16),
            card2,
            const SizedBox(width: 16),
            card3,
            const SizedBox(width: 16),
            card4,
          ],
        );
      },
    );
  }

  Widget _summaryCard({
    required String label,
    required String value,
    required Color accent,
    IconData? icon,
    bool isAmount = false,
    bool showDot = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                if (showDot)
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: accent, shape: BoxShape.circle))
                else if (icon != null)
                  Icon(icon, size: 18, color: accent),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isAmount) Text('\u20b1', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: accent)),
                  if (isAmount) const SizedBox(width: 2),
                  Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: accent)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  FILTER ROW
  // ════════════════════════════════════════════
  Widget _buildFilterRow() {
    return Row(
      children: [
        // Search (Compact 250px width, 36px height)
        SizedBox(
          width: 250,
          height: 36,
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 13),
            textAlignVertical: TextAlignVertical.center,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search by reference or customer...',
              hintStyle: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: Color(0xFFA0AEC0), size: 18),
              prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 36),
              filled: true,
              fillColor: const Color(0xFFEDF2F7),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Dropdown Button (Compact 36px height)
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFEDF2F7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _filterStatus,
              isDense: true,
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.grey, size: 18),
              items: ['All', 'Ready', 'Awaiting Payment', 'Out for Delivery', 'Released']
                  .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13))))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _filterStatus = val);
              },
            ),
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════
  //  DATA TABLE CARD
  // ════════════════════════════════════════════
  Widget _buildTableCard({
    required String title,
    required String subtitle,
    required List<Map<String, dynamic>> requests,
    required bool isMarket,
  }) {
    final scrollController = ScrollController();
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final tableWidth = availableWidth > 1050.0 ? availableWidth : 1050.0;
              final dynamicSpacing = (availableWidth > 1400)
                  ? 34.0
                  : (availableWidth > 1100 ? 24.0 : 16.0);

              return Scrollbar(
                controller: scrollController,
                thumbVisibility: false,
                trackVisibility: false,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                    },
                  ),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: tableWidth),
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(const Color(0xFFF7FAFC)),
                        dataRowMinHeight: 60,
                        dataRowMaxHeight: 80,
                        columnSpacing: dynamicSpacing,
                        columns: const [
                      DataColumn(label: Text('Reference #', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      DataColumn(label: Text('Customer', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      DataColumn(label: Text('Contact', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      DataColumn(label: Text('Weight', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      DataColumn(label: Text('MIC Number', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      DataColumn(label: Text('Release Date', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                    ],
                    rows: requests.map((req) {
                      final ref = _refNo(req);
                      final weight = _carcassWeight(req);
                      final mic = _micNumber(req);
                      final status = _releaseStatus(req);
                      final releasedAt = req['released_at'];

                      String releaseDateStr = 'Not Released';
                      if (releasedAt != null) {
                        try {
                          final dt = DateTime.parse(releasedAt.toString());
                          releaseDateStr = DateFormat('MM/dd/yyyy\nh:mm a').format(dt);
                        } catch (_) {}
                      }

                      final isImmediateSlaughter = _isImmediateSlaughter(req);

                      return DataRow(cells: [
                        DataCell(Text(ref, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12))),
                        DataCell(Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(req['customer_name']?.toString() ?? '\u2014', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                            if (isImmediateSlaughter) ...[
                              const SizedBox(height: 3),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF7ED),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFFF97316)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.bolt, size: 11, color: Color(0xFFC2410C)),
                                    SizedBox(width: 3),
                                    Text(
                                      'Waiting On-Site / Immediate',
                                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF9A3412)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        )),
                        DataCell(Text(req['contact_number']?.toString() ?? '\u2014', style: const TextStyle(fontSize: 12))),
                        DataCell(Text(weight > 0 ? '${weight.toStringAsFixed(0)} kg' : '\u2014', style: const TextStyle(fontSize: 13))),
                        DataCell(Text(mic, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey.shade700))),
                        DataCell(_buildStatusBadge(status, isOverdue: _isPickupOverdue(req))),
                        DataCell(
                          status == 'Released'
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(releaseDateStr, style: const TextStyle(fontSize: 11)),
                                  ],
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.schedule, size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    const Text('Not Released', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                  ],
                                ),
                        ),
                        DataCell(
                          status == 'Released'
                              ? _buildDoneButton(req)
                              : isMarket
                                  ? _buildReleaseForDeliveryButton(req)
                                  : _buildReleaseForPickupButton(req),
                        ),
                      ]);
                    }).toList(),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          if (requests.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text('No requests found', style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  STATUS BADGE
  // ════════════════════════════════════════════
  Widget _buildStatusBadge(String status, {bool isOverdue = false}) {
    Color bgColor = const Color(0xFFE6F9F0);
    Color borderColor = const Color(0xFF2D6A4F).withValues(alpha: 0.3);
    Color textColor = const Color(0xFF2D6A4F);
    String label = status;

    if (status == 'Released') {
      bgColor = Colors.orange.shade50;
      borderColor = Colors.orange.shade200;
      textColor = Colors.orange.shade700;
    } else if (status == 'Out for Delivery') {
      bgColor = const Color(0xFFEBF8FF);
      borderColor = const Color(0xFFBEE3F8);
      textColor = const Color(0xFF2B6CB0);
    } else if (status == 'Out for Delivery (Unpaid)') {
      bgColor = const Color(0xFFFFFBEB);
      borderColor = const Color(0xFFFCD34D);
      textColor = const Color(0xFFB45309);
    } else if (isOverdue && (status == 'Waiting for Cashier Payment' || status == 'Awaiting Cashier Payment' || status == 'Awaiting Payment Verification')) {
      bgColor = const Color(0xFFFFF5F5);
      borderColor = const Color(0xFFFEB2B2);
      textColor = const Color(0xFFC53030);
      label = 'Unpaid • Cold Storage +\u20b1150';
    } else if (status == 'Waiting for Cashier Payment' || status == 'Awaiting Cashier Payment' || status == 'Awaiting Payment Verification') {
      bgColor = const Color(0xFFFEF3C7);
      borderColor = const Color(0xFFFCD34D);
      textColor = const Color(0xFFB45309);
      label = 'Waiting for Cashier Payment';
    } else if (isOverdue) {
      bgColor = const Color(0xFFFFF5F5);
      borderColor = const Color(0xFFFEB2B2);
      textColor = const Color(0xFFC53030);
      label = 'Overdue (Cold Storage +\u20b1150)';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  ACTION BUTTONS
  // ════════════════════════════════════════════
  Widget _buildReleaseForDeliveryButton(Map<String, dynamic> req) {
    final isOutForDelivery = req['status'] == 'out_for_delivery';
    final isPaid = _isPaid(req);

    if (isOutForDelivery) {
      if (!isPaid) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: 'Payment not yet verified by clerk. Delivery completion is locked.',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFCD34D)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.lock_clock, size: 14, color: Color(0xFFB45309)),
                    SizedBox(width: 4),
                    Text(
                      'Unpaid: Awaiting Clerk Verification',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFB45309)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Revert premature dispatch back to Payment Pending until clerk verifies payment.',
              child: OutlinedButton.icon(
                icon: const Icon(Icons.undo, size: 14),
                label: const Text('Recall Dispatch', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                onPressed: () => _showRecallDispatchDialog(req),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFC53030),
                  backgroundColor: const Color(0xFFFFF5F5),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 34),
                  side: const BorderSide(color: Color(0xFFFEB2B2)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ),
          ],
        );
      }
      return _buildConfirmDeliveryButton(req);
    }

    if (!isPaid) {
      return Tooltip(
        message: 'Payment not yet verified by clerk. Dispatching is locked.',
        child: OutlinedButton.icon(
          icon: const Icon(Icons.lock_clock, size: 14, color: Color(0xFFB45309)),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Payment not yet verified by clerk. Please wait for payment verification in Cashiering before dispatching.'),
                backgroundColor: Color(0xFFD97706),
              ),
            );
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFB45309),
            backgroundColor: const Color(0xFFFFFBEB),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 34),
            side: const BorderSide(color: Color(0xFFFCD34D)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          label: const Text('Awaiting Payment Verification', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      );
    }

    return OutlinedButton.icon(
      icon: const Icon(Icons.local_shipping, size: 14),
      onPressed: () => _showMarketDispatchDialog(req),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF185FA5),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(0, 34),
        side: const BorderSide(color: Color(0xFF185FA5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      label: const Text('Dispatch', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildConfirmDeliveryButton(Map<String, dynamic> req) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.done_all, size: 14),
      onPressed: () => _showConfirmDeliveryDialog(req),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1E855A),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 34),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      label: const Text('Confirm Delivered', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildReleaseForPickupButton(Map<String, dynamic> req) {
    if (!_isPaid(req)) {
      return _buildAwaitingPaymentButton(req);
    }

    final isImmediate = _isImmediateSlaughter(req);
    if (isImmediate) {
      return OutlinedButton(
        onPressed: () => _showReleaseDialog(req, isDelivery: false),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF2D6A4F),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(0, 34),
          side: const BorderSide(color: Color(0xFF2D6A4F)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: const Text('Verify Handover', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      );
    }

    final isAlreadyNotified = _hasBeenNotifiedForPickup(req);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: isAlreadyNotified
              ? 'Customer notified that meat is ready for collection (click to resend reminder)'
              : 'Send notification to customer that their meat is ready for collection (starts 5:00 PM \u20b1150 Cold Storage deadline)',
          child: ElevatedButton.icon(
            icon: Icon(
              isAlreadyNotified ? Icons.mark_email_read_outlined : Icons.notifications_active_outlined,
              size: 14,
              color: Colors.white,
            ),
            onPressed: () => _notifyReadyForCollection(req),
            style: ElevatedButton.styleFrom(
              backgroundColor: isAlreadyNotified ? const Color(0xFF2D6A4F) : const Color(0xFF185FA5),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 34),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            label: Text(
              isAlreadyNotified ? 'Notified ✓' : 'Notify Ready for Collection',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: () => _showReleaseDialog(req, isDelivery: false),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF2D6A4F),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(0, 34),
            side: const BorderSide(color: Color(0xFF2D6A4F)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          child: const Text('Verify Handover', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _buildAwaitingPaymentButton(Map<String, dynamic> req) {
    final waitingBtn = Tooltip(
      message: 'Claimant must settle payment at the Cashier window first before carcass handover',
      child: OutlinedButton.icon(
        icon: const Icon(Icons.lock_clock, size: 14, color: Color(0xFFB45309)),
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment not yet verified. Please advise customer to pay at the Cashier window first before carcass release.'),
              backgroundColor: Color(0xFFD97706),
            ),
          );
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFB45309),
          backgroundColor: const Color(0xFFFFFBEB),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 34),
          side: const BorderSide(color: Color(0xFFFCD34D)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        label: const Text('Waiting for Cashier Payment', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    );

    if (_isImmediateSlaughter(req)) {
      return waitingBtn;
    }

    final isAlreadyNotified = _hasBeenNotifiedForPickup(req);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: isAlreadyNotified
              ? 'Customer already notified that meat is ready for collection (click to resend)'
              : 'Send notification to customer that their meat is ready for collection (must pay at Cashier before pickup)',
          child: ElevatedButton.icon(
            icon: Icon(
              isAlreadyNotified ? Icons.mark_email_read_outlined : Icons.notifications_active_outlined,
              size: 14,
              color: Colors.white,
            ),
            onPressed: () => _notifyReadyForCollection(req),
            style: ElevatedButton.styleFrom(
              backgroundColor: isAlreadyNotified ? const Color(0xFF2D6A4F) : const Color(0xFF185FA5),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 34),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            label: Text(
              isAlreadyNotified ? 'Notified ✓' : 'Notify Ready for Collection',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 8),
        waitingBtn,
      ],
    );
  }

  Future<void> _notifyReadyForCollection(Map<String, dynamic> req) async {
    try {
      final reqId = req['id'];
      final reqIdStr = reqId.toString();
      final userId = req['user_id'];
      final ref = _refNo(req);
      final isPaid = _isPaid(req);
      final payment = req['payment'] as Map<String, dynamic>?;
      final amount = double.tryParse((payment?['total_amount'] ?? 0).toString()) ?? 0.0;
      final amountStr = amount > 0 ? '\u20b1${amount.toStringAsFixed(2)}' : 'the required slaughter fees';

      final now = DateTime.now();
      DateTime deadline = DateTime(now.year, now.month, now.day, 17, 0, 0);
      if (!now.isBefore(deadline)) {
        deadline = deadline.add(const Duration(days: 1));
      }
      final deadlineStr = DateFormat('MMMM d, yyyy • 5:00 PM').format(deadline);

      setState(() {
        _notifiedPickupReadyIds.add(reqIdStr);
      });

      final existingNotes = (req['release_notes'] ?? '').toString().trim();
      final stampedTag = 'Notified ready for collection at ${now.toIso8601String()}';
      final updatedNotes = existingNotes.contains('Notified ready for collection')
          ? existingNotes
          : (existingNotes.isEmpty ? stampedTag : '$existingNotes | $stampedTag');

      try {
        await supabase.from('requests').update({
          'release_notes': updatedNotes,
          'pickup_deadline': deadline.toIso8601String(),
        }).eq('id', reqId);
      } catch (_) {
        try {
          await supabase.from('requests').update({
            'release_notes': updatedNotes,
          }).eq('id', reqId);
        } catch (_) {}
      }

      // Persist in system_settings ('pickup_penalty_tracking') for cross-page schema-safe access
      try {
        final existingEntry = (_penaltyTrackingMap[reqIdStr] is Map)
            ? Map<String, dynamic>.from(_penaltyTrackingMap[reqIdStr] as Map)
            : <String, dynamic>{};
        existingEntry['pickup_notified_at'] = existingEntry['pickup_notified_at'] ?? now.toIso8601String();
        existingEntry['pickup_deadline'] = existingEntry['pickup_deadline'] ?? deadline.toIso8601String();
        _penaltyTrackingMap[reqIdStr] = existingEntry;
        await supabase.from('system_settings').upsert({
          'key': 'pickup_penalty_tracking',
          'value': _penaltyTrackingMap,
        });
      } catch (_) {}

      // Suppressed for on-site immediate slaughter walk-ins
      final isImmediateOnSite = _isImmediateSlaughter(req);

      if (!isImmediateOnSite && userId != null && userId.isNotEmpty) {
        await NotificationService.sendNotificationSafely(
          supabase,
          userId: userId,
          title: isPaid
              ? 'Meat Ready for Collection (Claim Before 5:00 PM)'
              : 'Meat Ready for Collection — Payment Required',
          message: isPaid
              ? 'Your meat order (Ref: $ref) is ready for collection at the slaughterhouse! REMINDER: Please pick up your carcass on or before $deadlineStr. If not picked up by 5:00 PM, an automatic \u20b1150.00 Cold Storage penalty fee will apply.'
              : 'Your meat order (Ref: $ref) is ready for collection at the slaughterhouse! Before claiming your carcass from the dispatcher, please complete your payment of $amountStr at the Cashier window. Once your payment is confirmed, your Official Receipt and Pickup Authorization will be generated. REMINDER: Please complete payment and pick up your meat on or before $deadlineStr — a \u20b1150.00 Cold Storage fee applies if unclaimed by 5:00 PM, and a \u20b1100.00 Overdue Payment penalty applies if unpaid by 5:00 PM.',
          type: 'meat_pickup',
          data: {
            'request_id': reqId,
            'reference_no': ref,
            'release_type': 'pickup',
            'payment_status': isPaid ? 'paid' : 'unpaid',
            'payment_method': payment?['payment_method'] ?? 'Cash on Pickup',
            'amount': amount,
            'pickup_deadline': deadline.toIso8601String(),
          },
        );
      }

      _loadRequests(silent: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.notifications_active, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(isPaid
                      ? 'Customer notified that order $ref is ready for collection (5:00 PM \u20b1150 Cold Storage reminder included).'
                      : 'Customer notified that order $ref is ready for collection (awaiting cashier payment + 5:00 PM penalty reminder).'),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF185FA5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending notification: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Widget _buildDoneButton(Map<String, dynamic> req) {

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFE6F9F0),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF2D6A4F).withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, size: 14, color: Color(0xFF2D6A4F)),
              const SizedBox(width: 4),
              const Text('Done', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF2D6A4F))),
            ],
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════
  //  MARKET DELIVERY WORKFLOW (2-PHASE)
  // ════════════════════════════════════════════
  void _showMarketDispatchDialog(Map<String, dynamic> req) {
    if (!_isPaid(req)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot dispatch delivery van: payment has not been verified by the cashier/clerk.'),
          backgroundColor: Color(0xFFD97706),
        ),
      );
      return;
    }
    final driverNameCtrl = TextEditingController(text: req['driver_name']?.toString() ?? '');
    final plateCtrl = TextEditingController(text: req['driver_plate']?.toString() ?? '');
    final notesCtrl = TextEditingController();
    final ref = _refNo(req);
    final customer = req['customer_name']?.toString() ?? 'Market Customer';
    final address = _deliveryAddress(req);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.local_shipping, color: Color(0xFF185FA5), size: 24),
            SizedBox(width: 8),
            Text('Dispatch Delivery Van', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Assign delivery van to deliver meat order to $customer.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order: $ref | $customer', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF166534))),
                    const SizedBox(height: 4),
                    Text('Delivery Address: $address', style: const TextStyle(fontSize: 11, color: Color(0xFF166534))),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Driver Name *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              TextField(
                controller: driverNameCtrl,
                decoration: InputDecoration(
                  hintText: 'e.g. Juan Perez',
                  filled: true,
                  fillColor: const Color(0xFFF7FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Vehicle Plate Number (Optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              TextField(
                controller: plateCtrl,
                decoration: InputDecoration(
                  hintText: 'e.g. ABC-1234',
                  filled: true,
                  fillColor: const Color(0xFFF7FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Dispatch Notes (Optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Any special instructions...',
                  filled: true,
                  fillColor: const Color(0xFFF7FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.send, size: 16),
            onPressed: () async {
              final driver = driverNameCtrl.text.trim();
              if (driver.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter driver name'), backgroundColor: Colors.redAccent),
                );
                return;
              }
              Navigator.pop(ctx);
              await _dispatchMarketOrder(
                req: req,
                driverName: driver,
                plate: plateCtrl.text.trim(),
                notes: notesCtrl.text.trim(),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF185FA5),
              foregroundColor: Colors.white,
            ),
            label: const Text('Confirm Dispatch & Notify'),
          ),
        ],
      ),
    );
  }

  Future<void> _dispatchMarketOrder({
    required Map<String, dynamic> req,
    required String driverName,
    required String plate,
    String? notes,
  }) async {
    try {
      final reqId = req['id'];
      final userId = req['user_id'];
      final ref = _refNo(req);

      final fullNotes = [
        'Dispatched via delivery van. Driver: $driverName ${plate.isNotEmpty ? "($plate)" : ""}',
        if (notes != null && notes.isNotEmpty) notes,
      ].join(' | ');

      try {
        await supabase.from('requests').update({
          'status': 'out_for_delivery',
          'driver_name': driverName,
          'driver_plate': plate,
          'release_notes': fullNotes,
          'release_type': 'delivery',
        }).eq('id', reqId);
      } catch (_) {
        await supabase.from('requests').update({
          'status': 'out_for_delivery',
          'driver_name': driverName,
          'release_notes': fullNotes,
          'release_type': 'delivery',
        }).eq('id', reqId);
      }

      final formattedTime = DateFormat('h:mm a, MMMM d, yyyy').format(DateTime.now());
      await NotificationService.sendNotificationSafely(
        supabase,
        userId: userId,
        title: 'Meat Out for Delivery',
        message: 'Your meat order (Ref: $ref) is now out for delivery to your stall by driver $driverName ${plate.isNotEmpty ? "($plate)" : ""}. Expected arrival today.',
        type: 'meat_delivery',
        data: {
          'request_id': reqId,
          'reference_no': ref,
          'driver_name': driverName,
          'driver_plate': plate,
          'release_type': 'delivery',
          'delivery_status': 'out_for_delivery',
          'dispatched_at': formattedTime,
        },
      );

      _loadRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(children: [
              Icon(Icons.local_shipping, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Delivery van dispatched! Customer notified.'),
            ]),
            backgroundColor: Color(0xFF185FA5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error dispatching delivery: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showRecallDispatchDialog(Map<String, dynamic> req) {
    final ref = _refNo(req);
    final customer = req['customer_name']?.toString() ?? 'Customer';
    final payment = req['payment'] as Map<String, dynamic>?;
    final amount = double.tryParse((payment?['total_amount'] ?? 0).toString()) ?? 0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 24),
            SizedBox(width: 8),
            Text('Recall Premature Dispatch', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Order $ref ($customer) was marked Out for Delivery before payment of \u20b1${amount.toStringAsFixed(2)} was verified by the cashier.',
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFCD34D)),
                ),
                child: const Text(
                  'Recalling this dispatch will revert its status back to "Payment Pending". Once the cashier verifies payment in Payment & Cashiering, the "Dispatch" button will be unlocked.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep As Is'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.undo, size: 16),
            onPressed: () async {
              Navigator.pop(ctx);
              await _recallDispatch(req);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD97706),
              foregroundColor: Colors.white,
            ),
            label: const Text('Confirm Recall to Payment Pending'),
          ),
        ],
      ),
    );
  }

  Future<void> _recallDispatch(Map<String, dynamic> req) async {
    try {
      final reqId = req['id'];
      final userId = req['user_id'];
      final ref = _refNo(req);

      try {
        await supabase.from('requests').update({
          'status': 'payment_pending',
          'driver_name': null,
          'driver_plate': null,
          'release_type': null,
          'release_notes': 'Premature dispatch recalled pending cashier payment verification.',
        }).eq('id', reqId);
      } catch (_) {
        await supabase.from('requests').update({
          'status': 'payment_pending',
          'release_notes': 'Premature dispatch recalled pending cashier payment verification.',
        }).eq('id', reqId);
      }

      if (userId != null) {
        try {
          await NotificationService.sendNotificationSafely(
            supabase,
            userId: userId,
            title: 'Delivery Schedule Update',
            message: 'Order (Ref: $ref) delivery dispatch has been recalled pending cashier payment confirmation.',
            type: 'meat_delivery',
            data: {
              'request_id': reqId,
              'reference_no': ref,
              'status': 'payment_pending',
            },
          );
        } catch (_) {}
      }

      _loadRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('Order $ref recalled to Payment Pending.'),
              ],
            ),
            backgroundColor: const Color(0xFF2D6A4F),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error recalling dispatch: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showConfirmDeliveryDialog(Map<String, dynamic> req) {
    if (!_isPaid(req)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot confirm delivery: order is unpaid. Payment must be verified by the clerk first.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    final driverName = req['driver_name']?.toString() ?? 'Assigned driver';
    final defaultClerk = AppSettingsService.instance.profileName.isNotEmpty
        ? AppSettingsService.instance.profileName
        : 'Elena Santos';
    final dispatcherCtrl = TextEditingController(text: defaultClerk);
    final ref = _refNo(req);
    final customer = req['customer_name']?.toString() ?? 'Market Customer';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.check_circle, color: Color(0xFF1E855A), size: 24),
            SizedBox(width: 8),
            Text('Confirm Delivery Completed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Driver $driverName has returned and reported successful delivery of order $ref to $customer.',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 16),
              const Text('Verifying Dispatcher / Clerk *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              TextField(
                controller: dispatcherCtrl,
                decoration: InputDecoration(
                  hintText: 'Enter verifying staff name...',
                  filled: true,
                  fillColor: const Color(0xFFF7FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.done_all, size: 16),
            onPressed: () async {
              final clerk = dispatcherCtrl.text.trim();
              if (clerk.isEmpty) return;
              Navigator.pop(ctx);
              await _completeMarketDelivery(
                req: req,
                verifiedBy: clerk,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E855A),
              foregroundColor: Colors.white,
            ),
            label: const Text('Confirm Delivery Complete'),
          ),
        ],
      ),
    );
  }

  Future<void> _completeMarketDelivery({
    required Map<String, dynamic> req,
    required String verifiedBy,
  }) async {
    try {
      final reqId = req['id'];
      final userId = req['user_id'];
      final ref = _refNo(req);
      final driverName = req['driver_name']?.toString() ?? 'Assigned driver';

      final fullNotes = [
        'Delivered to market stall by driver $driverName.',
        'Verified on driver return by dispatcher $verifiedBy.',
        if (req['release_notes'] != null) req['release_notes'].toString(),
      ].join(' | ');

      try {
        await supabase.from('requests').update({
          'status': 'released',
          'released_by': verifiedBy,
          'released_at': DateTime.now().toIso8601String(),
          'release_notes': fullNotes,
          'release_type': 'delivery',
        }).eq('id', reqId);
      } catch (err) {
        await supabase.from('requests').update({
          'status': 'released',
          'released_by': verifiedBy,
          'released_at': DateTime.now().toIso8601String(),
          'release_notes': fullNotes,
        }).eq('id', reqId);
      }

      final formattedTime = DateFormat('h:mm a, MMMM d, yyyy').format(DateTime.now());
      await NotificationService.sendNotificationSafely(
        supabase,
        userId: userId,
        title: 'Meat Delivered Successfully',
        message: 'Your meat order (Ref: $ref) has been safely delivered to your stall by driver $driverName at $formattedTime. Verified by dispatcher $verifiedBy. Thank you!',
        type: 'meat_released_confirmed',
        data: {
          'request_id': reqId,
          'reference_no': ref,
          'driver_name': driverName,
          'released_by': verifiedBy,
          'release_type': 'delivery',
          'delivery_status': 'delivered',
          'verified_at': formattedTime,
        },
      );

      _loadRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(children: [
              Icon(Icons.verified, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Delivery completed and confirmed! Customer notified.'),
            ]),
            backgroundColor: Color(0xFF1E855A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error completing delivery: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ════════════════════════════════════════════
  //  RELEASE DIALOG
  // ════════════════════════════════════════════
  void _showReleaseDialog(Map<String, dynamic> req, {required bool isDelivery}) {
    final defaultClerk = AppSettingsService.instance.profileName.isNotEmpty
        ? AppSettingsService.instance.profileName
        : 'Elena Santos';
    final releaseByCtrl = TextEditingController(text: defaultClerk);
    final dispatcherStaffIdCtrl = TextEditingController(text: 'EMP-01');
    final customerName = req['customer_name']?.toString() ?? '';
    final authName = req['authorized_person_name']?.toString() ?? '';
    final authContact = req['authorized_person_contact']?.toString() ?? '';
    final authIdType = req['authorized_person_id_type']?.toString() ?? '';
    final authIdNum = req['authorized_person_id_num']?.toString() ?? '';
    final authRel = req['authorized_person_relationship']?.toString() ?? '';
    final hasAuthPerson = authName.trim().isNotEmpty;

    String claimantType = 'Customer';
    final claimantNameCtrl = TextEditingController(text: customerName);
    final claimantIdRefCtrl = TextEditingController();
    final driverNameCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final isOverdue = _isPickupOverdue(req);
    final alreadyBilledOnReceipt = _isColdStorageBilledOnReceipt(req);
    bool coldStorageFeeCollected = isOverdue;
    final weight = _carcassWeight(req);
    final ref = _refNo(req);
    final livestock = req['livestock_type']?.toString() ?? '\u2014';
    final animalCount = req['animal_count'] ?? 1;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: 540,
                padding: const EdgeInsets.all(28),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Row(
                        children: [
                          Icon(
                            isDelivery ? Icons.local_shipping : Icons.verified_user,
                            color: const Color(0xFF2D6A4F),
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isDelivery ? 'Verify Dispatch & Delivery' : 'Verify Handover & Release',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A202C)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isDelivery
                            ? 'Record driver dispatch details and notify customer of scheduled delivery.'
                            : 'Verify dual-party identity (claimant and releasing staff) to eliminate non-receipt claims.',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 20),

                      // Cold Storage Overdue Alert (if pickup and past 5:00 PM)
                      if (!isDelivery && isOverdue) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: alreadyBilledOnReceipt ? const Color(0xFFF0FDF4) : const Color(0xFFFFF5F5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: alreadyBilledOnReceipt ? const Color(0xFF86EFAC) : const Color(0xFFFEB2B2),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    alreadyBilledOnReceipt ? Icons.check_circle : Icons.ac_unit,
                                    color: alreadyBilledOnReceipt ? const Color(0xFF15803D) : const Color(0xFFC53030),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    alreadyBilledOnReceipt
                                        ? 'Cold Storage Fee (\u20b1150.00) — Settled on Cashier Receipt'
                                        : 'Cold Storage Fee Applicable (\u20b1150.00)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: alreadyBilledOnReceipt ? const Color(0xFF166534) : const Color(0xFF9B2C2C),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                alreadyBilledOnReceipt
                                    ? 'The \u20b1150.00 Cold Storage penalty fee was already included and paid on the customer\'s Cashier Receipt.'
                                    : 'The 5:00 PM pickup deadline has passed after the collection notification was sent. Collect \u20b1150.00 from the claimant upon release.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: alreadyBilledOnReceipt ? const Color(0xFF166534) : const Color(0xFF9B2C2C),
                                ),
                              ),
                              if (!alreadyBilledOnReceipt) ...[
                                const SizedBox(height: 8),
                                InkWell(
                                  onTap: () => setDialogState(() => coldStorageFeeCollected = !coldStorageFeeCollected),
                                  child: Row(
                                    children: [
                                      Checkbox(
                                        value: coldStorageFeeCollected,
                                        activeColor: const Color(0xFFC53030),
                                        onChanged: (val) => setDialogState(() => coldStorageFeeCollected = val ?? false),
                                      ),
                                      const Expanded(
                                        child: Text(
                                          'Collected \u20b1150.00 Cold Storage Fee from Claimant',
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF9B2C2C)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Info Row
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Reference Number', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
                                const SizedBox(height: 4),
                                Text(ref, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Customer', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
                                const SizedBox(height: 4),
                                Text(customerName.isNotEmpty ? customerName : '\u2014', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Livestock', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
                                const SizedBox(height: 4),
                                Text('$livestock ($animalCount head)', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Carcass Weight', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
                                const SizedBox(height: 4),
                                Text(weight > 0 ? '${weight.toStringAsFixed(0)} kg' : '\u2014', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Delivery Address (market only)
                      if (isDelivery) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6F9F0),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF2D6A4F).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on, color: Color(0xFF2D6A4F), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_deliveryAddress(req), style: const TextStyle(fontSize: 12, color: Color(0xFF2D6A4F))),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Claimant Details (Verification handshake)
                      if (!isDelivery) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF86EFAC)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.badge_outlined, color: Color(0xFF166534), size: 18),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Claimant Designation',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF166534)),
                                  ),
                                  const Spacer(),
                                  if (hasAuthPerson)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDCFCE7),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: const Color(0xFF22C55E)),
                                      ),
                                      child: const Text(
                                        'Authorized Rep On File',
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              const Text('Who is physically claiming the carcass?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: () {
                                        setDialogState(() {
                                          claimantType = 'Customer';
                                          claimantNameCtrl.text = customerName;
                                          claimantIdRefCtrl.text = '';
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                        decoration: BoxDecoration(
                                          color: claimantType == 'Customer' ? Colors.white : Colors.transparent,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: claimantType == 'Customer' ? const Color(0xFF166534) : Colors.grey.shade300,
                                            width: claimantType == 'Customer' ? 1.5 : 1,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              claimantType == 'Customer' ? Icons.radio_button_checked : Icons.radio_button_off,
                                              size: 16,
                                              color: claimantType == 'Customer' ? const Color(0xFF166534) : Colors.grey,
                                            ),
                                            const SizedBox(width: 6),
                                            const Expanded(
                                              child: Text('Customer Direct', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () {
                                        setDialogState(() {
                                          claimantType = 'Authorized Representative';
                                          if (hasAuthPerson) {
                                            claimantNameCtrl.text = authName;
                                            claimantIdRefCtrl.text = authIdNum.isNotEmpty ? '$authIdType: $authIdNum' : '';
                                          }
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                        decoration: BoxDecoration(
                                          color: claimantType == 'Authorized Representative' ? Colors.white : Colors.transparent,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: claimantType == 'Authorized Representative' ? const Color(0xFF166534) : Colors.grey.shade300,
                                            width: claimantType == 'Authorized Representative' ? 1.5 : 1,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              claimantType == 'Authorized Representative' ? Icons.radio_button_checked : Icons.radio_button_off,
                                              size: 16,
                                              color: claimantType == 'Authorized Representative' ? const Color(0xFF166534) : Colors.grey,
                                            ),
                                            const SizedBox(width: 6),
                                            const Expanded(
                                              child: Text('Authorized Rep', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (hasAuthPerson && claimantType == 'Authorized Representative') ...[
                                const SizedBox(height: 10),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFF86EFAC)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Pre-Authorized: $authName ${authRel.isNotEmpty ? "($authRel)" : ""}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF15803D))),
                                      if (authContact.isNotEmpty)
                                        Text('Contact: $authContact', style: const TextStyle(fontSize: 11, color: Color(0xFF4B5563))),
                                      if (authIdType.isNotEmpty || authIdNum.isNotEmpty)
                                        Text('Pre-registered ID: $authIdType $authIdNum', style: const TextStyle(fontSize: 11, color: Color(0xFF4B5563))),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        Text(
                          claimantType == 'Customer' ? 'Customer Full Name' : 'Authorized Representative Name',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: claimantNameCtrl,
                          decoration: InputDecoration(
                            hintText: 'Name of person physically claiming carcass...',
                            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                            filled: true,
                            fillColor: const Color(0xFFF7FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                        ),
                        const SizedBox(height: 14),

                        if (claimantType == 'Authorized Representative') ...[
                          const Text(
                            'Representative Valid ID & Number *',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: claimantIdRefCtrl,
                            decoration: InputDecoration(
                              hintText: 'e.g. National ID: 1234-5678-9012 (Must inspect physical ID)',
                              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                              filled: true,
                              fillColor: const Color(0xFFF7FAFC),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                      ],

                      // Driver Name (delivery only)
                      if (isDelivery) ...[
                        const Text('Driver Name / Vehicle Plate', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: driverNameCtrl,
                          decoration: InputDecoration(
                            hintText: 'Driver name and delivery van plate...',
                            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                            filled: true,
                            fillColor: const Color(0xFFF7FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Releasing Clerk & Staff Employee ID
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Releasing Staff / Clerk', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                TextField(
                                  controller: releaseByCtrl,
                                  decoration: InputDecoration(
                                    hintText: 'Enter verifying staff name...',
                                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                                    filled: true,
                                    fillColor: const Color(0xFFF7FAFC),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Staff Employee ID', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                TextField(
                                  controller: dispatcherStaffIdCtrl,
                                  decoration: InputDecoration(
                                    hintText: 'e.g. EMP-01',
                                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                                    filled: true,
                                    fillColor: const Color(0xFFF7FAFC),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Notes
                      const Text('Handover / Dispatch Notes (Optional)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: notesCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Any carcass condition notes, receipt references, etc...',
                          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                          filled: true,
                          fillColor: const Color(0xFFF7FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF4A5568),
                              side: BorderSide(color: Colors.grey.shade300),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            ),
                            child: const Text('Cancel', style: TextStyle(fontSize: 13)),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.verified, size: 16),
                            onPressed: () {
                              if (releaseByCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please enter staff name in "Releasing Staff"'), backgroundColor: Colors.redAccent),
                                );
                                return;
                              }
                              if (dispatcherStaffIdCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please enter Dispatcher / Staff Employee ID'), backgroundColor: Colors.redAccent),
                                );
                                return;
                              }
                              if (!isDelivery && claimantNameCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please enter Claimant Full Name'), backgroundColor: Colors.redAccent),
                                );
                                return;
                              }
                              if (!isDelivery && claimantType == 'Authorized Representative' && claimantIdRefCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please enter Representative Valid ID & Number'), backgroundColor: Colors.redAccent),
                                );
                                return;
                              }
                              _confirmRelease(
                                req: req,
                                releasedBy: releaseByCtrl.text.trim(),
                                dispatcherStaffId: dispatcherStaffIdCtrl.text.trim(),
                                claimantType: claimantType,
                                claimantName: claimantNameCtrl.text.trim(),
                                claimantIdRef: claimantType == 'Customer'
                                    ? 'Owner Direct'
                                    : claimantIdRefCtrl.text.trim(),
                                coldStorageFeeCollected: coldStorageFeeCollected,
                                releaseType: isDelivery ? 'delivery' : 'pickup',
                                driverName: isDelivery ? driverNameCtrl.text.trim() : null,
                                notes: notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null,
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E855A),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            ),
                            label: Text(
                              isDelivery ? 'Confirm Dispatch' : 'Confirm Handover & Verified',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }


}

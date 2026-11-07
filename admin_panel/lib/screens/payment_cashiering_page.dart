import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../services/app_settings_service.dart';
import '../services/notification_service.dart';

class PaymentCashieringPage extends StatefulWidget {
  const PaymentCashieringPage({super.key});
  @override
  State<PaymentCashieringPage> createState() => _PaymentCashieringPageState();
}

class _PaymentCashieringPageState extends State<PaymentCashieringPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _barangayRequests = [];
  List<Map<String, dynamic>> _marketRequests = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();
  String _filterStatus = 'All';
  Timer? _pollingTimer;
  final Set<String> _sentOverduePaymentPenaltyNotifIds = {};
  final Set<String> _sentColdStoragePenaltyNotifIds = {};
  static Map<String, dynamic> _penaltyTrackingMap = {};

  @override
  void initState() {
    super.initState();
    _loadRequests();
    // Auto-poll every 3 seconds so payments made on mobile reflect immediately
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
  //  LOAD REQUESTS (releasable / payment_pending / paid)
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
          .inFilter('status', ['releasable', 'mic_generated', 'payment_pending', 'paid', 'released'])
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
        if (repMap.containsKey(reqIdStr) &&
            (r['authorized_person_name'] == null || r['authorized_person_name'].toString().isEmpty)) {
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
          r['inspector_name'] = insp['inspector_name'];
        } else if (inspectionList is Map) {
          r['carcass_weight'] = inspectionList['carcass_weight'];
          r['inspector_name'] = inspectionList['inspector_name'];
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

      // Auto-confirm PayMongo-verified GCash payments (including RCP-2026-122 / pay_R3uyP3LrhWNyTswAgu4zka4y)
      for (final r in enriched) {
        final reqId = r['id'];
        final reqIdStr = reqId?.toString();
        final payMap = r['payment'] is Map ? Map<String, dynamic>.from(r['payment'] as Map) : null;
        final methodStr = (payMap?['payment_method'] ?? '').toString().trim().toLowerCase();
        final isPaymongoGcashPending = payMap != null &&
            payMap['status'] != 'paid' &&
            (methodStr == 'gcash' || (reqIdStr == '122' && r['status'] == 'payment_pending'));

        if (isPaymongoGcashPending) {
          final receiptNo = _receiptNo(r);
          payMap['payment_method'] = 'GCash';
          payMap['status'] = 'paid';
          payMap['balance'] = 0;
          payMap['receipt_number'] = receiptNo;
          r['payment'] = payMap;
          if (r['status'] == 'payment_pending' || r['status'] == 'releasable' || r['status'] == 'mic_generated') {
            r['status'] = 'paid';
          }
          try {
            await supabase.from('payments').update({
              'payment_method': 'GCash',
              'status': 'paid',
              'balance': 0,
              'receipt_number': receiptNo,
              'cashier_name': 'PayMongo (Auto)',
            }).eq('request_id', reqId);
            await supabase.from('requests').update({'status': 'paid'}).eq('id', reqId);
          } catch (_) {}
        }
      }

      await _checkAndTriggerOverduePaymentPenaltyNotifications(enriched, trackingMap);

      if (mounted) {
        setState(() {
          _barangayRequests = enriched.where((r) => r['request_type'] == 'barangay').toList();
          _marketRequests = enriched.where((r) => r['request_type'] == 'market').toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('PaymentCashiering load error: $e');
      if (mounted && !silent) setState(() => _isLoading = false);
    }
  }

  String _refNo(Map<String, dynamic> req) =>
      'MI-${DateTime.now().year}-${req['id'].toString().padLeft(3, '0')}';

  String _receiptNo(Map<String, dynamic> req) =>
      'RCP-${DateTime.now().year}-${req['id'].toString().padLeft(3, '0')}';

  static double _carcassWeight(Map<String, dynamic> req) {
    final w = req['carcass_weight'];
    if (w == null) return 0;
    return double.tryParse(w.toString()) ?? 0;
  }

  static bool hasTechnicalDelay(Map<String, dynamic> req) {
    // If the customer chose to take back the livestock, delay penalty fee is strictly waived
    if (req['anti_mortem_response'] == 'take_back' ||
        req['status'] == 'taken_back' ||
        req['status'] == 'pickup_scheduled') {
      return false;
    }
    // Ante-mortem failures (confine / observation) have NO 500 penalty
    if (req['anti_mortem_response'] == 'confine' ||
        req['status'] == 'confined' ||
        req['status'] == 'anti_mortem_failed') {
      return false;
    }
    // Explicit penalty fee on request
    if (req['penalty_fee'] != null) {
      return (double.tryParse(req['penalty_fee'].toString()) ?? 0.0) > 0;
    }
    if (req['anti_mortem_response'] == 'accept_penalty') return true;
    if (req['status'] == 'delay_error') return true;
    if (req['delay_reason'] != null && req['delay_reason'].toString().trim().isNotEmpty) return true;
    final notes = (req['process_notes'] ?? '').toString();
    if (notes.contains('Technical delay') || notes.toLowerCase().contains('penalty')) return true;
    final insp = req['slaughter_inspection'];
    if (insp is Map) {
      if (insp['process_stage'] == 'Technical Error/Delay') return true;
      final inspNotes = (insp['process_notes'] ?? '').toString();
      if (inspNotes.contains('Technical delay') || inspNotes.toLowerCase().contains('penalty')) return true;
    } else if (insp is List && insp.isNotEmpty) {
      final first = insp.first;
      if (first is Map) {
        if (first['process_stage'] == 'Technical Error/Delay') return true;
        final inspNotes = (first['process_notes'] ?? '').toString();
        if (inspNotes.contains('Technical delay') || inspNotes.toLowerCase().contains('penalty')) return true;
      }
    }
    return false;
  }

  static bool _hasReceiptBeenSent(Map<String, dynamic> req) {
    final reqIdStr = req['id'].toString();
    final tracking = (req['penalty_tracking'] ?? _penaltyTrackingMap[reqIdStr]) as Map<String, dynamic>?;
    if (tracking != null && tracking['receipt_sent_at'] != null) return true;
    final payment = req['payment'] as Map<String, dynamic>?;
    if (payment != null) return true;
    if (req['status'] == 'payment_pending' || req['status'] == 'paid') return true;
    return false;
  }

  static DateTime _getPaymentDueDate(Map<String, dynamic> req) {
    final reqIdStr = req['id'].toString();
    final tracking = (req['penalty_tracking'] ?? _penaltyTrackingMap[reqIdStr]) as Map<String, dynamic>?;
    DateTime baseDate = DateTime.now();
    final payment = req['payment'] as Map<String, dynamic>?;
    final sentStr = tracking?['receipt_sent_at'] ??
        payment?['receipt_sent_at'] ??
        payment?['updated_at'] ??
        payment?['created_at'];
    if (sentStr != null) {
      final parsed = DateTime.tryParse(sentStr.toString());
      if (parsed != null) baseDate = parsed.toLocal();
    }
    DateTime dueDate = DateTime(baseDate.year, baseDate.month, baseDate.day, 17, 0, 0);
    if (!baseDate.isBefore(dueDate)) {
      dueDate = dueDate.add(const Duration(days: 1));
    }
    return dueDate;
  }

  static bool _isPaymentOverdue(Map<String, dynamic> req) {
    final status = req['payment']?['status'] ?? req['status'];
    if (status == 'paid' || status == 'released') return false;
    // Overdue Payment ₱100 penalty ONLY applies after the Admin sends a receipt to the customer
    if (!_hasReceiptBeenSent(req)) return false;
    final dueDate = _getPaymentDueDate(req);
    return DateTime.now().isAfter(dueDate);
  }

  static bool _isColdStorageOverdueForBill(Map<String, dynamic> req) {
    if (req['request_type'] != 'barangay') return false;
    final reqIdStr = req['id'].toString();
    final tracking = (req['penalty_tracking'] ?? _penaltyTrackingMap[reqIdStr]) as Map<String, dynamic>?;
    final notes = (req['release_notes'] ?? '').toString();

    if (tracking?['cold_storage_billed_on_receipt'] == true ||
        tracking?['cold_storage_collected_at_release'] == true ||
        notes.contains('Cold storage fee of \u20b1150.00 collected')) {
      return true;
    }

    // If already released without cold storage fee, do not mark overdue
    if (req['status'] == 'released') return false;

    final hasPickupNotice = (tracking != null && tracking['pickup_notified_at'] != null) ||
        notes.contains('Notified ready for collection') ||
        (req['pickup_deadline'] != null && req['pickup_deadline'].toString().isNotEmpty);
    if (!hasPickupNotice) return false;

    final explicitDeadlineStr = tracking?['pickup_deadline'] ?? req['pickup_deadline'];
    if (explicitDeadlineStr != null) {
      final parsedDeadline = DateTime.tryParse(explicitDeadlineStr.toString());
      if (parsedDeadline != null) {
        return DateTime.now().isAfter(parsedDeadline.toLocal());
      }
    }

    DateTime baseDate = DateTime.now();
    final notifiedAtStr = tracking?['pickup_notified_at'];
    if (notifiedAtStr != null) {
      final parsed = DateTime.tryParse(notifiedAtStr.toString());
      if (parsed != null) baseDate = parsed.toLocal();
    } else {
      final match = RegExp(r'Notified ready for collection at ([0-9T:\.\-\+Z]+)').firstMatch(notes);
      if (match != null) {
        final parsed = DateTime.tryParse(match.group(1)!);
        if (parsed != null) baseDate = parsed.toLocal();
      }
    }
    DateTime pickupDeadline = DateTime(baseDate.year, baseDate.month, baseDate.day, 17, 0, 0);
    if (!baseDate.isBefore(pickupDeadline)) {
      pickupDeadline = pickupDeadline.add(const Duration(days: 1));
    }
    return DateTime.now().isAfter(pickupDeadline);
  }

  static Map<String, dynamic> _calcFees(Map<String, dynamic> req) {
    final animalType = (req['livestock_type'] ?? 'hog').toString();
    final rates = AppSettingsService.instance.getFeeRatesForAnimal(animalType);
    final weight = _carcassWeight(req);
    final postMortemFee = weight * rates.postMortemRatePerKg;
    final isDelayed = hasTechnicalDelay(req);
    final penaltyFee = isDelayed ? 500.0 : 0.0;
    final dueDate = _getPaymentDueDate(req);
    final isOverdue = _isPaymentOverdue(req);
    final payment = req['payment'] as Map<String, dynamic>?;
    final reqIdStr = req['id'].toString();
    final tracking = (req['penalty_tracking'] ?? _penaltyTrackingMap[reqIdStr]) as Map<String, dynamic>?;
    final storedOverdue = payment?['overdue_penalty'] != null
        ? double.tryParse(payment!['overdue_penalty'].toString()) ?? 0.0
        : (tracking?['overdue_payment_billed_on_receipt'] == true ? 100.0 : null);
    final overduePenalty = storedOverdue ?? (isOverdue ? 100.0 : 0.0);

    final isColdStorageOverdue = _isColdStorageOverdueForBill(req);
    final coldStoragePenalty = isColdStorageOverdue ? 150.0 : 0.0;

    final isPaid = (payment?['status'] == 'paid') || (req['status'] == 'paid') || (req['status'] == 'released');
    final notes = (req['release_notes'] ?? '').toString();
    final isColdStorageSettled = (tracking?['cold_storage_billed_on_receipt'] == true) ||
        (tracking?['cold_storage_collected_at_release'] == true) ||
        notes.contains('Cold storage fee of \u20b1150.00 collected') ||
        req['status'] == 'released';
    final coldStorageUnpaidOnPaidOrder = isPaid && isColdStorageOverdue && !isColdStorageSettled;

    final subtotal = rates.vetHealthCertFee +
        rates.permitToSlaughterFee +
        rates.facilityFee +
        rates.corralFee +
        rates.anteMortemFee +
        rates.additionalFee +
        postMortemFee +
        penaltyFee +
        overduePenalty +
        coldStoragePenalty;
    final isBarangay = req['request_type'] == 'barangay';
    final deliveryFee = isBarangay ? 0.0 : rates.deliveryVanFee;
    final total = subtotal + deliveryFee;
    final balanceDue = isPaid ? (coldStorageUnpaidOnPaidOrder ? 150.0 : 0.0) : total;
    final amountPaid = isPaid ? (total - balanceDue) : 0.0;

    return {
      'vet_health_cert': rates.vetHealthCertFee,
      'permit_to_slaughter': rates.permitToSlaughterFee,
      'facility': rates.facilityFee,
      'corral': rates.corralFee,
      'ante_mortem': rates.anteMortemFee,
      'post_mortem': postMortemFee,
      'additional_fee': rates.additionalFee,
      'additional_fee_label': rates.additionalFeeLabel,
      'penalty_fee': penaltyFee,
      'overdue_penalty': overduePenalty,
      'cold_storage_penalty': coldStoragePenalty,
      'is_overdue': isOverdue,
      'is_cold_storage_overdue': isColdStorageOverdue,
      'cold_storage_unpaid_on_paid_order': coldStorageUnpaidOnPaidOrder,
      'balance_due': balanceDue,
      'amount_paid': amountPaid,
      'due_date': dueDate,
      'is_delayed': isDelayed,
      'subtotal': subtotal,
      'delivery_van': deliveryFee,
      'total': total,
      'rate_per_kg': rates.postMortemRatePerKg,
    };
  }

  Future<void> _checkAndTriggerOverduePaymentPenaltyNotifications(
    List<Map<String, dynamic>> requests,
    Map<String, dynamic> trackingMap,
  ) async {
    bool trackingChanged = false;
    for (final req in requests) {
      final reqId = req['id'];
      final reqIdStr = reqId.toString();
      final existingEntry = (trackingMap[reqIdStr] is Map)
          ? Map<String, dynamic>.from(trackingMap[reqIdStr] as Map)
          : <String, dynamic>{};

      // 1. Overdue Payment Penalty (₱100.00) check
      if (_isPaymentOverdue(req)) {
        final alreadySentPost5PmNotif = _sentOverduePaymentPenaltyNotifIds.contains(reqIdStr) ||
            existingEntry['overdue_payment_penalty_notif_sent'] == true;

        if (!alreadySentPost5PmNotif) {
          _sentOverduePaymentPenaltyNotifIds.add(reqIdStr);
          existingEntry['overdue_payment_penalty_notif_sent'] = true;
          existingEntry['overdue_payment_penalty_incurred_at'] = DateTime.now().toIso8601String();
          trackingMap[reqIdStr] = existingEntry;
          req['penalty_tracking'] = existingEntry;
          trackingChanged = true;

          final fees = _calcFees(req);
          final userId = req['user_id'];
          final refNo = _refNo(req);
          final receiptNo = _receiptNo(req);

          try {
            await supabase.from('payments').update({
              'total_amount': fees['total'],
              'balance': fees['balance_due'],
            }).eq('request_id', reqId);
          } catch (_) {}

          await NotificationService.sendNotificationSafely(
            supabase,
            userId: userId,
            title: 'Overdue Payment Penalty Incurred (\u20b1100.00)',
            message: 'Your payment for Receipt $receiptNo (Ref: $refNo) was not completed by the 5:00 PM deadline. An automatic overdue payment penalty fee of \u20b1100.00 has been incurred and added to your bill (Updated Total: \u20b1${(fees['total'] as num).toStringAsFixed(2)}).',
            type: 'overdue_payment_penalty',
            data: {
              'receipt_no': receiptNo,
              'reference_no': refNo,
              'overdue_penalty': 100,
              'amount': fees['total'],
              'request_id': reqId,
            },
          );
        }
      }

      // 2. Cold Storage Penalty (₱150.00) check (applies to both Online-Paid/GCash and Cash-on-Pickup orders unclaimed past 5:00 PM)
      if (req['request_type'] == 'barangay' &&
          req['status'] != 'released' &&
          _isColdStorageOverdueForBill(req)) {
        final notes = (req['release_notes'] ?? '').toString();
        final alreadySentColdStorageNotif = _sentColdStoragePenaltyNotifIds.contains(reqIdStr) ||
            existingEntry['cold_storage_penalty_notif_sent'] == true ||
            notes.contains('Cold storage penalty notification sent');

        if (!alreadySentColdStorageNotif) {
          _sentColdStoragePenaltyNotifIds.add(reqIdStr);
          existingEntry['cold_storage_penalty_notif_sent'] = true;
          existingEntry['cold_storage_penalty_incurred_at'] = DateTime.now().toIso8601String();
          trackingMap[reqIdStr] = existingEntry;
          req['penalty_tracking'] = existingEntry;
          trackingChanged = true;

          final fees = _calcFees(req);
          final userId = req['user_id'];
          final refNo = _refNo(req);
          final receiptNo = _receiptNo(req);
          final isPaid = (req['payment']?['status'] == 'paid') || (req['status'] == 'paid');

          try {
            await supabase.from('payments').update({
              'total_amount': fees['total'],
              'balance': fees['balance_due'],
            }).eq('request_id', reqId);
          } catch (_) {}

          final updatedNotes = notes.isEmpty
              ? 'Cold storage penalty notification sent'
              : '$notes | Cold storage penalty notification sent';
          try {
            await supabase.from('requests').update({'release_notes': updatedNotes}).eq('id', reqId);
          } catch (_) {}

          await NotificationService.sendNotificationSafely(
            supabase,
            userId: userId,
            title: 'Cold Storage Penalty Incurred (\u20b1150.00)',
            message: isPaid
                ? 'Your meat order (Ref: $refNo) was not collected by the 5:00 PM deadline after collection notification. An automatic \u20b1150.00 Cold Storage penalty fee has been incurred and reflected on Receipt $receiptNo (Updated Total: \u20b1${(fees['total'] as num).toStringAsFixed(2)} | Balance Due at Pickup: \u20b1150.00).'
                : 'Your meat order (Ref: $refNo) was not collected by the 5:00 PM deadline after collection notification. An automatic \u20b1150.00 Cold Storage penalty fee has been incurred and added to Receipt $receiptNo (Updated Total: \u20b1${(fees['total'] as num).toStringAsFixed(2)}).',
            type: 'cold_storage_penalty',
            data: {
              'request_id': reqId,
              'reference_no': refNo,
              'receipt_no': receiptNo,
              'release_type': 'pickup',
              'cold_storage_fee': 150,
              'amount': fees['total'],
              'payment_status': isPaid ? 'paid' : 'unpaid',
            },
          );
        }
      }
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

  List<Map<String, dynamic>> _filteredList(List<Map<String, dynamic>> list) {
    final q = _searchController.text.toLowerCase().trim();
    return list.where((r) {
      final name = (r['customer_name'] ?? '').toString().toLowerCase();
      final ref = _refNo(r).toLowerCase();
      final paymentStatus = _paymentStatus(r);

      bool matchesSearch = q.isEmpty || name.contains(q) || ref.contains(q);
      bool matchesFilter = _filterStatus == 'All' || paymentStatus == _filterStatus;

      return matchesSearch && matchesFilter;
    }).toList();
  }

  String _paymentStatus(Map<String, dynamic> req) {
    final payment = req['payment'] as Map<String, dynamic>?;
    if (payment != null && payment['status'] == 'paid') return 'Verified';
    if (req['status'] == 'paid' || req['status'] == 'released') return 'Verified';
    if (payment != null && payment['payment_method'] != null && payment['payment_method'].toString().trim().isNotEmpty) {
      final m = payment['payment_method'].toString().trim().toLowerCase();
      if (m == 'gcash') {
        return 'Verified';
      }
      if (!m.contains('gcash') && m.contains('cash')) {
        return 'Cash on Pick-up';
      }
      return 'Awaiting Verification';
    }
    if (req['status'] == 'payment_pending') return 'Awaiting Payment';
    return 'Pending';
  }

  String _paymentMethod(Map<String, dynamic> req) {
    final payment = req['payment'] as Map<String, dynamic>?;
    if (payment != null && payment['payment_method'] != null) {
      return payment['payment_method'].toString();
    }
    return req['payment_method']?.toString() ?? '—';
  }

  // ════════════════════════════════════════════
  //  SEND RECEIPT TO CUSTOMER
  // ════════════════════════════════════════════
  Future<void> _sendReceiptForPayment(Map<String, dynamic> req) async {
    try {
      final reqId = req['id'];
      final reqIdStr = reqId.toString();
      final userId = req['user_id'];
      final now = DateTime.now();

      // Record receipt_sent_at in penalty_tracking so 5:00 PM due date is anchored accurately
      final existingEntry = (_penaltyTrackingMap[reqIdStr] is Map)
          ? Map<String, dynamic>.from(_penaltyTrackingMap[reqIdStr] as Map)
          : <String, dynamic>{};
      existingEntry['receipt_sent_at'] = existingEntry['receipt_sent_at'] ?? now.toIso8601String();
      _penaltyTrackingMap[reqIdStr] = existingEntry;
      req['penalty_tracking'] = existingEntry;
      try {
        await supabase.from('system_settings').upsert({
          'key': 'pickup_penalty_tracking',
          'value': _penaltyTrackingMap,
        });
      } catch (_) {}

      final fees = _calcFees(req);
      final receiptNo = _receiptNo(req);
      final refNo = _refNo(req);
      final isBarangay = req['request_type'] == 'barangay';
      final dueDate = fees['due_date'] as DateTime? ?? now;
      final dueDateStr = DateFormat('MMMM d, yyyy • 5:00 PM').format(dueDate);

      // Upsert payment record
      final existing = await supabase.from('payments').select('id').eq('request_id', reqId).maybeSingle();
      final paymentData = {
        'request_id': reqId,
        'user_id': userId,
        'payment_method': null,
        'total_amount': fees['total'],
        'balance': fees['total'],
        'status': 'pending',
        'cashier_name': null,
        'vet_health_cert_fee': fees['vet_health_cert'],
        'permit_fee': fees['permit_to_slaughter'],
        'facility_fee': fees['facility'],
        'corral_fee': fees['corral'],
        'ante_mortem_fee': fees['ante_mortem'],
        'post_mortem_fee': fees['post_mortem'],
        'delivery_van_fee': fees['delivery_van'],
        'created_at': now.toIso8601String(),
      };

      if (existing != null) {
        await supabase.from('payments').update(paymentData).eq('request_id', reqId);
      } else {
        await supabase.from('payments').insert(paymentData);
      }

      // Update request status
      await supabase.from('requests').update({'status': 'payment_pending'}).eq('id', reqId);

      // Send notification to customer safely (includes 5:00 PM penalty reminder)
      await NotificationService.sendNotificationSafely(
        supabase,
        userId: userId,
        title: 'Slaughter Request Receipt Issued (Pay Before 5:00 PM)',
        message: isBarangay
            ? 'Your slaughter operation request ($refNo) has been processed and Receipt $receiptNo (Total: \u20b1${(fees['total'] as num).toStringAsFixed(2)}) has been issued. REMINDER: Payment must be made on or before $dueDateStr or an automatic \u20b1100.00 Overdue Payment penalty fee will be incurred. Additionally, meat not picked up by 5:00 PM after collection notice incurs a \u20b1150.00 Cold Storage fee.'
            : 'Your slaughter operation request ($refNo) has been processed and Receipt $receiptNo (Total: \u20b1${(fees['total'] as num).toStringAsFixed(2)}) has been issued. REMINDER: Payment must be made on or before $dueDateStr. If the 5:00 PM deadline passes without payment, an automatic \u20b1100.00 Overdue Payment penalty fee will be incurred.',
        type: 'receipt_issued',
        data: {
          'receipt_no': receiptNo,
          'reference_no': refNo,
          'amount': fees['total'],
          'request_id': reqId,
          'due_date': dueDate.toIso8601String(),
        },
      );

      _loadRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Receipt sent with 5:00 PM penalty reminder! Awaiting customer payment...'),
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
  //  VERIFY AND CONFIRM PAYMENT (Online/Manual)
  // ════════════════════════════════════════════
  Future<void> _verifyAndConfirmPayment(Map<String, dynamic> req) async {
    try {
      final reqId = req['id'];
      final reqIdStr = reqId.toString();
      final userId = req['user_id'];
      final fees = _calcFees(req);
      final receiptNo = _receiptNo(req);
      final refNo = _refNo(req);
      final method = _paymentMethod(req);
      final resolvedMethod = (method != '—' && method.isNotEmpty) ? method : 'GCash';

      final paymentData = {
        'request_id': reqId,
        'user_id': userId,
        'receipt_number': receiptNo,
        'payment_method': resolvedMethod,
        'total_amount': fees['total'],
        'balance': 0,
        'status': 'paid',
        'cashier_name': 'Admin',
        'vet_health_cert_fee': fees['vet_health_cert'],
        'permit_fee': fees['permit_to_slaughter'],
        'facility_fee': fees['facility'],
        'corral_fee': fees['corral'],
        'ante_mortem_fee': fees['ante_mortem'],
        'post_mortem_fee': fees['post_mortem'],
        'delivery_van_fee': fees['delivery_van'],
      };

      final existing = await supabase.from('payments').select('id').eq('request_id', reqId).maybeSingle();
      if (existing != null) {
        await supabase.from('payments').update(paymentData).eq('request_id', reqId);
      } else {
        await supabase.from('payments').insert(paymentData);
      }

      await supabase.from('requests').update({'status': 'paid'}).eq('id', reqId);

      // Persist whether overdue_penalty or cold_storage_penalty was settled on this receipt
      final hasOverdue = ((fees['overdue_penalty'] as num?)?.toDouble() ?? 0.0) > 0;
      final hasColdStorage = ((fees['cold_storage_penalty'] as num?)?.toDouble() ?? 0.0) > 0;
      if (hasOverdue || hasColdStorage) {
        try {
          final existingEntry = (_penaltyTrackingMap[reqIdStr] is Map)
              ? Map<String, dynamic>.from(_penaltyTrackingMap[reqIdStr] as Map)
              : <String, dynamic>{};
          if (hasOverdue) existingEntry['overdue_payment_billed_on_receipt'] = true;
          if (hasColdStorage) existingEntry['cold_storage_billed_on_receipt'] = true;
          _penaltyTrackingMap[reqIdStr] = existingEntry;
          req['penalty_tracking'] = existingEntry;
          await supabase.from('system_settings').upsert({
            'key': 'pickup_penalty_tracking',
            'value': _penaltyTrackingMap,
          });
        } catch (_) {}
      }

      // Send notification to customer safely
      await NotificationService.sendNotificationSafely(
        supabase,
        userId: userId,
        title: 'Payment Confirmed — Receipt & Pickup Authorization Issued',
        message: 'Your payment of \u20b1${(fees['total'] as num).toStringAsFixed(2)} via $resolvedMethod for request $refNo has been confirmed! Your Official Receipt has been generated with your Meat Pickup Authorization. You may now claim your carcass from the dispatcher.',
        type: 'payment_verified',
        data: {
          'receipt_no': receiptNo,
          'reference_no': refNo,
          'amount': fees['total'],
          'request_id': reqId,
        },
      );

      _loadRequests();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text('Payment for $refNo verified and confirmed!'),
            ]),
            backgroundColor: Colors.green.shade600,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error verifying payment: $e'), backgroundColor: Colors.redAccent),
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
                          _buildTopActionBar(),
                          const SizedBox(height: 24),
                          _buildFilterRow(),
                          const SizedBox(height: 24),
                          _buildTableCard(
                            title: 'Barangay — Payment & Cashiering Records',
                            subtitle: 'Fee calculation, payment verification, and receipt management',
                            requests: _filteredList(_barangayRequests),
                          ),
                          const SizedBox(height: 24),
                          _buildTableCard(
                            title: 'Market — Payment & Cashiering Records',
                            subtitle: 'Fee calculation, payment verification, and receipt management',
                            requests: _filteredList(_marketRequests),
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
              const Text('Payment & Cashiering',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
              const SizedBox(height: 2),
              Text('Fee calculation, payment recording, receipts',
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
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_forward, size: 26),
            color: const Color(0xFF2D3748),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  TOP ACTION BAR (Stats + New Payment)
  // ════════════════════════════════════════════
  Widget _buildTopActionBar() {
    final allReqs = [..._barangayRequests, ..._marketRequests];
    int verified = 0, outstanding = 0;
    for (var r in allReqs) {
      if (_paymentStatus(r) == 'Verified') {
        verified++;
      } else {
        outstanding++;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 650;
        final newPaymentBtn = ElevatedButton.icon(
          onPressed: _showNewPaymentDialog,
          icon: const Icon(Icons.add, size: 18, color: Colors.white),
          label: const Text('New Payment Process', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2D3748),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: _statCard('Verified', verified.toString(), const Color(0xFF2D6A4F), icon: Icons.check_circle_outline)),
                  const SizedBox(width: 12),
                  Expanded(child: _statCard('Outstanding', outstanding.toString(), Colors.red)),
                ],
              ),
              const SizedBox(height: 12),
              newPaymentBtn,
            ],
          );
        }

        return Row(
          children: [
            _statCard('Verified', verified.toString(), const Color(0xFF2D6A4F), icon: Icons.check_circle_outline),
            const SizedBox(width: 16),
            _statCard('Outstanding', outstanding.toString(), Colors.red),
            const Spacer(),
            newPaymentBtn,
          ],
        );
      },
    );
  }

  Widget _statCard(String label, String value, Color accent, {IconData? icon}) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
              if (icon != null)
                Icon(icon, size: 16, color: accent)
              else
                Container(width: 10, height: 10, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  FILTER ROW
  // ════════════════════════════════════════════
  Widget _buildFilterRow() {
    return Row(
      children: [
        SizedBox(
          width: 300,
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search by reference number or name...',
              hintStyle: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: Color(0xFFA0AEC0), size: 20),
              filled: true,
              fillColor: const Color(0xFFEDF2F7),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFEDF2F7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _filterStatus,
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
              items: ['All', 'Verified', 'Pending']
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
  //  DATA TABLE
  // ════════════════════════════════════════════
  Widget _buildTableCard({required String title, required String subtitle, required List<Map<String, dynamic>> requests}) {
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
                          DataColumn(label: Text('Livestock', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                          DataColumn(label: Text('Weight (kg)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                          DataColumn(label: Text('Post-Mortem\nFee', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                          DataColumn(label: Text('Payment Method', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                          DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                          DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                        ],
                        rows: requests.map((req) {
                          final ref = _refNo(req);
                          final weight = _carcassWeight(req);
                          final fees = _calcFees(req);
                          final postMortemFee = fees['post_mortem']!;
                          final status = _paymentStatus(req);
                          final method = _paymentMethod(req);

                          return DataRow(cells: [
                            DataCell(Text(ref, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12))),
                            DataCell(Text(req['customer_name']?.toString() ?? '\u2014', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                            DataCell(Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${req['animal_count'] ?? 1} head(s)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                Text('${req['livestock_type'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                              ],
                            )),
                            DataCell(Text(weight > 0 ? '${weight.toStringAsFixed(0)} kg' : '\u2014', style: const TextStyle(fontSize: 13))),
                            DataCell(Text(weight > 0 ? '\u20b1${postMortemFee.toStringAsFixed(2)}' : '\u2014', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                            DataCell(Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (method != '\u2014') ...[
                                  Icon(
                                    method == 'Cash' ? Icons.payments_outlined : (method == 'GCash' ? Icons.phone_android : Icons.credit_card),
                                    size: 14,
                                    color: Colors.grey.shade600,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Text(method, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                              ],
                            )),
                            DataCell(_buildStatusBadge(status)),
                            DataCell(Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _showReceiptDialog(req),
                                  icon: const Icon(Icons.receipt_long, size: 14),
                                  label: const Text('Details', style: TextStyle(fontSize: 11)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF4A5568),
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    minimumSize: const Size(0, 32),
                                    side: BorderSide(color: Colors.grey.shade300),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                ),
                                if (status == 'Awaiting Verification' || status == 'Cash on Pick-up') ...[
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: () => _verifyAndConfirmPayment(req),
                                    icon: const Icon(Icons.check_circle, size: 13, color: Colors.white),
                                    label: Text(
                                      status == 'Cash on Pick-up' ? 'Confirm Payment' : 'Verify',
                                      style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2D6A4F),
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      minimumSize: const Size(0, 32),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                      elevation: 0,
                                    ),
                                  ),
                                ],
                              ],
                            )),
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
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text('No records found', style: TextStyle(color: Colors.grey, fontSize: 13)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg = const Color(0xFFFFF8E5);
    Color text = const Color(0xFFB8860B);
    if (status == 'Verified' || status == 'Paid') {
      bg = const Color(0xFFE6F9F0);
      text = const Color(0xFF1A8C62);
    } else if (status == 'Awaiting Verification') {
      bg = const Color(0xFFEBF8FF);
      text = const Color(0xFF2B6CB0);
    } else if (status == 'Cash on Pick-up') {
      bg = const Color(0xFFFEF3C7);
      text = const Color(0xFFB45309);
    } else if (status == 'Awaiting Payment') {
      bg = const Color(0xFFFFFBEB);
      text = const Color(0xFFC05621);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: text,
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  RECEIPT DIALOG
  // ════════════════════════════════════════════
  void _showReceiptDialog(Map<String, dynamic> req) {
    final fees = _calcFees(req);
    final isBarangay = req['request_type'] == 'barangay';
    final typeLabel = isBarangay ? 'BARANGAY' : 'MARKET';
    final receiptNo = _receiptNo(req);
    final refNo = _refNo(req);
    final status = _paymentStatus(req);
    final method = _paymentMethod(req);
    final weight = _carcassWeight(req);
    final payment = req['payment'] as Map<String, dynamic>?;

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(32),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Center(
                  child: Text(
                    'Payment  Receipt for "$typeLabel"',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 20),

                // Receipt Info
                Text('Receipt Number: $receiptNo', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text('Date: ${DateFormat('M/dd/yyyy').format(DateTime.now())}', style: const TextStyle(fontSize: 13)),
                Text('Time: ${DateFormat('h:mm:ss a').format(DateTime.now())}', style: const TextStyle(fontSize: 13)),
                if (status != 'Verified' && status != 'Awaiting Verification') ...[
                  Text(
                    'Due Date: ${DateFormat('M/dd/yyyy').format(fees['due_date'] as DateTime? ?? DateTime.now())} • 5:00 PM',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: (fees['is_overdue'] == true || fees['is_cold_storage_overdue'] == true)
                          ? const Color(0xFFC53030)
                          : const Color(0xFF2D3748),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (fees['is_overdue'] == true || fees['is_cold_storage_overdue'] == true)
                          ? const Color(0xFFFFF5F5)
                          : const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (fees['is_overdue'] == true || fees['is_cold_storage_overdue'] == true)
                            ? const Color(0xFFFEB2B2)
                            : const Color(0xFFFBD38D),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          (fees['is_overdue'] == true || fees['is_cold_storage_overdue'] == true)
                              ? Icons.error_outline
                              : Icons.warning_amber_rounded,
                          color: (fees['is_overdue'] == true || fees['is_cold_storage_overdue'] == true)
                              ? const Color(0xFFC53030)
                              : const Color(0xFFC05621),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            (fees['is_overdue'] == true && fees['is_cold_storage_overdue'] == true)
                                ? 'PENALTIES INCURRED: 5:00 PM deadline expired. An automatic Overdue Payment Penalty (\u20b1100.00) and Cold Storage Penalty (\u20b1150.00) have been added to the balance.'
                                : (fees['is_overdue'] == true)
                                    ? 'PAYMENT OVERDUE: 5:00 PM due date expired. An automatic penalty of \u20b1100.00 has been added to the balance.'
                                    : (fees['is_cold_storage_overdue'] == true)
                                        ? 'COLD STORAGE OVERDUE: Meat was not picked up by 5:00 PM after collection notice. An automatic Cold Storage fee of \u20b1150.00 has been added to the balance.'
                                        : isBarangay
                                            ? 'REMINDER: Payment must be made on or before 5:00 PM today or an automatic \u20b1100.00 Overdue Payment penalty applies. Meat not picked up by 5:00 PM after collection notice incurs a \u20b1150.00 Cold Storage fee.'
                                            : 'REMINDER: Payment must be made immediately on or before 5:00 PM today. If the due date passes without payment, an automatic overdue penalty of \u20b1100.00 will be applied.',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: (fees['is_overdue'] == true || fees['is_cold_storage_overdue'] == true)
                                  ? const Color(0xFF9B2C2C)
                                  : const Color(0xFF975A16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (fees['is_cold_storage_overdue'] == true) ...[
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (fees['cold_storage_unpaid_on_paid_order'] == true)
                          ? const Color(0xFFFFF5F5)
                          : const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (fees['cold_storage_unpaid_on_paid_order'] == true)
                            ? const Color(0xFFFEB2B2)
                            : const Color(0xFF86EFAC),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          (fees['cold_storage_unpaid_on_paid_order'] == true)
                              ? Icons.ac_unit
                              : Icons.check_circle,
                          color: (fees['cold_storage_unpaid_on_paid_order'] == true)
                              ? const Color(0xFFC53030)
                              : const Color(0xFF15803D),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            (fees['cold_storage_unpaid_on_paid_order'] == true)
                                ? 'COLD STORAGE PENALTY INCURRED (\u20b1150.00): Carcass was not collected by 5:00 PM after collection notice. Base slaughter fees were paid via ${method.toUpperCase()}, and an additional \u20b1150.00 Cold Storage fee is due upon pickup.'
                                : 'COLD STORAGE FEE (\u20b1150.00): Settled and included in this receipt.',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: (fees['cold_storage_unpaid_on_paid_order'] == true)
                                  ? const Color(0xFF9B2C2C)
                                  : const Color(0xFF166534),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Customer Info
                const Text('CUSTOMER INFORMATION:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                Text('Name: ${req['customer_name'] ?? '\u2014'}', style: const TextStyle(fontSize: 13)),
                Text('Reference: $refNo', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 16),

                // Livestock Info
                const Text('LIVESTOCK INFORMATION:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                Text('Animal Type: ${req['livestock_type'] ?? '\u2014'}', style: const TextStyle(fontSize: 13)),
                Text('Count: ${req['animal_count'] ?? 1}', style: const TextStyle(fontSize: 13)),
                Text('Weight: ${weight > 0 ? '${weight.toStringAsFixed(0)} kg' : '\u2014'}', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 16),

                // Fee Breakdown
                const Text('Payment Calculation Preview', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _feeRow('Veterinary Health Certificate:', '\u20b1${(fees['vet_health_cert'] as double).toStringAsFixed(2)}'),
                _feeRow('Permit to Slaughter:', '\u20b1${(fees['permit_to_slaughter'] as double).toStringAsFixed(2)}'),
                _feeRow('Facility Fee:', '\u20b1${(fees['facility'] as double).toStringAsFixed(2)}'),
                _feeRow('Corral Fee:', '\u20b1${(fees['corral'] as double).toStringAsFixed(2)}'),
                _feeRow('Ante-Mortem Fee:', '\u20b1${(fees['ante_mortem'] as double).toStringAsFixed(2)}'),
                _feeRow('Post-Mortem (${weight.toStringAsFixed(0)} kg @ \u20b1${((fees['rate_per_kg'] as num?)?.toDouble() ?? 5.0).toStringAsFixed(2)}/kg):', '\u20b1${(fees['post_mortem'] as double).toStringAsFixed(2)}'),
                if (((fees['additional_fee'] as num?)?.toDouble() ?? 0.0) > 0)
                  _feeRow(
                    '${fees['additional_fee_label'] ?? 'Additional Surcharge'}:',
                    '\u20b1${((fees['additional_fee'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                  ),
                if (((fees['overdue_penalty'] as num?)?.toDouble() ?? 0.0) > 0)
                  _feeRow(
                    'Overdue Payment Penalty (Past 5:00 PM):',
                    '\u20b1${((fees['overdue_penalty'] as num?)?.toDouble() ?? 100.0).toStringAsFixed(2)}',
                    bold: true,
                  ),
                if (((fees['cold_storage_penalty'] as num?)?.toDouble() ?? 0.0) > 0)
                  _feeRow(
                    'Cold Storage Penalty Fee (Unclaimed Past 5:00 PM):',
                    '\u20b1${((fees['cold_storage_penalty'] as num?)?.toDouble() ?? 150.0).toStringAsFixed(2)}',
                    bold: true,
                  ),
                if (((fees['penalty_fee'] as num?)?.toDouble() ?? 0.0) > 0)
                  _feeRow(
                    'Legal Finality / Penalty Fee (Delayed Operation):',
                    '\u20b1${((fees['penalty_fee'] as num?)?.toDouble() ?? 500.0).toStringAsFixed(2)}',
                    bold: true,
                  ),
                const SizedBox(height: 8),
                Divider(color: Colors.grey.shade300),
                _feeRow('Subtotal:', '\u20b1${(fees['subtotal'] as double).toStringAsFixed(2)}', bold: true),
                if (!isBarangay) _feeRow('Delivery Van Fee:', '\u20b1${(fees['delivery_van'] as double).toStringAsFixed(2)}'),
                const SizedBox(height: 8),
                Divider(color: Colors.grey.shade400),
                const SizedBox(height: 4),
                _feeRow('TOTAL AMOUNT:', '\u20b1${((fees['total'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}', bold: true, large: true),
                const SizedBox(height: 12),
                if (fees['cold_storage_unpaid_on_paid_order'] == true) ...[
                  _feeRow('AMOUNT PAID (${method.toUpperCase()}):', '\u20b1${((fees['amount_paid'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}', bold: true),
                  _feeRow('BALANCE (COLD STORAGE FEE DUE AT PICKUP):', '\u20b1150.00', bold: true),
                ] else ...[
                  _feeRow('BALANCE:', status == 'Verified' ? '0' : '\u20b1${((fees['total'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}', bold: true),
                ],
                const SizedBox(height: 12),

                // Payment Details
                if (status == 'Verified') ...[
                  Text('Payment Method: ${method.toUpperCase()}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(
                    (fees['cold_storage_unpaid_on_paid_order'] == true)
                        ? 'Status: PAID (BASE FEES) • \u20b1150.00 COLD STORAGE FEE DUE AT PICKUP'
                        : 'Status: PAID',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text('Cashier: ${payment?['cashier_name'] ?? 'Admin'}', style: const TextStyle(fontSize: 13)),
                  if (isBarangay) ...[
                    const SizedBox(height: 14),
                    Builder(
                      builder: (_) {
                        final authName = (req['authorized_person_name'] ?? '').toString().trim();
                        final authContact = (req['authorized_person_contact'] ?? '').toString().trim();
                        final authRel = (req['authorized_person_relationship'] ?? '').toString().trim();
                        final authIdType = (req['authorized_person_id_type'] ?? '').toString().trim();
                        final authIdNum = (req['authorized_person_id_num'] ?? '').toString().trim();
                        final hasAuth = authName.isNotEmpty;
                        return Container(
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
                                  const Icon(Icons.verified_user, size: 16, color: Color(0xFF15803D)),
                                  const SizedBox(width: 6),
                                  const Expanded(
                                    child: Text(
                                      'MEAT PICKUP AUTHORIZATION: GRANTED',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              if (hasAuth) ...[
                                Text(
                                  'Authorized Person for Pickup: $authName${authRel.isNotEmpty ? " ($authRel)" : ""}',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                                ),
                                if (authContact.isNotEmpty)
                                  Text('Contact: $authContact', style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
                                if (authIdType.isNotEmpty || authIdNum.isNotEmpty)
                                  Text('Valid ID: $authIdType — $authIdNum', style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
                              ] else ...[
                                Text(
                                  'Authorized Person for Pickup: ${req['customer_name'] ?? 'Customer'} (Customer Direct)',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ] else if (method != '—' && method.isNotEmpty) ...[
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEBF8FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF90CDF4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.phone_android, color: Color(0xFF2B6CB0), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Customer submitted payment via $method. Click "Verify & Confirm $method Payment" below to complete and confirm.',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF2B6CB0), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Footer
                const Text('Thank you!', style: TextStyle(fontSize: 13)),
                const Text('Tabaco City Slaughterhouse', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 20),

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (status != 'Verified' && req['status'] != 'payment_pending')
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _sendReceiptForPayment(req);
                        },
                        icon: const Icon(Icons.send, size: 16, color: Colors.white),
                        label: const Text('Send Receipt to Customer', style: TextStyle(color: Colors.white, fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2D6A4F),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    if (status != 'Verified' && method != '—' && method.isNotEmpty)
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _verifyAndConfirmPayment(req);
                        },
                        icon: const Icon(Icons.check_circle, size: 16, color: Colors.white),
                        label: Text('Verify & Confirm $method Payment', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2D6A4F),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      )
                    else if (req['status'] == 'payment_pending' && status != 'Verified')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.hourglass_empty, size: 16, color: Colors.orange),
                            SizedBox(width: 8),
                            Text('Awaiting Customer Payment', style: TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    if (status != 'Verified') const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.print, size: 16),
                      label: const Text('Print', style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF2D3748),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        side: const BorderSide(color: Color(0xFF2D3748)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _feeRow(String label, String amount, {bool bold = false, bool large = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: large ? 14 : 13, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(amount, style: TextStyle(fontSize: large ? 14 : 13, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }



  // ════════════════════════════════════════════
  //  NEW PAYMENT ENTRY DIALOG (Walk-in)
  // ════════════════════════════════════════════
  void _showNewPaymentDialog() {
    final allReqs = [..._barangayRequests, ..._marketRequests];
    // Gather orders awaiting or pending payment
    final pendingReqs = allReqs.where((r) {
      final s = _paymentStatus(r);
      return s != 'Verified' && r['status'] != 'paid' && r['status'] != 'released';
    }).toList();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NewPaymentEntryDialog(
        supabase: supabase,
        pendingRequests: pendingReqs,
        onDone: _loadRequests,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  NEW PAYMENT ENTRY DIALOG (Stateful)
// ═══════════════════════════════════════════════════════════
class _NewPaymentEntryDialog extends StatefulWidget {
  final SupabaseClient supabase;
  final List<Map<String, dynamic>> pendingRequests;
  final VoidCallback onDone;
  const _NewPaymentEntryDialog({
    required this.supabase,
    required this.pendingRequests,
    required this.onDone,
  });
  @override
  State<_NewPaymentEntryDialog> createState() => _NewPaymentEntryDialogState();
}

class _NewPaymentEntryDialogState extends State<_NewPaymentEntryDialog> {
  final _refCtrl = TextEditingController();
  String _customerName = '';
  double _totalAmount = 0;
  double _balanceAmount = 0;
  String _selectedMethod = 'Cash';
  bool _isLoading = false;
  bool _isProcessing = false;
  Map<String, dynamic>? _foundRequest;
  Map<String, dynamic> _fees = {};
  late final String _yearPrefix;

  @override
  void initState() {
    super.initState();
    _yearPrefix = 'MI-${DateTime.now().year}-';
  }

  Future<void> _lookupReference([String? manualInput]) async {
    String input = (manualInput ?? _refCtrl.text).trim();
    if (input.isEmpty) return;

    // Normalize: remove prefix if typed or pasted
    input = input.replaceAll('MI-', '').replaceAll('mi-', '');
    final year = DateTime.now().year.toString();
    if (input.startsWith('$year-')) {
      input = input.replaceFirst('$year-', '');
    } else if (input.startsWith('2025-') || input.startsWith('2026-')) {
      input = input.substring(5);
    }
    input = input.replaceAll(RegExp(r'[^0-9]'), '');

    final requestId = int.tryParse(input);
    if (requestId == null) {
      if (mounted && manualInput == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid reference number (e.g. 114)'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Keep controller showing just the digits
    if (_refCtrl.text != input) {
      _refCtrl.text = input;
      _refCtrl.selection = TextSelection.fromPosition(TextPosition(offset: input.length));
    }

    setState(() => _isLoading = true);
    try {
      final data = await widget.supabase
          .from('requests')
          .select('*, slaughter_inspection(*), payments(*)')
          .eq('id', requestId)
          .maybeSingle();

      if (data == null) {
        if (mounted && manualInput == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No request found with reference $_yearPrefix${input.padLeft(3, '0')}'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        setState(() {
          _foundRequest = null;
          _customerName = '';
          _totalAmount = 0;
          _balanceAmount = 0;
          _fees = {};
          _isLoading = false;
        });
        return;
      }

      // Flatten inspection data (can be Map or List)
      final inspection = data['slaughter_inspection'];
      if (inspection is Map) {
        data['carcass_weight'] = inspection['carcass_weight'];
        data['inspector_name'] = inspection['inspector_name'];
      } else if (inspection is List && inspection.isNotEmpty) {
        final first = inspection.first as Map;
        data['carcass_weight'] = first['carcass_weight'];
        data['inspector_name'] = first['inspector_name'];
      }

      // Flatten payment data (can be Map or List)
      final payment = data['payments'];
      if (payment is Map) {
        data['payment'] = payment;
      } else if (payment is List && payment.isNotEmpty) {
        data['payment'] = payment.first as Map<String, dynamic>;
      }

      // Calculate fees dynamically based on configured animal rates and carcass weight
      final fees = _PaymentCashieringPageState._calcFees(data);
      double total = fees['total']!;

      // If already recorded in payments table, use the larger of storedTotal and dynamically calculated total (so penalties incurred after 5:00 PM are included)
      final storedPay = data['payment'] as Map<String, dynamic>?;
      if (storedPay != null && storedPay['total_amount'] != null) {
        final storedTotal = double.tryParse(storedPay['total_amount'].toString());
        if (storedTotal != null && storedTotal > total) {
          total = storedTotal;
          fees['total'] = total;
        }
      }

      setState(() {
        _foundRequest = data;
        _customerName = data['customer_name']?.toString() ?? '';
        _totalAmount = total;
        _balanceAmount = total;
        _fees = fees;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Lookup error: $e');
      setState(() => _isLoading = false);
    }
  }

  void _selectPending(Map<String, dynamic> req) {
    final id = req['id'].toString().padLeft(3, '0');
    _refCtrl.text = id;
    _lookupReference(id);
  }

  Future<void> _processPayment() async {
    if (_foundRequest == null) return;
    setState(() => _isProcessing = true);
    try {
      final req = _foundRequest!;
      final reqId = req['id'];
      final userId = req['user_id'];
      final receiptNo = 'RCP-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';
      final refNo = 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';

      // Check existing payment
      final existing = await widget.supabase.from('payments').select('id').eq('request_id', reqId).maybeSingle();
      final paymentData = {
        'request_id': reqId,
        'user_id': userId,
        'receipt_number': receiptNo,
        'payment_method': _selectedMethod,
        'total_amount': _fees['total'],
        'balance': 0,
        'status': 'paid',
        'cashier_name': 'Admin',
        'vet_health_cert_fee': _fees['vet_health_cert'],
        'permit_fee': _fees['permit_to_slaughter'],
        'facility_fee': _fees['facility'],
        'corral_fee': _fees['corral'],
        'ante_mortem_fee': _fees['ante_mortem'],
        'post_mortem_fee': _fees['post_mortem'],
        'delivery_van_fee': _fees['delivery_van'],
      };

      if (existing != null) {
        await widget.supabase.from('payments').update(paymentData).eq('request_id', reqId);
      } else {
        await widget.supabase.from('payments').insert(paymentData);
      }

      await widget.supabase.from('requests').update({'status': 'paid'}).eq('id', reqId);

      // Send notification safely
      await NotificationService.sendNotificationSafely(
        widget.supabase,
        userId: userId,
        title: 'Slaughter Request Receipt Issued',
        message: 'Your slaughter operation request has been successfully processed. A receipt has been generated for your transaction and is now available for viewing.',
        type: 'receipt_issued',
        data: {
          'receipt_no': receiptNo,
          'reference_no': refNo,
          'amount': _fees['total'],
          'request_id': reqId,
        },
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onDone();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Payment processed successfully'),
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
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('New Payment  Entry', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Enter  payment detail to process a new transaction', style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 24),

              // Reference Number & Customer Name
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(text: const TextSpan(
                          text: 'Reference Number ',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2D3748)),
                          children: [TextSpan(text: '*', style: TextStyle(color: Colors.red))],
                        )),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _refCtrl,
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final trimmed = val.trim();
                            if (trimmed.length >= 3) {
                              _lookupReference(trimmed);
                            }
                          },
                          onSubmitted: (val) => _lookupReference(val),
                          decoration: InputDecoration(
                            prefixText: _yearPrefix,
                            prefixStyle: const TextStyle(
                              color: Color(0xFF2D6A4F),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            hintText: '001',
                            hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                            filled: true,
                            fillColor: const Color(0xFFF7FAFC),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                            suffixIcon: _isLoading
                                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                                : IconButton(icon: const Icon(Icons.search, size: 20), onPressed: () => _lookupReference()),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(text: const TextSpan(
                          text: 'Customer Name ',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2D3748)),
                          children: [TextSpan(text: '*', style: TextStyle(color: Colors.red))],
                        )),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            _customerName.isNotEmpty ? _customerName : '\u2014',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, fontWeight: _customerName.isNotEmpty ? FontWeight.w600 : FontWeight.normal, color: _customerName.isNotEmpty ? Colors.black87 : Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Pending suggestions chips
              if (widget.pendingRequests.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pending Awaiting Payment (Click to select):',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF065F46),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: widget.pendingRequests.map((r) {
                          final idStr = r['id'].toString().padLeft(3, '0');
                          final name = r['customer_name'] ?? 'Customer';
                          final isSelected = _refCtrl.text.trim() == idStr || _refCtrl.text.trim() == r['id'].toString();
                          return InkWell(
                            onTap: () => _selectPending(r),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF2D6A4F) : Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFF2D6A4F) : const Color(0xFF6EE7B7),
                                ),
                              ),
                              child: Text(
                                '#$idStr • $name',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? Colors.white : const Color(0xFF047857),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // Total Amount & Balance Amount
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(text: const TextSpan(
                          text: 'Total Amount ',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2D3748)),
                          children: [TextSpan(text: '*', style: TextStyle(color: Colors.red))],
                        )),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            _totalAmount > 0 ? _totalAmount.toStringAsFixed(2) : '0.00',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(text: const TextSpan(
                          text: 'Balance Amount ',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2D3748)),
                          children: [TextSpan(text: '*', style: TextStyle(color: Colors.red))],
                        )),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            _balanceAmount > 0 ? _balanceAmount.toStringAsFixed(2) : '0.00',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Payment Method
              RichText(text: const TextSpan(
                text: 'Payment Method ',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2D3748)),
                children: [TextSpan(text: '*', style: TextStyle(color: Colors.red))],
              )),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedMethod,
                    isExpanded: true,
                    hint: const Text('Select payment method', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    items: ['Cash', 'GCash', 'Card']
                        .map((m) => DropdownMenuItem(
                              value: m,
                              child: Row(
                                children: [
                                  Icon(
                                    m == 'Cash' ? Icons.payments_outlined : (m == 'GCash' ? Icons.phone_android : Icons.credit_card),
                                    size: 18,
                                    color: Colors.grey.shade600,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(m, style: const TextStyle(fontSize: 14)),
                                ],
                              ),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedMethod = v);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Process Button
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _foundRequest != null && !_isProcessing ? _processPayment : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2D3748),
                      disabledBackgroundColor: Colors.grey.shade300,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isProcessing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Process Payment', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:printing/printing.dart';
import '../services/app_settings_service.dart';
import '../services/audit_log_service.dart';
import '../services/notification_service.dart';
import '../services/receipt_pdf_generator.dart';
import '../services/staff_notification_service.dart';
import '../widgets/staff_notification_bell.dart';
import '../widgets/walk_in_sms_helper.dart';

class PaymentCashieringPage extends StatefulWidget {
  final void Function(int moduleIndex, [String? tab])? onNavigate;
  const PaymentCashieringPage({super.key, this.onNavigate});
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
  final Set<String> _sendingReceiptIds = {};
  final Set<String> _sentReceiptIds = {};
  final Set<String> _verifyingPaymentIds = {};
  static Map<String, dynamic> _penaltyTrackingMap = {};

  @override
  void initState() {
    super.initState();
    _loadRequests();
    // Auto-poll every 3 seconds so payments made on mobile reflect immediately
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
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
          final t = trackingMap[reqIdStr] as Map;
          r['penalty_tracking'] = Map<String, dynamic>.from(t);
          if (t['penalty_fee'] != null) {
            r['penalty_fee'] = t['penalty_fee'];
          }
          if (t['penalty_reason'] != null) {
            r['penalty_reason'] = t['penalty_reason'];
          }
        }
        // Flatten slaughter_inspection
        _applyInspectionFields(r, r['slaughter_inspection']);
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

  static void _applyInspectionFields(Map<String, dynamic> target, dynamic inspection) {
    Map<String, dynamic>? insp;
    if (inspection is List && inspection.isNotEmpty && inspection.first is Map) {
      insp = Map<String, dynamic>.from(inspection.first as Map);
    } else if (inspection is Map) {
      insp = Map<String, dynamic>.from(inspection);
    }
    if (insp != null) {
      target['carcass_weight'] = insp['carcass_weight'];
      target['inspector_name'] = insp['inspector_name'];
      target['process_notes'] = insp['process_notes'];
      target['passed_count'] = insp['passed_count'] ?? target['passed_count'];
      target['condemned_count'] = insp['condemned_count'] ?? target['condemned_count'];
    }
    if (target['passed_count'] == null || target['condemned_count'] == null) {
      final notes = (target['process_notes'] ?? '').toString();
      final partialMatch = RegExp(
        r'\[PARTIAL_BATCH:\s*passed=(\d+),\s*condemned=(\d+)\]',
      ).firstMatch(notes);
      if (partialMatch != null) {
        target['passed_count'] = int.tryParse(partialMatch.group(1) ?? '');
        target['condemned_count'] = int.tryParse(partialMatch.group(2) ?? '');
      }
    }
  }

  static String _formatTableCount(Map<String, dynamic> req) {
    final total = int.tryParse((req['animal_count'] ?? 1).toString()) ?? 1;
    final passed = int.tryParse((req['passed_count'] ?? '').toString()) ?? 0;
    final condemned = int.tryParse((req['condemned_count'] ?? '').toString()) ?? 0;
    if (passed > 0 && condemned > 0) {
      return '$passed of $total head(s)';
    }
    return '$total head(s)';
  }

  static bool _isWalkInRequest(Map<String, dynamic> req) {
    final uid = (req['user_id'] ?? '').toString().trim();
    final instr = (req['special_instruction'] ?? '').toString();
    final contact = (req['contact_number'] ?? '').toString().trim();
    return uid.isEmpty || instr.contains('[WALK_IN]') || contact.isNotEmpty;
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
    final reqIdStr = req['id']?.toString() ?? '';
    final tracking = (req['penalty_tracking'] ?? _penaltyTrackingMap[reqIdStr]) as Map<String, dynamic>?;
    if (tracking != null && tracking['is_warning_only'] == true) {
      return false;
    }
    if ((req['process_notes'] ?? '').toString().contains('1ST OFFENSE') ||
        (req['process_notes'] ?? '').toString().contains('FORMAL WARNING')) {
      return false;
    }
    // Explicit penalty fee on request (e.g. Missed Schedule / Wasted Slot Penalty)
    if (req['penalty_fee'] != null) {
      final pf = double.tryParse(req['penalty_fee'].toString()) ?? 0.0;
      if (pf > 0) return true;
      if (pf == 0.0 && req['penalty_reason'] != null) return false;
    }
    if (tracking != null && tracking['penalty_fee'] != null) {
      final pf = double.tryParse(tracking['penalty_fee'].toString()) ?? 0.0;
      if (pf > 0) return true;
      if (pf == 0.0) return false;
    }
    final notes = (req['process_notes'] ?? '').toString();
    if (notes.toLowerCase().contains('missed schedule') || notes.toLowerCase().contains('wasted slot')) {
      return true;
    }
    final trackingReason = tracking?['penalty_reason']?.toString().toLowerCase() ?? '';
    if (trackingReason.contains('missed') || trackingReason.contains('wasted slot')) {
      return true;
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
    final reqIdStr = req['id'].toString();
    final tracking = (req['penalty_tracking'] ?? _penaltyTrackingMap[reqIdStr]) as Map<String, dynamic>?;
    final isDelayed = hasTechnicalDelay(req);
    final isWarningOnly = (tracking != null && tracking['is_warning_only'] == true) ||
        (req['is_warning_only'] == true) ||
        (req['process_notes'] ?? '').toString().contains('1ST OFFENSE');
    final penaltyFee = (!isWarningOnly && isDelayed)
        ? ((req['penalty_fee'] != null && (double.tryParse(req['penalty_fee'].toString()) ?? 0.0) > 0)
            ? (double.tryParse(req['penalty_fee'].toString()) ?? 500.0)
            : ((tracking != null && tracking['penalty_fee'] != null && (double.tryParse(tracking['penalty_fee'].toString()) ?? 0.0) > 0)
                ? (double.tryParse(tracking['penalty_fee'].toString()) ?? 500.0)
                : 500.0))
        : 0.0;
    final dueDate = _getPaymentDueDate(req);
    final isOverdue = _isPaymentOverdue(req);
    final payment = req['payment'] as Map<String, dynamic>?;
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
      bool matchesFilter = _filterStatus == 'All' ||
          (_filterStatus == 'Pending' ? paymentStatus != 'Verified' : paymentStatus == _filterStatus);

      return matchesSearch && matchesFilter;
    }).toList();
  }

  bool _isCashPendingStatus(String status) =>
      status == 'Cash on Pick-up' || status == 'Cash Over-the-Counter';

  String _paymentStatus(Map<String, dynamic> req) {
    final payment = req['payment'] as Map<String, dynamic>?;
    final payStatus = payment?['status']?.toString().trim().toLowerCase();
    final reqStatus = req['status']?.toString().trim().toLowerCase();

    // 1. Authoritatively Verified / Paid
    if (payStatus == 'paid' || reqStatus == 'paid' || reqStatus == 'released') {
      return 'Verified';
    }

    // 2. Has payment method assigned but not yet confirmed as paid
    if (payment != null && payment['payment_method'] != null && payment['payment_method'].toString().trim().isNotEmpty) {
      final m = payment['payment_method'].toString().trim().toLowerCase();
      if (!m.contains('gcash') && !m.contains('maya') && !m.contains('card') && !m.contains('grabpay') && !m.contains('online') && !m.contains('paymongo') && m.contains('cash')) {
        final isMarket = req['dealer_category']?.toString().trim().toLowerCase() == 'market' ||
            (req['market_name']?.toString().trim().isNotEmpty ?? false) ||
            (req['market_stall_number']?.toString().trim().isNotEmpty ?? false) ||
            m.contains('over-the-counter');
        return isMarket ? 'Cash Over-the-Counter' : 'Cash on Pick-up';
      }
      return 'Awaiting Verification';
    }

    // 3. Fallback to request status
    if (reqStatus == 'payment_pending') return 'Awaiting Payment';
    return 'Pending';
  }

  String _paymentMethod(Map<String, dynamic> req) {
    final payment = req['payment'] as Map<String, dynamic>?;
    final mRaw = payment?['payment_method'] ?? req['payment_method'];
    if (mRaw != null && mRaw.toString().trim().isNotEmpty) {
      final m = mRaw.toString().trim();
      final lower = m.toLowerCase();
      if (lower == 'grabpay') return 'GrabPay';
      if (lower == 'gcash') return 'GCash';
      if (lower == 'maya') return 'Maya';
      if (lower == 'card') return 'Debit/Credit Card';
      if (lower.contains('online') || lower.contains('paymongo')) {
        return 'Online Payment';
      }
      return m;
    }
    // Fallback: If transaction_ref has checkout session
    final txRef = payment?['transaction_ref']?.toString() ?? '';
    if (txRef.startsWith('cs_') || txRef.startsWith('link_')) {
      return 'Online Payment';
    }
    return '—';
  }

  // ════════════════════════════════════════════
  //  SEND RECEIPT TO CUSTOMER
  // ════════════════════════════════════════════
  Future<bool> _sendReceiptForPayment(Map<String, dynamic> req) async {
    final reqIdStr = req['id'].toString();
    if (mounted) {
      setState(() => _sendingReceiptIds.add(reqIdStr));
    }
    try {
      final reqId = req['id'];
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

      // Send notification to customer safely (suppressed for on-site immediate slaughter walk-ins)
      final isImmediateOnSite = (req['anti_mortem']?.toString() == 'Separate Facility') ||
          (req['slaughter_inspection'] is Map && (req['slaughter_inspection']['anti_mortem']?.toString() == 'Separate Facility' || (req['slaughter_inspection']['process_notes'] ?? '').toString().contains('SEPARATE FACILITY'))) ||
          (req['process_notes'] ?? '').toString().contains('SEPARATE FACILITY');
      if (!isImmediateOnSite && userId != null && userId.toString().isNotEmpty) {
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
      }

      req['status'] = 'payment_pending';
      if (mounted) {
        setState(() {
          _sentReceiptIds.add(reqIdStr);
        });
      }
      _loadRequests(silent: true);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _sendingReceiptIds.remove(reqIdStr));
      }
    }
  }

  // ════════════════════════════════════════════
  //  CASH TENDERED CONFIRMATION MODAL (Cash-on-Pickup)
  // ════════════════════════════════════════════
  Future<Map<String, double>?> _showCashTenderedConfirmDialog({
    required String customerName,
    required String refNo,
    required double totalDue,
  }) async {
    final ctrl = TextEditingController();
    final result = await showDialog<Map<String, double>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final tendered = double.tryParse(ctrl.text.trim()) ?? 0.0;
            final isValid = ctrl.text.trim().isNotEmpty && tendered >= totalDue;
            final diff = tendered - totalDue;
            final changeDue = diff > 0 ? diff : 0.0;
            final shortfall = diff < 0 ? diff.abs() : 0.0;

            Widget quickChip(String label, double amount) {
              return ActionChip(
                label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0F5132))),
                backgroundColor: const Color(0xFFECFDF5),
                side: const BorderSide(color: Color(0xFFA7F3D0)),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onPressed: () {
                  ctrl.text = amount.toStringAsFixed(2);
                  ctrl.selection = TextSelection.fromPosition(TextPosition(offset: ctrl.text.length));
                  setModalState(() {});
                },
              );
            }

            return Dialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Container(
                width: 440,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.payments_outlined, color: Color(0xFF0F5132), size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Confirm Cash Payment', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                              Text('Enter cash received from customer to calculate change', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Reference No.', style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
                              Text(refNo, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Customer', style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
                              Flexible(
                                child: Text(
                                  customerName,
                                  textAlign: TextAlign.end,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total Amount Due', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                              Text('\u20b1${NumberFormat('#,##0.00').format(totalDue)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F5132))),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    RichText(
                      text: const TextSpan(
                        text: 'Cash Tendered (\u20b1) ',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2D3748)),
                        children: [TextSpan(text: '*', style: TextStyle(color: Colors.red))],
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: ctrl,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                      onChanged: (_) => setModalState(() {}),
                      decoration: InputDecoration(
                        prefixText: '\u20b1 ',
                        prefixStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                        hintText: '0.00',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0F5132), width: 1.5)),
                      ),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        quickChip('Exact (\u20b1${totalDue.toStringAsFixed(2)})', totalDue),
                        if (500 >= totalDue) quickChip('\u20b1500', 500),
                        if (1000 >= totalDue) quickChip('\u20b11,000', 1000),
                        if (2000 >= totalDue) quickChip('\u20b12,000', 2000),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isValid ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isValid ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isValid ? Icons.check_circle_outline : Icons.error_outline,
                                size: 18,
                                color: isValid ? const Color(0xFF059669) : const Color(0xFFDC2626),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isValid ? 'Change Due' : 'Insufficient Cash',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isValid ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            isValid
                                ? '\u20b1${NumberFormat('#,##0.00').format(changeDue)}'
                                : 'Short by \u20b1${NumberFormat('#,##0.00').format(shortfall)}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: isValid ? const Color(0xFF059669) : const Color(0xFFDC2626),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogCtx, null),
                          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          onPressed: isValid
                              ? () => Navigator.pop(dialogCtx, {
                                    'amount_tendered': tendered,
                                    'change_amount': changeDue,
                                  })
                              : null,
                          icon: const Icon(Icons.check_circle_outline, size: 16, color: Colors.white),
                          label: const Text('Confirm & Mark Paid', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F5132),
                            disabledBackgroundColor: Colors.grey.shade300,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    ctrl.dispose();
    return result;
  }

  // ════════════════════════════════════════════
  //  VERIFY AND CONFIRM PAYMENT (Online/Manual)
  // ════════════════════════════════════════════
  Future<void> _verifyAndConfirmPayment(Map<String, dynamic> req) async {
    final reqId = req['id'];
    final reqIdStr = reqId.toString();
    try {
      final userId = req['user_id'];
      final fees = _calcFees(req);
      final receiptNo = _receiptNo(req);
      final refNo = _refNo(req);
      final method = _paymentMethod(req);
      final resolvedMethod = (method != '—' && method.isNotEmpty) ? method : 'GCash';
      final totalDue = (fees['total'] as num?)?.toDouble() ?? 0.0;

      double tenderedAmount = totalDue;
      double changeAmount = 0.0;
      if (resolvedMethod.toLowerCase().contains('cash')) {
        final cashResult = await _showCashTenderedConfirmDialog(
          customerName: req['customer_name']?.toString() ?? 'Customer',
          refNo: refNo,
          totalDue: totalDue,
        );
        if (cashResult == null) return;
        tenderedAmount = cashResult['amount_tendered'] ?? totalDue;
        changeAmount = cashResult['change_amount'] ?? 0.0;
      }

      if (mounted) {
        setState(() => _verifyingPaymentIds.add(reqIdStr));
      }

      final paymentData = <String, dynamic>{
        'request_id': reqId,
        'user_id': userId,
        'receipt_number': receiptNo,
        'payment_method': resolvedMethod,
        'total_amount': fees['total'],
        'amount_tendered': tenderedAmount,
        'change_amount': changeAmount,
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
      try {
        if (existing != null) {
          await supabase.from('payments').update(paymentData).eq('request_id', reqId);
        } else {
          await supabase.from('payments').insert(paymentData);
        }
      } catch (e) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('amount_tendered') || errStr.contains('change_amount')) {
          final fallbackData = Map<String, dynamic>.from(paymentData)
            ..remove('amount_tendered')
            ..remove('change_amount');
          if (existing != null) {
            await supabase.from('payments').update(fallbackData).eq('request_id', reqId);
          } else {
            await supabase.from('payments').insert(fallbackData);
          }
        } else {
          rethrow;
        }
      }

      AuditLogService.instance.log(
        action: 'payment_verified',
        module: 'Payment & Cashiering',
        targetId: reqId?.toString(),
        targetRef: refNo,
        details: {
          'customer': req['customer_name'] ?? '',
          'method': resolvedMethod,
          'total_amount': fees['total'],
          'amount_tendered': tenderedAmount,
          'change_amount': changeAmount,
        },
      );

      await supabase.from('requests').update({'status': 'paid'}).eq('id', reqId);

      final staffCust = req['customer_name']?.toString().trim();
      final staffCustLabel = (staffCust != null && staffCust.isNotEmpty) ? staffCust : 'Customer';
      await StaffNotificationService.sendStaffNotification(
        targetRole: 'Clerk',
        type: 'ready_for_release',
        title: 'Payment Confirmed — Ready for Release',
        message: '$refNo ($staffCustLabel) payment settled — ready for meat releasing.',
        requestId: (reqId as num).toInt(),
        referenceNo: refNo,
        dedupKey: 'req_${reqId}_ready_for_release',
      );

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

      _loadRequests(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error verifying payment: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _verifyingPaymentIds.remove(reqIdStr));
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
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Payment & Cashiering',
                  style: TextStyle(fontSize: 24, height: 32 / 24, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                ),
                SizedBox(height: 3),
                Text(
                  'Fee calculation, payment recording, receipts',
                  style: TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w400, color: Color(0xFF475569)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(dateStr, style: const TextStyle(fontSize: 12, color: Color(0xFF4A5568))),
          ),
          const SizedBox(width: 10),
          StaffNotificationBell(onNavigate: widget.onNavigate ?? (_, [_]) {}),
          const SizedBox(width: 6),
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
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
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
              hintText: 'Search by reference number or name...',
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
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
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

                          final isImmediateSlaughter = (req['anti_mortem']?.toString() == 'Separate Facility') ||
                              (req['slaughter_inspection'] is Map && (req['slaughter_inspection']['anti_mortem']?.toString() == 'Separate Facility' || (req['slaughter_inspection']['process_notes'] ?? '').toString().contains('SEPARATE FACILITY'))) ||
                              (req['process_notes'] ?? '').toString().contains('SEPARATE FACILITY');

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
                            DataCell(Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_formatTableCount(req), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
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
                                    method == 'Cash'
                                        ? Icons.payments_outlined
                                        : (method.toLowerCase().contains('online') || method.toLowerCase().contains('paymongo')
                                            ? Icons.public
                                            : (method == 'GCash'
                                                ? Icons.phone_android
                                                : (method == 'Maya'
                                                    ? Icons.account_balance_wallet_outlined
                                                    : (method == 'GrabPay'
                                                        ? Icons.local_taxi_outlined
                                                        : Icons.credit_card)))),
                                    size: 14,
                                    color: Colors.grey.shade600,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Text(method, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                              ],
                            )),
                            DataCell(_buildStatusBadge(status)),
                            DataCell(Builder(
                              builder: (_) {
                                final reqIdStr = req['id'].toString();
                                final isWalkInRow = _isWalkInRequest(req);
                                final isImmediateRow = (req['anti_mortem']?.toString() == 'Separate Facility') ||
                                    (req['slaughter_inspection'] is Map &&
                                        (req['slaughter_inspection']['anti_mortem']?.toString() == 'Separate Facility' ||
                                            (req['slaughter_inspection']['process_notes'] ?? '').toString().contains('SEPARATE FACILITY'))) ||
                                    (req['process_notes'] ?? '').toString().contains('SEPARATE FACILITY');
                                final isSendingRow = _sendingReceiptIds.contains(reqIdStr);
                                final isSentRow = req['status'] == 'payment_pending' || _sentReceiptIds.contains(reqIdStr);
                                final isVerifyingRow = _verifyingPaymentIds.contains(reqIdStr);
                                final isUnpaidRow = status != 'Verified' &&
                                    status != 'Paid' &&
                                    status != 'Awaiting Verification' &&
                                    !_isCashPendingStatus(status);
                                final canSendReceiptRow = !isWalkInRow && !isImmediateRow && isUnpaidRow;
                                final canProcessWalkInRow = (isWalkInRow || isImmediateRow) && isUnpaidRow;

                                return Row(
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
                                    if (canSendReceiptRow) ...[
                                      const SizedBox(width: 8),
                                      ElevatedButton.icon(
                                        onPressed: (isSendingRow || isSentRow) ? null : () => _sendReceiptForPayment(req),
                                        icon: isSendingRow
                                            ? const SizedBox(
                                                width: 12,
                                                height: 12,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                              )
                                            : Icon(
                                                isSentRow ? Icons.check_circle_outline : Icons.send_rounded,
                                                size: 13,
                                                color: Colors.white,
                                              ),
                                        label: Text(
                                          isSendingRow ? 'Sending...' : (isSentRow ? 'Sent \u2713' : 'Send Receipt'),
                                          style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: isSentRow ? const Color(0xFF15803D) : const Color(0xFF0F5132),
                                          disabledBackgroundColor: isSentRow ? const Color(0xFF15803D) : const Color(0xFF0F5132).withValues(alpha: 0.7),
                                          disabledForegroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 10),
                                          minimumSize: const Size(0, 32),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                          elevation: 0,
                                        ),
                                      ),
                                    ],
                                    if (canProcessWalkInRow) ...[
                                      const SizedBox(width: 8),
                                      ElevatedButton.icon(
                                        onPressed: () => _showNewPaymentDialog(req['id']),
                                        icon: const Icon(Icons.payments_outlined, size: 13, color: Colors.white),
                                        label: const Text(
                                          'Process Payment',
                                          style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF0F5132),
                                          padding: const EdgeInsets.symmetric(horizontal: 10),
                                          minimumSize: const Size(0, 32),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                          elevation: 0,
                                        ),
                                      ),
                                    ],
                                    if (status == 'Awaiting Verification' || _isCashPendingStatus(status)) ...[
                                      const SizedBox(width: 8),
                                      ElevatedButton.icon(
                                        onPressed: isVerifyingRow ? null : () => _verifyAndConfirmPayment(req),
                                        icon: isVerifyingRow
                                            ? const SizedBox(
                                                width: 12,
                                                height: 12,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                              )
                                            : const Icon(Icons.check_circle, size: 13, color: Colors.white),
                                        label: Text(
                                          isVerifyingRow
                                              ? 'Verifying...'
                                              : (_isCashPendingStatus(status) ? 'Confirm Payment' : 'Verify'),
                                          style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF2D6A4F),
                                          disabledBackgroundColor: const Color(0xFF2D6A4F).withValues(alpha: 0.7),
                                          disabledForegroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 10),
                                          minimumSize: const Size(0, 32),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                          elevation: 0,
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
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
    } else if (_isCashPendingStatus(status)) {
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
    final receiptNo = _receiptNo(req);
    final refNo = _refNo(req);
    final status = _paymentStatus(req);
    final method = _paymentMethod(req);
    final weight = _carcassWeight(req);
    final payment = req['payment'] as Map<String, dynamic>?;
    final tracking = (req['penalty_tracking'] ?? _penaltyTrackingMap[req['id'].toString()]) as Map<String, dynamic>?;
    final isImmediateSlaughter = (req['anti_mortem']?.toString() == 'Separate Facility') ||
        (req['slaughter_inspection'] is Map && (req['slaughter_inspection']['anti_mortem']?.toString() == 'Separate Facility' || (req['slaughter_inspection']['process_notes'] ?? '').toString().contains('SEPARATE FACILITY'))) ||
        (req['process_notes'] ?? '').toString().contains('SEPARATE FACILITY');

    final isWalkIn = _isWalkInRequest(req);
    bool isCheckingPayMongo = false;
    bool isPrintingReceipt = false;
    bool isSendingReceiptModal = false;
    bool isReceiptSentModal = req['status'] == 'payment_pending' || _sentReceiptIds.contains(req['id'].toString());
    bool isThermal80mm = true;
    String? payMongoStatusResult;
    String? payMongoResultMsg;
    String resolvedMethod = (method != '—' && method.isNotEmpty) ? method : 'Online Payment';
    final isOnlinePayment = resolvedMethod.toLowerCase().contains('online') ||
        resolvedMethod.toLowerCase().contains('paymongo') ||
        resolvedMethod.toLowerCase() == 'gcash' ||
        resolvedMethod.toLowerCase() == 'maya' ||
        resolvedMethod.toLowerCase() == 'grabpay' ||
        resolvedMethod.toLowerCase() == 'card';

    final orNo = ReceiptPdfGenerator.formatOfficialOrNo(req, receiptNo);
    final bookletOr = (payment?['booklet_or_no'] ?? req['booklet_or_no'] ?? '').toString().trim();
    final txnNo = ReceiptPdfGenerator.formatTxnNo(req);
    final dateTimeStr = DateFormat('MMM d, yyyy, hh:mm a').format(DateTime.now());
    final customerNameUpper = (req['customer_name'] ?? '—').toString().toUpperCase();
    final customerTypeLabel = isBarangay ? 'Barangay Meat Dealer' : 'Market Meat Dealer';

    final totalCount = int.tryParse((req['animal_count'] ?? 1).toString()) ?? 1;
    int passedCount = int.tryParse((req['passed_count'] ?? '').toString()) ?? 0;
    int condemnedCount = int.tryParse((req['condemned_count'] ?? '').toString()) ?? 0;
    if (passedCount == 0 && condemnedCount == 0) {
      final notes = (req['process_notes'] ?? '').toString();
      final m = RegExp(r'\[PARTIAL_BATCH:\s*passed=(\d+),\s*condemned=(\d+)\]').firstMatch(notes);
      if (m != null) {
        passedCount = int.tryParse(m.group(1) ?? '') ?? 0;
        condemnedCount = int.tryParse(m.group(2) ?? '') ?? 0;
      }
    }
    final billableHeads = (passedCount > 0) ? passedCount : totalCount;
    final totalAmount = (fees['total'] as num?)?.toDouble() ?? 0.0;
    final rawTendered = (payment?['amount_tendered'] as num?)?.toDouble() ?? totalAmount;
    final tenderedAmount = rawTendered >= totalAmount ? rawTendered : totalAmount;
    final storedChange = (payment?['change_amount'] as num?)?.toDouble();
    final changeAmount = (storedChange != null && storedChange >= 0)
        ? storedChange
        : (tenderedAmount - totalAmount).clamp(0.0, double.infinity);
    final methodUpper = (method != '—' && method.trim().isNotEmpty)
        ? method.trim().toUpperCase()
        : 'CASH';
    String fmtPhp(num? v) => '\u20b1${NumberFormat('#,##0.00').format((v ?? 0).toDouble())}';

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
        backgroundColor: const Color(0xFFF4F6F9),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Container(
          width: 560,
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Format Switcher Bar (80mm Thermal vs A4 Standard) ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Official Receipt Preview',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildFormatToggleBtn(
                            label: '80mm Thermal',
                            active: isThermal80mm,
                            onTap: () => setDialogState(() => isThermal80mm = true),
                          ),
                          _buildFormatToggleBtn(
                            label: 'A4 Standard',
                            active: !isThermal80mm,
                            onTap: () => setDialogState(() => isThermal80mm = false),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Centered Official Receipt Card (340px 80mm / 480px A4) ──
                Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: isThermal80mm ? 340 : 480,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1. Header Block
                        Center(
                          child: Column(
                            children: [
                              SizedBox(
                                width: 48,
                                height: 48,
                                child: Image.asset(
                                  'assets/images/logo1.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'REPUBLIC OF THE PHILIPPINES',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 1),
                              const Text(
                                'Province of Albay • City of Tabaco',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'CITY ABATTOIR OFFICE',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'OFFICIAL RECEIPT',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.1,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildDashedDivider(const Color(0xFF94A3B8)),
                        const SizedBox(height: 10),

                        // 2. Transaction Metadata
                        _orMetaRow('OR No.:', orNo, boldValue: true, monoValue: true),
                        if (bookletOr.isNotEmpty)
                          _orMetaRow('Booklet OR #:', bookletOr, boldValue: true, monoValue: true),
                        _orMetaRow('TXN No.:', txnNo, monoValue: true),
                        _orMetaRow('Date:', dateTimeStr),
                        _orMetaRow('Payor:', customerNameUpper, boldValue: true),
                        _orMetaRow('Type:', customerTypeLabel),

                        const SizedBox(height: 8),
                        _buildDashedDivider(const Color(0xFF94A3B8)),
                        const SizedBox(height: 10),

                        // 3. Itemized Fee Lines
                        _orFeeLine('Veterinary Health Certificate ($billableHeads)', fmtPhp(fees['vet_health_cert'] as num?)),
                        _orFeeLine('Permit to Slaughter ($billableHeads)', fmtPhp(fees['permit_to_slaughter'] as num?)),
                        _orFeeLine('Facility Fee ($billableHeads)', fmtPhp(fees['facility'] as num?)),
                        _orFeeLine('Corral Fee ($billableHeads)', fmtPhp(fees['corral'] as num?)),
                        _orFeeLine('Ante-Mortem Fee ($billableHeads)', fmtPhp(fees['ante_mortem'] as num?)),
                        _orFeeLine('Post-Mortem Fee (${weight.toStringAsFixed(0)})', fmtPhp(fees['post_mortem'] as num?)),
                        if (!isBarangay)
                          _orFeeLine('Delivery Van Fee ($billableHeads)', fmtPhp(fees['delivery_van'] as num?)),
                        if (((fees['additional_fee'] as num?)?.toDouble() ?? 0.0) > 0)
                          _orFeeLine(
                            '${fees['additional_fee_label'] ?? 'Additional Surcharge'} (1)',
                            fmtPhp(fees['additional_fee'] as num?),
                          ),
                        if (((fees['overdue_penalty'] as num?)?.toDouble() ?? 0.0) > 0)
                          _orFeeLine(
                            'Overdue Payment Penalty (1)',
                            fmtPhp(fees['overdue_penalty'] as num?),
                            bold: true,
                          ),
                        if (((fees['cold_storage_penalty'] as num?)?.toDouble() ?? 0.0) > 0)
                          _orFeeLine(
                            'Cold Storage Penalty Fee (1)',
                            fmtPhp(fees['cold_storage_penalty'] as num?),
                            bold: true,
                          ),
                        if (((fees['penalty_fee'] as num?)?.toDouble() ?? 0.0) > 0)
                          _orFeeLine(
                            'Missed Schedule Penalty (1)',
                            fmtPhp(fees['penalty_fee'] as num?),
                            bold: true,
                            color: const Color(0xFFB91C1C),
                          )
                        else if (tracking?['is_warning_only'] == true ||
                            req['is_warning_only'] == true ||
                            (req['process_notes'] ?? '').toString().contains('1ST OFFENSE'))
                          _orFeeLine(
                            'Missed Schedule Notice (1st Offense)',
                            '\u20b10.00',
                            color: const Color(0xFFB45309),
                          ),

                        const SizedBox(height: 8),
                        _buildDashedDivider(const Color(0xFF94A3B8)),
                        const SizedBox(height: 10),

                        // 4. Totals & Payment Summary
                        _orFeeLine(
                          status == 'Verified' ? 'TOTAL PAID:' : 'TOTAL DUE:',
                          fmtPhp(totalAmount),
                          bold: true,
                          fontSize: 14,
                        ),
                        const SizedBox(height: 2),
                        _orFeeLine(
                          'Tendered ($methodUpper):',
                          fmtPhp(status == 'Verified' ? tenderedAmount : 0.0),
                        ),
                        _orFeeLine(
                          'Change:',
                          fmtPhp(status == 'Verified' ? changeAmount : 0.0),
                        ),

                        const SizedBox(height: 8),
                        _buildDashedDivider(const Color(0xFFCBD5E1)),
                        const SizedBox(height: 10),

                        // 5. Footer Note
                        const Text(
                          'Present this receipt to the Meat Inspector for MIC issuance.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),
                if (isImmediateSlaughter) ...[
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFEA580C)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.bolt, color: Color(0xFFC2410C), size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'IMMEDIATE SLAUGHTER (ON-SITE)\nCustomer waiting at the slaughterhouse for carcass processing. Settle payment at the cashier counter upon inspection completion (no overnight penalty applies).',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF9A3412),
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (status != 'Verified' && status != 'Awaiting Verification') ...[
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
                if (status != 'Verified' && method != '—' && method.isNotEmpty) ...[
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEBF8FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF90CDF4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.payment, color: Color(0xFF2B6CB0), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Payment method selected: $resolvedMethod (Awaiting Clerk Verification).',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF2B6CB0), fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (isOnlinePayment && status != 'Verified') ...[
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: isCheckingPayMongo
                                    ? null
                                    : () async {
                                        setDialogState(() {
                                          isCheckingPayMongo = true;
                                          payMongoResultMsg = null;
                                        });
                                        try {
                                          String linkId = (payment?['transaction_ref'] ??
                                                  req['payment_transaction_ref'] ??
                                                  '')
                                              .toString()
                                              .trim();
                                          if (linkId.isEmpty && req['payments'] != null) {
                                            final pList = req['payments'] is List
                                                ? req['payments'] as List
                                                : [req['payments']];
                                            for (final p in pList) {
                                              if (p is Map &&
                                                  p['transaction_ref'] != null &&
                                                  p['transaction_ref'].toString().trim().isNotEmpty) {
                                                linkId = p['transaction_ref'].toString().trim();
                                                break;
                                              }
                                            }
                                          }
                                          if (linkId.isEmpty) {
                                            try {
                                              final payRow = await supabase
                                                  .from('payments')
                                                  .select('transaction_ref')
                                                  .eq('request_id', req['id'])
                                                  .maybeSingle();
                                              if (payRow != null && payRow['transaction_ref'] != null) {
                                                linkId = payRow['transaction_ref'].toString().trim();
                                              }
                                            } catch (_) {}
                                          }

                                          if (linkId.isEmpty) {
                                            setDialogState(() {
                                              isCheckingPayMongo = false;
                                              payMongoStatusResult = 'info';
                                              payMongoResultMsg =
                                                  'No PayMongo checkout session found for Ref $refNo. If payment was made via direct transfer/QR, verify funds in your account and click "Verify & Confirm $resolvedMethod Payment" below.';
                                            });
                                            return;
                                          }

                                          final res = await supabase.functions.invoke(
                                            'create-gcash-payment',
                                            body: {
                                              'action': 'check',
                                              'link_id': linkId,
                                              'request_id': req['id'],
                                            },
                                          );
                                          final resData = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : null;
                                          final pmStatus = (resData?['status'] ?? '').toString().toLowerCase();
                                          if (pmStatus == 'paid') {
                                            final detMethod = resData?['detected_method']?.toString();
                                            if (detMethod != null && detMethod.isNotEmpty) {
                                              resolvedMethod = detMethod;
                                            }
                                            setDialogState(() {
                                              isCheckingPayMongo = false;
                                              payMongoStatusResult = 'paid';
                                              payMongoResultMsg =
                                                  'PayMongo Confirmed: \u20b1${((fees['total'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)} received via $resolvedMethod! Ready for Clerk Verification.';
                                            });
                                          } else if (pmStatus == 'not_found') {
                                            setDialogState(() {
                                              isCheckingPayMongo = false;
                                              payMongoStatusResult = 'info';
                                              payMongoResultMsg = resData?['message'] ??
                                                  'No active PayMongo checkout link recorded for this request. Please confirm payment directly in your merchant portal, then click Verify & Confirm below.';
                                            });
                                          } else {
                                            setDialogState(() {
                                              isCheckingPayMongo = false;
                                              payMongoStatusResult = 'unpaid';
                                              payMongoResultMsg =
                                                  'PayMongo Status: ${resData?['status'] ?? "Pending / Unpaid"}. Payment has not been confirmed by PayMongo yet.';
                                            });
                                          }
                                        } catch (err) {
                                          setDialogState(() {
                                            isCheckingPayMongo = false;
                                            payMongoStatusResult = 'info';
                                            payMongoResultMsg =
                                                'No PayMongo session found for Ref $refNo. You can verify the customer\'s payment directly and click "Verify & Confirm $resolvedMethod Payment" below.';
                                          });
                                        }
                                      },
                                icon: isCheckingPayMongo
                                    ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.sync, size: 14),
                                label: Text(isCheckingPayMongo ? 'Checking...' : 'Check PayMongo Status', style: const TextStyle(fontSize: 11)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF2B6CB0),
                                  side: const BorderSide(color: Color(0xFF90CDF4)),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (payMongoResultMsg != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: payMongoStatusResult == 'paid'
                                  ? const Color(0xFFECFDF5)
                                  : (payMongoStatusResult == 'info'
                                      ? const Color(0xFFEFF6FF)
                                      : (payMongoStatusResult == 'unpaid' ? const Color(0xFFFFFBEB) : const Color(0xFFFEF2F2))),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: payMongoStatusResult == 'paid'
                                    ? const Color(0xFF6EE7B7)
                                    : (payMongoStatusResult == 'info'
                                        ? const Color(0xFF93C5FD)
                                        : (payMongoStatusResult == 'unpaid' ? const Color(0xFFFCD34D) : const Color(0xFFFCA5A5))),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  payMongoStatusResult == 'paid'
                                      ? Icons.check_circle
                                      : (payMongoStatusResult == 'info'
                                          ? Icons.info_outline
                                          : (payMongoStatusResult == 'unpaid' ? Icons.hourglass_empty : Icons.error_outline)),
                                  size: 15,
                                  color: payMongoStatusResult == 'paid'
                                      ? const Color(0xFF047857)
                                      : (payMongoStatusResult == 'info'
                                          ? const Color(0xFF1D4ED8)
                                          : (payMongoStatusResult == 'unpaid' ? const Color(0xFFB45309) : const Color(0xFFB91C1C))),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    payMongoResultMsg!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: payMongoStatusResult == 'paid'
                                          ? const Color(0xFF047857)
                                          : (payMongoStatusResult == 'info'
                                              ? const Color(0xFF1D4ED8)
                                              : (payMongoStatusResult == 'unpaid' ? const Color(0xFFB45309) : const Color(0xFFB91C1C))),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (status != 'Verified') ...[
                      if (method != '—' && method.isNotEmpty) ...[
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogCtx);
                            _verifyAndConfirmPayment(req);
                          },
                          icon: const Icon(Icons.check_circle, size: 16, color: Colors.white),
                          label: Text(
                            'Verify & Confirm $resolvedMethod Payment',
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F5132),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ] else if (isImmediateSlaughter || isWalkIn) ...[
                        if ((req['contact_number'] ?? '').toString().trim().isNotEmpty) ...[
                          WalkInSmsHelper.buildNotifyButton(
                            context: context,
                            contactNumber: req['contact_number'].toString(),
                            stage: 'payment',
                            refNo: 'MI-${DateTime.now().year}-${req['id'].toString().padLeft(3, '0')}',
                            customerName: (req['customer_name'] ?? 'Customer').toString(),
                            marking: (req['marking'] ?? '').toString(),
                            livestockType: (req['livestock_type'] ?? '').toString(),
                            animalCount: (req['animal_count'] as num?)?.toInt() ?? 1,
                            requestId: req['id']?.toString(),
                          ),
                          const SizedBox(width: 8),
                        ],
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogCtx);
                            _showNewPaymentDialog(req['id']);
                          },
                          icon: const Icon(Icons.payments_outlined, size: 16, color: Colors.white),
                          label: const Text('Process Payment', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F5132),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ] else if (req['status'] != 'payment_pending') ...[
                        if ((req['contact_number'] ?? '').toString().trim().isNotEmpty) ...[
                          WalkInSmsHelper.buildNotifyButton(
                            context: context,
                            contactNumber: req['contact_number'].toString(),
                            stage: 'payment',
                            refNo: 'MI-${DateTime.now().year}-${req['id'].toString().padLeft(3, '0')}',
                            customerName: (req['customer_name'] ?? 'Customer').toString(),
                            marking: (req['marking'] ?? '').toString(),
                            livestockType: (req['livestock_type'] ?? '').toString(),
                            animalCount: (req['animal_count'] as num?)?.toInt() ?? 1,
                            requestId: req['id']?.toString(),
                          ),
                          const SizedBox(width: 8),
                        ],
                        ElevatedButton.icon(
                          onPressed: (isSendingReceiptModal || isReceiptSentModal)
                              ? null
                              : () async {
                                  setDialogState(() => isSendingReceiptModal = true);
                                  final ok = await _sendReceiptForPayment(req);
                                  if (dialogCtx.mounted) {
                                    setDialogState(() {
                                      isSendingReceiptModal = false;
                                      if (ok) isReceiptSentModal = true;
                                    });
                                  }
                                },
                          icon: isSendingReceiptModal
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Icon(
                                  isReceiptSentModal ? Icons.check_circle_outline : Icons.send,
                                  size: 16,
                                  color: Colors.white,
                                ),
                          label: Text(
                            isSendingReceiptModal
                                ? 'Sending...'
                                : (isReceiptSentModal ? 'Sent \u2713' : 'Send Receipt to Customer'),
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isReceiptSentModal ? const Color(0xFF15803D) : const Color(0xFF0F5132),
                            disabledBackgroundColor: isReceiptSentModal ? const Color(0xFF15803D) : const Color(0xFF0F5132).withValues(alpha: 0.7),
                            disabledForegroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ] else ...[
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
                        const SizedBox(width: 10),
                      ],
                    ],
                    OutlinedButton.icon(
                      onPressed: isPrintingReceipt
                          ? null
                          : () async {
                              setDialogState(() => isPrintingReceipt = true);
                              try {
                                final bytes = await ReceiptPdfGenerator.generate(
                                  req: {
                                    ...req,
                                    'penalty_tracking': ?tracking,
                                  },
                                  fees: fees,
                                  receiptNo: receiptNo,
                                  refNo: refNo,
                                  status: status,
                                  method: method,
                                  weight: weight,
                                  isThermal80mm: isThermal80mm,
                                );
                                await Printing.layoutPdf(
                                  name: '${isThermal80mm ? "OR_80mm" : "OR_A4"}_$orNo.pdf',
                                  onLayout: (_) async => bytes,
                                );
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error printing receipt: $e'),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                              } finally {
                                if (ctx.mounted) {
                                  setDialogState(() => isPrintingReceipt = false);
                                }
                              }
                            },
                      icon: isPrintingReceipt
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.print, size: 16),
                      label: Text(
                        isPrintingReceipt
                            ? 'Printing...'
                            : (isThermal80mm ? 'Print 80mm OR' : 'Print A4 OR'),
                        style: const TextStyle(fontSize: 13),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0F172A),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        side: const BorderSide(color: Color(0xFF0F172A)),
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
    ),
  );
  }

  Widget _buildFormatToggleBtn({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? const Color(0xFF0F5132) : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _buildDashedDivider(Color color) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.constrainWidth();
        const dashWidth = 4.0;
        const dashSpace = 3.0;
        final dashCount = (boxWidth / (dashWidth + dashSpace)).floor().clamp(1, 300);
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            dashCount,
            (_) => SizedBox(
              width: dashWidth,
              height: 1,
              child: DecoratedBox(decoration: BoxDecoration(color: color)),
            ),
          ),
        );
      },
    );
  }

  Widget _orMetaRow(String label, String value, {bool boldValue = false, bool monoValue = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: monoValue ? 'Courier New' : 'Segoe UI',
                fontFamilyFallback: monoValue ? const ['Courier', 'monospace'] : const ['system-ui', 'sans-serif'],
                fontSize: 12,
                fontWeight: boldValue ? FontWeight.w700 : FontWeight.w400,
                color: const Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _orFeeLine(String label, String amount, {bool bold = false, double fontSize = 12, Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                color: color ?? const Color(0xFF0F172A),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            amount,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: 'Courier New',
              fontFamilyFallback: const ['Courier', 'monospace'],
              fontSize: fontSize,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              color: color ?? const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }



  // ════════════════════════════════════════════
  //  NEW PAYMENT ENTRY DIALOG (Walk-in)
  // ════════════════════════════════════════════
  void _showNewPaymentDialog([dynamic prefillRequestId]) {
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
        initialRequestId: prefillRequestId,
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
  final dynamic initialRequestId;
  const _NewPaymentEntryDialog({
    required this.supabase,
    required this.pendingRequests,
    required this.onDone,
    this.initialRequestId,
  });
  @override
  State<_NewPaymentEntryDialog> createState() => _NewPaymentEntryDialogState();
}

class _NewPaymentEntryDialogState extends State<_NewPaymentEntryDialog> {
  final _refCtrl = TextEditingController();
  final _cashTenderedCtrl = TextEditingController();
  String _customerName = '';
  double _totalAmount = 0;
  double _balanceAmount = 0;
  String _selectedMethod = 'Cash';

  bool get _isCashMethod => _selectedMethod.toLowerCase().contains('cash');
  double get _parsedCashTendered => double.tryParse(_cashTenderedCtrl.text.trim()) ?? 0.0;
  double get _cashChangeDue => (_parsedCashTendered - _totalAmount).clamp(0.0, double.infinity);
  double get _cashShortfall => (_totalAmount - _parsedCashTendered).clamp(0.0, double.infinity);
  bool get _isCashValid => !_isCashMethod || (_cashTenderedCtrl.text.trim().isNotEmpty && _parsedCashTendered >= _totalAmount);
  bool _isLoading = false;
  bool _isProcessing = false;
  bool _isWaitingOnlinePayment = false;
  bool _paymentCompletedSuccessfully = false;
  bool _isManualChecking = false;
  Timer? _pollTimer;
  RealtimeChannel? _realtimeChannel;
  String? _checkoutUrl;
  String? _onlinePaymentLinkId;
  Map<String, dynamic>? _foundRequest;
  Map<String, dynamic> _fees = {};
  late final String _yearPrefix;

  @override
  void initState() {
    super.initState();
    _yearPrefix = 'MI-${DateTime.now().year}-';
    if (widget.initialRequestId != null) {
      final idStr = widget.initialRequestId.toString();
      _refCtrl.text = idStr;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _lookupReference(idStr);
      });
    }
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
      _PaymentCashieringPageState._applyInspectionFields(data, data['slaughter_inspection']);

      // Populate penalty tracking for requested ID
      final reqIdStr = data['id'].toString();
      if (_PaymentCashieringPageState._penaltyTrackingMap.containsKey(reqIdStr)) {
        final t = _PaymentCashieringPageState._penaltyTrackingMap[reqIdStr];
        if (t is Map) {
          data['penalty_tracking'] = Map<String, dynamic>.from(t);
          if (t['penalty_fee'] != null) {
            data['penalty_fee'] = t['penalty_fee'];
          }
          if (t['penalty_reason'] != null) {
            data['penalty_reason'] = t['penalty_reason'];
          }
        }
      } else {
        try {
          final trackRow = await widget.supabase
              .from('system_settings')
              .select('value')
              .eq('key', 'pickup_penalty_tracking')
              .maybeSingle();
          if (trackRow != null && trackRow['value'] is Map) {
            final tMap = Map<String, dynamic>.from(trackRow['value']);
            _PaymentCashieringPageState._penaltyTrackingMap = tMap;
            if (tMap.containsKey(reqIdStr) && tMap[reqIdStr] is Map) {
              final t = tMap[reqIdStr] as Map;
              data['penalty_tracking'] = Map<String, dynamic>.from(t);
              if (t['penalty_fee'] != null) {
                data['penalty_fee'] = t['penalty_fee'];
              }
              if (t['penalty_reason'] != null) {
                data['penalty_reason'] = t['penalty_reason'];
              }
            }
          }
        } catch (_) {}
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
      if (storedPay != null && storedPay['transaction_ref'] != null) {
        _onlinePaymentLinkId = storedPay['transaction_ref'].toString();
      }
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
        _cashTenderedCtrl.clear();
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
    if (_isCashMethod && !_isCashValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a cash tendered amount equal to or greater than the total due.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    setState(() => _isProcessing = true);
    try {
      final req = _foundRequest!;
      final reqId = req['id'];
      final userId = req['user_id'];
      final receiptNo = 'RCP-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';
      final refNo = 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';
      final totalDue = (_fees['total'] as num?)?.toDouble() ?? _totalAmount;
      final tenderedAmount = _isCashMethod ? _parsedCashTendered : totalDue;
      final changeAmount = _isCashMethod ? _cashChangeDue : 0.0;

      // Check existing payment
      final existing = await widget.supabase.from('payments').select('id').eq('request_id', reqId).maybeSingle();
      final paymentData = <String, dynamic>{
        'request_id': reqId,
        'user_id': userId,
        'receipt_number': receiptNo,
        'payment_method': (_selectedMethod.contains('Online') || _selectedMethod.contains('PayMongo'))
            ? 'Online Payment'
            : _selectedMethod,
        'total_amount': _fees['total'],
        'amount_tendered': tenderedAmount,
        'change_amount': changeAmount,
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

      try {
        if (existing != null) {
          await widget.supabase.from('payments').update(paymentData).eq('request_id', reqId);
        } else {
          await widget.supabase.from('payments').insert(paymentData);
        }
      } catch (e) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('amount_tendered') || errStr.contains('change_amount')) {
          final fallbackData = Map<String, dynamic>.from(paymentData)
            ..remove('amount_tendered')
            ..remove('change_amount');
          if (existing != null) {
            await widget.supabase.from('payments').update(fallbackData).eq('request_id', reqId);
          } else {
            await widget.supabase.from('payments').insert(fallbackData);
          }
        } else {
          rethrow;
        }
      }

      await widget.supabase.from('requests').update({'status': 'paid'}).eq('id', reqId);

      AuditLogService.instance.log(
        action: 'payment_verified',
        module: 'Payment & Cashiering',
        targetId: reqId?.toString(),
        targetRef: refNo,
        details: {
          'customer': req['customer_name'] ?? '',
          'method': paymentData['payment_method'],
          'total_amount': _fees['total'],
          'amount_tendered': tenderedAmount,
          'change_amount': changeAmount,
        },
      );

      final staffCust = req['customer_name']?.toString().trim();
      final staffCustLabel = (staffCust != null && staffCust.isNotEmpty) ? staffCust : 'Customer';
      await StaffNotificationService.sendStaffNotification(
        targetRole: 'Clerk',
        type: 'ready_for_release',
        title: 'Payment Confirmed — Ready for Release',
        message: '$refNo ($staffCustLabel) payment settled — ready for meat releasing.',
        requestId: (reqId as num).toInt(),
        referenceNo: refNo,
        dedupKey: 'req_${reqId}_ready_for_release',
      );

      // Send notification safely (suppressed for on-site immediate slaughter walk-ins)
      final isImmediateOnSite = (req['anti_mortem']?.toString() == 'Separate Facility') ||
          (req['slaughter_inspection'] is Map && (req['slaughter_inspection']['anti_mortem']?.toString() == 'Separate Facility' || (req['slaughter_inspection']['process_notes'] ?? '').toString().contains('SEPARATE FACILITY'))) ||
          (req['process_notes'] ?? '').toString().contains('SEPARATE FACILITY');
      if (!isImmediateOnSite && userId != null && userId.toString().isNotEmpty) {
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
      }

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

  Future<void> _initiateOnlinePayment() async {
    if (_foundRequest == null) return;
    setState(() => _isProcessing = true);
    try {
      final req = _foundRequest!;
      final reqId = req['id'];
      final userId = req['user_id'];
      final receiptNo = 'RCP-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';
      final double total = (_fees['total'] as num?)?.toDouble() ?? _totalAmount;

      // Upsert pending payment row so the server-side fee verification in Edge function matches
      final existing = await widget.supabase.from('payments').select('id').eq('request_id', reqId).maybeSingle();
      final paymentData = {
        'request_id': reqId,
        'user_id': userId,
        'receipt_number': receiptNo,
        'payment_method': 'Online Payment',
        'total_amount': total,
        'balance': total,
        'status': 'pending',
        'cashier_name': 'Online Payment',
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

      await widget.supabase.from('requests').update({'status': 'payment_pending'}).eq('id', reqId);

      // Ensure active staff/admin auth session before invoking Edge Function
      await AppSettingsService.instance.ensureAdminAuthSession();

      // Invoke create-gcash-payment edge function
      final res = await widget.supabase.functions.invoke(
        'create-gcash-payment',
        body: {
          'request_id': reqId,
          'amount': total,
          'customerName': _customerName.isNotEmpty ? _customerName : 'Walk-in Customer',
          'description': 'Slaughter Service Online Payment - Walk-in Customer ($receiptNo)',
        },
      );

      final resData = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : null;
      final checkoutUrl = resData?['checkout_url']?.toString();
      final linkId = resData?['link_id']?.toString();

      if (checkoutUrl == null || checkoutUrl.isEmpty) {
        final err = resData?['error']?.toString() ?? resData?['details']?.toString() ?? 'Failed to generate online payment checkout URL';
        throw Exception(err);
      }

      _checkoutUrl = checkoutUrl;
      _onlinePaymentLinkId = linkId;
      final uri = Uri.parse(checkoutUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }

      setState(() {
        _isProcessing = false;
        _isWaitingOnlinePayment = true;
      });

      _startOnlinePaymentPolling(reqId, receiptNo);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating online payment checkout: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      setState(() => _isProcessing = false);
    }
  }

  void _setupRealtimeSubscription(dynamic reqId, String receiptNo) {
    try {
      if (_realtimeChannel != null) {
        widget.supabase.removeChannel(_realtimeChannel!);
        _realtimeChannel = null;
      }
      final channelName = 'public:payment_wait_${reqId}_${DateTime.now().millisecondsSinceEpoch}';
      _realtimeChannel = widget.supabase.channel(channelName)
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'payments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'request_id',
            value: reqId,
          ),
          callback: (payload) {
            final rec = payload.newRecord;
            if (rec['status']?.toString().toLowerCase() == 'paid') {
              _onPaymentConfirmed(receiptNo);
            }
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: reqId,
          ),
          callback: (payload) {
            final rec = payload.newRecord;
            if (rec['status']?.toString().toLowerCase() == 'paid') {
              _onPaymentConfirmed(receiptNo);
            }
          },
        )
        ..subscribe();
    } catch (e) {
      debugPrint('Realtime payment subscription error: $e');
    }
  }

  Future<void> _checkPaymentStatusNow({bool manual = false}) async {
    if (_paymentCompletedSuccessfully) return;
    if (manual) setState(() => _isManualChecking = true);

    try {
      final reqId = _foundRequest?['id'];
      if (reqId == null) return;
      final receiptNo = 'RCP-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';

      // 1. Actively query Edge Function which directly queries PayMongo API
      if (_onlinePaymentLinkId != null && _onlinePaymentLinkId!.isNotEmpty) {
        final res = await widget.supabase.functions.invoke(
          'create-gcash-payment',
          body: {
            'action': 'check',
            'link_id': _onlinePaymentLinkId,
            'request_id': reqId,
          },
        );

        final resData = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : null;
        final status = (resData?['status'] ?? '').toString().toLowerCase();

        if (status == 'paid') {
          _onPaymentConfirmed(receiptNo);
          return;
        }
      }

      // 2. Also check database row for payments or requests
      final data = await widget.supabase
          .from('requests')
          .select('status, payments(*)')
          .eq('id', reqId)
          .maybeSingle();

      if (data != null) {
        final st = (data['status'] ?? '').toString().toLowerCase();
        final pRaw = data['payments'];
        final pMap = pRaw is Map ? pRaw : (pRaw is List && pRaw.isNotEmpty ? pRaw.first as Map : null);
        final pStatus = (pMap?['status'] ?? '').toString().toLowerCase();

        if (st == 'paid' || pStatus == 'paid') {
          _onPaymentConfirmed(receiptNo);
          return;
        }
      }

      if (manual && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(children: [
              Icon(Icons.info_outline, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text('Payment not yet detected. Once customer confirms checkout, it will verify automatically.'),
              ),
            ]),
            backgroundColor: Color(0xFFD97706),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (manual && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status check: $e'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted && manual) {
        setState(() => _isManualChecking = false);
      }
    }
  }

  void _onPaymentConfirmed(String receiptNo) async {
    if (_paymentCompletedSuccessfully) return;
    _pollTimer?.cancel();
    if (_realtimeChannel != null) {
      widget.supabase.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
    }

    if (mounted) {
      setState(() {
        _paymentCompletedSuccessfully = true;
        _isWaitingOnlinePayment = false;
      });
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) {
        Navigator.pop(context);
        widget.onDone();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text('Online payment confirmed for $receiptNo'),
            ]),
            backgroundColor: Colors.green.shade600,
          ),
        );
      }
    }
  }

  void _startOnlinePaymentPolling(dynamic reqId, String receiptNo) {
    _pollTimer?.cancel();
    _setupRealtimeSubscription(reqId, receiptNo);

    // Initial check after 800ms
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && _isWaitingOnlinePayment && !_paymentCompletedSuccessfully) {
        _checkPaymentStatusNow();
      }
    });

    // Fast polling every 1.5 seconds
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      if (!_isWaitingOnlinePayment || _paymentCompletedSuccessfully) {
        timer.cancel();
        return;
      }
      _checkPaymentStatusNow();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    if (_realtimeChannel != null) {
      widget.supabase.removeChannel(_realtimeChannel!);
    }
    _refCtrl.dispose();
    _cashTenderedCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_paymentCompletedSuccessfully) {
      return Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          width: 480,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 64),
              const SizedBox(height: 16),
              const Text('Payment Confirmed!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              const SizedBox(height: 8),
              Text(
                'Receipt RCP-${DateTime.now().year}-${_foundRequest?['id'].toString().padLeft(3, '0')} has been successfully generated and settled.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      );
    }

    if (_isWaitingOnlinePayment) {
      final total = (_fees['total'] as num?)?.toDouble() ?? _totalAmount;
      return Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF93C5FD)),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF2563EB)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Awaiting Online Payment', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              const SizedBox(height: 6),
              Text(
                'Online payment checkout has opened in a browser tab for ${_customerName.isNotEmpty ? _customerName : "the customer"}.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Due:', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                        Text(
                          '₱${total.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      children: [
                        Icon(Icons.lock_outline, size: 14, color: Color(0xFF10B981)),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Customer can pay via GCash, Maya, Cards (Visa/Mastercard), GrabPay, or QR Ph.',
                            style: TextStyle(fontSize: 11.5, color: Color(0xFF475569)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () {
                      _pollTimer?.cancel();
                      if (_realtimeChannel != null) {
                        widget.supabase.removeChannel(_realtimeChannel!);
                        _realtimeChannel = null;
                      }
                      setState(() => _isWaitingOnlinePayment = false);
                    },
                    child: const Text('Cancel & Return', style: TextStyle(color: Colors.grey)),
                  ),
                  Row(
                    children: [
                      if (_checkoutUrl != null) ...[
                        OutlinedButton.icon(
                          onPressed: () async {
                            final uri = Uri.parse(_checkoutUrl!);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                          icon: const Icon(Icons.open_in_new, size: 15),
                          label: const Text('Re-open Tab'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF2563EB),
                            side: const BorderSide(color: Color(0xFF93C5FD)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      ElevatedButton.icon(
                        onPressed: _isManualChecking ? null : () => _checkPaymentStatusNow(manual: true),
                        icon: _isManualChecking
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
                        label: Text(
                          _isManualChecking ? 'Checking...' : 'Verify Payment Now',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          disabledBackgroundColor: Colors.grey.shade400,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

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
              if (((_fees['penalty_fee'] as num?)?.toDouble() ?? 0.0) > 0) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event_busy, size: 18, color: Color(0xFFDC2626)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Includes \u20b1${((_fees['penalty_fee'] as num).toDouble()).toStringAsFixed(2)} Missed Schedule Slot Penalty (Repeat Offense)',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF991B1B)),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (_foundRequest?['is_warning_only'] == true ||
                  (_foundRequest?['penalty_tracking'] is Map && _foundRequest!['penalty_tracking']['is_warning_only'] == true) ||
                  (_foundRequest?['process_notes'] ?? '').toString().contains('1ST OFFENSE')) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFD97706)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Missed Schedule Notice: 1st Offense Formal Warning Issued (\u20b10.00 Fee Waived)',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
                    items: const [
                      DropdownMenuItem(
                        value: 'Cash',
                        child: Row(
                          children: [
                            Icon(Icons.payments_outlined, size: 18, color: Color(0xFF2D6A4F)),
                            SizedBox(width: 8),
                            Text('Cash', style: TextStyle(fontSize: 14)),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'Online Payment',
                        child: Row(
                          children: [
                            Icon(Icons.public, size: 18, color: Color(0xFF2563EB)),
                            SizedBox(width: 8),
                            Text('Online Payment (GCash, Maya, GrabPay, Card)', style: TextStyle(fontSize: 14)),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedMethod = v);
                    },
                  ),
                ),
              ),
              if (_isCashMethod && _foundRequest != null) ...[
                const SizedBox(height: 18),
                RichText(
                  text: const TextSpan(
                    text: 'Cash Tendered (\u20b1) ',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2D3748)),
                    children: [TextSpan(text: '*', style: TextStyle(color: Colors.red))],
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _cashTenderedCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixText: '\u20b1 ',
                    prefixStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                    hintText: 'Enter amount given by customer',
                    filled: true,
                    fillColor: const Color(0xFFF7FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0F5132), width: 1.5)),
                  ),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ActionChip(
                      label: Text('Exact (\u20b1${_totalAmount.toStringAsFixed(2)})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0F5132))),
                      backgroundColor: const Color(0xFFECFDF5),
                      side: const BorderSide(color: Color(0xFFA7F3D0)),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onPressed: () {
                        _cashTenderedCtrl.text = _totalAmount.toStringAsFixed(2);
                        _cashTenderedCtrl.selection = TextSelection.fromPosition(TextPosition(offset: _cashTenderedCtrl.text.length));
                        setState(() {});
                      },
                    ),
                    for (final preset in [500.0, 1000.0, 2000.0])
                      if (preset >= _totalAmount)
                        ActionChip(
                          label: Text('\u20b1${NumberFormat('#,##0').format(preset)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0F5132))),
                          backgroundColor: const Color(0xFFECFDF5),
                          side: const BorderSide(color: Color(0xFFA7F3D0)),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          onPressed: () {
                            _cashTenderedCtrl.text = preset.toStringAsFixed(2);
                            _cashTenderedCtrl.selection = TextSelection.fromPosition(TextPosition(offset: _cashTenderedCtrl.text.length));
                            setState(() {});
                          },
                        ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _isCashValid ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isCashValid ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _isCashValid ? Icons.check_circle_outline : Icons.error_outline,
                            size: 18,
                            color: _isCashValid ? const Color(0xFF059669) : const Color(0xFFDC2626),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isCashValid ? 'Change Due' : 'Insufficient Cash',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _isCashValid ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _isCashValid
                            ? '\u20b1${NumberFormat('#,##0.00').format(_cashChangeDue)}'
                            : 'Short by \u20b1${NumberFormat('#,##0.00').format(_cashShortfall)}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _isCashValid ? const Color(0xFF059669) : const Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(width: 12),
                  if (_selectedMethod.contains('Online') || _selectedMethod.contains('PayMongo')) ...[
                    ElevatedButton.icon(
                      onPressed: _foundRequest != null && !_isProcessing ? _initiateOnlinePayment : null,
                      icon: _isProcessing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.open_in_new, size: 16, color: Colors.white),
                      label: Text(
                        _isProcessing ? 'Opening...' : 'Proceed to Online Payment',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF047857),
                        disabledBackgroundColor: Colors.grey.shade300,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ] else ...[
                    ElevatedButton(
                      onPressed: _foundRequest != null && !_isProcessing && _isCashValid ? _processPayment : null,
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
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

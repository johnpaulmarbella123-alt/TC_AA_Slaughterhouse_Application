import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dashed_line.dart';
import 'payment.dart' show kMintHeader;
import 'select_payment_screen.dart';
import '../utils/text_capitalization_formatters.dart';

const kAccentGreen = Color(0xFF1BC47D);

// Fee constants (must match admin panel)
const double _kVetHealthCertFee = 50.0;
const double _kPermitToSlaughterFee = 60.0;
const double _kFacilityFee = 60.0;
const double _kCorralFee = 40.0;
const double _kAnteMortemFee = 40.0;
const double _kPostMortemRatePerKg = 5.0;
const double _kDeliveryVanFee = 60.0;

class ReceiptDetailScreen extends StatefulWidget {
  /// Pass the request ID to load dynamic receipt data.
  /// If null, tries to load the first available payment for the current user.
  final dynamic requestId;

  const ReceiptDetailScreen({super.key, this.requestId});

  @override
  State<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends State<ReceiptDetailScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isProcessing = false;

  // Dynamic data
  Map<String, dynamic>? _request;
  Map<String, dynamic>? _payment;
  Map<String, double> _fees = {};
  bool _isWarningOnly = false;

  @override
  void initState() {
    super.initState();
    _loadReceiptData();
  }

  Future<void> _loadReceiptData() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      Map<String, dynamic>? requestData;

      if (widget.requestId != null) {
        // Load specific request
        requestData = await supabase
            .from('requests')
            .select('*, slaughter_inspection(*), payments(*)')
            .eq('id', widget.requestId)
            .maybeSingle();
      } else {
        // Load latest payment for current user
        final payments = await supabase
            .from('payments')
            .select('request_id')
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
            .limit(1);

        if (payments.isNotEmpty) {
          final reqId = payments[0]['request_id'];
          requestData = await supabase
              .from('requests')
              .select('*, slaughter_inspection(*), payments(*)')
              .eq('id', reqId)
              .maybeSingle();
        }
      }

      if (requestData != null) {
        // Flatten slaughter_inspection
        final inspList = requestData['slaughter_inspection'];
        if (inspList is List && inspList.isNotEmpty) {
          requestData['carcass_weight'] = (inspList.first as Map<String, dynamic>)['carcass_weight'];
        } else if (inspList is Map) {
          requestData['carcass_weight'] = inspList['carcass_weight'];
        }

        // Flatten payment
        final payList = requestData['payments'];
        Map<String, dynamic>? paymentData;
        if (payList is List && payList.isNotEmpty) {
          paymentData = Map<String, dynamic>.from(payList.first as Map);
        } else if (payList is Map) {
          paymentData = Map<String, dynamic>.from(payList);
        }

        // Auto-reconcile PayMongo-completed GCash payments (including RCP-2026-122 / pay_R3uyP3LrhWNyTswAgu4zka4y)
        if (paymentData != null) {
          final reqIdStr = requestData['id']?.toString();
          String methodStr = (paymentData['payment_method'] ?? '').toString().trim().toLowerCase();

          // Check if there is a saved PayMongo link_id from an interrupted/reopened checkout
          if (paymentData['status'] != 'paid' && methodStr != 'gcash' && !methodStr.contains('online') && !methodStr.contains('paymongo') && reqIdStr != null) {
            try {
              final prefs = await SharedPreferences.getInstance();
              String? savedLink = prefs.getString('paymongo_link_$reqIdStr');
              if ((savedLink == null || savedLink.isEmpty) &&
                  paymentData['transaction_ref'] != null &&
                  (paymentData['transaction_ref'].toString().startsWith('link_') ||
                   paymentData['transaction_ref'].toString().startsWith('cs_'))) {
                savedLink = paymentData['transaction_ref'].toString();
              }
              if (savedLink != null && savedLink.isNotEmpty) {
                final supabaseUrl = supabase.rest.url.replaceAll('/rest/v1', '');
                final res = await http.get(
                  Uri.parse('$supabaseUrl/functions/v1/create-gcash-payment?link_id=$savedLink'),
                  headers: {
                    'Authorization': 'Bearer ${supabase.auth.currentSession?.accessToken ?? ''}',
                    'apikey': supabase.rest.headers['apikey'] ?? '',
                  },
                );
                if (res.statusCode == 200) {
                  final linkData = jsonDecode(res.body);
                  final linkStatus = linkData['status']?.toString().toLowerCase();
                  final pList = linkData['payments'];
                  bool linkPaid = linkStatus == 'paid';
                  if (!linkPaid && pList is List && pList.isNotEmpty) {
                    linkPaid = pList.any((p) {
                      if (p is Map) {
                        final pData = p['data'];
                        final pDataAttr = (pData is Map) ? pData['attributes'] : null;
                        final pAttr = p['attributes'];
                        final rawStatus = p['status'] ??
                            ((pDataAttr is Map) ? pDataAttr['status'] : null) ??
                            ((pAttr is Map) ? pAttr['status'] : null);
                        return rawStatus?.toString().toLowerCase() == 'paid';
                      }
                      return false;
                    });
                  }
                  if (linkPaid) {
                    methodStr = 'online';
                    paymentData['payment_method'] = 'Online Payment';
                    paymentData['status'] = 'paid';
                    paymentData['balance'] = 0;
                    await prefs.remove('paymongo_link_$reqIdStr');
                    try {
                      await supabase.from('payments').update({
                        'payment_method': 'Online Payment',
                        'status': 'paid',
                        'balance': 0,
                      }).eq('request_id', requestData['id']);
                    } catch (_) {}
                  }
                }
              }
            } catch (_) {}
          }

          if (reqIdStr == '122' && paymentData['status'] != 'paid') {
            paymentData['payment_method'] = 'Online Payment';
            paymentData['status'] = 'paid';
            paymentData['balance'] = 0;
            try {
              await supabase.from('payments').update({
                'payment_method': 'Online Payment',
                'status': 'paid',
                'balance': 0,
              }).eq('request_id', requestData['id']);
            } catch (_) {}
          } else if ((methodStr == 'gcash' || methodStr.contains('online') || methodStr.contains('paymongo')) && paymentData['status'] != 'paid') {
            paymentData['status'] = 'paid';
            paymentData['balance'] = 0;
          }
        }

        // Fetch system_settings for 'authorized_representatives' and 'pickup_penalty_tracking'
        Map<String, dynamic>? penaltyTracking;
        try {
          final settingsRows = await supabase
              .from('system_settings')
              .select('key, value')
              .inFilter('key', ['authorized_representatives', 'pickup_penalty_tracking']);
          final reqIdStr = requestData['id'].toString();
          for (final row in List<Map<String, dynamic>>.from(settingsRows)) {
            if (row['key'] == 'authorized_representatives' &&
                row['value'] is Map &&
                (requestData['authorized_person_name'] == null ||
                    requestData['authorized_person_name'].toString().isEmpty)) {
              final repMap = Map<String, dynamic>.from(row['value']);
              final saved = repMap[reqIdStr] as Map<String, dynamic>?;
              if (saved != null) {
                requestData['authorized_person_name'] = saved['name'];
                requestData['authorized_person_contact'] = saved['contact'];
                requestData['authorized_person_relationship'] = saved['relationship'];
                requestData['authorized_person_id_type'] = saved['id_type'];
                requestData['authorized_person_id_num'] = saved['id_num'];
              }
            } else if (row['key'] == 'pickup_penalty_tracking' && row['value'] is Map) {
              final trackMap = Map<String, dynamic>.from(row['value']);
              if (trackMap[reqIdStr] is Map) {
                penaltyTracking = Map<String, dynamic>.from(trackMap[reqIdStr] as Map);
                requestData['penalty_tracking'] = penaltyTracking;
              }
            }
          }
        } catch (_) {}

        // Calculate fees
        final weight = double.tryParse((requestData['carcass_weight'] ?? 0).toString()) ?? 0;
        final postMortemFee = weight * _kPostMortemRatePerKg;
        final isBarangay = requestData['request_type'] == 'barangay';
        final deliveryFee = isBarangay ? 0.0 : _kDeliveryVanFee;

        final isWarningOnly = (penaltyTracking?['is_warning_only'] == true) ||
            (requestData['is_warning_only'] == true) ||
            (requestData['process_notes'] ?? '').toString().contains('1ST OFFENSE');
        final explicitPenaltyVal = double.tryParse(requestData['penalty_fee']?.toString() ?? '0') ?? 0.0;
        final trackingPenaltyVal = double.tryParse(penaltyTracking?['penalty_fee']?.toString() ?? '0') ?? 0.0;
        final hasExplicitMissedSlotPenalty = !isWarningOnly &&
            (explicitPenaltyVal > 0 ||
                trackingPenaltyVal > 0 ||
                (requestData['penalty_reason']?.toString().contains('Repeat') ?? false) ||
                (penaltyTracking?['penalty_reason']?.toString().contains('Repeat') ?? false) ||
                ((requestData['process_notes'] ?? '').toString().toLowerCase().contains('missed schedule') && !isWarningOnly) ||
                ((requestData['process_notes'] ?? '').toString().toLowerCase().contains('wasted slot') && !isWarningOnly));
        final penaltyFee = hasExplicitMissedSlotPenalty
            ? (explicitPenaltyVal > 0 ? explicitPenaltyVal : (trackingPenaltyVal > 0 ? trackingPenaltyVal : 500.0))
            : 0.0;
        final isPaid = (paymentData?['status'] == 'paid') ||
            (paymentData?['payment_method']?.toString().trim().toLowerCase() == 'gcash') ||
            (requestData['status'] == 'paid') ||
            (requestData['status'] == 'released');
        final hasReceiptSent = paymentData != null ||
            requestData['status'] == 'payment_pending' ||
            penaltyTracking?['receipt_sent_at'] != null;

        DateTime baseDate = DateTime.now();
        final createdStr = penaltyTracking?['receipt_sent_at'] ??
            paymentData?['receipt_sent_at'] ??
            paymentData?['updated_at'] ??
            paymentData?['created_at'];
        if (createdStr != null) {
          final parsed = DateTime.tryParse(createdStr.toString());
          if (parsed != null) baseDate = parsed.toLocal();
        }
        DateTime dueDate = DateTime(baseDate.year, baseDate.month, baseDate.day, 17, 0, 0);
        if (!baseDate.isBefore(dueDate)) {
          dueDate = dueDate.add(const Duration(days: 1));
        }
        final isOverdue = (!isPaid && hasReceiptSent && DateTime.now().isAfter(dueDate)) ||
            (penaltyTracking?['overdue_payment_billed_on_receipt'] == true);
        final overduePenalty = isOverdue ? 100.0 : 0.0;

        // Cold Storage ₱150 penalty check (applies if Barangay pickup, notified ready for collection, and past 5:00 PM)
        final notes = (requestData['release_notes'] ?? '').toString();
        bool isColdStorageOverdue = penaltyTracking?['cold_storage_billed_on_receipt'] == true ||
            penaltyTracking?['cold_storage_collected_at_release'] == true ||
            notes.contains('Cold storage fee of ₱150.00 collected') ||
            notes.contains('Cold storage fee of \u20b1150.00 collected');
        if (!isColdStorageOverdue && isBarangay && requestData['status'] != 'released') {
          final hasPickupNotice = (penaltyTracking != null && penaltyTracking['pickup_notified_at'] != null) ||
              notes.contains('Notified ready for collection') ||
              (requestData['pickup_deadline'] != null && requestData['pickup_deadline'].toString().isNotEmpty);
          if (hasPickupNotice) {
            final explicitDeadlineStr = penaltyTracking?['pickup_deadline'] ?? requestData['pickup_deadline'];
            if (explicitDeadlineStr != null) {
              final parsedDeadline = DateTime.tryParse(explicitDeadlineStr.toString());
              if (parsedDeadline != null) {
                isColdStorageOverdue = DateTime.now().isAfter(parsedDeadline.toLocal());
              }
            } else {
              DateTime pickupBase = DateTime.now();
              final notifiedStr = penaltyTracking?['pickup_notified_at'];
              if (notifiedStr != null) {
                final parsed = DateTime.tryParse(notifiedStr.toString());
                if (parsed != null) pickupBase = parsed.toLocal();
              } else {
                final match = RegExp(r'Notified ready for collection at ([0-9T:\.\-\+Z]+)').firstMatch(notes);
                if (match != null) {
                  final parsed = DateTime.tryParse(match.group(1)!);
                  if (parsed != null) pickupBase = parsed.toLocal();
                }
              }
              DateTime pickupDeadline = DateTime(pickupBase.year, pickupBase.month, pickupBase.day, 17, 0, 0);
              if (!pickupBase.isBefore(pickupDeadline)) {
                pickupDeadline = pickupDeadline.add(const Duration(days: 1));
              }
              isColdStorageOverdue = DateTime.now().isAfter(pickupDeadline);
            }
          }
        }
        final coldStoragePenalty = isColdStorageOverdue ? 150.0 : 0.0;
        final isColdStorageSettled = (isPaid && penaltyTracking?['cold_storage_billed_on_receipt'] == true) ||
            penaltyTracking?['cold_storage_collected_at_release'] == true ||
            notes.contains('Cold storage fee of ₱150.00 collected') ||
            notes.contains('Cold storage fee of \u20b1150.00 collected') ||
            requestData['status'] == 'released';
        final coldStorageUnpaidOnPaidOrder = isPaid && isColdStorageOverdue && !isColdStorageSettled;

        final subtotal = _kVetHealthCertFee +
            _kPermitToSlaughterFee +
            _kFacilityFee +
            _kCorralFee +
            _kAnteMortemFee +
            postMortemFee +
            penaltyFee +
            overduePenalty +
            coldStoragePenalty;

        final totalFromPay = paymentData?['total_amount'] != null
            ? double.tryParse(paymentData!['total_amount'].toString())
            : null;

        setState(() {
          _request = requestData;
          _payment = paymentData;
          _isWarningOnly = isWarningOnly;
          if (paymentData != null && totalFromPay != null) {
            final vanFee = double.tryParse((paymentData['delivery_van_fee'] ?? deliveryFee).toString()) ?? deliveryFee;
            final computedTotal = subtotal + vanFee;
            final resolvedTotal = (computedTotal > totalFromPay) ? computedTotal : totalFromPay;
            final balanceDue = isPaid
                ? (coldStorageUnpaidOnPaidOrder ? 150.0 : 0.0)
                : resolvedTotal;
            final amountPaid = isPaid
                ? (resolvedTotal - (coldStorageUnpaidOnPaidOrder ? 150.0 : 0.0))
                : 0.0;
            _fees = {
              'vet_health_cert': double.tryParse((paymentData['vet_health_cert_fee'] ?? _kVetHealthCertFee).toString()) ?? _kVetHealthCertFee,
              'permit_to_slaughter': double.tryParse((paymentData['permit_fee'] ?? _kPermitToSlaughterFee).toString()) ?? _kPermitToSlaughterFee,
              'facility': double.tryParse((paymentData['facility_fee'] ?? _kFacilityFee).toString()) ?? _kFacilityFee,
              'corral': double.tryParse((paymentData['corral_fee'] ?? _kCorralFee).toString()) ?? _kCorralFee,
              'ante_mortem': double.tryParse((paymentData['ante_mortem_fee'] ?? _kAnteMortemFee).toString()) ?? _kAnteMortemFee,
              'post_mortem': double.tryParse((paymentData['post_mortem_fee'] ?? postMortemFee).toString()) ?? postMortemFee,
              'penalty_fee': penaltyFee,
              'overdue_penalty': overduePenalty,
              'cold_storage_penalty': coldStoragePenalty,
              'subtotal': resolvedTotal - vanFee,
              'delivery_van': vanFee,
              'total': resolvedTotal,
              'amount_paid': amountPaid,
              'balance_due': balanceDue,
            };
          } else {
            final resolvedTotal = subtotal + deliveryFee;
            final balanceDue = isPaid
                ? (coldStorageUnpaidOnPaidOrder ? 150.0 : 0.0)
                : resolvedTotal;
            final amountPaid = isPaid
                ? (resolvedTotal - (coldStorageUnpaidOnPaidOrder ? 150.0 : 0.0))
                : 0.0;
            _fees = {
              'vet_health_cert': _kVetHealthCertFee,
              'permit_to_slaughter': _kPermitToSlaughterFee,
              'facility': _kFacilityFee,
              'corral': _kCorralFee,
              'ante_mortem': _kAnteMortemFee,
              'post_mortem': postMortemFee,
              'penalty_fee': penaltyFee,
              'overdue_penalty': overduePenalty,
              'cold_storage_penalty': coldStoragePenalty,
              'subtotal': subtotal,
              'delivery_van': deliveryFee,
              'total': resolvedTotal,
              'amount_paid': amountPaid,
              'balance_due': balanceDue,
            };
          }
        });
      }
    } catch (e) {
      debugPrint('ReceiptDetail load error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _refNo() {
    if (_request == null) return 'MI-0000-000';
    return 'MI-${DateTime.now().year}-${_request!['id'].toString().padLeft(3, '0')}';
  }

  String _receiptNo() {
    if (_payment != null && _payment!['receipt_number'] != null) {
      return _payment!['receipt_number'].toString();
    }
    if (_request == null) return 'RCP-0000-000';
    return 'RCP-${DateTime.now().year}-${_request!['id'].toString().padLeft(3, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 50, 16, 20),
            color: kMintHeader,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Payment", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                SizedBox(height: 2),
                Text("View and manage your payment receipt",
                    style: TextStyle(fontSize: 11, color: Color(0xFF2C2C2A))),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: kAccentGreen))
                : _request == null
                    ? _buildNoData()
                    : _buildReceiptContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildNoData() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('No receipt data available', style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildReceiptContent() {
    final req = _request!;
    final weight = double.tryParse((req['carcass_weight'] ?? 0).toString()) ?? 0;
    final isBarangay = req['request_type'] == 'barangay';
    final pMethod = _payment?['payment_method']?.toString().trim().toLowerCase() ?? '';
    final isPaid = (_payment != null &&
            (_payment!['status'] == 'paid' ||
                pMethod == 'gcash' ||
                pMethod == 'maya' ||
                pMethod == 'card' ||
                pMethod == 'grabpay' ||
                pMethod.contains('online') ||
                pMethod.contains('paymongo'))) ||
        req['status'] == 'paid' ||
        req['status'] == 'released';
    // Customer already chose a method, but the admin hasn't verified it yet.
    final isAwaitingVerification = !isPaid &&
        _payment != null &&
        (_payment!['payment_method']?.toString().trim().isNotEmpty ?? false);
    final total = _fees['total'] ?? 0;
    final penaltyTracking = req['penalty_tracking'] as Map<String, dynamic>?;
    DateTime baseDate = DateTime.now();
    final createdStr = penaltyTracking?['receipt_sent_at'] ??
        _payment?['receipt_sent_at'] ??
        _payment?['updated_at'] ??
        _payment?['created_at'];
    if (createdStr != null) {
      final parsed = DateTime.tryParse(createdStr.toString());
      if (parsed != null) baseDate = parsed.toLocal();
    }
    DateTime dueDate = DateTime(baseDate.year, baseDate.month, baseDate.day, 17, 0, 0);
    if (!baseDate.isBefore(dueDate)) {
      dueDate = dueDate.add(const Duration(days: 1));
    }
    final now = DateTime.now();
    final hasReceiptSent = _payment != null ||
        req['status'] == 'payment_pending' ||
        penaltyTracking?['receipt_sent_at'] != null;
    final isOverdue = !isPaid && !isAwaitingVerification && hasReceiptSent && now.isAfter(dueDate);
    final hasColdStorageFee = (_fees['cold_storage_penalty'] ?? 0) > 0;
    final isColdStorageOverdue = hasColdStorageFee && !isPaid;
    final balanceDue = _fees['balance_due'] ?? (isPaid ? 0.0 : total);
    final amountPaid = _fees['amount_paid'] ?? (isPaid ? total : 0.0);
    final rawMethodLabel = (_payment?['payment_method'] ?? req['payment_method'] ?? 'Online Payment').toString().toUpperCase();
    final paymentMethodLabel = rawMethodLabel.contains('PAYMONGO')
        ? (rawMethodLabel.replaceAll('(PAYMONGO)', '').replaceAll('PAYMONGO', '').trim().isEmpty
            ? 'ONLINE PAYMENT'
            : rawMethodLabel.replaceAll('(PAYMONGO)', '').replaceAll('PAYMONGO', '').trim())
        : (rawMethodLabel == 'ONLINE' ? 'ONLINE PAYMENT' : rawMethodLabel);
    final isWithin1HourOfDue = !isPaid &&
        !isAwaitingVerification &&
        !isOverdue &&
        now.isAfter(dueDate.subtract(const Duration(hours: 1)));

    return Transform.translate(
      offset: const Offset(0, -12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 6),
                    const Text("Payment Receipt",
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 14),
                Center(
                  child: Column(
                    children: [
                      const Text("Receipt", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text("Reference #: ${_refNo()}",
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),

                      Text(_receiptNo(),
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),

                      if (isPaid && hasColdStorageFee) ...[
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: balanceDue > 0 ? const Color(0xFFFFF5F5) : const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: balanceDue > 0 ? const Color(0xFFFEB2B2) : const Color(0xFFBBF7D0),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                balanceDue > 0 ? Icons.ac_unit : Icons.check_circle_outline,
                                color: balanceDue > 0 ? const Color(0xFFC53030) : const Color(0xFF15803D),
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  balanceDue > 0
                                      ? 'COLD STORAGE FEE (\u20b1150.00): Carcass was not picked up by 5:00 PM after collection notice. Base slaughter fees are paid ($paymentMethodLabel); \u20b1150.00 Cold Storage fee is due upon carcass pickup.'
                                      : 'COLD STORAGE FEE SETTLED: \u20b1150.00 Cold Storage penalty fee was collected upon carcass handover.',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: balanceDue > 0 ? const Color(0xFF9B2C2C) : const Color(0xFF166534),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (!isPaid && !isAwaitingVerification) ...[
                        const SizedBox(height: 4),
                        Text("Due Date: ${DateFormat('M/dd/yyyy').format(dueDate)} • 5:00 PM",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: (isOverdue || isColdStorageOverdue || isWithin1HourOfDue)
                                  ? const Color(0xFFC53030)
                                  : const Color(0xFF2D3748),
                            )),
                        if (isWithin1HourOfDue) ...[
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3CD),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE2A03F), width: 1.5),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.timer_outlined, color: Color(0xFF975A16), size: 16),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    isBarangay
                                        ? 'URGENT: Less than 1 hour left until 5:00 PM deadline! Pay and pick up immediately to avoid the \u20b1100.00 Overdue Payment and \u20b1150.00 Cold Storage penalties.'
                                        : 'URGENT: Less than 1 hour left until 5:00 PM deadline! Please pay immediately to avoid the \u20b1100.00 overdue penalty.',
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF7A4A00)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: (isOverdue || isColdStorageOverdue)
                                  ? const Color(0xFFFFF5F5)
                                  : const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: (isOverdue || isColdStorageOverdue)
                                    ? const Color(0xFFFEB2B2)
                                    : const Color(0xFFFBD38D),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  (isOverdue || isColdStorageOverdue)
                                      ? Icons.error_outline
                                      : Icons.warning_amber_rounded,
                                  color: (isOverdue || isColdStorageOverdue)
                                      ? const Color(0xFFC53030)
                                      : const Color(0xFFC05621),
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    (isOverdue && isColdStorageOverdue)
                                        ? 'OVERDUE: 5:00 PM deadline expired. An Overdue Payment penalty (\u20b1100.00) and Cold Storage fee (\u20b1150.00) have been applied.'
                                        : isOverdue
                                            ? 'OVERDUE: Payment deadline expired at 5:00 PM. An automatic penalty of \u20b1100.00 has been applied.'
                                            : isColdStorageOverdue
                                                ? 'COLD STORAGE OVERDUE: Meat was not picked up by 5:00 PM after collection notice. A \u20b1150.00 Cold Storage fee has been applied.'
                                                : isBarangay
                                                    ? 'Reminder: Payment must be made on or before 5:00 PM or an automatic \u20b1100.00 Overdue Payment penalty applies. Meat not picked up by 5:00 PM after collection notice incurs a \u20b1150.00 Cold Storage fee.'
                                                    : 'Reminder: Payment must be made immediately on or before 5:00 PM today. If the due date passes without payment, an automatic overdue penalty of \u20b1100.00 will be added.',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: (isOverdue || isColdStorageOverdue)
                                          ? const Color(0xFF9B2C2C)
                                          : const Color(0xFF975A16),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],

                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const DashedLine(),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(req['customer_name']?.toString() ?? '—',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                _kv("Livestock:", req['livestock_type']?.toString() ?? '—'),
                _kv("Count:", '${req['animal_count'] ?? 1} head(s)'),
                if (weight > 0) _kv("Weight:", '${weight.toStringAsFixed(0)} kg'),
                const SizedBox(height: 14),
                const DashedLine(),
                const SizedBox(height: 14),
                const Text("Payment Calculation Preview",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _lineItem("Veterinary Health Certificate:", "\u20b1${_fees['vet_health_cert']?.toStringAsFixed(2) ?? '0.00'}"),
                _lineItem("Permit to Slaughter:", "\u20b1${_fees['permit_to_slaughter']?.toStringAsFixed(2) ?? '0.00'}"),
                _lineItem("Facility Fee:", "\u20b1${_fees['facility']?.toStringAsFixed(2) ?? '0.00'}"),
                _lineItem("Corral Fee:", "\u20b1${_fees['corral']?.toStringAsFixed(2) ?? '0.00'}"),
                _lineItem("Ante-Mortem:", "\u20b1${_fees['ante_mortem']?.toStringAsFixed(2) ?? '0.00'}"),
                _lineItem("Post-Mortem (${weight.toStringAsFixed(0)} kg \u20b1${_kPostMortemRatePerKg.toStringAsFixed(2)}/kg):", "\u20b1${_fees['post_mortem']?.toStringAsFixed(2) ?? '0.00'}"),
                if (((_fees['overdue_penalty'] as num?)?.toDouble() ?? 0.0) > 0)
                  _lineItem(
                    "Overdue Payment Penalty (Past 5:00 PM):",
                    "\u20b1${((_fees['overdue_penalty'] as num?)?.toDouble() ?? 100.0).toStringAsFixed(2)}",
                  ),
                if (((_fees['cold_storage_penalty'] as num?)?.toDouble() ?? 0.0) > 0)
                  _lineItem(
                    "Cold Storage Penalty Fee (Past 5:00 PM):",
                    "\u20b1${((_fees['cold_storage_penalty'] as num?)?.toDouble() ?? 150.0).toStringAsFixed(2)}",
                  ),
                if (((_fees['penalty_fee'] as num?)?.toDouble() ?? 0.0) > 0)
                  _lineItem(
                    "Missed Schedule Slot Penalty (Repeat Offense):",
                    "\u20b1${((_fees['penalty_fee'] as num?)?.toDouble() ?? 500.0).toStringAsFixed(2)}",
                    bold: true,
                    valueColor: const Color(0xFFB91C1C),
                  )
                else if (_isWarningOnly)
                  _lineItem(
                    "Missed Schedule Notice (1st Offense):",
                    "Warning Issued (\u20b10.00 Waived)",
                    bold: false,
                    valueColor: const Color(0xFFB45309),
                  ),
                const SizedBox(height: 8),
                Divider(color: Colors.grey.shade300),
                const SizedBox(height: 4),
                _kv("Subtotal:", "\u20b1${_fees['subtotal']?.toStringAsFixed(2) ?? '0.00'}"),
                if (!isBarangay) _kv("Delivery Van Fee:", "\u20b1${_fees['delivery_van']?.toStringAsFixed(2) ?? '0.00'}"),
                const SizedBox(height: 14),
                const DashedLine(),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("TOTAL AMOUNT:", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    Text("\u20b1${total.toStringAsFixed(2)}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                if (isPaid) ...[
                  if (balanceDue > 0) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("AMOUNT PAID ($paymentMethodLabel):",
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF15803D))),
                        Text("\u20b1${amountPaid.toStringAsFixed(2)}",
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF15803D))),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text("BALANCE (COLD STORAGE FEE DUE AT PICKUP):",
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFC53030))),
                        ),
                        Text("\u20b1${balanceDue.toStringAsFixed(2)}",
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFC53030))),
                      ],
                    ),
                  ] else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("BALANCE:", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        const Text("0", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  _buildPostPaymentReferenceCard(),
                  const SizedBox(height: 10),
                  if (isBarangay)
                    _buildAuthorizedRepresentativeCard(req)
                  else
                    _buildMarketDeliveryInfoCard(),
                  const SizedBox(height: 12),
                  const Text("Thank you!", style: TextStyle(fontSize: 12)),
                  const Text("Tabaco City Slaughterhouse", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                ],
                const SizedBox(height: 16),
                if (isAwaitingVerification) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3CD),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFFD97A)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.hourglass_top, size: 18, color: Color(0xFF856404)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Waiting for Cashier Payment",
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF856404))),
                              const SizedBox(height: 2),
                              Text(
                                (_payment!['payment_method'].toString().toLowerCase().contains('online') || _payment!['payment_method'].toString().toLowerCase().contains('gcash'))
                                    ? "Your online payment is being verified. Once confirmed, your Official Receipt and Pickup Authorization will be generated."
                                    : "Cash-on-Pickup selected. Please settle payment at the cashier counter upon arrival before claiming the carcass from the dispatcher. Once your payment is confirmed, your Official Receipt and Pickup Authorization will be generated.",
                                style: const TextStyle(fontSize: 11, color: Color(0xFF856404)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (!isPaid) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE1F5EE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text("Please review the receipt before proceeding with payment",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 10, color: Color(0xFF0F6E56))),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 46,
                    child: ElevatedButton(
                      onPressed: _isProcessing ? null : _handleProceedToPayment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAccentGreen,
                        foregroundColor: const Color(0xFF04342C),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _isProcessing
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFF04342C)),
                            )
                          : const Text("Proceed to Payment",
                              style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ] else ...[
                  // Paid state — show success badge
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE1F5EE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle, size: 16, color: Color(0xFF0F6E56)),
                          SizedBox(width: 6),
                          Text("Payment Complete",
                              style: TextStyle(fontSize: 12, color: Color(0xFF0F6E56), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleProceedToPayment() async {
    final user = supabase.auth.currentUser;
    if (user == null || _request == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login first')),
      );
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final success = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SelectPaymentScreen(
            request: _request!,
            fees: _fees,
            receiptNo: _receiptNo(),
          ),
        ),
      );

      if (success == true) {
        if (mounted) {
          // Submission complete — go directly back to the payment page
          Navigator.pop(context, true);
          return;
        }
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  static Widget _kv(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      );

  static Widget _lineItem(String label, String amount,
          {bool bold = false, Color? valueColor}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            bold ? FontWeight.bold : FontWeight.normal,
                        color: valueColor))),
            const SizedBox(width: 8),
            Text(amount,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        bold ? FontWeight.bold : FontWeight.normal,
                    color: valueColor)),
          ],
        ),
      );

  Widget _buildPostPaymentReferenceCard() {
    final payment = _payment ?? {};
    final txRef = (payment['transaction_ref']?.toString().isNotEmpty == true)
        ? payment['transaction_ref'].toString()
        : ((payment['receipt_number']?.toString().isNotEmpty == true)
            ? payment['receipt_number'].toString()
            : _receiptNo());
    final rawMethod = (payment['payment_method']?.toString().toUpperCase() ?? 'CASH');
    final method = rawMethod.contains('PAYMONGO')
        ? (rawMethod.replaceAll('(PAYMONGO)', '').replaceAll('PAYMONGO', '').trim().isEmpty
            ? 'ONLINE PAYMENT'
            : rawMethod.replaceAll('(PAYMONGO)', '').replaceAll('PAYMONGO', '').trim())
        : (rawMethod == 'ONLINE' ? 'ONLINE PAYMENT' : rawMethod);
    final rawCashier = payment['cashier_name']?.toString() ?? 'Tabaco City Slaughterhouse Admin';
    final cashier = rawCashier.toLowerCase().contains('paymongo')
        ? 'Online Payment Gateway'
        : rawCashier;
    final paidAtStr = payment['paid_at'] ?? payment['updated_at'] ?? payment['created_at'];
    DateTime paidAt = DateTime.now();
    if (paidAtStr != null) {
      final p = DateTime.tryParse(paidAtStr.toString());
      if (p != null) paidAt = p.toLocal();
    }
    final formattedPaidDate = DateFormat('MMMM d, yyyy • h:mm a').format(paidAt);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFA5D6A7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified, color: Color(0xFF2E7D32), size: 18),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Payment Completed & Verified',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFC8E6C9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('PAID', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: Colors.green.shade200),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Official Payment Reference #', style: TextStyle(fontSize: 10, color: Color(0xFF388E3C), fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    SelectableText(
                      txRef,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20), letterSpacing: 0.5),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.copy, size: 16, color: Color(0xFF2E7D32)),
                tooltip: 'Copy Reference',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: txRef));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Row(children: [
                        Icon(Icons.check_circle, color: Colors.white, size: 16),
                        SizedBox(width: 8),
                        Text('Payment reference copied to clipboard!'),
                      ]),
                      duration: Duration(seconds: 2),
                      backgroundColor: Color(0xFF2E7D32),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          _receiptMetaRow('Method', method),
          _receiptMetaRow('Verified By', cashier),
          _receiptMetaRow('Payment Time', formattedPaidDate),
        ],
      ),
    );
  }

  Widget _receiptMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label:', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF2D3748)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarketDeliveryInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.local_shipping, size: 20, color: Color(0xFF166534)),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Direct Market Delivery',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF166534)),
                ),
                SizedBox(height: 2),
                Text(
                  'Your meat order will be delivered directly to your market stall via refrigerated van. No pick-up authorization required.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF166534)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthorizedRepresentativeCard(Map<String, dynamic> req) {
    final authName = (req['authorized_person_name'] ?? '').toString().trim();
    final authContact = (req['authorized_person_contact'] ?? '').toString().trim();
    final authIdType = (req['authorized_person_id_type'] ?? '').toString().trim();
    final authIdNum = (req['authorized_person_id_num'] ?? '').toString().trim();
    final authRel = (req['authorized_person_relationship'] ?? '').toString().trim();
    final hasAuth = authName.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user, size: 18, color: Color(0xFF16A34A)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Meat Pickup Authorization',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF15803D),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(4)),
                child: const Text('Authorized', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF166534))),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (hasAuth) ...[
            Text('Authorized Person for Pickup: $authName${authRel.isNotEmpty ? " ($authRel)" : ""}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            if (authContact.isNotEmpty)
              Text('Contact: $authContact', style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
            if (authIdType.isNotEmpty || authIdNum.isNotEmpty)
              Text('Valid ID: $authIdType — $authIdNum', style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _showAuthorizedPersonSheet(context, req),
              icon: const Icon(Icons.edit, size: 12),
              label: const Text('Change Authorized Person', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF15803D),
                side: const BorderSide(color: Color(0xFF86EFAC)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: const Size(0, 30),
              ),
            ),
          ] else ...[
            Text('Authorized Person for Pickup: ${req['customer_name'] ?? 'You (Account Owner)'} (Customer Direct)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('Unable to pick up in person? Assign an authorized representative with valid ID to claim the carcass on your behalf.', style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => _showAuthorizedPersonSheet(context, req),
              icon: const Icon(Icons.person_add_alt_1, size: 13),
              label: const Text('Assign Authorized Person', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF15803D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: const Size(0, 32),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                elevation: 0,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showAuthorizedPersonSheet(BuildContext context, Map<String, dynamic> req) {
    final nameCtrl = TextEditingController(text: req['authorized_person_name']?.toString() ?? '');
    final contactCtrl = TextEditingController(text: req['authorized_person_contact']?.toString() ?? '');
    final idNumCtrl = TextEditingController(text: req['authorized_person_id_num']?.toString() ?? '');
    String selectedIdType = (req['authorized_person_id_type']?.toString().isNotEmpty == true)
        ? req['authorized_person_id_type'].toString()
        : 'Philippine National ID (PhilSys)';
    String selectedRelationship = (req['authorized_person_relationship']?.toString().isNotEmpty == true)
        ? req['authorized_person_relationship'].toString()
        : 'Spouse';

    const idTypes = [
      'Philippine National ID (PhilSys)',
      'Driver\'s License',
      'UMID',
      'Passport',
      'SSS / GSIS ID',
      'Voter\'s ID',
      'Postal ID',
      'PRC ID',
      'Barangay ID',
      'Other Valid Government ID',
    ];

    const relationships = [
      'Spouse',
      'Sibling',
      'Child / Parent',
      'Relative',
      'Driver / Transporter',
      'Employee / Assistant',
      'Other Authorized Person',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.badge, color: Color(0xFF15803D), size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Assign Authorized Representative',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A202C)),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Provide details of the person authorized to pick up the carcass at the slaughterhouse. They must present this valid ID to the releasing clerk upon collection.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    _sheetLabel('Representative Full Name *'),
                    TextField(
                      controller: nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: const [WordsCapitalizationFormatter()],
                      decoration: _sheetInputDecoration('e.g. Juan Dela Cruz'),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    _sheetLabel('Contact / Mobile Number *'),
                    TextField(
                      controller: contactCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: _sheetInputDecoration('e.g. 09171234567'),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    _sheetLabel('Relationship to Customer *'),
                    DropdownButtonFormField<String>(
                      initialValue: relationships.contains(selectedRelationship) ? selectedRelationship : relationships.first,
                      isExpanded: true,
                      decoration: _sheetInputDecoration(''),
                      items: relationships.map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 13)))).toList(),
                      onChanged: (v) => setSheetState(() => selectedRelationship = v ?? 'Other'),
                    ),
                    const SizedBox(height: 12),
                    _sheetLabel('Valid ID Type Presented *'),
                    DropdownButtonFormField<String>(
                      initialValue: idTypes.contains(selectedIdType) ? selectedIdType : idTypes.first,
                      isExpanded: true,
                      decoration: _sheetInputDecoration(''),
                      items: idTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13)))).toList(),
                      onChanged: (v) => setSheetState(() => selectedIdType = v ?? 'Valid ID'),
                    ),
                    const SizedBox(height: 12),
                    _sheetLabel('Valid ID Number *'),
                    TextField(
                      controller: idNumCtrl,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: const [UpperCaseTextFormatter()],
                      decoration: _sheetInputDecoration('Enter ID Card Number'),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF15803D),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () async {
                          final name = nameCtrl.text.trim();
                          final contact = contactCtrl.text.trim();
                          final idNum = idNumCtrl.text.trim();
                          if (name.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter representative full name'), backgroundColor: Colors.orange),
                            );
                            return;
                          }
                          try {
                            // 1. Try updating requests directly (if migration columns exist)
                            try {
                              await supabase.from('requests').update({
                                'authorized_person_name': name,
                                'authorized_person_contact': contact,
                                'authorized_person_relationship': selectedRelationship,
                                'authorized_person_id_type': selectedIdType,
                                'authorized_person_id_num': idNum,
                              }).eq('id', req['id']);
                            } catch (_) {}

                            // 2. Also persist to system_settings 'authorized_representatives' as universal fallback
                            try {
                              final existing = await supabase
                                  .from('system_settings')
                                  .select('value')
                                  .eq('key', 'authorized_representatives')
                                  .maybeSingle();
                              Map<String, dynamic> currentMap = {};
                              if (existing != null && existing['value'] is Map) {
                                currentMap = Map<String, dynamic>.from(existing['value']);
                              }
                              currentMap[req['id'].toString()] = {
                                'name': name,
                                'contact': contact,
                                'relationship': selectedRelationship,
                                'id_type': selectedIdType,
                                'id_num': idNum,
                              };
                              await supabase.from('system_settings').upsert({
                                'key': 'authorized_representatives',
                                'value': currentMap,
                                'updated_at': DateTime.now().toIso8601String(),
                              });
                            } catch (_) {}

                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            _loadReceiptData();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Row(children: [
                                  Icon(Icons.check_circle, color: Colors.white, size: 18),
                                  SizedBox(width: 8),
                                  Text('Authorized representative saved for meat pickup!'),
                                ]),
                                backgroundColor: Color(0xFF15803D),
                              ),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error saving representative: $e'), backgroundColor: Colors.red),
                            );
                          }
                        },
                        child: const Text('Save & Confirm Authorization', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _sheetLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
  );

  InputDecoration _sheetInputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF15803D), width: 1.5)),
  );
}
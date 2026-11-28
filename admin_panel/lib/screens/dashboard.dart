import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/app_settings_service.dart';
import '../services/admin_realtime_hub.dart';
import '../services/audit_log_service.dart';
import '../services/notification_service.dart';
import '../utils/confinement_schedule_helper.dart';
import '../widgets/staff_notification_bell.dart';

class DashboardPage extends StatefulWidget {
  final void Function(int index, [String? tab])? onNavigate;

  const DashboardPage({super.key, this.onNavigate});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final supabase = Supabase.instance.client;

  // Pipeline stage counts (live from database, default 0)
  int _pendingCount = 0;
  int _docVerifCount = 0;
  int _slaughterCount = 0;
  int _paymentCount = 0;
  int _releasingCount = 0;

  List<Map<String, dynamic>> _allRequests = [];
  int _clerkStageFilterVal = 0;
  int get _clerkStageFilter => _clerkStageFilterVal;
  int? _inspectorFloorFilterVal;
  int get _inspectorFloorFilter => _inspectorFloorFilterVal ?? 0;
  TextEditingController? _queueSearchCtrl;
  TextEditingController get _queueCtrl => _queueSearchCtrl ??= TextEditingController();

  int _inspectorAwaitingAnteCount = 0;
  int _inspectorInProgressCount = 0;
  int _inspectorFlaggedCount = 0;
  int _inspectorCompletedCount = 0;

  static const List<_ClerkStage> _clerkStages = [
    _ClerkStage(1, 'Receiving & new', 'Assign ref & marking tag', Icons.assignment_outlined,
        Color(0xFFD97706), Color(0xFFFEF3C7), 1, 'Open Receiving'),
    _ClerkStage(2, 'Document verification', 'Vet health & ownership', Icons.fact_check_outlined,
        Color(0xFF2563EB), Color(0xFFDBEAFE), 2, 'Verify Documents'),
    _ClerkStage(3, 'Slaughter & inspection', 'Handled by Meat Inspector', Icons.content_cut_outlined,
        Color(0xFF15803D), Color(0xFFDCFCE7), 3, 'With Inspector'),
    _ClerkStage(4, 'Payment & OR', 'Slaughter & corral fees', Icons.payments_outlined,
        Color(0xFF7C3AED), Color(0xFFEDE9FE), 4, 'Open Cashiering'),
    _ClerkStage(5, 'Meat releasing', 'MIC & gate pass release', Icons.inventory_2_outlined,
        Color(0xFF16A34A), Color(0xFFDCFCE7), 5, 'Release Meat'),
  ];

  // Illegal reports counts (live from database, default 0)
  int _unreviewedIllegalReports = 0;
  String _oldestIllegalReportAgo = '';

  // Statistics
  double _totalRevenue = 0;
  int _animalsProcessed = 0;
  double _avgProcessingHours = 0.0;
  double _satisfactionRate = 0.0;
  bool _isLoading = true;

  // Live Slaughter Floor Queue & Upcoming Schedule state
  String _liveQueueTab = 'active'; // 'active' | 'upcoming' | 'completed'
  bool _liveQueueExpanded = false;

  // Operational strip stats (Collections Today + Inspection Outcomes)
  double _cashTodayTotal = 0.0;
  int _cashTodayCount = 0;
  double _onlineTodayTotal = 0.0;
  int _onlineTodayCount = 0;
  int _inspectionPassedToday = 0;
  int _inspectionConfinedNow = 0;
  int _inspectionCondemnedToday = 0;

  // Recent activity list
  List<Map<String, dynamic>> _recentActivities = [];

  // Polling timer & real-time clock
  Timer? _refreshTimer;
  Timer? _clockTimer;
  DateTime _currentTime = DateTime.now();

  String get _realtimeSubtitle =>
      'City Abattoir Office, City of Tabaco — ${DateFormat('MMMM d, yyyy • h:mm a').format(_currentTime)}';

  bool _isSameLocalDay(DateTime? dt, DateTime ref) {
    if (dt == null) return false;
    final local = dt.toLocal();
    return local.year == ref.year &&
        local.month == ref.month &&
        local.day == ref.day;
  }

  // Search controller
  final TextEditingController _searchCtrl = TextEditingController();

  final Set<String> _shownAnteMortemAlertIds = {};
  StreamSubscription<String>? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _loadAllDashboardData();
    _realtimeSub = AdminRealtimeHub.instance.listen(
      {'requests', 'payments', 'slaughter_inspection', 'reports'},
      () {
        if (mounted) {
          _loadAllDashboardData(silent: true);
          _checkAnteMortemAlerts();
        }
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAnteMortemAlerts();
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _loadAllDashboardData(silent: true);
      _checkAnteMortemAlerts();
    });
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final dayChanged = !_isSameLocalDay(now, _currentTime);
      if (now.minute != _currentTime.minute || dayChanged) {
        setState(() => _currentTime = now);
        if (dayChanged) {
          _loadAllDashboardData(silent: true);
        }
      }
    });
  }

  Future<void> _acknowledgeAnteMortemAlert(String reqId) async {
    try {
      final alertRow = await supabase
          .from('system_settings')
          .select('value')
          .eq('key', 'ante_mortem_alerts')
          .maybeSingle();
      if (alertRow != null && alertRow['value'] is Map) {
        final alerts = Map<String, dynamic>.from(alertRow['value']);
        if (alerts.containsKey(reqId) && alerts[reqId] is Map) {
          alerts[reqId]['acknowledged'] = true;
          await supabase.from('system_settings').upsert({
            'key': 'ante_mortem_alerts',
            'value': alerts,
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _checkAnteMortemAlerts() async {
    try {
      // 1. Check system_settings ante_mortem_alerts for real-time notification
      try {
        final alertRow = await supabase
            .from('system_settings')
            .select('value')
            .eq('key', 'ante_mortem_alerts')
            .maybeSingle();
        if (alertRow != null && alertRow['value'] is Map) {
          final alerts = Map<String, dynamic>.from(alertRow['value']);
          for (final entry in alerts.entries) {
            final idStr = entry.key;
            final alert = entry.value as Map<String, dynamic>;
            if (alert['acknowledged'] == true) continue;
            if (_shownAnteMortemAlertIds.contains(idStr)) continue;

            final req = _allRequests.firstWhere(
              (r) => r['id'].toString() == idStr,
              orElse: () => {
                'id': alert['request_id'] ?? idStr,
                'livestock_type': alert['livestock_type'] ?? 'Livestock',
                'customer_name': 'Customer',
                'animal_count': 1,
              },
            );
            _shownAnteMortemAlertIds.add(idStr);
            if (mounted) {
              _showAnteMortemAlertModal(req, alert['choice']?.toString() ?? 'accept_penalty');
            }
            return;
          }
        }
      } catch (_) {}

      // 2. Direct requests table fallback
      final data = await supabase
          .from('requests')
          .select('id, customer_name, livestock_type, animal_count, status, anti_mortem_response, anti_mortem_response_at')
          .inFilter('status', ['anti_mortem_failed', 'delay_error'])
          .not('anti_mortem_response', 'is', null)
          .order('anti_mortem_response_at', ascending: false)
          .limit(5);

      for (final req in data) {
        final idStr = req['id'].toString();
        final response = req['anti_mortem_response']?.toString();
        if (response != null && response.isNotEmpty && !_shownAnteMortemAlertIds.contains(idStr)) {
          _shownAnteMortemAlertIds.add(idStr);
          if (mounted) {
            _showAnteMortemAlertModal(req, response);
          }
          break;
        }
      }
    } catch (_) {}
  }

  void _showAnteMortemAlertModal(Map<String, dynamic> req, String choice) {
    final ref = 'MI-${DateTime.now().year}-${req['id'].toString().padLeft(3, '0')}';
    final customer = req['customer_name'] ?? 'Customer';
    final livestock = req['livestock_type'] ?? 'Livestock';
    final count = req['animal_count'] ?? 1;
    final isPenaltyAccepted = choice == 'accept_penalty';
    final isConfine = choice == 'confine';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isPenaltyAccepted
                  ? Icons.receipt_long
                  : (isConfine ? Icons.medical_services_outlined : Icons.assignment_return_outlined),
              color: isPenaltyAccepted
                  ? const Color(0xFF16A34A)
                  : (isConfine ? const Color(0xFFD97706) : const Color(0xFFC0392B)),
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isPenaltyAccepted
                    ? 'Technical Delay: Reschedule Accepted'
                    : 'Ante-Mortem Decision Received',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isPenaltyAccepted
                      ? const Color(0xFFECFDF5)
                      : (isConfine ? const Color(0xFFFFFBEB) : const Color(0xFFFEF2F2)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isPenaltyAccepted
                        ? const Color(0xFFA7F3D0)
                        : (isConfine ? const Color(0xFFFCD34D) : const Color(0xFFFCA5A5)),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order: $ref | $customer', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text('Livestock: $livestock ($count head)', style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Text('Customer Response: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        Expanded(
                          child: Text(
                            isPenaltyAccepted
                                ? 'ACCEPTED RESCHEDULE (FACILITY DELAY)'
                                : (isConfine ? 'CONFINE IN SLAUGHTERHOUSE' : 'TAKE LIVESTOCK BACK'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isPenaltyAccepted
                                  ? const Color(0xFF15803D)
                                  : (isConfine ? const Color(0xFFB45309) : const Color(0xFFDC2626)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!isPenaltyAccepted && isConfine) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.event_available_outlined, size: 14, color: Color(0xFF92400E)),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              '2-Day Confinement Ends: ${ConfinementScheduleHelper.formatEndLabel(ConfinementScheduleHelper.resolveConfinementEnd(req))}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                isPenaltyAccepted
                    ? 'The customer accepted rescheduling to keep livestock in facility for resumed slaughter (₱0 facility delay fee). Go to Slaughter & Inspection to set the schedule.'
                    : (isConfine
                        ? 'The animal will remain under 2-day observation until ${ConfinementScheduleHelper.formatEndLabel(ConfinementScheduleHelper.resolveConfinementEnd(req))}. Once confinement ends, evaluate whether to continue slaughter or condemn and notify the customer.'
                        : 'The customer chose to retrieve their livestock. Please set the pickup schedule so the customer knows when to collect the animal at the corral.'),
                style: const TextStyle(fontSize: 13, color: Color(0xFF4A5568)),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _acknowledgeAnteMortemAlert(req['id'].toString());
            },
            child: const Text('Dismiss'),
          ),
          ElevatedButton.icon(
            icon: Icon(isPenaltyAccepted ? Icons.calendar_month : (isConfine ? Icons.arrow_forward : Icons.schedule), size: 16),
            onPressed: () {
              Navigator.pop(ctx);
              _acknowledgeAnteMortemAlert(req['id'].toString());
              widget.onNavigate?.call(3);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isPenaltyAccepted
                  ? const Color(0xFF2563EB)
                  : (isConfine ? const Color(0xFF1E855A) : const Color(0xFFC0392B)),
              foregroundColor: Colors.white,
            ),
            label: Text(isPenaltyAccepted ? 'Go to Reschedule' : (isConfine ? 'Go to Inspection Queue' : 'Set Pickup Schedule')),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _refreshTimer?.cancel();
    _clockTimer?.cancel();
    _searchCtrl.dispose();
    _queueSearchCtrl?.dispose();
    super.dispose();
  }

  Future<void> _loadAllDashboardData({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);

    if (AppSettingsService.instance.hasActiveStaffSession ||
        Supabase.instance.client.auth.currentSession == null) {
      await AppSettingsService.instance.ensureAdminAuthSession();
    }

    await Future.wait([
      _loadPendingCounts(),
      _loadDashboardStats(),
      _loadIllegalReportsData(),
      _loadRecentActivities(),
    ]);

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 1. STAGE / PIPELINE COUNTS
  // ═══════════════════════════════════════════════════════════
  Future<void> _loadPendingCounts() async {
    try {
      final data = await supabase
          .from('requests')
          .select('*, payments(*), slaughter_inspection(*)')
          .order('created_at', ascending: false);

      int pending = 0;
      int docVerif = 0;
      int slaughter = 0;
      int payment = 0;
      int releasing = 0;

      int inspAwaiting = 0;
      int inspInProgress = 0;
      int inspFlagged = 0;
      int inspCompleted = 0;

      final reqList = List<Map<String, dynamic>>.from(data);
      for (var req in reqList) {
        final st = req['status']?.toString().toLowerCase() ?? '';
        final releasedAt = req['released_at'];

        if (st == 'doc_verified') {
          inspAwaiting++;
        } else if (st == 'slaughter_started') {
          inspInProgress++;
        } else if ([
          'anti_mortem_failed',
          'delay_error',
          'post_mortem_failed',
          'confined',
          'pickup_scheduled',
        ].contains(st)) {
          inspFlagged++;
        } else if ([
          'releasable',
          'mic_generated',
          'payment_pending',
          'paid',
          'out_for_delivery',
          'released',
          'completed',
          'condemned',
        ].contains(st)) {
          inspCompleted++;
        }

        // If already released, it is fully completed and not in active workflow
        if (st == 'released' || releasedAt != null) {
          continue;
        }

        // Check if payment was already completed
        bool isPaid = st == 'paid' || st == 'out_for_delivery';
        final payments = req['payments'];
        if (!isPaid && payments != null) {
          if (payments is List && payments.isNotEmpty) {
            isPaid = payments.any((p) => (p as Map)['status'] == 'paid');
          } else if (payments is Map) {
            isPaid = payments['status'] == 'paid';
          }
        }

        if (st == 'pending') {
          pending++;
        } else if (st == 'approved') {
          docVerif++;
        } else if (st == 'doc_verified' || st == 'slaughter_started') {
          slaughter++;
        } else if (isPaid) {
          releasing++;
        } else if (st == 'releasable' || st == 'mic_generated' || st == 'payment_pending') {
          payment++;
        }
      }

      if (mounted) {
        setState(() {
          _allRequests = reqList;
          _pendingCount = pending;
          _docVerifCount = docVerif;
          _slaughterCount = slaughter;
          _paymentCount = payment;
          _releasingCount = releasing;
          _inspectorAwaitingAnteCount = inspAwaiting;
          _inspectorInProgressCount = inspInProgress;
          _inspectorFlaggedCount = inspFlagged;
          _inspectorCompletedCount = inspCompleted;
        });
      }
    } catch (e) {
      debugPrint('Dashboard pending counts error: $e');
    }
  }

  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
  // 2. DASHBOARD KPI STATS
  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
  bool _isOnlinePaymentMethod(dynamic raw) {
    final m = (raw ?? '').toString().trim().toLowerCase();
    return m.contains('gcash') ||
        m.contains('online') ||
        m.contains('xendit') ||
        m.contains('paymongo') ||
        m.contains('maya') ||
        m.contains('qr') ||
        m.contains('card');
  }

  Future<void> _loadDashboardStats() async {
    try {
      final today = DateTime.now();

      double revenue = 0;
      int animals = 0;
      double avgHours = 0.0;
      double cashTotal = 0.0;
      int cashCount = 0;
      double onlineTotal = 0.0;
      int onlineCount = 0;
      int passedToday = 0;
      int confinedNow = 0;
      int condemnedToday = 0;
      final countedRequestIds = <String>{};

      // Fetch requests with inspection & payment details so Dashboard maintains continuous all-time totals
      try {
        final rawRequests = await supabase
            .from('requests')
            .select('*, slaughter_inspection(*), payments(*)');

        double totalHours = 0;
        int completedCount = 0;

        for (var raw in List<Map<String, dynamic>>.from(rawRequests)) {
          final r = Map<String, dynamic>.from(raw);
          final status = (r['status'] ?? '').toString().toLowerCase();

          // Flatten slaughter_inspection
          Map<String, dynamic>? insp;
          final inspRaw = r['slaughter_inspection'];
          if (inspRaw is List && inspRaw.isNotEmpty && inspRaw.first is Map) {
            insp = Map<String, dynamic>.from(inspRaw.first as Map);
          } else if (inspRaw is Map) {
            insp = Map<String, dynamic>.from(inspRaw);
          }

          // Flatten payment
          Map<String, dynamic>? payment;
          final payRaw = r['payments'];
          if (payRaw is List && payRaw.isNotEmpty && payRaw.first is Map) {
            payment = Map<String, dynamic>.from(payRaw.first as Map);
          } else if (payRaw is Map) {
            payment = Map<String, dynamic>.from(payRaw);
          }

          final anti = (insp?['anti_mortem'] ?? '').toString().toLowerCase();
          final post = (insp?['post_mortem'] ?? '').toString().toLowerCase();
          final condReason = (insp?['condemnation_reason'] ?? '').toString().trim();
          final vetFindings = (insp?['veterinary_findings'] ?? '').toString().trim();

          final passedCount = int.tryParse((insp?['passed_count'] ?? r['passed_count'] ?? '').toString()) ?? 0;
          final condemnedCount = int.tryParse((insp?['condemned_count'] ?? r['condemned_count'] ?? '').toString()) ?? 0;
          final isPartialPassed = passedCount > 0 && condemnedCount > 0;

          final releasedAt = DateTime.tryParse(r['released_at']?.toString() ?? '');
          final payCreatedAt = DateTime.tryParse(payment?['created_at']?.toString() ?? '');
          final inspUpdatedAt = DateTime.tryParse(insp?['updated_at']?.toString() ?? '');
          final inspCreatedAt = DateTime.tryParse(insp?['created_at']?.toString() ?? '');
          final preferredDate = DateTime.tryParse(r['preferred_date']?.toString() ?? '');
          final createdAt = DateTime.tryParse(r['created_at']?.toString() ?? '');

          final isToday = _isSameLocalDay(inspCreatedAt, today) ||
              _isSameLocalDay(preferredDate, today) ||
              _isSameLocalDay(releasedAt, today) ||
              _isSameLocalDay(payCreatedAt, today) ||
              _isSameLocalDay(inspUpdatedAt, today) ||
              _isSameLocalDay(createdAt, today);

          final isCondemned = post == 'failed' ||
              status == 'post_mortem_failed' ||
              status == 'condemned' ||
              (condReason.isNotEmpty && condReason != 'null');
          final isConfinedNow = !isCondemned &&
              post != 'passed' &&
              !['releasable', 'paid', 'released', 'completed', 'cancelled', 'rejected', 'taken_back'].contains(status) &&
              (status == 'confined' || status == 'anti_mortem_failed' || anti == 'failed');

          if (isConfinedNow) {
            confinedNow += int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1;
            continue;
          }

          final isFullHealthIssue = !isPartialPassed &&
              (isCondemned ||
                  status == 'taken_back' ||
                  (vetFindings.isNotEmpty && vetFindings != 'null' && anti != 'passed'));

          if (isFullHealthIssue) {
            if (isCondemned && isToday) {
              condemnedToday += condemnedCount > 0
                  ? condemnedCount
                  : (int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1);
            }
            continue;
          }

          final isProcessed = post == 'passed' ||
              [
                'releasable',
                'mic_generated',
                'payment_pending',
                'paid',
                'out_for_delivery',
                'released',
                'completed',
              ].contains(status) ||
              (status == 'slaughter_started' && anti == 'passed');

          if (!isProcessed) continue;

          countedRequestIds.add(r['id'].toString());

          if (isPartialPassed && condemnedCount > 0 && isToday) {
            condemnedToday += condemnedCount;
          }

          // 1. Livestock Processed (All-Time Cumulative) + Passed Today (for Inspection Outcomes)
          final headCount = isPartialPassed
              ? passedCount
              : (int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1);
          animals += headCount;
          if (isToday) {
            passedToday += headCount;
          }

          // 2. Total Revenue & Collections Breakdown (All-Time Cumulative)
          double fee = 0;
          if (payment != null) {
            fee = double.tryParse((payment['total_amount'] ?? payment['amount'] ?? 0).toString()) ?? 0;
          }
          if (fee <= 0) {
            fee = double.tryParse((r['total_amount'] ?? r['total_fee'] ?? 0).toString()) ?? 0;
          }
          if (fee <= 0) {
            final weight = double.tryParse((insp?['carcass_weight'] ?? r['carcass_weight'] ?? 0).toString()) ?? 0;
            if (weight > 0) {
              fee = (weight * 5.0) + 250.0;
            }
          }
          revenue += fee;

          final payStatus = (payment?['status'] ?? '').toString().toLowerCase();
          final isPaidReq = payStatus == 'paid' || ['paid', 'out_for_delivery', 'released', 'completed'].contains(status);
          if (isPaidReq && fee > 0) {
            final methodRaw = payment?['payment_method'] ?? r['payment_method'];
            if (_isOnlinePaymentMethod(methodRaw)) {
              onlineTotal += fee;
              onlineCount++;
            } else {
              cashTotal += fee;
              cashCount++;
            }
          }

          // 3. Avg Processing Time (All-Time Cumulative)
          final isDoneOrNearDone = post == 'passed' ||
              ['releasable', 'paid', 'out_for_delivery', 'released', 'completed'].contains(status);
          final endTime = releasedAt ?? payCreatedAt ?? inspUpdatedAt ?? inspCreatedAt;
          if (isDoneOrNearDone && createdAt != null && endTime != null) {
            final diff = endTime.difference(createdAt).abs();
            totalHours += diff.inSeconds / 3600.0;
            completedCount++;
          }
        }

        if (completedCount > 0) avgHours = totalHours / completedCount;

        // Also include any standalone paid payments whose request wasn't counted above (All-Time)
        try {
          final paymentsData = await supabase
              .from('payments')
              .select('request_id, total_amount, payment_method, status, created_at')
              .eq('status', 'paid');

          for (var p in List<Map<String, dynamic>>.from(paymentsData)) {
            final reqIdStr = p['request_id']?.toString() ?? '';
            if (reqIdStr.isNotEmpty && countedRequestIds.contains(reqIdStr)) continue;
            final amt = double.tryParse(p['total_amount']?.toString() ?? '0') ?? 0;
            revenue += amt;
            if (amt > 0) {
              if (_isOnlinePaymentMethod(p['payment_method'])) {
                onlineTotal += amt;
                onlineCount++;
              } else {
                cashTotal += amt;
                cashCount++;
              }
            }
          }
        } catch (e) {
          debugPrint('Dashboard standalone payments query error: $e');
        }
      } catch (e) {
        debugPrint('Dashboard stats query error: $e');
      }

      // Satisfaction Rate (All-time cumulative — never resets on date change:
      // 50% Completed Transactions + 50% Customer Review Ratings)
      double satisfaction = 0.0;
      try {
        // 1. All-time transaction completion rate
        final allReqRes = await supabase.from('requests').select('status');
        int totalRequests = 0;
        int completedRequests = 0;
        for (var req in List<Map<String, dynamic>>.from(allReqRes)) {
          final s = req['status']?.toString().toLowerCase() ?? '';
          if (s != 'cancelled' && s != 'rejected') {
            totalRequests++;
            if (s == 'released' || s == 'completed') {
              completedRequests++;
            }
          }
        }
        final double completionRate = totalRequests > 0
            ? (completedRequests / totalRequests) * 100.0
            : 0.0;

        // 2. All-time customer review ratings
        final reviewsData = await supabase.from('reviews').select('rating');
        double totalRating = 0;
        int reviewCount = 0;
        for (var r in List<Map<String, dynamic>>.from(reviewsData)) {
          final rating = double.tryParse(r['rating']?.toString() ?? '0') ?? 0;
          if (rating > 0) {
            totalRating += rating;
            reviewCount++;
          }
        }

        final double reviewScore = reviewCount > 0
            ? (totalRating / reviewCount / 5.0) * 100.0
            : 0.0;

        satisfaction = ((completionRate * 0.5) + (reviewScore * 0.5)).clamp(0.0, 100.0);
      } catch (e) {
        debugPrint('Dashboard satisfaction rate calculation error: $e');
      }

      if (mounted) {
        setState(() {
          _totalRevenue = revenue;
          _animalsProcessed = animals;
          _avgProcessingHours = avgHours;
          _satisfactionRate = satisfaction;
          _cashTodayTotal = cashTotal;
          _cashTodayCount = cashCount;
          _onlineTodayTotal = onlineTotal;
          _onlineTodayCount = onlineCount;
          _inspectionPassedToday = passedToday;
          _inspectionConfinedNow = confinedNow;
          _inspectionCondemnedToday = condemnedToday;
        });
      }
    } catch (e) {
      debugPrint('Dashboard stats error: $e');
    }
  }

  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
  // 3. ILLEGAL REPORTS ALERT
  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
  Future<void> _loadIllegalReportsData() async {
    try {
      final reportsRes = await supabase.from('reports').select();
      final Map<String, Map<String, dynamic>> reportsMap = {};

      for (var r in (reportsRes as List)) {
        final idStr = r['id']?.toString() ?? '';
        final shortId = idStr.length >= 8
            ? idStr.substring(0, 8).toUpperCase()
            : idStr.toUpperCase();
        final ref = r['reference_no']?.toString() ?? (idStr.isNotEmpty ? 'RPT-2026-$shortId' : '');
        final key = ref.isNotEmpty ? ref : idStr;
        if (key.isNotEmpty) {
          reportsMap[key] = {
            'id': idStr,
            'reference_no': ref,
            'status': r['status'] ?? 'Pending Review',
            'created_at': r['incident_date'] ?? r['created_at'],
          };
        }
      }

      // Merge notifications to accurately reflect updated statuses (e.g. 'Report Compiled')
      try {
        final notifs = await supabase
            .from('notifications')
            .select('id, type, reference_no, data, created_at')
            .inFilter('type', [
              'admin_illegal_report',
              'report_filed',
              'report_status_update',
              'report_investigating',
              'report_resolved',
            ])
            .order('created_at', ascending: true);

        for (var n in (notifs as List)) {
          final data = n['data'] is Map ? Map<String, dynamic>.from(n['data']) : <String, dynamic>{};
          final ref = n['reference_no']?.toString() ?? data['reference_no']?.toString() ?? '';
          final rId = data['report_id']?.toString() ?? data['id']?.toString() ?? '';

          String? matchKey;
          for (var k in reportsMap.keys) {
            final item = reportsMap[k]!;
            if ((ref.isNotEmpty && (k == ref || item['reference_no'] == ref)) ||
                (rId.isNotEmpty && (item['id'] == rId || k == rId))) {
              matchKey = k;
              break;
            }
          }

          if (matchKey != null) {
            if (data['status'] != null && data['status'].toString().isNotEmpty) {
              reportsMap[matchKey]!['status'] = data['status'].toString();
            }
          } else if (ref.isNotEmpty || rId.isNotEmpty) {
            final key = ref.isNotEmpty ? ref : rId;
            reportsMap[key] = {
              'id': rId,
              'reference_no': ref,
              'status': data['status'] ?? 'Pending Review',
              'created_at': n['created_at'],
            };
          }
        }
      } catch (_) {}

      int count = 0;
      DateTime? oldestDate;
      for (var rep in reportsMap.values) {
        final s = (rep['status'] ?? '').toString().trim().toLowerCase();
        final isPending = s == 'pending' ||
            s == 'unreviewed' ||
            s == 'submitted' ||
            s == 'new' ||
            s == 'pending review' ||
            s == 'pending_review' ||
            s == 'under review';
        if (isPending) {
          count++;
          final dStr = rep['created_at']?.toString();
          if (dStr != null) {
            final dt = DateTime.tryParse(dStr);
            if (dt != null && (oldestDate == null || dt.isBefore(oldestDate))) {
              oldestDate = dt;
            }
          }
        }
      }

      String oldestAgo = '';
      if (oldestDate != null && count > 0) {
        final diff = DateTime.now().difference(oldestDate);
        if (diff.inDays > 1) {
          oldestAgo = 'Oldest filed ${diff.inDays} days ago';
        } else if (diff.inDays == 1) {
          oldestAgo = 'Oldest filed yesterday';
        } else if (diff.inHours > 0) {
          oldestAgo = 'Oldest filed ${diff.inHours} hr ago';
        } else {
          oldestAgo = 'Filed today';
        }
      }

      if (mounted) {
        setState(() {
          _unreviewedIllegalReports = count;
          _oldestIllegalReportAgo = oldestAgo;
        });
      }
    } catch (e) {
      debugPrint('Dashboard illegal reports error: $e');
    }
  }

  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
  // 4. RECENT ACTIVITY
  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
  Future<void> _loadRecentActivities() async {
    try {
      final today = DateTime.now();
      final List<Map<String, dynamic>> items = [];

      // 1. Payment activity (Today only — resets at midnight)
      try {
        final payments = await supabase
            .from('payments')
            .select('request_id, created_at, total_amount')
            .order('created_at', ascending: false)
            .limit(5);

        for (var p in payments) {
          final dt = DateTime.tryParse(p['created_at']?.toString() ?? '');
          if (!_isSameLocalDay(dt, today)) continue;
          final idNum = (p['request_id'] ?? '').toString().padLeft(4, '0');
          items.add({
            'title': 'Request #$idNum payment confirmed',
            'time': _formatTimeAgo(dt!),
            'color': const Color(0xFF16A34A), // Green dot
            'dt': dt,
          });
        }
      } catch (_) {}

      // 2. New Request activity (Today only — resets at midnight)
      try {
        final requests = await supabase
            .from('requests')
            .select('id, barangay, customer_name, created_at')
            .order('created_at', ascending: false)
            .limit(5);

        for (var r in requests) {
          final dt = DateTime.tryParse(r['created_at']?.toString() ?? '');
          if (!_isSameLocalDay(dt, today)) continue;
          final brgy = r['barangay']?.toString() ?? r['customer_name']?.toString() ?? 'Walk-in';
          items.add({
            'title': 'New request from $brgy',
            'time': _formatTimeAgo(dt!),
            'color': const Color(0xFFD97706), // Amber dot
            'dt': dt,
          });
        }
      } catch (_) {}

      // 3. Illegal report activity (kept across days — except for the report)
      try {
        final notifs = await supabase
            .from('notifications')
            .select('reference_no, created_at, data')
            .inFilter('type', ['admin_illegal_report', 'report_filed'])
            .order('created_at', ascending: false)
            .limit(2);

        for (var n in notifs) {
          final data = n['data'] is Map ? Map<String, dynamic>.from(n['data']) : <String, dynamic>{};
          final ref = n['reference_no']?.toString() ?? data['reference_no']?.toString() ?? '';
          final dt = DateTime.tryParse(n['created_at']?.toString() ?? '');
          if (ref.isEmpty || dt == null) continue;
          items.add({
            'title': 'Report $ref filed',
            'time': _formatTimeAgo(dt),
            'color': const Color(0xFFDC2626), // Red dot
            'dt': dt,
          });
        }
      } catch (_) {}

      // Sort by date descending
      items.sort((a, b) => (b['dt'] as DateTime).compareTo(a['dt'] as DateTime));

      if (mounted) {
        setState(() {
          _recentActivities = items.take(4).toList();
        });
      }
    } catch (e) {
      debugPrint('Dashboard recent activities error: $e');
    }
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours} hr ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes} min ago';
    return 'Just now';
  }

  String _formatRevenue(double amount) {
    final formatted = amount.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
    return '₱$formatted';
  }

  String _formatProcessingTime(double hours) {
    if (hours <= 0) return '0m';
    if (hours < 1) {
      final mins = (hours * 60).round();
      return mins > 0 ? '${mins}m' : '<1m';
    } else {
      final h = hours.floor();
      final m = ((hours - h) * 60).round();
      return m > 0 ? '${h}h ${m}m' : '${h}h';
    }
  }

  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
  // 5. SEARCH REFERENCE HANDLER
  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
  Future<void> _handleSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;

    try {
      // Check notifications / reports
      final notifs = await supabase
          .from('notifications')
          .select()
          .ilike('reference_no', '%$q%')
          .limit(1);

      if (notifs.isNotEmpty) {
        final ref = notifs.first['reference_no']?.toString() ?? q;
        _showSearchResultDialog(
          title: 'Illegal Slaughter Report',
          refNo: ref,
          description: notifs.first['message']?.toString() ?? 'Citizen illegal slaughter submission.',
          targetModuleIndex: 8,
        );
        return;
      }

      // Check requests
      final intId = int.tryParse(q.replaceAll(RegExp(r'[^0-9]'), ''));
      if (intId != null) {
        final reqs = await supabase
            .from('requests')
            .select()
            .eq('id', intId)
            .limit(1);

        if (reqs.isNotEmpty) {
          final r = reqs.first;
          final status = r['status']?.toString() ?? 'pending';
          int module = 1;
          if (status == 'approved') module = 2;
          if (status == 'doc_verified') module = 3;
          if (status == 'releasable' || status == 'mic_generated' || status == 'payment_pending') module = 4;
          if (status == 'paid') module = 5;

          _showSearchResultDialog(
            title: 'Slaughter Request #$intId',
            refNo: 'MI-${DateTime.now().year}-${intId.toString().padLeft(3, '0')}',
            description: 'Status: $status | Customer: ${r['customer_name'] ?? 'N/A'}',
            targetModuleIndex: module,
          );
          return;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No matching records found for "$q"'),
            backgroundColor: const Color(0xFF475569),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Search error: $e');
    }
  }

  void _showSearchResultDialog({
    required String title,
    required String refNo,
    required String description,
    required int targetModuleIndex,
    String? targetTab,
  }) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close Search Dialog',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, anim1, anim2) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 460,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.check_circle_outline, color: Color(0xFF2D6A4F), size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            ),
                            Text(
                              refNo,
                              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20, color: Color(0xFF94A3B8)),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    description,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Close', style: TextStyle(color: Color(0xFF64748B))),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2D6A4F),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        ),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          widget.onNavigate?.call(targetModuleIndex, targetTab);
                        },
                        child: const Text('Open in Module', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4 * anim1.value, sigmaY: 4 * anim1.value),
          child: FadeTransition(opacity: anim1, child: child),
        );
      },
    );
  }

  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
  // MAIN BUILD
  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
    @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettingsService.instance,
      builder: (context, _) {
        final role = StaffAccount.normalizeRole(AppSettingsService.instance.currentRole);
        if (role == 'Clerk') {
          return _buildClerkDashboard();
        }
        if (role == 'Inspector') {
          return _buildInspectorDashboard();
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF4F6F9),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── 1. TOP HEADER ROW ───
                _buildHeaderRow(),
                if (_isLoading) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0F5132)),
                  ),
                  const SizedBox(height: 14),
                ] else ...[
                  const SizedBox(height: 24),
                ],

                // â”€â”€â”€ 2. TOP 4 KPI CARDS â”€â”€â”€
                _buildKpiMetricsGrid(),
                const SizedBox(height: 22),

                // â”€â”€â”€ 3. TODAY'S WORKFLOW (PIPELINE) â”€â”€â”€
                _buildTodayWorkflowCard(),
                const SizedBox(height: 22),

                // â”€â”€â”€ 4. MIDDLE SECTION: NEEDS ATTENTION & RECENT ACTIVITY â”€â”€â”€
                _buildMiddleSection(),
                const SizedBox(height: 24),

                // ─── 5. OPERATIONAL STRIP: COLLECTIONS TODAY & INSPECTION OUTCOMES ───
                _buildOperationalStrip(),
                const SizedBox(height: 20),

                // ─── 6. BOTTOM LIVE OPERATIONS: SLAUGHTER FLOOR QUEUE & SCHEDULE ───
                _buildLiveFloorQueueCard(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
  // WIDGET 1: HEADER ROW
  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
  Widget _buildHeaderRow() {
    Widget buildWelcome() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppSettingsService.instance.isSuperAdmin
                  ? 'Welcome back, Super Admin'
                  : 'Welcome back, Admin',
              style: const TextStyle(
                fontSize: 24,
                height: 32 / 24,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(
              _realtimeSubtitle,
              style: const TextStyle(
                fontSize: 14,
                height: 20 / 14,
                color: Color(0xFF475569),
                fontWeight: FontWeight.w400,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );

    Widget buildSearchBox({double? width}) => Container(
          width: width,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: TextField(
            controller: _searchCtrl,
            onSubmitted: _handleSearch,
            style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
            decoration: InputDecoration(
              hintText: 'Search reference no.',
              hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16, color: Color(0xFF94A3B8)),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {});
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        );

    Widget buildActions() => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StaffNotificationBell(
              onNavigate: (m, [tab]) => widget.onNavigate?.call(m, tab),
            ),
          ],
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 760) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: buildWelcome()),
              const SizedBox(width: 16),
              buildSearchBox(width: 260),
              const SizedBox(width: 8),
              buildActions(),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: buildWelcome()),
                const SizedBox(width: 8),
                buildActions(),
              ],
            ),
            const SizedBox(height: 12),
            buildSearchBox(),
          ],
        );
      },
    );
  }

  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
  // WIDGET 2: TOP 4 KPI CARDS
  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
  Widget _buildKpiMetricsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 950;
        final card1 = _buildKpiCard(
          iconWidget: const Text(
            '\u20B1',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F5132),
            ),
          ),
          iconBgColor: const Color(0xFFECFDF5),
          title: 'TOTAL REVENUE',
          value: _formatRevenue(_totalRevenue),
          valueColor: const Color(0xFF047857),
          subtitleText: _totalRevenue > 0 ? 'From processed & paid requests' : 'No payments yet',
          subtitleColor: const Color(0xFF047857),
        );

        final card2 = _buildKpiCard(
          iconWidget: const Text(
            '\u{1F437}',
            style: TextStyle(fontSize: 16),
          ),
          iconBgColor: const Color(0xFFFCE7F3),
          title: 'LIVESTOCK PROCESSED',
          value: '$_animalsProcessed',
          valueColor: const Color(0xFF0F172A),
          subtitleText: _animalsProcessed > 0 ? 'Livestock completed' : 'None processed yet',
          subtitleColor: const Color(0xFF64748B),
        );

        final card3 = _buildKpiCard(
          iconWidget: const Icon(Icons.timer_outlined, size: 18, color: Color(0xFFB45309)),
          iconBgColor: const Color(0xFFFFFBEB),
          title: 'AVG PROCESSING TIME',
          value: _formatProcessingTime(_avgProcessingHours),
          valueColor: const Color(0xFF0F172A),
          subtitleText: 'per livestock',
          subtitleColor: const Color(0xFFD97706),
        );

        final card4 = InkWell(
          onTap: () => widget.onNavigate?.call(6, 'Customer Reviews'),
          borderRadius: BorderRadius.circular(14),
          child: _buildKpiCard(
            iconWidget: const Icon(Icons.star_rounded, size: 20, color: Color(0xFF1D4ED8)),
            iconBgColor: const Color(0xFFEFF6FF),
            title: 'SATISFACTION RATE',
            value: '${_satisfactionRate.toStringAsFixed(0)}%',
            valueColor: const Color(0xFF1D4ED8),
            subtitleText: 'View customer feedback →',
            subtitleColor: const Color(0xFF1D4ED8),
          ),
        );

        if (isWide) {
          return Row(
            children: [
              Expanded(child: card1),
              const SizedBox(width: 16),
              Expanded(child: card2),
              const SizedBox(width: 16),
              Expanded(child: card3),
              const SizedBox(width: 16),
              Expanded(child: card4),
            ],
          );
        } else {
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(width: (constraints.maxWidth - 16) / 2, child: card1),
              SizedBox(width: (constraints.maxWidth - 16) / 2, child: card2),
              SizedBox(width: (constraints.maxWidth - 16) / 2, child: card3),
              SizedBox(width: (constraints.maxWidth - 16) / 2, child: card4),
            ],
          );
        }
      },
    );
  }

  Widget _buildKpiCard({
    required Widget iconWidget,
    required Color iconBgColor,
    required String title,
    required String value,
    Color valueColor = const Color(0xFF0F172A),
    required String subtitleText,
    required Color subtitleColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
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
          // Uppercase Tracked Label
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),

          // Big Bold Metric Value
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: valueColor,
              letterSpacing: -0.5,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),

          // Clean Subtitle
          Text(
            subtitleText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: subtitleColor,
            ),
          ),
        ],
      ),
    );
  }

  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
  // WIDGET 3: TODAY'S WORKFLOW
  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
  Widget _buildTodayWorkflowCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Today's workflow",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Requests currently at each stage',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 18),

          // Responsive 5-stage stepper (horizontal on desktop, 2-col grid on Android phones)
          LayoutBuilder(
            builder: (context, constraints) {
              final boxes = [
                _buildStageBox(
                  count: _pendingCount,
                  label: 'Receiving & new',
                  isHighlighted: _pendingCount > 0,
                  onTap: () => widget.onNavigate?.call(1),
                  highlightBgColor: const Color(0xFFFEF2F2),
                  highlightBorderColor: const Color(0xFFFECACA),
                  highlightTextColor: const Color(0xFFDC2626),
                ),
                _buildStageBox(
                  count: _docVerifCount,
                  label: 'Document verification',
                  isHighlighted: _docVerifCount > 0,
                  onTap: () => widget.onNavigate?.call(2),
                  highlightBgColor: const Color(0xFFEFF6FF),
                  highlightBorderColor: const Color(0xFFBFDBFE),
                  highlightTextColor: const Color(0xFF2563EB),
                ),
                _buildStageBox(
                  count: _slaughterCount,
                  label: 'Slaughter & inspection',
                  isHighlighted: _slaughterCount > 0,
                  onTap: () => widget.onNavigate?.call(3),
                  highlightBgColor: const Color(0xFFF0FDF4),
                  highlightBorderColor: const Color(0xFFBBF7D0),
                  highlightTextColor: const Color(0xFF16A34A),
                ),
                _buildStageBox(
                  count: _paymentCount,
                  label: 'Payment',
                  isHighlighted: _paymentCount > 0,
                  onTap: () => widget.onNavigate?.call(4),
                  highlightBgColor: const Color(0xFFFFFBEB),
                  highlightBorderColor: const Color(0xFFFDE68A),
                  highlightTextColor: const Color(0xFFD97706),
                ),
                _buildStageBox(
                  count: _releasingCount,
                  label: 'Meat releasing',
                  isHighlighted: _releasingCount > 0,
                  onTap: () => widget.onNavigate?.call(5),
                  highlightBgColor: const Color(0xFFFAF5FF),
                  highlightBorderColor: const Color(0xFFE9D5FF),
                  highlightTextColor: const Color(0xFF9333EA),
                ),
              ];

              if (constraints.maxWidth >= 680) {
                return Row(
                  children: [
                    for (int i = 0; i < boxes.length; i++) ...[
                      if (i > 0) _buildChevron(),
                      Expanded(child: boxes[i]),
                    ],
                  ],
                );
              }

              final cardW = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: boxes.map((b) => SizedBox(width: cardW, child: b)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChevron() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 6),
      child: Icon(Icons.chevron_right, size: 18, color: Color(0xFFCBD5E1)),
    );
  }

  Widget _buildStageBox({
    required int count,
    required String label,
    bool isHighlighted = false,
    required VoidCallback onTap,
    Color highlightBgColor = const Color(0xFFFFFBEB),
    Color highlightBorderColor = const Color(0xFFFDE68A),
    Color highlightTextColor = const Color(0xFFD97706),
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isHighlighted ? highlightBgColor : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isHighlighted ? highlightBorderColor : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: isHighlighted ? highlightTextColor : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
  // WIDGET 4: MIDDLE SECTION (NEEDS ATTENTION & RECENT ACTIVITY)
  // ΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉΓòÉ
  Widget _buildMiddleSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 950;
        final leftSection = _buildNeedsAttentionColumn();
        final rightSection = _buildRecentActivityColumn();

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: leftSection),
              const SizedBox(width: 20),
              Expanded(flex: 4, child: rightSection),
            ],
          );
        } else {
          return Column(
            children: [
              leftSection,
              const SizedBox(height: 20),
              rightSection,
            ],
          );
        }
      },
    );
  }

  Widget _buildNeedsAttentionColumn() {
    final hasIllegalReports = _unreviewedIllegalReports > 0;
    final hasDocVerif = _docVerifCount > 0;
    final hasAnyAttention = hasIllegalReports || hasDocVerif;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Needs attention',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Items waiting for an admin decision',
          style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 14),

        if (!hasAnyAttention)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.check_circle_outline, size: 20, color: Color(0xFF16A34A)),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'All caught up!',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'No requests or citizen reports currently requiring immediate action.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else ...[
          // 1. Red Alert: Illegal Slaughter Reports (only if > 0)
          if (hasIllegalReports) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFEE2E2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.warning_amber_rounded, size: 20, color: Color(0xFFDC2626)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_unreviewedIllegalReports new illegal slaughter report${_unreviewedIllegalReports == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        if (_oldestIllegalReportAgo.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            _oldestIllegalReportAgo,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    ),
                    onPressed: () => widget.onNavigate?.call(8),
                    child: const Text('Review', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ],
              ),
            ),
            if (hasDocVerif) const SizedBox(height: 12),
          ],

          // 2. Amber Alert: Document Check (only if > 0)
          if (hasDocVerif)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFEF3C7)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.description_outlined, size: 20, color: Color(0xFFD97706)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_docVerifCount request${_docVerifCount == 1 ? '' : 's'} awaiting document check',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Barangay certificate / proof of ownership',
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD97706),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    onPressed: () => widget.onNavigate?.call(2),
                    child: const Text('Open', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildRecentActivityColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent activity',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Latest operations',
          style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 14),

        // Activity Card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: _recentActivities.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      Icon(Icons.history_toggle_off_rounded, size: 18, color: Color(0xFF94A3B8)),
                      SizedBox(width: 10),
                      Text(
                        'No activity recorded today.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: _recentActivities.asMap().entries.map((entry) {
              final idx = entry.key;
              final act = entry.value;
              final isLast = idx == _recentActivities.length - 1;

              return Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Dot
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: act['color'] as Color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Title
                    Expanded(
                      child: Text(
                        act['title'].toString(),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Time
                    Text(
                      act['time'].toString(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // WIDGET 5A: OPERATIONAL STRIP (COLLECTIONS TODAY & INSPECTION OUTCOMES)
  // ═══════════════════════════════════════════════════════════
  Widget _buildOperationalStrip() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 860) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildCollectionsTodayCard()),
                const SizedBox(width: 16),
                Expanded(child: _buildInspectionOutcomesCard()),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCollectionsTodayCard(),
            const SizedBox(height: 16),
            _buildInspectionOutcomesCard(),
          ],
        );
      },
    );
  }

  Widget _buildCollectionsTodayCard() {
    final totalCollected = _cashTodayTotal + _onlineTodayTotal;
    final cashPct = totalCollected > 0 ? ((_cashTodayTotal / totalCollected) * 100).round() : 0;
    final onlinePct = totalCollected > 0 ? 100 - cashPct : 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Collections',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'All-time Cash drawer vs. GCash / Online payment breakdown',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              if (_paymentCount > 0)
                InkWell(
                  onTap: () => widget.onNavigate?.call(4),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$_paymentCount unpaid',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.payments_outlined, size: 15, color: Color(0xFF047857)),
                          SizedBox(width: 5),
                          Text('Cash', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF047857))),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatRevenue(_cashTodayTotal),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF065F46)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$_cashTodayCount ${_cashTodayCount == 1 ? 'payment' : 'payments'} ($cashPct%)',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF047857)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.phone_android_outlined, size: 15, color: Color(0xFF1D4ED8)),
                          SizedBox(width: 5),
                          Text('GCash / Online', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF1D4ED8))),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatRevenue(_onlineTodayTotal),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1E3A8A)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$_onlineTodayCount ${_onlineTodayCount == 1 ? 'payment' : 'payments'} ($onlinePct%)',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF1D4ED8)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 7,
              child: totalCollected <= 0
                  ? Container(color: const Color(0xFFE2E8F0))
                  : Row(
                      children: [
                        if (_cashTodayTotal > 0)
                          Expanded(
                            flex: _cashTodayTotal.round().clamp(1, 10000000),
                            child: Container(color: const Color(0xFF059669)),
                          ),
                        if (_onlineTodayTotal > 0)
                          Expanded(
                            flex: _onlineTodayTotal.round().clamp(1, 10000000),
                            child: Container(color: const Color(0xFF2563EB)),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInspectionOutcomesCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Inspection Outcomes',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Food-safety clearance, 2-day confinement & condemnations',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => widget.onNavigate?.call(3),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF2D6A4F),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Inspection →', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildOutcomeStatTile(
                  label: 'Passed Today',
                  value: '$_inspectionPassedToday',
                  unit: _inspectionPassedToday == 1 ? 'head' : 'heads',
                  color: const Color(0xFF15803D),
                  bgColor: const Color(0xFFECFDF5),
                  borderColor: const Color(0xFFA7F3D0),
                  icon: Icons.check_circle_outline,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildOutcomeStatTile(
                  label: 'Confined (2d)',
                  value: '$_inspectionConfinedNow',
                  unit: 'on hold',
                  color: const Color(0xFFB45309),
                  bgColor: const Color(0xFFFFFBEB),
                  borderColor: const Color(0xFFFDE68A),
                  icon: Icons.medical_services_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildOutcomeStatTile(
                  label: 'Condemned',
                  value: '$_inspectionCondemnedToday',
                  unit: 'today',
                  color: const Color(0xFFDC2626),
                  bgColor: const Color(0xFFFEF2F2),
                  borderColor: const Color(0xFFFECACA),
                  icon: Icons.gpp_bad_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOutcomeStatTile({
    required String label,
    required String value,
    required String unit,
    required Color color,
    required Color bgColor,
    required Color borderColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  unit,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: color.withValues(alpha: 0.85)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _isRequestOverdue(Map<String, dynamic> req) {
    final rawTime = req['updated_at'] ?? req['created_at'];
    final dt = DateTime.tryParse(rawTime?.toString() ?? '')?.toLocal();
    if (dt == null) return false;
    final thresholdHours = _avgProcessingHours > 1.0 ? _avgProcessingHours : 24.0;
    final elapsedHours = DateTime.now().difference(dt).inMinutes / 60.0;
    return elapsedHours > thresholdHours;
  }

  // ═══════════════════════════════════════════════════════════
  // WIDGET 5B: LIVE SLAUGHTER FLOOR QUEUE & UPCOMING SCHEDULE
  // ═══════════════════════════════════════════════════════════
  ({int moduleIndex, String label, Color color, Color bgColor}) _resolveAdminQueueStage(
    Map<String, dynamic> req,
  ) {
    final st = (req['status'] ?? '').toString().toLowerCase();
    final releasedAt = req['released_at'];

    if (st == 'released' || st == 'completed' || releasedAt != null) {
      return (
        moduleIndex: 5,
        label: 'Released',
        color: const Color(0xFF15803D),
        bgColor: const Color(0xFFDCFCE7),
      );
    }

    bool isPaid = st == 'paid' || st == 'out_for_delivery';
    final payments = req['payments'];
    if (!isPaid && payments != null) {
      if (payments is List && payments.isNotEmpty) {
        isPaid = payments.any((p) => (p as Map)['status'] == 'paid');
      } else if (payments is Map) {
        isPaid = payments['status'] == 'paid';
      }
    }

    if (st == 'pending' || st == 'pending_approval') {
      return (
        moduleIndex: 1,
        label: 'Receiving',
        color: const Color(0xFFB45309),
        bgColor: const Color(0xFFFEF3C7),
      );
    }
    if (st == 'approved' ||
        st == 'doc_submitted' ||
        st == 'pending_verification' ||
        st == 'document_pending') {
      return (
        moduleIndex: 2,
        label: 'Verification',
        color: const Color(0xFF1D4ED8),
        bgColor: const Color(0xFFDBEAFE),
      );
    }
    if (st == 'anti_mortem_failed' ||
        st == 'post_mortem_failed' ||
        st == 'confined' ||
        st == 'delay_error' ||
        st == 'pickup_scheduled') {
      return (
        moduleIndex: 3,
        label: 'Inspection Flagged',
        color: const Color(0xFFDC2626),
        bgColor: const Color(0xFFFEE2E2),
      );
    }
    if (st == 'doc_verified' || st == 'slaughter_started') {
      return (
        moduleIndex: 3,
        label: st == 'slaughter_started' ? 'Slaughtering' : 'Inspection',
        color: const Color(0xFF047857),
        bgColor: const Color(0xFFD1FAE5),
      );
    }
    if (isPaid) {
      return (
        moduleIndex: 5,
        label: 'Ready for Release',
        color: const Color(0xFF16A34A),
        bgColor: const Color(0xFFDCFCE7),
      );
    }
    if (st == 'releasable' || st == 'mic_generated' || st == 'payment_pending') {
      return (
        moduleIndex: 4,
        label: 'Awaiting Payment',
        color: const Color(0xFF6D28D9),
        bgColor: const Color(0xFFEDE9FE),
      );
    }
    return (
      moduleIndex: 1,
      label: 'In Queue',
      color: const Color(0xFF475569),
      bgColor: const Color(0xFFF1F5F9),
    );
  }

  DateTime? _parseScheduledDate(Map<String, dynamic> req) {
    final raw = req['slaughter_schedule'] ?? req['scheduled_date'] ?? req['preferred_date'];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  String _formatQueueRelativeTime(Map<String, dynamic> req, String tab) {
    if (tab == 'upcoming') {
      final sched = _parseScheduledDate(req);
      if (sched == null) return 'Scheduled';
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final schedDay = DateTime(sched.year, sched.month, sched.day);
      final hasTime = sched.hour != 0 || sched.minute != 0;
      final timePart = hasTime ? ' • ${DateFormat('h:mm a').format(sched)}' : '';
      if (schedDay == todayStart) return 'Today$timePart';
      if (schedDay == todayStart.add(const Duration(days: 1))) return 'Tomorrow$timePart';
      return '${DateFormat('MMM d').format(sched)}$timePart';
    }

    final rawTime = tab == 'completed'
        ? (req['released_at'] ?? req['updated_at'] ?? req['created_at'])
        : (req['updated_at'] ?? req['created_at']);
    final dt = DateTime.tryParse(rawTime?.toString() ?? '')?.toLocal();
    if (dt == null) return '—';
    if (tab == 'completed') {
      return DateFormat('h:mm a').format(dt);
    }
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d').format(dt);
  }

  Widget _buildLiveFloorQueueCard() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    final List<Map<String, dynamic>> activeList = [];
    final List<Map<String, dynamic>> upcomingList = [];
    final List<Map<String, dynamic>> completedTodayList = [];

    for (final req in _allRequests) {
      final st = (req['status'] ?? '').toString().toLowerCase();
      if (st == 'cancelled' || st == 'rejected' || st == 'condemned' || st == 'taken_back') {
        continue;
      }

      final isReleased = st == 'released' || st == 'completed' || req['released_at'] != null;
      if (isReleased) {
        final relDt = DateTime.tryParse(
          (req['released_at'] ?? req['updated_at'] ?? req['created_at'] ?? '').toString(),
        );
        if (_isSameLocalDay(relDt, now)) {
          completedTodayList.add(req);
        }
        continue;
      }

      // Active on the floor (Stages 1–5)
      activeList.add(req);

      // Upcoming scheduled bookings (today or future scheduled date)
      final sched = _parseScheduledDate(req);
      if (sched != null) {
        final schedDay = DateTime(sched.year, sched.month, sched.day);
        if (!schedDay.isBefore(todayStart)) {
          upcomingList.add(req);
        }
      }
    }

    upcomingList.sort((a, b) {
      final da = _parseScheduledDate(a) ?? DateTime(2100);
      final db = _parseScheduledDate(b) ?? DateTime(2100);
      return da.compareTo(db);
    });

    final List<Map<String, dynamic>> currentItems = _liveQueueTab == 'upcoming'
        ? upcomingList
        : (_liveQueueTab == 'completed' ? completedTodayList : activeList);
    final int overdueCount = activeList.where(_isRequestOverdue).length;

    const int defaultCap = 8;
    final bool hasMore = currentItems.length > defaultCap;
    final visibleItems = (!_liveQueueExpanded && hasMore)
        ? currentItems.take(defaultCap).toList()
        : currentItems;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header + Tabs
          Wrap(
            spacing: 12,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'Live Slaughter Floor Queue',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, size: 7, color: Color(0xFF16A34A)),
                            SizedBox(width: 4),
                            Text(
                              'Live',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF15803D),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (overdueCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFFFECACA)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.warning_amber_rounded, size: 12, color: Color(0xFFDC2626)),
                              const SizedBox(width: 4),
                              Text(
                                '$overdueCount Overdue',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Real-time status of active floor transactions, upcoming bookings, and completed releases',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Wrap(
                  spacing: 2,
                  children: [
                    _liveQueueTabPill('active', 'Active Now', activeList.length),
                    _liveQueueTabPill('upcoming', 'Upcoming Schedule', upcomingList.length),
                    _liveQueueTabPill('completed', 'Completed Today', completedTodayList.length),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Queue Body
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: visibleItems.isEmpty
                ? Container(
                    key: ValueKey('empty_$_liveQueueTab'),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          _liveQueueTab == 'completed'
                              ? Icons.check_circle_outline
                              : (_liveQueueTab == 'upcoming'
                                  ? Icons.event_available_outlined
                                  : Icons.fact_check_outlined),
                          size: 28,
                          color: const Color(0xFF94A3B8),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _liveQueueTab == 'active'
                              ? 'No active transactions on the slaughter floor right now.'
                              : (_liveQueueTab == 'upcoming'
                                  ? 'No upcoming scheduled slaughter bookings found.'
                                  : 'No completed releases recorded yet today.'),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF64748B),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    key: ValueKey('list_${_liveQueueTab}_${visibleItems.length}'),
                    builder: (context, constraints) {
                      final isCompact = constraints.maxWidth < 820;
                      return Column(
                        children: [
                          if (!isCompact)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: const Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Text('REFERENCE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text('DEALER / OWNER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text('SECTION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text('LIVESTOCK', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text('STAGE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text('TIME / SLOT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                                  ),
                                  SizedBox(width: 72),
                                ],
                              ),
                            ),
                          ...visibleItems.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final req = entry.value;
                            final isLast = idx == visibleItems.length - 1;
                            return _buildLiveQueueRow(req, isCompact: isCompact, isLast: isLast);
                          }),
                          if (hasMore) ...[
                            const SizedBox(height: 10),
                            Center(
                              child: TextButton.icon(
                                onPressed: () => setState(() => _liveQueueExpanded = !_liveQueueExpanded),
                                icon: Icon(
                                  _liveQueueExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                  size: 18,
                                ),
                                label: Text(
                                  _liveQueueExpanded
                                      ? 'Show less'
                                      : 'Show all (${currentItems.length})',
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF2D6A4F),
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _liveQueueTabPill(String tabKey, String label, int count) {
    final active = _liveQueueTab == tabKey;
    return GestureDetector(
      onTap: () {
        if (_liveQueueTab != tabKey) {
          setState(() {
            _liveQueueTab = tabKey;
            _liveQueueExpanded = false;
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? const Color(0xFF0F172A) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: active ? const Color(0xFF2D6A4F).withValues(alpha: 0.12) : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: active ? const Color(0xFF1B4332) : const Color(0xFF475569),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveQueueRow(
    Map<String, dynamic> req, {
    required bool isCompact,
    required bool isLast,
  }) {
    final stage = _resolveAdminQueueStage(req);
    final isOverdue = _liveQueueTab == 'active' && _isRequestOverdue(req);
    final refNo = (req['reference_no'] ?? 'REQ-${req['id'] ?? ''}').toString();
    final customer = (req['customer_name'] ?? req['owner_name'] ?? 'Walk-in Client').toString();
    final mark = (req['customer_marking'] ?? req['animal_tag'] ?? '').toString().trim();
    final isMarket = (req['request_type'] ?? req['section'] ?? '').toString().toLowerCase().contains('market');
    final species = (req['livestock_type'] ?? req['animal_type'] ?? 'Hog').toString();
    final heads = int.tryParse((req['animal_count'] ?? 1).toString()) ?? 1;
    final timeStr = _formatQueueRelativeTime(req, _liveQueueTab);

    final sectionBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isMarket ? const Color(0xFFEFF6FF) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isMarket ? 'Market' : 'Barangay',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isMarket ? const Color(0xFF1D4ED8) : const Color(0xFFB45309),
        ),
      ),
    );

    final stageBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: stage.bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        stage.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: stage.color,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );

    if (isCompact) {
      return InkWell(
        onTap: () => widget.onNavigate?.call(stage.moduleIndex),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: EdgeInsets.only(bottom: isLast ? 0 : 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$refNo • $customer',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  stageBadge,
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  sectionBadge,
                  if (mark.isNotEmpty)
                    Text('Mark: $mark', style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), fontWeight: FontWeight.w600)),
                  Text('$species ($heads hd)', style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569))),
                  Text('• $timeStr', style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: () => widget.onNavigate?.call(stage.moduleIndex),
      hoverColor: const Color(0xFFF8FAFC),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                refNo,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      customer,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (mark.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        mark,
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(alignment: Alignment.centerLeft, child: sectionBadge),
            ),
            Expanded(
              flex: 2,
              child: Text(
                '$species • $heads hd',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155), fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    stageBadge,
                    if (isOverdue)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Overdue',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFDC2626)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                timeStr,
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 72,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Open →',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2D6A4F),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  // =========================================================
  // CLERK DASHBOARD
  // =========================================================
  Widget _buildClerkDashboard() {
    final allTasks = _allRequests.where((r) => _clerkStageOf(r) != 0).toList();
    final stageCounts = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final r in allTasks) {
      final s = _clerkStageOf(r);
      stageCounts[s] = (stageCounts[s] ?? 0) + 1;
    }

    // Processed / Completed counts for each stage so processed records are visible even when pending is 0
    int processedReceivingCount = 0;
    int processedDocVerifCount = 0;
    int processedPaidCount = 0;
    int processedReleasedCount = 0;

    for (final r in _allRequests) {
      final st = (r['status'] ?? '').toString().toLowerCase();
      final isReleased = st == 'released' || r['released_at'] != null;
      bool isPaid = st == 'paid' || isReleased;
      final payments = r['payments'];
      if (!isPaid && payments != null) {
        if (payments is List && payments.isNotEmpty) {
          isPaid = payments.any((p) => (p as Map)['status'] == 'paid');
        } else if (payments is Map) {
          isPaid = payments['status'] == 'paid';
        }
      }

      if (st != 'pending' && st != 'rejected' && st != 'cancelled') {
        processedReceivingCount++;
      }
      if ([
        'doc_verified',
        'slaughter_started',
        'releasable',
        'mic_generated',
        'payment_pending',
        'paid',
        'out_for_delivery',
        'released',
        'completed',
      ].contains(st)) {
        processedDocVerifCount++;
      }
      if (isPaid) {
        processedPaidCount++;
      }
      if (isReleased) {
        processedReleasedCount++;
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildRoleHeaderRow(
              roleTitle: 'Welcome back, ${AppSettingsService.instance.profileName}',
              roleSubtitle: _realtimeSubtitle,
              badgeLabel: 'Clerk Portal',
              badgeColor: const Color(0xFF7C3AED),
            ),
            const SizedBox(height: 24),

            // ── 4 Summary Cards ──
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _buildClerkSummaryCard(
                      title: 'Pending Receiving',
                      count: stageCounts[1] ?? 0,
                      processedBadge: '$processedReceivingCount Processed',
                      subtitle: 'For review & tagging',
                      icon: Icons.assignment_outlined,
                      accent: const Color(0xFFD97706),
                      bg: const Color(0xFFFEF3C7),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildClerkSummaryCard(
                      title: 'Pending Doc Verification',
                      count: stageCounts[2] ?? 0,
                      processedBadge: '$processedDocVerifCount Verified',
                      subtitle: 'Permits to verify',
                      icon: Icons.verified_outlined,
                      accent: const Color(0xFF2563EB),
                      bg: const Color(0xFFDBEAFE),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildClerkSummaryCard(
                      title: 'Pending Billing & Payment',
                      count: stageCounts[4] ?? 0,
                      processedBadge: '$processedPaidCount Paid',
                      subtitle: 'Receipts & payments',
                      icon: Icons.credit_card_outlined,
                      accent: const Color(0xFF9333EA),
                      bg: const Color(0xFFF3E8FF),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildClerkSummaryCard(
                      title: 'Ready for Meat Release',
                      count: stageCounts[5] ?? 0,
                      processedBadge: '$processedReleasedCount Released',
                      subtitle: 'Ready for release',
                      icon: Icons.inventory_2_outlined,
                      accent: const Color(0xFF059669),
                      bg: const Color(0xFFD1FAE5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Today's clerk workflow ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Today's clerk workflow",
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Click any stage below to filter the live queue — Inspector stage shown for end-to-end visibility',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      if (_clerkStageFilter != 0)
                        TextButton.icon(
                          onPressed: () => setState(() => _clerkStageFilterVal = 0),
                          icon: const Icon(Icons.clear, size: 15),
                          label: const Text('Show All (Active & Processed)', style: TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (int i = 0; i < _clerkStages.length; i++) ...[
                          Expanded(child: _buildWorkflowStep(_clerkStages[i], stageCounts[_clerkStages[i].id] ?? 0)),
                          if (i < _clerkStages.length - 1) const SizedBox(width: 12),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Clerk Live Queue & Processed Requests Table ──
            _buildClerkQueueTableCard(),
            const SizedBox(height: 24),

            // ── Today's Cashiering Card ──
            _buildTodaysCashieringCard(),
            const SizedBox(height: 20),

            // ── Recent Clerk Activity Card ──
            _buildRecentClerkActivityCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildClerkQueueTableCard() {
    final List<Map<String, dynamic>> filteredRequests = _allRequests.where((req) {
      if (_clerkStageFilter == 0) return true;
      final activeStage = _clerkStageOf(req);
      if (activeStage == _clerkStageFilter) return true;
      // Also allow viewing processed/released items when stage 5 (Meat releasing) or stage 4 (Payment) is clicked
      final st = (req['status'] ?? '').toString().toLowerCase();
      if (_clerkStageFilter == 5 && (st == 'released' || req['released_at'] != null)) {
        return true;
      }
      return false;
    }).toList();

    // Sort active (unprocessed) items first, followed by processed/released items
    filteredRequests.sort((a, b) {
      final stageA = _clerkStageOf(a);
      final stageB = _clerkStageOf(b);
      final isActiveA = stageA != 0 ? 0 : 1;
      final isActiveB = stageB != 0 ? 0 : 1;
      if (isActiveA != isActiveB) return isActiveA.compareTo(isActiveB);
      final idA = int.tryParse(a['id']?.toString() ?? '0') ?? 0;
      final idB = int.tryParse(b['id']?.toString() ?? '0') ?? 0;
      return idB.compareTo(idA);
    });

    final displayList = filteredRequests.take(15).toList();
    final activeCount = _allRequests.where((r) => _clerkStageOf(r) != 0).length;
    final processedCount = _allRequests.where((r) => _clerkStageOf(r) == 0).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Clerk Requests Queue (Active & Processed)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Showing live unprocessed requests alongside completed & released records',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$activeCount Unprocessed',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$processedCount Processed',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (displayList.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  'No requests found for the selected stage.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: constraints.maxWidth),
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                        headingRowHeight: 44,
                        dataRowMinHeight: 52,
                        dataRowMaxHeight: 58,
                        horizontalMargin: 18,
                        columnSpacing: 24,
                        columns: const [
                          DataColumn(label: Text('Reference #', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF475569)))),
                          DataColumn(label: Text('Marking Tag', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF475569)))),
                          DataColumn(label: Text('Customer', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF475569)))),
                          DataColumn(label: Text('Livestock', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF475569)))),
                          DataColumn(label: Text('Stage / Status', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF475569)))),
                          DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF475569)))),
                        ],
                        rows: displayList.map((req) {
                          final refNo = _refOf(req);
                          final stage = _clerkStageOf(req);
                          final st = (req['status'] ?? '').toString().toLowerCase();

                          String statusText = 'Processed / Released';
                          Color badgeBg = const Color(0xFFDCFCE7);
                          Color badgeFg = const Color(0xFF15803D);
                          int targetModule = 5;
                          String btnLabel = 'View Release';

                          if (stage == 1) {
                            statusText = 'Pending Receiving';
                            badgeBg = const Color(0xFFFEF3C7);
                            badgeFg = const Color(0xFFB45309);
                            targetModule = 1;
                            btnLabel = 'Open Receiving';
                          } else if (stage == 2) {
                            statusText = 'Pending Doc Verification';
                            badgeBg = const Color(0xFFDBEAFE);
                            badgeFg = const Color(0xFF1D4ED8);
                            targetModule = 2;
                            btnLabel = 'Verify Docs';
                          } else if (stage == 3) {
                            statusText = 'Slaughter & Inspection (Inspector)';
                            badgeBg = const Color(0xFFE0F2FE);
                            badgeFg = const Color(0xFF0369A1);
                            targetModule = 0;
                            btnLabel = 'With Inspector';
                          } else if (stage == 4) {
                            statusText = 'Pending Billing & Payment';
                            badgeBg = const Color(0xFFF3E8FF);
                            badgeFg = const Color(0xFF7E22CE);
                            targetModule = 4;
                            btnLabel = 'Open Cashiering';
                          } else if (stage == 5) {
                            statusText = 'Ready for Meat Release';
                            badgeBg = const Color(0xFFD1FAE5);
                            badgeFg = const Color(0xFF047857);
                            targetModule = 5;
                            btnLabel = 'Release Meat';
                          } else if (st == 'cancelled' || st == 'rejected') {
                            statusText = 'Cancelled / Rejected';
                            badgeBg = const Color(0xFFFEE2E2);
                            badgeFg = const Color(0xFFB91C1C);
                            targetModule = 1;
                            btnLabel = 'View Request';
                          }

                          return DataRow(cells: [
                            DataCell(Text(refNo, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F5132)))),
                            DataCell(Text(req['marking']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w600))),
                            DataCell(Text(req['customer_name']?.toString() ?? '—')),
                            DataCell(Text('${req['animal_count'] ?? 1} head(s) ${req['livestock_type'] ?? ''}')),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(12)),
                                child: Text(statusText, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: badgeFg)),
                              ),
                            ),
                            DataCell(
                              targetModule == 0
                                  ? const Text('On Floor', style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600))
                                  : OutlinedButton(
                                      onPressed: () => widget.onNavigate?.call(targetModule),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: Text(btnLabel, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                                    ),
                            ),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTodaysCashieringCard() {
    final today = DateTime.now();
    double collectedToday = 0;
    double totalCollectedAll = 0;
    int orCountToday = 0;
    int totalOrCount = 0;
    double unpaidBilled = 0;
    int awaitingOrCount = 0;

    for (final req in _allRequests) {
      final st = (req['status'] ?? '').toString().toLowerCase();
      final payments = req['payments'];
      bool isPaid = st == 'paid' || st == 'released';
      double reqPaidAmountToday = 0;
      double reqPaidAmountAll = 0;
      double reqUnpaidAmount = 0;

      if (payments != null) {
        final pList = payments is List ? payments : [payments];
        for (final p in pList) {
          if (p is Map) {
            final pStatus = (p['status'] ?? '').toString().toLowerCase();
            final amt = double.tryParse(p['total_amount']?.toString() ?? '0') ?? 0;
            final dt = DateTime.tryParse(p['created_at']?.toString() ?? '')?.toLocal();
            if (pStatus == 'paid') {
              isPaid = true;
              reqPaidAmountAll += amt;
              if (dt == null || _isSameDay(dt, today)) {
                reqPaidAmountToday += amt;
              }
            } else {
              reqUnpaidAmount += amt;
            }
          }
        }
      }

      if (isPaid) {
        if (reqPaidAmountAll > 0) {
          totalCollectedAll += reqPaidAmountAll;
          totalOrCount++;
        }
        if (_isSameDay(req['released_at'], today) || reqPaidAmountToday > 0) {
          collectedToday += reqPaidAmountToday > 0 ? reqPaidAmountToday : reqPaidAmountAll;
          orCountToday++;
        }
      } else if (st == 'releasable' || st == 'mic_generated' || st == 'payment_pending') {
        if (reqUnpaidAmount > 0) {
          unpaidBilled += reqUnpaidAmount;
        } else {
          final animalType = req['livestock_type']?.toString() ?? 'Hog';
          final count = int.tryParse(req['animal_count']?.toString() ?? '1') ?? 1;
          final rates = AppSettingsService.instance.getFeeRatesForAnimal(animalType);
          final estFee = (rates.vetHealthCertFee +
                  rates.permitToSlaughterFee +
                  rates.facilityFee +
                  rates.corralFee +
                  rates.anteMortemFee +
                  rates.additionalFee) *
              count;
          unpaidBilled += estFee > 0 ? estFee : 340.0 * count;
        }
        awaitingOrCount++;
      }
    }

    final displayCollected = collectedToday > 0
        ? collectedToday
        : (totalCollectedAll > 0 ? totalCollectedAll : _totalRevenue);
    final displayOrCount = orCountToday > 0 ? orCountToday : totalOrCount;

    final formattedCollected = displayCollected.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
    final formattedUnpaid = unpaidBilled.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Today's Cashiering",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Collections & official receipts',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                  ),
                ],
              ),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Text(
                    '₱',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF059669),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        collectedToday > 0 ? 'Collected Today' : 'Total Collected Revenue',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '₱$formattedCollected',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        displayOrCount > 0
                            ? '$displayOrCount Official Receipt${displayOrCount == 1 ? '' : 's'} Issued'
                            : 'No collections recorded yet',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: displayOrCount > 0 ? const Color(0xFF059669) : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Unpaid / Billed',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '₱$formattedUnpaid',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFD97706),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        awaitingOrCount > 0
                            ? '$awaitingOrCount awaiting OR'
                            : 'No unpaid bills',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: awaitingOrCount > 0 ? const Color(0xFFD97706) : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentClerkActivityCard() {
    final List<Map<String, dynamic>> clerkLogs = [];

    // 1. Verified docs from real requests
    final verifiedReqs = _allRequests.where((r) {
      final st = (r['status'] ?? '').toString().toLowerCase();
      return st == 'doc_verified' || st == 'slaughter_started' || st == 'releasable' || st == 'paid';
    }).toList();

    if (verifiedReqs.isNotEmpty) {
      final req = verifiedReqs.first;
      final ref = _refOf(req);
      final cust = req['customer_name']?.toString() ?? 'Customer';
      final animal = '${req['animal_count'] ?? 1} ${req['livestock_type'] ?? 'Hogs'}';
      final dt = DateTime.tryParse(req['created_at']?.toString() ?? '')?.toLocal();
      clerkLogs.add({
        'dot': const Color(0xFF10B981),
        'title': 'Verified docs for $ref',
        'time': dt != null ? _formatTimeAgo(dt) : 'Today',
        'subtitle': '$cust • $animal',
      });
    }

    // 2. New online requests from real requests
    final pendingReqs = _allRequests.where((r) {
      final st = (r['status'] ?? '').toString().toLowerCase();
      return st == 'pending';
    }).toList();

    if (pendingReqs.isNotEmpty) {
      final req = pendingReqs.first;
      final brgy = (req['barangay'] ?? req['customer_name'] ?? 'Tabaco City').toString();
      final dt = DateTime.tryParse(req['created_at']?.toString() ?? '')?.toLocal();
      clerkLogs.add({
        'dot': const Color(0xFFF59E0B),
        'title': 'New online request from $brgy',
        'time': dt != null ? _formatTimeAgo(dt) : 'Today',
        'subtitle': 'Awaiting tag assignment',
      });
    }

    // 3. Paid orders / Issued ORs from real requests
    final paidReqs = _allRequests.where((r) {
      final st = (r['status'] ?? '').toString().toLowerCase();
      return st == 'paid' || st == 'released';
    }).toList();

    if (paidReqs.isNotEmpty) {
      final req = paidReqs.first;
      String receiptNo = 'OR-${req['id'].toString().padLeft(6, '0')}';
      double totalAmt = 0;
      final payments = req['payments'];
      if (payments != null) {
        final pList = payments is List ? payments : [payments];
        for (final p in pList) {
          if (p is Map) {
            if (p['receipt_number'] != null && p['receipt_number'].toString().isNotEmpty) {
              receiptNo = p['receipt_number'].toString();
            }
            totalAmt += double.tryParse(p['total_amount']?.toString() ?? '0') ?? 0;
          }
        }
      }
      final cust = req['customer_name']?.toString() ?? 'Customer';
      final animal = '${req['animal_count'] ?? 1} ${req['livestock_type'] ?? 'Livestock'}';
      final dt = DateTime.tryParse(req['created_at']?.toString() ?? '')?.toLocal();
      clerkLogs.add({
        'dot': const Color(0xFF3B82F6),
        'title': 'Issued OR #$receiptNo (₱${totalAmt > 0 ? totalAmt.toStringAsFixed(0) : '0'})',
        'time': dt != null ? _formatTimeAgo(dt) : 'Today',
        'subtitle': '$cust • $animal',
      });
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          const Text(
            'Recent clerk activity',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Latest operations logged today',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          if (clerkLogs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No operations logged today yet',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade400, fontWeight: FontWeight.w500),
                ),
              ),
            )
          else
            for (int i = 0; i < clerkLogs.length; i++) ...[
              _buildActivityItem(
                dotColor: clerkLogs[i]['dot'] as Color,
                title: clerkLogs[i]['title'] as String,
                timeAgo: clerkLogs[i]['time'] as String,
                subtitle: clerkLogs[i]['subtitle'] as String,
              ),
              if (i < clerkLogs.length - 1) const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Widget _buildActivityItem({
    required Color dotColor,
    required String title,
    required String timeAgo,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              Text(
                timeAgo,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClerkSummaryCard({
    required String title,
    required int count,
    String? processedBadge,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required Color bg,
  }) {
    final lower = title.toLowerCase();
    final Color valueColor = lower.contains('release')
        ? const Color(0xFF2563EB)
        : (lower.contains('billing') || lower.contains('payment')
            ? const Color(0xFF047857)
            : const Color(0xFF0F172A));
    final Color subColor = (lower.contains('billing') || lower.contains('payment'))
        ? const Color(0xFFD97706)
        : const Color(0xFF64748B);
    final String displaySubtitle = (processedBadge != null && processedBadge.trim().isNotEmpty)
        ? '$subtitle • $processedBadge'
        : subtitle;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
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
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: valueColor,
              letterSpacing: -0.5,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            displaySubtitle,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: subColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowStep(_ClerkStage s, int count) {
    final selected = _clerkStageFilter == s.id;
    final isInspector = s.id == 3;
    final bool hasItems = count > 0;

    final Color bgColor = selected
        ? const Color(0xFFDCFCE7)
        : (hasItems ? const Color(0xFFF0FDF4) : Colors.white);
    final Color borderColor = selected
        ? const Color(0xFF059669)
        : (hasItems ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0));
    final Color countColor = selected
        ? const Color(0xFF047857)
        : (hasItems ? const Color(0xFF059669) : const Color(0xFF94A3B8));
    final Color titleColor = hasItems ? const Color(0xFF1E293B) : const Color(0xFF64748B);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _clerkStageFilterVal = selected ? 0 : s.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: selected ? 1.8 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$count',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: countColor),
                  ),
                ),
                if (isInspector && count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFBBF7D0),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'On Floor',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF166534)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${s.id}. ${s.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: titleColor),
            ),
          ],
        ),
      ),
    );
  }

  int _clerkStageOf(Map<String, dynamic> req) {
    final st = (req['status'] ?? '').toString().toLowerCase();
    if (st == 'released' || req['released_at'] != null) return 0;
    bool isPaid = st == 'paid' || st == 'out_for_delivery';
    final payments = req['payments'];
    if (!isPaid && payments != null) {
      if (payments is List && payments.isNotEmpty) {
        isPaid = payments.any((p) => (p as Map)['status'] == 'paid');
      } else if (payments is Map) {
        isPaid = payments['status'] == 'paid';
      }
    }
    if (st == 'pending') return 1;
    if (st == 'approved') return 2;
    if (st == 'doc_verified' ||
        st == 'slaughter_started' ||
        st == 'anti_mortem_failed' ||
        st == 'delay_error' ||
        st == 'post_mortem_failed' ||
        st == 'confined' ||
        st == 'pickup_scheduled') {
      return 3;
    }
    if (isPaid) return 5;
    if (st == 'releasable' || st == 'mic_generated' || st == 'payment_pending') return 4;
    return 0;
  }

  bool _isSameDay(dynamic raw, DateTime target) {
    if (raw == null) return false;
    final dt = raw is DateTime ? raw : DateTime.tryParse(raw.toString());
    if (dt == null) return false;
    final local = dt.toLocal();
    return local.year == target.year && local.month == target.month && local.day == target.day;
  }

  String _refOf(Map<String, dynamic> req) {
    final id = req['id'];
    if (id == null) return 'MI-REQ';
    final yr = DateTime.now().year;
    return 'MI-$yr-${id.toString().padLeft(3, '0')}';
  }

  Widget _buildRoleHeaderRow({
    required String roleTitle,
    required String roleSubtitle,
    required String badgeLabel,
    required Color badgeColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      roleTitle,
                      style: const TextStyle(
                        fontSize: 24,
                        height: 32 / 24,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      badgeLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: badgeColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                roleSubtitle,
                style: const TextStyle(
                  fontSize: 14,
                  height: 20 / 14,
                  color: Color(0xFF475569),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        StaffNotificationBell(
          onNavigate: (m, [tab]) => widget.onNavigate?.call(m, tab),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // INSPECTOR: CONFINED LIVESTOCK MONITOR (2-DAY OBSERVATION)
  // ═══════════════════════════════════════════════════════════
  Map<String, dynamic>? _extractInspectionMap(Map<String, dynamic> req) {
    final raw = req['slaughter_inspection'];
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return Map<String, dynamic>.from(raw.first as Map);
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  DateTime _confinementStartOf(Map<String, dynamic> req) {
    final insp = _extractInspectionMap(req);
    final raw = insp?['updated_at'] ?? insp?['created_at'] ?? req['updated_at'] ?? req['created_at'];
    return DateTime.tryParse(raw?.toString() ?? '')?.toLocal() ?? DateTime.now();
  }

  String _formatConfinementDuration(Duration d) {
    if (d.inHours < 1) return '< 1h held';
    if (d.inDays < 1) return '${d.inHours}h held';
    final remH = d.inHours % 24;
    return remH > 0 ? '${d.inDays}d ${remH}h held' : '${d.inDays}d held';
  }

  String _cleanDashboardFindings(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'\[AM_PASSED_AT:[^\]]+\]\s*\|?\s*'), '')
        .replaceAll(RegExp(r'\[PHONE:[^\]]+\]\s*\|?\s*'), '')
        .trim();
    return cleaned.isEmpty || cleaned.toLowerCase() == 'null'
        ? 'Failed ante-mortem inspection — under mandatory 2-day observation'
        : cleaned;
  }

  Widget _buildInspectorConfinedMonitorCard() {
    final now = DateTime.now();
    final confinedList = _allRequests.where((req) {
      final st = (req['status'] ?? '').toString().toLowerCase();
      final insp = _extractInspectionMap(req);
      final anti = (insp?['anti_mortem'] ?? '').toString().toLowerCase();
      final post = (insp?['post_mortem'] ?? '').toString().toLowerCase();
      if (post == 'failed' || st == 'post_mortem_failed' || st == 'condemned') return false;
      if (post == 'passed' || ['releasable', 'paid', 'released', 'completed', 'cancelled', 'rejected', 'taken_back'].contains(st)) {
        return false;
      }
      return st == 'confined' || st == 'anti_mortem_failed' || anti == 'failed';
    }).toList();

    // Sort longest held first so >= 48h warnings always appear at the top
    confinedList.sort((a, b) => _confinementStartOf(a).compareTo(_confinementStartOf(b)));

    final int readyCount = confinedList.where((r) => now.difference(_confinementStartOf(r)).inHours >= 48).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: readyCount > 0 ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0),
          width: readyCount > 0 ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Icon(Icons.medical_services_outlined, size: 18, color: Color(0xFFB45309)),
                      Text(
                        'Confined Livestock Monitor — 2-Day Hold (${confinedList.length})',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      if (readyCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.warning_amber_rounded, size: 13, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                '$readyCount Ready for Evaluation (2+ Days)',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Livestock that failed ante-mortem inspection must be confined for 2 days before clearing for slaughter or condemnation',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => widget.onNavigate?.call(3),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF2D6A4F),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                child: const Text('Open Inspection →', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (confinedList.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF16A34A)),
                  SizedBox(width: 8),
                  Text(
                    'No livestock currently held in 2-day confinement.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 780;
                return Column(
                  children: confinedList.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final req = entry.value;
                    final isLast = idx == confinedList.length - 1;
                    final start = _confinementStartOf(req);
                    final elapsed = now.difference(start);
                    final isReady = elapsed.inHours >= 48;
                    final isDay2 = !isReady && elapsed.inHours >= 24;

                    final refNo = _refOf(req);
                    final customer = (req['customer_name'] ?? req['owner_name'] ?? 'Walk-in Client').toString();
                    final mark = (req['customer_marking'] ?? req['marking'] ?? req['animal_tag'] ?? '').toString().trim();
                    final species = (req['livestock_type'] ?? 'Livestock').toString();
                    final heads = int.tryParse((req['animal_count'] ?? 1).toString()) ?? 1;
                    final insp = _extractInspectionMap(req);
                    final findings = _cleanDashboardFindings(
                      (insp?['veterinary_findings'] ?? insp?['process_notes'] ?? req['notes'] ?? '').toString(),
                    );
                    final ageLabel = _formatConfinementDuration(elapsed);

                    final Color badgeBg = isReady
                        ? const Color(0xFFFEE2E2)
                        : (isDay2 ? const Color(0xFFFEF3C7) : const Color(0xFFDBEAFE));
                    final Color badgeFg = isReady
                        ? const Color(0xFFDC2626)
                        : (isDay2 ? const Color(0xFFB45309) : const Color(0xFF1D4ED8));
                    final String badgeText = isReady
                        ? 'WARNING • $ageLabel (Ready)'
                        : (isDay2 ? 'Day 2 of 2 • $ageLabel' : 'Day 1 of 2 • $ageLabel');

                    return Container(
                      margin: EdgeInsets.only(bottom: isLast ? 0 : 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isReady ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isReady ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: isCompact
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '$refNo • $customer',
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(999)),
                                      child: Text(badgeText, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: badgeFg)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '$species ($heads hd)${mark.isNotEmpty ? ' • Mark: $mark' : ''} • Held since ${DateFormat('MMM d, h:mm a').format(start)}',
                                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  findings,
                                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () => _showInspectorConfinementEvaluationDialog(req, elapsed),
                                    icon: const Icon(Icons.fact_check_outlined, size: 15),
                                    label: Text(isReady ? 'Evaluate Now (Due)' : 'Evaluate Confinement'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isReady ? const Color(0xFFDC2626) : const Color(0xFF2D6A4F),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            refNo,
                                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              customer,
                                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (mark.isNotEmpty) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                              ),
                                              child: Text(mark, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '$species ($heads hd) • Held since ${DateFormat('MMM d, h:mm a').format(start)}',
                                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    findings,
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(999)),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isReady) ...[
                                        Icon(Icons.warning_amber_rounded, size: 13, color: badgeFg),
                                        const SizedBox(width: 4),
                                      ],
                                      Text(badgeText, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: badgeFg)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: () => _showInspectorConfinementEvaluationDialog(req, elapsed),
                                  icon: const Icon(Icons.fact_check_outlined, size: 15),
                                  label: Text(isReady ? 'Evaluate Now' : 'Evaluate', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isReady ? const Color(0xFFDC2626) : const Color(0xFF2D6A4F),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                ),
                              ],
                            ),
                    );
                  }).toList(),
                );
              },
            ),
        ],
      ),
    );
  }

  void _showInspectorConfinementEvaluationDialog(Map<String, dynamic> req, Duration elapsed) {
    final refNo = _refOf(req);
    final customer = (req['customer_name'] ?? req['owner_name'] ?? 'Walk-in Client').toString();
    final species = (req['livestock_type'] ?? 'Livestock').toString();
    final heads = int.tryParse((req['animal_count'] ?? 1).toString()) ?? 1;
    final insp = _extractInspectionMap(req);
    final findings = _cleanDashboardFindings(
      (insp?['veterinary_findings'] ?? insp?['process_notes'] ?? req['notes'] ?? '').toString(),
    );
    final notesCtrl = TextEditingController();
    final bool isEarly = elapsed.inHours < 48;
    final int remainingHours = (48 - elapsed.inHours).clamp(0, 48);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.fact_check_outlined, color: Color(0xFF1B4332), size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Evaluate Confined Livestock — $refNo',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$customer • $species ($heads hd)', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text('Duration Held: ${_formatConfinementDuration(elapsed)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                      const SizedBox(height: 4),
                      Text('Ante-Mortem Findings: $findings', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
                if (isEarly) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 16, color: Color(0xFFB45309)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Early Evaluation Notice: ~$remainingHours hr(s) remaining in the mandatory 2-day (48h) observation hold.',
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFF92400E), fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: notesCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Veterinary Evaluation Notes / Condemnation Reason',
                    hintText: 'Required if condemning; optional notes if clearing for slaughter...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final reason = notesCtrl.text.trim();
              if (reason.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a condemnation reason before condemning.'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              Navigator.pop(ctx);
              await _inspectorCondemnFromConfinement(req, reason: reason);
            },
            icon: const Icon(Icons.gpp_bad_outlined, size: 16),
            label: const Text('Condemn Livestock'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC0392B),
              foregroundColor: Colors.white,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final notes = notesCtrl.text.trim();
              Navigator.pop(ctx);
              await _inspectorClearConfinement(req, notes: notes);
            },
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: const Text('Clear & Send to Slaughter'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E855A),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _inspectorClearConfinement(Map<String, dynamic> req, {String notes = ''}) async {
    try {
      final reqId = req['id'];
      final userId = req['user_id'];
      final livestockType = req['livestock_type'] ?? 'Livestock';
      final animalCount = req['animal_count'] ?? 1;
      final refNo = _refOf(req);
      final inspectorName = AppSettingsService.instance.profileName.isNotEmpty
          ? AppSettingsService.instance.profileName
          : 'Meat Inspector';

      await supabase.from('requests').update({'status': 'slaughter_started'}).eq('id', reqId);

      final existingInsp = await supabase.from('slaughter_inspection').select('id').eq('request_id', reqId).maybeSingle();
      final nowUtcIso = DateTime.now().toUtc().toIso8601String();
      final resolvedNotesBase = notes.isNotEmpty
          ? 'Cleared after 2-day confinement observation: $notes'
          : 'Cleared after 2-day confinement observation. Resumed active slaughter at Stunning stage.';
      final inspData = <String, dynamic>{
        'request_id': reqId,
        'anti_mortem': 'Passed',
        'process_stage': 'Stunning',
        'ante_mortem_passed_at': nowUtcIso,
        'inspector_name': inspectorName,
        'process_notes': '[AM_PASSED_AT:$nowUtcIso] $resolvedNotesBase',
      };
      try {
        if (existingInsp != null) {
          await supabase.from('slaughter_inspection').update(inspData).eq('request_id', reqId);
        } else {
          await supabase.from('slaughter_inspection').insert(inspData);
        }
      } catch (_) {
        inspData.remove('ante_mortem_passed_at');
        if (existingInsp != null) {
          await supabase.from('slaughter_inspection').update(inspData).eq('request_id', reqId);
        } else {
          await supabase.from('slaughter_inspection').insert(inspData);
        }
      }

      await NotificationService.sendNotificationSafely(
        supabase,
        userId: userId,
        title: '$livestockType — Cleared & Ready for Slaughter',
        message: 'Your $animalCount head(s) of $livestockType ($refNo) has been cleared after confinement and sent to active slaughter.',
        type: 'slaughter_started',
        referenceNo: refNo,
        data: {'request_id': reqId, 'reference_no': refNo, 'livestock_type': livestockType, 'process_stage': 'Stunning'},
      );

      await AuditLogService.instance.log(
        action: 'confinement_cleared_for_slaughter',
        module: 'Slaughter & Inspection',
        targetId: reqId?.toString(),
        targetRef: refNo,
        details: {'livestock': livestockType, 'heads': animalCount, 'notes': notes},
      );

      await _loadAllDashboardData(silent: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$refNo cleared for slaughter and moved to Stunning stage.'),
            backgroundColor: const Color(0xFF1E855A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear confinement: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _inspectorCondemnFromConfinement(Map<String, dynamic> req, {required String reason}) async {
    try {
      final reqId = req['id'];
      final userId = req['user_id'];
      final livestockType = req['livestock_type'] ?? 'Livestock';
      final animalCount = req['animal_count'] ?? 1;
      final refNo = _refOf(req);
      final inspectorName = AppSettingsService.instance.profileName.isNotEmpty
          ? AppSettingsService.instance.profileName
          : 'Meat Inspector';

      await supabase.from('requests').update({'status': 'post_mortem_failed'}).eq('id', reqId);

      final existingInsp = await supabase.from('slaughter_inspection').select('id').eq('request_id', reqId).maybeSingle();
      final inspData = <String, dynamic>{
        'request_id': reqId,
        'anti_mortem': 'Failed',
        'post_mortem': 'Failed',
        'process_stage': 'Condemned',
        'inspector_name': inspectorName,
        'condemnation_reason': reason,
        'process_notes': 'Condemned after 2-day confinement evaluation: $reason',
      };
      if (existingInsp != null) {
        await supabase.from('slaughter_inspection').update(inspData).eq('request_id', reqId);
      } else {
        await supabase.from('slaughter_inspection').insert(inspData);
      }

      await NotificationService.sendNotificationSafely(
        supabase,
        userId: userId,
        title: '$livestockType — Condemned Following Confinement',
        message: 'Following 2-day veterinary confinement and re-evaluation, your $animalCount head(s) of $livestockType ($refNo) was deemed unfit for slaughter and condemned ($reason).',
        type: 'post_mortem_failed',
        referenceNo: refNo,
        data: {'request_id': reqId, 'reference_no': refNo, 'livestock_type': livestockType, 'condemnation_reason': reason},
      );

      await AuditLogService.instance.log(
        action: 'confinement_condemned',
        module: 'Slaughter & Inspection',
        targetId: reqId?.toString(),
        targetRef: refNo,
        details: {'livestock': livestockType, 'heads': animalCount, 'reason': reason},
      );

      await _loadAllDashboardData(silent: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$refNo marked as Condemned. Customer notified.'),
            backgroundColor: const Color(0xFFC0392B),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to condemn livestock: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // =========================================================
  // INSPECTOR DASHBOARD
  // =========================================================
// ═══════════════════════════════════════════════════════════
  // INSPECTOR DASHBOARD (TODAY'S FLOOR WORKFLOW & QUEUE)
  // ═══════════════════════════════════════════════════════════
    
  Widget _buildInspectorDashboard() {
    final query = _queueCtrl.text.trim().toLowerCase();

    // Floor stages:
    // 1: Ante-mortem exam (st == 'doc_verified' AND arrived today/past)
    // 2: Stunning & dressing (st == 'slaughter_started')
    // 3: Post-mortem & weight (st == 'slaughter_started')
    // 4: Flagged / hold rail (st == 'anti_mortem_failed' || st == 'delay_error')
    // 5: MIC issued ('mic_generated', 'releasable', 'payment_pending', 'paid', 'released')

    bool isScheduledForFuture(Map<String, dynamic> r) {
      final pref = r['preferred_date']?.toString();
      if (pref == null || pref.isEmpty) return false;
      try {
        final date = DateTime.parse(pref);
        final today = DateTime.now();
        final todayMidnight = DateTime(today.year, today.month, today.day);
        final reqMidnight = DateTime(date.year, date.month, date.day);
        return reqMidnight.isAfter(todayMidnight);
      } catch (_) {
        return false;
      }
    }

    final allDocVerified = _allRequests.where((r) => (r['status'] ?? '').toString().toLowerCase() == 'doc_verified').toList();
    final inProgressList = _allRequests.where((r) => (r['status'] ?? '').toString().toLowerCase() == 'slaughter_started').toList();
    final flaggedList = _allRequests.where((r) {
      final st = (r['status'] ?? '').toString().toLowerCase();
      return [
        'anti_mortem_failed',
        'delay_error',
        'post_mortem_failed',
        'confined',
        'pickup_scheduled',
      ].contains(st);
    }).toList();
    final completedList = _allRequests.where((r) {
      final st = (r['status'] ?? '').toString().toLowerCase();
      return [
        'mic_generated',
        'releasable',
        'payment_pending',
        'paid',
        'out_for_delivery',
        'released',
        'completed',
        'condemned',
      ].contains(st);
    }).toList();

    final floorCounts = <int, int>{
      1: allDocVerified.length,
      2: inProgressList.length,
      3: inProgressList.length,
      4: flaggedList.length,
      5: completedList.length,
    };

    // Include both active floor tasks AND completed/processed inspections when viewing all (filter == 0)
    final List<Map<String, dynamic>> allActiveFloorTasks = [];
    if (_inspectorFloorFilter == 0) {
      allActiveFloorTasks.addAll(allDocVerified);
      allActiveFloorTasks.addAll(inProgressList);
      allActiveFloorTasks.addAll(flaggedList);
      allActiveFloorTasks.addAll(completedList);
    } else if (_inspectorFloorFilter == 1) {
      allActiveFloorTasks.addAll(allDocVerified);
    } else if (_inspectorFloorFilter == 2 || _inspectorFloorFilter == 3) {
      allActiveFloorTasks.addAll(inProgressList);
    } else if (_inspectorFloorFilter == 4) {
      allActiveFloorTasks.addAll(flaggedList);
    } else if (_inspectorFloorFilter == 5) {
      allActiveFloorTasks.addAll(completedList);
    }

    final inspectorTasks = query.isEmpty
        ? allActiveFloorTasks
        : allActiveFloorTasks.where((req) {
            final id = req['id'];
            final refNo = 'mi-${DateTime.now().year}-${id.toString().padLeft(3, '0')}';
            final customer = (req['customer_name'] ?? '').toString().toLowerCase();
            final marking = (req['marking'] ?? '').toString().toLowerCase();
            final livestock = (req['livestock_type'] ?? '').toString().toLowerCase();
            return refNo.contains(query) ||
                customer.contains(query) ||
                marking.contains(query) ||
                livestock.contains(query);
          }).toList();

    final totalActiveFloor = allDocVerified.length + inProgressList.length + flaggedList.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top Header Row with Search & Refresh ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Welcome back, ${AppSettingsService.instance.profileName}',
                              style: const TextStyle(
                                fontSize: 24,
                                height: 32 / 24,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDBEAFE),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFF93C5FD)),
                            ),
                            child: const Text(
                              'Inspector Portal',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1D4ED8),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _realtimeSubtitle,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 20 / 14,
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 260,
                      height: 38,
                      child: TextField(
                        controller: _queueCtrl,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(fontSize: 12.5, color: Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          hintText: 'Search ref # or marking tag...',
                          hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                          prefixIcon: const Icon(Icons.search, size: 17, color: Color(0xFF64748B)),
                          suffixIcon: _queueCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close, size: 14, color: Color(0xFF64748B)),
                                  padding: EdgeInsets.zero,
                                  onPressed: () {
                                    _queueCtrl.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF0F5132), width: 1.4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    StaffNotificationBell(
                      onNavigate: (m, [tab]) => widget.onNavigate?.call(m, tab),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── 4 Inspector Counter Cards (Equal Height) ──
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _buildInspectorSummaryCard(
                      title: 'Awaiting Ante-Mortem',
                      count: _inspectorAwaitingAnteCount,
                      subtitle: 'For floor exam',
                      icon: Icons.pets_outlined,
                      accentColor: const Color(0xFF0D9488),
                      iconColor: const Color(0xFF2563EB),
                      bgColor: const Color(0xFFDBEAFE),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildInspectorSummaryCard(
                      title: 'In-Progress Slaughter',
                      count: _inspectorInProgressCount,
                      subtitle: 'Pending post-mortem',
                      icon: Icons.content_cut_outlined,
                      accentColor: const Color(0xFFD97706),
                      iconColor: const Color(0xFFD97706),
                      bgColor: const Color(0xFFFEF3C7),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildInspectorSummaryCard(
                      title: 'Flagged / Awaiting Decision',
                      count: _inspectorFlaggedCount,
                      subtitle: 'Awaiting decision',
                      icon: Icons.warning_amber_rounded,
                      accentColor: const Color(0xFFDC2626),
                      iconColor: const Color(0xFFDC2626),
                      bgColor: const Color(0xFFFEE2E2),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildInspectorSummaryCard(
                      title: 'Completed Inspections',
                      count: _inspectorCompletedCount,
                      subtitle: 'Passed or condemned',
                      icon: Icons.verified_outlined,
                      accentColor: const Color(0xFF16A34A),
                      iconColor: const Color(0xFF16A34A),
                      bgColor: const Color(0xFFDCFCE7),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Confined Livestock Monitor (2-Day Observation Hold) ──
            _buildInspectorConfinedMonitorCard(),
            const SizedBox(height: 24),

            // ── Today's slaughterhouse floor workflow ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Today's slaughterhouse floor workflow",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Live livestock progression from holding pen to Meat Inspection Certificate (MIC) issuance',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _buildFloorWorkflowStep(
                            stepNumber: 1,
                            title: '1. Ante-mortem exam',
                            subtitle: 'Holding pen physical check',
                            count: floorCounts[1] ?? 0,
                            isSelected: _inspectorFloorFilter == 1,
                            onTap: () => setState(() => _inspectorFloorFilterVal = _inspectorFloorFilter == 1 ? 0 : 1),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildFloorWorkflowStep(
                            stepNumber: 2,
                            title: '2. Stunning & dressing',
                            subtitle: 'Active slaughter floor',
                            count: floorCounts[2] ?? 0,
                            isSelected: _inspectorFloorFilter == 2,
                            onTap: () => setState(() => _inspectorFloorFilterVal = _inspectorFloorFilter == 2 ? 0 : 2),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildFloorWorkflowStep(
                            stepNumber: 3,
                            title: '3. Post-mortem & weight',
                            subtitle: 'Visceral & carcass exam',
                            count: floorCounts[3] ?? 0,
                            isSelected: _inspectorFloorFilter == 3,
                            onTap: () => setState(() => _inspectorFloorFilterVal = _inspectorFloorFilter == 3 ? 0 : 3),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildFloorWorkflowStep(
                            stepNumber: 4,
                            title: '4. Flagged / hold rail',
                            subtitle: 'Suspect carcass review',
                            count: floorCounts[4] ?? 0,
                            isSelected: _inspectorFloorFilter == 4,
                            onTap: () => setState(() => _inspectorFloorFilterVal = _inspectorFloorFilter == 4 ? 0 : 4),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildFloorWorkflowStep(
                            stepNumber: 5,
                            title: '5. MIC issued',
                            subtitle: 'Cleared for billing & release',
                            count: floorCounts[5] ?? 0,
                            isSelected: _inspectorFloorFilter == 5,
                            onTap: () => setState(() => _inspectorFloorFilterVal = _inspectorFloorFilter == 5 ? 0 : 5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Pending Slaughter & Inspection Queue Table ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
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
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pending Slaughter & Inspection Queue',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Livestock currently requiring Ante-Mortem inspection, Post-Mortem carcass weighing, or Decision recording',
                            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDBEAFE),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$totalActiveFloor Active on Floor',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1D4ED8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (inspectorTasks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              query.isNotEmpty ? Icons.search_off_rounded : Icons.check_circle_outline,
                              size: 44,
                              color: query.isNotEmpty ? Colors.grey.shade400 : Colors.green.shade400,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              query.isNotEmpty
                                  ? 'No floor livestock matching "$query"'
                                  : 'No livestock currently waiting for inspection!',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: constraints.maxWidth),
                              child: DataTable(
                                headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                                headingRowHeight: 46,
                                dataRowMinHeight: 56,
                                dataRowMaxHeight: 62,
                                horizontalMargin: 20,
                                columnSpacing: 28,
                                columns: const [
                                  DataColumn(
                                    label: Text(
                                      'Reference #',
                                      style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Marking Tag',
                                      style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Customer',
                                      style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Livestock',
                                      style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Inspection Status',
                                      style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Action',
                                      style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                                    ),
                                  ),
                                ],
                                rows: inspectorTasks.map((req) {
                                  final id = req['id'];
                                  final refNo = 'MI-${DateTime.now().year}-${id.toString().padLeft(3, '0')}';
                                  final st = (req['status'] ?? '').toString().toLowerCase();
                                  final bool isFuture = isScheduledForFuture(req);
                                  final String? prefDate = req['preferred_date']?.toString();

                                  String stageLabel = 'Ready for Ante-Mortem / Slaughter';
                                  Color badgeBg = const Color(0xFFDBEAFE);
                                  Color badgeFg = const Color(0xFF1D4ED8);

                                  if (st == 'doc_verified' && isFuture) {
                                    String dateDesc = 'Future Date';
                                    if (prefDate != null) {
                                      try {
                                        final d = DateTime.parse(prefDate);
                                        final now = DateTime.now();
                                        final diffDays = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
                                        if (diffDays == 1) {
                                          dateDesc = 'Tomorrow (${DateFormat('MMM d').format(d)})';
                                        } else {
                                          dateDesc = DateFormat('MMM d, yyyy').format(d);
                                        }
                                      } catch (_) {}
                                    }
                                    stageLabel = 'Scheduled for $dateDesc — Awaiting Arrival';
                                    badgeBg = const Color(0xFFEDE9FE);
                                    badgeFg = const Color(0xFF6D28D9);
                                  } else if (st == 'slaughter_started') {
                                    stageLabel = 'In Dressing — Awaiting Carcass Weight';
                                    badgeBg = const Color(0xFFFEF3C7);
                                    badgeFg = const Color(0xFFB45309);
                                  } else if (st == 'anti_mortem_failed') {
                                    stageLabel = 'Ante-Mortem Issue — Record Decision';
                                    badgeBg = const Color(0xFFFEE2E2);
                                    badgeFg = const Color(0xFFB91C1C);
                                  } else if (st == 'delay_error') {
                                    stageLabel = 'Delayed — Record Decision';
                                    badgeBg = const Color(0xFFFEE2E2);
                                    badgeFg = const Color(0xFFB91C1C);
                                  } else if (['mic_generated', 'releasable', 'payment_pending', 'paid', 'released'].contains(st)) {
                                    stageLabel = 'MIC Issued — Ready for Cashier';
                                    badgeBg = const Color(0xFFDCFCE7);
                                    badgeFg = const Color(0xFF15803D);
                                  }

                                  return DataRow(cells: [
                                    DataCell(
                                      Text(
                                        refNo,
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F5132)),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        req['marking']?.toString() ?? '—',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    DataCell(Text(req['customer_name']?.toString() ?? '—')),
                                    DataCell(
                                      Text('${req['animal_count'] ?? 1} head(s) ${req['livestock_type'] ?? ''}'),
                                    ),
                                    DataCell(
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: badgeBg,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          stageLabel,
                                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: badgeFg),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      isFuture
                                          ? Tooltip(
                                              message: 'Livestock scheduled for a future date. Ante-mortem inspection can only be conducted upon physical arrival.',
                                              child: ElevatedButton.icon(
                                                onPressed: null,
                                                icon: const Icon(Icons.schedule, size: 14),
                                                label: const Text('Awaiting Arrival', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                                style: ElevatedButton.styleFrom(
                                                  disabledBackgroundColor: Colors.grey.shade200,
                                                  disabledForegroundColor: Colors.grey.shade500,
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                ),
                                              ),
                                            )
                                          : ElevatedButton.icon(
                                              onPressed: () => widget.onNavigate?.call(3),
                                              icon: const Icon(Icons.search, size: 14),
                                              label: const Text('Inspect Now', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFF0F5132),
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                            ),
                                    ),
                                  ]);
                                }).toList(),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Bottom Section: Needs attention & Recent floor activity ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildInspectorNeedsAttentionCard(
                    flaggedCount: flaggedList.length,
                    flaggedItems: flaggedList,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: _buildInspectorRecentFloorActivityCard(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInspectorSummaryCard({
    required String title,
    required int count,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required Color iconColor,
    required Color bgColor,
  }) {
    final lower = title.toLowerCase();
    final Color valueColor = lower.contains('flagged')
        ? const Color(0xFFDC2626)
        : (lower.contains('completed')
            ? const Color(0xFF047857)
            : (lower.contains('in-progress')
                ? const Color(0xFF2563EB)
                : const Color(0xFF0F172A)));
    final Color subColor = lower.contains('flagged')
        ? const Color(0xFFD97706)
        : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
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
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: valueColor,
              letterSpacing: -0.5,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: subColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloorWorkflowStep({
    required int stepNumber,
    required String title,
    required String subtitle,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final bool hasItems = count > 0;
    final Color bgColor = isSelected
        ? const Color(0xFFDCFCE7)
        : (hasItems ? const Color(0xFFF0FDF4) : Colors.white);
    final Color borderColor = isSelected
        ? const Color(0xFF059669)
        : (hasItems ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0));
    final Color countColor = isSelected
        ? const Color(0xFF047857)
        : (hasItems ? const Color(0xFF059669) : const Color(0xFF94A3B8));

    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: isSelected ? 1.8 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: countColor),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: hasItems ? const Color(0xFF1E293B) : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );

    if (!hasItems) {
      return child;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: child,
    );
  }

  Widget _buildInspectorNeedsAttentionCard({
    required int flaggedCount,
    required List<Map<String, dynamic>> flaggedItems,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          const Text(
            'Needs attention',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Carcasses or livestock waiting for veterinary disposition',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          if (flaggedCount == 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: Color(0xFFDCFCE7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_outline, color: Color(0xFF16A34A), size: 20),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No flagged carcasses on hold rail',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'All inspected livestock have passed ante-mortem standards today.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: flaggedItems.map((item) {
                final refNo = _refOf(item);
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Flagged: $refNo (${item['customer_name'] ?? 'Livestock'})',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF991B1B)),
                            ),
                            const Text('Requires Ante-Mortem examination or condemnation choice.', style: TextStyle(fontSize: 12, color: Color(0xFFB91C1C))),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () => widget.onNavigate?.call(3),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        child: const Text('Review', style: TextStyle(fontSize: 11.5)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildInspectorRecentFloorActivityCard() {
    final List<Map<String, dynamic>> activities = [];

    // 1. Requests ready for Ante-Mortem
    final anteReqs = _allRequests.where((r) => (r['status'] ?? '').toString().toLowerCase() == 'doc_verified').toList();
    if (anteReqs.isNotEmpty) {
      final req = anteReqs.first;
      final ref = _refOf(req);
      final dt = DateTime.tryParse(req['created_at']?.toString() ?? '')?.toLocal();
      activities.add({
        'dot': const Color(0xFF10B981),
        'title': '$ref cleared Doc Verification — ready for Ante-Mortem',
        'time': dt != null ? _formatTimeAgo(dt) : 'Today',
      });
    }

    // 2. Completed / MIC issued requests
    final completedReqs = _allRequests.where((r) {
      final st = (r['status'] ?? '').toString().toLowerCase();
      return ['mic_generated', 'releasable', 'payment_pending', 'paid', 'out_for_delivery', 'released', 'completed'].contains(st);
    }).toList();

    for (final req in completedReqs.take(3)) {
      final ref = _refOf(req);
      final count = req['animal_count'] ?? 1;
      final type = req['livestock_type'] ?? 'Livestock';
      final dt = DateTime.tryParse((req['released_at'] ?? req['created_at'])?.toString() ?? '')?.toLocal();
      activities.add({
        'dot': const Color(0xFFF59E0B),
        'title': 'MIC #$ref issued for $count $type (${req['customer_name'] ?? 'Customer'})',
        'time': dt != null ? _formatTimeAgo(dt) : 'Completed',
      });
    }

    if (activities.isEmpty) {
      activities.add({
        'dot': const Color(0xFF94A3B8),
        'title': 'No inspection operations logged yet',
        'time': '—',
      });
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          const Text(
            'Recent floor activity',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Latest veterinary inspections & MIC issuances',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < activities.length; i++) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF1F5F9)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: activities[i]['dot'] as Color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      activities[i]['title'] as String,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    activities[i]['time'] as String,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
            if (i < activities.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

}

class _ClerkStage {
  final int id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color bg;
  final int module;
  final String action;
  const _ClerkStage(this.id, this.title, this.subtitle, this.icon, this.color, this.bg, this.module, this.action);
}

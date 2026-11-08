import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import '../services/notification_service.dart';
import '../services/inspection_documents_pdf_generator.dart';
import '../services/app_settings_service.dart';
import '../services/regular_dealers_service.dart';

class ReceivingRequestsPage extends StatefulWidget {
  const ReceivingRequestsPage({super.key});

  @override
  State<ReceivingRequestsPage> createState() => _ReceivingRequestsPageState();
}

class _ReceivingRequestsPageState extends State<ReceivingRequestsPage> {
  final supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _allRequests = [];
  List<Map<String, dynamic>> _approvedRequests = [];
  List<Map<String, dynamic>> _pendingBarangay = [];
  List<Map<String, dynamic>> _pendingMarket = [];
  bool _isLoading = true;
  int _pendingTabIndex = 0; // 0 = Barangay, 1 = Market
  bool _userManuallySelectedTab = false;

  // Add scroll controllers for horizontal scrolling
  final ScrollController _approvedScrollController = ScrollController();
  final ScrollController _pendingScrollController = ScrollController();
  RealtimeChannel? _requestsChannel;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _loadRequests();
    _subscribeRequests();
    // Auto-poll every 3 seconds so incoming requests appear automatically in real-time
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _loadRequests(silent: true);
    });
  }

  void _subscribeRequests() {
    try {
      _requestsChannel = supabase
          .channel('public:admin-receiving-requests')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'requests',
            callback: (payload) {
              debugPrint('RECEIVING: Requests change detected, reloading...');
              if (mounted) _loadRequests(silent: true);
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Realtime error in ReceivingRequestsPage: $e');
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    if (_requestsChannel != null) {
      supabase.removeChannel(_requestsChannel!);
    }
    _searchController.dispose();
    _approvedScrollController.dispose();
    _pendingScrollController.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════
  //  LOAD DATA
  // ════════════════════════════════════════════
  Future<void> _loadRequests({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);
    try {
      if (AppSettingsService.instance.hasActiveStaffSession ||
          supabase.auth.currentSession == null) {
        await AppSettingsService.instance.ensureAdminAuthSession();
      }
      final allRequestsRaw = await supabase
          .from('requests')
          .select()
          .order('created_at', ascending: false);
      final allRequests = List<Map<String, dynamic>>.from(allRequestsRaw);

      try {
        await RegularDealersService.instance.reload();
        await RegularDealersService.instance.syncCustomersFromRequests(allRequests);
      } catch (_) {}

      // Sync walk-in claims and directory via `system_settings` so mobile customers
      // can claim walk-in orders by Reference # or Marking Tag despite `requests` RLS.
      await _syncWalkInBridge(allRequests);

      final approved = allRequests.where((r) => r['status'] == 'approved').toList();
      final pendingAll = allRequests.where((r) => r['status'] == 'pending').toList();

      if (mounted) {
        setState(() {
          _allRequests = List<Map<String, dynamic>>.from(allRequests);
          _approvedRequests = List<Map<String, dynamic>>.from(approved);
          _pendingBarangay = List<Map<String, dynamic>>.from(
            pendingAll.where((r) => r['request_type'] == 'barangay'),
          );
          _pendingMarket = List<Map<String, dynamic>>.from(
            pendingAll.where((r) => r['request_type'] == 'market'),
          );

          // If the user hasn't manually selected a tab, automatically focus
          // on the tab that actually has pending items (e.g. Market if Barangay is empty)
          if (!_userManuallySelectedTab) {
            if (_pendingBarangay.isEmpty && _pendingMarket.isNotEmpty) {
              _pendingTabIndex = 1;
            } else if (_pendingMarket.isEmpty && _pendingBarangay.isNotEmpty) {
              _pendingTabIndex = 0;
            }
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('═══ ERROR loading requests: $e ═══');
      if (mounted && !silent) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _syncWalkInBridge(List<Map<String, dynamic>> allRequests) async {
    try {
      // 1. Read any claims submitted by mobile users in `system_settings` ('walk_in_claims')
      final claimsRow = await supabase
          .from('system_settings')
          .select('value')
          .eq('key', 'walk_in_claims')
          .maybeSingle();

      Map<String, dynamic> claimsMap = {};
      if (claimsRow != null && claimsRow['value'] is Map) {
        claimsMap = Map<String, dynamic>.from(claimsRow['value']);
      }

      // Apply claimed user_ids to `requests` and `payments` using Admin privileges
      for (final req in allRequests) {
        final idStr = req['id']?.toString();
        if (idStr != null && claimsMap.containsKey(idStr)) {
          final claimedUid = claimsMap[idStr]?.toString();
          if (claimedUid != null &&
              claimedUid.isNotEmpty &&
              req['user_id']?.toString() != claimedUid) {
            req['user_id'] = claimedUid;
            try {
              await supabase
                  .from('requests')
                  .update({'user_id': claimedUid})
                  .eq('id', req['id']);
              await supabase
                  .from('payments')
                  .update({'user_id': claimedUid})
                  .eq('request_id', req['id']);
            } catch (_) {}
          }
        }
      }

      // 2. Publish active requests into `system_settings` ('walk_in_directory')
      final directoryList = allRequests.take(100).map((r) {
        return <String, dynamic>{
          'id': r['id'],
          'user_id': r['user_id'],
          'customer_name': r['customer_name'],
          'livestock_type': r['livestock_type'],
          'animal_count': r['animal_count'],
          'request_type': r['request_type'],
          'province': r['province'],
          'municipality': r['municipality'],
          'barangay': r['barangay'],
          'market_stall_number': r['market_stall_number'],
          'market_name': r['market_name'],
          'marking': r['marking'],
          'preferred_date': r['preferred_date'],
          'status': r['status'],
          'created_at': r['created_at'],
        };
      }).toList();

      await supabase.from('system_settings').upsert({
        'key': 'walk_in_directory',
        'value': directoryList,
      }, onConflict: 'key');
    } catch (e) {
      debugPrint('Walk-in bridge sync error: $e');
    }
  }

  // ════════════════════════════════════════════
  //  APPROVE REQUEST
  // ════════════════════════════════════════════
  Future<void> _approveRequest(Map<String, dynamic> request) async {
    try {
      final dealersService = RegularDealersService.instance;
      await dealersService.init();

      String customerName = (request['customer_name'] ?? '').toString().trim();
      String? existingMarking = (request['customer_marking'] ?? request['marking'])?.toString().trim();

      // Check if customer already has a locked marking in profiles or registry
      final requestedMarking = (request['customer_marking'] ?? request['marking'])?.toString().trim();
      final permanentMarking = await dealersService.getCustomerPermanentMarking(
        userId: request['user_id']?.toString(),
        customerName: customerName,
        requestedMarking: requestedMarking,
      );

      final matchedDealer = dealersService.findAuthoritativeDealer(
        userId: request['user_id']?.toString(),
        customerName: customerName,
      );
      if (matchedDealer != null) {
        customerName = matchedDealer.name; // Keep as official abattoir record name (e.g. D. CERILLO)
      }

      final specialInstruction = (request['special_instruction'] ?? '').toString().trim();
      if (permanentMarking != null && permanentMarking.isNotEmpty) {
        existingMarking = permanentMarking;
        if (specialInstruction.isNotEmpty) {
          if (!mounted) return;
          final proceed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              title: const Row(
                children: [
                  Icon(Icons.assignment_outlined, color: Color(0xFFB45309)),
                  SizedBox(width: 8),
                  Text('Review Special Instructions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Customer: $customerName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.speaker_notes, size: 14, color: Color(0xFFB45309)),
                            SizedBox(width: 5),
                            Text('Customer Special Instructions:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF92400E))),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(specialInstruction, style: const TextStyle(fontSize: 13, color: Color(0xFF78350F), height: 1.35)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Confirm and approve this slaughter request?', style: TextStyle(fontSize: 12, color: Colors.black87)),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2D6A4F), foregroundColor: Colors.white),
                  child: const Text('Proceed & Approve'),
                ),
              ],
            ),
          );
          if (proceed != true) return;
        }
      } else {
        // This is a NEW meat dealer or initial request without a locked marking yet.
        // Prompt Admin/Clerk with the dealer's requested marking (or suggested initials) to confirm & permanently lock.
        final defaultInitialMarking = (requestedMarking != null && requestedMarking.isNotEmpty)
            ? requestedMarking.toUpperCase()
            : dealersService.suggestMarkingForName(customerName);

        final markingCtrl = TextEditingController(text: defaultInitialMarking);
        if (!mounted) return;
        final confirmed = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.label_important, color: Color(0xFF2D6A4F)),
                SizedBox(width: 8),
                Text('Confirm Permanent Customer Marking Tag', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Customer: $customerName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                const Text(
                  'This is a new meat dealer with their initial slaughter request. Once confirmed, this marking tag will remain permanently locked for all future slaughter requests.',
                  style: TextStyle(fontSize: 12, color: Colors.black87),
                ),
                if (specialInstruction.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.speaker_notes, size: 14, color: Color(0xFFB45309)),
                            SizedBox(width: 4),
                            Text('Customer Special Instructions:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFF92400E))),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(specialInstruction, style: const TextStyle(fontSize: 12, color: Color(0xFF78350F), height: 1.3)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: markingCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Permanent Marking Tag',
                    border: OutlineInputBorder(),
                    helperText: 'Review requested tag and confirm to lock permanently.',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, markingCtrl.text.trim().toUpperCase()),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2D6A4F), foregroundColor: Colors.white),
                child: const Text('Confirm & Permanently Lock'),
              ),
            ],
          ),
        );

        if (confirmed == null || confirmed.isEmpty) return; // User cancelled
        existingMarking = confirmed;

        // Permanently record in regular_dealers registry and profiles
        await dealersService.assignPermanentMarking(
          name: customerName,
          markings: existingMarking,
          category: (request['request_type'] ?? 'barangay').toString(),
          userId: request['user_id']?.toString(),
        );
      }

      // 1. Update request status and locked marking
      await supabase
          .from('requests')
          .update({
            'status': 'approved',
            'marking': existingMarking,
          })
          .eq('id', request['id']);

      // 2. Format the preferred date for the notification message
      String dateStr = 'your requested date';
      if (request['preferred_date'] != null) {
        try {
          final date = DateTime.parse(request['preferred_date']);
          dateStr = DateFormat('MMMM d, yyyy').format(date);
        } catch (_) {
          dateStr = request['preferred_date'].toString();
        }
      }

      // 3. Send notification to customer safely
      await NotificationService.sendNotificationSafely(
        supabase,
        userId: request['user_id'],
        title: 'Approved Request',
        message:
            'Your slaughter request has been approved for $dateStr to bring your animals',
        type: 'request_approved',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Request approved — notification sent to customer'),
              ],
            ),
            backgroundColor: const Color(0xFF38A169),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }

      _loadRequests();
    } catch (e) {
      debugPrint('Error approving request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error approving request: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // ════════════════════════════════════════════
  //  REJECT REQUEST
  // ════════════════════════════════════════════
  Future<void> _rejectRequest(Map<String, dynamic> request) async {
    // Show confirmation dialog
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _RejectDialog(),
    );

    if (reason == null) return; // User cancelled

    try {
      // 1. Update request status
      await supabase
          .from('requests')
          .update({'status': 'rejected'})
          .eq('id', request['id']);

      // 2. Send notification to customer safely
      await NotificationService.sendNotificationSafely(
        supabase,
        userId: request['user_id'],
        title: 'Request Rejected',
        message: reason.isNotEmpty
            ? reason
            : 'Request denied — fully booked. Please select another date.',
        type: 'request_rejected',
        data: {
          'request_id': request['id'],
          'reference_no': _buildRefNo(request),
          'reason': reason.isNotEmpty
              ? reason
              : 'Request denied — fully booked. Please select another date.',
          'preferred_date': request['preferred_date'],
          'livestock_type': request['livestock_type'],
          'animal_count': request['animal_count'],
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Request rejected — notification sent to customer'),
              ],
            ),
            backgroundColor: const Color(0xFFE53E3E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }

      _loadRequests();
    } catch (e) {
      debugPrint('Error rejecting request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error rejecting request: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // ════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(now);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(
        children: [
          // ─── TOP HEADER ───
          _buildHeader(dateStr),
          // ─── CONTENT ───
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF2D6A4F),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadRequests,
                    color: const Color(0xFF2D6A4F),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSearchAndActions(),
                          const SizedBox(height: 24),
                          _buildApprovedSection(),
                          const SizedBox(height: 32),
                          _buildNewRequestsSection(),
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
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
      child: Row(
        children: [
          const Text(
            'Receiving & Inspection',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A202C),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              dateStr,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF4A5568),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  SEARCH + NEW ENTRY BUTTON
  // ════════════════════════════════════════════
  Widget _buildSearchAndActions() {
    return Row(
      children: [
        // Search
        SizedBox(
          width: 320,
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search by reference or customer...',
              hintStyle: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: Color(0xFFA0AEC0)),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF2D6A4F), width: 1.5),
              ),
            ),
          ),
        ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: () => _showNewReceivingEntryDialog(),
          icon: const Icon(Icons.add, size: 20),
          label: const Text('New Receiving Entry'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A202C),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 0,
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════
  //  APPROVED REQUESTS SECTION
  // ════════════════════════════════════════════
  Widget _buildApprovedSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Approve Request',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A202C),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Animals received for inspection with ante-mortem examination results',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Table
          _approvedRequests.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.inbox_outlined, size: 40, color: Colors.grey.shade300),
                        const SizedBox(height: 8),
                        Text(
                          'No approved requests yet',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final availableWidth = constraints.maxWidth;
                    final tableWidth = math.max(1000.0, availableWidth);
                    final colSpacing = (availableWidth > 1400)
                        ? 46.0
                        : (availableWidth > 1100 ? 32.0 : 20.0);

                    return Scrollbar(
                      controller: _approvedScrollController,
                      thumbVisibility: true,
                      trackVisibility: true,
                      child: SingleChildScrollView(
                        controller: _approvedScrollController,
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: tableWidth),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: DataTable(
                              headingRowColor: WidgetStateProperty.all(const Color(0xFFF7FAFC)),
                              headingTextStyle: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF4A5568),
                                fontSize: 13,
                              ),
                              dataTextStyle: const TextStyle(
                                color: Color(0xFF2D3748),
                                fontSize: 13,
                              ),
                              columnSpacing: colSpacing,
                              horizontalMargin: 24,
                              columns: const [
                                DataColumn(label: Text('Reference #')),
                                DataColumn(label: Text('City/Brgy.')),
                                DataColumn(label: Text('Customer')),
                                DataColumn(label: Text('Livestock')),
                                DataColumn(label: Text('Type')),
                                DataColumn(label: Text('Marking')),
                                DataColumn(label: Text('Date')),
                                DataColumn(label: Text('Actions')),
                              ],
                              rows: _approvedRequests.map((req) {
                                final refNo = _buildRefNo(req);
                                return DataRow(cells: [
                                  DataCell(Text(refNo, style: const TextStyle(fontWeight: FontWeight.w600))),
                                  DataCell(Text('${req['municipality'] ?? ''}/ ${req['barangay'] ?? ''}')),
                                  DataCell(
                                    Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(req['customer_name'] ?? ''),
                                        _buildSpecialInstructionBadge(
                                          context,
                                          req['special_instruction']?.toString(),
                                          customerName: req['customer_name']?.toString(),
                                          refNo: refNo,
                                        ),
                                      ],
                                    ),
                                  ),
                                  DataCell(Text(
                                    '${req['animal_count'] ?? 0} head(s)\n${req['livestock_type'] ?? ''}',
                                  )),
                                  DataCell(_buildTypeBadge(req['request_type'])),
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEBF8FF),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: const Color(0xFFBEE3F8)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.lock, size: 10, color: Color(0xFF2B6CB0)),
                                          const SizedBox(width: 4),
                                          Text(
                                            (req['customer_marking'] ?? req['marking'] ?? '—').toString(),
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF2B6CB0)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  DataCell(Text(_formatDate(req['preferred_date']))),
                                  DataCell(
                                    OutlinedButton(
                                      onPressed: () {
                                        // TODO: Update entry
                                      },
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                        side: BorderSide(color: Colors.grey.shade300),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        foregroundColor: const Color(0xFF2D3748),
                                        textStyle: const TextStyle(fontSize: 12),
                                      ),
                                      child: const Text('Update'),
                                    ),
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
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  NEW REQUESTS SECTION (BARANGAY / MARKET TABS)
  // ════════════════════════════════════════════
  Widget _buildNewRequestsSection() {
    final searchQuery = _searchController.text.toLowerCase();

    List<Map<String, dynamic>> currentList =
        _pendingTabIndex == 0 ? _pendingBarangay : _pendingMarket;

    // Apply search filter
    if (searchQuery.isNotEmpty) {
      currentList = currentList.where((r) {
        final name = (r['customer_name'] ?? '').toString().toLowerCase();
        final refNo = _buildRefNo(r).toLowerCase();
        return name.contains(searchQuery) || refNo.contains(searchQuery);
      }).toList();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tabs
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              children: [
                _buildTab('Barangay New (${_pendingBarangay.length})', 0),
                const SizedBox(width: 8),
                _buildTab('Market New (${_pendingMarket.length})', 1),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Section header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _pendingTabIndex == 0
                      ? 'Barangay New Requests'
                      : 'Market New Requests',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A202C),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _pendingTabIndex == 0
                      ? 'Verify information and assign tags to approve requests from barangay'
                      : 'Verify information and assign tags to approve requests from market',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Table
          currentList.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.inbox_outlined, size: 40, color: Colors.grey.shade300),
                        const SizedBox(height: 8),
                        Text(
                          'No pending requests',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final availableWidth = constraints.maxWidth;
                    final tableWidth = math.max(1100.0, availableWidth);
                    final colSpacing = (availableWidth > 1400)
                        ? 32.0
                        : (availableWidth > 1100 ? 24.0 : 16.0);

                    return Scrollbar(
                      controller: _pendingScrollController,
                      thumbVisibility: true,
                      trackVisibility: true,
                      child: SingleChildScrollView(
                        controller: _pendingScrollController,
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: tableWidth),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: DataTable(
                              headingRowColor: WidgetStateProperty.all(const Color(0xFFF7FAFC)),
                              headingTextStyle: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF4A5568),
                                fontSize: 13,
                              ),
                              dataTextStyle: const TextStyle(
                                color: Color(0xFF2D3748),
                                fontSize: 13,
                              ),
                              columnSpacing: colSpacing,
                    horizontalMargin: 24,
                    columns: [
                      const DataColumn(label: Text('Reference #')),
                      const DataColumn(label: Text('Customer Name')),
                      const DataColumn(label: Text('Municipality')),
                      const DataColumn(label: Text('Barangay')),
                      const DataColumn(label: Text('Livestock')),
                      const DataColumn(label: Text('Marking')),
                      const DataColumn(label: Text('Schedule Date')),
                      const DataColumn(label: Text('Document')),
                      const DataColumn(label: Text('Status')),
                      const DataColumn(label: Text('Action')),
                    ],
                    rows: currentList.map((req) {
                      final refNo = _buildRefNo(req);
                      final cName = (req['customer_name'] ?? '').toString();
                      final rawMark = (req['marking'] ?? req['customer_marking'] ?? '').toString();
                      final uId = req['user_id']?.toString();
                      final matchedDealer = RegularDealersService.instance.findAuthoritativeDealer(
                        userId: uId,
                        customerName: cName,
                        marking: rawMark,
                      );
                      final hasApprovedHistory = _allRequests.any((r) {
                        final st = (r['status'] ?? '').toString().toLowerCase();
                        if (st == 'pending' || st == 'rejected' || st == 'cancelled') return false;
                        final rUid = r['user_id']?.toString();
                        if (uId != null && uId.isNotEmpty && rUid != null && rUid.isNotEmpty) {
                          return rUid == uId;
                        }
                        return (r['customer_name'] ?? '').toString().trim().toLowerCase() ==
                            cName.trim().toLowerCase();
                      });
                      final isEstablishedRegular =
                          (matchedDealer != null && !matchedDealer.isNew) || hasApprovedHistory;
                      final mMark = (matchedDealer != null && matchedDealer.markings.trim().isNotEmpty)
                          ? matchedDealer.markings.trim()
                          : rawMark;
                      final hasLockedMarking =
                          matchedDealer != null && matchedDealer.markings.trim().isNotEmpty;
                      return DataRow(cells: [
                        DataCell(Text(refNo, style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(cName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  if (isEstablishedRegular) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE8F5E9),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: const Color(0xFF81C784)),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.verified, size: 10, color: Color(0xFF2E7D32)),
                                          SizedBox(width: 3),
                                          Text(
                                            'Regular Dealer',
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ] else ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDEF7EC),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: const Color(0xFF31C48D)),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.star, size: 10, color: Color(0xFF046C4E)),
                                          SizedBox(width: 3),
                                          Text(
                                            'New Dealer',
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF046C4E)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              _buildSpecialInstructionBadge(
                                context,
                                req['special_instruction']?.toString(),
                                customerName: cName,
                                refNo: refNo,
                              ),
                            ],
                          ),
                        ),
                        DataCell(Text(req['municipality'] ?? '')),
                        DataCell(Text(req['barangay'] ?? '')),
                        DataCell(Text(
                          '${req['animal_count'] ?? 0} head(s)\n${req['livestock_type'] ?? ''}',
                        )),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: hasLockedMarking ? const Color(0xFFE8F5E9) : const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: hasLockedMarking ? const Color(0xFFA5D6A7) : const Color(0xFFFDE68A)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  hasLockedMarking ? Icons.lock : Icons.edit_note,
                                  size: 11,
                                  color: hasLockedMarking ? const Color(0xFF2E7D32) : const Color(0xFFB45309),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  mMark.isNotEmpty ? mMark : '—',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: hasLockedMarking ? const Color(0xFF2E7D32) : const Color(0xFFB45309),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        DataCell(
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_formatDate(req['preferred_date'])),
                              if (req['rescheduled_date'] != null)
                                Container(
                                  margin: const EdgeInsets.only(top: 2),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFFFDE68A)),
                                  ),
                                  child: const Text('Rescheduled',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFF92400E),
                                          fontWeight: FontWeight.bold)),
                                ),
                            ],
                          ),
                        ),
                        DataCell(_buildDocumentBadges(req)),
                        DataCell(_buildStatusBadge('Pending')),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildActionButton(
                                label: 'Reject',
                                color: const Color(0xFFE53E3E),
                                bgColor: const Color(0xFFFFF5F5),
                                onTap: () => _rejectRequest(req),
                              ),
                              const SizedBox(width: 6),
                              _buildActionButton(
                                label: 'Approve',
                                color: Colors.white,
                                bgColor: const Color(0xFF38A169),
                                onTap: () => _approveRequest(req),
                              ),
                            ],
                          ),
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
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  HELPER WIDGETS
  // ════════════════════════════════════════════

  Widget _buildSpecialInstructionBadge(BuildContext context, String? instruction, {String? customerName, String? refNo}) {
    if (instruction == null || instruction.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final text = instruction.trim();

    return Tooltip(
      message: 'Customer Special Note: $text\n(Click to view details)',
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(6),
      ),
      child: InkWell(
        onTap: () => _showSpecialInstructionDialog(context, text, customerName: customerName, refNo: refNo),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.6)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.assignment_outlined, size: 12, color: Color(0xFFB45309)),
              SizedBox(width: 4),
              Text(
                'Special Note',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFB45309),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSpecialInstructionDialog(BuildContext context, String text, {String? customerName, String? refNo}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.assignment_outlined, color: Color(0xFFB45309), size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Customer Special Instructions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (refNo != null || customerName != null) ...[
              Row(
                children: [
                  if (refNo != null)
                    Text(refNo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF2D6A4F))),
                  if (refNo != null && customerName != null)
                    const Text(' • ', style: TextStyle(color: Colors.grey)),
                  if (customerName != null)
                    Text(customerName, style: const TextStyle(fontSize: 13, color: Color(0xFF4A5568), fontWeight: FontWeight.w500)),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Text(
                text,
                style: const TextStyle(fontSize: 13.5, color: Color(0xFF78350F), height: 1.4),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2D6A4F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isActive = _pendingTabIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _userManuallySelectedTab = true;
          _pendingTabIndex = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFF7FAFC) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? Colors.grey.shade300 : Colors.grey.shade200,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            color: isActive ? const Color(0xFF2D3748) : const Color(0xFF718096),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeBadge(String? type) {
    final isBarangay = type == 'barangay';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isBarangay
            ? const Color(0xFFE6FFFA)
            : const Color(0xFFEBF4FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isBarangay ? 'Barangay' : 'Market',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isBarangay
              ? const Color(0xFF234E52)
              : const Color(0xFF2B6CB0),
        ),
      ),
    );
  }


  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor;
    switch (status.toLowerCase()) {
      case 'approved':
        bgColor = const Color(0xFFC6F6D5);
        textColor = const Color(0xFF22543D);
        break;
      case 'rejected':
        bgColor = const Color(0xFFFED7D7);
        textColor = const Color(0xFF822727);
        break;
      default:
        bgColor = const Color(0xFFFEFCBF);
        textColor = const Color(0xFF744210);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildDocumentBadges(Map<String, dynamic> req) {
    final List<Widget> badges = [];

    if (req['barangay_certificate'] != null) {
      badges.add(_docBadge('Barangay Cert'));
    }
    if (req['business_permit'] != null) {
      badges.add(_docBadge('Business Permit'));
    }
    if (req['proof_of_ownership'] != null) {
      badges.add(_docBadge('Proof of Ownership'));
    }
    if (req['vet_certificate'] != null) {
      badges.add(_docBadge('Vet Certificate'));
    }

    if (badges.isEmpty) {
      return const Text('—', style: TextStyle(color: Color(0xFFA0AEC0)));
    }

    return Wrap(spacing: 4, runSpacing: 4, children: badges);
  }

  Widget _docBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, color: Color(0xFF4A5568)),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  DATA HELPERS
  // ════════════════════════════════════════════
  String _buildRefNo(Map<String, dynamic> req) {
    final id = req['id'];
    final year = DateTime.now().year;
    return 'MI-$year-${id.toString().padLeft(3, '0')}';
  }

  String _formatDate(dynamic dateVal) {
    if (dateVal == null) return '—';
    try {
      final date = DateTime.parse(dateVal.toString());
      return DateFormat('dd/MM/yyyy').format(date);
    } catch (_) {
      return dateVal.toString();
    }
  }

  // ════════════════════════════════════════════
  //  NEW RECEIVING ENTRY DIALOG
  // ════════════════════════════════════════════
  void _showNewReceivingEntryDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _NewReceivingEntryDialog(
        supabase: supabase,
        onSaved: _loadRequests,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  NEW RECEIVING ENTRY DIALOG
// ═══════════════════════════════════════════════════════════
class _CustomerLookupItem {
  final String name;
  final String markings;
  final String category; // 'market' or 'barangay'
  final String? phone;
  final String? municipality;
  final String? barangay;
  final String? stallNumber;
  final String? storeName;
  final String? usualAnimalType;
  final bool isRegularDealer;
  final String? userId;

  _CustomerLookupItem({
    required this.name,
    required this.markings,
    required this.category,
    this.phone,
    this.municipality,
    this.barangay,
    this.stallNumber,
    this.storeName,
    this.usualAnimalType,
    this.isRegularDealer = false,
    this.userId,
  });
}

class _NewReceivingEntryDialog extends StatefulWidget {
  final dynamic supabase;
  final VoidCallback onSaved;
  const _NewReceivingEntryDialog({required this.supabase, required this.onSaved});

  @override
  State<_NewReceivingEntryDialog> createState() => _NewReceivingEntryDialogState();
}

const List<Map<String, String>> _albayMunicipalities = [
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

const List<String> _tabacoBarangays = [
  "Agnas", "Bacolod", "Bangkilingan", "Bantayan", "Baranghawon", "Basagan", "Basud (Pob.)",
  "Bogñabong", "Bombon (Pob.)", "Bonot", "San Isidro", "Buang", "Buhian", "Cabagñan",
  "Cobo", "Comon", "Cormidal", "Divino Rostro (Pob.)", "Fatima", "Guinobat", "Hacienda",
  "Magapo", "Mariroc", "Matagbac", "Oras", "Oson", "Panal", "Pawa", "Pinagbobong",
  "Quinale Cabasan (Pob.)", "Quinastillojan", "Rawis", "Sagurong", "Salvacion",
  "San Antonio", "San Carlos", "San Juan (Pob.)", "San Lorenzo", "San Ramon",
  "San Roque", "San Vicente", "Santo Cristo (Pob.)", "Sua-Igot", "Tabiguian",
  "Tagas", "Tayhi (Pob.)", "Visita"
];

class _NewReceivingEntryDialogState extends State<_NewReceivingEntryDialog> {
  bool _isBarangay = true;
  bool _isSaving = false;

  final _customerNameCtrl = TextEditingController();
  final _contactNumberCtrl = TextEditingController();
  final _animalCountCtrl = TextEditingController();
  final _markingCtrl = TextEditingController();

  final FocusNode _customerNameFocus = FocusNode();
  final FocusNode _animalCountFocus = FocusNode();

  // PSGC API address state (instant Albay defaults)
  List _municipalities = List.from(_albayMunicipalities);
  List _barangays = [];
  final String _selectedProvince = 'Albay';
  final String _selectedProvinceCode = '050500000';
  String? _selectedMunicipality;
  String? _selectedMunicipalityCode;
  String? _selectedBarangay;
  bool _isLoadingBarangays = false;

  String? _selectedAnimalType;
  final List<String> _animalTypes = ['Cattle', 'Carabao', 'Hog', 'Goat', 'Sheep'];

  List<_CustomerLookupItem> _lookupDirectory = [];
  _CustomerLookupItem? _selectedCustomer;
  bool _isMarkingLocked = false;
  bool _isSeparateFacility = false;
  String _selectedEmergencyCause = 'Heat Stroke';
  final List<String> _emergencyCauses = const [
    'Heat Stroke',
    'Transit Stress',
    'Accidental / Transit Injury',
    'Other Non-Infectious Cause',
  ];

  @override
  void initState() {
    super.initState();
    _loadMunicipalities(_selectedProvinceCode);
    _loadRegisteredCustomers();
  }

  Future<void> _loadRegisteredCustomers() async {
    try {
      final dealersService = RegularDealersService.instance;
      await dealersService.init();
      final allDealers = dealersService.allDealers;

      // 1. Fetch recent requests to extract past phone, address, and animal types
      final Map<String, Map<String, dynamic>> historyByName = {};
      try {
        final reqsRes = await widget.supabase
            .from('requests')
            .select('customer_name, contact_number, livestock_type, municipality, barangay, market_stall_number, market_name, marking, customer_marking, request_type, user_id')
            .order('created_at', ascending: false)
            .limit(250);

        if (reqsRes is List) {
          for (final r in reqsRes) {
            final rawName = (r['customer_name'] ?? '').toString().trim().toUpperCase();
            if (rawName.isEmpty) continue;
            if (!historyByName.containsKey(rawName)) {
              historyByName[rawName] = Map<String, dynamic>.from(r);
            }
          }
        }
      } catch (err) {
        debugPrint('Notice loading request history: $err');
      }

      // 2. Fetch profiles
      final Map<String, Map<String, dynamic>> profilesByName = {};
      try {
        final res = await widget.supabase
            .from('profiles')
            .select('id, display_name, phone_number, address');
        if (res is List) {
          for (final p in res) {
            final dName = (p['display_name'] ?? '').toString().trim().toUpperCase();
            if (dName.isNotEmpty) {
              profilesByName[dName] = Map<String, dynamic>.from(p);
            }
          }
        }
      } catch (e) {
        debugPrint('Notice loading profiles: $e');
      }

      final List<_CustomerLookupItem> directory = [];
      final Set<String> processedNames = {};

      // A. Populate from registered Regular Dealers (all Market & Barangay dealers)
      for (final dealer in allDealers) {
        final upper = dealer.name.trim().toUpperCase();
        processedNames.add(upper);

        final hist = historyByName[upper];
        final prof = profilesByName[upper];

        final phone = dealer.phone ??
            hist?['contact_number']?.toString() ??
            prof?['phone_number']?.toString();

        final usualAnimal = hist?['livestock_type']?.toString();
        final mun = hist?['municipality']?.toString();
        final brgy = hist?['barangay']?.toString();
        final stall = hist?['market_stall_number']?.toString();
        final store = hist?['market_name']?.toString();
        final uid = dealer.userId ?? hist?['user_id']?.toString() ?? prof?['id']?.toString();

        directory.add(_CustomerLookupItem(
          name: dealer.name,
          markings: dealer.markings,
          category: dealer.category,
          phone: phone,
          municipality: mun,
          barangay: brgy,
          stallNumber: stall,
          storeName: store,
          usualAnimalType: usualAnimal,
          isRegularDealer: true,
          userId: uid,
        ));
      }

      // B. Add returning customers from requests who aren't in the default dealers roster
      historyByName.forEach((upperName, hist) {
        if (!processedNames.contains(upperName)) {
          processedNames.add(upperName);
          final rawName = hist['customer_name']?.toString() ?? upperName;
          final mark = (hist['customer_marking'] ?? hist['marking'] ?? '').toString();
          final cat = (hist['request_type'] ?? 'barangay').toString().toLowerCase();
          final phone = hist['contact_number']?.toString();
          final mun = hist['municipality']?.toString();
          final brgy = hist['barangay']?.toString();
          final stall = hist['market_stall_number']?.toString();
          final store = hist['market_name']?.toString();
          final usualAnimal = hist['livestock_type']?.toString();
          final uid = hist['user_id']?.toString();

          directory.add(_CustomerLookupItem(
            name: rawName,
            markings: mark,
            category: cat,
            phone: phone,
            municipality: mun,
            barangay: brgy,
            stallNumber: stall,
            storeName: store,
            usualAnimalType: usualAnimal,
            isRegularDealer: false,
            userId: uid,
          ));
        }
      });

      if (mounted) {
        setState(() {
          _lookupDirectory = directory;
        });
      }
    } catch (e) {
      debugPrint('Error loading customer directory: $e');
    }
  }

  void _onCustomerSelected(_CustomerLookupItem item) {
    setState(() {
      _selectedCustomer = item;
      _customerNameCtrl.text = item.name;

      if (item.markings.isNotEmpty) {
        _markingCtrl.text = item.markings;
        _isMarkingLocked = true;
      } else {
        _isMarkingLocked = false;
      }

      if (item.phone != null && item.phone!.isNotEmpty) {
        _contactNumberCtrl.text = item.phone!;
      }

      // Switch category
      final isBrgy = item.category != 'market';
      _isBarangay = isBrgy;

      if (isBrgy) {
        // Barangay customer
        if (item.municipality != null && item.municipality!.isNotEmpty) {
          _selectedMunicipality = item.municipality;
          _loadBarangays(_selectedMunicipalityCode ?? "050517000");
        }
        if (item.barangay != null && item.barangay!.isNotEmpty) {
          _selectedBarangay = item.barangay;
        }
      }

      // Pre-select usual animal type
      if (item.usualAnimalType != null && item.usualAnimalType!.isNotEmpty) {
        final match = _animalTypes.firstWhere(
          (t) => t.toLowerCase() == item.usualAnimalType!.toLowerCase(),
          orElse: () => 'Hog',
        );
        _selectedAnimalType = match;
      } else {
        _selectedAnimalType ??= 'Hog';
      }
    });

    // Advance focus to animal count
    Future.microtask(() {
      if (mounted) _animalCountFocus.requestFocus();
    });
  }

  Future<void> _loadMunicipalities(String provinceCode) async {
    try {
      final response = await http.get(
        Uri.parse('https://psgc.gitlab.io/api/provinces/$provinceCode/cities-municipalities/'),
      ).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final list = jsonDecode(response.body);
        if (mounted && list is List && list.isNotEmpty) {
          setState(() {
            _municipalities = list;
          });
        }
      }
    } catch (e) {
      debugPrint('Notice: Using pre-bundled Albay municipalities: $e');
      if (mounted && _municipalities.isEmpty) {
        setState(() {
          _municipalities = List.from(_albayMunicipalities);
        });
      }
    }
  }

  Future<void> _loadBarangays(String municipalityCode) async {
    // If Tabaco City, use instant pre-bundled barangays
    if (municipalityCode == "050517000" || _selectedMunicipality == "City of Tabaco") {
      setState(() {
        _barangays = _tabacoBarangays.map((name) => {'name': name}).toList();
        _selectedBarangay = null;
        _isLoadingBarangays = false;
      });
      return;
    }

    setState(() {
      _isLoadingBarangays = true;
      _barangays = [];
      _selectedBarangay = null;
    });
    try {
      final response = await http.get(
        Uri.parse('https://psgc.gitlab.io/api/cities-municipalities/$municipalityCode/barangays/'),
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final list = jsonDecode(response.body);
        if (mounted && list is List) {
          setState(() {
            _barangays = list;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading barangays: $e');
    } finally {
      if (mounted) setState(() => _isLoadingBarangays = false);
    }
  }

  @override
  void dispose() {
    _customerNameCtrl.dispose();
    _contactNumberCtrl.dispose();
    _animalCountCtrl.dispose();
    _markingCtrl.dispose();
    _customerNameFocus.dispose();
    _animalCountFocus.dispose();
    super.dispose();
  }

  Future<void> _saveRecord() async {
    if (_customerNameCtrl.text.trim().isEmpty ||
        _selectedAnimalType == null ||
        _animalCountCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all required fields')),
      );
      return;
    }

    if (_isBarangay &&
        (_selectedMunicipality == null || _selectedBarangay == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select Municipality and Barangay')),
      );
      return;
    }

    if (_markingCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a unique marking for the livestock')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await AppSettingsService.instance.ensureAdminAuthSession();
      final markingInput = _markingCtrl.text.trim();
      final currentEnteredName = _customerNameCtrl.text.trim().toUpperCase();
      final conflicting = await widget.supabase
          .from('requests')
          .select('id, marking, status, customer_name')
          .ilike('marking', markingInput)
          .not('status', 'in', '("completed","cancelled","rejected","released")')
          .limit(1);

      if (conflicting.isNotEmpty) {
        final existingName = (conflicting[0]['customer_name'] ?? '').toString().trim().toUpperCase();
        if (existingName.isNotEmpty && existingName != currentEnteredName) {
          setState(() => _isSaving = false);
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Marking In Use by Another Customer'),
                ],
              ),
              content: Text(
                "The marking '$markingInput' is already currently active for customer '$existingName'.\n\n"
                "Please assign a distinct marking tag to avoid confusing animals on the floor.",
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E855A)),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          return;
        }
      }

      String? matchedUserId = _selectedCustomer?.userId;
      if (matchedUserId == null) {
        final enteredName = _customerNameCtrl.text.trim().toLowerCase();
        for (final cust in _lookupDirectory) {
          if (cust.name.trim().toLowerCase() == enteredName && cust.userId != null) {
            matchedUserId = cust.userId;
            break;
          }
        }
      }

      final contactStr = _contactNumberCtrl.text.trim();
      final basePayload = <String, dynamic>{
        'user_id': ?matchedUserId,
        'request_type': _isBarangay ? 'barangay' : 'market',
        'customer_name': _customerNameCtrl.text.trim(),
        'livestock_type': _selectedAnimalType,
        'animal_count': int.tryParse(_animalCountCtrl.text.trim()) ?? 0,
        'province': _isBarangay ? _selectedProvince : null,
        'municipality': _isBarangay ? _selectedMunicipality : null,
        'barangay': _isBarangay ? _selectedBarangay : null,
        'market_stall_number': null,
        'market_name': null,
        'marking': _markingCtrl.text.trim(),
        'preferred_date': DateTime.now().toIso8601String().split('T')[0], // today's date
        'status': _isSeparateFacility ? 'slaughter_started' : 'approved', // Separate Facility bypasses Doc Verification directly into Slaughter & Inspection
      };

      Map<String, dynamic> insertedRow;
      try {
        insertedRow = await widget.supabase
            .from('requests')
            .insert({
              ...basePayload,
              if (contactStr.isNotEmpty) 'contact_number': contactStr,
            })
            .select()
            .single();
      } catch (err) {
        debugPrint('Direct insert error: $err. Trying with admin session and auth fallback...');
        await AppSettingsService.instance.ensureAdminAuthSession();
        final currentAdminUid = widget.supabase.auth.currentUser?.id;
        try {
          insertedRow = await widget.supabase
              .from('requests')
              .insert({
                ...basePayload,
                if (contactStr.isNotEmpty) 'contact_number': contactStr,
                'user_id': basePayload['user_id'] ?? currentAdminUid,
              })
              .select()
              .single();
        } catch (_) {
          insertedRow = await widget.supabase
              .from('requests')
              .insert({
                ...basePayload,
                'user_id': currentAdminUid,
              })
              .select()
              .single();
        }
      }

      final reqId = insertedRow['id'];
      final refNo = 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';
      final destOrOrigin = _isBarangay
          ? '${_selectedBarangay ?? ''}, ${_selectedMunicipality ?? 'Tabaco City'}, $_selectedProvince'
          : 'Tabaco Public Market';

      // If Separate Facility (Emergency Slaughter), create slaughter_inspection row & notify linked account
      if (_isSeparateFacility) {
        try {
          await widget.supabase.from('slaughter_inspection').insert({
            'request_id': reqId,
            'anti_mortem': 'Separate Facility',
            'process_stage': 'Separate Facility (Weighing)',
            'post_mortem': 'Pending',
            'process_notes':
                '[SEPARATE FACILITY - EMERGENCY SLAUGHTER | Cause: $_selectedEmergencyCause] Walk-in livestock arrived deceased due to non-infectious cause ($_selectedEmergencyCause). Routed to Separate Facility for immediate slaughter.',
          });
        } catch (inspErr) {
          debugPrint('Error inserting separate facility inspection row: $inspErr');
        }

        if (matchedUserId != null) {
          final livestockType = _selectedAnimalType ?? 'Livestock';
          final animalCount = int.tryParse(_animalCountCtrl.text.trim()) ?? 1;
          await NotificationService.sendNotificationSafely(
            widget.supabase,
            userId: matchedUserId,
            title: 'Separate Facility — Emergency Slaughter',
            message:
                'Your $animalCount head(s) of $livestockType ($refNo) arrived deceased due to $_selectedEmergencyCause (non-infectious) and is being processed immediately in the Separate Facility, bypassing the standard slaughterhouse queue.',
            type: 'separate_facility_slaughter',
            data: {
              'request_id': reqId,
              'livestock_type': livestockType,
              'animal_count': animalCount,
              'emergency_cause': _selectedEmergencyCause,
              'facility': 'Separate Facility',
            },
          );
        }
      }

      // Ensure newly entered walk-in meat dealer is permanently locked in registry
      try {
        final dealersService = RegularDealersService.instance;
        await dealersService.init();
        await dealersService.assignPermanentMarking(
          name: _customerNameCtrl.text.trim(),
          markings: _markingCtrl.text.trim(),
          category: _isBarangay ? 'barangay' : 'market',
          phone: contactStr.isNotEmpty ? contactStr : null,
          userId: matchedUserId,
        );
      } catch (err) {
        debugPrint('Note on auto-locking walk-in dealer marking: $err');
      }

      if (mounted) {
        widget.onSaved();
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => _WalkInClaimStubDialog(
            refNo: refNo,
            marking: _markingCtrl.text.trim(),
            customerName: _customerNameCtrl.text.trim(),
            contactNumber: contactStr,
            livestockType: _selectedAnimalType ?? 'Hog',
            animalCount: _animalCountCtrl.text.trim(),
            requestType: _isBarangay ? 'Barangay' : 'Market',
            destinationOrOrigin: destOrOrigin,
            isLinkedToAccount: matchedUserId != null,
            isSeparateFacility: _isSeparateFacility,
            emergencyCause: _isSeparateFacility ? _selectedEmergencyCause : null,
          ),
        );
        if (mounted) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving record: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──
              const Text(
                'New Animal Receiving & Inspection',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A202C)),
              ),
              const SizedBox(height: 4),
              const Text(
                'Enter customer and animal details for the new receiving entry.',
                style: TextStyle(fontSize: 13, color: Color(0xFF718096)),
              ),
              const SizedBox(height: 24),

              // ── Request Type Toggle ──
              const Text('Request Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2D3748))),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildTypeButton('Barangay', 'For barangay customer', true)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTypeButton('Market', 'For market customer', false)),
                ],
              ),
              const SizedBox(height: 20),

              // ── Customer Name & Contact Number ──
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Customer Name *'),
                        const SizedBox(height: 6),
                        _buildCustomerNameField(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Contact / Phone No.'),
                        const SizedBox(height: 6),
                        _buildTextField(
                          _contactNumberCtrl,
                          'e.g. 09171234567',
                          keyboardType: TextInputType.phone,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Animal Type / Count / Weight ──
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Animal Type'),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedAnimalType,
                          hint: const Text('Select Type', style: TextStyle(fontSize: 13)),
                          decoration: _dropdownDecoration(),
                          items: _animalTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                          onChanged: (v) => setState(() => _selectedAnimalType = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Animal Count'),
                        const SizedBox(height: 6),
                        _buildTextField(
                          _animalCountCtrl,
                          'e.g. 5',
                          keyboardType: TextInputType.number,
                          focusNode: _animalCountFocus,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Location fields (conditional) ──
              if (_isBarangay) ...[
                ..._buildBarangayFields(),
                const SizedBox(height: 16),
              ],

              // ── Marking ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildLabel('Marking (Unique Tag) *'),
                  if (_isMarkingLocked)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6F9F0),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF2D6A4F).withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified, size: 14, color: Color(0xFF2D6A4F)),
                          const SizedBox(width: 4),
                          const Text(
                            'Verified Permanent Marking',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2D6A4F)),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => setState(() => _isMarkingLocked = false),
                            child: const Text(
                              'Unlock',
                              style: TextStyle(fontSize: 11, color: Color(0xFF1E3A8A), fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              _buildTextField(
                _markingCtrl,
                'Enter unique marking (e.g., MK, MK-1)..',
                readOnly: _isMarkingLocked,
              ),
              const SizedBox(height: 18),

              // ── Separate Facility (Emergency Slaughter) Toggle ──
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _isSeparateFacility ? const Color(0xFFFFF7ED) : const Color(0xFFF7FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _isSeparateFacility ? const Color(0xFFEA580C) : Colors.grey.shade300,
                    width: _isSeparateFacility ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.bolt_rounded,
                          color: _isSeparateFacility ? const Color(0xFFC2410C) : Colors.grey.shade600,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Separate Facility — Emergency Slaughter',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: _isSeparateFacility ? const Color(0xFF9A3412) : const Color(0xFF2D3748),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'For livestock that died due to stress, heat stroke, or accidental (non-infectious) causes. Bypasses standard slaughterhouse queue for immediate slaughter.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: _isSeparateFacility ? const Color(0xFFC2410C) : Colors.grey.shade600,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _isSeparateFacility,
                          activeThumbColor: const Color(0xFFC2410C),
                          onChanged: (val) => setState(() => _isSeparateFacility = val),
                        ),
                      ],
                    ),
                    if (_isSeparateFacility) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Non-Infectious Cause of Death *',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF9A3412)),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedEmergencyCause,
                        decoration: _dropdownDecoration(),
                        items: _emergencyCauses
                            .map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13))))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _selectedEmergencyCause = v);
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Actions ──
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      foregroundColor: const Color(0xFF4A5568),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveRecord,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A202C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Save Record'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBarangayFields() {
    return [
      // Province (Fixed to Albay)
      _buildLabel('Province'),
      const SizedBox(height: 6),
      TextFormField(
        initialValue: 'Albay',
        readOnly: true,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        decoration: _dropdownDecoration().copyWith(
          prefixIcon: const Icon(Icons.location_on, color: Color(0xFF2D6A4F), size: 18),
          suffixIcon: const Padding(
            padding: EdgeInsets.only(right: 12),
            child: Tooltip(
              message: 'Fixed to Albay (Local facility jurisdiction)',
              child: Icon(Icons.lock_outline, size: 16, color: Colors.grey),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),

      // Municipality
      _buildLabel('City / Municipality'),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
              initialValue: _selectedMunicipality,
              isExpanded: true,
              hint: const Text('Select Municipality', style: TextStyle(fontSize: 13)),
              decoration: _dropdownDecoration(),
              items: _municipalities.map<DropdownMenuItem<String>>((m) {
                return DropdownMenuItem<String>(
                  value: m['name'] as String,
                  child: Text(m['name'] as String, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                );
              }).toList(),
              onChanged: (value) {
                final selected = _municipalities.firstWhere((m) => m['name'] == value);
                setState(() {
                  _selectedMunicipality = value;
                  _selectedMunicipalityCode = selected['code'] as String;
                });
                _loadBarangays(_selectedMunicipalityCode!);
              },
            ),
      const SizedBox(height: 16),

      // Barangay
      _buildLabel('Barangay'),
      const SizedBox(height: 6),
      _isLoadingBarangays
          ? const SizedBox(
              height: 48,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2D6A4F))),
            )
          : DropdownButtonFormField<String>(
              initialValue: _selectedBarangay,
              isExpanded: true,
              hint: const Text('Select Barangay', style: TextStyle(fontSize: 13)),
              decoration: _dropdownDecoration(),
              items: _barangays.map<DropdownMenuItem<String>>((b) {
                return DropdownMenuItem<String>(
                  value: b['name'] as String,
                  child: Text(b['name'] as String, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                );
              }).toList(),
              onChanged: _selectedMunicipality == null
                  ? null
                  : (value) {
                      setState(() => _selectedBarangay = value);
                    },
            ),
    ];
  }

  Widget _buildTypeButton(String label, String sub, bool isBarangay) {
    final isActive = _isBarangay == isBarangay;
    return GestureDetector(
      onTap: () => setState(() => _isBarangay = isBarangay),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: isActive
              ? (isBarangay ? const Color(0xFFEBFFF5) : const Color(0xFFEBF4FF))
              : Colors.white,
          border: Border.all(
            color: isActive
                ? (isBarangay ? const Color(0xFF38A169) : const Color(0xFF3182CE))
                : Colors.grey.shade300,
            width: isActive ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isActive
                    ? (isBarangay ? const Color(0xFF276749) : const Color(0xFF2B6CB0))
                    : const Color(0xFF718096),
              ),
            ),
            Text(
              sub,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2D3748)));
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String hint, {
    TextInputType keyboardType = TextInputType.text,
    FocusNode? focusNode,
    bool readOnly = false,
  }) {
    return TextField(
      controller: ctrl,
      focusNode: focusNode,
      readOnly: readOnly,
      keyboardType: keyboardType,
      style: TextStyle(
        fontSize: 13,
        fontWeight: readOnly ? FontWeight.bold : FontWeight.normal,
        color: readOnly ? const Color(0xFF2D6A4F) : const Color(0xFF2D3748),
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
        filled: true,
        fillColor: readOnly ? const Color(0xFFF0FFF4) : const Color(0xFFF7FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: readOnly ? const Color(0xFF81C784) : Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF2D6A4F), width: 1.5)),
      ),
    );
  }

  Widget _buildCustomerNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            return RawAutocomplete<_CustomerLookupItem>(
              textEditingController: _customerNameCtrl,
              focusNode: _customerNameFocus,
              optionsBuilder: (TextEditingValue textEditingValue) {
                final query = textEditingValue.text.trim().toLowerCase();
                if (query.isEmpty) {
                  return _lookupDirectory.take(6);
                }
                return _lookupDirectory.where((item) {
                  final nameMatch = item.name.toLowerCase().contains(query);
                  final markingMatch = item.markings.toLowerCase().contains(query);
                  final phoneMatch = item.phone != null && item.phone!.contains(query);
                  return nameMatch || markingMatch || phoneMatch;
                });
              },
              displayStringForOption: (_CustomerLookupItem option) => option.name,
              onSelected: (_CustomerLookupItem selection) {
                _onCustomerSelected(selection);
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Type surname, full name, or marking (e.g. Bondad, 4)...',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFFF7FAFC),
                    prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF2D6A4F)),
                    suffixIcon: controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              controller.clear();
                              setState(() {
                                _selectedCustomer = null;
                                _isMarkingLocked = false;
                              });
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF2D6A4F), width: 1.5)),
                  ),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth,
                        maxHeight: 260,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: options.length,
                        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
                        itemBuilder: (context, index) {
                          final item = options.elementAt(index);
                          final isMarket = item.category == 'market';
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1A202C)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (item.markings.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE6F9F0),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: const Color(0xFF2D6A4F).withValues(alpha: 0.4)),
                                    ),
                                    child: Text(
                                      'Mark: ${item.markings}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF2D6A4F)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              '${isMarket ? 'Market Dealer' : 'Barangay Dealer'}'
                              '${item.phone != null && item.phone!.isNotEmpty ? ' • ${item.phone}' : ''}'
                              '${item.usualAnimalType != null ? ' • Usual: ${item.usualAnimalType}' : ''}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                            leading: Icon(
                              isMarket ? Icons.storefront : Icons.home_work_outlined,
                              size: 20,
                              color: isMarket ? const Color(0xFF2B6CB0) : const Color(0xFFD69E2E),
                            ),
                            onTap: () => onSelected(item),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
        if (_selectedCustomer != null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFEBF8FF),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF3182CE).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user, size: 16, color: Color(0xFF2B6CB0)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Regular Dealer Profile Loaded: ${_selectedCustomer!.name} (Marking: ${_selectedCustomer!.markings}, ${_selectedCustomer!.category.toUpperCase()})',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF2B6CB0)),
                  ),
                ),
                InkWell(
                  onTap: () {
                    setState(() {
                      _selectedCustomer = null;
                      _isMarkingLocked = false;
                      _customerNameCtrl.clear();
                      _contactNumberCtrl.clear();
                      _markingCtrl.clear();
                    });
                  },
                  child: const Text('Reset', style: TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  InputDecoration _dropdownDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFFF7FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF2D6A4F), width: 1.5)),
    );
  }
}
class _RejectDialog extends StatefulWidget {
  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _controller = TextEditingController(
    text: 'Request denied — fully booked. Please select another date.',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF5F5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.block, color: Color(0xFFE53E3E), size: 22),
          ),
          const SizedBox(width: 12),
          const Text(
            'Reject Request',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D3748),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Reason for rejection (this will be sent to the customer):',
              style: TextStyle(fontSize: 13, color: Color(0xFF718096)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 3,
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFFF7FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE53E3E), width: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Color(0xFF718096))),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE53E3E),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
          child: const Text('Reject & Notify'),
        ),
      ],
    );
  }
}

class _WalkInClaimStubDialog extends StatefulWidget {
  final String refNo;
  final String marking;
  final String customerName;
  final String contactNumber;
  final String livestockType;
  final String animalCount;
  final String requestType;
  final String destinationOrOrigin;
  final bool isLinkedToAccount;
  final bool isSeparateFacility;
  final String? emergencyCause;

  const _WalkInClaimStubDialog({
    required this.refNo,
    required this.marking,
    required this.customerName,
    required this.contactNumber,
    required this.livestockType,
    required this.animalCount,
    required this.requestType,
    required this.destinationOrOrigin,
    required this.isLinkedToAccount,
    this.isSeparateFacility = false,
    this.emergencyCause,
  });

  @override
  State<_WalkInClaimStubDialog> createState() => _WalkInClaimStubDialogState();
}

class _WalkInClaimStubDialogState extends State<_WalkInClaimStubDialog> {
  bool _isPrinting = false;

  Future<void> _printStub() async {
    setState(() => _isPrinting = true);
    try {
      final bytes = await InspectionDocumentsPdfGenerator.generateWalkInClaimStub(
        refNo: widget.refNo,
        marking: widget.marking,
        customerName: widget.customerName,
        contactNumber: widget.contactNumber,
        livestockType: widget.livestockType,
        animalCount: widget.animalCount,
        requestType: widget.requestType,
        destinationOrOrigin: widget.destinationOrOrigin,
      );
      await Printing.layoutPdf(
        name: 'WalkIn_ClaimStub_${widget.refNo}.pdf',
        onLayout: (_) async => bytes,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error printing claim stub: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 540,
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEBFFF5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.receipt_long, color: Color(0xFF2D6A4F), size: 26),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Walk-In Receiving & Mobile Claim Stub',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A202C)),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Print or provide this Reference No. to the walk-in customer.',
                        style: TextStyle(fontSize: 12.5, color: Color(0xFF718096)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEBFFF5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF38A169)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'REFERENCE NO. (CLAIM CODE)',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF276749)),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          widget.refNo,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1A202C)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'LIVESTOCK MARKING TAG',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF4A5568)),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          widget.marking,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1A202C)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _stubInfoRow('Customer Name:', widget.customerName),
            _stubInfoRow('Contact Number:', widget.contactNumber.isNotEmpty ? widget.contactNumber : 'Not provided'),
            _stubInfoRow('Livestock & Head Count:', '${widget.livestockType} (${widget.animalCount} head/s)'),
            _stubInfoRow('Classification:', '${widget.requestType} • ${widget.destinationOrOrigin}'),
            if (widget.isSeparateFacility) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFEA580C)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bolt_rounded, color: Color(0xFFC2410C), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Separate Facility — Immediate Slaughter (Cause: ${widget.emergencyCause ?? "Non-Infectious"})',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF9A3412)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: widget.isLinkedToAccount ? Colors.blue.shade50 : Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: widget.isLinkedToAccount ? Colors.blue.shade200 : Colors.amber.shade300),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (!widget.isLinkedToAccount) ...[
                    Container(
                      width: 82,
                      height: 82,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Image.asset(
                        'assets/images/app_qr_code.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => Icon(Icons.qr_code_2, size: 54, color: Colors.amber.shade900),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ] else ...[
                    Icon(
                      Icons.verified_user,
                      size: 24,
                      color: Colors.blue.shade700,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      widget.isLinkedToAccount
                          ? 'Automatically linked to ${widget.customerName}\'s Mobile App account! They will receive real-time night slaughter alerts and online billing automatically.'
                          : 'Scan QR Code to Install the App: Have the walk-in customer scan this QR code to install the Mobile App, sign up, and enter Reference No. ${widget.refNo} under "Claim Walk-In" to receive overnight inspection updates, pay via GCash, and track morning release.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: widget.isLinkedToAccount ? Colors.blue.shade900 : Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _isPrinting ? null : _printStub,
                  icon: _isPrinting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.print, size: 18),
                  label: Text(_isPrinting ? 'Printing...' : 'Print Claim Stub'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2D6A4F),
                    side: const BorderSide(color: Color(0xFF2D6A4F)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D6A4F),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stubInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: const TextStyle(fontSize: 12.5, color: Color(0xFF718096))),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2D3748))),
          ),
        ],
      ),
    );
  }
}

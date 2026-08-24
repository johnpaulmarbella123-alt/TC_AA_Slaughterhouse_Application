import 'dart:math';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class ReportsRecordsPage extends StatefulWidget {
  const ReportsRecordsPage({super.key});
  @override
  State<ReportsRecordsPage> createState() => _ReportsRecordsPageState();
}

class _ReportsRecordsPageState extends State<ReportsRecordsPage> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;

  // All completed requests (released / paid)
  List<Map<String, dynamic>> _allRequests = [];

  // Filter state
  String _periodFilter = 'Last 7 days';
  String _reportType = 'Daily Report';
  String _activeTab = 'Analytics'; // 'Analytics' or 'Report Illegal'

  // Calendar state
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ════════════════════════════════════════════
  //  LOAD DATA
  // ════════════════════════════════════════════
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final data = await supabase
          .from('requests')
          .select('*, slaughter_inspection(*), payments(*)')
          .inFilter('status', ['paid', 'released', 'completed', 'releasable'])
          .order('created_at', ascending: false);

      final enriched = List<Map<String, dynamic>>.from(data).map((r) {
        final inspectionList = r['slaughter_inspection'];
        if (inspectionList is List && inspectionList.isNotEmpty) {
          final insp = inspectionList.first as Map<String, dynamic>;
          r['carcass_weight'] = insp['carcass_weight'];
          r['post_mortem'] = insp['post_mortem'];
          r['anti_mortem'] = insp['anti_mortem'];
          r['process_notes'] = insp['process_notes'];
        } else if (inspectionList is Map) {
          r['carcass_weight'] = inspectionList['carcass_weight'];
          r['post_mortem'] = inspectionList['post_mortem'];
          r['anti_mortem'] = inspectionList['anti_mortem'];
          r['process_notes'] = inspectionList['process_notes'];
        }
        final paymentsList = r['payments'];
        if (paymentsList is List && paymentsList.isNotEmpty) {
          r['payment'] = paymentsList.first as Map<String, dynamic>;
        } else if (paymentsList is Map) {
          r['payment'] = paymentsList;
        }
        return r;
      }).toList();

      setState(() {
        _allRequests = enriched;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Reports load error: $e');
      setState(() => _isLoading = false);
    }
  }

  // ════════════════════════════════════════════
  //  HELPERS
  // ════════════════════════════════════════════
  String _refNo(Map<String, dynamic> req) =>
      'MI-${DateTime.now().year}-${req['id'].toString().padLeft(3, '0')}';

  double _carcassWeight(Map<String, dynamic> req) {
    final w = req['carcass_weight'];
    if (w == null) return 0;
    return double.tryParse(w.toString()) ?? 0;
  }

  List<Map<String, dynamic>> _filteredByPeriod() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    Duration period;
    switch (_periodFilter) {
      case 'Last 7 days':
        period = const Duration(days: 7);
        break;
      case 'Last 30 days':
        period = const Duration(days: 30);
        break;
      case 'Last 90 days':
        period = const Duration(days: 90);
        break;
      default:
        period = const Duration(days: 365);
    }
    final cutoff = today.subtract(period);
    return _allRequests.where((r) {
      final createdStr = r['created_at']?.toString() ?? '';
      if (createdStr.isEmpty) return false;
      try {
        final dt = DateTime.parse(createdStr);
        return dt.isAfter(cutoff);
      } catch (_) {
        return false;
      }
    }).toList();
  }

  List<Map<String, dynamic>> _requestsForDate(DateTime date) {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    return _allRequests.where((r) {
      final preferred = r['preferred_date']?.toString() ?? '';
      final created = r['created_at']?.toString() ?? '';
      return preferred.startsWith(dateStr) || created.startsWith(dateStr);
    }).toList();
  }

  /// Group requests by date for recent reports
  Map<String, List<Map<String, dynamic>>> _groupByDate() {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (var r in _allRequests) {
      final created = r['created_at']?.toString() ?? r['preferred_date']?.toString() ?? '';
      if (created.isEmpty) continue;
      try {
        final dt = DateTime.parse(created);
        final key = DateFormat('yyyy-MM-dd').format(dt);
        grouped.putIfAbsent(key, () => []);
        grouped[key]!.add(r);
      } catch (_) {}
    }
    // Sort by date descending
    final sorted = Map.fromEntries(
      grouped.entries.toList()..sort((a, b) => b.key.compareTo(a.key)),
    );
    return sorted;
  }

  // Animal type distribution
  Map<String, int> _animalDistribution() {
    final filtered = _selectedDate != null ? _requestsForDate(_selectedDate!) : _filteredByPeriod();
    final dist = <String, int>{};
    for (var r in filtered) {
      final type = r['livestock_type']?.toString() ?? 'Unknown';
      final count = int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1;
      dist[type] = (dist[type] ?? 0) + count;
    }
    return dist;
  }

  String _remarkForRequest(Map<String, dynamic> req) {
    final postMortem = req['post_mortem']?.toString();
    final notes = req['process_notes']?.toString() ?? '';
    if (postMortem == 'Failed') return 'Condemned';
    if (notes.isNotEmpty && notes != 'null') return notes;
    return 'Passed Inspection';
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
                    onRefresh: _loadData,
                    color: const Color(0xFF2D6A4F),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFilterBar(),
                          const SizedBox(height: 20),
                          _buildSummaryCards(),
                          const SizedBox(height: 24),
                          _buildTabButtons(),
                          const SizedBox(height: 24),
                          if (_activeTab == 'Analytics') ...[
                            _buildCalendarAndChart(),
                            const SizedBox(height: 24),
                            if (_selectedDate != null) ...[
                              _buildCustomerRecordsTable(),
                              const SizedBox(height: 24),
                            ],
                            _buildRecentReports(),
                          ] else ...[
                            _buildReportIllegalSection(),
                          ],
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
              const Text('Reports & Records',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
              const SizedBox(height: 2),
              Text('Daily, weekly, monthly reports and analytics',
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
          const SizedBox(width: 12),
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
  //  FILTER BAR
  // ════════════════════════════════════════════
  Widget _buildFilterBar() {
    return Row(
      children: [
        _dropdownChip(
          value: _periodFilter,
          items: ['Last 7 days', 'Last 30 days', 'Last 90 days', 'All time'],
          onChanged: (v) => setState(() => _periodFilter = v),
        ),
        const SizedBox(width: 12),
        _dropdownChip(
          value: _reportType,
          items: ['Daily Report', 'Weekly Report', 'Monthly Report'],
          onChanged: (v) => setState(() => _reportType = v),
        ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(children: [
                  Icon(Icons.info_outline, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('Export feature coming soon'),
                ]),
                backgroundColor: Colors.grey.shade700,
              ),
            );
          },
          icon: const Icon(Icons.download, size: 16, color: Colors.white),
          label: const Text('Export Report', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2D3748),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  Widget _dropdownChip({required String value, required List<String> items, required ValueChanged<String> onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF2F7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.grey, size: 18),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: (val) {
            if (val != null) onChanged(val);
          },
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  SUMMARY CARDS
  // ════════════════════════════════════════════
  Widget _buildSummaryCards() {
    final filtered = _filteredByPeriod();
    double totalRevenue = 0;
    int totalInspections = 0;
    int livestockProcessed = 0;
    int outstanding = 0;

    for (var r in filtered) {
      final payment = r['payment'] as Map<String, dynamic>?;
      final amount = double.tryParse((payment?['total_amount'] ?? 0).toString()) ?? 0;
      totalRevenue += amount;
      totalInspections++;
      livestockProcessed += int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1;
      if (r['status'] == 'paid' || r['status'] == 'releasable') outstanding++;
    }

    final prevFiltered = _allRequests.length;
    final changePercent = prevFiltered > 0 ? ((filtered.length / prevFiltered) * 100).toStringAsFixed(1) : '0.0';

    return Row(
      children: [
        _summaryCard(
          label: 'Total Revenue',
          value: '\u20b1 ${NumberFormat('#,##0.00').format(totalRevenue)}',
          accent: const Color(0xFF2D6A4F),
          changeText: '\u25b2 $changePercent% from last period',
          changeColor: const Color(0xFF2D6A4F),
          showDot: true,
          dotColor: const Color(0xFF2D6A4F),
        ),
        const SizedBox(width: 16),
        _summaryCard(
          label: 'Total Inspection',
          value: totalInspections.toString().padLeft(2, '0'),
          accent: const Color(0xFF2D6A4F),
          changeText: '\u25b2 $changePercent% from last period',
          changeColor: const Color(0xFF2D6A4F),
          icon: Icons.assignment_outlined,
        ),
        const SizedBox(width: 16),
        _summaryCard(
          label: 'Livestock Processed',
          value: livestockProcessed.toString(),
          accent: Colors.pink,
          changeText: '\u25b2 $changePercent% from last period',
          changeColor: const Color(0xFF2D6A4F),
          showDot: true,
          dotColor: Colors.pink,
        ),
        const SizedBox(width: 16),
        _summaryCard(
          label: 'Outstanding',
          value: '$outstanding',
          accent: Colors.orange,
          changeText: outstanding > 0 ? '\u25bc pending release' : 'All released',
          changeColor: Colors.orange,
          icon: Icons.warning_amber_rounded,
          iconColor: Colors.orange,
        ),
      ],
    );
  }

  Widget _summaryCard({
    required String label,
    required String value,
    required Color accent,
    required String changeText,
    required Color changeColor,
    IconData? icon,
    Color? iconColor,
    bool showDot = false,
    Color? dotColor,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500))),
                if (showDot)
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: dotColor ?? accent, shape: BoxShape.circle))
                else if (icon != null)
                  Icon(icon, size: 18, color: iconColor ?? accent),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: accent)),
            const SizedBox(height: 6),
            Text(changeText, style: TextStyle(fontSize: 10, color: changeColor), overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  TAB BUTTONS
  // ════════════════════════════════════════════
  Widget _buildTabButtons() {
    return Row(
      children: [
        _tabButton('Analytics', _activeTab == 'Analytics'),
        const SizedBox(width: 8),
        _tabButton('Report Illegal', _activeTab == 'Report Illegal'),
      ],
    );
  }

  Widget _tabButton(String label, bool isActive) {
    return OutlinedButton(
      onPressed: () => setState(() => _activeTab = label),
      style: OutlinedButton.styleFrom(
        backgroundColor: isActive ? const Color(0xFF2D6A4F).withValues(alpha: 0.08) : Colors.white,
        foregroundColor: isActive ? const Color(0xFF2D6A4F) : const Color(0xFF4A5568),
        side: BorderSide(
          color: isActive ? const Color(0xFF2D6A4F) : Colors.grey.shade300,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      child: Text(label, style: TextStyle(fontSize: 13, fontWeight: isActive ? FontWeight.w600 : FontWeight.w500)),
    );
  }

  // ════════════════════════════════════════════
  //  CALENDAR + DONUT CHART (side by side)
  // ════════════════════════════════════════════
  Widget _buildCalendarAndChart() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Calendar
        Expanded(child: _buildCalendarCard()),
        const SizedBox(width: 24),
        // Donut Chart
        Expanded(child: _buildDonutChartCard()),
      ],
    );
  }

  // ── CALENDAR ──
  Widget _buildCalendarCard() {
    final month = _calendarMonth;
    final monthStr = DateFormat('MMMM yyyy').format(month);
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);
    final startWeekday = firstDay.weekday % 7; // Sunday=0
    final daysInMonth = lastDay.day;

    // Fill calendar grid
    final cells = <Widget>[];
    // Empty cells before first day
    for (int i = 0; i < startWeekday; i++) {
      // Show previous month's trailing days
      final prevMonthLastDay = DateTime(month.year, month.month, 0).day;
      cells.add(_calendarDay((prevMonthLastDay - startWeekday + i + 1).toString(), isOtherMonth: true));
    }
    // Days of current month
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(month.year, month.month, d);
      final isSelected = _selectedDate != null &&
          _selectedDate!.year == date.year &&
          _selectedDate!.month == date.month &&
          _selectedDate!.day == date.day;
      final isToday = DateTime.now().year == date.year &&
          DateTime.now().month == date.month &&
          DateTime.now().day == date.day;
      cells.add(_calendarDay(d.toString(), isSelected: isSelected, isToday: isToday, onTap: () {
        setState(() => _selectedDate = date);
      }));
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Select Date', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
          const SizedBox(height: 4),
          Text('Choose a date to view daily operations report', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 16),
          // Month navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => setState(() {
                  _calendarMonth = DateTime(month.year, month.month - 1);
                }),
                icon: const Icon(Icons.chevron_left, size: 20),
                splashRadius: 18,
              ),
              Text(monthStr, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              IconButton(
                onPressed: () => setState(() {
                  _calendarMonth = DateTime(month.year, month.month + 1);
                }),
                icon: const Icon(Icons.chevron_right, size: 20),
                splashRadius: 18,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Day-of-week headers
          Row(
            children: ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa']
                .map((d) => Expanded(
                      child: Center(
                        child: Text(d, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 6),
          // Calendar grid
          ...List.generate(
            ((cells.length + 6) ~/ 7),
            (row) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: List.generate(7, (col) {
                  final idx = row * 7 + col;
                  return Expanded(child: idx < cells.length ? cells[idx] : const SizedBox.shrink());
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _calendarDay(String day, {bool isSelected = false, bool isToday = false, bool isOtherMonth = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(2),
        height: 36,
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF2D6A4F)
              : isToday
                  ? const Color(0xFF2D6A4F).withValues(alpha: 0.1)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            day,
            style: TextStyle(
              fontSize: 13,
              fontWeight: (isSelected || isToday) ? FontWeight.bold : FontWeight.w500,
              color: isSelected
                  ? Colors.white
                  : isOtherMonth
                      ? Colors.grey.shade300
                      : const Color(0xFF2D3748),
            ),
          ),
        ),
      ),
    );
  }

  // ── DONUT CHART ──
  Widget _buildDonutChartCard() {
    final dist = _animalDistribution();
    final total = dist.values.fold(0, (a, b) => a + b);

    Color getColor(String animal) {
      final name = animal.toLowerCase();
      if (name.contains('hog') || name.contains('pig')) return Colors.blue;
      if (name.contains('cara')) return Colors.orange;
      if (name.contains('cow') || name.contains('cattle')) return Colors.red;
      if (name.contains('goat')) return Colors.yellow.shade700; // slightly darker yellow for visibility
      if (name.contains('sheep')) return Colors.green;
      return Colors.grey;
    }

    // Generate colors aligned with dist entries
    final mappedColors = dist.keys.map((k) => getColor(k)).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Animal Type Distribution', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
          const SizedBox(height: 4),
          Text('Breakdown by animal type processed', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 24),
          if (total == 0)
            SizedBox(
              height: 200,
              child: Center(child: Text('No data available', style: TextStyle(color: Colors.grey.shade400))),
            )
          else ...[
            Center(
              child: SizedBox(
                width: 200,
                height: 200,
                child: CustomPaint(
                  painter: _DonutChartPainter(
                    values: dist.values.toList(),
                    colors: mappedColors,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Legend
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: dist.entries.toList().asMap().entries.map((entry) {
                final idx = entry.key;
                final e = entry.value;
                final color = mappedColors[idx];
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  ],
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  CUSTOMER RECORDS TABLE (for selected date)
  // ════════════════════════════════════════════
  Widget _buildCustomerRecordsTable() {
    final records = _requestsForDate(_selectedDate!);
    final dateFmt = DateFormat('EEE, MMMM d, yyyy').format(_selectedDate!);
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Customer Records - $dateFmt', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
                      const SizedBox(height: 4),
                      Text('Detailed breakdown of all customers processed on this date', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: const Text('Download coming soon'), backgroundColor: Colors.grey.shade700),
                    );
                  },
                  icon: Icon(Icons.download, size: 20, color: Colors.grey.shade600),
                  splashRadius: 20,
                ),
                IconButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: const Text('Print coming soon'), backgroundColor: Colors.grey.shade700),
                    );
                  },
                  icon: Icon(Icons.print_outlined, size: 20, color: Colors.grey.shade600),
                  splashRadius: 20,
                ),
              ],
            ),
          ),
          if (records.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.event_busy, size: 48, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text('No records for this date', style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
                  ],
                ),
              ),
            )
          else
            Scrollbar(
              controller: scrollController,
              thumbVisibility: false,
              trackVisibility: false,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 1000),
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(const Color(0xFFF7FAFC)),
                      dataRowMinHeight: 52,
                      dataRowMaxHeight: 68,
                      columnSpacing: 24,
                      columns: const [
                        DataColumn(label: Text('Reference Number', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                        DataColumn(label: Text('Customer Name', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                        DataColumn(label: Text('Type', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                        DataColumn(label: Text('Livestock', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                        DataColumn(label: Text('Heads', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                        DataColumn(label: Text('Carcass Weight', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                        DataColumn(label: Text('Remarks', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                      ],
                      rows: records.map((req) {
                        final ref = _refNo(req);
                        final type = req['request_type']?.toString() ?? '';
                        final isBarangay = type == 'barangay';
                        final livestock = req['livestock_type']?.toString() ?? '\u2014';
                        final animalCount = req['animal_count'] ?? 1;
                        final weight = _carcassWeight(req);
                        final remark = _remarkForRequest(req);

                        return DataRow(cells: [
                          DataCell(Text(ref, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12))),
                          DataCell(Text(req['customer_name']?.toString() ?? '\u2014', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                          DataCell(_buildTypeBadge(isBarangay ? 'Barangay' : 'Market')),
                          DataCell(Text('$livestock ($animalCount)', style: const TextStyle(fontSize: 12))),
                          DataCell(Text('$animalCount', style: const TextStyle(fontSize: 13))),
                          DataCell(Text(weight > 0 ? '${weight.toStringAsFixed(2)} kg' : '\u2014', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                          DataCell(Text(remark, style: TextStyle(fontSize: 11, color: remark == 'Condemned' ? Colors.red : Colors.grey.shade700))),
                        ]);
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTypeBadge(String type) {
    final isBarangay = type == 'Barangay';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isBarangay ? const Color(0xFF2D6A4F).withValues(alpha: 0.1) : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        type,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isBarangay ? const Color(0xFF2D6A4F) : Colors.blue.shade700,
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  RECENT REPORTS
  // ════════════════════════════════════════════
  Widget _buildRecentReports() {
    final grouped = _groupByDate();
    final recentDates = grouped.keys.take(5).toList();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recent Reports', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
          const SizedBox(height: 4),
          Text('Quick access to recent daily operations reports', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 16),
          if (recentDates.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(child: Text('No reports available', style: TextStyle(color: Colors.grey.shade400))),
            )
          else
            ...recentDates.map((dateKey) {
              final dayReqs = grouped[dateKey]!;
              final dt = DateTime.parse(dateKey);
              final dateFmt = DateFormat('EEE, MMMM d, yyyy').format(dt);
              final customers = dayReqs.length;
              final heads = dayReqs.fold<int>(0, (s, r) => s + (int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1));
              final totalWeight = dayReqs.fold<double>(0, (s, r) => s + _carcassWeight(r));

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(dateFmt, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
                          const SizedBox(height: 4),
                          Text(
                            '$customers Customer  •  $heads Heads  •  ${totalWeight.toStringAsFixed(totalWeight == totalWeight.roundToDouble() ? 0 : 2)} kg',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: const Text('Download coming soon'), backgroundColor: Colors.grey.shade700),
                        );
                      },
                      icon: Icon(Icons.download, size: 20, color: Colors.grey.shade600),
                      splashRadius: 20,
                    ),
                    IconButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: const Text('Print coming soon'), backgroundColor: Colors.grey.shade700),
                        );
                      },
                      icon: Icon(Icons.print_outlined, size: 20, color: Colors.grey.shade600),
                      splashRadius: 20,
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  REPORT ILLEGAL SECTION
  // ════════════════════════════════════════════
  Widget _buildReportIllegalSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.report_outlined, size: 40, color: Colors.red.shade400),
          ),
          const SizedBox(height: 20),
          const Text('Report Illegal Activity', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
          const SizedBox(height: 8),
          Text(
            'Report illegal slaughtering activities or violations',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('Coming Soon', style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  DONUT CHART PAINTER
// ═══════════════════════════════════════════════════════════
class _DonutChartPainter extends CustomPainter {
  final List<int> values;
  final List<Color> colors;

  _DonutChartPainter({required this.values, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold(0, (a, b) => a + b);
    if (total == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;
    final strokeWidth = radius * 0.45;
    final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    double startAngle = -pi / 2;
    for (int i = 0; i < values.length; i++) {
      final sweepAngle = (values[i] / total) * 2 * pi;
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.colors != colors;
  }
}

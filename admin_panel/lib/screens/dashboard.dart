import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardPage extends StatefulWidget {
  final ValueChanged<int>? onNavigate;

  const DashboardPage({super.key, this.onNavigate});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final supabase = Supabase.instance.client;

  int _pendingCount = 0;
  int _docVerifCount = 0;
  int _slaughterCount = 0;
  int _paymentCount = 0;
  int _releasingCount = 0;
  int _reportsWeekCount = 0;
  bool _isLoadingCount = true;

  List<Map<String, dynamic>> _recentActivities = [];

  @override
  void initState() {
    super.initState();
    _loadPendingCount();
    _loadRecentActivities();
  }

  Future<void> _loadRecentActivities() async {
    try {
      final reqs = await supabase.from('requests').select('id, created_at, released_at, status').order('created_at', ascending: false).limit(10);
      final insps = await supabase.from('slaughter_inspection').select('request_id, created_at').order('created_at', ascending: false).limit(10);
      final payments = await supabase.from('payments').select('request_id, created_at').order('created_at', ascending: false).limit(10);

      final activities = <Map<String, dynamic>>[];

      String refNo(dynamic id) {
        return 'MI-${DateTime.now().year}-${id.toString().padLeft(3, '0')}';
      }

      for (var r in reqs) {
        final dt = DateTime.tryParse(r['created_at'].toString());
        if (dt != null) {
          activities.add({
            'title': 'New Request Received',
            'subtitle': refNo(r['id']),
            'time': dt,
            'color': Colors.blueAccent,
          });
        }
        
        if (r['released_at'] != null) {
          final relDt = DateTime.tryParse(r['released_at'].toString());
          if (relDt != null) {
            activities.add({
              'title': 'Meat Released',
              'subtitle': refNo(r['id']),
              'time': relDt,
              'color': Colors.orange,
            });
          }
        }
      }

      for (var i in insps) {
        final dt = DateTime.tryParse(i['created_at'].toString());
        if (dt != null) {
          activities.add({
            'title': 'Slaughter & Inspection',
            'subtitle': refNo(i['request_id']),
            'time': dt,
            'color': Colors.green,
          });
        }
      }

      for (var p in payments) {
        final dt = DateTime.tryParse(p['created_at'].toString());
        if (dt != null) {
          activities.add({
            'title': 'Payment Processed',
            'subtitle': refNo(p['request_id']),
            'time': dt,
            'color': Colors.purpleAccent,
          });
        }
      }

      activities.sort((a, b) => (b['time'] as DateTime).compareTo(a['time'] as DateTime));

      if (mounted) {
        setState(() {
          _recentActivities = activities.take(5).toList();
        });
      }
    } catch (e) {
      debugPrint('Dashboard: error loading recent activities: $e');
    }
  }

  Future<void> _loadPendingCount() async {
    try {
      final data = await supabase
          .from('requests')
          .select('status, created_at');
          
      int pending = 0;
      int docVerif = 0;
      int slaughter = 0;
      int payment = 0;
      int releasing = 0;
      int reportsWeek = 0;

      final now = DateTime.now();
      final oneWeekAgo = now.subtract(const Duration(days: 7));

      final reqList = List<Map<String, dynamic>>.from(data);
      for (var req in reqList) {
        final st = req['status']?.toString() ?? '';
        
        if (st == 'pending') {
          pending++;
        } else if (st == 'approved') {
          docVerif++;
        } else if (st == 'doc_verified') {
          slaughter++;
        } else if (st == 'releasable' || st == 'payment_pending') {
          payment++;
        } else if (st == 'paid') {
          releasing++;
        }
        
        try {
          final dtStr = req['created_at']?.toString() ?? '';
          if (dtStr.isNotEmpty) {
            final dt = DateTime.parse(dtStr);
            if (dt.isAfter(oneWeekAgo)) reportsWeek++;
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _pendingCount = pending;
          _docVerifCount = docVerif;
          _slaughterCount = slaughter;
          _paymentCount = payment;
          _releasingCount = releasing;
          _reportsWeekCount = reportsWeek;
          _isLoadingCount = false;
        });
      }
    } catch (e) {
      debugPrint('Dashboard: error loading pending count: $e');
      if (mounted) setState(() => _isLoadingCount = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        title: Row(
          children: [
            Image.asset('assets/images/logo1.png', height: 40),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tabaco City Slaughterhouse',
                  style: TextStyle(
                    color: Color(0xFF2D6A4F),
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  'Management system',
                  style: TextStyle(
                    color: Color(0xFF718096),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF718096)),
            tooltip: 'Refresh counts',
            onPressed: () {
              setState(() => _isLoadingCount = true);
              _loadPendingCount();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'WELCOME, ADMIN!',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A202C),
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Overview and system statistics',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF718096),
              ),
            ),
            const SizedBox(height: 10),
            const Divider(),
            const SizedBox(height: 10),
            const Text(
              'Dashboard',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D3748),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Overview and system statistics',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF718096),
              ),
            ),
            const SizedBox(height: 16),
            // Statistics Grid
            LayoutBuilder(
              builder: (context, constraints) {
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: constraints.maxWidth > 1200 ? 4 : (constraints.maxWidth > 800 ? 2 : 1),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: constraints.maxWidth > 1200 ? 2.0 : 2.5,
                  children: [
                    _buildStatCard('Total Revenue', '₱15,000', 'This week', Icons.payments_outlined, Colors.grey),
                    _buildStatCard('Animal Processed', '362', 'This week', Icons.show_chart, Colors.grey),
                    _buildStatCard('Avg Processing Time', '4.5h', 'Per livestock', Icons.access_time, Colors.grey),
                    _buildStatCard('Satisfaction Rate', '98.5%', 'Customer feedback', Icons.trending_up, Colors.grey),
                  ],
                );
              },
            ),
            const SizedBox(height: 32),
            const Text(
              'Quick Navigation Tools',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D3748),
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: constraints.maxWidth > 1200 ? 3 : (constraints.maxWidth > 800 ? 2 : 1),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: constraints.maxWidth > 1200 ? 2.2 : 2.0,
                  children: [
                    _buildNavigationCard(
                      'Receiving & New Requests',
                      _pendingCount > 0
                          ? '$_pendingCount new request${_pendingCount == 1 ? '' : 's'} pending'
                          : 'No pending requests',
                      _isLoadingCount ? '…' : '$_pendingCount',
                      Icons.assignment_outlined,
                      _pendingCount > 0 ? Colors.redAccent : Colors.grey,
                      1,
                      hasPendingAlert: _pendingCount > 0,
                    ),
                    _buildNavigationCard(
                      'Document Verification',
                      _docVerifCount > 0 ? '$_docVerifCount pending verification' : 'verified',
                      _isLoadingCount ? '…' : '$_docVerifCount',
                      Icons.fact_check_outlined,
                      _docVerifCount > 0 ? Colors.blueAccent : Colors.grey,
                      2,
                      hasPendingAlert: _docVerifCount > 0,
                    ),
                    _buildNavigationCard(
                      'Slaughter & Inspection',
                      _slaughterCount > 0 ? '$_slaughterCount awaiting slaughter' : 'Processed',
                      _isLoadingCount ? '…' : '$_slaughterCount',
                      Icons.content_cut,
                      _slaughterCount > 0 ? Colors.green : Colors.grey,
                      3,
                      hasPendingAlert: _slaughterCount > 0,
                    ),
                    _buildNavigationCard(
                      'Payment & Cashiering',
                      _paymentCount > 0 ? '$_paymentCount pending payment' : 'Complete',
                      _isLoadingCount ? '…' : '$_paymentCount',
                      Icons.payment_outlined,
                      _paymentCount > 0 ? Colors.orangeAccent : Colors.grey,
                      4,
                      hasPendingAlert: _paymentCount > 0,
                    ),
                    _buildNavigationCard(
                      'Meat Releasing',
                      _releasingCount > 0 ? '$_releasingCount ready for release' : 'Released',
                      _isLoadingCount ? '…' : '$_releasingCount',
                      Icons.inventory_2_outlined,
                      _releasingCount > 0 ? Colors.orange : Colors.grey,
                      5,
                      hasPendingAlert: _releasingCount > 0,
                    ),
                    _buildNavigationCard(
                      'Report & Records',
                      'This week',
                      _isLoadingCount ? '…' : '$_reportsWeekCount',
                      Icons.receipt_long_outlined,
                      Colors.pinkAccent,
                      6,
                      hasPendingAlert: false,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 32),
            _buildRecentActivity(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, String subtitle, IconData icon, Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF4A5568),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Icon(icon, color: iconColor, size: 20),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D3748),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFFA0AEC0),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationCard(
    String title,
    String subtitle,
    String badgeCount,
    IconData icon,
    Color color,
    int navIndex, {
    bool hasPendingAlert = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasPendingAlert ? Colors.redAccent.withValues(alpha: 0.4) : Colors.grey.shade300,
          width: hasPendingAlert ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              // Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: hasPendingAlert
                      ? const Color(0xFFE53E3E)
                      : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasPendingAlert) ...[
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                    Text(
                      badgeCount,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: hasPendingAlert ? Colors.white : const Color(0xFF4A5568),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D3748),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: hasPendingAlert ? const Color(0xFFE53E3E) : const Color(0xFF718096),
              fontWeight: hasPendingAlert ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => widget.onNavigate?.call(navIndex),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: hasPendingAlert ? Colors.redAccent.withValues(alpha: 0.5) : Colors.grey.shade300,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                foregroundColor: hasPendingAlert ? const Color(0xFFE53E3E) : const Color(0xFF2D3748),
              ),
              child: const Text('Open Modules'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivity(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Activity',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D3748),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'latest operations in the system',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF718096),
            ),
          ),
          const SizedBox(height: 24),
          if (_recentActivities.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('No recent activity', style: TextStyle(color: Colors.grey))),
            )
          else
            ..._recentActivities.asMap().entries.expand((entry) {
              final idx = entry.key;
              final act = entry.value;
              final isLast = idx == _recentActivities.length - 1;
              return [
                _buildActivityItem(
                  act['title'],
                  act['subtitle'],
                  _timeAgo(act['time']),
                  act['color'],
                ),
                if (!isLast) const Divider(height: 24),
              ];
            }),
        ],
      ),
    );
  }

  String _timeAgo(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  Widget _buildActivityItem(String title, String subtitle, String time, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF2D3748)),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF718096), fontSize: 13),
              ),
            ],
          ),
        ),
        Text(
          time,
          style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 12),
        ),
      ],
    );
  }
}

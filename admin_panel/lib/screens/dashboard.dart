import 'package:flutter/material.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

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
                          _buildNavigationCard('Receiving & New Requests', 'Pending', '3', Icons.assignment_outlined, Colors.redAccent),
                          _buildNavigationCard('Document Verification', 'verified', '21', Icons.fact_check_outlined, Colors.blueAccent),
                          _buildNavigationCard('Slaughter & Inspection', 'Processed', '18', Icons.content_cut, Colors.green),
                          _buildNavigationCard('Payment & Cashiering', 'Complete', '16', Icons.payment_outlined, Colors.orangeAccent),
                          _buildNavigationCard('Meat Releasing', 'Released', '15', Icons.inventory_2_outlined, Colors.orange),
                          _buildNavigationCard('Report & Records', 'This week', '168', Icons.receipt_long_outlined, Colors.pinkAccent),
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

  Widget _buildNavigationCard(String title, String subtitle, String badgeCount, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badgeCount,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4A5568),
                  ),
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
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF718096),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {},
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                foregroundColor: const Color(0xFF2D3748),
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
          _buildActivityItem('Livestock received', 'REF-2025-001', '10 mins ago', Colors.green),
          const Divider(height: 24),
          _buildActivityItem('Document verified', 'REF-2025-002', '25 mins ago', Colors.green),
          const Divider(height: 24),
          _buildActivityItem('Payment processed', 'REF-2025-003', '45 mins ago', Colors.green),
          const Divider(height: 24),
          _buildActivityItem('Awaiting inspection', 'REF-2025-004', '1 hour ago', Colors.orange),
        ],
      ),
    );
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

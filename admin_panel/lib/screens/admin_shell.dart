import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dashboard.dart';
import 'receiving_requests_page.dart';
import 'document_verification_page.dart';
import 'slaughter_inspection_page.dart';
import 'payment_cashiering_page.dart';
import 'meat_releasing_page.dart';
import 'reports_records_page.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _selectedIndex = 0;

  void _onNavigate(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    // Dashboard = full screen (no sidebar)
    // Any module = sidebar + content
    if (_selectedIndex == 0) {
      return DashboardPage(onNavigate: _onNavigate);
    }

    return Scaffold(
      body: Row(
        children: [
          // ─── SIDEBAR ───
          _AdminSidebar(
            selectedIndex: _selectedIndex,
            onItemSelected: _onNavigate,
          ),
          // ─── CONTENT AREA ───
          Expanded(
            child: _buildPage(),
          ),
        ],
      ),
    );
  }

  Widget _buildPage() {
    switch (_selectedIndex) {
      case 0:
        return DashboardPage(onNavigate: _onNavigate);
      case 1:
        return const ReceivingRequestsPage();
      case 2:
        return const DocumentVerificationPage();
      case 3:
        return const SlaughterInspectionPage();
      case 4:
        return const PaymentCashieringPage();
      case 5:
        return const MeatReleasingPage();
      case 6:
        return const ReportsRecordsPage();
      default:
        return DashboardPage(onNavigate: _onNavigate);
    }
  }
}

// ═══════════════════════════════════════════════════════════
//  SIDEBAR WIDGET
// ═══════════════════════════════════════════════════════════
class _AdminSidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  const _AdminSidebar({
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // ─── LOGO HEADER ───
          _buildLogoHeader(),
          const SizedBox(height: 8),
          // ─── NAV ITEMS ───
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                children: [
                  _buildNavItem(
                    index: 0,
                    icon: Icons.dashboard_outlined,
                    activeIcon: Icons.dashboard,
                    label: 'Dashboard',
                    subtitle: 'Overview & statistics',
                  ),
                  const SizedBox(height: 2),
                  _buildNavItem(
                    index: 1,
                    icon: Icons.assignment_outlined,
                    activeIcon: Icons.assignment,
                    label: 'Receiving & New Requests',
                    subtitle: 'Customer details, animal inspection, reference assignment',
                  ),
                  const SizedBox(height: 2),
                  _buildNavItem(
                    index: 2,
                    icon: Icons.fact_check_outlined,
                    activeIcon: Icons.fact_check,
                    label: 'Document Verification',
                    subtitle: 'Permits and certificates verification',
                  ),
                  const SizedBox(height: 2),
                  _buildNavItem(
                    index: 3,
                    icon: Icons.content_cut_outlined,
                    activeIcon: Icons.content_cut,
                    label: 'Slaughter & Inspection',
                    subtitle: 'Process tagging, post-mortem inspection, MC generation',
                  ),
                  const SizedBox(height: 2),
                  _buildNavItem(
                    index: 4,
                    icon: Icons.payment_outlined,
                    activeIcon: Icons.payment,
                    label: 'Payment & Cashiering',
                    subtitle: 'Fee calculation, payment recording, receipts',
                  ),
                  const SizedBox(height: 2),
                  _buildNavItem(
                    index: 5,
                    icon: Icons.inventory_2_outlined,
                    activeIcon: Icons.inventory_2,
                    label: 'Meat Releasing',
                    subtitle: 'Ready for pickup, collection confirmation',
                  ),
                  const SizedBox(height: 2),
                  _buildNavItem(
                    index: 6,
                    icon: Icons.assessment_outlined,
                    activeIcon: Icons.assessment,
                    label: 'Reports & Records',
                    subtitle: 'Daily, weekly, monthly reports and analytics',
                  ),
                ],
              ),
            ),
          ),
          // ─── ADMIN PROFILE + LOGOUT ───
          _buildAdminFooter(context),
        ],
      ),
    );
  }

  Widget _buildLogoHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade100, width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2D6A4F).withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset('assets/images/logo1.png', fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tabaco City Slaughterhouse',
                  style: TextStyle(
                    color: Color(0xFF2D6A4F),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2),
                Text(
                  'Management System',
                  style: TextStyle(
                    color: Color(0xFF718096),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required String subtitle,
  }) {
    final isSelected = selectedIndex == index;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => onItemSelected(index),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF2D6A4F).withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected
                ? Border.all(
                    color: const Color(0xFF2D6A4F).withValues(alpha: 0.3),
                    width: 1,
                  )
                : Border.all(color: Colors.transparent, width: 1),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                color: isSelected
                    ? const Color(0xFF2D6A4F)
                    : const Color(0xFF718096),
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: isSelected
                            ? const Color(0xFF2D6A4F)
                            : const Color(0xFF2D3748),
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w600,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: isSelected
                            ? const Color(0xFF2D6A4F).withValues(alpha: 0.7)
                            : const Color(0xFFA0AEC0),
                        fontSize: 10.5,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdminFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Admin profile row
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.grey.shade200,
                child: const Icon(Icons.person_outline, color: Color(0xFF718096), size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Admin',
                  style: TextStyle(
                    color: Color(0xFF2D3748),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Logout button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                // Clear "keep me logged in" so next launch requires login
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('keepMeLoggedIn', false);
                await Supabase.instance.client.auth.signOut();
                if (context.mounted) {
                  Navigator.pushReplacementNamed(context, '/');
                }
              },
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Logout'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF718096),
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

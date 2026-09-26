import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class IllegalSlaughterReportsView extends StatefulWidget {
  const IllegalSlaughterReportsView({super.key});

  @override
  State<IllegalSlaughterReportsView> createState() => _IllegalSlaughterReportsViewState();
}

class _IllegalSlaughterReportsViewState extends State<IllegalSlaughterReportsView> {
  String _activeTab = 'Mobile Submissions'; // 'Mobile Submissions', 'All Reports', 'Manual Entry'
  
  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now());

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(dateStr),
          const SizedBox(height: 30),
          _buildSummaryCards(),
          const SizedBox(height: 30),
          _buildTabs(),
          const SizedBox(height: 24),
          _buildTabContent(),
        ],
      ),
    );
  }

  Widget _buildHeader(String dateStr) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Illegal Slaughter Reports',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A202C)),
            ),
            const SizedBox(height: 4),
            Text(
              'Track and report illegal slaughter activities',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            dateStr,
            style: const TextStyle(fontSize: 12, color: Color(0xFF4A5568)),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCards() {
    return Row(
      children: [
        _summaryCard('1', 'Unreviewed Mobile', const Color(0xFFD946EF), Icons.phone_android),
        const SizedBox(width: 16),
        _summaryCard('1', 'Awaiting Action', const Color(0xFFF59E0B), Icons.access_time),
        const SizedBox(width: 16),
        _summaryCard('1', 'Under Investigation', const Color(0xFF3B82F6), Icons.shield_outlined),
        const SizedBox(width: 16),
        _summaryCard('1', 'Resolved', const Color(0xFF10B981), Icons.check_circle_outline),
      ],
    );
  }

  Widget _summaryCard(String count, String label, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4))
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF4A5568)),
                ),
              ],
            ),
            Icon(icon, color: color, size: 28),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          _tabButton('Mobile Submissions', icon: Icons.phone_android, hasBadge: true),
          _tabButton('All Reports', icon: Icons.description_outlined),
          _tabButton('Manual Entry', icon: Icons.add, isManual: true),
        ],
      ),
    );
  }

  Widget _tabButton(String title, {IconData? icon, bool hasBadge = false, bool isManual = false}) {
    final isActive = _activeTab == title;
    
    // Figma shows specific naming like "+ Manual Entry" and "All Reports (3)"
    String displayTitle = title;
    if (title == 'Manual Entry') displayTitle = '+ Manual Entry';
    if (title == 'All Reports') displayTitle = 'All Reports (3)';

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = title),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            boxShadow: isActive
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null && !isManual) ...[
                Icon(icon, size: 16, color: isActive ? const Color(0xFF1A202C) : Colors.grey.shade600),
                const SizedBox(width: 8),
              ],
              Text(
                displayTitle,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                  color: isActive ? const Color(0xFF1A202C) : Colors.grey.shade600,
                ),
              ),
              if (hasBadge) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  child: const Text('1', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_activeTab) {
      case 'Mobile Submissions':
        return _buildMobileSubmissionsTab();
      case 'All Reports':
        return _buildAllReportsTab();
      case 'Manual Entry':
        return _buildManualEntryTab();
      default:
        return const SizedBox.shrink();
    }
  }

  // ═══════════════════════════════════════════════════════════
  // MOBILE SUBMISSIONS TAB
  // ═══════════════════════════════════════════════════════════
  Widget _buildMobileSubmissionsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Alert Box
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFDF4FF),
            border: Border.all(color: const Color(0xFFF0ABFC)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.phone_android, color: Color(0xFFC026D3), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Mobile App — Report Illegal Slaughter', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF86198F), fontSize: 13)),
                    SizedBox(height: 2),
                    Text('Citizens submit reports directly via the mobile app. Each submission must be acknowledged, assigned for investigation, and compiled before the case is closed.', style: TextStyle(color: Color(0xFFA21CAF), fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Report Card List
        _buildReportCard(),
      ],
    );
  }

  Widget _buildReportCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF1D4ED8),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.description_outlined, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text('ISR-2024-001', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                Row(
                  children: const [
                    Icon(Icons.access_time, color: Colors.white70, size: 14),
                    SizedBox(width: 6),
                    Text('1/10/2024, 8:23:00 AM', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          
          // Content
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info Grid
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _infoItem(Icons.location_on_outlined, 'LOCATION OF INCIDENT', 'Corner of Main St. and Rizal Ave., Barangay San Jose'),
                          const SizedBox(height: 20),
                          _infoItem(Icons.calendar_today_outlined, 'DATE OF INCIDENT', 'January 9, 2024'),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: _infoItem(Icons.person_outline, 'REPORTER', 'Maria Cruz\n+63 917 123 4567'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _infoItem(Icons.description_outlined, 'DESCRIPTION OF VIOLATION', 'Observed unauthorized slaughter operation in residential area during late evening hours. Multiple animals heard, strong odor present. Approximately 5-6 hogs being slaughtered without any visible permits or veterinary inspection.'),
                const SizedBox(height: 20),
                _infoItem(Icons.camera_alt_outlined, 'PHOTO EVIDENCE', 'No photos attached', isGrey: true),
                
                const SizedBox(height: 24),
                // Status Badges
                Row(
                  children: [
                    _statusBadge('Investigating', Colors.blue),
                    const SizedBox(width: 8),
                    _statusBadge('High', Colors.deepOrange),
                    const SizedBox(width: 8),
                    _statusBadge('Inspector Santos', Colors.grey.shade700, outlined: true),
                  ],
                ),
                
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Divider(),
                ),
                
                // Investigation Log
                const Text('INVESTIGATION LOG', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
                const SizedBox(height: 12),
                _logEntry('1/10/2024, 9:00:00 AM', 'Report acknowledged', 'Received from mobile app'),
                _logEntry('1/10/2024, 10:30:00 AM', 'Investigation started', 'Assigned to Inspector Santos. High priority.'),
                
                const SizedBox(height: 24),
                // Action Buttons
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _showUpdateInvestigationModal(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Update Investigation'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () => _showCompileReportModal(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF475569),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.edit_document, size: 18),
                      label: const Text('Compile Report'),
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: () => _showFullDetailsModal(context),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF475569),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('View Details'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoItem(IconData icon, String label, String value, {bool isGrey = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.grey.shade500),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(fontSize: 13, color: isGrey ? Colors.grey.shade500 : const Color(0xFF1A202C), height: 1.5),
        ),
      ],
    );
  }

  Widget _statusBadge(String text, Color color, {bool outlined = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: outlined ? Colors.white : color.withValues(alpha: 0.1),
        border: Border.all(color: outlined ? Colors.grey.shade300 : color.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: outlined ? color : color.withOpacity(0.8)),
      ),
    );
  }

  Widget _logEntry(String time, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 4, right: 8),
            child: Icon(Icons.chevron_right, size: 14, color: Colors.grey),
          ),
          Text(time, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(width: 12),
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
          const SizedBox(width: 8),
          const Text('—', style: TextStyle(color: Colors.grey)),
          const SizedBox(width: 8),
          Expanded(child: Text(desc, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // ALL REPORTS TAB
  // ═══════════════════════════════════════════════════════════
  Widget _buildAllReportsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('All Reports', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
        const SizedBox(height: 4),
        Text('All illegal slaughter reports from mobile and manual sources', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        const SizedBox(height: 24),
        
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search by report #, location, or reporter...',
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade200)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade200)),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: const [
                  Text('All Status', style: TextStyle(color: Color(0xFF4A5568))),
                  SizedBox(width: 8),
                  Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.grey),
                ],
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 24),
        
        // Data Table
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DataTable(
            headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A202C), fontSize: 12),
            dataTextStyle: const TextStyle(color: Color(0xFF4A5568), fontSize: 13),
            columns: const [
              DataColumn(label: Text('Report #')),
              DataColumn(label: Text('Source')),
              DataColumn(label: Text('Date Filed')),
              DataColumn(label: Text('Location of Incident')),
              DataColumn(label: Text('Reporter')),
              DataColumn(label: Text('Priority')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Assigned To')),
              DataColumn(label: Text('Actions')),
            ],
            rows: [
              _buildTableRow('ISR-2024-001', 'Mobile', '1/10/2024', 'Corner of Main St. and Rizal Ave...', 'Maria Cruz', 'High', 'Investigating', 'Inspector Santos'),
              _buildTableRow('ISR-2024-002', 'Mobile', '1/12/2024', 'Behind Public Market, near the...', 'Anonymous', 'Medium', 'Pending', '—'),
              _buildTableRow('ISR-2024-003', 'Mobile', '1/5/2024', 'Sitio Mabuhay, Interior Road, Ba...', 'Juan Dela Cruz', 'High', 'Resolved', 'Inspector Reyes'),
            ],
          ),
        ),
      ],
    );
  }

  DataRow _buildTableRow(String id, String source, String date, String loc, String reporter, String priority, String status, String assigned) {
    Color priorityColor = priority == 'High' ? Colors.deepOrange : Colors.blue;
    Color statusColor = status == 'Resolved' ? Colors.green : (status == 'Pending' ? Colors.orange : Colors.blue);
    
    return DataRow(
      cells: [
        DataCell(Text(id, style: const TextStyle(fontWeight: FontWeight.w600))),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFD946EF).withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(4),
              color: const Color(0xFFFDF4FF),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.phone_android, size: 12, color: Color(0xFFC026D3)),
                const SizedBox(width: 4),
                Text(source, style: const TextStyle(fontSize: 11, color: Color(0xFF86198F))),
              ],
            ),
          )
        ),
        DataCell(Text(date)),
        DataCell(Text(loc)),
        DataCell(Row(
          children: [
            if (reporter == 'Anonymous') const Icon(Icons.person_off_outlined, size: 14, color: Colors.grey),
            if (reporter == 'Anonymous') const SizedBox(width: 4),
            Text(reporter, style: TextStyle(color: reporter == 'Anonymous' ? Colors.grey : const Color(0xFF4A5568))),
          ],
        )),
        DataCell(_statusBadge(priority, priorityColor)),
        DataCell(_statusBadge(status, statusColor, outlined: status == 'Investigating' || status == 'Pending')),
        DataCell(Text(assigned)),
        DataCell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(onTap: () {}, child: const Icon(Icons.visibility_outlined, size: 16, color: Colors.grey)),
            const SizedBox(width: 12),
            if (status != 'Resolved') InkWell(onTap: () {}, child: const Icon(Icons.edit_outlined, size: 16, color: Colors.grey)),
            if (status != 'Resolved') const SizedBox(width: 12),
            InkWell(onTap: () {}, child: const Icon(Icons.delete_outline, size: 16, color: Colors.grey)),
          ],
        )),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // MANUAL ENTRY TAB
  // ═══════════════════════════════════════════════════════════
  Widget _buildManualEntryTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.edit_document, color: Color(0xFF475569)),
            SizedBox(width: 8),
            Text('Add Report Manually', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
          ],
        ),
        const SizedBox(height: 4),
        Text('Record a report received via walk-in, phone call, or other offline channel. Uses the same fields as the mobile form.', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        const SizedBox(height: 30),
        
        _buildFormField('Location of Incident *', 'Exact address or landmark', icon: Icons.location_on_outlined),
        const SizedBox(height: 20),
        _buildFormField('Date of Incident *', 'dd/mm/yyyy', icon: Icons.calendar_today_outlined, isDate: true),
        const SizedBox(height: 20),
        _buildFormField('Description of Violation *', 'Describe what you observed, including specific violations, number of animals, conditions, etc.', icon: Icons.description_outlined, maxLines: 4),
        const SizedBox(height: 20),
        
        // Photo Evidence Mock
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.camera_alt_outlined, size: 16, color: Colors.grey),
                SizedBox(width: 8),
                Text('Photo Evidence', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A202C))),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.add_a_photo_outlined, color: Colors.grey, size: 18),
                  SizedBox(width: 8),
                  Text('Attach photo evidence (optional) — upload not available in manual mode', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        
        Row(
          children: [
            SizedBox(
              height: 20,
              width: 20,
              child: Checkbox(value: false, onChanged: (v) {}),
            ),
            const SizedBox(width: 8),
            const Text('Submit anonymously', style: TextStyle(fontSize: 13, color: Color(0xFF1A202C))),
          ],
        ),
        
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: _buildFormField('Your Name *', 'Full name', icon: Icons.person_outline)),
            const SizedBox(width: 20),
            Expanded(child: _buildFormField('Contact Number *', '+63 XXX XXX XXXX', icon: Icons.phone_outlined)),
          ],
        ),
        
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            border: Border.all(color: const Color(0xFFFDE68A)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('Note: False reporting is a serious offense and may result in legal action. Please ensure all information provided is accurate and truthful.', style: TextStyle(color: Color(0xFFB45309), fontSize: 13)),
        ),
        
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.send, size: 18),
                label: const Text('Submit Report'),
              ),
            ),
            const SizedBox(width: 16),
            OutlinedButton(
              onPressed: () {},
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Clear', style: TextStyle(color: Color(0xFF475569))),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFormField(String label, String hint, {IconData? icon, int maxLines = 1, bool isDate = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
            ],
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A202C))),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade200)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade200)),
            suffixIcon: isDate ? const Icon(Icons.calendar_today, size: 16, color: Colors.grey) : null,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // MODALS
  // ═══════════════════════════════════════════════════════════
  void _showUpdateInvestigationModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: const [
                Icon(Icons.shield_outlined, color: Colors.blue),
                SizedBox(width: 8),
                Text('Update Investigation', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ISR-2024-001 — Corner of Main St. and Rizal Ave., Barangay San Jose', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              const SizedBox(height: 24),
              _buildDropdownField('Assign Investigator *', 'Inspector Santos'),
              const SizedBox(height: 16),
              _buildDropdownField('Priority Level', 'High'),
              const SizedBox(height: 16),
              _buildFormField('Field Instructions / Initial Notes', 'Instructions for the investigator, site visit details, context...', maxLines: 3),
            ],
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.send, size: 16),
                  label: const Text('Update'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24)),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showCompileReportModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: const [
                Icon(Icons.edit_document, color: Colors.green),
                SizedBox(width: 8),
                Text('Compile Investigation Report', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
          ],
        ),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ISR-2024-001 • Assigned to Inspector Santos', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                const SizedBox(height: 24),
                _buildFormField('Investigation Findings *', 'What was found during field investigation...', maxLines: 3),
                const SizedBox(height: 16),
                _buildFormField('Evidence Collected', 'Photos, documents, physical samples...', maxLines: 2),
                const SizedBox(height: 16),
                _buildFormField('Witness Statements', 'Summary of witness accounts...', maxLines: 2),
                const SizedBox(height: 16),
                _buildFormField('Action Taken *', 'Citations, fines, cease-and-desist orders...', maxLines: 2),
                const SizedBox(height: 16),
                _buildFormField('Recommendation', 'Recommended follow-up actions...', maxLines: 2),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
            child: const Text('Submit Report'),
          ),
        ],
      ),
    );
  }

  void _showFullDetailsModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('ISR-2024-001 — Full Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _statusBadge('Investigating', Colors.blue),
                    const SizedBox(width: 8),
                    _statusBadge('High', Colors.deepOrange),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFD946EF).withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.phone_android, size: 12, color: Color(0xFFC026D3)),
                          SizedBox(width: 4),
                          Text('Mobile App', style: TextStyle(fontSize: 11, color: Color(0xFF86198F))),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('SUBMITTED REPORT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 16),
                      _infoItem(Icons.location_on_outlined, 'Location of Incident', 'Corner of Main St. and Rizal Ave., Barangay San Jose'),
                      const Divider(height: 30),
                      _infoItem(Icons.calendar_today_outlined, 'Date of Incident', 'Tuesday, January 9, 2024'),
                      const Divider(height: 30),
                      _infoItem(Icons.description_outlined, 'Description of Violation', 'Observed unauthorized slaughter operation in residential area during late evening hours. Multiple animals heard, strong odor present. Approximately 5-6 hogs being slaughtered without any visible permits or veterinary inspection.'),
                      const Divider(height: 30),
                      _infoItem(Icons.camera_alt_outlined, 'Photo Evidence', 'No photos attached', isGrey: true),
                      const Divider(height: 30),
                      _infoItem(Icons.person_outline, 'Reporter', 'Maria Cruz'),
                      const Divider(height: 30),
                      _infoItem(Icons.phone_outlined, 'Contact Number', '+63 917 123 4567'),
                      const Divider(height: 30),
                      _infoItem(Icons.access_time, 'Submitted At', '1/10/2024, 8:23:00 AM'),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text('Investigation Timeline', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _logEntry('1/10/2024, 9:00:00 AM', 'Report acknowledged', 'Received from mobile app'),
                _logEntry('1/10/2024, 10:30:00 AM', 'Investigation started', 'Assigned to Inspector Santos. High priority.'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A202C))),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(value, style: const TextStyle(color: Color(0xFF4A5568))),
              const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
            ],
          ),
        ),
      ],
    );
  }
}

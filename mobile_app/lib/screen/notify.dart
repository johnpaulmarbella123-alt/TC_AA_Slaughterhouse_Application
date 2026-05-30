import 'package:flutter/material.dart';

class NotificationContent extends StatefulWidget {
  const NotificationContent({super.key});

  @override
  State<NotificationContent> createState() => _NotificationContentState();
}

class _NotificationContentState extends State<NotificationContent> {
  bool isAllSelected = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F5F5), // Very light grey/white background
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildHeader(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: _buildTabs(),
          ),
          _buildNotificationList(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24.0),
      decoration: const BoxDecoration(
        color: Color(0xFFC8E6C9), // Light green banner
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 8),
          Text(
            'Notification',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'keeps customers updated on every step of their slaughter request.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => setState(() => isAllSelected = true),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            decoration: BoxDecoration(
              color: isAllSelected ? const Color(0xFF2E7D32) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'All',
              style: TextStyle(
                color: isAllSelected ? Colors.white : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        GestureDetector(
          onTap: () => setState(() => isAllSelected = false),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(
              'Unread',
              style: TextStyle(
                color: !isAllSelected ? const Color(0xFF2E7D32) : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationList() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          _buildSuccessCard(),
          _buildApprovalCard(),
          _buildActionCard(),
          _buildRejectionCard(),
          _buildAlertCard(),
          _buildReceiptCard(),
          _buildFailureCard(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildNotificationCard({
    required Widget icon,
    required String title,
    String? subtitle,
    required String timestamp,
    Widget? badge,
    Widget? actionButton,
    Widget? bottomAction,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              icon,
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          badge,
                        ],
                      ],
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // ignore: use_null_aware_elements
              if (actionButton != null) actionButton,
            ],
          ),
          if (bottomAction != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.bottomRight,
              child: bottomAction,
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.bottomRight,
            child: Text(
              timestamp,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessCard() {
    return _buildNotificationCard(
      icon: _buildIconContainer(
        color: const Color(0xFF4CAF50),
        icon: Icons.check,
      ),
      title: 'Request submitted successfully',
      subtitle: 'Ref code: #RQ12345',
      timestamp: 'Just now',
    );
  }

  Widget _buildApprovalCard() {
    return _buildNotificationCard(
      icon: _buildIconContainer(
        color: const Color(0xFF4CAF50),
        icon: Icons.check,
      ),
      title: 'Approved Request',
      subtitle: 'Date info: October 26, 2025',
      timestamp: '-1h ago',
    );
  }

  Widget _buildActionCard() {
    return _buildNotificationCard(
      icon: _buildIconContainer(
        color: Colors.blue,
        icon: Icons.search,
        solid: false,
      ),
      title: 'View Status Update',
      timestamp: '-2h ago',
      actionButton: OutlinedButton(
        onPressed: () {},
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.blue),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        ),
        child: const Text('View', style: TextStyle(color: Colors.blue)),
      ),
    );
  }

  Widget _buildRejectionCard() {
    return _buildNotificationCard(
      icon: _buildIconContainer(
        color: const Color(0xFFD32F2F),
        icon: Icons.close,
      ),
      title: 'Request Reject',
      timestamp: '-5h ago',
      bottomAction: OutlinedButton(
        onPressed: () {},
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.black),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text('Reschedule', style: TextStyle(color: Colors.black)),
      ),
    );
  }

  Widget _buildAlertCard() {
    return _buildNotificationCard(
      icon: _buildIconContainer(
        color: Colors.blue,
        icon: Icons.description_outlined,
        solid: false,
      ),
      title: 'Pig',
      badge: _buildBadge('Health Issue Detected', const Color(0xFFD32F2F)),
      timestamp: '-10m ago',
      bottomAction: ElevatedButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
        label: const Text('View Options', style: TextStyle(color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFD32F2F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _buildReceiptCard() {
    return _buildNotificationCard(
      icon: _buildIconContainer(
        color: Colors.blue,
        icon: Icons.receipt_long_outlined,
        solid: false,
      ),
      title: 'Slaughter Request Receipt Issued',
      timestamp: '-1d ago',
      bottomAction: OutlinedButton(
        onPressed: () {},
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.black),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text('View Receipt & Pay', style: TextStyle(color: Colors.black)),
      ),
    );
  }

  Widget _buildFailureCard() {
    return _buildNotificationCard(
      icon: _buildIconContainer(
        color: const Color(0xFFD32F2F),
        icon: Icons.event_busy,
      ),
      title: 'Pig',
      badge: _buildBadge('Operation Failed', const Color(0xFFD32F2F)),
      timestamp: '-2d ago',
    );
  }

  Widget _buildIconContainer({
    required Color color,
    required IconData icon,
    bool solid = true,
  }) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: solid ? color : color.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: solid ? Colors.white : color, size: 24),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

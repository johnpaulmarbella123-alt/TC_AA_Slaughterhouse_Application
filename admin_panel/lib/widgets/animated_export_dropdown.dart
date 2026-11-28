import 'package:flutter/material.dart';

/// Smooth, animated export dropdown anchored directly below its trigger button.
/// Replaces center-screen modal export popups with a fluid right-aligned panel.
class AnimatedExportDropdown extends StatefulWidget {
  final String activeReportName;
  final String periodLabel;
  final bool showAnalyticsSections;
  final bool canSendToNmis;
  final Future<void> Function(String analyticsSection) onExportPdf;
  final Future<void> Function(String analyticsSection) onExportCsv;
  final VoidCallback onSendToNmis;

  const AnimatedExportDropdown({
    super.key,
    required this.activeReportName,
    required this.periodLabel,
    required this.showAnalyticsSections,
    required this.canSendToNmis,
    required this.onExportPdf,
    required this.onExportCsv,
    required this.onSendToNmis,
  });

  @override
  State<AnimatedExportDropdown> createState() => _AnimatedExportDropdownState();
}

class _AnimatedExportDropdownState extends State<AnimatedExportDropdown>
    with SingleTickerProviderStateMixin {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;
  late final Animation<Offset> _slideAnim;
  bool _isOpen = false;
  String _selectedAnalyticsSection = 'all';

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 160),
    );
    final curved = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _fadeAnim = curved;
    _scaleAnim = Tween<double>(begin: 0.95, end: 1.0).animate(curved);
    _slideAnim = Tween<Offset>(begin: const Offset(0, -0.04), end: Offset.zero).animate(curved);
  }

  @override
  void didUpdateWidget(covariant AnimatedExportDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeReportName != widget.activeReportName) {
      _selectedAnalyticsSection = 'all';
      if (_isOpen) {
        _closeDropdown(immediate: true);
      }
    }
  }

  @override
  void dispose() {
    _closeDropdown(immediate: true);
    _animCtrl.dispose();
    super.dispose();
  }

  void _toggleDropdown() {
    if (_isOpen) {
      _closeDropdown();
    } else {
      _openDropdown();
    }
  }

  void _openDropdown() {
    if (_isOpen) return;
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final buttonSize = renderBox.size;
    final buttonOffset = renderBox.localToGlobal(Offset.zero);
    final screenWidth = MediaQuery.of(context).size.width;
    const double menuWidth = 340.0;

    // Right-align the dropdown with the Export button, clamped safely inside viewport
    double dx = buttonSize.width - menuWidth;
    final projectedLeft = buttonOffset.dx + dx;
    if (projectedLeft < 12) {
      dx = 12 - buttonOffset.dx;
    } else if (projectedLeft + menuWidth > screenWidth - 12) {
      dx = (screenWidth - 12 - menuWidth) - buttonOffset.dx;
    }

    _overlayEntry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeDropdown,
              child: const SizedBox.expand(),
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(dx, buttonSize.height + 8),
            child: Material(
              color: Colors.transparent,
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: ScaleTransition(
                    scale: _scaleAnim,
                    alignment: Alignment.topRight,
                    child: SizedBox(
                      width: menuWidth,
                      child: StatefulBuilder(
                        builder: (ctx, setMenuState) => _buildDropdownPanel(setMenuState),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(_overlayEntry!);
    setState(() => _isOpen = true);
    _animCtrl.forward(from: 0);
  }

  Future<void> _closeDropdown({bool immediate = false}) async {
    if (!_isOpen && _overlayEntry == null) return;
    if (mounted && !immediate) {
      setState(() => _isOpen = false);
      await _animCtrl.reverse();
    } else {
      _isOpen = false;
    }
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Widget _buildDropdownPanel(StateSetter setMenuState) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.14),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D6A4F).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(Icons.file_download_outlined, color: Color(0xFF2D6A4F), size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Export ${widget.activeReportName}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      widget.periodLabel,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (widget.showAnalyticsSections) ...[
            const SizedBox(height: 10),
            Divider(height: 1, color: Colors.grey.shade200),
            const SizedBox(height: 10),
            Text(
              'Analytics Section',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ('all', 'Full Report'),
                ('production', 'Operations'),
                ('health_issues', 'Condemnations'),
                ('uninspected', 'Held / Confined'),
              ].map((opt) {
                final isSel = _selectedAnalyticsSection == opt.$1;
                return InkWell(
                  onTap: () => setMenuState(() => _selectedAnalyticsSection = opt.$1),
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isSel ? const Color(0xFF2D6A4F) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      opt.$2,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                        color: isSel ? Colors.white : const Color(0xFF334155),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 10),
          Divider(height: 1, color: Colors.grey.shade200),
          const SizedBox(height: 8),

          _buildActionRow(
            icon: Icons.picture_as_pdf_rounded,
            iconColor: const Color(0xFFDC2626),
            title: 'Download as PDF',
            subtitle: 'Printable report for ${widget.activeReportName}',
            onTap: () async {
              final section = _selectedAnalyticsSection;
              await _closeDropdown();
              await widget.onExportPdf(section);
            },
          ),
          const SizedBox(height: 6),
          _buildActionRow(
            icon: Icons.table_chart_outlined,
            iconColor: const Color(0xFF15803D),
            title: 'Download as Excel (.csv)',
            subtitle: 'Spreadsheet file for ${widget.activeReportName}',
            onTap: () async {
              final section = _selectedAnalyticsSection;
              await _closeDropdown();
              await widget.onExportCsv(section);
            },
          ),
          if (widget.canSendToNmis) ...[
            const SizedBox(height: 6),
            _buildActionRow(
              icon: Icons.send_rounded,
              iconColor: const Color(0xFF1E3A8A),
              title: 'Send Directly to NMIS',
              subtitle: 'Generate PDF & email directly to NMIS',
              onTap: () async {
                await _closeDropdown();
                widget.onSendToNmis();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      hoverColor: const Color(0xFFF1F5F9),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Material(
        color: const Color(0xFF2D6A4F),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: _toggleDropdown,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.file_download_outlined, size: 17, color: Colors.white),
                const SizedBox(width: 8),
                const Text(
                  'Export',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _isOpen ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Smooth, compact animated dropdown calendar anchored directly below its trigger button.
/// Replaces full-screen / center-screen modal `showDatePicker` dialogs.
class AnimatedDateDropdown extends StatefulWidget {
  final DateTime selectedDate;
  final String label;
  final ValueChanged<DateTime> onDateSelected;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;

  const AnimatedDateDropdown({
    super.key,
    required this.selectedDate,
    required this.label,
    required this.onDateSelected,
    this.firstDate,
    this.lastDate,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    this.backgroundColor,
    this.borderColor,
  });

  @override
  State<AnimatedDateDropdown> createState() => _AnimatedDateDropdownState();
}

class _AnimatedDateDropdownState extends State<AnimatedDateDropdown>
    with SingleTickerProviderStateMixin {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  late final AnimationController _animCtrl;
  late final Animation<double> _curveAnim;
  late DateTime _visibleMonth;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _visibleMonth = DateTime(widget.selectedDate.year, widget.selectedDate.month);
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _curveAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
  }

  @override
  void didUpdateWidget(covariant AnimatedDateDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate && !_isOpen) {
      _visibleMonth = DateTime(widget.selectedDate.year, widget.selectedDate.month);
    }
  }

  @override
  void dispose() {
    _removeOverlayImmediate();
    _animCtrl.dispose();
    super.dispose();
  }

  void _removeOverlayImmediate() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isOpen = false;
  }

  Future<void> _closeDropdown() async {
    if (!_isOpen) return;
    _isOpen = false;
    if (mounted) setState(() {});
    await _animCtrl.reverse();
    _overlayEntry?.remove();
    _overlayEntry = null;
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
    _visibleMonth = DateTime(widget.selectedDate.year, widget.selectedDate.month);
    _isOpen = true;
    setState(() {});

    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    final triggerSize = renderBox?.size ?? const Size(160, 36);
    final triggerPos = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final screenWidth = MediaQuery.of(context).size.width;
    const double panelWidth = 296.0;

    // Auto-shift horizontally if the dropdown would overflow the right edge
    double dxOffset = 0.0;
    if (triggerPos.dx + panelWidth > screenWidth - 16) {
      dxOffset = (screenWidth - 16) - (triggerPos.dx + panelWidth);
      if (triggerPos.dx + dxOffset < 12) {
        dxOffset = 12 - triggerPos.dx;
      }
    }

    _overlayEntry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeDropdown,
            ),
          ),
          Positioned(
            width: panelWidth,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: Offset(dxOffset, triggerSize.height + 6),
              child: Material(
                color: Colors.transparent,
                child: AnimatedBuilder(
                  animation: _curveAnim,
                  builder: (context, child) {
                    return FadeTransition(
                      opacity: _curveAnim,
                      child: SizeTransition(
                        sizeFactor: _curveAnim,
                        axisAlignment: -1.0,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.96, end: 1.0).animate(_curveAnim),
                          alignment: Alignment.topCenter,
                          child: child,
                        ),
                      ),
                    );
                  },
                  child: StatefulBuilder(
                    builder: (context, setPanelState) => _buildCalendarCard(setPanelState),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(_overlayEntry!);
    _animCtrl.forward(from: 0.0);
  }

  Widget _buildCalendarCard(StateSetter setPanelState) {
    final firstDay = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final lastDay = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0);
    final startWeekday = firstDay.weekday % 7; // Sun=0..Sat=6
    final daysInMonth = lastDay.day;
    final prevMonthLastDay = DateTime(_visibleMonth.year, _visibleMonth.month, 0).day;
    final now = DateTime.now();
    final minDate = widget.firstDate ?? DateTime(2020);
    final maxDate = widget.lastDate ?? DateTime(2035);

    final cells = <Widget>[];
    for (int i = 0; i < startWeekday; i++) {
      final dayNum = prevMonthLastDay - startWeekday + i + 1;
      cells.add(_dayCell(dayNum.toString(), isOtherMonth: true));
    }
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(_visibleMonth.year, _visibleMonth.month, d);
      final isSelected = widget.selectedDate.year == date.year &&
          widget.selectedDate.month == date.month &&
          widget.selectedDate.day == date.day;
      final isToday = now.year == date.year && now.month == date.month && now.day == date.day;
      final isDisabled = date.isBefore(DateTime(minDate.year, minDate.month, minDate.day)) ||
          date.isAfter(DateTime(maxDate.year, maxDate.month, maxDate.day));

      cells.add(
        _dayCell(
          d.toString(),
          isSelected: isSelected,
          isToday: isToday,
          isDisabled: isDisabled,
          onTap: isDisabled
              ? null
              : () {
                  widget.onDateSelected(date);
                  _closeDropdown();
                },
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.14),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => setPanelState(() {
                  _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
                }),
                icon: const Icon(Icons.chevron_left, size: 18, color: Color(0xFF334155)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                splashRadius: 16,
              ),
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy').format(_visibleMonth),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => setPanelState(() {
                  _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
                }),
                icon: const Icon(Icons.chevron_right, size: 18, color: Color(0xFF334155)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                splashRadius: 16,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: const ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa']
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 4),
          ...List.generate(
            (cells.length + 6) ~/ 7,
            (row) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                children: List.generate(7, (col) {
                  final idx = row * 7 + col;
                  return Expanded(child: idx < cells.length ? cells[idx] : const SizedBox.shrink());
                }),
              ),
            ),
          ),
          const Divider(height: 14, color: Color(0xFFE2E8F0)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () {
                  final today = DateTime(now.year, now.month, now.day);
                  widget.onDateSelected(today);
                  _closeDropdown();
                },
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF0F5132),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Today', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              TextButton(
                onPressed: _closeDropdown,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF64748B),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Close', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dayCell(
    String label, {
    bool isSelected = false,
    bool isToday = false,
    bool isOtherMonth = false,
    bool isDisabled = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF0F5132)
              : isToday
                  ? const Color(0xFF0F5132).withValues(alpha: 0.12)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: (isSelected || isToday) ? FontWeight.w700 : FontWeight.w500,
              color: isSelected
                  ? Colors.white
                  : (isOtherMonth || isDisabled)
                      ? Colors.grey.shade300
                      : const Color(0xFF1E293B),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: InkWell(
        onTap: _toggleDropdown,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.backgroundColor ?? Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: widget.borderColor != null
                ? Border.all(
                    color: _isOpen ? const Color(0xFF0F5132) : widget.borderColor!,
                    width: _isOpen ? 1.4 : 1.0,
                  )
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.calendar_today_outlined, size: 14, color: Color(0xFF2D6A4F)),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D3748),
                ),
              ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: _isOpen ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: const Icon(Icons.keyboard_arrow_down, size: 16, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

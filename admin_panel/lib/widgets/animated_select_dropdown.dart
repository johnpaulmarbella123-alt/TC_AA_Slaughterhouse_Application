import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Smooth downward-gliding select dropdown anchored cleanly beneath its trigger.
/// Replaces Material's abrupt floating `DropdownButton` overlay.
class AnimatedSelectDropdown<T> extends StatefulWidget {
  final T value;
  final List<T> items;
  final String Function(T item) labelBuilder;
  final IconData? Function(T item)? iconBuilder;
  final ValueChanged<T> onChanged;
  final Color backgroundColor;
  final Color borderColor;
  final Color textColor;
  final Color iconColor;
  final double? minMenuWidth;
  final EdgeInsetsGeometry padding;

  const AnimatedSelectDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
    this.iconBuilder,
    this.backgroundColor = const Color(0xFFEDF2F7),
    this.borderColor = Colors.transparent,
    this.textColor = const Color(0xFF1E293B),
    this.iconColor = const Color(0xFF64748B),
    this.minMenuWidth,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  });

  @override
  State<AnimatedSelectDropdown<T>> createState() => _AnimatedSelectDropdownState<T>();
}

class _AnimatedSelectDropdownState<T> extends State<AnimatedSelectDropdown<T>>
    with SingleTickerProviderStateMixin {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;
  late final Animation<Offset> _slideAnim;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 150),
    );
    final curved = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _fadeAnim = curved;
    _scaleAnim = Tween<double>(begin: 0.96, end: 1.0).animate(curved);
    _slideAnim = Tween<Offset>(begin: const Offset(0, -0.04), end: Offset.zero).animate(curved);
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

    final triggerSize = renderBox.size;
    final triggerOffset = renderBox.localToGlobal(Offset.zero);
    final screenWidth = MediaQuery.of(context).size.width;
    final double menuWidth = math.max(
      triggerSize.width,
      widget.minMenuWidth ?? 210.0,
    );

    double dx = 0;
    if (triggerOffset.dx + menuWidth > screenWidth - 12) {
      dx = (screenWidth - 12 - menuWidth) - triggerOffset.dx;
    }
    if (triggerOffset.dx + dx < 12) {
      dx = 12 - triggerOffset.dx;
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
            offset: Offset(dx, triggerSize.height + 6),
            child: Material(
              color: Colors.transparent,
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: ScaleTransition(
                    scale: _scaleAnim,
                    alignment: Alignment.topLeft,
                    child: Container(
                      width: menuWidth,
                      constraints: const BoxConstraints(maxHeight: 360),
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0F172A).withValues(alpha: 0.13),
                            blurRadius: 22,
                            offset: const Offset(0, 10),
                          ),
                          BoxShadow(
                            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: widget.items.map((item) {
                            final isSelected = item == widget.value;
                            final icon = widget.iconBuilder?.call(item);
                            return InkWell(
                              onTap: () async {
                                await _closeDropdown();
                                if (item != widget.value) {
                                  widget.onChanged(item);
                                } else if (widget.labelBuilder(item) == 'Custom Range') {
                                  widget.onChanged(item);
                                }
                              },
                              borderRadius: BorderRadius.circular(8),
                              hoverColor: const Color(0xFFF1F5F9),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 120),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFF2D6A4F).withValues(alpha: 0.10)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    if (icon != null) ...[
                                      Icon(
                                        icon,
                                        size: 16,
                                        color: isSelected
                                            ? const Color(0xFF2D6A4F)
                                            : const Color(0xFF64748B),
                                      ),
                                      const SizedBox(width: 9),
                                    ],
                                    Expanded(
                                      child: Text(
                                        widget.labelBuilder(item),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                          color: isSelected
                                              ? const Color(0xFF1B4332)
                                              : const Color(0xFF334155),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isSelected)
                                      const Icon(
                                        Icons.check_rounded,
                                        size: 16,
                                        color: Color(0xFF2D6A4F),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
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

  @override
  Widget build(BuildContext context) {
    final activeIcon = widget.iconBuilder?.call(widget.value);
    return CompositedTransformTarget(
      link: _layerLink,
      child: Material(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: _toggleDropdown,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            padding: widget.padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: _isOpen
                    ? const Color(0xFF2D6A4F).withValues(alpha: 0.65)
                    : widget.borderColor,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (activeIcon != null) ...[
                  Icon(activeIcon, size: 16, color: widget.iconColor),
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.labelBuilder(widget.value),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: widget.textColor,
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: _isOpen ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 19,
                    color: widget.iconColor,
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

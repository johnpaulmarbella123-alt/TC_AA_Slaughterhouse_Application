import 'package:flutter/material.dart';

enum LucideSidebarIcon {
  layoutGrid,
  clipboardPlus,
  clipboardCheck,
  stethoscope,
  receiptDollar,
  truck,
  fileText,
  settings,
  user,
  logOut,
  panelLeftClose,
  panelLeftOpen,
}

/// Crisp Lucide-style outline vector icon (`24x24` viewBox, `strokeWidth: 1.75`,
/// `StrokeCap.round`, `StrokeJoin.round`, no fill).
class LucideIcon extends StatelessWidget {
  final LucideSidebarIcon icon;
  final double size;
  final Color color;
  final double strokeWidth;

  const LucideIcon(
    this.icon, {
    super.key,
    this.size = 20,
    required this.color,
    this.strokeWidth = 1.75,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _LucidePainter(
          icon: icon,
          color: color,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _LucidePainter extends CustomPainter {
  final LucideSidebarIcon icon;
  final Color color;
  final double strokeWidth;

  _LucidePainter({
    required this.icon,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 24.0;
    final sy = size.height / 24.0;
    canvas.save();
    canvas.scale(sx, sy);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    switch (icon) {
      case LucideSidebarIcon.layoutGrid:
        _rrect(canvas, 3, 3, 7, 7, 1.5, paint);
        _rrect(canvas, 14, 3, 7, 7, 1.5, paint);
        _rrect(canvas, 14, 14, 7, 7, 1.5, paint);
        _rrect(canvas, 3, 14, 7, 7, 1.5, paint);
        break;

      case LucideSidebarIcon.clipboardPlus:
        _rrect(canvas, 8, 2, 8, 4, 1, paint);
        final clip = Path()
          ..moveTo(16, 4)
          ..lineTo(18, 4)
          ..arcToPoint(const Offset(20, 6), radius: const Radius.circular(2))
          ..lineTo(20, 20)
          ..arcToPoint(const Offset(18, 22), radius: const Radius.circular(2))
          ..lineTo(6, 22)
          ..arcToPoint(const Offset(4, 20), radius: const Radius.circular(2))
          ..lineTo(4, 6)
          ..arcToPoint(const Offset(6, 4), radius: const Radius.circular(2))
          ..lineTo(8, 4);
        canvas.drawPath(clip, paint);
        canvas.drawLine(const Offset(9, 14), const Offset(15, 14), paint);
        canvas.drawLine(const Offset(12, 11), const Offset(12, 17), paint);
        break;

      case LucideSidebarIcon.clipboardCheck:
        _rrect(canvas, 8, 2, 8, 4, 1, paint);
        final clip = Path()
          ..moveTo(16, 4)
          ..lineTo(18, 4)
          ..arcToPoint(const Offset(20, 6), radius: const Radius.circular(2))
          ..lineTo(20, 20)
          ..arcToPoint(const Offset(18, 22), radius: const Radius.circular(2))
          ..lineTo(6, 22)
          ..arcToPoint(const Offset(4, 20), radius: const Radius.circular(2))
          ..lineTo(4, 6)
          ..arcToPoint(const Offset(6, 4), radius: const Radius.circular(2))
          ..lineTo(8, 4);
        canvas.drawPath(clip, paint);
        final check = Path()
          ..moveTo(9, 14)
          ..lineTo(11, 16)
          ..lineTo(15, 12);
        canvas.drawPath(check, paint);
        break;

      case LucideSidebarIcon.stethoscope:
        canvas.drawLine(const Offset(4, 2), const Offset(6, 2), paint);
        canvas.drawLine(const Offset(12, 2), const Offset(14, 2), paint);
        final u = Path()
          ..moveTo(4, 2)
          ..lineTo(4, 8)
          ..arcToPoint(const Offset(14, 8), radius: const Radius.circular(5), clockwise: false)
          ..lineTo(14, 2);
        canvas.drawPath(u, paint);
        final tube = Path()
          ..moveTo(9, 13)
          ..lineTo(9, 16)
          ..arcToPoint(const Offset(19, 16), radius: const Radius.circular(5), clockwise: false)
          ..lineTo(19, 12);
        canvas.drawPath(tube, paint);
        canvas.drawCircle(const Offset(19, 10), 2, paint);
        break;

      case LucideSidebarIcon.receiptDollar:
        final receipt = Path()
          ..moveTo(4, 2)
          ..lineTo(4, 22)
          ..lineTo(6, 21)
          ..lineTo(8, 22)
          ..lineTo(10, 21)
          ..lineTo(12, 22)
          ..lineTo(14, 21)
          ..lineTo(16, 22)
          ..lineTo(18, 21)
          ..lineTo(20, 22)
          ..lineTo(20, 2)
          ..lineTo(18, 3)
          ..lineTo(16, 2)
          ..lineTo(14, 3)
          ..lineTo(12, 2)
          ..lineTo(10, 3)
          ..lineTo(8, 2)
          ..lineTo(6, 3)
          ..close();
        canvas.drawPath(receipt, paint);
        // Crisp '$' inside receipt
        final sPath = Path()
          ..moveTo(15, 8.5)
          ..lineTo(10.5, 8.5)
          ..arcToPoint(const Offset(10.5, 12), radius: const Radius.circular(1.75), clockwise: false)
          ..lineTo(13.5, 12)
          ..arcToPoint(const Offset(13.5, 15.5), radius: const Radius.circular(1.75))
          ..lineTo(9, 15.5);
        canvas.drawPath(sPath, paint);
        canvas.drawLine(const Offset(12, 6.8), const Offset(12, 17.2), paint);
        break;

      case LucideSidebarIcon.truck:
        final cargo = Path()
          ..moveTo(14, 18)
          ..lineTo(14, 6)
          ..arcToPoint(const Offset(12, 4), radius: const Radius.circular(2), clockwise: false)
          ..lineTo(4, 4)
          ..arcToPoint(const Offset(2, 6), radius: const Radius.circular(2), clockwise: false)
          ..lineTo(2, 16)
          ..arcToPoint(const Offset(4, 18), radius: const Radius.circular(2), clockwise: false)
          ..lineTo(5, 18);
        canvas.drawPath(cargo, paint);
        final cab = Path()
          ..moveTo(14, 8)
          ..lineTo(18.5, 8)
          ..lineTo(22, 12)
          ..lineTo(22, 17)
          ..arcToPoint(const Offset(21, 18), radius: const Radius.circular(1))
          ..lineTo(19, 18);
        canvas.drawPath(cab, paint);
        canvas.drawLine(const Offset(9, 18), const Offset(15, 18), paint);
        canvas.drawCircle(const Offset(7, 18), 2, paint);
        canvas.drawCircle(const Offset(17, 18), 2, paint);
        break;

      case LucideSidebarIcon.fileText:
        final doc = Path()
          ..moveTo(15, 2)
          ..lineTo(6, 2)
          ..arcToPoint(const Offset(4, 4), radius: const Radius.circular(2), clockwise: false)
          ..lineTo(4, 20)
          ..arcToPoint(const Offset(6, 22), radius: const Radius.circular(2), clockwise: false)
          ..lineTo(18, 22)
          ..arcToPoint(const Offset(20, 20), radius: const Radius.circular(2), clockwise: false)
          ..lineTo(20, 7)
          ..close();
        canvas.drawPath(doc, paint);
        final fold = Path()
          ..moveTo(14, 2)
          ..lineTo(14, 7)
          ..lineTo(20, 7);
        canvas.drawPath(fold, paint);
        canvas.drawLine(const Offset(8, 13), const Offset(16, 13), paint);
        canvas.drawLine(const Offset(8, 17), const Offset(16, 17), paint);
        canvas.drawLine(const Offset(8, 9), const Offset(10, 9), paint);
        break;

      case LucideSidebarIcon.settings:
        canvas.drawCircle(const Offset(12, 12), 3, paint);
        canvas.drawCircle(const Offset(12, 12), 7.2, paint);
        for (int i = 0; i < 8; i++) {
          final angle = i * 3.14159265 / 4;
          final cosA = _cos(angle);
          final sinA = _sin(angle);
          canvas.drawLine(
            Offset(12 + 7.2 * cosA, 12 + 7.2 * sinA),
            Offset(12 + 9.6 * cosA, 12 + 9.6 * sinA),
            paint,
          );
        }
        break;

      case LucideSidebarIcon.user:
        canvas.drawCircle(const Offset(12, 8), 4, paint);
        final body = Path()
          ..moveTo(5, 20)
          ..arcToPoint(const Offset(19, 20), radius: const Radius.circular(7));
        canvas.drawPath(body, paint);
        break;

      case LucideSidebarIcon.logOut:
        final door = Path()
          ..moveTo(9, 21)
          ..lineTo(5, 21)
          ..arcToPoint(const Offset(3, 19), radius: const Radius.circular(2))
          ..lineTo(3, 5)
          ..arcToPoint(const Offset(5, 3), radius: const Radius.circular(2))
          ..lineTo(9, 3);
        canvas.drawPath(door, paint);
        final arrow = Path()
          ..moveTo(16, 17)
          ..lineTo(21, 12)
          ..lineTo(16, 7);
        canvas.drawPath(arrow, paint);
        canvas.drawLine(const Offset(21, 12), const Offset(9, 12), paint);
        break;

      case LucideSidebarIcon.panelLeftClose:
        _rrect(canvas, 3, 3, 18, 18, 2.5, paint);
        canvas.drawLine(const Offset(9, 3), const Offset(9, 21), paint);
        final chev = Path()
          ..moveTo(16, 9.5)
          ..lineTo(13.5, 12)
          ..lineTo(16, 14.5);
        canvas.drawPath(chev, paint);
        break;

      case LucideSidebarIcon.panelLeftOpen:
        _rrect(canvas, 3, 3, 18, 18, 2.5, paint);
        canvas.drawLine(const Offset(9, 3), const Offset(9, 21), paint);
        final chev = Path()
          ..moveTo(13.5, 9.5)
          ..lineTo(16, 12)
          ..lineTo(13.5, 14.5);
        canvas.drawPath(chev, paint);
        break;
    }

    canvas.restore();
  }

  void _rrect(Canvas c, double l, double t, double w, double h, double r, Paint p) {
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(l, t, w, h), Radius.circular(r)), p);
  }

  double _cos(double rad) {
    const vals = [1.0, 0.70710678, 0.0, -0.70710678, -1.0, -0.70710678, 0.0, 0.70710678];
    return vals[((rad / (3.14159265 / 4)).round()) % 8];
  }

  double _sin(double rad) {
    const vals = [0.0, 0.70710678, 1.0, 0.70710678, 0.0, -0.70710678, -1.0, -0.70710678];
    return vals[((rad / (3.14159265 / 4)).round()) % 8];
  }

  @override
  bool shouldRepaint(covariant _LucidePainter oldDelegate) =>
      oldDelegate.icon != icon ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}

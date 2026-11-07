import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/scan_models.dart';

class FaceBoxPainter extends CustomPainter {
  final List<LeaderScanItem> items;
  final Size originalSize;
  final int activeIndex;

  FaceBoxPainter({
    required this.items,
    required this.originalSize,
    required this.activeIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (originalSize.width <= 0 || originalSize.height <= 0) return;

    final double scaleX = size.width / originalSize.width;
    final double scaleY = size.height / originalSize.height;

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final isSel = (i == activeIndex);

      final left = item.box.left * scaleX;
      final top = item.box.top * scaleY;
      final width = (item.box.right - item.box.left) * scaleX;
      final height = (item.box.bottom - item.box.top) * scaleY;

      final paint = Paint()
        ..color = isSel
            ? Colors.amberAccent
            : (item.identified ? Colors.greenAccent : Colors.redAccent)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSel ? 3.5 : 2.0;

      final rect = Rect.fromLTWH(left, top, width, height);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), paint);

      final span = TextSpan(
        text: ' #${item.faceIndex} ',
        style: TextStyle(
          color: Colors.white,
          backgroundColor: isSel ? Colors.amber[900] : Colors.black87,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      );
      final tp = TextPainter(text: span, textDirection: TextDirection.ltr)..layout();
      final textY = math.max(0.0, top - 18);
      tp.paint(canvas, Offset(left, textY));
    }
  }

  @override
  bool shouldRepaint(covariant FaceBoxPainter old) =>
      old.activeIndex != activeIndex || old.items != items || old.originalSize != originalSize;
}

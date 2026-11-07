import 'package:flutter/material.dart';

class AnimatedComparisonBar extends StatelessWidget {
  final String label;
  final double valueA;
  final double valueB;
  final String displayValA;
  final String displayValB;
  final Color colorA;
  final Color colorB;

  const AnimatedComparisonBar({
    super.key,
    required this.label,
    required this.valueA,
    required this.valueB,
    required this.displayValA,
    required this.displayValB,
    this.colorA = Colors.blue,
    this.colorB = Colors.teal,
  });

  @override
  Widget build(BuildContext context) {
    final double total = valueA + valueB;
    final double targetRatioA = (total > 0) ? (valueA / total) : 0.5;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(displayValA, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorA)),
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
              Text(displayValB, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorB)),
            ],
          ),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: targetRatioA),
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeOutCubic,
            builder: (context, currentRatioA, child) {
              final double currentRatioB = 1.0 - currentRatioA;
              int flexA = (currentRatioA * 1000).toInt().clamp(1, 999);
              int flexB = (currentRatioB * 1000).toInt().clamp(1, 999);

              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 10,
                  child: Row(
                    children: [
                      Expanded(flex: flexA, child: Container(color: colorA)),
                      const SizedBox(width: 2),
                      Expanded(flex: flexB, child: Container(color: colorB)),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
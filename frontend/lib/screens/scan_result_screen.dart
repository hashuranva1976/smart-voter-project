import 'dart:io';
import 'package:flutter/material.dart';
import '../models/scan_models.dart';
import '../widgets/box_painter.dart';
import 'leader_detail_screen.dart';
import 'comparison_screen.dart';

class ScanResultScreen extends StatefulWidget {
  final File file;
  final List<LeaderScanItem> leaders;
  final Size originalSize;

  const ScanResultScreen({
    super.key,
    required this.file,
    required this.leaders,
    required this.originalSize,
  });

  @override
  State<ScanResultScreen> createState() => _ScanResultScreenState();
}

class _ScanResultScreenState extends State<ScanResultScreen> {
  int _active = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _openComparison(List<LeaderScanItem> identifiedList) {
    if (identifiedList.length < 2) return;

    if (identifiedList.length == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ComparisonScreen(
            candA: identifiedList[0].reportCard!,
            candB: identifiedList[1].reportCard!,
          ),
        ),
      );
      return;
    }

    // જો 2 થી વધુ ઉમેદવારો હોય તો પસંદગી માટે ડાયલોગ
    int selectedA = 0;
    int selectedB = 1;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('સરખામણી માટે ઉમેદવાર પસંદ કરો'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: selectedA,
                  decoration: const InputDecoration(labelText: 'પ્રથમ ઉમેદવાર (A)'),
                  items: List.generate(identifiedList.length, (i) {
                    final card = identifiedList[i].reportCard!;
                    return DropdownMenuItem(
                      value: i,
                      child: Text(card['full_name']?.toString() ?? 'ઉમેદવાર ${i + 1}'),
                    );
                  }),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedA = val);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: selectedB,
                  decoration: const InputDecoration(labelText: 'બીજો ઉમેદવાર (B)'),
                  items: List.generate(identifiedList.length, (i) {
                    final card = identifiedList[i].reportCard!;
                    return DropdownMenuItem(
                      value: i,
                      child: Text(card['full_name']?.toString() ?? 'ઉમેદવાર ${i + 1}'),
                    );
                  }),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedB = val);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('રદ કરો'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (selectedA == selectedB) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('બે અલગ ઉમેદવારો પસંદ કરો')),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ComparisonScreen(
                        candA: identifiedList[selectedA].reportCard!,
                        candB: identifiedList[selectedB].reportCard!,
                      ),
                    ),
                  );
                },
                child: const Text('સરખાવો'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final identifiedList = widget.leaders
        .where((l) => l.identified && l.reportCard != null)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('સ્કેન વિશ્લેષણ'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          if (identifiedList.length >= 2)
            IconButton(
              icon: const Icon(Icons.compare_arrows),
              tooltip: 'સરખામણી કરો',
              onPressed: () => _openComparison(identifiedList),
            )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: FittedBox(
                child: SizedBox(
                  width: widget.originalSize.width > 0 ? widget.originalSize.width : 300,
                  height: widget.originalSize.height > 0 ? widget.originalSize.height : 400,
                  child: Stack(
                    children: [
                      Image.file(widget.file, fit: BoxFit.fill),
                      CustomPaint(
                        painter: FaceBoxPainter(
                          items: widget.leaders,
                          originalSize: widget.originalSize,
                          activeIndex: _active,
                        ),
                        size: widget.originalSize,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: widget.leaders.isEmpty
                ? const Center(child: Text('કોઈ ચહેરો મળ્યો નથી'))
                : PageView.builder(
                    controller: _pageController,
                    itemCount: widget.leaders.length,
                    onPageChanged: (i) => setState(() => _active = i),
                    itemBuilder: (context, i) {
                      final item = widget.leaders[i];
                      if (!item.identified || item.reportCard == null) {
                        return const Card(
                          margin: EdgeInsets.all(16),
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text(
                                'અજ્ઞાત ચહેરો\n(ડેટાબેઝમાં રેકોર્ડ મળ્યો નથી)',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.black54),
                              ),
                            ),
                          ),
                        );
                      }
                      final c = item.reportCard!;
                      final fullName = c['full_name']?.toString() ?? 'અનામી ઉમેદવાર';
                      final party = c['party_name']?.toString() ?? '-';
                      final constituency = c['constituency']?.toString() ?? '-';

                      return Card(
                        margin: const EdgeInsets.all(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => LeaderDetailScreen(reportCard: c),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        fullName,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Chip(
                                      label: Text(
                                        '${item.confidence.toStringAsFixed(1)}% મેળ',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$party | $constituency',
                                  style: const TextStyle(color: Colors.black87),
                                ),
                                const Divider(height: 24),
                                const Row(
                                  children: [
                                    Text(
                                      'સંપૂર્ણ પ્રોફાઇલ જોવા માટે ટેપ કરો...',
                                      style: TextStyle(
                                        color: Colors.indigo,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Spacer(),
                                    Icon(Icons.arrow_forward_ios, size: 14, color: Colors.indigo),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

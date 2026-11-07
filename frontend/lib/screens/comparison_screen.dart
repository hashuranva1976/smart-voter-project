import 'dart:io';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/animated_bar.dart';

class ComparisonScreen extends StatefulWidget {
  final Map<String, dynamic> candA;
  final Map<String, dynamic> candB;

  const ComparisonScreen({super.key, required this.candA, required this.candB});

  @override
  State<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends State<ComparisonScreen> {
  final ScreenshotController _ctrl = ScreenshotController();
  bool _sharing = false;

  String _formatInrShort(double amt) {
    if (amt >= 10000000) return '₹ ${(amt / 10000000).toStringAsFixed(2)} Cr';
    if (amt >= 100000) return '₹ ${(amt / 100000).toStringAsFixed(1)} L';
    return '₹ ${amt.toStringAsFixed(0)}';
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final img = await _ctrl.capture(pixelRatio: 2.0);
      if (img != null) {
        final dir = await getTemporaryDirectory();
        final file = await File('${dir.path}/comparison.png').create();
        await file.writeAsBytes(img);
        await Share.shareXFiles([XFile(file.path)], text: 'સ્માર્ટ વોટર એપ: ઉમેદવારોનો સરખામણી રિપોર્ટ');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('શેર કરવામાં ભૂલ આવી: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final assetA = (widget.candA['assets'] as List? ?? []).isNotEmpty ? widget.candA['assets'][0] : null;
    final assetB = (widget.candB['assets'] as List? ?? []).isNotEmpty ? widget.candB['assets'][0] : null;

    final double movA = double.tryParse(assetA?['movable_assets']?.toString() ?? '0') ?? 0.0;
    final double movB = double.tryParse(assetB?['movable_assets']?.toString() ?? '0') ?? 0.0;

    final nameA = widget.candA['full_name']?.toString() ?? 'ઉમેદવાર A';
    final nameB = widget.candB['full_name']?.toString() ?? 'ઉમેદવાર B';

    final partyA = widget.candA['party_name']?.toString() ?? '-';
    final partyB = widget.candB['party_name']?.toString() ?? '-';

    final eduA = widget.candA['education']?.toString() ?? '-';
    final eduB = widget.candB['education']?.toString() ?? '-';

    final casesCountA = (widget.candA['criminal_cases'] as List? ?? []).length;
    final casesCountB = (widget.candB['criminal_cases'] as List? ?? []).length;

    final perfA = widget.candA['performance'] as Map? ?? {};
    final perfB = widget.candB['performance'] as Map? ?? {};

    final attA = perfA['attendance_percentage'] != null ? '${perfA['attendance_percentage']}%' : '-';
    final attB = perfB['attendance_percentage'] != null ? '${perfB['attendance_percentage']}%' : '-';

    return Scaffold(
      appBar: AppBar(
        title: const Text('ઉમેદવારોની સરખામણી'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: _sharing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.share),
            onPressed: _sharing ? null : _share,
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Screenshot(
              controller: _ctrl,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, 0.05),
                      blurRadius: 10,
                      spreadRadius: 1,
                    )
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Expanded(
                          child: Text(
                            nameA,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'VS',
                            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            nameB,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    _compareRow('પક્ષ', partyA, partyB),
                    _compareRow('શિક્ષણ', eduA, eduB),
                    _compareRow('કેસો', '$casesCountA', '$casesCountB'),
                    _compareRow('હાજરી', attA, attB),
                    const SizedBox(height: 16),
                    AnimatedComparisonBar(
                      label: 'ચલ સંપત્તિ સરખામણી',
                      valueA: movA,
                      valueB: movB,
                      displayValA: _formatInrShort(movA),
                      displayValB: _formatInrShort(movB),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _sharing ? null : _share,
              icon: const Icon(Icons.share),
              label: const Text('સરખામણી કાર્ડ શેર કરો', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compareRow(String label, String a, String b) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(a, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
          Container(
            width: 80,
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(color: Colors.black45, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          Expanded(child: Text(b, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

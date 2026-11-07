import 'package:flutter/material.dart';

class LeaderDetailScreen extends StatelessWidget {
  final Map<String, dynamic> reportCard;

  const LeaderDetailScreen({super.key, required this.reportCard});

  String _formatInr(dynamic val) {
    double amt = double.tryParse(val?.toString() ?? '0') ?? 0.0;
    if (amt >= 10000000) return '₹ ${(amt / 10000000).toStringAsFixed(2)} કરોડ';
    if (amt >= 100000) return '₹ ${(amt / 100000).toStringAsFixed(2)} લાખ';
    return '₹ ${amt.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final assets = (reportCard['assets'] as List? ?? []);
    final asset = assets.isNotEmpty ? assets[0] : null;
    final cases = (reportCard['criminal_cases'] as List? ?? []);
    final perf = (reportCard['performance'] as Map? ?? {});

    final fullName = reportCard['full_name']?.toString().trim() ?? 'ઉમેદવાર પ્રોફાઇલ';
    final initial = fullName.isNotEmpty ? fullName[0] : '?';
    final partyName = reportCard['party_name']?.toString() ?? '-';
    final constituency = reportCard['constituency']?.toString() ?? '-';
    final education = reportCard['education']?.toString() ?? '-';

    return Scaffold(
      appBar: AppBar(
        title: Text(fullName),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.indigo.shade100,
                  child: Text(
                    initial,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
                  ),
                ),
                title: Text(fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('$partyName | $constituency\nશિક્ષણ: $education'),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'સંપત્તિ અને દેવું (Affidavit)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _row('ચલ સંપત્તિ', _formatInr(asset?['movable_assets'])),
                    const Divider(),
                    _row('અચલ સંપત્તિ', _formatInr(asset?['immovable_assets'])),
                    const Divider(),
                    _row('દેવું / લોન', _formatInr(asset?['total_liabilities']), isRed: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'જાહેર થયેલા કેસો (${cases.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (cases.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.green),
                  title: Text('કોઈ જાહેર કેસ નથી'),
                ),
              )
            else
              ...cases.map((c) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.warning, color: Colors.red),
                      title: Text(c['case_details']?.toString() ?? 'કેસ વિગત ઉપલબ્ધ નથી'),
                      subtitle: Text('સ્થિતિ: ${c['case_status']?.toString() ?? '-'}'),
                    ),
                  )),
            const SizedBox(height: 16),
            const Text(
              'સંસદીય / વિધાનસભા કામગીરી',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat('હાજરી', perf['attendance_percentage'] != null ? '${perf['attendance_percentage']}%' : '-'),
                    _stat('પ્રશ્નો', '${perf['questions_asked'] ?? '-'}'),
                    _stat('ચર્ચાઓ', '${perf['debates_participated'] ?? '-'}'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v, {bool isRed = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(k),
        Text(
          v,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isRed ? Colors.red : Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _stat(String k, String v) {
    return Column(
      children: [
        Text(
          v,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.indigo,
          ),
        ),
        Text(k, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }
}

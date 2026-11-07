import 'package:flutter_test/flutter_test.dart';
import 'package:smart_voter/main.dart';

void main() {
  testWidgets('Smart Voter home screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // Verify title and main buttons exist
    expect(find.text('સ્માર્ટ વોટર - પોસ્ટર સ્કેનર'), findsOneWidget);
    expect(find.text('કેમેરાથી સ્કેન કરો'), findsOneWidget);
    expect(find.text('ગેલેરીમાંથી પસંદ કરો'), findsOneWidget);
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:medigo/main.dart';
import 'package:medigo/services/prescription_extractor.dart';

void main() {
  testWidgets('MediGo app loads the onboarding flow', (WidgetTester tester) async {
    await tester.pumpWidget(const MediGoApp(requireAuth: false));

    expect(find.text('MediGo'), findsOneWidget);
    expect(find.text('Safer dispensing'), findsOneWidget);
  });

  test('extracts medicine fields without treating doctor metadata as medicine', () {
    final items = PrescriptionExtractor.parsePrintedLines(
      [
        'Clinic: MediGo Demo Clinic',
        'Doctor: Dr. Demo User License No: DEMO-0001',
        'Paracetamol 500 mg Quantity: 2 tablets',
        'Cetirizine 10 mg Qty: 1 tablet',
        'Doctor seal 12345',
      ],
      ['Paracetamol', 'Cetirizine', 'ORS'],
    );

    expect(items, hasLength(2));
    expect(items[0].medicine, 'Paracetamol');
    expect(items[0].quantity, 2);
    expect(items[1].medicine, 'Cetirizine');
    expect(items[1].quantity, 1);
  });

  test('extracts quantities from printed prescription table rows', () {
    final items = PrescriptionExtractor.parsePrintedLines(
      [
        'Paracetamol 500 mg 1 tablet As directed 2 tablets',
        'Cetirizine 10 mg 1 tablet As directed 1 tablet',
        'ORS 1 packet 1 packet As directed 1 packet',
      ],
      ['Paracetamol', 'Cetirizine', 'ORS'],
    );

    expect(items.map((item) => item.quantity), [2, 1, 1]);
    expect(items.map((item) => item.strength), ['500 mg', '10 mg', null]);
  });

  test('extracts quantity when OCR separates prescription columns into lines', () {
    final items = PrescriptionExtractor.parsePrintedLines(
      ['Paracetamol', '500 mg', '1 tablet', 'As directed', '2 tablets', 'Cetirizine', '10 mg', '1 tablet', 'As directed', '1 tablet'],
      ['Paracetamol', 'Cetirizine'],
    );

    expect(items.map((item) => item.quantity), [2, 1]);
    expect(items.map((item) => item.strength), ['500 mg', '10 mg']);
  });

  test('maps a separate quantity column to medicines in order', () {
    final items = PrescriptionExtractor.parsePrintedLines(
      ['Paracetamol 500 mg', 'Cetirizine 10 mg', 'ORS 1 packet', '2 tablets', '1 tablet', '1 packet'],
      ['Paracetamol', 'Cetirizine', 'ORS'],
    );

    expect(items.map((item) => item.quantity), [2, 1, 1]);
  });
}

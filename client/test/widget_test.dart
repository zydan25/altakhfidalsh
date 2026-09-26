import 'package:flutter_test/flutter_test.dart';
import 'package:altakhfid_client/main.dart';

void main() {
  testWidgets('customer app boots', (tester) async {
    await tester.pumpWidget(const AltakhfidApp());
    expect(find.text('التخفيض الصح'), findsOneWidget);
  });
}

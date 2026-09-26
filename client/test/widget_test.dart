import 'package:flutter_test/flutter_test.dart';
import 'package:altakhfid_client/main.dart';

void main() {
  test('OTP request payload is consumed from the nested item response', () {
    final response = <String, dynamic>{'item': {'otp_request_id': 42, 'phone': '967700000000'}};
    final item = response['item'];
    expect(item is Map ? item['otp_request_id'] : null, 42);
  });

  testWidgets('customer app boots', (tester) async {
    await tester.pumpWidget(const AltakhfidApp());
    expect(find.text('التخفيض الصح'), findsOneWidget);
  });
}

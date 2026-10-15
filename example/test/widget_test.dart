import 'package:flutter_test/flutter_test.dart';

import 'package:aws_liveness_for_flutter_example/main.dart';

void main() {
  testWidgets('example app renders its home screen', (tester) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('Face Liveness example'), findsOneWidget);
  });
}

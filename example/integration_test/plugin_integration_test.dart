// Integration tests run inside the example app on a device, so they can reach
// the native side of the plugin. See https://flutter.dev/to/integration-testing

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:aws_liveness_for_flutter_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('example app launches with the plugin registered', (
    tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('Face Liveness example'), findsOneWidget);
  });
}

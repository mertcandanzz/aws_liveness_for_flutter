import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aws_liveness_for_flutter_example/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renders the home screen and loads saved settings', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'backend_url': 'http://localhost:8787',
      'backend_token': 'saved-token',
    });

    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    expect(find.text('Face Liveness example'), findsOneWidget);
    final url = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Backend URL'),
    );
    expect(url.controller!.text, 'http://localhost:8787');
    expect(find.text('Start check'), findsOneWidget);
  });

  testWidgets('switches the UI language to Turkish', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Türkçe'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Türkçe'));
    await tester.pumpAndSettle();

    expect(find.text('Yüz canlılık örneği'), findsOneWidget);
  });

  testWidgets('asks for settings before starting', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start check'));
    await tester.pump();

    expect(find.text('Enter a valid http(s) URL and a token.'), findsOneWidget);
  });

  testWidgets('refuses to save an insecure non-loopback URL', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Backend URL'),
      'http://192.168.1.20:8787',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Access token'),
      'token-value',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('backend_url'), isNull);
    expect(
      find.text(
        'Use an https:// URL. http:// is allowed only for localhost in debug builds.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('saves valid settings', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Backend URL'),
      'https://backend.example',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Access token'),
      'token-value',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('backend_url'), 'https://backend.example');
    expect(find.text('Saved'), findsOneWidget);
  });
}

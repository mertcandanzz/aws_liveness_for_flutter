import 'package:flutter/material.dart';

void main() {
  runApp(const ExampleApp());
}

/// Placeholder until the liveness API lands; see `doc/design.md`.
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'aws_liveness_for_flutter example',
      home: Scaffold(
        appBar: AppBar(title: const Text('Face Liveness example')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'The liveness API is not available yet.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

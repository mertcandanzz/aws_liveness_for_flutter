import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// Guards the plugin registration and native source layout that the Flutter
/// tool, SwiftPM and CocoaPods rely on. Paths are relative to the package root.
void main() {
  const pluginClass = 'AwsLivenessForFlutterPlugin';
  const androidPackage = 'io.github.mertcandanzz.aws_liveness_for_flutter';
  const iosSources =
      'ios/aws_liveness_for_flutter/Sources/aws_liveness_for_flutter';

  String read(String path) => File(path).readAsStringSync();

  YamlMap platforms() {
    final pubspec = loadYaml(read('pubspec.yaml')) as YamlMap;
    final flutter = pubspec['flutter'] as YamlMap;
    final plugin = flutter['plugin'] as YamlMap;
    return plugin['platforms'] as YamlMap;
  }

  test('pubspec registers exactly the android and ios platforms', () {
    expect(platforms().keys.toSet(), {'android', 'ios'});
  });

  test('pubspec registers the Android plugin class and package', () {
    final android = platforms()['android'] as YamlMap;

    expect(android['package'], androidPackage);
    expect(android['pluginClass'], pluginClass);
  });

  test('pubspec registers the iOS plugin class', () {
    final ios = platforms()['ios'] as YamlMap;

    expect(ios['pluginClass'], pluginClass);
  });

  test('Android plugin class lives in the declared package', () {
    final source = read(
      'android/src/main/kotlin/io/github/mertcandanzz/'
      'aws_liveness_for_flutter/$pluginClass.kt',
    );

    expect(source, contains('package $androidPackage'));
    expect(source, contains('class $pluginClass'));
  });

  test('iOS sources use the Swift Package Manager layout', () {
    expect(
      read('$iosSources/$pluginClass.swift'),
      contains('class $pluginClass'),
    );
    expect(File('$iosSources/PrivacyInfo.xcprivacy').existsSync(), isTrue);

    final manifest = read('ios/aws_liveness_for_flutter/Package.swift');
    expect(manifest, contains('.library(name: "aws-liveness-for-flutter"'));
    expect(manifest, contains('.iOS("15.0")'));
  });

  test('podspec points at the SwiftPM source folder', () {
    final podspec = read('ios/aws_liveness_for_flutter.podspec');
    // Podspec paths are relative to the ios/ folder.
    final sourcesFromIos = iosSources.substring('ios/'.length);

    expect(podspec, contains("'$sourcesFromIos/**/*.swift'"));
    expect(podspec, contains("'$sourcesFromIos/PrivacyInfo.xcprivacy'"));
    expect(podspec, contains("s.platform = :ios, '15.0'"));
  });

  test('generated Pigeon outputs exist for every platform', () {
    expect(File('lib/src/messages.g.dart').existsSync(), isTrue);
    expect(
      File(
        'android/src/main/kotlin/io/github/mertcandanzz/'
        'aws_liveness_for_flutter/Messages.g.kt',
      ).existsSync(),
      isTrue,
    );
    expect(File('$iosSources/Messages.g.swift').existsSync(), isTrue);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:aws_liveness_for_flutter/aws_liveness_for_flutter.dart';
import 'package:aws_liveness_for_flutter/aws_liveness_for_flutter_platform_interface.dart';
import 'package:aws_liveness_for_flutter/aws_liveness_for_flutter_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockAwsLivenessForFlutterPlatform
    with MockPlatformInterfaceMixin
    implements AwsLivenessForFlutterPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final AwsLivenessForFlutterPlatform initialPlatform = AwsLivenessForFlutterPlatform.instance;

  test('$MethodChannelAwsLivenessForFlutter is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelAwsLivenessForFlutter>());
  });

  test('getPlatformVersion', () async {
    AwsLivenessForFlutter awsLivenessForFlutterPlugin = AwsLivenessForFlutter();
    MockAwsLivenessForFlutterPlatform fakePlatform = MockAwsLivenessForFlutterPlatform();
    AwsLivenessForFlutterPlatform.instance = fakePlatform;

    expect(await awsLivenessForFlutterPlugin.getPlatformVersion(), '42');
  });
}

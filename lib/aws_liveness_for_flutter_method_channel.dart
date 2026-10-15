import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'aws_liveness_for_flutter_platform_interface.dart';

/// An implementation of [AwsLivenessForFlutterPlatform] that uses method channels.
class MethodChannelAwsLivenessForFlutter extends AwsLivenessForFlutterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('aws_liveness_for_flutter');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}

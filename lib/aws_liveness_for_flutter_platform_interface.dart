import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'aws_liveness_for_flutter_method_channel.dart';

abstract class AwsLivenessForFlutterPlatform extends PlatformInterface {
  /// Constructs a AwsLivenessForFlutterPlatform.
  AwsLivenessForFlutterPlatform() : super(token: _token);

  static final Object _token = Object();

  static AwsLivenessForFlutterPlatform _instance = MethodChannelAwsLivenessForFlutter();

  /// The default instance of [AwsLivenessForFlutterPlatform] to use.
  ///
  /// Defaults to [MethodChannelAwsLivenessForFlutter].
  static AwsLivenessForFlutterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [AwsLivenessForFlutterPlatform] when
  /// they register themselves.
  static set instance(AwsLivenessForFlutterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}

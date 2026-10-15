
import 'aws_liveness_for_flutter_platform_interface.dart';

class AwsLivenessForFlutter {
  Future<String?> getPlatformVersion() {
    return AwsLivenessForFlutterPlatform.instance.getPlatformVersion();
  }
}

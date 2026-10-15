#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint aws_liveness_for_flutter.podspec` to validate before publishing.
#
# CocoaPods is a fallback only: the Amplify Face Liveness SDK ships via Swift
# Package Manager, so under CocoaPods the plugin builds but reports isAvailable = false.
#
Pod::Spec.new do |s|
  s.name             = 'aws_liveness_for_flutter'
  s.version          = '0.0.1'
  s.summary          = 'Native Amazon Rekognition Face Liveness for Flutter.'
  s.description      = <<-DESC
Native Amazon Rekognition Face Liveness for Flutter on iOS and Android, built on the
official AWS Amplify Face Liveness SDKs. Unofficial; not affiliated with AWS.
                       DESC
  s.homepage         = 'https://github.com/mertcandanzz/aws_liveness_for_flutter'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'Mertcan' => '28989684+mertcandanzz@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'aws_liveness_for_flutter/Sources/aws_liveness_for_flutter/**/*.swift'
  s.resource_bundles = {
    'aws_liveness_for_flutter_privacy' => ['aws_liveness_for_flutter/Sources/aws_liveness_for_flutter/PrivacyInfo.xcprivacy']
  }
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end

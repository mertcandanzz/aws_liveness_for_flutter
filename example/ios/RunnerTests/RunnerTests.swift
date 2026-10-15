import Flutter
import UIKit
import XCTest

@testable import aws_liveness_for_flutter

class RunnerTests: XCTestCase {

  func testPluginTypeIsLinked() {
    XCTAssertNotNil(AwsLivenessForFlutterPlugin.self)
  }

}

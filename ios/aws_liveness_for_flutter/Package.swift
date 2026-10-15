// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "aws_liveness_for_flutter",
    platforms: [
        // Amplify UI Face Liveness requires iOS 15.
        .iOS("15.0")
    ],
    products: [
        .library(name: "aws-liveness-for-flutter", targets: ["aws_liveness_for_flutter"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "aws_liveness_for_flutter",
            dependencies: [],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        )
    ]
)

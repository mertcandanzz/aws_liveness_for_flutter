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
    dependencies: [
        // FaceLiveness ships only through Swift Package Manager; CocoaPods builds compile
        // without it and report sdkUnavailable (doc/design.md §8).
        .package(url: "https://github.com/aws-amplify/amplify-ui-swift-liveness", from: "1.5.1")
    ],
    targets: [
        .target(
            name: "aws_liveness_for_flutter",
            dependencies: [
                .product(name: "FaceLiveness", package: "amplify-ui-swift-liveness")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        )
    ]
)

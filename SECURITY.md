# Security policy

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Report them privately through GitHub:
**Security** tab → **Report a vulnerability**
(<https://github.com/mertcandanzz/aws_liveness_for_flutter/security/advisories/new>).

Include the plugin version, platform, what an attacker can do, and steps to reproduce.
Never include real AWS credentials, session tokens or face images.

You can expect an acknowledgement within 7 days. Fixes are released as a patch version and
credited in the advisory unless you prefer otherwise.

## Supported versions

| Version | Supported |
|---|---|
| Latest `0.x` release | Yes |
| Older releases | No; please upgrade |

## Scope

In scope: this plugin's Dart, Kotlin and Swift code, and the example app and backend in
this repository.

Out of scope: the AWS Amplify SDKs and Amazon Rekognition (report those to AWS through
<https://aws.amazon.com/security/vulnerability-reporting/>), and your own backend.

How to integrate the plugin safely: [doc/security.md](doc/security.md).

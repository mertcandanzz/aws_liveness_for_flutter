# backend-express

Example backend for [`aws_liveness_for_flutter`](../../README.md). It does the
three things the app must never do itself:

1. **Create the session** with Rekognition `CreateFaceLivenessSession`.
2. **Vend short-lived credentials** that can do nothing except stream one liveness
   check (`rekognition:StartFaceLivenessSession`).
3. **Decide the result** with `GetFaceLivenessSessionResults` and a confidence
   threshold that lives only on the server.

It is an example: in-memory session binding and rate limiting, one process. Put a
database and a shared rate limiter behind it before running more than one instance.

## Run

Requires Node.js 22.13+ on the 22 line, 24.x or 26 and later (`^22.13.0 || ^24.0.0 || >=26.0.0`; `.nvmrc` pins 22.13.0 and `.npmrc` sets `engine-strict`).

```sh
npm ci
cp .env.example .env   # fill it in; never commit .env
set -a; . ./.env; set +a
npm run build && npm start
```

Checks: `npm run lint`, `npm run typecheck`, `npm test`.

To reach it from an Android device over USB, forward the port and use
`http://localhost:8787` in the example app:

```sh
adb reverse tcp:8787 tcp:8787
```

## API

Every route needs `Authorization: Bearer <token>` (one of `LIVENESS_API_TOKENS`).
Errors are `{"error": "<code>"}`; AWS error messages are never forwarded.

| Route | Body | Response |
|---|---|---|
| `POST /liveness/sessions` | `{}` or `{"challenge": "FaceMovementAndLightChallenge"}` when `LIVENESS_ALLOW_CLIENT_CHALLENGE=true` | `201 {"sessionId", "region", "challenge"}` |
| `POST /liveness/credentials` | `{"sessionId"}` of a session this caller created | `200 {"accessKeyId", "secretAccessKey", "sessionToken", "expiration"}` |
| `GET /liveness/sessions/:sessionId/result` | — | `200 {"sessionId", "status", "isLive", "confidence"}` |

- Sessions are bound to the token that created them. Credentials and results for a
  session are only served to that caller; anyone else gets `404`.
- `isLive` is `true` only when `status` is `SUCCEEDED` and `confidence` is at least
  `LIVENESS_CONFIDENCE_THRESHOLD`. A threshold sent by the client is ignored.
- Reference and audit images are never returned. Store them with the S3 output
  settings if you need them.
- Responses with credentials or results carry `Cache-Control: no-store`.
- Logs contain method, path, status and duration only: no headers, bodies,
  tokens, credentials or images.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `PORT` | `8787` | Listen port |
| `AWS_REGION` | required | Region for sessions; must support Face Liveness (for example `eu-west-1`, not `eu-central-1`) |
| `LIVENESS_API_TOKENS` | required | Comma-separated bearer tokens, at least 32 characters each |
| `LIVENESS_CREDENTIALS_ROLE_ARN` | required | Role assumed for app credentials |
| `LIVENESS_CHALLENGE` | `FaceMovementChallenge` | Or `FaceMovementAndLightChallenge` (flashing colours; see the photosensitivity note in the plugin README) |
| `LIVENESS_ALLOW_CLIENT_CHALLENGE` | `false` | Let callers pick the challenge. Demo only: in production the server decides |
| `LIVENESS_AUDIT_IMAGES_LIMIT` | `0` | 0-4 audit images |
| `LIVENESS_OUTPUT_S3_BUCKET`, `LIVENESS_OUTPUT_S3_KEY_PREFIX` | unset | Optional S3 output for images |
| `LIVENESS_CONFIDENCE_THRESHOLD` | `80` | 0-100; pick it for your risk tolerance |
| `LIVENESS_RATE_LIMIT_PER_MINUTE` | `30` | Requests per client IP per minute |

The server's own AWS credentials come from the standard provider chain
(environment, shared profile, instance or task role).

## IAM

Two identities are involved. Replace `<ACCOUNT_ID>`, `<BACKEND_ROLE>` and
`<LIVENESS_CLIENT_ROLE>`.

**Backend identity** (the role or user this server runs as):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rekognition:CreateFaceLivenessSession",
        "rekognition:GetFaceLivenessSessionResults"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::<ACCOUNT_ID>:role/<LIVENESS_CLIENT_ROLE>"
    }
  ]
}
```

Add `s3:PutObject` on your bucket if you set the S3 output.

**Liveness client role** (`LIVENESS_CREDENTIALS_ROLE_ARN`), permissions policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "rekognition:StartFaceLivenessSession",
      "Resource": "*"
    }
  ]
}
```

Trust policy, so only the backend can assume it:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::<ACCOUNT_ID>:role/<BACKEND_ROLE>" },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

On every request the backend calls `AssumeRole` with `DurationSeconds: 900` (the STS
minimum; a session lasts about 3 minutes) and an inline session policy that again
allows only `rekognition:StartFaceLivenessSession`. The effective permissions are the
intersection of the role policy and the session policy, so a role that is later
broadened by mistake still yields liveness-only credentials.

**Alternative: `GetFederationToken`.** If the backend runs as an IAM user, it can call
`GetFederationToken` with the same inline policy and `DurationSeconds: 900` instead of
assuming a role. It needs `sts:GetFederationToken`, and the user's own policy must
include `rekognition:StartFaceLivenessSession`. A dedicated role is preferred: it keeps
long-lived user keys out of the picture.

## Cost and sessions

- Each liveness check is billed by Rekognition (about **0.015 USD per check** in most
  regions at the time of writing; see the Rekognition pricing page).
- Sessions are **single use** and expire about **3 minutes** after creation. Create a
  new session for every attempt, including retries.
- Results can be read for a limited time after the check; read them right after
  `LivenessCompleted`.

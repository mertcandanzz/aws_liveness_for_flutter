# aws_liveness_for_flutter_example

Example app for the `aws_liveness_for_flutter` plugin. It needs the
[`examples/backend-express`](../examples/backend-express) backend: the app creates a
session there, gets liveness-only credentials from it and shows the backend's
decision. The app never decides liveness itself.

## Run

1. Start the backend (see its README) and note one of its `LIVENESS_API_TOKENS`.
2. Connect an Android device and forward the port:
   `adb reverse tcp:8787 tcp:8787`.
3. Run the app and enter `http://localhost:8787` and the token, or pass them at build
   time with `--dart-define=LIVENESS_BACKEND_URL=...` and
   `--dart-define=LIVENESS_BACKEND_TOKEN=...`.

The app contains no AWS keys, identity pool ids or backend URLs. Values entered in the
app are stored with `shared_preferences`, which is plain storage: use demo tokens only.
Debug builds allow cleartext HTTP so `localhost` works; release builds need HTTPS.

The native liveness screen follows the device language; the language switch only
changes the example's own text.

## Integration tests

`integration_test/liveness_test.dart` runs on a real device and covers availability,
camera permission, an unknown session, invalid credentials, a throwing credentials
provider, `cancel()` and timeout. See the comment at the top of the file for the
commands and `--dart-define` values; tests skip with a reason when a backend or the
camera permission is missing.

import Foundation

/// Asks Dart for credentials for one attempt; production uses `LivenessFlutterApi`.
typealias CredentialsFetcher =
  (_ attemptId: Int64, _ completion: @escaping (Result<CredentialsResultMessage, Error>) -> Void)
  -> Void

/// Temporary AWS credentials handed to the SDK. Conforms to `AWSTemporaryCredentials` when
/// FaceLiveness is linked. Every textual and reflected form is redacted.
struct PluginTemporaryCredentials: Sendable, CustomStringConvertible,
  CustomDebugStringConvertible, CustomReflectable
{
  let accessKeyId: String
  let secretAccessKey: String
  let sessionToken: String
  let expiration: Date

  var description: String { "PluginTemporaryCredentials(<redacted>)" }
  var debugDescription: String { description }
  var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

/// Why the plugin could not hand credentials to the SDK. Carries no credential data.
struct CredentialsUnavailableError: Error, Equatable, CustomStringConvertible {
  enum Reason: String {
    case providerError
    case timedOut
    case invalid
    case staleAttempt
    case channelError
    case attemptEnded
  }

  let reason: Reason

  var description: String { "Liveness credentials are unavailable (\(reason.rawValue))." }
}

/// Converts the Dart reply into SDK credentials.
enum CredentialsConverter {
  static func convert(_ result: CredentialsResultMessage, now: Date)
    -> Result<PluginTemporaryCredentials, CredentialsUnavailableError>
  {
    if let failure = result.failure {
      return .failure(CredentialsUnavailableError(reason: reason(for: failure)))
    }
    guard let message = result.credentials else {
      return .failure(CredentialsUnavailableError(reason: .invalid))
    }
    let expiration = Date(timeIntervalSince1970: TimeInterval(message.expirationEpochSeconds))
    guard !isBlank(message.accessKeyId), !isBlank(message.secretAccessKey),
      !isBlank(message.sessionToken), expiration > now
    else {
      return .failure(CredentialsUnavailableError(reason: .invalid))
    }
    return .success(
      PluginTemporaryCredentials(
        accessKeyId: message.accessKeyId,
        secretAccessKey: message.secretAccessKey,
        sessionToken: message.sessionToken,
        expiration: expiration))
  }

  private static func reason(for failure: CredentialsFailureMessage)
    -> CredentialsUnavailableError.Reason
  {
    switch failure {
    case .providerError: return .providerError
    case .timedOut: return .timedOut
    case .invalid: return .invalid
    case .staleAttempt: return .staleAttempt
    }
  }

  private static func isBlank(_ value: String) -> Bool {
    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

/// Fetches credentials for one attempt (design §5, §6.3, §8).
///
/// Every request completes exactly once: with credentials, or with a
/// [CredentialsUnavailableError] after setting [ActiveAttempt.credentialsFailed]. A request
/// fails at once when the attempt ends, and after `credentialsTimeoutMillis` + 5 s without a
/// Dart reply. Credentials are handed over and never stored or logged.
@MainActor
final class CredentialsBroker {
  /// Native waits this long past Dart's own credentials timeout (design §6.3).
  static let guardDelay: TimeInterval = 5

  private let attempt: ActiveAttempt
  private let fetcher: CredentialsFetcher
  private let scheduler: Scheduler
  private let now: () -> Date

  init(
    attempt: ActiveAttempt,
    fetcher: @escaping CredentialsFetcher,
    scheduler: Scheduler,
    now: @escaping () -> Date = Date.init
  ) {
    self.attempt = attempt
    self.fetcher = fetcher
    self.scheduler = scheduler
    self.now = now
  }

  /// The SDK entry point, bridged with a checked continuation.
  func fetch() async throws -> PluginTemporaryCredentials {
    try await withCheckedThrowingContinuation { continuation in
      fetch { result in
        continuation.resume(with: result)
      }
    }
  }

  func fetch(
    _ completion: @escaping @MainActor (Result<PluginTemporaryCredentials, CredentialsUnavailableError>)
      -> Void
  ) {
    let attempt = self.attempt
    var replied = false
    var timeout: Cancellation?
    let reply: @MainActor (Result<PluginTemporaryCredentials, CredentialsUnavailableError>) -> Void =
      { result in
        guard !replied else {
          return
        }
        replied = true
        timeout?.cancel()
        if case .failure = result {
          attempt.credentialsFailed = true
        }
        completion(result)
      }
    guard !attempt.isFinished else {
      reply(.failure(CredentialsUnavailableError(reason: .attemptEnded)))
      return
    }
    attempt.onEnd {
      reply(.failure(CredentialsUnavailableError(reason: .attemptEnded)))
    }
    let delay = Double(attempt.request.credentialsTimeoutMillis) / 1000 + Self.guardDelay
    timeout = scheduler.schedule(after: delay) {
      reply(.failure(CredentialsUnavailableError(reason: .timedOut)))
    }
    let now = self.now
    fetcher(attempt.request.attemptId) { result in
      // Pigeon replies on the platform (main) thread.
      MainActor.assumeIsolated {
        switch result {
        case .failure:
          reply(.failure(CredentialsUnavailableError(reason: .channelError)))
        case .success(let message):
          reply(CredentialsConverter.convert(message, now: now()))
        }
      }
    }
  }
}

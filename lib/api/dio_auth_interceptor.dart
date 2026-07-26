import 'package:dio/dio.dart';

import '../services/auth/token_store.dart';

/// Single source of `Authorization: Bearer` for the Herald session
/// (design §4.1 single-source rule, §5.3).
///
/// Responsibilities:
/// - [onRequest]: inject `Authorization: Bearer <accessToken>` when a token is
///   present. Never injects for the refresh endpoint (it authenticates via the
///   refresh token in the body, not Bearer).
/// - [onError]: on a 401 from a non-refresh, non-retried request, single-flight
///   one refresh (concurrent 401s await the same in-flight refresh), then replay
///   the original request with the new token. The replay is marked retried, so a
///   second 401 on it is surfaced directly instead of triggering another refresh
///   — this caps retries at one and breaks a 401 → refresh → 401 loop (e.g. the
///   token is valid but lacks permission for the resource, or the new token is
///   also rejected). On refresh failure, the [TokenStore] is cleared and
///   [onSessionEnd] invoked exactly once (bound to the single-flight); all
///   waiters reject with the original error.
///
/// The refresh request itself returning 401 must never re-enter refresh
/// (recursion guard via the `/browser-token/refresh` path check).
///
/// FL-D02 supplies [_refreshFn] (calls `AuthApi.refresh`, writes new tokens
/// into [TokenStore], returns true on success / false on failure) and
/// [_onSessionEnd] (resets `authStateProvider`; the router then redirects to
/// `/login`). This interceptor only triggers and replays.
///
/// Constructor signature is frozen for FL-D02.
class DioAuthInterceptor extends Interceptor {
  DioAuthInterceptor(this._tokenStore, this._refreshFn, this._onSessionEnd);

  // Non-final so [rebind] can swap in the provider-backed implementations
  // during app bootstrap (FL-D02). The constructor signature is frozen.
  TokenStore _tokenStore;
  Future<bool> Function() _refreshFn;
  Future<void> Function() _onSessionEnd;

  /// The [Dio] instance used to replay requests after a successful refresh.
  /// Set by the owner that mounts this interceptor (DioUtil) right after
  /// construction, since [RequestOptions] does not carry a Dio reference and
  /// the constructor signature is frozen for FL-D02.
  Dio? _dio;

  /// Bind the [Dio] instance used for replaying 401 requests.
  /// Called once by DioUtil after both the Dio singleton and this interceptor
  /// are constructed.
  void attachDio(Dio dio) => _dio = dio;

  /// Replace the TokenStore / refreshFn / onSessionEnd callbacks. Used by the
  /// app bootstrap (FL-D02) to swap in the provider-backed implementations
  /// after this interceptor has already been mounted with no-op defaults.
  /// The constructor signature itself is frozen for FL-D02.
  void rebind({
    required TokenStore tokenStore,
    required Future<bool> Function() refreshFn,
    required Future<void> Function() onSessionEnd,
  }) {
    _tokenStore = tokenStore;
    _refreshFn = refreshFn;
    _onSessionEnd = onSessionEnd;
  }

  /// Key on [RequestOptions.extra] marking a request that has already been
  /// replayed once after a refresh. A 401 on such a request is surfaced
  /// directly instead of triggering another refresh — caps retries at one.
  static const _retriedKey = 'dioAuth.retried';

  /// The single in-flight refresh future. Non-null while a refresh is running;
  /// concurrent 401s await this same future to avoid refresh-token reuse
  /// (which would revoke the whole token family server-side). The failure
  /// cleanup (clear + onSessionEnd) is bound to this future, so it runs
  /// exactly once regardless of how many waiters shared the refresh.
  Future<bool>? _refreshInFlight;

  // Recursion guard: a 401 from the refresh endpoint must not trigger another
  // refresh. The suffix matches the path produced by `AuthApi.refresh(...)`
  // (wired in buildSessionBindings' refreshFn) — both must stay aligned; if the
  // server changes the refresh route, update this suffix too.
  static bool _isRefreshRequest(RequestOptions options) =>
      options.path.endsWith('/browser-token/refresh');

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _inject(options).whenComplete(() => handler.next(options));
  }

  Future<void> _inject(RequestOptions options) async {
    // The refresh endpoint authenticates via the refresh token in the body,
    // not Bearer. Never attach Authorization there (also avoids a stale access
    // token shadowing the refresh attempt).
    if (_isRefreshRequest(options)) return;
    final token = await _tokenStore.getAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;
    final is401 = response?.statusCode == 401;
    final isRefresh = _isRefreshRequest(err.requestOptions);
    final alreadyRetried = err.requestOptions.extra[_retriedKey] == true;
    // Non-401 errors, a 401 on the refresh endpoint itself (recursion guard),
    // or a 401 on a request we already replayed (retry cap) are passed through
    // unchanged. Without the retry cap a persistently-401 request would loop:
    // 401 → refresh → replay → 401 → refresh → ...
    if (!is401 || isRefresh || alreadyRetried) {
      handler.next(err);
      return;
    }
    _refreshAndReplay(err, handler);
  }

  Future<void> _refreshAndReplay(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // _refreshOnce never throws; on failure it has already cleared the store
    // and invoked onSessionEnd exactly once (via the single-flight).
    final refreshSucceeded = await _refreshOnce();
    if (!refreshSucceeded) {
      handler.next(err);
      return;
    }

    // Refresh succeeded: replay the original request via dio.fetch, which
    // re-runs the interceptor chain (onRequest._inject reads the fresh token
    // from the store and sets Authorization — so we do NOT set the header
    // here; doing so would be redundant and race with the refresh's persist).
    // Mark the request retried so a second 401 on it is not refreshed again.
    try {
      final dio = _dio;
      if (dio == null) {
        // No dio reference available: cannot replay. Surface the original error.
        handler.next(err);
        return;
      }
      err.requestOptions.extra[_retriedKey] = true;
      final Response replayResponse = await dio.fetch(err.requestOptions);
      handler.resolve(replayResponse);
    } catch (replayError) {
      // Replay itself failed (e.g. network). Surface that error.
      if (replayError is DioException) {
        handler.next(replayError);
      } else {
        handler.next(err);
      }
    }
  }

  /// Returns the in-flight refresh future, creating it on the first 401.
  /// Concurrent callers await the same future so refresh runs exactly once.
  Future<bool> _refreshOnce() {
    _refreshInFlight ??= _runRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
    return _refreshInFlight!;
  }

  /// Runs one refresh and, on failure, performs the clear + onSessionEnd
  /// cleanup. Bound to the single-flight future in [_refreshOnce], so when N
  /// waiters share a refresh the cleanup runs exactly once, not N times.
  /// Never throws — a thrown refreshFn is treated as failure and cleaned up.
  Future<bool> _runRefresh() async {
    try {
      final success = await _refreshFn();
      if (!success) {
        await _tokenStore.clear();
        await _onSessionEnd();
      }
      return success;
    } catch (_) {
      // Defensive: refreshFn should not throw, but if it does treat as failure.
      await _tokenStore.clear();
      await _onSessionEnd();
      return false;
    }
  }
}

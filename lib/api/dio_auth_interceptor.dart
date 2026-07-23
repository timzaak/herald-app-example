import 'package:dio/dio.dart';

import '../services/auth/token_store.dart';

/// Single source of `Authorization: Bearer` for the Herald session
/// (design §4.1 single-source rule, §5.3).
///
/// Responsibilities:
/// - [onRequest]: inject `Authorization: Bearer <accessToken>` when a token is
///   present. Never injects for the refresh endpoint (it authenticates via the
///   refresh token in the body, not Bearer).
/// - [onError]: on a 401 from a non-refresh request, single-flight one refresh
///   (concurrent 401s await the same in-flight refresh), then replay the
///   original request with the new token. On refresh failure, clears the
///   [TokenStore] and invokes [onSessionEnd]; all waiters reject with the
///   original error.
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

  /// The single in-flight refresh future. Non-null while a refresh is running;
  /// concurrent 401s await this same future to avoid refresh-token reuse
  /// (which would revoke the whole token family server-side).
  Future<bool>? _refreshInFlight;

  static bool _isRefreshRequest(RequestOptions options) =>
      options.path.contains('/browser-token/refresh');

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
    // Non-401 errors, or a 401 on the refresh endpoint itself, are passed
    // through unchanged (refresh 401 must NOT recurse into another refresh).
    if (!is401 || isRefresh) {
      handler.next(err);
      return;
    }
    _refreshAndReplay(err, handler);
  }

  Future<void> _refreshAndReplay(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final bool refreshSucceeded;
    try {
      refreshSucceeded = await _refreshOnce();
    } catch (_) {
      // Defensive: refreshFn should not throw, but if it does treat as failure.
      await _handleRefreshFailure(err, handler);
      return;
    }

    if (!refreshSucceeded) {
      await _handleRefreshFailure(err, handler);
      return;
    }

    // Refresh succeeded: reload the new access token and replay the original
    // request via dio.fetch. dio.fetch re-runs the interceptor chain, so the
    // fresh Authorization is injected by onRequest above; we still set the
    // header explicitly on the cloned options to be unambiguous.
    try {
      final newToken = await _tokenStore.getAccessToken();
      final dio = _dio;
      if (dio == null) {
        // No dio reference available: cannot replay. Surface the original error.
        handler.next(err);
        return;
      }
      err.requestOptions.headers['Authorization'] =
          (newToken != null && newToken.isNotEmpty) ? 'Bearer $newToken' : null;
      final Response replayResponse = await dio.fetch(err.requestOptions);
      handler.resolve(replayResponse);
    } catch (replayError) {
      // Replay itself failed (e.g. another 401, network). Surface that error.
      if (replayError is DioException) {
        handler.next(replayError);
      } else {
        handler.next(err);
      }
    }
  }

  Future<void> _handleRefreshFailure(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    await _tokenStore.clear();
    await _onSessionEnd();
    handler.next(err);
  }

  /// Returns the in-flight refresh future, creating it on the first 401.
  /// Concurrent callers await the same future so refresh runs exactly once.
  Future<bool> _refreshOnce() {
    _refreshInFlight ??= _refreshFn().whenComplete(() {
      _refreshInFlight = null;
    });
    return _refreshInFlight!;
  }
}

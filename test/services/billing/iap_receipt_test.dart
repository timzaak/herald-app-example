// Unit tests for HeraldBillingService.submitIapReceipt.
//
// Exercises the dual error channel:
// - 200 `status=succeeded`/`pending` → IapReceiptResult parsed normally.
// - 200 `status=failed` → ALSO returns normally; classifyIapFailure(result:)
//   yields verificationFailed (the only 200-channel reason).
// - 200 idempotent-hit → attemptId = payment_event.id, billingType=null.
// - 4xx → DioException thrown; classifyIapFailure(dioError:) reads the
//   response body's `message` field (NOT `code`) for the reason literal.
//
// Extends the `_ScriptedAdapter` dio-mocking pattern from
// test/services/account/account_and_billing_service_test.dart with a
// 4xx-capable variant (the existing adapter only returns 200). No new deps.
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/services/billing/billing_service.dart';
import 'package:app/services/iap/iap_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hand-rolled Dio adapter scripting (statusCode, body) pairs in sequence and
/// recording each request's [RequestOptions] so the request body can be
/// asserted. Mirrors the existing account-test adapter but supports non-200.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(List<(int, Map<String, dynamic>)> responses)
    : _responses = responses;

  final List<(int, Map<String, dynamic>)> _responses;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (_responses.isEmpty) {
      throw StateError('_ScriptedAdapter: no scripted response left');
    }
    final (status, body) = _responses.removeAt(0);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: const {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(_ScriptedAdapter adapter) {
  return Dio(BaseOptions(baseUrl: 'https://herald.test'))
    ..httpClientAdapter = adapter;
}

HeraldBillingService _service(_ScriptedAdapter adapter) {
  return HeraldBillingService(
    _dio(adapter),
    realmId: 'realm-1',
    clientAppUuid: 'client-uuid',
  );
}

const _input = IapReceiptInput(
  provider: 'apple',
  receipt: 'jws-representation',
  productId: 'com.example.pro.monthly',
  targetId: 'mapping-uuid-1',
);

void main() {
  group('HeraldBillingService.submitIapReceipt — 200 channel', () {
    test('status=succeeded → IapReceiptResult parsed normally', () async {
      final adapter = _ScriptedAdapter([
        (
          200,
          {
            'attemptId': 'attempt-1',
            'status': 'succeeded',
            'entitlementKey': 'pro_monthly',
            'billingType': 'recurring',
            'failureReason': null,
          },
        ),
      ]);
      final service = _service(adapter);

      final result = await service.submitIapReceipt(_input);

      expect(result.attemptId, 'attempt-1');
      expect(result.status, 'succeeded');
      expect(result.entitlementKey, 'pro_monthly');
      expect(result.billingType, 'recurring');
      expect(result.failureReason, isNull);
      expect(result.succeeded, isTrue);
    });

    test(
      'status=failed → parsed normally (NOT thrown); classify → verificationFailed',
      () async {
        // WHY: the 200 channel's only failure reason is verification_failed;
        // the caller classifies via classifyIapFailure(result:) rather than
        // the service throwing. Throwing here would break the dual-channel
        // contract.
        final adapter = _ScriptedAdapter([
          (
            200,
            {
              'attemptId': 'attempt-2',
              'status': 'failed',
              'entitlementKey': null,
              'billingType': null,
              'failureReason': 'verification_failed',
            },
          ),
        ]);
        final service = _service(adapter);

        final result = await service.submitIapReceipt(_input);

        expect(result.status, 'failed');
        expect(result.failureReason, 'verification_failed');
        expect(result.succeeded, isFalse);
        expect(
          classifyIapFailure(result: result),
          IapFailureReason.verificationFailed,
        );
      },
    );

    test(
      'idempotent-hit → attemptId=payment_event id, billingType=null; caller '
      'decides by status only (no status-endpoint call)',
      () async {
        // WHY: a replayed/repeat receipt returns the already-fulfilled event;
        // the client must NOT feed this attemptId into getPaymentAttemptStatus.
        final paymentEventId = '11111111-1111-4111-8111-111111111111';
        final adapter = _ScriptedAdapter([
          (
            200,
            {
              'attemptId': paymentEventId,
              'status': 'succeeded',
              'entitlementKey': 'pro_monthly',
              'billingType': null,
              'failureReason': null,
            },
          ),
        ]);
        final service = _service(adapter);

        final result = await service.submitIapReceipt(_input);

        expect(result.attemptId, paymentEventId);
        expect(result.billingType, isNull);
        expect(result.failureReason, isNull);
        expect(result.succeeded, isTrue);
        // Only one request — proves no follow-up status-endpoint poll.
        expect(adapter.requests, hasLength(1));
      },
    );
  });

  group('HeraldBillingService.submitIapReceipt — 4xx channel', () {
    test('409 conflict + message=ownership_mismatch → DioException; classify → '
        'ownershipMismatch (reads message, NOT code)', () async {
      final adapter = _ScriptedAdapter([
        (409, {'code': 'conflict', 'message': 'ownership_mismatch'}),
      ]);
      final service = _service(adapter);

      Object? caught;
      try {
        await service.submitIapReceipt(_input);
      } on DioException catch (e) {
        caught = e;
      }
      expect(
        caught,
        isA<DioException>(),
        reason: '4xx must throw DioException, not return normally',
      );

      final reason = classifyIapFailure(dioError: caught as DioException);
      expect(reason, IapFailureReason.ownershipMismatch);
    });

    test(
      '422 validation_error + message=already_consumed → alreadyConsumed',
      () async {
        final adapter = _ScriptedAdapter([
          (422, {'code': 'validation_error', 'message': 'already_consumed'}),
        ]);
        final service = _service(adapter);

        Object? caught;
        try {
          await service.submitIapReceipt(_input);
        } on DioException catch (e) {
          caught = e;
        }
        expect(caught, isA<DioException>());

        final reason = classifyIapFailure(dioError: caught as DioException);
        expect(reason, IapFailureReason.alreadyConsumed);
      },
    );

    test('404 not_found + message=no_mapping → noMapping', () async {
      final adapter = _ScriptedAdapter([
        (404, {'code': 'not_found', 'message': 'no_mapping'}),
      ]);
      final service = _service(adapter);

      Object? caught;
      try {
        await service.submitIapReceipt(_input);
      } on DioException catch (e) {
        caught = e;
      }
      expect(caught, isA<DioException>());

      final reason = classifyIapFailure(dioError: caught as DioException);
      expect(reason, IapFailureReason.noMapping);
    });

    test('404 + message=NotConfigured → noMapping (backend literal)', () async {
      // The backend may surface realm-not-configured as `NotConfigured`; that
      // also routes to noMapping / iapProductUnavailable.
      final adapter = _ScriptedAdapter([
        (404, {'code': 'not_found', 'message': 'NotConfigured'}),
      ]);
      final service = _service(adapter);

      Object? caught;
      try {
        await service.submitIapReceipt(_input);
      } on DioException catch (e) {
        caught = e;
      }

      final reason = classifyIapFailure(dioError: caught as DioException);
      expect(reason, IapFailureReason.noMapping);
    });

    test('422 + message=verification_failed → verificationFailed (4xx-channel '
        'sibling of the 200 case)', () async {
      final adapter = _ScriptedAdapter([
        (422, {'code': 'validation_error', 'message': 'verification_failed'}),
      ]);
      final service = _service(adapter);

      Object? caught;
      try {
        await service.submitIapReceipt(_input);
      } on DioException catch (e) {
        caught = e;
      }

      final reason = classifyIapFailure(dioError: caught as DioException);
      expect(reason, IapFailureReason.verificationFailed);
    });

    test('409 + message=type_mismatch → productUnavailable', () async {
      final adapter = _ScriptedAdapter([
        (409, {'code': 'conflict', 'message': 'type_mismatch'}),
      ]);
      final service = _service(adapter);

      Object? caught;
      try {
        await service.submitIapReceipt(_input);
      } on DioException catch (e) {
        caught = e;
      }

      final reason = classifyIapFailure(dioError: caught as DioException);
      expect(reason, IapFailureReason.productUnavailable);
    });

    test('unknown 4xx message → generic', () async {
      final adapter = _ScriptedAdapter([
        (400, {'code': 'bad_request', 'message': 'something_unexpected'}),
      ]);
      final service = _service(adapter);

      Object? caught;
      try {
        await service.submitIapReceipt(_input);
      } on DioException catch (e) {
        caught = e;
      }

      final reason = classifyIapFailure(dioError: caught as DioException);
      expect(reason, IapFailureReason.generic);
    });
  });

  group('classifyIapFailure — does NOT branch on `code`', () {
    test('code=conflict but message=already_consumed → alreadyConsumed (proves '
        '`message` is the source, not `code`)', () {
      // WHY: if the classifier read `code`, a 409 `conflict` would route to
      // ownershipMismatch (the typical 409 case). Routing to alreadyConsumed
      // proves it reads `message` instead — the load-bearing assertion for
      // the dual-channel contract.
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 409,
          data: {'code': 'conflict', 'message': 'already_consumed'},
        ),
      );

      expect(
        classifyIapFailure(dioError: dioError),
        IapFailureReason.alreadyConsumed,
        reason: 'classifier must read `message`, not `code`',
      );
    });

    test('missing body / no message field → generic', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 500,
        ),
      );

      expect(classifyIapFailure(dioError: dioError), IapFailureReason.generic);
    });

    test('no result and no dioError → generic', () {
      expect(classifyIapFailure(), IapFailureReason.generic);
    });
  });

  group('HeraldBillingService.submitIapReceipt — request body', () {
    test(
      'posts IapReceiptInput.toJson() to the iap/receipt endpoint',
      () async {
        final adapter = _ScriptedAdapter([
          (200, {'attemptId': 'attempt-1', 'status': 'succeeded'}),
        ]);
        final service = _service(adapter);

        await service.submitIapReceipt(_input);

        final request = adapter.requests.single;
        expect(request.path, '/api/bill/realm-1/purchase/iap/receipt');
        expect(request.method, 'POST');
        expect(request.data, _input.toJson());
        expect(request.data, {
          'provider': 'apple',
          'receipt': 'jws-representation',
          'productId': 'com.example.pro.monthly',
          'targetType': 'entitlement_mapping',
          'targetId': 'mapping-uuid-1',
        });
      },
    );

    test(
      'IapReceiptInput.toJson() defaults targetType to entitlement_mapping',
      () {
        const input = IapReceiptInput(
          provider: 'google',
          receipt: 'purchase-token',
          productId: 'points_1000',
          targetId: 'mapping-uuid-2',
        );
        expect(input.toJson(), {
          'provider': 'google',
          'receipt': 'purchase-token',
          'productId': 'points_1000',
          'targetType': 'entitlement_mapping',
          'targetId': 'mapping-uuid-2',
        });
      },
    );
  });
}

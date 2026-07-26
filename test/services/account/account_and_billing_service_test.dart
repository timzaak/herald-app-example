import 'dart:convert';
import 'dart:typed_data';

import 'package:app/services/account/account_service.dart';
import 'package:app/services/billing/billing_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(List<Map<String, dynamic>> responses)
    : _responses = responses;

  final List<Map<String, dynamic>> _responses;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(_responses.removeAt(0)),
      200,
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

void main() {
  test(
    'account overview uses the server-computed cross-bucket total',
    () async {
      // WHY: quota windows and bucket rules belong to the server; the app must
      // display crossBucketTotal verbatim instead of re-summing wallet rows.
      final adapter = _ScriptedAdapter([
        {'id': 'u1', 'email': 'user@example.com', 'nickname': 'User'},
        {
          'crossBucketTotal': 1250,
          'items': [
            {'bucketTotal': 999999},
          ],
        },
      ]);

      final result = await HeraldAccountService(_dio(adapter)).getOverview();

      expect(result.email, 'user@example.com');
      expect(result.nickname, 'User');
      expect(result.points, 1250);
      expect(adapter.requests.map((request) => request.path), [
        '/api/user/profile',
        '/api/user/wallets',
      ]);
    },
  );

  test('billing maps Stripe checkout and polls backend status', () async {
    final adapter = _ScriptedAdapter([
      {
        'items': [
          {
            'mappingId': 'mapping-1',
            'displayName': '1000 points',
            'paymentProvider': 'stripe',
            'enabled': true,
            'alreadyOwned': false,
            'pointsPerPeriod': 1000,
            'amount': 499,
            'currency': 'USD',
            'billingType': 'one_time',
          },
        ],
      },
      {
        'id': 'attempt-1',
        'status': 'Pending',
        'paymentContext': {
          'stripeCheckoutUrl': 'https://checkout.stripe.com/test',
        },
      },
      {'status': 'Succeeded'},
    ]);
    final service = HeraldBillingService(
      _dio(adapter),
      realmId: 'realm-1',
      clientAppUuid: 'client-uuid',
    );

    final options = await service.listPurchaseOptions();
    final attempt = await service.createPaymentAttempt(options.single);
    final status = await service.getPaymentAttemptStatus(attempt.id);

    expect(options.single.points, 1000);
    expect(attempt.checkoutUrl.host, 'checkout.stripe.com');
    expect(status.succeeded, isTrue);
    expect(adapter.requests[1].data, {
      'targetType': 'entitlement_mapping',
      'targetId': 'mapping-1',
      'paymentProvider': 'stripe',
    });
  });

  test('purchase options fail loud when client app UUID is missing', () async {
    final service = HeraldBillingService(
      Dio(),
      realmId: 'realm-1',
      clientAppUuid: '',
    );

    expect(
      service.listPurchaseOptions(),
      throwsA(isA<BillingConfigurationException>()),
    );
  });
}

import 'package:dio/dio.dart';

import '../../config/settings.dart';
import '../iap/iap_models.dart';

class PurchaseOption {
  const PurchaseOption({
    required this.mappingId,
    required this.displayName,
    required this.paymentProvider,
    required this.enabled,
    required this.alreadyOwned,
    this.points,
    this.amount,
    this.currency,
    this.billingType,
    this.billingPeriod,
    this.externalProductId,
  });

  final String mappingId;
  final String displayName;
  final String paymentProvider;
  final bool enabled;
  final bool alreadyOwned;
  final int? points;
  final int? amount;
  final String? currency;
  final String? billingType;
  final String? billingPeriod;

  /// Store product id (= backend `mapping.external_product_id`).
  ///
  /// Two-key distinction (do NOT conflate):
  /// - [externalProductId] = store product id = receipt request `productId`
  ///   field = `in_app_purchase` `ProductDetails.id` / `PurchaseDetails.productID`.
  /// - [mappingId] = entitlement_mapping UUID = receipt request `targetId`
  ///   field. A backend concept, NOT a store id.
  ///
  /// Nullable: backend always serializes `externalProductId` for IAP rows, but
  /// this model is shared with Stripe/Creem rows where it is absent.
  final String? externalProductId;

  bool get purchasable =>
      enabled && !alreadyOwned && paymentProvider.isNotEmpty;
}

class PaymentAttempt {
  const PaymentAttempt({
    required this.id,
    required this.status,
    required this.checkoutUrl,
  });

  final String id;
  final String status;
  final Uri checkoutUrl;
}

class PaymentAttemptStatus {
  const PaymentAttemptStatus(this.status);

  final String status;

  bool get succeeded => status.toLowerCase() == 'succeeded';

  bool get finished {
    return const {
      'succeeded',
      'failed',
      'cancelled',
      'expired',
    }.contains(status.toLowerCase());
  }
}

/// Request body for `POST /api/bill/{realmId}/purchase/iap/receipt`
/// (hand-written raw Dio — the endpoint is NOT in the generated `api_client`
/// auth-only spec).
///
/// Two-key distinction (do NOT conflate):
/// - [productId] = store product id (the `in_app_purchase` ProductDetails /
///   PurchaseDetails id). NOT the backend mapping UUID.
/// - [targetId] = entitlement_mapping UUID (= `PurchaseOption.mappingId`).
class IapReceiptInput {
  const IapReceiptInput({
    required this.provider,
    required this.receipt,
    required this.productId,
    required this.targetId,
    this.targetType = 'entitlement_mapping',
  });

  /// `'apple'` or `'google'`.
  final String provider;

  /// Apple: StoreKit 2 `jwsRepresentation` (JWS).
  /// Google: `purchaseToken`.
  final String receipt;

  /// Store product id (= `PurchaseOption.externalProductId`).
  final String productId;

  /// entitlement_mapping UUID (= `PurchaseOption.mappingId`).
  final String targetId;

  /// Fixed `'entitlement_mapping'`.
  final String targetType;

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'receipt': receipt,
    'productId': productId,
    'targetType': targetType,
    'targetId': targetId,
  };
}

abstract class BillingService {
  Future<List<PurchaseOption>> listPurchaseOptions();

  Future<PaymentAttempt> createPaymentAttempt(PurchaseOption option);

  Future<PaymentAttemptStatus> getPaymentAttemptStatus(String attemptId);

  /// Submits an IAP receipt for backend validation + fulfillment. Dual error
  /// channel — see [HeraldBillingService.submitIapReceipt].
  Future<IapReceiptResult> submitIapReceipt(IapReceiptInput input);
}

class HeraldBillingService implements BillingService {
  HeraldBillingService(this._dio, {String? realmId, String? clientAppUuid})
    : _realmId = realmId ?? Settings.heraldRealmId,
      _clientAppUuid = clientAppUuid ?? Settings.heraldClientAppUuid;

  final Dio _dio;
  final String _realmId;
  final String _clientAppUuid;

  @override
  Future<List<PurchaseOption>> listPurchaseOptions() async {
    if (_clientAppUuid.isEmpty) {
      throw const BillingConfigurationException();
    }
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/bill/$_realmId/client/$_clientAppUuid/purchase-options',
    );
    final items = response.data?['items'];
    if (items is! List) throw const FormatException('Invalid purchase options');
    return items
        .whereType<Map>()
        .map((item) => _purchaseOption(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  @override
  Future<PaymentAttempt> createPaymentAttempt(PurchaseOption option) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/bill/$_realmId/purchase/payment-attempts',
      data: {
        'targetType': 'entitlement_mapping',
        'targetId': option.mappingId,
        'paymentProvider': option.paymentProvider,
      },
    );
    final data = response.data;
    final context = data?['paymentContext'];
    if (data == null || context is! Map) {
      throw const FormatException('Invalid payment attempt');
    }
    final checkoutUrl = switch (option.paymentProvider.toLowerCase()) {
      'stripe' => context['stripeCheckoutUrl'],
      'creem' => context['creemCheckoutUrl'],
      _ => null,
    };
    final uri = checkoutUrl is String ? Uri.tryParse(checkoutUrl) : null;
    if (uri == null || uri.scheme != 'https') {
      throw const FormatException('Missing secure checkout URL');
    }
    return PaymentAttempt(
      id: _string(data, 'id'),
      status: _string(data, 'status'),
      checkoutUrl: uri,
    );
  }

  @override
  Future<PaymentAttemptStatus> getPaymentAttemptStatus(String attemptId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/bill/$_realmId/purchase/payment-attempts/$attemptId',
    );
    final data = response.data;
    if (data == null) throw const FormatException('Missing payment status');
    return PaymentAttemptStatus(_string(data, 'status'));
  }

  /// Submits an IAP receipt to Herald for validation + fulfillment (hand-written
  /// raw Dio — the endpoint is NOT in the generated `api_client` spec).
  ///
  /// **Dual error channel (critical contract)** — callers MUST handle both:
  /// (a) 200 with `status == 'succeeded'` OR `status == 'pending'` returns
  ///     normally.
  /// (b) 200 with `status == 'failed'` ALSO returns normally — the caller
  ///     classifies via `classifyIapFailure(result: ...)` (the ONLY possible
  ///     200-channel reason is `verification_failed`).
  /// (c) 4xx throws `DioException` — the caller classifies via
  ///     `classifyIapFailure(dioError: ...)` reading `response.data['message']`
  ///     (NOT `code`; `code` is HTTP-status-derived: `conflict` /
  ///     `validation_error` / `not_found` / `bad_request`).
  /// (d) Idempotent-hit (200, already-fulfilled) returns `attemptId` =
  ///     `payment_event.id` with `billingType = null` / `failureReason = null`
  ///     — the caller decides purely by `status` and MUST NOT use this
  ///     `attemptId` to call [getPaymentAttemptStatus].
  /// (e) 401 is handled transparently by `DioAuthInterceptor` (single-flight
  ///     refresh + replay).
  @override
  Future<IapReceiptResult> submitIapReceipt(IapReceiptInput input) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/bill/$_realmId/purchase/iap/receipt',
      data: input.toJson(),
    );
    final data = response.data;
    if (data == null) {
      throw const FormatException('Invalid iap receipt response');
    }
    return IapReceiptResult(
      attemptId: _string(data, 'attemptId'),
      status: _string(data, 'status'),
      entitlementKey: data['entitlementKey'] as String?,
      billingType: data['billingType'] as String?,
      failureReason: data['failureReason'] as String?,
    );
  }

  static PurchaseOption _purchaseOption(Map<String, dynamic> json) {
    return PurchaseOption(
      mappingId: _string(json, 'mappingId'),
      displayName:
          json['displayName'] as String? ??
          json['entitlementKey'] as String? ??
          '',
      paymentProvider: json['paymentProvider'] as String? ?? '',
      enabled: json['enabled'] == true,
      alreadyOwned: json['alreadyOwned'] == true,
      points: _optionalInt(json['pointsPerPeriod']),
      amount: _optionalInt(json['amount']),
      currency: json['currency'] as String?,
      billingType: json['billingType'] as String?,
      billingPeriod: json['billingPeriod'] as String?,
      externalProductId: json['externalProductId'] as String?,
    );
  }

  static String _string(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('Invalid $key');
  }

  static int? _optionalInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }
}

class BillingConfigurationException implements Exception {
  const BillingConfigurationException();
}

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
    this.hasTopupGrant = false,
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
  final bool hasTopupGrant;
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

  /// Herald and the stores agree that only a points-granting one-time product
  /// is consumable. A points-less one-time product is a restorable buyout.
  ///
  /// Consumability is derived from the backend `pointRules`: any enabled rule
  /// with the `topup` trigger (fixed OR quota) makes this a consumable topup
  /// pack. A one-time product with no topup rules is a non-consumable buyout.
  bool get isConsumable => billingType == 'one_time' && hasTopupGrant;

  bool get isNonConsumable =>
      billingType == 'recurring' ||
      billingType == 'non_renewing' ||
      (billingType == 'one_time' && !isConsumable);

  bool get purchasable =>
      enabled &&
      !alreadyOwned &&
      paymentProvider.isNotEmpty &&
      (isConsumable || isNonConsumable);
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
    final pointRules = _parsePointRules(json['pointRules']);
    return PurchaseOption(
      mappingId: _string(json, 'mappingId'),
      displayName:
          json['displayName'] as String? ??
          json['entitlementKey'] as String? ??
          '',
      paymentProvider: json['paymentProvider'] as String? ?? '',
      enabled: json['enabled'] == true,
      alreadyOwned: json['alreadyOwned'] == true,
      points: pointRules.displayPoints,
      hasTopupGrant: pointRules.hasTopupGrant,
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

  /// Projects the backend `pointRules` array into the two client-side
  /// derivations:
  ///
  /// - [ParsedPointRules.hasTopupGrant]: any enabled rule carries the `topup`
  ///   trigger. This drives [PurchaseOption.isConsumable] — a one-time product
  ///   with a topup rule (fixed OR quota) is a consumable pack; without one it
  ///   is a non-consumable buyout.
  /// - [ParsedPointRules.displayPoints]: the `pointsAmount` of the
  ///   lowest-`displayOrder` enabled `fixed` topup rule, surfaced as the
  ///   "N points" badge on the purchase tile. Quota grants carry no scalar to
  ///   show, so a quota-only topup pack is consumable but shows no badge.
  ///
  /// `topup` is the only trigger legal for a `one_time` mapping on the backend
  /// (see cas-2 `distribution_rules.rs`), so trigger filtering is belt-and-
  /// suspenders against a misconfigured rule set rather than a live branch.
  static ({bool hasTopupGrant, int? displayPoints}) _parsePointRules(
    Object? raw,
  ) {
    if (raw is! List) return (hasTopupGrant: false, displayPoints: null);

    var hasTopupGrant = false;
    int? displayPoints;
    var displayOrder = 0x7FFFFFFF;
    for (final entry in raw) {
      if (entry is! Map) continue;
      if (entry['enabled'] != true) continue;
      final triggers = entry['triggerSources'];
      if (triggers is! List || !triggers.contains('topup')) continue;
      hasTopupGrant = true;
      if (entry['grantMode'] != 'fixed') continue;
      final amount = _optionalInt(entry['pointsAmount']);
      if (amount == null || amount <= 0) continue;
      final order = _optionalInt(entry['displayOrder']) ?? 0;
      if (order < displayOrder) {
        displayPoints = amount;
        displayOrder = order;
      }
    }
    return (hasTopupGrant: hasTopupGrant, displayPoints: displayPoints);
  }
}

class BillingConfigurationException implements Exception {
  const BillingConfigurationException();
}

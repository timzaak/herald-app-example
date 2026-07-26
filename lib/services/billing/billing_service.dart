import 'package:dio/dio.dart';

import '../../config/settings.dart';

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

abstract class BillingService {
  Future<List<PurchaseOption>> listPurchaseOptions();

  Future<PaymentAttempt> createPaymentAttempt(PurchaseOption option);

  Future<PaymentAttemptStatus> getPaymentAttemptStatus(String attemptId);
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

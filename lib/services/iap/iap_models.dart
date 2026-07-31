import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:uuid/uuid.dart';

import '../billing/billing_service.dart';

/// An aligned IAP product = a backend [PurchaseOption] plus the store-resolved
/// [ProductDetails], which carries the authoritative localized display price.
///
/// `iapProductsProvider` only constructs this when `option.externalProductId`
/// is non-null AND matched a store `ProductDetails`, so [storeId] is always
/// the matched store id.
class IapProduct {
  const IapProduct({required this.option, required this.storeProduct});

  /// Backend purchase option (carries [PurchaseOption.externalProductId] and
  /// [PurchaseOption.mappingId]).
  final PurchaseOption option;

  /// Store-resolved product details (carries the localized `price`).
  final ProductDetails storeProduct;

  /// Store product id — the receipt-request `productId` field, the
  /// `ProductDetails.id`, and the `PurchaseDetails.productID` (all the same
  /// value, by construction). NOT the backend mapping UUID
  /// ([PurchaseOption.mappingId]).
  String get storeId => storeProduct.id;
}

/// Client projection of the backend `IapReceiptResponse`
/// (`POST /api/bill/{realmId}/purchase/iap/receipt`).
class IapReceiptResult {
  const IapReceiptResult({
    required this.attemptId,
    required this.status,
    this.entitlementKey,
    this.billingType,
    this.failureReason,
  });

  /// On the new-fulfillment path this is the `payment_attempt.id`; on the
  /// idempotent-hit path this is the `payment_event.id` (with `billingType`
  /// null). Callers decide purely by [status] and MUST NOT feed this into
  /// `getPaymentAttemptStatus` on a receipt result.
  final String attemptId;

  /// `'succeeded'` / `'pending'` / `'failed'`.
  final String status;

  /// Present on success.
  final String? entitlementKey;

  /// `'recurring'` / `'one_time'` / `'non_renewing'`; null on idempotent-hit.
  final String? billingType;

  /// Only ever `'verification_failed'` on the 200 channel. Other reasons come
  /// through the 4xx channel (see [classifyIapFailure]).
  final String? failureReason;

  bool get succeeded => status == 'succeeded';
}

/// Ownership-binding abstraction. Injects the Herald `user_id` into the
/// in-app purchase as platform-appropriate identification:
/// - iOS: `Uuid.parse(user_id)` → `appAccountToken` (Apple requires a UUID;
///   Herald compares `app_account_token: Option<Uuid>` against the parsed
///   `user_id: Uuid` — a non-UUID fails the comparison, so the caller MUST
///   block via [canBind] before purchasing on iOS).
/// - Android: `user_id` → `obfuscatedAccountId` (Herald compares
///   `obfuscated_external_account_id: Option<String>` against
///   `user_id.to_string()` — a plain string compare).
abstract class IapOwnershipBinding {
  /// Whether [userId] can be bound on the current platform. Returns false on
  /// iOS when [userId] is not a valid UUID (fail-closed — the notifier must
  /// block the purchase instead of injecting a binding that StoreKit /
  /// the backend will reject). Returns whether [userId] is non-empty on
  /// Android.
  bool canBind(String userId);
}

/// Production ownership binding keyed off `dart:io` [Platform].
class PlatformIapOwnershipBinding implements IapOwnershipBinding {
  const PlatformIapOwnershipBinding();

  @override
  bool canBind(String userId) {
    if (Platform.isIOS) {
      // Apple requires `appAccountToken` to be a UUID; a non-UUID would be
      // rejected by StoreKit and always mismatch Herald's UUID compare.
      return Uuid.isValidUUID(fromString: userId);
    }
    return userId.isNotEmpty;
  }
}

/// Classified IAP failure reason for surfacing via l10n. The
/// reason→l10n-key mapping table is:
///
/// | Reason | l10n key |
/// | --- | --- |
/// | [verificationFailed] | `iapVerificationFailed` |
/// | [ownershipMismatch] | `iapOwnershipMismatch` |
/// | [alreadyConsumed] | `iapAlreadyConsumed` |
/// | [noMapping] | `iapProductUnavailable` |
/// | [productUnavailable] | `iapProductUnavailable` |
/// | [generic] | `paymentFailed` (existing) |
enum IapFailureReason {
  verificationFailed,
  ownershipMismatch,
  alreadyConsumed,
  noMapping,
  productUnavailable,
  generic,
}

/// Thrown by [InAppPurchaseIapService.buyNonConsumable] /
/// [buyConsumable] when [IapOwnershipBinding.canBind] returns false — a
/// fail-closed guard so an invalid/empty binding is never injected into the
/// system purchase. The purchase notifier is expected to have already blocked
/// the purchase upstream; this is the defensive backstop.
class IapOwnershipBindingException implements Exception {
  const IapOwnershipBindingException(this.userId);
  final String userId;
  @override
  String toString() =>
      'IapOwnershipBindingException: cannot bind userId '
      '"$userId" on this platform';
}

/// Classifies an IAP receipt-submission failure across the dual error channels
/// (a 200 body whose `status` is `failed`, vs. a thrown `DioException` 4xx).
///
/// Evaluation order:
/// 1. If [result] is present and `result.status == 'failed'` →
///    [IapFailureReason.verificationFailed]. This is the ONLY reason the
///    200-channel can ever surface (`failureReason` must be
///    `'verification_failed'`); we deliberately do NOT branch on any other
///    `failureReason` value from the 200 channel.
/// 2. Else if [dioError] is present → read `dioError.response?.data` as a Map
///    and take the **`message`** field (NOT `code`). `code` is HTTP-status
///    derived (`conflict` / `validation_error` / `not_found` / `bad_request`)
///    and must NOT be used for reason branching.
/// 3. Else → [IapFailureReason.generic] (covers network / 5xx where no body
///    is present).
///
/// Exactly one of [result] / [dioError] should be passed: [result] for the
/// 200-channel `status == 'failed'` case, [dioError] for a thrown 4xx.
IapFailureReason classifyIapFailure({
  IapReceiptResult? result,
  DioException? dioError,
}) {
  // 1. 200 channel: the only possible failure reason is verification_failed.
  if (result != null && result.status == 'failed') {
    return IapFailureReason.verificationFailed;
  }

  // 2. 4xx channel: read the reason literal from the `message` field.
  if (dioError != null) {
    final message = _readMessage(dioError);
    switch (message) {
      case 'ownership_mismatch':
        return IapFailureReason.ownershipMismatch;
      case 'already_consumed':
        return IapFailureReason.alreadyConsumed;
      case 'no_mapping':
      case 'NotConfigured':
        return IapFailureReason.noMapping;
      case 'type_mismatch':
      case 'no_billing_type':
        return IapFailureReason.productUnavailable;
      case 'verification_failed':
        return IapFailureReason.verificationFailed;
      default:
        return IapFailureReason.generic;
    }
  }

  // 3. Fallback (network / 5xx without a parseable body, or no input).
  return IapFailureReason.generic;
}

/// Reads the reason literal from a 4xx [DioException]'s response body. Reads
/// the `message` field ONLY — never `code` (which is HTTP-status derived and
/// unsuitable for reason branching). Returns null when the body is absent or
/// `message` is missing/non-string.
String? _readMessage(DioException dioError) {
  final data = dioError.response?.data;
  if (data is Map) {
    final message = data['message'];
    if (message is String && message.isNotEmpty) return message;
  }
  return null;
}

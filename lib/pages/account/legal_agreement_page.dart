import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_providers.dart';
import 'agreement_web_view_page.dart';

class LegalAgreementPage extends HookConsumerWidget {
  const LegalAgreementPage({
    required this.agreementType,
    required this.title,
    super.key,
  });

  final String agreementType;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final request = useMemoized(
      () => ref
          .read(legalAgreementServiceProvider)
          .getAgreement(agreementType: agreementType, locale: locale),
      [agreementType, locale],
    );
    final agreement = useFuture(request);

    Widget body;
    if (agreement.hasError) {
      body = Center(
        key: const ValueKey('legalAgreementError'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            AppLocalizations.of(
              context,
            )!.unexpectedError(agreement.error.toString()),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (!agreement.hasData) {
      body = const Center(
        key: ValueKey('legalAgreementLoading'),
        child: CircularProgressIndicator(),
      );
    } else {
      final value = agreement.data!;
      body = SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (value.content.isNotEmpty)
              SelectableText(
                value.content,
                key: const ValueKey('legalAgreementContent'),
              ),
            if (value.externalUrl case final url? when url.isNotEmpty) ...[
              if (value.content.isNotEmpty) const SizedBox(height: 16),
              InkWell(
                key: const ValueKey('legalAgreementExternalLink'),
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        AgreementWebViewPage(url: url, title: title),
                  ),
                ),
                child: Text(
                  url,
                  style: const TextStyle(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: body,
    );
  }
}

// Widget tests for LegalAgreementPage (design §6.1).
//
// WHY these exist: the page previously rendered the agreement body as a plain
// `SelectableText`; this feature switches it to Markdown rendering. The core
// invariant under test is that the body is rendered through the Markdown
// pathway (`MarkdownBody`), not the legacy plain-text widget — otherwise the
// page would silently regress to unformatted output while still "passing" a
// naive text-existence check. We assert the widget type and the stable
// `legalAgreementContent` key, plus the unchanged error / empty-content +
// external-url branches.
import 'package:app/l10n/app_localizations.dart';
import 'package:app/pages/account/legal_agreement_page.dart';
import 'package:app/providers/auth_providers.dart';
import 'package:app/services/auth/legal_agreement_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
// `Override` is not re-exported by hooks_riverpod; importing it from riverpod
// internals is the approach already used in test/helpers/pump_herald_app.dart
// (Riverpod 3). riverpod is a transitive dep of hooks_riverpod.
// ignore: depend_on_referenced_packages, invalid_use_of_internal_member
import 'package:riverpod/src/internals.dart' show Override;

class _FakeLegalAgreementService implements LegalAgreementService {
  _FakeLegalAgreementService({this.agreement, this.error});

  LegalAgreement? agreement;
  Object? error;

  @override
  Future<LegalAgreement> getAgreement({
    required String agreementType,
    required String locale,
  }) async {
    if (error != null) {
      throw error!;
    }
    return agreement ??
        LegalAgreement(
          content: '# Terms\n\n- item one\n- item two\n\n**bold** text',
        );
  }
}

Future<void> pumpPage(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: ProviderContainer(overrides: overrides),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const LegalAgreementPage(
          agreementType: 'terms_of_service',
          title: 'User Agreement',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'renders the agreement body through MarkdownBody, not plain text',
    (tester) async {
      // WHY: the page must render content via the Markdown pathway so that
      // headings/lists/emphasis display as structured text. Asserting the
      // MarkdownBody type (not just that the text exists) catches a regression
      // back to SelectableText, which would still contain the raw string.
      final service = _FakeLegalAgreementService(
        agreement: LegalAgreement(
          content: '# Heading\n\n- one\n- two\n\n**bold** text',
        ),
      );

      await pumpPage(
        tester,
        overrides: [legalAgreementServiceProvider.overrideWithValue(service)],
      );

      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(
        find.byKey(const ValueKey('legalAgreementContent')),
        findsOneWidget,
      );
      // Structured Markdown elements render as distinct Text nodes: a heading
      // and two list items. The legacy plain-text renderer would put the raw
      // markdown source into a single SelectableText, so these would not be
      // individually findable. (Note: selectable: true may use SelectableText
      // internally as a leaf — that is expected, not a regression.)
      expect(find.text('Heading'), findsOneWidget);
      expect(find.text('one'), findsOneWidget);
      expect(find.text('two'), findsOneWidget);
    },
  );

  testWidgets(
    'renders the external link and skips the body when content is empty',
    (tester) async {
      // WHY: external_url is the fallback display when there is no inline body
      // (design §4.4.2); the body region must be absent in that case so the
      // link is the sole content.
      const url = 'https://example.com/full-text';
      final service = _FakeLegalAgreementService(
        agreement: const LegalAgreement(content: '', externalUrl: url),
      );

      await pumpPage(
        tester,
        overrides: [legalAgreementServiceProvider.overrideWithValue(service)],
      );

      expect(find.byKey(const ValueKey('legalAgreementContent')), findsNothing);
      expect(
        find.byKey(const ValueKey('legalAgreementExternalLink')),
        findsOneWidget,
      );
      expect(find.text(url), findsOneWidget);
    },
  );

  testWidgets('renders the error branch when the service fails', (
    tester,
  ) async {
    // WHY: a fetch failure must surface the error region (not the body), so
    // the user is not left looking at an empty/loading page.
    final service = _FakeLegalAgreementService(error: Exception('boom'));

    await pumpPage(
      tester,
      overrides: [legalAgreementServiceProvider.overrideWithValue(service)],
    );

    expect(find.byKey(const ValueKey('legalAgreementError')), findsOneWidget);
    expect(find.byKey(const ValueKey('legalAgreementContent')), findsNothing);
  });
}

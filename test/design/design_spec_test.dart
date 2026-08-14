import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cookpilot/app/app_theme.dart';
import 'package:cookpilot/design/design_catalog.dart';
import 'package:cookpilot/design/design_tokens.dart';

/// 토큰을 읽어 그대로 그리는 최소 위젯. 화면 코드가 디자인 값을 직접 알지
/// 않는다는 사실을 검사하기 위한 대역이다.
class _TokenProbe extends StatelessWidget {
  const _TokenProbe();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('probe'),
      color: context.color.accent,
      padding: EdgeInsets.all(context.space.cardPadding),
      child: Text('토큰', style: context.type.body),
    );
  }
}

void main() {
  group('디자인 안 카탈로그', () {
    test('안의 id가 서로 겹치지 않는다', () {
      final ids = designCatalog.map((spec) => spec.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('기본 안이 카탈로그에 들어 있다', () {
      expect(designCatalog, contains(defaultDesignSpec));
    });

    test('모든 안이 토큰을 실은 테마를 만든다', () {
      for (final spec in designCatalog) {
        final theme = buildCookPilotTheme(spec);
        final tokens = theme.extension<CookPilotTokens>();
        expect(tokens, isNotNull, reason: spec.id);
        expect(tokens!.spec, same(spec), reason: spec.id);
        expect(theme.scaffoldBackgroundColor, spec.palette.surface);
        expect(theme.textTheme.bodyMedium?.fontSize, spec.type.bodySize);
      }
    });
  });

  group('토큰 조회', () {
    testWidgets('테마가 없으면 기본 안으로 떨어진다', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _TokenProbe()));

      final probe = tester.widget<Container>(find.byKey(const Key('probe')));
      expect(probe.color, defaultDesignSpec.palette.accent);
    });

    testWidgets('안을 바꾸면 화면이 그린 값도 함께 바뀐다', (tester) async {
      for (final spec in designCatalog) {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildCookPilotTheme(spec),
            home: const _TokenProbe(),
          ),
        );
        // MaterialApp은 테마 교체를 애니메이션으로 넘긴다. 전환이 끝난 뒤에
        // 봐야 새 안의 값이 나온다.
        await tester.pumpAndSettle();

        final probe = tester.widget<Container>(find.byKey(const Key('probe')));
        expect(probe.color, spec.palette.accent, reason: spec.id);

        final text = tester.widget<Text>(find.text('토큰'));
        expect(text.style?.fontSize, spec.type.bodySize, reason: spec.id);
      }
    });
  });
}

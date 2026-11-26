// Onaylı tasarım: motorun her türü merkez benzeri ev sahibinde (koyu palet)
// açılır; oyun içi yazılar ve dokunuşla açılan pencereler okunur (3:1).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strateji_motoru/strateji_motoru.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studio_core/app/studio_ui.dart' show StudioBackdrop;
import 'package:studio_core/core/level_plan.dart';

import 'studio_readability.dart';
import 'views_test.dart' show fakeCtx;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final e in kStratejiKinds.entries) {
    testWidgets('${e.key}: onaylı koyu tasarımda yazılar ve pencereler okunur', (tester) async {
      tester.view.physicalSize = const Size(1080, 2280);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final rules = stratejiRulesFor('oyun-test-${e.key}', e.key);
      final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
      final gl = rules.build(planner.spec(5));
      await tester.pumpWidget(studioHost(StratejiStage(ctx: fakeCtx(gl, 'tr', []), rules: rules)));
      await tester.pump(const Duration(milliseconds: 400));
      final issues = await sweepReadability(tester, e.key);
      expect(issues, isEmpty, reason: 'Okunmayan yazı (${e.key}): ${issues.join('; ')}');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });
  }

  for (final kind in const ['altigen', 'taktik']) {
    testWidgets('$kind: aynı cihazda iki kişi ekranı onaylı koyu tasarımda okunur', (tester) async {
      tester.view.physicalSize = const Size(1080, 2280);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final rules = stratejiRulesFor('oyun-test-$kind', kind);
      final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
      final gl = rules.build(planner.spec(5));
      await tester.pumpWidget(studioHost(StratejiStage(ctx: fakeCtx(gl, 'tr', []), rules: rules)));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byTooltip(st('tr', 'hotseat')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(StudioBackdrop), findsWidgets);
      expectReadable(tester, where: '$kind iki kişi');
      final issues = await sweepReadability(tester, '$kind iki kişi', rows: 5, cols: 4, top: 120);
      expect(issues, isEmpty, reason: issues.join('; '));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });
  }
}

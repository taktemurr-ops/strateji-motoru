import 'package:flutter_test/flutter_test.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:strateji_motoru/strateji_motoru.dart';

void main() {
  for (final e in kStratejiKinds.entries) {
    test('${e.key}: bölümler kurulur ve yapay zekâ ile doğrulanır', timeout: const Timeout(Duration(minutes: 10)), () {
      final rules = stratejiRulesFor('oyun-test-${e.key}', e.key);
      final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
      for (final n in const [1, 7, 40, 300, 5000, 99999]) {
        expect(rules.build(planner.spec(n)).validation.ok, isTrue, reason: '${e.key} $n');
      }
    });

    test('${e.key}: aynı tohum aynı bölümü verir', () {
      final rules = stratejiRulesFor('oyun-test-${e.key}', e.key);
      final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
      final a = rules.build(planner.spec(123)).puzzle;
      final b = rules.build(planner.spec(123)).puzzle;
      expect(a.d, b.d);
      expect(a.puzzle.runtimeType, b.puzzle.runtimeType);
    });

    test('${e.key}: beş kazanım artan eşiklerle', () {
      final perks = e.value.perks;
      expect(perks.length, 5);
      for (var i = 1; i < perks.length; i++) {
        expect(perks[i].need, greaterThan(perks[i - 1].need));
      }
      for (final p in perks) {
        expect(kStratejiTexts.containsKey(p.key), isTrue, reason: p.key);
      }
    });
  }

  test('bütün metinler 33 dilde', () {
    for (final e in kStratejiTexts.entries) {
      expect(e.value.length, 33, reason: e.key);
      expect(e.value.every((s) => s.isNotEmpty), isTrue, reason: e.key);
    }
  });

  test('Dört Mevsim Krallık: en az 200 kart, her kartta iki farklı seçenek', () {
    expect(kKCards.length, greaterThanOrEqualTo(200));
    for (final c in kKCards) {
      expect(c.le.length, 4);
      expect(c.re.length, 4);
      expect(c.le.join(','), isNot(c.re.join(',')));
      expect(c.qTr.isNotEmpty && c.qEn.isNotEmpty, isTrue);
    }
  });

  test('Harita Defteri: biçim yönleri ve hedefler', () {
    expect(hOrients(7).map((o) => o.toString()).toSet().length, 1);
    expect(hOrients(3).map((o) => o.toString()).toSet().length, 2);
    expect(hOrients(9).map((o) => o.toString()).toSet().length, 1);
    final g = List<int>.filled(kHN * kHN, -1);
    for (var x = 0; x < kHN; x++) {
      g[x] = 0;
    }
    expect(hGoal(g, 0), kHN);
    expect(hGoal(g, 1), 4);
  });

  test('Zar Macerası: yapay zekâ seferi belirlenimci', () {
    final rules = stratejiRulesFor('oyun-test-zar', 'zar');
    final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
    final z = rules.build(planner.spec(42)).puzzle.puzzle as ZPuzzle;
    expect(zBot(z), z.botHp);
    expect(z.botHp, greaterThan(0));
  });

  test('ustalık puanı zorlukla artar', () {
    expect(Meta.pointsFor(1, 1), 1);
    expect(Meta.pointsFor(9, 3), 5);
  });
}

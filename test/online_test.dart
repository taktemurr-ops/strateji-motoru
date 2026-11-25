import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strateji_motoru/strateji_motoru.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';

/// Ağ yerine bellek içi maç bağlantısı; [peer] verilirse hamleler karşıya gider.
class FakeLink implements MatchLink {
  @override
  final int mySeat;
  @override
  final int seed;
  final StreamController<(int, String)> ctrl = StreamController.broadcast();

  /// Gönderilenler: (koltuk, ham hamle).
  final List<(int, String)> sent = [];

  /// İki tarafın ortak günlüğü (geri dönüş denemesi için).
  final List<(int, String)>? log;
  @override
  final List<(int, String)> history;
  @override
  final Set<int> dropped = {};
  FakeLink? peer;
  int? winner;
  FakeLink(this.mySeat, {this.seed = 42, this.history = const [], this.log});

  @override
  List<String> get names => const ['A', 'B'];
  @override
  bool get isHost => mySeat == 0;
  @override
  Stream<(int, String)> get moves => ctrl.stream;
  @override
  Future<void> send(String move, {int? asSeat}) async {
    final s = asSeat ?? mySeat;
    sent.add((s, move));
    log?.add((s, move));
    final p = peer;
    if (p != null) p.ctrl.add((s, move));
  }

  @override
  Future<void> finish(int winner, {bool? iWon}) async => this.winner = winner;
  void opp(String m) => ctrl.add((mySeat == 0 ? 1 : 0, m));
}

/// Bir cihaz: oyun durumu + ağ katmanı.
class Peer {
  final DuelGame g;
  final FakeLink link;
  late final StratNet net;
  Peer(this.g, this.link) {
    net = StratNet(link, (s, m) => g.apply(s, m));
    net.start();
  }
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

/// Sıradaki koltuğun cihazı bilgisayar hamlesini oynar; her hamleden sonra
/// iki cihazın durumu aynı olmalı.
Future<int> playOut(Peer a, Peer b, {int? stopAfter}) async {
  var n = 0;
  while (!a.g.over && n < 5000) {
    if (stopAfter != null && n >= stopAfter) return -3;
    final seat = a.g.turnSeat;
    expect(b.g.turnSeat, seat);
    final mover = seat == a.link.mySeat ? a : b;
    final other = identical(mover, a) ? b : a;
    final mv = mover.g.botMove();
    expect(mover.g.apply(seat, mv), isTrue, reason: 'hamle $n: $mv');
    mover.net.send(seat, mv);
    await settle();
    expect(other.g.hash, mover.g.hash, reason: 'hamle $n: $mv');
    n++;
  }
  expect(a.g.over, isTrue);
  expect(b.g.over, isTrue);
  expect(a.g.winner, b.g.winner);
  expect(a.g.winner, inInclusiveRange(-1, 1));
  return a.g.winner;
}

(Peer, Peer) pair(DuelGame Function() mk, {List<(int, String)>? log}) {
  final la = FakeLink(0, log: log), lb = FakeLink(1, log: log);
  la.peer = lb;
  lb.peer = la;
  return (Peer(mk(), la), Peer(mk(), lb));
}

PlayContext duelCtx(GeneratedLevel gl, List<SeatRole> seats, List<RoundResult> results, {MatchLink? link, String lang = 'tr'}) => PlayContext(
      spec: gl.spec,
      generated: gl,
      resume: const {},
      pieceColors: const [Color(0xFF3E6FB0), Color(0xFFC8553D), Color(0xFF4F9A6E)],
      background: const [Color(0xFF203040), Color(0xFF304050)],
      colorBlind: false,
      reducedMotion: false,
      leftHanded: false,
      lang: lang,
      t: (k, [p = const {}]) => k,
      finish: results.add,
      saveResume: (_) {},
      requestHint: () async => true,
      requestBooster: () async => true,
      requestContinue: () async => false,
      sfx: (_) {},
      seats: seats,
      match: link,
    );

final Map<String, DuelGame Function(int seed)> kinds = {
  'altigen': HDuel.new,
  'taktik': TDuel.new,
};

Type viewType(String k) => k == 'altigen' ? HDuelView : TDuelView;

Future<GeneratedLevel> level(String k) async {
  final rules = stratejiRulesFor('oyun-o-$k', k);
  final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
  return rules.build(planner.run(GameModeId.online, 42, difficulty: 4));
}

Future<void> mount(WidgetTester tester, String k, PlayContext ctx) async {
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  final rules = stratejiRulesFor('oyun-o-$k', k);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: SafeArea(child: StratejiStage(ctx: ctx, rules: rules)))));
  await tester.pump();
}

DuelGame viewGame(WidgetTester tester, String k) => (tester.state(find.byType(viewType(k))) as dynamic).game as DuelGame;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('yalnızca Altıgen Savaş ve Sıra Tabanlı Taktik iki kişilik', () {
    for (final k in kStratejiKinds.keys) {
      expect(stratejiRulesFor('oyun-$k', k).localPlayers, kinds.containsKey(k) ? 2 : 0, reason: k);
    }
  });

  test('Altıgen düellosu: harita ve ordular ayna simetrik', () {
    for (var seed = 1; seed <= 30; seed++) {
      final g = HDuel(seed * 7919);
      for (final c in kHCells) {
        expect(g.terrain[c], g.terrain[hMirror(c)], reason: '$seed $c');
      }
      final n = g.army.length ~/ 2;
      expect(n, greaterThanOrEqualTo(4));
      for (var i = 0; i < n; i++) {
        expect(g.army[i].side, 0);
        expect(g.army[i + n].side, 1);
        expect(g.army[i + n].type, g.army[i].type);
        expect(g.army[i + n].pos, hMirror(g.army[i].pos));
      }
      expect(g.hash, HDuel(seed * 7919).hash);
    }
  });

  test('Taktik düellosu: avlu ve kahramanlar ayna simetrik', () {
    for (var seed = 1; seed <= 30; seed++) {
      final g = TDuel(seed * 7919);
      for (var k = 0; k < 64; k++) {
        expect(g.rock.contains(k), g.rock.contains(63 - k));
        expect(g.high.contains(k), g.high.contains(63 - k));
      }
      for (var i = 0; i < 4; i++) {
        expect(g.army[i + 4].type, g.army[i].type);
        expect(g.army[i + 4].x, 7 - g.army[i].x);
        expect(g.army[i + 4].y, 7 - g.army[i].y);
      }
      expect(g.hash, TDuel(seed * 7919).hash);
    }
  });

  for (final e in kinds.entries) {
    test('${e.key}: iki koltukta tam maç, her hamleden sonra aynı durum', () async {
      final wins = <int>[];
      for (var seed = 1; seed <= 6; seed++) {
        final (a, b) = pair(() => e.value(seed * 104729));
        expect(a.g.hash, b.g.hash);
        wins.add(await playOut(a, b));
        expect(a.link.winner, isNull); // sonuç ekrandan bildirilir
      }
      expect(wins.length, 6);
    });

    test('${e.key}: geri dönüş — günlük baştan uygulanır, maç sürer', () async {
      final log = <(int, String)>[];
      final (a, b) = pair(() => e.value(99), log: log);
      expect(await playOut(a, b, stopAfter: 25), -3);
      // B cihazı kapandı; aynı günlükle yeniden açılıyor.
      final lc = FakeLink(1, history: List.of(log), log: log);
      a.link.peer = lc;
      lc.peer = a.link;
      final c = Peer(e.value(99), lc);
      expect(c.g.hash, a.g.hash);
      expect(c.g.applied, a.g.applied);
      expect(c.net.next, log.length);
      await playOut(a, c);
    });

    test('${e.key}: rakip koparsa kalan cihaz onun yerine oynar ve hamleleri onun adına yazar', () async {
      final (a, b) = pair(() => e.value(5));
      await playOut(a, b, stopAfter: 10);
      a.link.peer = null;
      a.link.dropped.add(1);
      expect(a.net.oppGone, isTrue);
      var n = 0;
      while (!a.g.over && n++ < 5000) {
        final seat = a.g.turnSeat;
        final mv = a.g.botMove();
        expect(a.g.apply(seat, mv), isTrue);
        a.net.send(seat, mv);
      }
      expect(a.g.over, isTrue);
      expect(a.link.sent.any((m) => m.$1 == 1), isTrue);
      // Günlükten yeniden kurulan durum aynıdır.
      final all = [for (final m in a.link.sent) m];
      final re = e.value(5);
      final known = <int>{};
      for (final m in all) {
        known.add(StratNet.parse(m.$2)!.$1);
      }
      expect(known.length, all.length);
      final full = FakeLink(0, history: [...b.link.sent, ...all]);
      final rp = Peer(re, full);
      expect(rp.g.hash, a.g.hash);
    });

    test('${e.key}: kurala aykırı hamleler reddedilir, durum değişmez', () async {
      final g = e.value(11);
      final h0 = g.hash;
      for (final bad in ['', 'x', 'e1', 'm', 'a', 't', 'm0,0', 'a0', 't0,0,0', 'm99,0,0', 'a0,99', 'm0,9,9', 't9,0,0,w', 'tx,y,z,w', 't0,0,0,q']) {
        expect(g.apply(0, bad), isFalse, reason: bad);
        expect(g.apply(1, bad), isFalse, reason: bad);
      }
      // Sırası olmayan koltuk.
      final other = 1 - g.turnSeat;
      expect(g.apply(other, g.botMove()), isFalse);
      expect(g.apply(other, g.timeoutMove()), isFalse);
      expect(g.hash, h0);
      expect(g.applied, 0);
      // Ağdan gelen kurala aykırı hamle yok sayılır; sırası tüketilir.
      final (a, b) = pair(() => e.value(11));
      a.net.send(1, 'zzz');
      await settle();
      expect(b.g.hash, h0);
      expect(b.net.next, 1);
      // Aynı sıra iki kez gelirse ikincisi yok sayılır; sırasız gelen beklenir.
      final mv = a.g.botMove();
      final seat = a.g.turnSeat;
      a.g.apply(seat, mv);
      a.link.peer = null;
      b.link.ctrl.add((seat, '2|${a.g.botMove()}'));
      await settle();
      expect(b.g.applied, 0);
      b.link.ctrl.add((seat, '1|$mv'));
      b.link.ctrl.add((seat, '1|$mv'));
      await settle();
      expect(b.net.next, 3);
    });
  }

  test('Altıgen: tek tek kurallar', () {
    final g = HDuel(3);
    final n = g.army.length ~/ 2;
    // Rakip birimi oynatılamaz.
    final enemy = g.army[n];
    final er = g.reach(enemy).where((c) => c != enemy.pos).toList();
    if (er.isNotEmpty) expect(g.apply(0, 'm$n,${er.first.$1},${er.first.$2}'), isFalse);
    // Bir birim tek kez yürür.
    final u = g.army.indexWhere((x) => g.reach(x).length > 1 && x.side == 0 && x.t.rng <= 2);
    final cells = g.reach(g.army[u]).where((c) => c != g.army[u].pos).toList();
    expect(g.apply(0, 'm$u,${cells.first.$1},${cells.first.$2}'), isTrue);
    final again = g.reach(g.army[u]).where((c) => c != g.army[u].pos).toList();
    if (again.isNotEmpty) expect(g.apply(0, 'm$u,${again.first.$1},${again.first.$2}'), isFalse);
    // Menzil dışındaki rakibe saldırılamaz (başlangıçta ordular uzak).
    expect(g.apply(0, 'a$u,$n'), isFalse);
    expect(g.apply(0, 'e'), isTrue);
    expect(g.turnSeat, 1);
    expect(g.apply(0, 'e'), isFalse);
  });

  test('Taktik: tek tek kurallar', () {
    final g = TDuel(3);
    final u = g.current!;
    final id = g.army.indexOf(u);
    final seat = u.side;
    expect(g.apply(seat, 't$id,${u.x},${7 - u.y},w'), isFalse);
    // Yetenek türü uymayan eylem.
    if (u.type != 1) expect(g.apply(seat, 't$id,${u.x},${u.y},v3:3'), isFalse);
    if (u.type != 0) expect(g.apply(seat, 't$id,${u.x},${u.y},g'), isFalse);
    // Uzaktaki rakibe vurulamaz.
    final far = g.army.indexWhere((f) => f.side != seat);
    expect(g.apply(seat, 't$id,${u.x},${u.y},h$far'), isFalse);
    expect(g.applied, 0);
    expect(g.apply(seat, 't$id,${u.x},${u.y},w'), isTrue);
    expect(g.currentId, isNot(id));
  });

  for (final k in kinds.keys) {
    testWidgets('$k çevrimiçi ekran: rakip hamleleri işlenir, durum gölge kopyayla aynı', (tester) async {
      final gl = await level(k);
      final link = FakeLink(0);
      final results = <RoundResult>[];
      await mount(tester, k, duelCtx(gl, const [SeatRole.local, SeatRole.remote], results, link: link));
      expect(find.byType(viewType(k)), findsOneWidget);
      final shadow = kinds[k]!(42);
      expect(viewGame(tester, k).hash, shadow.hash);
      var seen = 0, next = 0;
      for (var step = 0; step < 3000 && !shadow.over; step++) {
        if (shadow.turnSeat == 1) {
          final mv = shadow.botMove();
          expect(shadow.apply(1, mv), isTrue);
          link.opp('${next++}|$mv');
          await tester.pump(const Duration(milliseconds: 20));
        } else {
          await tester.pump(Duration(seconds: k == 'altigen' ? 61 : 31));
        }
        while (seen < link.sent.length) {
          final m = link.sent[seen++];
          final p = StratNet.parse(m.$2)!;
          expect(m.$1, 0);
          expect(p.$1, next);
          next++;
          expect(shadow.apply(0, p.$2), isTrue);
        }
        expect(viewGame(tester, k).hash, shadow.hash);
      }
      expect(shadow.over, isTrue);
      await tester.pump(const Duration(seconds: 3));
      expect(results.length, 1);
      expect(link.winner, shadow.winner);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('$k çevrimiçi ekran: rakip koparsa bilgisayar onun adına oynar', (tester) async {
      final gl = await level(k);
      final link = FakeLink(1)..dropped.add(0);
      final results = <RoundResult>[];
      await mount(tester, k, duelCtx(gl, const [SeatRole.remote, SeatRole.local], results, link: link));
      for (var i = 0; i < 400 && results.isEmpty; i++) {
        await tester.pump(const Duration(seconds: 31));
      }
      await tester.pump(const Duration(seconds: 3));
      expect(results.length, 1);
      expect(link.sent.any((m) => m.$1 == 0), isTrue);
      expect(link.sent.any((m) => m.$1 == 1), isTrue);
      // Gönderilen günlükten yeniden kurulan durum ekrandakiyle aynı.
      final re = Peer(kinds[k]!(42), FakeLink(1, history: List.of(link.sent)));
      expect(re.g.hash, viewGame(tester, k).hash);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('$k çevrimiçi ekran: yarıda kalan maça geri dönülür', (tester) async {
      final gl = await level(k);
      final ref = kinds[k]!(42);
      final hist = <(int, String)>[];
      for (var i = 0; i < 30 && !ref.over; i++) {
        final s = ref.turnSeat;
        final mv = ref.botMove();
        expect(ref.apply(s, mv), isTrue);
        hist.add((s, '$i|$mv'));
      }
      final link = FakeLink(1, history: hist);
      final results = <RoundResult>[];
      await mount(tester, k, duelCtx(gl, const [SeatRole.remote, SeatRole.local], results, link: link));
      final g = viewGame(tester, k);
      expect(g.hash, ref.hash);
      expect(g.applied, hist.length);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('$k çevrimiçi masada bilgisayar rakip: maç biter, sonuç bildirilir', (tester) async {
      final gl = await level(k);
      final link = FakeLink(0);
      final results = <RoundResult>[];
      await mount(tester, k, duelCtx(gl, const [SeatRole.local, SeatRole.ai], results, link: link));
      for (var i = 0; i < 400 && results.isEmpty; i++) {
        await tester.pump(const Duration(seconds: 31));
      }
      await tester.pump(const Duration(seconds: 3));
      expect(results.length, 1);
      expect(link.winner, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('$k aynı cihazda iki kişi: ekran açılır, süre dolunca sıra geçer', (tester) async {
      final gl = await level(k);
      final results = <RoundResult>[];
      await mount(tester, k, duelCtx(gl, const [SeatRole.local, SeatRole.local], results));
      expect(find.byType(viewType(k)), findsOneWidget);
      final g = viewGame(tester, k);
      final first = g.turnKey;
      await tester.pump(Duration(seconds: k == 'altigen' ? 61 : 31));
      expect(g.turnKey, isNot(first));
      for (var i = 0; i < 400 && results.isEmpty; i++) {
        await tester.pump(const Duration(seconds: 61));
      }
      await tester.pump(const Duration(seconds: 3));
      expect(results.length, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });

    for (final lang in const ['tr', 'en', 'ar']) {
      testWidgets('$k düello ekranı ($lang): dokunuşlara dayanır', (tester) async {
        final gl = await level(k);
        final results = <RoundResult>[];
        await mount(tester, k, duelCtx(gl, const [SeatRole.local, SeatRole.remote], results, link: FakeLink(0), lang: lang));
        final size = tester.view.physicalSize / tester.view.devicePixelRatio;
        for (var y = 60.0; y < size.height - 10; y += size.height / 14) {
          for (var x = 20.0; x < size.width; x += size.width / 8) {
            await tester.tapAt(Offset(x, y));
            await tester.pump(const Duration(milliseconds: 60));
          }
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
      });
    }

    testWidgets('$k sefer ekranından aynı cihazda iki kişilik maç açılır', (tester) async {
      tester.view.physicalSize = const Size(1080, 2280);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final rules = stratejiRulesFor('oyun-c-$k', k);
      final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
      final gl = rules.build(planner.spec(3));
      final results = <RoundResult>[];
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SafeArea(child: StratejiStage(ctx: duelCtx(gl, const [], results), rules: rules)))));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(viewType(k)), findsNothing);
      await tester.tap(find.byIcon(Icons.people_alt));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(viewType(k)), findsOneWidget);
      final g = viewGame(tester, k);
      for (var i = 0; i < 400 && !g.over; i++) {
        await tester.pump(const Duration(seconds: 61));
      }
      expect(g.over, isTrue);
      await tester.pump(const Duration(seconds: 2));
      expect(results, isEmpty); // deneme maçı kaydedilmez
      await tester.tap(find.byType(FilledButton).last);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(viewType(k)), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });
  }
}

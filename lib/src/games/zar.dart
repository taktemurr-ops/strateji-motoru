import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../studio_chrome.dart';
import '../texts.dart';

/// Zar Macerası: kendi zarlarından oluşan bir torba. Her tur zarları at,
/// istemediklerini yeniden at, mücevherleri bir eyleme ata ve hamleni oyna.
/// Karşılaşmalar arasında bir yüzü güçlendir, yeni zar al ya da dinlen.
///
/// Yüz türleri: 0 kılıç, 1 kalkan, 2 şifa, 3 mücevher (istediğin eylem), 4 boş.
typedef ZFace = (int, int);

const List<String> kZFaceKeys = ['zm_sword', 'zm_shield', 'zm_heal', 'zm_gem', 'zm_blank'];
const List<IconData> kZFaceIcons = [Icons.hardware, Icons.shield, Icons.favorite, Icons.diamond, Icons.remove];
const List<Color> kZFaceColors = [Color(0xFFB0563B), Color(0xFF3E6FB0), Color(0xFF4F9A6E), Color(0xFF7A4E7E), Color(0xFF9A9286)];

/// Başlangıç torbası: dört zar.
const List<List<ZFace>> kZStart = [
  [(0, 3), (0, 2), (0, 2), (1, 2), (1, 1), (3, 1)],
  [(0, 2), (1, 3), (1, 2), (2, 2), (0, 1), (4, 0)],
  [(0, 2), (0, 2), (1, 1), (3, 1), (2, 2), (4, 0)],
  [(0, 1), (1, 1), (0, 2), (2, 1), (1, 2), (4, 0)],
];

/// Rakipler: ad anahtarı, temel dayanıklılık, niyet sırası (0 saldırı, 1 korunma, 2 toparlanma).
const List<(String, int, List<(int, int)>)> kZFoes = [
  ('zm_e_moth', 9, [(0, 3), (0, 4), (1, 3)]),
  ('zm_e_crab', 12, [(1, 4), (0, 5), (0, 2)]),
  ('zm_e_vine', 10, [(0, 2), (0, 3), (2, 3), (0, 4)]),
  ('zm_e_owl', 10, [(0, 4), (1, 2), (0, 5)]),
  ('zm_e_golem', 15, [(1, 5), (0, 6), (0, 2)]),
];
const (String, int, List<(int, int)>) kZBoss = ('zm_e_keeper', 20, [(0, 4), (1, 5), (0, 7), (2, 3)]);
const List<IconData> kZFoeIcons = [Icons.bug_report, Icons.set_meal, Icons.grass, Icons.nightlight, Icons.landscape, Icons.fort];

class ZEnc {
  final int foe; // 0..4 sıradan, 5 bekçi
  final int hp;
  final List<(int, int)> pattern;
  const ZEnc(this.foe, this.hp, this.pattern);
}

class ZReward {
  /// Güçlendirilecek zar (torbadaki sıra, mod alınır).
  final int die;
  final List<ZFace> newDie;
  const ZReward(this.die, this.newDie);
}

class ZPuzzle extends SPuzzle {
  final int seed, d;
  final List<ZEnc> encs;
  final List<ZReward> rewards;
  final int botHp;
  const ZPuzzle(this.seed, this.d, this.encs, this.rewards, this.botHp);
}

const int kZBaseHp = 24;

/// Bir seferin durumu: zarlar, can, karşılaşma, atılmış yüzler.
class ZRun {
  final ZPuzzle z;
  final SeededRandom rng;
  final List<List<ZFace>> dice;
  int maxHp, hp;
  final int rerollsPerTurn;
  final int restHeal;
  int enc = 0, foeHp = 0, turn = 0;
  List<ZFace> faces = [];
  List<bool> keep = [];

  /// Mücevher yüzlerinin seçilen eylemi (0 kılıç, 1 kalkan, 2 şifa).
  List<int> gemAs = [];
  int rerolls = 0;
  bool reward = false, over = false, won = false;
  int dealt = 0, turnsTotal = 0;

  ZRun(this.z, {int extraHp = 0, this.rerollsPerTurn = 1, bool gemStart = false, bool extraDie = false, this.restHeal = 0})
      : rng = SeededRandom(mixSeed([z.seed, 77])),
        dice = [for (final d in kZStart) [...d]],
        maxHp = kZBaseHp + extraHp,
        hp = kZBaseHp + extraHp {
    if (gemStart) dice[1][5] = (3, 1);
    if (extraDie) dice.add([(0, 2), (1, 2), (3, 1), (2, 1), (0, 1), (1, 1)]);
    _startEnc();
  }

  ZEnc get cur => z.encs[enc];
  (int, int) get intent => cur.pattern[turn % cur.pattern.length];
  int get atk => intent.$1 == 0 ? intent.$2 : 0;
  int get block => intent.$1 == 1 ? intent.$2 : 0;

  void _startEnc() {
    foeHp = cur.hp;
    turn = 0;
    _roll(all: true);
  }

  void _roll({required bool all}) {
    if (all) {
      faces = [for (final d in dice) d[rng.nextInt(6)]];
      keep = List<bool>.filled(dice.length, false);
      gemAs = List<int>.filled(dice.length, 0);
      rerolls = rerollsPerTurn;
    } else {
      for (var i = 0; i < dice.length; i++) {
        if (!keep[i]) faces[i] = dice[i][rng.nextInt(6)];
      }
    }
  }

  bool reroll() {
    if (rerolls <= 0 || reward || over || keep.every((k) => k)) return false;
    rerolls--;
    _roll(all: false);
    return true;
  }

  /// Bu turun toplamları: kılıç, kalkan, şifa.
  (int, int, int) totals() {
    var sw = 0, sh = 0, he = 0;
    for (var i = 0; i < faces.length; i++) {
      final f = faces[i];
      final t = f.$1 == 3 ? gemAs[i] : f.$1;
      if (t == 0) sw += f.$2;
      if (t == 1) sh += f.$2;
      if (t == 2) he += f.$2;
    }
    return (sw, sh, he);
  }

  /// Hamleyi oyna. Sonuç: 0 sürüyor, 1 karşılaşma kazanıldı, 2 sefer bitti (kazanç), -1 yenilgi.
  int resolve() {
    if (reward || over) return 0;
    final (sw, sh, he) = totals();
    final dmg = math.max<int>(0, sw - block);
    foeHp -= dmg;
    dealt += dmg;
    turnsTotal++;
    if (foeHp <= 0) {
      if (enc == z.encs.length - 1) {
        over = true;
        won = true;
        return 2;
      }
      reward = true;
      return 1;
    }
    hp = math.min<int>(maxHp, hp + he);
    hp -= math.max<int>(0, atk - sh);
    if (intent.$1 == 2) foeHp = math.min<int>(cur.hp, foeHp + intent.$2);
    if (hp <= 0) {
      hp = 0;
      over = true;
      return -1;
    }
    turn++;
    if (turn > 80) {
      over = true;
      return -1;
    }
    _roll(all: true);
    return 0;
  }

  ZReward get offer => z.rewards[enc];

  /// En zayıf yüz: önce boşlar, sonra en düşük değer.
  int weakest(List<ZFace> die) {
    var bj = 0;
    for (var j = 1; j < 6; j++) {
      final a = die[j], b = die[bj];
      final ka = a.$1 == 4 ? -1 : a.$2, kb = b.$1 == 4 ? -1 : b.$2;
      if (ka < kb) bj = j;
    }
    return bj;
  }

  int get upgradeDie => offer.die % dice.length;

  /// Ödül: 0 yüz güçlendir, 1 yeni zar, 2 dinlen.
  void takeReward(int k) {
    if (!reward) return;
    if (k == 0) {
      final die = dice[upgradeDie];
      final j = weakest(die);
      final f = die[j];
      die[j] = f.$1 == 4 ? (3, 1) : (f.$1, math.min<int>(4, f.$2 + 1));
    } else if (k == 1) {
      dice.add([...offer.newDie]);
    } else {
      hp = math.min<int>(maxHp, hp + 6);
    }
    hp = math.min<int>(maxHp, hp + restHeal);
    reward = false;
    enc++;
    _startEnc();
  }

  // ---------------------------------------------------------------- yapay zekâ

  bool useful(ZFace f) {
    final t = f.$1;
    return t == 0 || t == 3 || (t == 1 && atk > 0) || (t == 2 && hp < maxHp - 1);
  }

  /// Yeniden atılacakları seç (tutulanları işaretle).
  void botKeep() {
    for (var i = 0; i < faces.length; i++) {
      keep[i] = useful(faces[i]);
    }
  }

  void botGems() {
    var (sw, sh, he) = totals();
    for (var i = 0; i < faces.length; i++) {
      if (faces[i].$1 != 3) continue;
      final v = faces[i].$2;
      int a;
      if (sw + v - block >= foeHp) {
        a = 0;
      } else if (hp + he <= atk - sh) {
        a = 1;
      } else if (hp < maxHp ~/ 2) {
        a = 2;
      } else {
        a = 0;
      }
      gemAs[i] = a;
      if (a == 0) sw += v;
      if (a == 1) sh += v;
      if (a == 2) he += v;
    }
  }

  int botReward() => hp * 2 < maxHp ? 2 : (dice.length < 6 ? 1 : 0);

  /// Bir tam tur: yeniden at, mücevherleri ata, oyna.
  int botTurn() {
    if (rerolls > 0) {
      botKeep();
      if (keep.any((k) => !k)) reroll();
    }
    botGems();
    return resolve();
  }
}

/// Temel donanımlı yapay zekâ seferi; kazanırsa kalan can, yoksa -1.
int zBot(ZPuzzle z) {
  final s = ZRun(z);
  var guard = 0;
  while (!s.over && guard++ < 2000) {
    if (s.reward) {
      s.takeReward(s.botReward());
      continue;
    }
    s.botTurn();
  }
  return s.won ? s.hp : -1;
}

class ZarKind extends StratejiKind {
  @override
  String get id => 'zar';
  const ZarKind();

  @override
  SPuzzle? make(int d, SeededRandom r) {
    final n = 3 + d ~/ 4;
    final encs = <ZEnc>[];
    for (var i = 0; i < n; i++) {
      final boss = i == n - 1;
      final fi = boss ? 5 : r.nextInt(kZFoes.length);
      final f = boss ? kZBoss : kZFoes[fi];
      final hp = (f.$2 * (1 + 0.05 * d + 0.10 * i)).floor();
      final add = (d + 2 * i) ~/ 5;
      encs.add(ZEnc(fi, hp, [for (final (t, v) in f.$3) (t, t == 2 ? v + add ~/ 2 : v + add)]));
    }
    final rewards = <ZReward>[];
    for (var i = 0; i < n - 1; i++) {
      final k = r.nextInt(6);
      final nd = <ZFace>[];
      for (var j = 0; j < 6; j++) {
        final t = r.weighted(const [3, 3, 1, 1, 1]);
        nd.add((t, t == 4 ? 0 : (r.chance(0.34) ? 2 : 1)));
      }
      rewards.add(ZReward(k, nd));
    }
    final z0 = ZPuzzle(r.nextUint32(), d, encs, rewards, 0);
    final hp = zBot(z0);
    if (hp < 0) return null;
    return ZPuzzle(z0.seed, d, encs, rewards, hp);
  }

  @override
  bool check(SPuzzle p) => p is ZPuzzle && p.botHp > 0 && zBot(p) == p.botHp;

  @override
  List<Perk> get perks => const [
        Perk(3, Icons.casino_outlined, 'zm_roll', 1),
        Perk(8, Icons.favorite, 'hp', 4),
        Perk(15, Icons.diamond, 'zm_gem', 1),
        Perk(25, Icons.add_box, 'zm_newDie', 1),
        Perk(40, Icons.spa, 'zm_restPerk', 2),
      ];

  @override
  List<GameStat> get stats => const [
        GameStat('runs_won', 'Kazanılan macera', 'Adventures won', scale: 10),
        GameStat('flawless', 'Kusursuz macera', 'Flawless adventures', scale: 10),
        GameStat('encounters', 'Aşılan karşılaşma', 'Encounters cleared', scale: 50),
      ];

  @override
  Widget build(StratejiPlay play) => _ZView(play: play);
}

class _ZView extends StatefulWidget {
  final StratejiPlay play;
  const _ZView({required this.play});
  @override
  State<_ZView> createState() => _ZViewState();
}

class _ZViewState extends State<_ZView> with Clock, MetaLoader {
  late ZRun s;
  int hints = 0;
  bool hinted = false;
  int cleared = 0;
  String flash = '';

  StratejiPlay get p => widget.play;
  ZPuzzle get z => p.puzzle as ZPuzzle;

  ZRun _fresh() => ZRun(
        z,
        rerollsPerTurn: p.has(usta, 0) ? 2 : 1,
        extraHp: p.has(usta, 1) ? 4 : 0,
        gemStart: p.has(usta, 2),
        extraDie: p.has(usta, 3),
        restHeal: p.has(usta, 4) ? 2 : 0,
      );

  @override
  void initState() {
    super.initState();
    s = _fresh();
    startClock();
    loadMeta(p.gameId, () => s = _fresh());
  }

  void _play() {
    if (ended || s.reward) return;
    started = true;
    final before = s.foeHp;
    final r = s.resolve();
    final dmg = math.max<int>(0, before - s.foeHp);
    setState(() {
      hinted = false;
      flash = dmg > 0 ? '−$dmg' : '';
    });
    if (r == 1) {
      cleared++;
      p.sfx(Sfx.combo);
    } else if (r == 2) {
      cleared++;
      ended = true;
      p.sfx(Sfx.win);
      final stars = starsByHealth(s.hp, s.maxHp) - (hints > 0 ? 1 : 0);
      later(600, () => p.win(score: s.dealt * 5 + s.hp * 20 + p.d * 30, stars: stars, seconds: seconds, moves: s.turnsTotal, hints: hints, stats: {'encounters': cleared}));
    } else if (r == -1) {
      ended = true;
      p.sfx(Sfx.lose);
      later(700, () => p.lose(score: s.dealt * 5, seconds: seconds, moves: s.turnsTotal, stats: {'encounters': cleared}));
    } else {
      p.sfx(dmg > 0 ? Sfx.place : Sfx.tap);
    }
  }

  Future<void> _hint() async {
    if (ended || s.reward) return;
    final ok = await p.ctx.requestHint();
    if (!ok || !mounted) return;
    setState(() {
      hints++;
      hinted = true;
      if (s.rerolls > 0) s.botKeep();
      s.botGems();
    });
  }

  void _tapDie(int i) {
    if (ended || s.reward) return;
    started = true;
    setState(() {
      if (s.faces[i].$1 == 3) {
        s.gemAs[i] = (s.gemAs[i] + 1) % 3;
      } else if (s.rerolls > 0) {
        s.keep[i] = !s.keep[i];
      }
    });
    p.sfx(Sfx.tap);
  }

  @override
  Widget build(BuildContext context) {
    final lang = p.lang;
    final (sw, sh, he) = s.totals();
    return Stack(children: [
      SScreen(
        bar: SBar(
          lang: lang,
          left: '${st(lang, 'fight')} ${s.enc + 1}/${z.encs.length}',
          status: '${st(lang, 'hp')} ${s.hp}/${s.maxHp}',
          onHint: ended || s.reward ? null : _hint,
        ),
        top: PerkStrip(lang: lang, perks: p.perks, usta: usta),
        board: _board(lang),
        bottom: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(alignment: WrapAlignment.center, spacing: 10, children: [
            IconNum(kZFaceIcons[0], '$sw', color: kZFaceColors[0], size: 16),
            IconNum(kZFaceIcons[1], '$sh', color: kZFaceColors[1], size: 16),
            IconNum(kZFaceIcons[2], '$he', color: kZFaceColors[2], size: 16),
          ]),
          const SizedBox(height: 6),
          Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
            for (var i = 0; i < s.faces.length; i++) _die(i),
          ]),
          const SizedBox(height: 4),
          Text(st(lang, 'zm_keepHint'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: kStudioSubtle)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: !ended && !s.reward && s.rerolls > 0 && s.keep.any((k) => !k)
                    ? () {
                        started = true;
                        setState(() => s.reroll());
                        p.sfx(Sfx.tap);
                      }
                    : null,
                icon: const Icon(Icons.casino_outlined),
                label: FittedBox(fit: BoxFit.scaleDown, child: Text('${st(lang, 'zm_roll')} (${s.rerolls})')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: ended || s.reward ? null : _play,
                icon: const Icon(Icons.play_arrow),
                label: FittedBox(fit: BoxFit.scaleDown, child: Text(st(lang, 'zm_apply'))),
              ),
            ),
          ]),
        ]),
      ),
      if (s.reward && !ended) _rewardPanel(lang),
    ]);
  }

  Widget _board(String lang) {
    final e = s.cur;
    final it = s.intent;
    final ic = it.$1 == 0 ? Icons.flash_on : (it.$1 == 1 ? Icons.shield_outlined : Icons.healing);
    final icColor = it.$1 == 0 ? SColors.bad : (it.$1 == 1 ? SColors.accent : SColors.good);
    return LayoutBuilder(builder: (context, box) {
      final size = math.min<double>(box.maxWidth, box.maxHeight) * 0.42;
      return Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(st(lang, kZFoeName(e.foe)), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Stack(alignment: Alignment.center, children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: e.foe == 5 ? const Color(0xFF5B4636) : SColors.warm[e.foe % SColors.warm.length].withValues(alpha: 0.85),
                boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black26)],
              ),
              child: Icon(kZFoeIcons[e.foe], size: size * 0.5, color: Colors.white),
            ),
            if (flash.isNotEmpty)
              Positioned(top: 0, right: 0, child: Text(flash, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: SColors.bad))),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            width: math.max<double>(120, size * 1.4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: clampD(s.foeHp / math.max<int>(1, e.hp), 0, 1), minHeight: 10, color: SColors.bad, backgroundColor: Colors.black12),
            ),
          ),
          const SizedBox(height: 4),
          Text('${math.max<int>(0, s.foeHp)}/${e.hp}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Tooltip(
            message: st(lang, it.$1 == 0 ? 'atk' : (it.$1 == 1 ? 'def' : 'zm_recover')),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: icColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14), border: Border.all(color: icColor)),
              child: IconNum(ic, '${it.$2}', color: icColor, size: 18),
            ),
          ),
        ]),
        ),
      );
    });
  }

  Widget _die(int i) {
    final f = s.faces[i];
    final t = f.$1 == 3 ? s.gemAs[i] : f.$1;
    final sel = s.keep[i] && s.rerolls > 0;
    return SChip(
      selected: sel,
      color: hinted && s.keep[i] ? const Color(0xFFF6E3B4) : null,
      tooltip: st(p.lang, kZFaceKeys[f.$1]),
      onTap: () => _tapDie(i),
      child: SizedBox(
        width: 44,
        height: 48,
        // Büyük yazıda zarın içi kutuya sığacak kadar küçülür.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (f.$1 == 3) Icon(kZFaceIcons[3], size: 12, color: studioLift(kZFaceColors[3])),
              Icon(kZFaceIcons[f.$1 == 4 ? 4 : t], size: 22, color: studioLift(kZFaceColors[f.$1 == 4 ? 4 : t])),
            ]),
            Text(f.$1 == 4 ? '' : '${f.$2}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ]),
        ),
      ),
    );
  }

  Widget _rewardPanel(String lang) {
    final up = s.dice[s.upgradeDie];
    final j = s.weakest(up);
    final f = up[j];
    final nf = f.$1 == 4 ? (3, 1) : (f.$1, math.min<int>(4, f.$2 + 1));
    Widget face(ZFace x) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: IconNum(kZFaceIcons[x.$1], x.$1 == 4 ? '' : '${x.$2}', color: kZFaceColors[x.$1], size: 12),
        );
    Widget opt(int k, IconData icon, String title, Widget detail) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SizedBox(
            width: double.infinity,
            child: SChip(
              onTap: () {
                setState(() => s.takeReward(k));
                p.sfx(Sfx.coin);
              },
              child: Row(children: [
                Icon(icon, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: detail),
                  ]),
                ),
              ]),
            ),
          ),
        );
    return Positioned.fill(
      child: Container(
        color: Colors.black26,
        child: SingleChildScrollView(
          child: SPanel(title: st(lang, 'zm_reward'), children: [
            opt(0, Icons.upgrade, st(lang, 'zm_upgrade'), Row(mainAxisSize: MainAxisSize.min, children: [face(f), const Icon(Icons.arrow_forward, size: 14), face(nf)])),
            opt(1, Icons.add_box, st(lang, 'zm_newDie'), Row(mainAxisSize: MainAxisSize.min, children: [for (final x in s.offer.newDie) face(x)])),
            opt(2, Icons.local_fire_department, st(lang, 'rest'), IconNum(Icons.favorite, '+6', color: SColors.good, size: 13)),
          ]),
        ),
      ),
    );
  }
}

String kZFoeName(int foe) => foe == 5 ? kZBoss.$1 : kZFoes[foe].$1;

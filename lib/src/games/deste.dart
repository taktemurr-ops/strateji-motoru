import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../texts.dart';

/// Deste Seferi: kart destesi kurarak art arda karşılaşmaları geç.
/// Her tur 3 enerji ve 5 kart; rakibin niyeti önceden görünür.
class DCard {
  final String id;
  final int cost, dmg, hits, blk, draw, str, weak, heal, energy, thorns;
  final bool pierce, exhaust, blkDmg;
  const DCard(this.id, this.cost,
      {this.dmg = 0,
      this.hits = 1,
      this.blk = 0,
      this.draw = 0,
      this.str = 0,
      this.weak = 0,
      this.heal = 0,
      this.energy = 0,
      this.thorns = 0,
      this.pierce = false,
      this.exhaust = false,
      this.blkDmg = false});
  bool get attacks => dmg > 0 || blkDmg;
}

const Map<String, DCard> kCards = {
  'strike': DCard('strike', 1, dmg: 6),
  'guard': DCard('guard', 1, blk: 5),
  'focus': DCard('focus', 0, draw: 2),
  'twin': DCard('twin', 1, dmg: 4, hits: 2),
  'maul': DCard('maul', 2, dmg: 14),
  'wall': DCard('wall', 2, blk: 12),
  'echo': DCard('echo', 1, dmg: 5, draw: 1),
  'spines': DCard('spines', 1, blk: 4, thorns: 3),
  'rally': DCard('rally', 1, str: 2),
  'fog': DCard('fog', 1, weak: 2),
  'arrow': DCard('arrow', 1, dmg: 8, pierce: true),
  'regroup': DCard('regroup', 1, blk: 3, draw: 2),
  'stance': DCard('stance', 1, blk: 8),
  'storm': DCard('storm', 2, dmg: 3, hits: 4),
  'spark': DCard('spark', 0, energy: 1, exhaust: true),
  'salve': DCard('salve', 1, heal: 5, exhaust: true),
  'counter': DCard('counter', 1, blkDmg: true),
  'whirl': DCard('whirl', 1, dmg: 4, blk: 4),
  'wisdom': DCard('wisdom', 1, draw: 3, exhaust: true),
  'mud': DCard('mud', 1, exhaust: true),
};

const List<String> kBasePool = ['twin', 'maul', 'wall', 'echo', 'spines', 'rally', 'fog', 'arrow', 'regroup', 'stance'];
const List<String> kPool2 = ['storm', 'spark', 'salve'];
const List<String> kPool3 = ['counter', 'whirl', 'wisdom'];
const Map<String, int> kRank = {
  'maul': 9, 'arrow': 8, 'storm': 8, 'wall': 7, 'twin': 7, 'echo': 7, 'stance': 6, 'regroup': 6, 'rally': 6, //
  'whirl': 6, 'fog': 5, 'spines': 5, 'wisdom': 5, 'spark': 5, 'salve': 4, 'counter': 3,
};

/// Rakip niyeti: 0 saldırı, 1 çoklu saldırı, 2 blok, 3 güçlenme, 4 çamur kartı.
class DIntent {
  final int kind, n, hits;
  const DIntent(this.kind, this.n, [this.hits = 1]);
}

class DFoe {
  final String key;
  final int hp;
  final List<DIntent> pattern;
  final Color color;
  final bool boss;
  const DFoe(this.key, this.hp, this.pattern, this.color, {this.boss = false});
}

const List<DFoe> kFoes = [
  DFoe('dMushroom', 22, [DIntent(0, 6), DIntent(2, 5), DIntent(0, 7), DIntent(4, 0)], Color(0xFFB5654A)),
  DFoe('dBird', 18, [DIntent(1, 3, 2), DIntent(0, 5), DIntent(3, 1)], Color(0xFF5B8DB8)),
  DFoe('dCrab', 28, [DIntent(2, 8), DIntent(0, 8), DIntent(2, 6), DIntent(0, 10)], Color(0xFFD0704A)),
  DFoe('dClock', 24, [DIntent(0, 4), DIntent(0, 4), DIntent(0, 12)], Color(0xFFB59A5B)),
  DFoe('dMist', 20, [DIntent(4, 0), DIntent(0, 7), DIntent(0, 7), DIntent(3, 2)], Color(0xFF8D97A8)),
];
const List<DFoe> kBosses = [
  DFoe('dWarden', 55, [DIntent(2, 10), DIntent(0, 12), DIntent(1, 4, 3), DIntent(3, 2), DIntent(0, 15)], Color(0xFF6D7A68), boss: true),
  DFoe('dDrake', 60, [DIntent(0, 10), DIntent(4, 0), DIntent(1, 5, 3), DIntent(2, 12), DIntent(0, 18)], Color(0xFF5FA8A3), boss: true),
];

class DFight {
  final DFoe foe;
  final int hp, atk, offset;
  const DFight(this.foe, this.hp, this.atk, this.offset);
}

class DPuzzle extends SPuzzle {
  final int seed, d;
  const DPuzzle(this.seed, this.d);
}

List<DFight> dFights(int seed, int d) {
  final r = SeededRandom(mixSeed([seed, 5501]));
  final n = 3 + d ~/ 3;
  final out = <DFight>[];
  for (var i = 0; i < n - 1; i++) {
    final f = kFoes[r.nextInt(kFoes.length)];
    out.add(DFight(f, (f.hp * (1 + 0.05 * d + 0.1 * i)).floor(), d ~/ 3 + i ~/ 2, r.nextInt(f.pattern.length)));
  }
  final b = kBosses[r.nextInt(kBosses.length)];
  out.add(DFight(b, (b.hp * (1 + 0.06 * d)).floor(), d ~/ 3, 0));
  return out;
}

/// Seferin tüm durumu. Arayüz ve yapay zekâ aynı kuralları kullanır.
class DSim {
  final int seed, d;
  final List<DFight> fights;
  final List<String> pool;
  final int rewardCount;
  final int startBlock;
  late SeededRandom r;
  final List<String> deck = ['strike', 'strike', 'strike', 'strike', 'strike', 'guard', 'guard', 'guard', 'guard', 'focus'];
  int hp, maxHp;
  int fight = 0;

  // karşılaşma durumu
  List<String> draw = [], disc = [], hand = [], exh = [];
  int ehp = 0, eblk = 0, estr = 0, weak = 0, pstr = 0, turn = 0;
  int blk = 0, energy = 0, thorns = 0;

  /// 0 savaş, 1 ödül seçimi, 2 bitti
  int phase = 0;
  List<String> offers = [];
  bool won = false, lost = false;
  int dealt = 0, cardsPlayed = 0;

  DSim(this.seed, this.d, {int extraHp = 0, this.pool = kBasePool, this.rewardCount = 3, this.startBlock = 0})
      : fights = dFights(seed, d),
        hp = 40 + extraHp,
        maxHp = 40 + extraHp {
    r = SeededRandom(mixSeed([seed, 77]));
    _startFight();
  }

  DFight get cur => fights[fight];
  DIntent get intent => cur.foe.pattern[(cur.offset + turn) % cur.foe.pattern.length];

  void _startFight() {
    draw = [...deck];
    r.shuffle(draw);
    disc = [];
    exh = [];
    hand = [];
    ehp = cur.hp;
    eblk = 0;
    estr = 0;
    weak = 0;
    pstr = 0;
    turn = 0;
    _startTurn();
  }

  void _startTurn() {
    blk = turn == 0 ? startBlock : 0;
    energy = 3;
    thorns = 0;
    _draw(5);
  }

  void _draw(int k) {
    for (var i = 0; i < k; i++) {
      if (draw.isEmpty) {
        if (disc.isEmpty) return;
        draw = disc;
        disc = [];
        r.shuffle(draw);
      }
      hand.add(draw.removeLast());
    }
  }

  /// Rakibin bu tur vuracağı toplam hasar (zayıflatma sonrası).
  int get incoming {
    final it = intent;
    final per = math.max<int>(0, it.n + cur.atk + estr - weak);
    if (it.kind == 0) return per;
    if (it.kind == 1) return per * it.hits;
    return 0;
  }

  int dmgOf(DCard k) => k.blkDmg ? blk : (k.dmg > 0 ? (k.dmg + pstr) * k.hits : 0);

  bool canPlay(int i) => phase == 0 && i >= 0 && i < hand.length && kCards[hand[i]]!.cost <= energy;

  void play(int i) {
    if (!canPlay(i)) return;
    final id = hand.removeAt(i);
    final k = kCards[id]!;
    energy -= k.cost;
    cardsPlayed++;
    if (k.attacks) {
      for (var h = 0; h < k.hits; h++) {
        final dd = k.blkDmg ? blk : k.dmg + pstr;
        dealt += dd;
        if (k.pierce) {
          ehp -= dd;
        } else {
          final a = math.min<int>(eblk, dd);
          eblk -= a;
          ehp -= dd - a;
        }
      }
    }
    blk += k.blk;
    pstr += k.str;
    weak += k.weak;
    hp = math.min<int>(maxHp, hp + k.heal);
    energy += k.energy;
    thorns += k.thorns;
    (k.exhaust ? exh : disc).add(id);
    if (k.draw > 0) _draw(k.draw);
    if (ehp <= 0) _fightWon();
  }

  void _fightWon() {
    if (fight >= fights.length - 1) {
      phase = 2;
      won = true;
      return;
    }
    final opts = [...pool];
    r.shuffle(opts);
    offers = opts.take(math.min<int>(rewardCount, opts.length)).toList();
    phase = 1;
  }

  void endTurn() {
    if (phase != 0) return;
    disc.addAll(hand);
    hand = [];
    final it = intent;
    eblk = 0;
    if (it.kind == 0 || it.kind == 1) {
      final hits = it.kind == 1 ? it.hits : 1;
      for (var h = 0; h < hits; h++) {
        final dd = math.max<int>(0, it.n + cur.atk + estr - weak);
        final a = math.min<int>(blk, dd);
        blk -= a;
        hp -= dd - a;
        if (thorns > 0) ehp -= thorns;
      }
    } else if (it.kind == 2) {
      eblk = it.n + cur.atk;
    } else if (it.kind == 3) {
      estr += it.n;
    } else {
      disc.add('mud');
    }
    if (hp <= 0) {
      phase = 2;
      lost = true;
      return;
    }
    if (ehp <= 0) {
      _fightWon();
      return;
    }
    turn++;
    if (turn > 40) {
      phase = 2;
      lost = true;
      return;
    }
    _startTurn();
  }

  /// Ödül: [i] teklif, -1 geç.
  void choose(int i) {
    if (phase != 1) return;
    if (i >= 0 && i < offers.length) deck.add(offers[i]);
    if (fight % 2 == 1) hp = math.min<int>(maxHp, hp + 12);
    fight++;
    phase = 0;
    _startFight();
  }

  // ------------------------------------------------------------ yapay zekâ

  double score(String id) {
    final k = kCards[id]!;
    final inc = incoming - blk;
    var s = 0.0;
    if (k.draw > 0 || k.energy > 0) s += 50;
    if (id == 'mud') s = energy >= 2 ? -5.0 : -20.0;
    if (k.str > 0 && turn <= 1) s += 30;
    if (k.weak > 0 && turn <= 1) s += 25;
    if (k.heal > 0) s += hp < maxHp - 8 ? 20 : -30;
    final d0 = dmgOf(k);
    if (d0 >= ehp + eblk) s += 100;
    if (inc > 0 && k.blk > 0) s += 10 + math.min<int>(inc, k.blk) * 3;
    s += d0 * (inc <= 0 ? 1.2 : 0.8);
    if (k.blk > 0 && inc <= 0) s += k.blk * 0.3;
    return s / (k.cost + 0.6);
  }

  /// Önerilen kart (oynanacak bir şey yoksa -1: turu bitir).
  int botCard() {
    var best = -1;
    var bv = -1e9;
    for (var i = 0; i < hand.length; i++) {
      if (!canPlay(i)) continue;
      final v = score(hand[i]);
      if (v > bv) {
        bv = v;
        best = i;
      }
    }
    if (best < 0) return -1;
    if (bv < -10) return -1;
    if (bv <= 0 && hand[best] == 'mud') return -1;
    return best;
  }

  int botReward() {
    var best = 0;
    for (var i = 1; i < offers.length; i++) {
      if ((kRank[offers[i]] ?? 0) > (kRank[offers[best]] ?? 0)) best = i;
    }
    return offers.isEmpty ? -1 : best;
  }

  void botStep() {
    if (phase == 1) {
      choose(botReward());
      return;
    }
    final c = botCard();
    if (c < 0) {
      endTurn();
    } else {
      play(c);
    }
  }
}

class DesteKind extends StratejiKind {
  @override
  String get id => 'deste';
  const DesteKind();

  @override
  SPuzzle? make(int d, SeededRandom r) => DPuzzle(r.nextUint32(), d);

  @override
  bool check(SPuzzle p) {
    if (p is! DPuzzle) return false;
    final s = DSim(p.seed, p.d);
    var guard = 0;
    while (s.phase != 2 && guard++ < 3000) {
      s.botStep();
    }
    return s.won;
  }

  @override
  List<Perk> get perks => const [
        Perk(3, Icons.favorite, 'pMaxHp', 6),
        Perk(8, Icons.style, 'pCards', 3),
        Perk(15, Icons.shield, 'pBlock', 4),
        Perk(25, Icons.style, 'pCards', 3),
        Perk(40, Icons.add_card, 'pChoice', 1),
      ];

  @override
  List<GameStat> get stats => const [
        GameStat('runs_won', 'Kazanılan sefer', 'Runs won', scale: 10),
        GameStat('flawless', 'Kusursuz sefer', 'Flawless runs', scale: 10),
        GameStat('cards_played', 'Oynanan kart', 'Cards played', scale: 100),
      ];

  @override
  Widget build(StratejiPlay play) => _DView(play: play);
}

IconData dIntentIcon(int kind) => switch (kind) {
      0 => Icons.local_fire_department,
      1 => Icons.whatshot,
      2 => Icons.shield,
      3 => Icons.fitness_center,
      _ => Icons.water_drop,
    };

class _DView extends StatefulWidget {
  final StratejiPlay play;
  const _DView({required this.play});
  @override
  State<_DView> createState() => _DViewState();
}

class _DViewState extends State<_DView> with Clock, MetaLoader {
  late DSim s;
  int hints = 0;
  int hinted = -2;
  bool legend = false;

  StratejiPlay get p => widget.play;
  DPuzzle get z => p.puzzle as DPuzzle;

  DSim _fresh() => DSim(
        z.seed,
        z.d,
        extraHp: p.has(usta, 0) ? 6 : 0,
        pool: [...kBasePool, if (p.has(usta, 1)) ...kPool2, if (p.has(usta, 3)) ...kPool3],
        startBlock: p.has(usta, 2) ? 4 : 0,
        rewardCount: p.has(usta, 4) ? 4 : 3,
      );

  @override
  void initState() {
    super.initState();
    s = _fresh();
    startClock();
    loadMeta(p.gameId, () => s = _fresh());
  }

  void _after(int ehpBefore, int hpBefore) {
    started = true;
    hinted = -2;
    if (s.won) {
      ended = true;
      p.sfx(Sfx.win);
      final stars = starsByHealth(s.hp, s.maxHp) - (hints > 0 ? 1 : 0);
      later(500, () => p.win(score: s.dealt + s.hp * 5 + p.d * 30, stars: stars, seconds: seconds, moves: s.cardsPlayed, hints: hints, stats: {'cards_played': s.cardsPlayed}));
    } else if (s.lost) {
      ended = true;
      later(600, () => p.lose(score: s.dealt, seconds: seconds, moves: s.cardsPlayed, stats: {'cards_played': s.cardsPlayed}));
    } else if (s.phase == 1) {
      p.sfx(Sfx.coin);
    } else if (s.hp < hpBefore) {
      p.sfx(Sfx.error);
    } else if (s.ehp < ehpBefore) {
      p.sfx(Sfx.clear);
    } else {
      p.sfx(Sfx.place);
    }
    setState(() {});
  }

  void _play(int i) {
    if (ended || !s.canPlay(i)) {
      p.sfx(Sfx.error);
      return;
    }
    final e = s.ehp, h = s.hp;
    s.play(i);
    _after(e, h);
  }

  void _end() {
    if (ended) return;
    final e = s.ehp, h = s.hp;
    s.endTurn();
    _after(e, h);
  }

  void _choose(int i) {
    if (ended) return;
    s.choose(i);
    _after(s.ehp, s.hp);
  }

  Future<void> _hint() async {
    if (ended) return;
    final ok = await p.ctx.requestHint();
    if (!ok || !mounted) return;
    setState(() {
      hints++;
      hinted = s.phase == 1 ? s.botReward() : s.botCard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = p.lang;
    final status = '${st(lang, 'fight')} ${s.fight + 1}/${s.fights.length} · ${st(lang, 'deck')} ${s.draw.length} · ${st(lang, 'discard')} ${s.disc.length}';
    return SScreen(
      bar: SBar(lang: lang, left: '♥ ${s.hp}/${s.maxHp}', status: status, onHint: ended ? null : _hint, extra: [
        IconButton(tooltip: st(lang, 'legend'), onPressed: () => setState(() => legend = !legend), icon: const Icon(Icons.help_outline)),
      ]),
      top: PerkStrip(lang: lang, perks: p.perks, usta: usta),
      board: Stack(children: [
        Column(children: [
          Expanded(flex: 5, child: _foe(lang)),
          const SizedBox(height: 6),
          _playerRow(lang),
          const SizedBox(height: 6),
          Expanded(flex: 6, child: _hand(lang)),
        ]),
        if (s.phase == 1) _reward(lang),
        if (legend) _legend(lang),
      ]),
      bottom: s.phase == 0
          ? SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: ended ? null : _end,
                icon: Icon(hinted == -1 ? Icons.lightbulb : Icons.skip_next),
                label: Text(st(lang, 'endTurn')),
              ),
            )
          : null,
    );
  }

  Widget _foe(String lang) {
    final f = s.cur.foe;
    final it = s.intent;
    final ratio = clampD(s.ehp / s.cur.hp, 0, 1);
    return Column(children: [
        Text('${st(lang, f.key)}${f.boss ? ' ★' : ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconNum(dIntentIcon(it.kind), it.kind <= 1 ? '${math.max<int>(0, it.n + s.cur.atk + s.estr - s.weak)}${it.kind == 1 ? '×${it.hits}' : ''}' : (it.kind == 2 ? '${it.n + s.cur.atk}' : (it.kind == 3 ? '+${it.n}' : '')), color: it.kind <= 1 ? SColors.bad : SColors.accent, size: 16),
          const SizedBox(width: 14),
          if (s.eblk > 0) IconNum(Icons.shield, '${s.eblk}', color: SColors.accent),
          if (s.estr > 0) ...[const SizedBox(width: 10), IconNum(Icons.fitness_center, '${s.estr}', color: SColors.bad)],
          if (s.weak > 0) ...[const SizedBox(width: 10), IconNum(Icons.trending_down, '${s.weak}', color: SColors.good)],
        ]),
        Expanded(
          child: TapCanvas(w: 100, h: 70, paint: (c) => _paintFoe(c, f), semantics: st(lang, f.key)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: ratio, minHeight: 10, color: SColors.bad, backgroundColor: Colors.black12),
          ),
        ),
        Text('${math.max<int>(0, s.ehp)}/${s.cur.hp}', style: const TextStyle(fontSize: 12)),
      ]);
  }

  Widget _playerRow(String lang) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconNum(Icons.bolt, '${s.energy}/3', color: SColors.gold, size: 18),
        const SizedBox(width: 16),
        IconNum(Icons.shield, '${s.blk}', color: SColors.accent, size: 18),
        if (s.pstr > 0) ...[const SizedBox(width: 16), IconNum(Icons.fitness_center, '${s.pstr}', color: SColors.good, size: 18)],
        if (s.thorns > 0) ...[const SizedBox(width: 16), IconNum(Icons.grass, '${s.thorns}', color: SColors.good, size: 18)],
      ]);

  Widget _hand(String lang) => SingleChildScrollView(
        child: Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
          for (var i = 0; i < s.hand.length; i++)
            DCardView(
              id: s.hand[i],
              lang: lang,
              playable: s.canPlay(i),
              highlight: hinted == i,
              str: s.pstr,
              onTap: () => _play(i),
            ),
        ]),
      );

  Widget _reward(String lang) => SPanel(title: st(lang, 'reward'), children: [
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < s.offers.length; i++)
            DCardView(id: s.offers[i], lang: lang, playable: true, highlight: hinted == i, str: 0, onTap: () => _choose(i)),
        ]),
        const SizedBox(height: 10),
        if (s.fight % 2 == 1) IconNum(Icons.favorite, '+12 ${st(lang, 'rest')}', color: SColors.good),
        TextButton(onPressed: () => _choose(-1), child: Text(st(lang, 'skip'))),
      ]);

  Widget _legend(String lang) => GestureDetector(
        onTap: () => setState(() => legend = false),
        child: SPanel(title: st(lang, 'legend'), children: [
          for (final e in const [
            (Icons.local_fire_department, 'kDamage'),
            (Icons.shield, 'kBlock'),
            (Icons.style, 'kDraw'),
            (Icons.bolt, 'kEnergy'),
            (Icons.favorite, 'kHeal'),
            (Icons.fitness_center, 'kStrength'),
            (Icons.trending_down, 'kWeak'),
            (Icons.arrow_forward, 'kPierce'),
            (Icons.grass, 'kThorns'),
            (Icons.hourglass_bottom, 'kExhaust'),
            (Icons.water_drop, 'c_mud'),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [Icon(e.$1, size: 18), const SizedBox(width: 8), Expanded(child: Text(st(lang, e.$2)))]),
            ),
        ]),
      );

  void _paintFoe(Canvas c, DFoe f) {
    final col = f.color;
    const o = Offset(50, 40);
    final k = f.boss ? 1.25 : 1.0;
    switch (f.key) {
      case 'dMushroom':
        c.drawRect(Rect.fromCenter(center: o + Offset(0, 10 * k), width: 12 * k, height: 20 * k), fill(const Color(0xFFEDE3CF)));
        c.drawArc(Rect.fromCenter(center: o + const Offset(0, 2), width: 44 * k, height: 34 * k), math.pi, math.pi, true, fill(col));
        for (final d in const [Offset(-10, -6), Offset(6, -10), Offset(12, -2)]) {
          c.drawCircle(o + d * k, 3 * k, fill(const Color(0xFFF4F1EA)));
        }
      case 'dBird':
        final path = Path()
          ..moveTo(o.dx - 26 * k, o.dy - 8 * k)
          ..quadraticBezierTo(o.dx - 8 * k, o.dy - 2 * k, o.dx, o.dy + 4 * k)
          ..quadraticBezierTo(o.dx + 8 * k, o.dy - 2 * k, o.dx + 26 * k, o.dy - 8 * k)
          ..quadraticBezierTo(o.dx + 10 * k, o.dy + 12 * k, o.dx, o.dy + 14 * k)
          ..quadraticBezierTo(o.dx - 10 * k, o.dy + 12 * k, o.dx - 26 * k, o.dy - 8 * k)
          ..close();
        c.drawPath(path, fill(col));
        c.drawCircle(o + Offset(0, -2 * k), 6 * k, fill(col));
      case 'dCrab':
        c.drawOval(Rect.fromCenter(center: o + const Offset(0, 6), width: 40 * k, height: 24 * k), fill(col));
        for (final sx in const [-1.0, 1.0]) {
          c.drawCircle(o + Offset(sx * 24 * k, -8 * k), 7 * k, fill(col));
          for (var i = 0; i < 3; i++) {
            c.drawLine(o + Offset(sx * 14 * k, (8 + i * 4) * k), o + Offset(sx * 26 * k, (14 + i * 4) * k), stroke(col, 2.2));
          }
        }
      case 'dClock':
        c.drawCircle(o, 22 * k, fill(col));
        c.drawCircle(o, 17 * k, fill(const Color(0xFFF4F1EA)));
        for (var i = 0; i < 12; i++) {
          final a = i * math.pi / 6;
          c.drawCircle(o + Offset(math.cos(a), math.sin(a)) * 14 * k, 1.2, fill(SColors.ink));
        }
        c.drawLine(o, o + Offset(0, -11 * k), stroke(SColors.ink, 2));
        c.drawLine(o, o + Offset(8 * k, 3 * k), stroke(SColors.ink, 2));
      case 'dMist':
        for (final d in const [Offset(-14, 4), Offset(0, -6), Offset(14, 4), Offset(0, 10)]) {
          c.drawCircle(o + d * k, 14 * k, fill(col.withValues(alpha: 0.7)));
        }
      case 'dWarden':
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: 40 * k, height: 48 * k), Radius.circular(8 * k)), fill(col));
        c.drawRect(Rect.fromCenter(center: o + Offset(0, -6 * k), width: 26 * k, height: 6 * k), fill(const Color(0xFF3B4239)));
        c.drawCircle(o + Offset(-6 * k, -6 * k), 2 * k, fill(SColors.gold));
        c.drawCircle(o + Offset(6 * k, -6 * k), 2 * k, fill(SColors.gold));
      default:
        final path = Path()..moveTo(o.dx, o.dy - 24 * k);
        for (var i = 1; i <= 6; i++) {
          final a = -math.pi / 2 + i * math.pi / 3;
          path.lineTo(o.dx + math.cos(a) * 24 * k, o.dy + math.sin(a) * 20 * k);
        }
        path.close();
        c.drawPath(path, fill(col));
        c.drawPath(path, stroke(const Color(0xAAFFFFFF), 1.5));
        c.drawLine(o + Offset(0, -24 * k), o + Offset(0, 20 * k), stroke(const Color(0x66FFFFFF), 1));
    }
    if (f.key != 'dClock' && f.key != 'dWarden') {
      c.drawCircle(o + Offset(-5 * k, 0), 2.2, fill(Colors.white));
      c.drawCircle(o + Offset(5 * k, 0), 2.2, fill(Colors.white));
      c.drawCircle(o + Offset(-5 * k, 0.5), 1.0, fill(SColors.ink));
      c.drawCircle(o + Offset(5 * k, 0.5), 1.0, fill(SColors.ink));
    }
  }
}

/// Tek kart görünümü: maliyet, ad, etki simgeleri.
class DCardView extends StatelessWidget {
  final String id;
  final String lang;
  final bool playable;
  final bool highlight;
  final int str;
  final VoidCallback onTap;
  const DCardView({super.key, required this.id, required this.lang, required this.playable, required this.highlight, required this.str, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final k = kCards[id]!;
    final effects = <Widget>[
      if (k.dmg > 0) IconNum(Icons.local_fire_department, '${k.dmg + str}${k.hits > 1 ? '×${k.hits}' : ''}', color: SColors.bad),
      if (k.blkDmg) const IconNum(Icons.local_fire_department, '= ', color: SColors.bad),
      if (k.blkDmg) const IconNum(Icons.shield, '', color: SColors.accent),
      if (k.blk > 0) IconNum(Icons.shield, '${k.blk}', color: SColors.accent),
      if (k.draw > 0) IconNum(Icons.style, '+${k.draw}'),
      if (k.energy > 0) IconNum(Icons.bolt, '+${k.energy}', color: SColors.gold),
      if (k.heal > 0) IconNum(Icons.favorite, '+${k.heal}', color: SColors.good),
      if (k.str > 0) IconNum(Icons.fitness_center, '+${k.str}', color: SColors.good),
      if (k.weak > 0) IconNum(Icons.trending_down, '${k.weak}', color: SColors.good),
      if (k.thorns > 0) IconNum(Icons.grass, '${k.thorns}', color: SColors.good),
      if (k.pierce) const Icon(Icons.arrow_forward, size: 16),
      if (k.exhaust) const Icon(Icons.hourglass_bottom, size: 14, color: Colors.black45),
    ];
    final base = id == 'mud' ? const Color(0xFFBFAE95) : (k.attacks ? const Color(0xFFF6E3DA) : const Color(0xFFDCE7F2));
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: playable ? 1 : 0.5,
        child: Container(
          width: 92,
          height: 118,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: highlight ? SColors.gold : const Color(0x33000000), width: highlight ? 3 : 1),
            boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black26, offset: Offset(0, 1))],
          ),
          child: Column(children: [
            Row(children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: SColors.gold, shape: BoxShape.circle),
                child: Text('${k.cost}', style: const TextStyle(fontWeight: FontWeight.w800, color: SColors.ink)),
              ),
            ]),
            const SizedBox(height: 4),
            Expanded(
              child: Text(st(lang, 'c_$id'),
                  textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SColors.ink)),
            ),
            Wrap(alignment: WrapAlignment.center, spacing: 4, runSpacing: 2, children: effects),
          ]),
        ),
      ),
    );
  }
}

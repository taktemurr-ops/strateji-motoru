import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../studio_chrome.dart';
import '../texts.dart';

/// Kale Kuşatması: üç şeritli gerçek zamanlı kuşatma. Enerji kendiliğinden
/// dolar; eldeki dört karttan biri seçilip bir şeride bırakılır, birlik
/// ilerler, karşılaştığı düşmanla çarpışır, karşı kaleye varırsa surlara
/// vurur. Karşı kale yıkılınca ya da süre bitince surları sağlam olan kazanır.
const int kKkLanes = 3;
const double kKkLen = 100;
const double kKkDt = 0.1;

/// Birlik: anahtar, bedel, can, vuruş, menzil, hız, bekleme.
class KkType {
  final String key;
  final int cost;
  final double hp, dmg, range, speed, cd;
  final IconData icon;
  const KkType(this.key, this.cost, this.hp, this.dmg, this.range, this.speed, this.cd, this.icon);
}

const List<KkType> kKkTypes = [
  KkType('u_spear', 2, 10, 2, 4, 8, 1.0, Icons.navigation),
  KkType('u_archer', 3, 6, 2, 18, 7, 1.2, Icons.call_made),
  KkType('u_shield', 4, 26, 1, 4, 5, 1.0, Icons.shield),
  KkType('u_rider', 4, 14, 3, 4, 14, 0.9, Icons.bolt),
  KkType('u_catapult', 5, 8, 6, 30, 4, 2.4, Icons.architecture),
  KkType('e_slinger', 2, 5, 1, 14, 9, 0.8, Icons.radio_button_checked),
];

class KkUnit {
  final int type, side, lane;
  double pos, hp, cd = 0;
  KkUnit(this.type, this.side, this.lane, this.pos, this.hp);
  KkType get t => kKkTypes[type];
}

class KkPuzzle extends SPuzzle {
  final int seed, d;
  final double enemyRegen, enemyCastle, duration;
  final List<int> enemyDeck;
  const KkPuzzle(this.seed, this.d, this.enemyRegen, this.enemyCastle, this.duration, this.enemyDeck);
}

class KkSim {
  final KkPuzzle z;
  double t = 0;
  final List<double> energy = [4, 4];
  final List<double> castle;
  final List<double> castleMax;
  final List<KkUnit> units = [];
  final double regen;
  List<int> hand = [0, 1, 5, 2];
  int deckI = 4;
  int enemyI = 0;
  double enemyThink = 2;
  int deployed = 0, routed = 0;
  final List<int> myDeck;

  KkSim(this.z, {double myCastle = 60, this.regen = 1.0, int startEnergy = 4, this.myDeck = const [0, 1, 5, 2, 3, 4]})
      : castle = [myCastle, z.enemyCastle],
        castleMax = [myCastle, z.enemyCastle] {
    energy[0] = startEnergy.toDouble();
    hand = [for (var i = 0; i < 4; i++) myDeck[i % myDeck.length]];
    deckI = 4;
  }

  bool get won => castle[1] <= 0 || (t >= z.duration && castle[0] / castleMax[0] > castle[1] / castleMax[1]);
  bool get lost => castle[0] <= 0 || (t >= z.duration && !won);
  bool get over => won || lost;

  /// Oyuncu (taraf 0) kart [h] ile şerit [lane]'e birlik bırakır.
  bool deploy(int h, int lane) {
    if (over || h < 0 || h >= hand.length || lane < 0 || lane >= kKkLanes) return false;
    final ty = hand[h];
    final c = kKkTypes[ty].cost;
    if (energy[0] < c) return false;
    energy[0] -= c;
    units.add(KkUnit(ty, 0, lane, 0, kKkTypes[ty].hp));
    hand[h] = myDeck[deckI % myDeck.length];
    deckI++;
    deployed++;
    return true;
  }

  double _threat(int side, int lane) {
    var v = 0.0;
    for (final u in units) {
      if (u.lane == lane && u.side == side) v += u.hp * u.t.dmg / u.t.cd;
    }
    return v;
  }

  void _enemyAct() {
    enemyThink -= kKkDt;
    if (enemyThink > 0) return;
    final ty = z.enemyDeck[enemyI % z.enemyDeck.length];
    if (energy[1] < kKkTypes[ty].cost) return;
    // en çok baskı gören şeride, yoksa tohumla sırayla
    var lane = (enemyI * 7 + z.seed) % kKkLanes;
    var bv = 0.0;
    for (var l = 0; l < kKkLanes; l++) {
      final v = _threat(0, l) - _threat(1, l);
      if (v > bv + 1) {
        bv = v;
        lane = l;
      }
    }
    energy[1] -= kKkTypes[ty].cost;
    units.add(KkUnit(ty, 1, lane, kKkLen, kKkTypes[ty].hp));
    enemyI++;
    enemyThink = 1.2;
  }

  void step() {
    if (over) return;
    energy[0] = math.min(10, energy[0] + regen * 0.5 * kKkDt);
    energy[1] = math.min(10, energy[1] + z.enemyRegen * 0.5 * kKkDt);
    _enemyAct();
    for (final u in units) {
      if (u.hp <= 0) continue;
      u.cd -= kKkDt;
      final dir = u.side == 0 ? 1.0 : -1.0;
      // en yakın düşman (aynı şerit, önde)
      KkUnit? foe;
      var fd = 1e9;
      for (final o in units) {
        if (o.side == u.side || o.lane != u.lane || o.hp <= 0) continue;
        final d = (o.pos - u.pos) * dir;
        if (d >= -1 && d < fd) {
          fd = d;
          foe = o;
        }
      }
      final wall = u.side == 0 ? kKkLen - u.pos : u.pos;
      if (foe != null && fd <= u.t.range) {
        if (u.cd <= 0) {
          foe.hp -= u.t.dmg;
          u.cd = u.t.cd;
          if (foe.hp <= 0 && foe.side == 1) routed++;
        }
      } else if (wall <= u.t.range) {
        if (u.cd <= 0) {
          castle[1 - u.side] -= u.t.dmg;
          u.cd = u.t.cd;
        }
      } else {
        u.pos += dir * u.t.speed * kKkDt;
      }
    }
    units.removeWhere((u) => u.hp <= 0);
    t += kKkDt;
  }

  /// Bot: en çok baskı gören şeride savunma, yoksa en zayıf şeride saldırı.
  void botAct() {
    var lane = -1;
    var bv = 0.0;
    for (var l = 0; l < kKkLanes; l++) {
      final v = _threat(1, l) - _threat(0, l);
      if (v > bv) {
        bv = v;
        lane = l;
      }
    }
    if (lane < 0) {
      if (energy[0] < 7) return;
      var weak = 0;
      var wv = 1e9;
      for (var l = 0; l < kKkLanes; l++) {
        final v = _threat(1, l);
        if (v < wv) {
          wv = v;
          weak = l;
        }
      }
      lane = weak;
    }
    // elindeki en güçlü karşılanabilir kart
    var best = -1;
    var bs = -1.0;
    for (var h = 0; h < hand.length; h++) {
      final ty = kKkTypes[hand[h]];
      if (ty.cost > energy[0]) continue;
      final s = ty.hp * ty.dmg / ty.cd;
      if (s > bs) {
        bs = s;
        best = h;
      }
    }
    if (best >= 0) deploy(best, lane);
  }
}

/// Botun sur oranı (0: kaybetti).
double kkBot(KkPuzzle z) {
  final s = KkSim(z);
  var think = 0.0;
  while (!s.over) {
    think -= kKkDt;
    if (think <= 0) {
      s.botAct();
      think = 0.5;
    }
    s.step();
  }
  return s.won ? math.max(0.01, s.castle[0] / s.castleMax[0]) : 0;
}

class KaleKind extends StratejiKind {
  @override
  String get id => 'kale';
  const KaleKind();

  @override
  SPuzzle? make(int d, SeededRandom r) {
    final deck = [for (var i = 0; i < 8; i++) r.nextInt(kKkTypes.length)];
    final z = KkPuzzle(r.nextInt(1 << 20), d, 0.75 + 0.05 * d, 50.0 + 6 * d, 120.0 + 6 * d, deck);
    return kkBot(z) >= 0.15 ? z : null;
  }

  @override
  bool check(SPuzzle p) => p is KkPuzzle && p.enemyDeck.isNotEmpty && kkBot(p) >= 0.15;

  @override
  Widget build(StratejiPlay play) => _KkView(play: play);

  @override
  List<Perk> get perks => const [
        Perk(3, Icons.bolt, 'kk_pEnergy', 2),
        Perk(8, Icons.castle, 'kk_pWall', 15),
        Perk(15, Icons.speed, 'kk_pRegen', 0),
        Perk(25, Icons.bolt, 'kk_pEnergy', 2),
        Perk(40, Icons.castle, 'kk_pWall', 15),
      ];

  @override
  List<GameStat> get stats => [
        ...super.stats,
        const GameStat('units_routed', 'Püskürtülen birlik', 'Units routed', scale: 100),
      ];
}

class _KkView extends StatefulWidget {
  final StratejiPlay play;
  const _KkView({required this.play});
  @override
  State<_KkView> createState() => _KkViewState();
}

class _KkViewState extends State<_KkView> with Clock, MetaLoader {
  late KkSim s;
  Timer? loop;
  int sel = 0;
  bool go = false;

  StratejiPlay get p => widget.play;
  KkPuzzle get z => p.puzzle as KkPuzzle;
  String get lang => p.lang;

  KkSim _fresh() => KkSim(z,
      startEnergy: 4 + (p.has(usta, 0) ? 2 : 0) + (p.has(usta, 3) ? 2 : 0),
      myCastle: 60.0 + (p.has(usta, 1) ? 15 : 0) + (p.has(usta, 4) ? 15 : 0),
      regen: p.has(usta, 2) ? 1.15 : 1.0);

  @override
  void initState() {
    super.initState();
    s = _fresh();
    loadMeta(p.gameId, () => s = _fresh());
  }

  @override
  void dispose() {
    loop?.cancel();
    super.dispose();
  }

  void _start() {
    if (go) return;
    started = true;
    startClock();
    setState(() => go = true);
    loop = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || ended || held) return;
      final c0 = s.castle[0];
      setState(s.step);
      if (s.castle[0] < c0) p.sfx(Sfx.error);
      if (s.over) _end();
    });
  }

  void _tap(Offset o) {
    if (ended) return;
    if (!go) _start();
    final lane = clampI((o.dx / (100 / kKkLanes)).floor(), 0, kKkLanes - 1);
    setState(() => p.sfx(s.deploy(sel, lane) ? Sfx.place : Sfx.error));
  }

  void _end() {
    if (ended) return;
    ended = true;
    loop?.cancel();
    final ratio = s.castle[0] / s.castleMax[0];
    if (s.won) {
      p.sfx(Sfx.win);
      later(400, () => p.win(score: s.routed * 20 + (ratio * 300).round() + z.d * 30, stars: ratio >= 0.6 ? 3 : (ratio >= 0.3 ? 2 : 1),
          seconds: seconds, moves: s.deployed, stats: {'units_routed': s.routed}));
    } else {
      p.sfx(Sfx.lose);
      later(500, () => p.lose(score: s.routed * 20, seconds: seconds, moves: s.deployed, stats: {'units_routed': s.routed}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final left = math.max(0, (z.duration - s.t).ceil());
    return SScreen(
      bar: SBar(
        lang: lang,
        left: '⚡ ${s.energy[0].floor()}/10',
        status: '${clock(left)} · 🏰 ${s.castle[0].ceil()} : ${math.max(0, s.castle[1].ceil())}',
      ),
      top: PerkStrip(lang: lang, perks: p.perks, usta: usta),
      board: TapCanvas(w: 100, h: 130, paint: _paint, onTap: _tap, semantics: st(lang, 'kk_title')),
      bottom: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          for (var h = 0; h < s.hand.length; h++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: SChip(
                  selected: sel == h,
                  onTap: () => setState(() => sel = h),
                  tooltip: st(lang, kKkTypes[s.hand[h]].key),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(kKkTypes[s.hand[h]].icon, size: 18),
                    Text('⚡${kKkTypes[s.hand[h]].cost}',
                        style: TextStyle(fontSize: 11, color: kKkTypes[s.hand[h]].cost > s.energy[0] ? const Color(0xFFFFB4A2) : null)),
                  ]),
                ),
              ),
            ),
        ]),
        if (!go) ...[
          const SizedBox(height: 6),
          StudioButton(onPressed: _start, icon: Icons.flag, label: st(lang, 'kk_start')),
        ],
      ]),
    );
  }

  void _paint(Canvas c) {
    const lw = 100 / kKkLanes;
    c.drawRect(const Rect.fromLTWH(0, 0, 100, 130), fill(const Color(0xFF5F7F4A)));
    for (var l = 0; l < kKkLanes; l++) {
      c.drawRect(Rect.fromLTWH(l * lw + 4, 12, lw - 8, 106), fill(const Color(0xFFB59A6E)));
    }
    // kaleler
    void wall(double y, Color col, double ratio) {
      c.drawRect(Rect.fromLTWH(4, y, 92, 9), fill(col));
      for (var i = 0; i < 12; i++) {
        c.drawRect(Rect.fromLTWH(5 + i * 7.7, y - 2.5, 4, 2.5), fill(col));
      }
      c.drawRect(Rect.fromLTWH(4, y + 3.5, 92 * clampD(ratio, 0, 1), 2), fill(const Color(0xFFFFE08A)));
    }

    wall(2, SColors.bad, s.castle[1] / s.castleMax[1]);
    wall(119, SColors.accent, s.castle[0] / s.castleMax[0]);
    for (final u in s.units) {
      final x = u.lane * lw + lw / 2 + (u.type - 2.5) * 1.2;
      final y = 118 - u.pos / kKkLen * 106;
      final col = u.side == 0 ? SColors.accent : SColors.bad;
      c.drawCircle(Offset(x, y), 3.4, fill(col));
      c.drawCircle(Offset(x, y), 3.4, stroke(Colors.white, 0.5));
      c.drawRect(Rect.fromLTWH(x - 3, y - 5.5, 6 * clampD(u.hp / u.t.hp, 0, 1), 0.9), fill(const Color(0xFF9BE38A)));
      drawLabel(c, '${u.type + 1}', Offset(x, y), 3.2, Colors.white);
    }
  }
}

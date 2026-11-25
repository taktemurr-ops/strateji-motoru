import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../texts.dart';
import '../versus.dart';

/// Altıgen Savaş: altıgen haritada sıra tabanlı ordu savaşı. Rakip ordusunu
/// dağıt ya da sancağını ele geçir; kendi sancağını koru.
const int kHR = 4;
const List<(int, int)> kHDirs = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)];

/// Arazi: 0 ova, 1 orman, 2 tepe, 3 su, 4 köy.
const List<String> kTerrainKeys = ['tPlain', 'tForest', 'tHill', 'tWater', 'tVillage'];

class HType {
  final String key;
  final int hp, atk, def, mv, rng;
  const HType(this.key, this.hp, this.atk, this.def, this.mv, this.rng);
}

const List<HType> kHTypes = [
  HType('u_spear', 10, 4, 2, 2, 1),
  HType('u_archer', 7, 4, 1, 2, 2),
  HType('u_rider', 9, 5, 1, 3, 1),
  HType('u_shield', 12, 3, 3, 1, 1),
  HType('u_catapult', 6, 6, 0, 1, 3),
];

int hexDist((int, int) a, (int, int) b) => ((a.$1 - b.$1).abs() + (a.$2 - b.$2).abs() + (a.$1 + a.$2 - b.$1 - b.$2).abs()) ~/ 2;

final List<(int, int)> kHCells = [
  for (var q = -kHR; q <= kHR; q++)
    for (var r = -kHR; r <= kHR; r++)
      if ((q + r).abs() <= kHR) (q, r),
];

class HUnit {
  final int side, type;
  (int, int) pos;
  int hp, maxHp;
  bool moved = false, done = false;
  HUnit(this.side, this.type, this.pos, this.hp) : maxHp = hp;
  HType get t => kHTypes[type];
}

class HPuzzle extends SPuzzle {
  final int seed, d;
  const HPuzzle(this.seed, this.d);
}

class HSim {
  final int seed, d;
  final Map<(int, int), int> terrain = {};
  final (int, int) pf = (0, kHR), ef = (0, -kHR);
  final List<HUnit> units = [];
  int turn = 1;
  bool won = false, lost = false;
  int villageHeal;
  int kills = 0, losses = 0;

  HSim(this.seed, this.d, {int extraHp = 0, List<int> extraUnits = const [], this.villageHeal = 2}) {
    final r = SeededRandom(mixSeed([seed, 6601]));
    while (true) {
      terrain.clear();
      for (final c in kHCells) {
        final x = r.nextDouble();
        terrain[c] = x < 0.07 ? 3 : (x < 0.22 ? 1 : (x < 0.32 ? 2 : 0));
      }
      terrain[pf] = 0;
      terrain[ef] = 0;
      final land = kHCells.where((c) => terrain[c] != 3).length;
      final seen = {pf};
      final stack = [pf];
      while (stack.isNotEmpty) {
        final c = stack.removeLast();
        for (final dd in kHDirs) {
          final n = (c.$1 + dd.$1, c.$2 + dd.$2);
          if (terrain.containsKey(n) && terrain[n] != 3 && !seen.contains(n)) {
            seen.add(n);
            stack.add(n);
          }
        }
      }
      if (seen.length == land) break;
    }
    final mid = [for (final c in kHCells) if (terrain[c] == 0 && c.$2.abs() <= 1) c];
    r.shuffle(mid);
    for (final c in mid.take(3)) {
      terrain[c] = 4;
    }
    final pl = [for (final c in kHCells) if (terrain[c] != 3 && c.$2 >= 3 && c != pf) c];
    r.shuffle(pl);
    final en = [for (final c in kHCells) if (terrain[c] != 3 && c.$2 <= -2 && c != ef) c];
    r.shuffle(en);
    final ptypes = [0, 0, 1, 2, 1, 3].take(4 + d ~/ 4).toList()..addAll(extraUnits);
    final ne = 3 + (d * 2) ~/ 5;
    final et = <int>[0, 1, if (d >= 2) 2, if (d >= 4) 3, if (d >= 6) 4];
    for (var i = 0; i < ptypes.length && i < pl.length; i++) {
      units.add(HUnit(0, ptypes[i], pl[i], kHTypes[ptypes[i]].hp + extraHp));
    }
    for (var i = 0; i < ne && i < en.length; i++) {
      final t = r.pick(et);
      units.add(HUnit(1, t, en[i], kHTypes[t].hp));
    }
  }

  int tdef((int, int) c) => (terrain[c] == 1 || terrain[c] == 2) ? 1 : 0;

  int dmg(HUnit a, HUnit b) => math.max<int>(1, a.t.atk * 2 - (b.t.def + tdef(b.pos)));

  int rngAt(HUnit u, (int, int) c) => u.t.rng + (u.t.rng >= 2 && terrain[c] == 2 ? 1 : 0);

  HUnit? unitAt((int, int) c) {
    for (final u in units) {
      if (u.pos == c) return u;
    }
    return null;
  }

  /// Birimin bu tur gidebileceği hücreler (kendi yeri dahil).
  List<(int, int)> reach(HUnit u) {
    final occ = {for (final x in units) if (!identical(x, u)) x.pos};
    final best = <(int, int), int>{u.pos: 0};
    final open = [u.pos];
    while (open.isNotEmpty) {
      open.sort((a, b) => best[b]!.compareTo(best[a]!));
      final c = open.removeLast();
      final c0 = best[c]!;
      for (final dd in kHDirs) {
        final n = (c.$1 + dd.$1, c.$2 + dd.$2);
        final tt = terrain[n];
        if (tt == null || tt == 3 || occ.contains(n)) continue;
        final cost = c0 + (tt == 1 ? 2 : 1);
        if (cost <= u.t.mv && cost < (best[n] ?? 99)) {
          best[n] = cost;
          open.add(n);
        }
      }
    }
    return best.keys.toList()..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  }

  /// [a] birimi [b]'ye [from] hücresinden saldırırsa alacağı karşılık hasarı.
  int retaliation(HUnit a, HUnit b, (int, int) from, int dealt) {
    if (dealt >= b.hp) return 0;
    if (a.t.rng != 1 || hexDist(from, b.pos) != 1 || b.t.rng != 1) return 0;
    return math.max<int>(0, b.t.atk - (a.t.def + tdef(from)));
  }

  void attack(HUnit a, HUnit b) {
    final dd = dmg(a, b);
    final ret = retaliation(a, b, a.pos, dd);
    b.hp -= dd;
    if (b.hp <= 0) {
      units.remove(b);
      if (b.side == 1) {
        kills++;
      } else {
        losses++;
      }
    } else {
      a.hp -= ret;
      if (a.hp <= 0) {
        units.remove(a);
        if (a.side == 1) {
          kills++;
        } else {
          losses++;
        }
      }
    }
    a.done = true;
    a.moved = true;
  }

  /// Ortak yapay zekâ: en iyi saldırıyı yap, yoksa hedefe yaklaş.
  /// Dönüş: (gidilecek hücre, saldırılacak birim).
  ((int, int), HUnit?) plan(HUnit u, {bool rush = false, (int, int)? goal}) {
    final foes = [for (final x in units) if (x.side != u.side) x];
    if (foes.isEmpty) return (u.pos, null);
    double? bv;
    (int, int)? bh;
    HUnit? bf;
    final rs = u.moved ? [u.pos] : reach(u);
    if (!rush) {
      for (final h in rs) {
        for (final f in foes) {
          if (hexDist(h, f.pos) > rngAt(u, h)) continue;
          final save = u.pos;
          u.pos = h;
          final dd = dmg(u, f);
          final ret = retaliation(u, f, h, dd);
          u.pos = save;
          final kill = dd >= f.hp;
          final v = dd + (kill ? 50 : 0) - ret * 0.7 + tdef(h) * 0.5 + f.t.atk * 0.3;
          if (bv == null || v > bv) {
            bv = v;
            bh = h;
            bf = f;
          }
        }
      }
    }
    if (bh != null) return (bh, bf);
    var tgt = goal ?? foes.first.pos;
    if (!rush || goal == null) {
      var bd = 1 << 20;
      for (final f in foes) {
        final dd = hexDist(u.pos, f.pos);
        if (dd < bd) {
          bd = dd;
          tgt = f.pos;
        }
      }
    }
    var best = u.pos;
    var key = (1 << 20, 0);
    for (final c in rs) {
      final k = (hexDist(c, tgt), -tdef(c));
      if (k.$1 < key.$1 || (k.$1 == key.$1 && k.$2 < key.$2)) {
        key = k;
        best = c;
      }
    }
    return (best, null);
  }

  void moveTo(HUnit u, (int, int) c) {
    u.pos = c;
    u.moved = true;
    if (u.side == 0 && c == ef) won = true;
  }

  bool get over => won || lost;

  void _heal(int side) {
    for (final u in units) {
      if (u.side == side && terrain[u.pos] == 4) u.hp = math.min<int>(u.maxHp, u.hp + villageHeal);
    }
  }

  /// Oyuncu turunu bitirir; rakip oynar.
  void endTurn() {
    if (over) return;
    if (!units.any((x) => x.side == 1)) {
      won = true;
      return;
    }
    _heal(0);
    final es = [for (final x in units) if (x.side == 1) x];
    final rusher = d >= 5 && es.isNotEmpty ? es.first : null;
    for (final u in es) {
      if (!units.contains(u)) continue;
      u.moved = false;
      final rush = identical(u, rusher) && turn >= 3;
      final (h, f) = plan(u, rush: rush, goal: rush ? pf : null);
      u.pos = h;
      u.moved = true;
      if (f != null) attack(u, f);
    }
    if (units.any((x) => x.side == 1 && x.pos == pf)) {
      lost = true;
      return;
    }
    if (!units.any((x) => x.side == 0)) {
      lost = true;
      return;
    }
    _heal(1);
    turn++;
    if (turn > 14) {
      lost = true;
      return;
    }
    for (final u in units) {
      u.moved = false;
      u.done = false;
    }
  }

  void checkWin() {
    if (!units.any((x) => x.side == 1)) won = true;
  }

  /// Yapay zekâ oyuncunun bir birimlik hamlesi; hamle kalmadıysa false.
  bool botStep() {
    for (final u in units) {
      if (u.side != 0 || u.done) continue;
      if (!u.moved && reach(u).contains(ef)) {
        moveTo(u, ef);
        return true;
      }
      final (h, f) = plan(u);
      moveTo(u, h);
      if (f != null && units.contains(f)) {
        attack(u, f);
      }
      u.done = true;
      checkWin();
      return true;
    }
    return false;
  }
}

class AltigenKind extends StratejiKind {
  @override
  bool get duel => true;

  @override
  String get id => 'altigen';
  const AltigenKind();

  @override
  SPuzzle? make(int d, SeededRandom r) => HPuzzle(r.nextUint32(), d);

  @override
  bool check(SPuzzle p) {
    if (p is! HPuzzle) return false;
    final s = HSim(p.seed, p.d);
    var guard = 0;
    while (!s.over && guard++ < 400) {
      if (!s.botStep()) s.endTurn();
    }
    return s.won;
  }

  @override
  List<Perk> get perks => const [
        Perk(3, Icons.favorite, 'pUnitHp', 2),
        Perk(8, Icons.person_add, 'u_archer', 1),
        Perk(15, Icons.home, 'pVillage', 1),
        Perk(25, Icons.person_add, 'u_shield', 1),
        Perk(40, Icons.person_add, 'u_catapult', 1),
      ];

  @override
  List<GameStat> get stats => const [
        GameStat('runs_won', 'Kazanılan savaş', 'Battles won', scale: 10),
        GameStat('flawless', 'Kayıpsız zafer', 'Flawless victories', scale: 10),
        GameStat('units_routed', 'Dağıtılan birlik', 'Units routed', scale: 30),
      ];

  @override
  Widget build(StratejiPlay play) => play.ctx.match != null || play.ctx.passAndPlay ? HDuelView(play: play) : _HView(play: play);
}

class _HView extends StatefulWidget {
  final StratejiPlay play;
  const _HView({required this.play});
  @override
  State<_HView> createState() => _HViewState();
}

const List<Color> _kTerrainCols = [Color(0xFFD8CFA0), Color(0xFF7FA36B), Color(0xFFBFA27A), Color(0xFF7FB2D0), Color(0xFFE3C58E)];

const double _hs = 10; // altıgen yarıçapı (mantıksal birim)
final double _sq3 = math.sqrt(3);

class _HViewState extends State<_HView> with Clock, MetaLoader {
  late HSim s;
  HUnit? sel;
  int hints = 0;
  ((int, int), HUnit?)? hintPlan;
  String note = '';
  bool busy = false;

  StratejiPlay get p => widget.play;
  HPuzzle get z => p.puzzle as HPuzzle;

  HSim _fresh() => HSim(
        z.seed,
        z.d,
        extraHp: p.has(usta, 0) ? 2 : 0,
        extraUnits: [if (p.has(usta, 1)) 1, if (p.has(usta, 3)) 3, if (p.has(usta, 4)) 4],
        villageHeal: p.has(usta, 2) ? 3 : 2,
      );

  @override
  void initState() {
    super.initState();
    s = _fresh();
    startClock();
    loadMeta(p.gameId, () => s = _fresh());
  }

  static const double _w = 2 * kHR * 17.4 + 20, _h = (2 * kHR) * 15.0 + 24;

  Offset _px((int, int) c) => Offset(_w / 2 + _hs * _sq3 * (c.$1 + c.$2 / 2), _h / 2 + _hs * 1.5 * c.$2);

  (int, int)? _cellAt(Offset o) {
    (int, int)? best;
    var bd = 1e9;
    for (final c in kHCells) {
      final dd = (_px(c) - o).distance;
      if (dd < bd) {
        bd = dd;
        best = c;
      }
    }
    return bd <= _hs ? best : null;
  }

  void _finishCheck() {
    s.checkWin();
    if (s.won) {
      ended = true;
      p.sfx(Sfx.win);
      final alive = s.units.where((u) => u.side == 0).toList();
      final hpNow = alive.fold<int>(0, (a, u) => a + u.hp);
      final hpMax = alive.fold<int>(0, (a, u) => a + u.maxHp) + s.losses * 10;
      final stars = starsByHealth(hpNow, hpMax) - (hints > 0 ? 1 : 0);
      later(500, () => p.win(score: s.kills * 40 + (15 - s.turn) * 20 + p.d * 30, stars: stars, seconds: seconds, moves: s.turn, hints: hints, stats: {'units_routed': s.kills}));
    } else if (s.lost) {
      ended = true;
      later(600, () => p.lose(score: s.kills * 40, seconds: seconds, moves: s.turn, stats: {'units_routed': s.kills}));
    }
  }

  void _tap(Offset o) {
    if (ended || busy) return;
    final c = _cellAt(o);
    if (c == null) return;
    final u = s.unitAt(c);
    final cur = sel;
    if (u != null && u.side == 0) {
      setState(() {
        sel = u.done ? null : u;
        note = '${st(p.lang, u.t.key)} · ${st(p.lang, 'hp')} ${u.hp}/${u.maxHp} · ${st(p.lang, 'atk')} ${u.t.atk}';
      });
      p.sfx(Sfx.tap);
      return;
    }
    if (cur != null && u != null && u.side == 1) {
      if (hexDist(cur.pos, u.pos) <= s.rngAt(cur, cur.pos)) {
        started = true;
        s.attack(cur, u);
        p.sfx(s.units.contains(u) ? Sfx.clear : Sfx.combo);
        setState(() => sel = null);
        _finishCheck();
        return;
      }
      setState(() => note = '${st(p.lang, u.t.key)} · ${st(p.lang, 'hp')} ${u.hp}/${u.maxHp}');
      return;
    }
    if (u != null && u.side == 1) {
      setState(() => note = '${st(p.lang, u.t.key)} · ${st(p.lang, 'hp')} ${u.hp}/${u.maxHp} · ${st(p.lang, 'atk')} ${u.t.atk}');
      return;
    }
    if (cur != null && !cur.moved && s.reach(cur).contains(c)) {
      started = true;
      s.moveTo(cur, c);
      p.sfx(Sfx.place);
      final hasTarget = s.units.any((f) => f.side == 1 && hexDist(cur.pos, f.pos) <= s.rngAt(cur, cur.pos));
      if (!hasTarget) cur.done = true;
      setState(() {
        hintPlan = null;
        if (cur.done) sel = null;
      });
      _finishCheck();
      return;
    }
    setState(() => note = st(p.lang, kTerrainKeys[s.terrain[c]!]));
  }

  void _endTurn() {
    if (ended || busy) return;
    started = true;
    setState(() {
      busy = true;
      sel = null;
      hintPlan = null;
      note = st(p.lang, 'enemyTurn');
    });
    later(350, () {
      final before = s.losses;
      s.endTurn();
      p.sfx(s.losses > before ? Sfx.error : Sfx.place);
      setState(() {
        busy = false;
        note = '';
      });
      _finishCheck();
    });
  }

  Future<void> _hint() async {
    if (ended || busy) return;
    final ok = await p.ctx.requestHint();
    if (!ok || !mounted) return;
    for (final u in s.units) {
      if (u.side == 0 && !u.done) {
        setState(() {
          hints++;
          sel = u;
          hintPlan = s.reach(u).contains(s.ef) && !u.moved ? (s.ef, null) : s.plan(u);
        });
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = p.lang;
    final status = note.isNotEmpty ? note : '${st(lang, 'turn')} ${s.turn}/14 · ${st(lang, 'units')} ${s.units.where((u) => u.side == 0).length}:${s.units.where((u) => u.side == 1).length}';
    return SScreen(
      bar: SBar(lang: lang, left: '⚑ ${s.turn}', status: status, onHint: ended ? null : _hint, extra: [
        IconButton(
          tooltip: st(lang, 'hotseat'),
          onPressed: () => openHotseat(context, () => HDuelView(play: p, sandbox: true)),
          icon: const Icon(Icons.people_alt),
        ),
      ]),
      top: PerkStrip(lang: lang, perks: p.perks, usta: usta),
      board: TapCanvas(w: _w, h: _h, paint: _paint, onTap: _tap, semantics: st(lang, 'hTitle')),
      bottom: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(onPressed: ended || busy ? null : _endTurn, icon: const Icon(Icons.skip_next), label: Text(st(lang, 'endTurn'))),
      ),
    );
  }

  void _paint(Canvas c) {
    final cur = sel;
    final rs = cur != null && !cur.moved ? s.reach(cur).toSet() : <(int, int)>{};
    for (final cell in kHCells) {
      final o = _px(cell);
      final t = s.terrain[cell]!;
      c.drawPath(_hex(o, _hs - 0.4), fill(_kTerrainCols[t]));
      _terrainGlyph(c, o, t);
      if (rs.contains(cell)) c.drawPath(_hex(o, _hs - 1.4), stroke(const Color(0xCCFFFFFF), 1.0));
      c.drawPath(_hex(o, _hs - 0.4), stroke(const Color(0x22000000), 0.4));
    }
    _flag(c, _px(s.pf), SColors.accent);
    _flag(c, _px(s.ef), SColors.bad);
    final hp = hintPlan;
    if (hp != null) {
      c.drawPath(_hex(_px(hp.$1), _hs - 1.6), stroke(SColors.gold, 1.6));
      final f = hp.$2;
      if (f != null) c.drawCircle(_px(f.pos), _hs * 0.75, stroke(SColors.gold, 1.4));
    }
    for (final u in s.units) {
      final o = _px(u.pos);
      final col = u.side == 0 ? SColors.accent : SColors.bad;
      if (cur != null && u.side == 1 && hexDist(cur.pos, u.pos) <= s.rngAt(cur, cur.pos)) {
        c.drawCircle(o, _hs * 0.82, stroke(SColors.gold, 1.2));
      }
      c.drawCircle(o, _hs * 0.58, fill(u.done && u.side == 0 ? Color.lerp(col, Colors.grey, 0.55)! : col));
      if (identical(u, cur)) c.drawCircle(o, _hs * 0.66, stroke(Colors.white, 1.2));
      _glyph(c, o, u.type);
      final w = _hs * 1.1;
      c.drawRect(Rect.fromLTWH(o.dx - w / 2, o.dy + _hs * 0.62, w, 1.4), fill(const Color(0x55000000)));
      c.drawRect(Rect.fromLTWH(o.dx - w / 2, o.dy + _hs * 0.62, w * clampD(u.hp / u.maxHp, 0, 1), 1.4), fill(SColors.good));
    }
  }
}

Path _hex(Offset o, double r) {
  final path = Path();
  for (var i = 0; i < 6; i++) {
    final a = math.pi / 180 * (60 * i - 30);
    final pt = o + Offset(math.cos(a), math.sin(a)) * r;
    if (i == 0) {
      path.moveTo(pt.dx, pt.dy);
    } else {
      path.lineTo(pt.dx, pt.dy);
    }
  }
  return path..close();
}

void _flag(Canvas c, Offset o, Color col) {
  c.drawLine(o + const Offset(-3, 5), o + const Offset(-3, -6), stroke(SColors.ink, 0.8));
  final path = Path()
    ..moveTo(o.dx - 3, o.dy - 6)
    ..lineTo(o.dx + 4, o.dy - 4)
    ..lineTo(o.dx - 3, o.dy - 2)
    ..close();
  c.drawPath(path, fill(col));
}

void _glyph(Canvas c, Offset o, int type) {
  final w = stroke(Colors.white, 0.9);
  switch (type) {
    case 0:
      c.drawLine(o + const Offset(-3, 3), o + const Offset(3, -3), w);
      c.drawLine(o + const Offset(3, -3), o + const Offset(1.2, -2.6), w);
      c.drawLine(o + const Offset(3, -3), o + const Offset(2.6, -1.2), w);
    case 1:
      c.drawArc(Rect.fromCenter(center: o + const Offset(-1, 0), width: 6, height: 8), -math.pi / 2, math.pi, false, w);
      c.drawLine(o + const Offset(-1, -4), o + const Offset(-1, 4), stroke(Colors.white, 0.5));
    case 2:
      c.drawLine(o + const Offset(-3, 3), o + const Offset(0, -3), w);
      c.drawLine(o + const Offset(0, -3), o + const Offset(3, -1), w);
      c.drawLine(o + const Offset(-1.5, 0), o + const Offset(2.5, 3), w);
    case 3:
      final path = Path()
        ..moveTo(o.dx - 3, o.dy - 3)
        ..lineTo(o.dx + 3, o.dy - 3)
        ..lineTo(o.dx + 3, o.dy)
        ..quadraticBezierTo(o.dx + 2, o.dy + 3, o.dx, o.dy + 3.6)
        ..quadraticBezierTo(o.dx - 2, o.dy + 3, o.dx - 3, o.dy)
        ..close();
      c.drawPath(path, w);
    default:
      c.drawCircle(o + const Offset(-1.5, 2), 1.4, w);
      c.drawCircle(o + const Offset(2, 2), 1.4, w);
      c.drawLine(o + const Offset(-2, 0), o + const Offset(3, -3.5), w);
  }
}

void _terrainGlyph(Canvas c, Offset o, int t) {
  if (t == 1) {
    for (final d in const [Offset(-3, 1), Offset(2, -2), Offset(3, 3)]) {
      final path = Path()
        ..moveTo(o.dx + d.dx, o.dy + d.dy - 3)
        ..lineTo(o.dx + d.dx - 2, o.dy + d.dy + 1.5)
        ..lineTo(o.dx + d.dx + 2, o.dy + d.dy + 1.5)
        ..close();
      c.drawPath(path, fill(const Color(0xFF4E7A45)));
    }
  } else if (t == 2) {
    final path = Path()
      ..moveTo(o.dx - 5, o.dy + 3)
      ..lineTo(o.dx - 1, o.dy - 3)
      ..lineTo(o.dx + 1.5, o.dy)
      ..lineTo(o.dx + 3, o.dy - 1.5)
      ..lineTo(o.dx + 6, o.dy + 3)
      ..close();
    c.drawPath(path, fill(const Color(0xFF9A8060)));
  } else if (t == 3) {
    c.drawLine(o + const Offset(-4, -1), o + const Offset(4, -1), stroke(const Color(0xAAFFFFFF), 0.6));
    c.drawLine(o + const Offset(-3, 2), o + const Offset(3, 2), stroke(const Color(0xAAFFFFFF), 0.6));
  } else if (t == 4) {
    c.drawRect(Rect.fromCenter(center: o + const Offset(0, 1.5), width: 6, height: 4), fill(const Color(0xFFB0563B)));
    final roof = Path()
      ..moveTo(o.dx - 4, o.dy - 0.5)
      ..lineTo(o.dx, o.dy - 4)
      ..lineTo(o.dx + 4, o.dy - 0.5)
      ..close();
    c.drawPath(roof, fill(const Color(0xFF7A3B28)));
  }
}

// ------------------------------------------------------------ iki kişilik düello

(int, int) hMirror((int, int) c) => (-c.$1, -c.$2);

/// Altıgen Savaş düellosu: harita merkeze göre nokta simetrik, iki ordu
/// birbirinin aynası. Sıra mavide başlar; bir taraf turunda her birimiyle bir
/// kez yürüyüp bir kez saldırabilir, sonra turu bitirir.
///
/// Hamleler: "m<birim>,<q>,<r>" yürü, "a<birim>,<hedef>" saldır, "e" turu bitir.
/// Kazanma: rakip sancağına yürümek ya da bütün rakip birlikleri dağıtmak;
/// [maxRounds] turda bitmezse toplam canı çok olan kazanır.
class HDuel implements DuelGame {
  final int seed;
  final Map<(int, int), int> terrain = {};
  static const (int, int) flag0 = (0, kHR), flag1 = (0, -kHR);
  static const int maxRounds = 20;
  static const List<int> armyTypes = [0, 0, 1, 2, 3, 4];

  /// Birimler: önce mavi ordu, sonra aynı sırada kırmızı ordu. Dağılan birim
  /// listede kalır (canı 0), kimlikler değişmez.
  final List<HUnit> army = [];
  int side = 0;
  int round = 1;
  int _winner = -2;
  int _applied = 0;

  HDuel(this.seed) {
    final r = SeededRandom(mixSeed([seed, 6603]));
    while (true) {
      terrain.clear();
      for (final c in kHCells) {
        if (terrain.containsKey(c)) continue;
        final x = r.nextDouble();
        final t = x < 0.07 ? 3 : (x < 0.22 ? 1 : (x < 0.32 ? 2 : 0));
        terrain[c] = t;
        terrain[hMirror(c)] = t;
      }
      terrain[flag0] = 0;
      terrain[flag1] = 0;
      terrain[(0, 0)] = 4;
      final land = kHCells.where((c) => terrain[c] != 3).length;
      final seen = {flag0};
      final stack = [flag0];
      while (stack.isNotEmpty) {
        final c = stack.removeLast();
        for (final dd in kHDirs) {
          final n = (c.$1 + dd.$1, c.$2 + dd.$2);
          if (terrain.containsKey(n) && terrain[n] != 3 && !seen.contains(n)) {
            seen.add(n);
            stack.add(n);
          }
        }
      }
      if (seen.length == land) break;
    }
    final vil = [for (final c in kHCells) if (terrain[c] == 0 && c.$2.abs() <= 1 && (c.$2 > 0 || (c.$2 == 0 && c.$1 > 0))) c];
    r.shuffle(vil);
    if (vil.isNotEmpty) {
      terrain[vil.first] = 4;
      terrain[hMirror(vil.first)] = 4;
    }
    final spots = [for (final c in kHCells) if (terrain[c] != 3 && c.$2 >= 3 && c != flag0) c];
    r.shuffle(spots);
    final n = math.min<int>(armyTypes.length, spots.length);
    for (var i = 0; i < n; i++) {
      army.add(HUnit(0, armyTypes[i], spots[i], kHTypes[armyTypes[i]].hp));
    }
    for (var i = 0; i < n; i++) {
      army.add(HUnit(1, armyTypes[i], hMirror(spots[i]), kHTypes[armyTypes[i]].hp));
    }
  }

  @override
  int get turnSeat => side;

  @override
  int get turnKey => round * 2 + side;

  @override
  bool get over => _winner != -2;

  @override
  int get winner => _winner;

  @override
  int get applied => _applied;

  (int, int) flagOf(int s) => s == 0 ? flag0 : flag1;

  int idOf(HUnit u) => army.indexOf(u);

  Iterable<HUnit> get living => army.where((u) => u.hp > 0);

  int hpOf(int s) => living.where((u) => u.side == s).fold<int>(0, (a, u) => a + u.hp);

  HUnit? unitAt((int, int) c) {
    for (final u in army) {
      if (u.hp > 0 && u.pos == c) return u;
    }
    return null;
  }

  int tdef((int, int) c) => (terrain[c] == 1 || terrain[c] == 2) ? 1 : 0;

  int dmg(HUnit a, HUnit b) => math.max<int>(1, a.t.atk * 2 - (b.t.def + tdef(b.pos)));

  int rngAt(HUnit u, (int, int) c) => u.t.rng + (u.t.rng >= 2 && terrain[c] == 2 ? 1 : 0);

  int retaliation(HUnit a, HUnit b, (int, int) from, int dealt) {
    if (dealt >= b.hp) return 0;
    if (a.t.rng != 1 || hexDist(from, b.pos) != 1 || b.t.rng != 1) return 0;
    return math.max<int>(0, b.t.atk - (a.t.def + tdef(from)));
  }

  /// Birimin bu tur gidebileceği hücreler (kendi yeri dahil, sıralı).
  List<(int, int)> reach(HUnit u) {
    final occ = {for (final x in army) if (x.hp > 0 && !identical(x, u)) x.pos};
    final best = <(int, int), int>{u.pos: 0};
    final open = [u.pos];
    while (open.isNotEmpty) {
      open.sort((a, b) => best[b]!.compareTo(best[a]!));
      final c = open.removeLast();
      final c0 = best[c]!;
      for (final dd in kHDirs) {
        final n = (c.$1 + dd.$1, c.$2 + dd.$2);
        final tt = terrain[n];
        if (tt == null || tt == 3 || occ.contains(n)) continue;
        final cost = c0 + (tt == 1 ? 2 : 1);
        if (cost <= u.t.mv && cost < (best[n] ?? 99)) {
          best[n] = cost;
          open.add(n);
        }
      }
    }
    return best.keys.toList()..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  }

  /// [u] bulunduğu yerden saldırabileceği rakipler.
  List<HUnit> targets(HUnit u) => [for (final f in army) if (f.hp > 0 && f.side != u.side && hexDist(u.pos, f.pos) <= rngAt(u, u.pos)) f];

  HUnit? _own(int id) => id >= 0 && id < army.length && army[id].hp > 0 && army[id].side == side ? army[id] : null;

  static List<int>? _ints(String s, int count) {
    final p = s.split(',');
    if (p.length != count) return null;
    final out = <int>[];
    for (final x in p) {
      final v = int.tryParse(x);
      if (v == null) return null;
      out.add(v);
    }
    return out;
  }

  @override
  bool apply(int seat, String mv) {
    if (over || seat != side || mv.isEmpty) return false;
    final ok = switch (mv[0]) {
      'm' => _move(mv.substring(1)),
      'a' => _attack(mv.substring(1)),
      'e' => mv == 'e' && _end(),
      _ => false,
    };
    if (ok) _applied++;
    return ok;
  }

  bool _move(String s) {
    final a = _ints(s, 3);
    if (a == null) return false;
    final u = _own(a[0]);
    if (u == null || u.moved || u.done) return false;
    final c = (a[1], a[2]);
    if (c == u.pos || !reach(u).contains(c)) return false;
    u.pos = c;
    u.moved = true;
    if (c == flagOf(1 - side)) _winner = side;
    return true;
  }

  bool _attack(String s) {
    final a = _ints(s, 2);
    if (a == null) return false;
    final u = _own(a[0]);
    if (u == null || u.done) return false;
    final tid = a[1];
    if (tid < 0 || tid >= army.length) return false;
    final t = army[tid];
    if (t.hp <= 0 || t.side == side || hexDist(u.pos, t.pos) > rngAt(u, u.pos)) return false;
    final dd = dmg(u, t);
    final ret = retaliation(u, t, u.pos, dd);
    t.hp = math.max<int>(0, t.hp - dd);
    if (t.hp > 0) u.hp = math.max<int>(0, u.hp - ret);
    u.moved = true;
    u.done = true;
    _checkArmies();
    return true;
  }

  void _checkArmies() {
    final a0 = living.any((u) => u.side == 0), a1 = living.any((u) => u.side == 1);
    if (!a0 && !a1) {
      _winner = -1;
    } else if (!a1) {
      _winner = 0;
    } else if (!a0) {
      _winner = 1;
    }
  }

  bool _end() {
    for (final u in army) {
      if (u.hp > 0 && u.side == side && terrain[u.pos] == 4) u.hp = math.min<int>(u.maxHp, u.hp + 2);
      u.moved = false;
      u.done = false;
    }
    side = 1 - side;
    if (side == 0) {
      round++;
      if (round > maxRounds) {
        final h0 = hpOf(0), h1 = hpOf(1);
        _winner = h0 == h1 ? -1 : (h0 > h1 ? 0 : 1);
      }
    }
    return true;
  }

  @override
  String timeoutMove() => 'e';

  /// Bilgisayar: sancağa ulaşabilen yürür; en iyi saldırıyı yapar; yoksa en
  /// yakın tehdide (sancağına yaklaşan) ya da en yakın rakibe yaklaşır.
  @override
  String botMove() {
    if (over) return 'e';
    final goal = flagOf(1 - side), home = flagOf(side);
    final foes = [for (final f in army) if (f.hp > 0 && f.side != side) f];
    for (var id = 0; id < army.length; id++) {
      final u = army[id];
      if (u.hp <= 0 || u.side != side || u.done) continue;
      final rs = u.moved ? [u.pos] : reach(u);
      if (!u.moved && rs.contains(goal)) return 'm$id,${goal.$1},${goal.$2}';
      double? bv;
      (int, int)? bh;
      HUnit? bf;
      for (final h in rs) {
        for (final f in foes) {
          if (hexDist(h, f.pos) > rngAt(u, h)) continue;
          final save = u.pos;
          u.pos = h;
          final dd = dmg(u, f);
          final ret = retaliation(u, f, h, dd);
          u.pos = save;
          final kill = dd >= f.hp;
          final v = dd + (kill ? 50 : 0) - ret * 0.7 + tdef(h) * 0.5 + f.t.atk * 0.3 + (hexDist(f.pos, home) <= 2 ? 20 : 0);
          if (bv == null || v > bv) {
            bv = v;
            bh = h;
            bf = f;
          }
        }
      }
      final th = bh, tf = bf;
      if (th != null && tf != null) return th == u.pos ? 'a$id,${idOf(tf)}' : 'm$id,${th.$1},${th.$2}';
      if (u.moved || foes.isEmpty) continue;
      var tgt = goal;
      var bd = 1 << 20;
      for (final f in foes) {
        final dh = hexDist(f.pos, home);
        final dd = dh <= 3 ? dh : hexDist(u.pos, f.pos) + 4;
        if (dd < bd) {
          bd = dd;
          tgt = f.pos;
        }
      }
      if (u.type == 2) tgt = goal;
      var best = u.pos;
      var key = (hexDist(u.pos, tgt), -tdef(u.pos));
      for (final c in rs) {
        final k = (hexDist(c, tgt), -tdef(c));
        if (k.$1 < key.$1 || (k.$1 == key.$1 && k.$2 < key.$2)) {
          key = k;
          best = c;
        }
      }
      if (best != u.pos) return 'm$id,${best.$1},${best.$2}';
    }
    return 'e';
  }

  @override
  String get hash {
    final b = StringBuffer('$side/$round/$_winner/');
    for (final u in army) {
      b.write('${u.hp},${u.pos.$1},${u.pos.$2},${u.moved ? 1 : 0}${u.done ? 1 : 0};');
    }
    return b.toString();
  }
}

const double _kHW = 2 * kHR * 17.4 + 20, _kHH = (2 * kHR) * 15.0 + 24;

/// Düello ekranı: çevrimiçi (rakip ya da bilgisayar) ve aynı cihazda iki kişi.
class HDuelView extends StatefulWidget {
  final StratejiPlay play;

  /// Sefer ekranından açılan, sonucu kaydedilmeyen aynı cihaz maçı.
  final bool sandbox;
  const HDuelView({super.key, required this.play, this.sandbox = false});
  @override
  State<HDuelView> createState() => _HDuelViewState();
}

class _HDuelViewState extends State<HDuelView> with Clock, DuelHost {
  HUnit? sel;
  String note = '';
  bool shown = false;
  bool sentResult = false;

  StratejiPlay get p => widget.play;
  HDuel get g => game as HDuel;

  @override
  int get turnSeconds => 60;

  @override
  void initState() {
    super.initState();
    final m = p.ctx.match;
    final seed = widget.sandbox ? mixSeed([p.seed, DateTime.now().millisecondsSinceEpoch]) : (m?.seed ?? p.seed);
    startClock();
    initDuel(HDuel(seed), widget.sandbox ? null : p.ctx);
  }

  @override
  void onDuelChanged() {
    final s = sel;
    if (s != null && (s.hp <= 0 || s.done || s.side != g.side || !myTurn)) sel = null;
  }

  @override
  void onDuelOver() {
    ended = true;
    p.sfx(localWon ? Sfx.win : Sfx.error);
    later(700, () => setState(() => shown = true));
    if (dctx != null) later(2600, _report);
  }

  void _report() {
    if (!mounted || sentResult) return;
    sentResult = true;
    final kills = g.army.where((u) => u.side != viewer && u.hp <= 0).length;
    if (localWon) {
      p.win(score: 300 + kills * 40 + g.hpOf(viewer) * 5, stars: 3, seconds: seconds, moves: g.round, stats: {'units_routed': kills});
    } else {
      p.lose(score: kills * 40, seconds: seconds, moves: g.round, stats: {'units_routed': kills});
    }
  }

  void _done() {
    if (widget.sandbox) {
      Navigator.maybePop(context);
    } else {
      _report();
    }
  }

  Offset _px((int, int) c) {
    final d = flip ? hMirror(c) : c;
    return Offset(_kHW / 2 + _hs * _sq3 * (d.$1 + d.$2 / 2), _kHH / 2 + _hs * 1.5 * d.$2);
  }

  (int, int)? _cellAt(Offset o) {
    (int, int)? best;
    var bd = 1e9;
    for (final c in kHCells) {
      final dd = (_px(c) - o).distance;
      if (dd < bd) {
        bd = dd;
        best = c;
      }
    }
    return bd <= _hs ? best : null;
  }

  String _info(HUnit u) => '${st(p.lang, u.t.key)} · ${st(p.lang, 'hp')} ${u.hp}/${u.maxHp} · ${st(p.lang, 'atk')} ${u.t.atk}';

  void _tap(Offset o) {
    final c = _cellAt(o);
    if (c == null || game.over) return;
    final u = g.unitAt(c);
    final cur = sel;
    if (!myTurn) {
      setState(() => note = u != null ? _info(u) : st(p.lang, kTerrainKeys[g.terrain[c]!]));
      return;
    }
    if (u != null && u.side == g.side) {
      p.sfx(Sfx.tap);
      setState(() {
        sel = u.done ? null : u;
        note = _info(u);
      });
      return;
    }
    if (u != null) {
      if (cur != null && play('a${g.idOf(cur)},${g.idOf(u)}')) {
        p.sfx(u.hp <= 0 ? Sfx.combo : Sfx.clear);
        setState(() => note = '');
        return;
      }
      setState(() => note = _info(u));
      return;
    }
    if (cur != null && play('m${g.idOf(cur)},${c.$1},${c.$2}')) {
      p.sfx(Sfx.place);
      setState(() {
        note = '';
        if (g.targets(cur).isEmpty) sel = null;
      });
      return;
    }
    setState(() => note = st(p.lang, kTerrainKeys[g.terrain[c]!]));
  }

  void _endTurn() {
    if (!myTurn) return;
    if (play('e')) {
      p.sfx(Sfx.place);
      setState(() {
        sel = null;
        note = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = p.lang;
    final status = note.isNotEmpty ? note : turnText(lang);
    final a0 = g.living.where((u) => u.side == 0).length, a1 = g.living.where((u) => u.side == 1).length;
    final board = TapCanvas(w: _kHW, h: _kHH, paint: _paint, onTap: _tap, semantics: st(lang, 'hTitle'));
    return Stack(children: [
      SScreen(
        bar: SBar(lang: lang, left: '⚑ ${math.min<int>(g.round, HDuel.maxRounds)}/${HDuel.maxRounds}', status: status),
        top: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconNum(Icons.shield, '$a0', color: seatColor(0)),
          const SizedBox(width: 16),
          Container(width: 12, height: 12, decoration: BoxDecoration(color: seatColor(g.side), shape: BoxShape.circle)),
          const SizedBox(width: 16),
          IconNum(Icons.shield, '$a1', color: seatColor(1)),
        ]),
        board: board,
        bottom: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(onPressed: myTurn ? _endTurn : null, icon: const Icon(Icons.skip_next), label: Text(st(lang, 'endTurn'))),
        ),
      ),
      if (shown)
        DuelResultPanel(
          title: resultText(lang),
          color: game.winner < 0 ? SColors.gold : seatColor(game.winner),
          button: st(lang, 'close'),
          onDone: _done,
        ),
    ]);
  }

  void _paint(Canvas c) {
    final cur = sel;
    final rs = cur != null && !cur.moved ? g.reach(cur).toSet() : <(int, int)>{};
    for (final cell in kHCells) {
      final o = _px(cell);
      final t = g.terrain[cell]!;
      c.drawPath(_hex(o, _hs - 0.4), fill(_kTerrainCols[t]));
      _terrainGlyph(c, o, t);
      if (rs.contains(cell)) c.drawPath(_hex(o, _hs - 1.4), stroke(const Color(0xCCFFFFFF), 1.0));
      c.drawPath(_hex(o, _hs - 0.4), stroke(const Color(0x22000000), 0.4));
    }
    _flag(c, _px(HDuel.flag0), seatColor(0));
    _flag(c, _px(HDuel.flag1), seatColor(1));
    final inRange = cur == null ? const <HUnit>[] : g.targets(cur);
    for (final u in g.living) {
      final o = _px(u.pos);
      final col = seatColor(u.side);
      if (inRange.contains(u)) c.drawCircle(o, _hs * 0.82, stroke(SColors.gold, 1.2));
      final spent = u.side == g.side && u.done;
      c.drawCircle(o, _hs * 0.58, fill(spent ? Color.lerp(col, Colors.grey, 0.55)! : col));
      if (identical(u, cur)) c.drawCircle(o, _hs * 0.66, stroke(Colors.white, 1.2));
      _glyph(c, o, u.type);
      final w = _hs * 1.1;
      c.drawRect(Rect.fromLTWH(o.dx - w / 2, o.dy + _hs * 0.62, w, 1.4), fill(const Color(0x55000000)));
      c.drawRect(Rect.fromLTWH(o.dx - w / 2, o.dy + _hs * 0.62, w * clampD(u.hp / u.maxHp, 0, 1), 1.4), fill(SColors.good));
    }
  }
}

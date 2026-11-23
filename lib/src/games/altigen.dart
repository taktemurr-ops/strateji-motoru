import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../texts.dart';

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
  Widget build(StratejiPlay play) => _HView(play: play);
}

class _HView extends StatefulWidget {
  final StratejiPlay play;
  const _HView({required this.play});
  @override
  State<_HView> createState() => _HViewState();
}

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
      bar: SBar(lang: lang, left: '⚑ ${s.turn}', status: status, onHint: ended ? null : _hint),
      top: PerkStrip(lang: lang, perks: p.perks, usta: usta),
      board: TapCanvas(w: _w, h: _h, paint: _paint, onTap: _tap, semantics: st(lang, 'hTitle')),
      bottom: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(onPressed: ended || busy ? null : _endTurn, icon: const Icon(Icons.skip_next), label: Text(st(lang, 'endTurn'))),
      ),
    );
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

  void _paint(Canvas c) {
    const cols = [Color(0xFFD8CFA0), Color(0xFF7FA36B), Color(0xFFBFA27A), Color(0xFF7FB2D0), Color(0xFFE3C58E)];
    final cur = sel;
    final rs = cur != null && !cur.moved ? s.reach(cur).toSet() : <(int, int)>{};
    for (final cell in kHCells) {
      final o = _px(cell);
      final t = s.terrain[cell]!;
      c.drawPath(_hex(o, _hs - 0.4), fill(cols[t]));
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
}

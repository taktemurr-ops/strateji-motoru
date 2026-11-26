import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../texts.dart';
import '../versus.dart';

/// Sıra Tabanlı Taktik: dört kahramanlık bir bölük, hız sırasına göre
/// hareket eden rakiplerle 8×8 avluda karşılaşır. Sis Kaptanı'nı ya da
/// bütün rakipleri yen.
const int kTN = 8;

class TType {
  final String key;
  final int hp, atk, mv, rng, spd;

  /// Yetenek anahtarı ve bekleme süresi (yalnızca kahramanlar).
  final String ability;
  final int cool;
  const TType(this.key, this.hp, this.atk, this.mv, this.rng, this.spd, [this.ability = '', this.cool = 0]);
}

const List<TType> kHeroes = [
  TType('h_guard', 14, 3, 3, 1, 3, 'a_guard', 3),
  TType('u_archer', 9, 3, 3, 4, 5, 'a_volley', 3),
  TType('h_healer', 9, 2, 3, 2, 4, 'a_heal', 2),
  TType('u_rider', 11, 4, 4, 1, 6, 'a_charge', 3),
];
const List<TType> kFoesT = [
  TType('e_bandit', 8, 3, 3, 1, 3),
  TType('e_slinger', 6, 2, 2, 3, 4),
  TType('e_wolf', 7, 3, 5, 1, 6),
  TType('e_stone', 14, 4, 2, 1, 1),
  TType('e_captain', 16, 4, 3, 1, 2),
];

class TUnit {
  final int side, type;
  int x, y, hp, maxHp, cd = 0, sh = 0;
  bool moved = false;
  TUnit(this.side, this.type, this.x, this.y, this.hp) : maxHp = hp;
  TType get t => side == 0 ? kHeroes[type] : kFoesT[type];
  bool get captain => side == 1 && type == 4;
}

class TPuzzle extends SPuzzle {
  final int seed, d;
  const TPuzzle(this.seed, this.d);
}

/// Bir birimin tur planı: gidilecek kare, eylem (0 yok, 1 saldırı, 2 yetenek), hedef.
class TPlan {
  final int x, y, kind;
  final TUnit? target;
  final int tx, ty;
  const TPlan(this.x, this.y, this.kind, {this.target, this.tx = -1, this.ty = -1});
}

int _md(int ax, int ay, int bx, int by) => (ax - bx).abs() + (ay - by).abs();

class TSim {
  final int seed, d;
  final Set<int> rock = {}, high = {};
  final List<TUnit> units = [];
  int round = 1;
  List<TUnit> order = [];
  int idx = 0;
  bool won = false, lost = false;
  final int coolBonus;
  final int atkBonus;
  int kills = 0;

  TSim(this.seed, this.d, {bool rider = false, int extraHp = 0, this.coolBonus = 0, int shield = 0, this.atkBonus = 0}) {
    final r = SeededRandom(mixSeed([seed, 7707]));
    while (true) {
      rock.clear();
      high.clear();
      for (var y = 1; y < kTN - 1; y++) {
        for (var x = 0; x < kTN; x++) {
          if (r.chance(0.12)) rock.add(y * kTN + x);
        }
      }
      for (var y = 0; y < kTN; y++) {
        for (var x = 0; x < kTN; x++) {
          if (!rock.contains(y * kTN + x) && r.chance(0.08)) high.add(y * kTN + x);
        }
      }
      final free = kTN * kTN - rock.length;
      final seen = {(kTN - 1) * kTN};
      final st = [(kTN - 1) * kTN];
      while (st.isNotEmpty) {
        final c = st.removeLast();
        final cx = c % kTN, cy = c ~/ kTN;
        for (final dd in const [(0, -1), (1, 0), (0, 1), (-1, 0)]) {
          final nx = cx + dd.$1, ny = cy + dd.$2;
          final n = ny * kTN + nx;
          if (nx < 0 || ny < 0 || nx >= kTN || ny >= kTN || rock.contains(n) || seen.contains(n)) continue;
          seen.add(n);
          st.add(n);
        }
      }
      if (seen.length == free) break;
    }
    final hc = [for (var x = 0; x < kTN; x++) if (!rock.contains((kTN - 1) * kTN + x)) x];
    r.shuffle(hc);
    final ec = [
      for (var y = 0; y < 2; y++)
        for (var x = 0; x < kTN; x++)
          if (!rock.contains(y * kTN + x)) y * kTN + x
    ];
    r.shuffle(ec);
    final types = <int>[0, 1, if (d >= 3) 2, if (d >= 5) 3];
    final heroes = [0, 1, 2, if (rider) 3];
    for (var i = 0; i < heroes.length && i < hc.length; i++) {
      final u = TUnit(0, heroes[i], hc[i], kTN - 1, kHeroes[heroes[i]].hp + extraHp)..sh = shield;
      units.add(u);
    }
    units.add(TUnit(1, 4, ec[0] % kTN, ec[0] ~/ kTN, kFoesT[4].hp));
    for (var i = 0; i < 2 + d ~/ 3 && i + 1 < ec.length; i++) {
      final t = r.pick(types);
      units.add(TUnit(1, t, ec[i + 1] % kTN, ec[i + 1] ~/ kTN, kFoesT[t].hp));
    }
    _newRound();
  }

  void _newRound() {
    final list = [...units];
    final pos = {for (var i = 0; i < units.length; i++) units[i]: i};
    list.sort((a, b) {
      final c = b.t.spd.compareTo(a.t.spd);
      if (c != 0) return c;
      final s = a.side.compareTo(b.side);
      return s != 0 ? s : pos[a]!.compareTo(pos[b]!);
    });
    order = list;
    idx = 0;
    _begin();
  }

  TUnit? get current => idx < order.length ? order[idx] : null;

  void _begin() {
    while (idx < order.length && !units.contains(order[idx])) {
      idx++;
    }
    final u = current;
    if (u != null) {
      if (u.cd > 0) u.cd--;
      u.moved = false;
    }
  }

  bool get over => won || lost;

  int atkOf(TUnit u) => u.t.atk + (u.side == 0 ? atkBonus : 0);

  int rngAt(TUnit u, int x, int y) => u.t.rng + (u.t.rng >= 2 && high.contains(y * kTN + x) ? 1 : 0);

  int dmgFrom(TUnit u, int x, int y) => atkOf(u) + (u.t.rng >= 2 && high.contains(y * kTN + x) ? 1 : 0);

  TUnit? at(int x, int y) {
    for (final u in units) {
      if (u.x == x && u.y == y) return u;
    }
    return null;
  }

  /// Birimin gidebileceği kareler (y*N+x → adım).
  Map<int, int> reach(TUnit u) {
    final occ = {for (final x in units) if (!identical(x, u)) x.y * kTN + x.x};
    final dist = <int, int>{u.y * kTN + u.x: 0};
    if (u.moved) return dist;
    final q = Queue<int>()..add(u.y * kTN + u.x);
    while (q.isNotEmpty) {
      final c = q.removeFirst();
      if (dist[c]! >= u.t.mv) continue;
      final cx = c % kTN, cy = c ~/ kTN;
      for (final dd in const [(0, -1), (1, 0), (0, 1), (-1, 0)]) {
        final nx = cx + dd.$1, ny = cy + dd.$2;
        final n = ny * kTN + nx;
        if (nx < 0 || ny < 0 || nx >= kTN || ny >= kTN || rock.contains(n) || occ.contains(n) || dist.containsKey(n)) continue;
        dist[n] = dist[c]! + 1;
        q.add(n);
      }
    }
    return dist;
  }

  void hit(TUnit t, int dd) {
    final a = math.min<int>(t.sh, dd);
    t.sh -= a;
    t.hp -= dd - a;
    if (t.hp <= 0) {
      units.remove(t);
      if (t.side == 1) kills++;
    }
  }

  int coolOf(TUnit u) => math.max<int>(1, u.t.cool - coolBonus);

  // ------------------------------------------------------------ yetenekler

  /// Şifacı: menzil 3'teki dosta +5.
  bool canHeal(TUnit u, TUnit a) => u.type == 2 && u.side == 0 && a.side == 0 && _md(u.x, u.y, a.x, a.y) <= 3;

  /// Okçu: menzil 4'teki merkez çevresindeki 3×3 alana 2 hasar.
  List<TUnit> volleyAt(int cx, int cy) => [for (final f in units) if (f.side == 1 && (f.x - cx).abs() <= 1 && (f.y - cy).abs() <= 1) f];

  /// Atlı: düz çizgide (yolu açık) 4 kareye kadar uzaktaki rakibe hücum.
  (int, int)? chargeSpot(TUnit u, TUnit f) {
    if (f.side == u.side) return null;
    if (u.x != f.x && u.y != f.y) return null;
    final dist = _md(u.x, u.y, f.x, f.y);
    if (dist < 1 || dist > 4) return null;
    final sx = (f.x - u.x).sign, sy = (f.y - u.y).sign;
    var x = u.x, y = u.y;
    for (var k = 1; k < dist; k++) {
      x += sx;
      y += sy;
      if (rock.contains(y * kTN + x) || at(x, y) != null) return null;
    }
    return (f.x - sx, f.y - sy);
  }

  void useAbility(TUnit u, {TUnit? target, int tx = -1, int ty = -1}) {
    switch (u.type) {
      case 0:
        u.sh += 4;
      case 1:
        for (final f in volleyAt(tx, ty)) {
          hit(f, 2);
        }
      case 2:
        if (target != null) target.hp = math.min<int>(target.maxHp, target.hp + 5);
      default:
        if (target != null) {
          final spot = chargeSpot(u, target);
          if (spot != null) {
            u.x = spot.$1;
            u.y = spot.$2;
            u.moved = true;
            hit(target, 6);
          }
        }
    }
    u.cd = coolOf(u);
  }

  // ------------------------------------------------------------ yapay zekâ

  TPlan plan(TUnit u) {
    final foes = [for (final x in units) if (x.side != u.side) x];
    final allies = [for (final x in units) if (x.side == u.side) x];
    final reachMap = reach(u);
    final cells = reachMap.keys.toList()..sort();
    if (u.side == 0 && u.cd == 0) {
      if (u.type == 2) {
        final hurt = [for (final a in allies) if (a.maxHp - a.hp >= 5) a];
        final byDist = [...cells]..sort((a, b) {
            final c = reachMap[a]!.compareTo(reachMap[b]!);
            return c != 0 ? c : a.compareTo(b);
          });
        for (final h in byDist) {
          for (final a in hurt) {
            if (_md(h % kTN, h ~/ kTN, a.x, a.y) <= 3) return TPlan(h % kTN, h ~/ kTN, 2, target: a);
          }
        }
      }
      if (u.type == 1) {
        TPlan? best;
        var bn = 1;
        for (final h in cells) {
          final hx = h % kTN, hy = h ~/ kTN;
          for (var cy = 0; cy < kTN; cy++) {
            for (var cx = 0; cx < kTN; cx++) {
              if (_md(hx, hy, cx, cy) > 4) continue;
              final n = volleyAt(cx, cy).length;
              if (n >= 2 && n > bn) {
                bn = n;
                best = TPlan(hx, hy, 2, tx: cx, ty: cy);
              }
            }
          }
        }
        if (best != null) return best;
      }
      if (u.type == 3 && !u.moved) {
        for (final f in foes) {
          final spot = chargeSpot(u, f);
          if (spot != null) return TPlan(u.x, u.y, 2, target: f);
        }
      }
    }
    double? bv;
    TPlan? bp;
    for (final h in cells) {
      final hx = h % kTN, hy = h ~/ kTN;
      for (final f in foes) {
        if (_md(hx, hy, f.x, f.y) > rngAt(u, hx, hy)) continue;
        final dd = dmgFrom(u, hx, hy);
        final kill = dd >= f.hp + f.sh;
        var v = dd + (kill ? 30 : 0) + (f.captain ? 20 : 0) - f.hp * 0.2 - reachMap[h]! * 0.01;
        if (u.t.rng >= 2) {
          var m = 1 << 20;
          for (final g in foes) {
            m = math.min<int>(m, _md(hx, hy, g.x, g.y));
          }
          v += m * 0.3;
        }
        if (bv == null || v > bv) {
          bv = v;
          bp = TPlan(hx, hy, 1, target: f);
        }
      }
    }
    if (bp != null) return bp;
    if (foes.isEmpty) return TPlan(u.x, u.y, 0);
    var tgt = foes.first;
    for (final f in foes) {
      if (_md(u.x, u.y, f.x, f.y) < _md(u.x, u.y, tgt.x, tgt.y)) tgt = f;
    }
    final keep = u.side == 0 && (u.type == 1 || u.type == 2);
    final want = u.t.rng + 1;
    var best = u.y * kTN + u.x;
    (int, int)? key;
    for (final h in cells) {
      final dm = _md(h % kTN, h ~/ kTN, tgt.x, tgt.y);
      final k = (keep ? (dm - want).abs() : dm, reachMap[h]!);
      if (key == null || k.$1 < key.$1 || (k.$1 == key.$1 && k.$2 < key.$2)) {
        key = k;
        best = h;
      }
    }
    return TPlan(best % kTN, best ~/ kTN, 0);
  }

  /// Muhafız siperi: planın önünde, yakında rakip varsa.
  bool wantsGuard(TUnit u) =>
      u.side == 0 && u.type == 0 && u.cd == 0 && units.any((f) => f.side == 1 && _md(u.x, u.y, f.x, f.y) <= 3);

  void apply(TUnit u, TPlan pl) {
    if (pl.kind == 2 && u.type == 3) {
      useAbility(u, target: pl.target);
      return;
    }
    u.x = pl.x;
    u.y = pl.y;
    u.moved = true;
    if (pl.kind == 1) {
      final t = pl.target;
      if (t != null && units.contains(t)) hit(t, dmgFrom(u, u.x, u.y));
    } else if (pl.kind == 2) {
      useAbility(u, target: pl.target, tx: pl.tx, ty: pl.ty);
    }
  }

  void _check() {
    if (!units.any((x) => x.captain) || !units.any((x) => x.side == 1)) won = true;
    if (!units.any((x) => x.side == 0)) lost = true;
  }

  /// Sıradaki birimin turunu bitirir; sıra yeniden kahramana gelene ya da
  /// oyun bitene kadar rakipler oynar.
  void next() {
    _check();
    if (over) return;
    idx++;
    _begin();
    while (!over) {
      if (idx >= order.length) {
        round++;
        if (round > 20) {
          lost = true;
          return;
        }
        _newRound();
        continue;
      }
      final u = current!;
      if (u.side == 0) return;
      apply(u, plan(u));
      _check();
      if (over) return;
      idx++;
      _begin();
    }
  }

  /// Yapay zekâ oyuncu kahramanın turunu oynar.
  void botTurn() {
    final u = current;
    if (u == null || u.side != 0) return;
    if (wantsGuard(u)) useAbility(u);
    apply(u, plan(u));
    next();
  }

  /// Oyun başında sıra rakipteyse onları oynat.
  void settle() {
    final u = current;
    if (u != null && u.side == 1) {
      idx--;
      next();
    }
  }
}

class TaktikKind extends StratejiKind {
  @override
  bool get duel => true;

  @override
  String get id => 'taktik';
  const TaktikKind();

  @override
  SPuzzle? make(int d, SeededRandom r) => TPuzzle(r.nextUint32(), d);

  @override
  bool check(SPuzzle p) {
    if (p is! TPuzzle) return false;
    final s = TSim(p.seed, p.d);
    s.settle();
    var guard = 0;
    while (!s.over && guard++ < 500) {
      s.botTurn();
    }
    return s.won;
  }

  @override
  List<Perk> get perks => const [
        Perk(3, Icons.favorite, 'pUnitHp', 2),
        Perk(8, Icons.person_add, 'u_rider', 1),
        Perk(15, Icons.timer, 'pCooldown', -1),
        Perk(25, Icons.shield, 'pShield', 3),
        Perk(40, Icons.gavel, 'pAtk', 1),
      ];

  @override
  List<GameStat> get stats => const [
        GameStat('runs_won', 'Kazanılan çarpışma', 'Skirmishes won', scale: 10),
        GameStat('flawless', 'Kusursuz zafer', 'Flawless victories', scale: 10),
        GameStat('foes_defeated', 'Yenilen rakip', 'Foes defeated', scale: 30),
      ];

  @override
  Widget build(StratejiPlay play) => play.ctx.match != null || play.ctx.passAndPlay ? TDuelView(play: play) : _TView(play: play);
}

class _TView extends StatefulWidget {
  final StratejiPlay play;
  const _TView({required this.play});
  @override
  State<_TView> createState() => _TViewState();
}

class _TViewState extends State<_TView> with Clock, MetaLoader {
  late TSim s;
  bool aiming = false;
  bool acted = false;
  int hints = 0;
  TPlan? hint;
  String note = '';

  StratejiPlay get p => widget.play;
  TPuzzle get z => p.puzzle as TPuzzle;

  TSim _fresh() {
    final t = TSim(
      z.seed,
      z.d,
      extraHp: p.has(usta, 0) ? 2 : 0,
      rider: p.has(usta, 1),
      coolBonus: p.has(usta, 2) ? 1 : 0,
      shield: p.has(usta, 3) ? 3 : 0,
      atkBonus: p.has(usta, 4) ? 1 : 0,
    );
    t.settle();
    return t;
  }

  @override
  void initState() {
    super.initState();
    s = _fresh();
    startClock();
    loadMeta(p.gameId, () => s = _fresh());
  }

  void _after() {
    if (s.won) {
      ended = true;
      p.sfx(Sfx.win);
      final heroes = s.units.where((u) => u.side == 0).toList();
      final hp = heroes.fold<int>(0, (a, u) => a + u.hp);
      final mx = heroes.fold<int>(0, (a, u) => a + u.maxHp) + (s.order.where((u) => u.side == 0).length - heroes.length) * 10;
      final stars = starsByHealth(hp, mx) - (hints > 0 ? 1 : 0);
      later(500, () => p.win(score: s.kills * 30 + (21 - s.round) * 15 + p.d * 30, stars: stars, seconds: seconds, moves: s.round, hints: hints, stats: {'foes_defeated': s.kills}));
    } else if (s.lost) {
      ended = true;
      later(600, () => p.lose(score: s.kills * 30, seconds: seconds, moves: s.round, stats: {'foes_defeated': s.kills}));
    }
    setState(() {});
  }

  void _endUnit() {
    if (ended) return;
    started = true;
    aiming = false;
    acted = false;
    hint = null;
    final before = s.units.where((u) => u.side == 0).fold<int>(0, (a, u) => a + u.hp);
    s.next();
    final after = s.units.where((u) => u.side == 0).fold<int>(0, (a, u) => a + u.hp);
    p.sfx(after < before ? Sfx.error : Sfx.tap);
    _after();
  }

  void _tap(Offset o) {
    final u = s.current;
    if (ended || u == null || u.side != 0) return;
    final x = (o.dx / 10).floor(), y = (o.dy / 10).floor();
    if (x < 0 || y < 0 || x >= kTN || y >= kTN) return;
    final t = s.at(x, y);
    if (aiming) {
      switch (u.type) {
        case 1:
          if (_md(u.x, u.y, x, y) > 4) return;
          started = true;
          s.useAbility(u, tx: x, ty: y);
          p.sfx(Sfx.combo);
          _endUnit();
        case 2:
          if (t == null || !s.canHeal(u, t)) return;
          started = true;
          s.useAbility(u, target: t);
          p.sfx(Sfx.coin);
          _endUnit();
        case 3:
          if (t == null || s.chargeSpot(u, t) == null) return;
          started = true;
          s.useAbility(u, target: t);
          p.sfx(Sfx.combo);
          _endUnit();
        default:
          break;
      }
      return;
    }
    if (t != null && t.side == 1) {
      if (_md(u.x, u.y, x, y) <= s.rngAt(u, u.x, u.y)) {
        started = true;
        s.hit(t, s.dmgFrom(u, u.x, u.y));
        p.sfx(Sfx.clear);
        _endUnit();
      } else {
        setState(() => note = '${st(p.lang, t.t.key)} · ${st(p.lang, 'hp')} ${t.hp} · ${st(p.lang, 'atk')} ${t.t.atk}');
      }
      return;
    }
    if (t != null) {
      setState(() => note = '${st(p.lang, t.t.key)} · ${st(p.lang, 'hp')} ${t.hp}/${t.maxHp}');
      return;
    }
    final rm = s.reach(u);
    if (!u.moved && rm.containsKey(y * kTN + x)) {
      started = true;
      u.x = x;
      u.y = y;
      u.moved = true;
      p.sfx(Sfx.place);
      setState(() => hint = null);
    }
  }

  void _ability() {
    final u = s.current;
    if (ended || u == null || u.side != 0 || u.cd > 0 || acted) return;
    if (u.type == 0) {
      started = true;
      s.useAbility(u);
      acted = true;
      p.sfx(Sfx.unlock);
      setState(() {});
      return;
    }
    setState(() => aiming = !aiming);
  }

  Future<void> _hint() async {
    final u = s.current;
    if (ended || u == null || u.side != 0) return;
    final ok = await p.ctx.requestHint();
    if (!ok || !mounted) return;
    setState(() {
      hints++;
      hint = s.plan(u);
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = p.lang;
    final u = s.current;
    final status = note.isNotEmpty
        ? note
        : (u != null && u.side == 0
            ? '${st(lang, u.t.key)} · ${st(lang, 'hp')} ${u.hp}/${u.maxHp}${u.sh > 0 ? ' · 🛡${u.sh}' : ''}'
            : st(lang, 'enemyTurn'));
    return SScreen(
      bar: SBar(lang: lang, left: '${st(lang, 'round')} ${s.round}', status: status, onHint: ended ? null : _hint, extra: [
        IconButton(
          tooltip: st(lang, 'hotseat'),
          onPressed: () => openHotseat(context, () => TDuelView(play: p, sandbox: true)),
          icon: const Icon(Icons.people_alt),
        ),
      ]),
      top: Column(mainAxisSize: MainAxisSize.min, children: [
        PerkStrip(lang: lang, perks: p.perks, usta: usta),
        const SizedBox(height: 4),
        SizedBox(height: 26, child: _timeline()),
      ]),
      board: TapCanvas(w: kTN * 10.0, h: kTN * 10.0, paint: _paint, onTap: (o) {
        note = '';
        _tap(o);
      }, semantics: st(lang, 'tTitle')),
      bottom: u == null || u.side != 0
          ? null
          : Row(children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: u.cd == 0 && !acted && !ended ? _ability : null,
                  icon: Icon(aiming ? Icons.close : Icons.auto_awesome),
                  label: Text(u.cd > 0 ? '${st(lang, u.t.ability)} (${u.cd})' : st(lang, u.t.ability), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(onPressed: ended ? null : _endUnit, icon: const Icon(Icons.skip_next), label: Text(st(lang, 'wait'), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ),
            ]),
    );
  }

  Widget _timeline() {
    final list = [for (var i = s.idx; i < s.order.length; i++) if (s.units.contains(s.order[i])) s.order[i]];
    return ListView(scrollDirection: Axis.horizontal, children: [
      for (var i = 0; i < list.length; i++)
        Container(
          width: 24,
          margin: const EdgeInsetsDirectional.only(end: 4),
          decoration: BoxDecoration(
            color: list[i].side == 0 ? SColors.accent : SColors.bad,
            shape: BoxShape.circle,
            border: Border.all(color: i == 0 ? SColors.gold : Colors.white, width: i == 0 ? 3 : 1),
          ),
          alignment: Alignment.center,
          child: Text('${list[i].t.spd}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
        ),
    ]);
  }

  void _paint(Canvas c) {
    final cur = s.current;
    final u = cur != null && cur.side == 0 ? cur : null;
    final rm = u != null ? s.reach(u) : const <int, int>{};
    for (var y = 0; y < kTN; y++) {
      for (var x = 0; x < kTN; x++) {
        final k = y * kTN + x;
        final r = Rect.fromLTWH(x * 10.0, y * 10.0, 10, 10);
        _tile(c, r, (x + y) % 2 == 0, s.high.contains(k), s.rock.contains(k));
        if (u != null && !u.moved && rm.containsKey(k) && !aiming) c.drawRect(r.deflate(1.2), stroke(const Color(0xAA3E6FB0), 0.8));
        if (aiming && u != null) {
          final ok = switch (u.type) {
            1 => _md(u.x, u.y, x, y) <= 4,
            2 => s.at(x, y) != null && s.canHeal(u, s.at(x, y)!),
            3 => s.at(x, y) != null && s.chargeSpot(u, s.at(x, y)!) != null,
            _ => false,
          };
          if (ok) c.drawRect(r.deflate(0.8), fill(const Color(0x33D9A441)));
        }
      }
    }
    final h = hint;
    if (h != null) {
      c.drawRect(Rect.fromLTWH(h.x * 10.0, h.y * 10.0, 10, 10).deflate(0.6), stroke(SColors.gold, 1.4));
      final t = h.target;
      if (t != null) c.drawCircle(Offset(t.x * 10 + 5.0, t.y * 10 + 5.0), 5, stroke(SColors.gold, 1.2));
      if (h.tx >= 0) c.drawRect(Rect.fromLTWH(h.tx * 10.0 - 10, h.ty * 10.0 - 10, 30, 30), stroke(SColors.gold, 0.8));
    }
    for (final v in s.units) {
      final o = Offset(v.x * 10 + 5.0, v.y * 10 + 5.0);
      final col = v.side == 0 ? SColors.accent : (v.captain ? const Color(0xFF6B3E8C) : SColors.bad);
      if (u != null && v.side == 1 && !aiming && _md(u.x, u.y, v.x, v.y) <= s.rngAt(u, u.x, u.y)) {
        c.drawCircle(o, 4.8, stroke(SColors.gold, 1.0));
      }
      c.drawCircle(o, 3.8, fill(col));
      if (identical(v, cur)) c.drawCircle(o, 4.4, stroke(Colors.white, 1.0));
      if (v.sh > 0) c.drawCircle(o, 4.2, stroke(const Color(0xFF9CC3E6), 0.8));
      _glyph(c, o, v);
      c.drawRect(Rect.fromLTWH(v.x * 10 + 1.0, v.y * 10 + 8.8, 8, 0.9), fill(const Color(0x55000000)));
      c.drawRect(Rect.fromLTWH(v.x * 10 + 1.0, v.y * 10 + 8.8, 8 * clampD(v.hp / v.maxHp, 0, 1), 0.9), fill(SColors.good));
    }
  }

  void _glyph(Canvas c, Offset o, TUnit v) {
    final w = stroke(Colors.white, 0.7);
    if (v.side == 0) {
      _heroGlyph(c, o, v.type);
    } else {
      switch (v.type) {
        case 4:
          final path = Path()
            ..moveTo(o.dx - 2.2, o.dy + 1)
            ..lineTo(o.dx - 2.2, o.dy - 1.6)
            ..lineTo(o.dx - 1, o.dy - 0.4)
            ..lineTo(o.dx, o.dy - 2)
            ..lineTo(o.dx + 1, o.dy - 0.4)
            ..lineTo(o.dx + 2.2, o.dy - 1.6)
            ..lineTo(o.dx + 2.2, o.dy + 1)
            ..close();
          c.drawPath(path, fill(SColors.gold));
        case 1:
          c.drawCircle(o, 1.2, w);
        case 2:
          c.drawLine(o + const Offset(-2, -1.5), o + const Offset(-1, 1.5), w);
          c.drawLine(o + const Offset(2, -1.5), o + const Offset(1, 1.5), w);
        case 3:
          c.drawRect(Rect.fromCenter(center: o, width: 3, height: 3), fill(const Color(0x99FFFFFF)));
        default:
          c.drawLine(o + const Offset(-1.8, -1.8), o + const Offset(1.8, 1.8), w);
          c.drawLine(o + const Offset(1.8, -1.8), o + const Offset(-1.8, 1.8), w);
      }
    }
  }
}

void _tile(Canvas c, Rect r, bool even, bool high, bool rock) {
  c.drawRect(r, fill(even ? const Color(0xFFE4D8BE) : const Color(0xFFDACDB0)));
  if (high) {
    c.drawRect(r.deflate(0.8), fill(const Color(0xFFC9B48B)));
    c.drawLine(r.bottomLeft + const Offset(1.5, -1.5), r.topRight + const Offset(-1.5, 1.5), stroke(const Color(0x55000000), 0.4));
  }
  if (rock) {
    final path = Path()
      ..moveTo(r.left + 1, r.bottom - 1)
      ..lineTo(r.left + 3, r.top + 2.5)
      ..lineTo(r.left + 6.5, r.top + 1.5)
      ..lineTo(r.right - 1, r.bottom - 1)
      ..close();
    c.drawPath(path, fill(const Color(0xFF7D746A)));
  }
}

void _heroGlyph(Canvas c, Offset o, int type) {
  final w = stroke(Colors.white, 0.7);
  switch (type) {
    case 0:
      c.drawRect(Rect.fromCenter(center: o, width: 3.4, height: 4), w);
    case 1:
      c.drawArc(Rect.fromCenter(center: o, width: 3.6, height: 5), -math.pi / 2, math.pi, false, w);
    case 2:
      c.drawLine(o + const Offset(0, -2), o + const Offset(0, 2), w);
      c.drawLine(o + const Offset(-2, 0), o + const Offset(2, 0), w);
    default:
      c.drawLine(o + const Offset(-2, 2), o + const Offset(0, -2), w);
      c.drawLine(o + const Offset(0, -2), o + const Offset(2, 2), w);
  }
}

// ------------------------------------------------------------ iki kişilik düello

class DUnit {
  final int side, type;
  int x, y, hp, maxHp, cd = 0, sh = 0;
  DUnit(this.side, this.type, this.x, this.y, this.hp) : maxHp = hp;
  TType get t => kHeroes[type];
}

/// Sıra Tabanlı Taktik düellosu: 8×8 avlu merkeze göre nokta simetrik; iki
/// taraf da aynı dört kahramanı (muhafız, okçu, şifacı, atlı) karşılıklı
/// konumlarda dizer. Birimler hız sırasıyla oynar; eşit hızda ilk sıra her
/// raunt yer değiştirir. Bir birimin turu tek hamledir:
/// "t<birim>,<x>,<y>,<eylem>" — önce (x,y)'ye yürü, sonra eylem:
/// w bekle · h<hedef> vur · g siper · v<x>:<y> ok yağmuru · l<dost> iyileştir ·
/// c<hedef> hücum (yürümeden). Bütün rakipleri yenen kazanır; [maxRounds]
/// rauntta bitmezse toplam canı çok olan.
class TDuel implements DuelGame {
  final int seed;
  final Set<int> rock = {}, high = {};

  /// 0-3 mavi, 4-7 kırmızı (aynı sırada aynı kahramanlar).
  final List<DUnit> army = [];
  int round = 1;
  List<int> order = [];
  int idx = 0;
  int _winner = -2;
  int _applied = 0;
  static const int maxRounds = 20;

  TDuel(this.seed) {
    final r = SeededRandom(mixSeed([seed, 7708]));
    const last = kTN * kTN - 1;
    while (true) {
      rock.clear();
      high.clear();
      for (var k = kTN; k < kTN * kTN ~/ 2; k++) {
        if (r.chance(0.12)) {
          rock.add(k);
          rock.add(last - k);
        }
      }
      for (var k = 0; k < kTN * kTN ~/ 2; k++) {
        if (!rock.contains(k) && r.chance(0.08)) {
          high.add(k);
          high.add(last - k);
        }
      }
      final free = kTN * kTN - rock.length;
      final seen = {(kTN - 1) * kTN};
      final st = [(kTN - 1) * kTN];
      while (st.isNotEmpty) {
        final c = st.removeLast();
        final cx = c % kTN, cy = c ~/ kTN;
        for (final dd in const [(0, -1), (1, 0), (0, 1), (-1, 0)]) {
          final nx = cx + dd.$1, ny = cy + dd.$2;
          final n = ny * kTN + nx;
          if (nx < 0 || ny < 0 || nx >= kTN || ny >= kTN || rock.contains(n) || seen.contains(n)) continue;
          seen.add(n);
          st.add(n);
        }
      }
      if (seen.length == free) break;
    }
    final xs = [for (var x = 0; x < kTN; x++) x];
    r.shuffle(xs);
    for (var i = 0; i < kHeroes.length; i++) {
      army.add(DUnit(0, i, xs[i], kTN - 1, kHeroes[i].hp));
    }
    for (var i = 0; i < kHeroes.length; i++) {
      army.add(DUnit(1, i, kTN - 1 - xs[i], 0, kHeroes[i].hp));
    }
    _newRound();
  }

  void _newRound() {
    final ids = [for (var i = 0; i < army.length; i++) if (army[i].hp > 0) i];
    final first = round.isOdd ? 0 : 1;
    ids.sort((a, b) {
      final ua = army[a], ub = army[b];
      final c = ub.t.spd.compareTo(ua.t.spd);
      if (c != 0) return c;
      if (ua.side != ub.side) return ua.side == first ? -1 : 1;
      return a.compareTo(b);
    });
    order = ids;
    idx = 0;
    _begin();
  }

  void _begin() {
    while (idx < order.length && army[order[idx]].hp <= 0) {
      idx++;
    }
    if (idx >= order.length) {
      round++;
      if (round > maxRounds) {
        final h0 = hpOf(0), h1 = hpOf(1);
        _winner = h0 == h1 ? -1 : (h0 > h1 ? 0 : 1);
        return;
      }
      _newRound();
      return;
    }
    final u = army[order[idx]];
    if (u.cd > 0) u.cd--;
  }

  int get currentId => over || idx >= order.length ? -1 : order[idx];

  DUnit? get current => currentId < 0 ? null : army[currentId];

  @override
  int get turnSeat => current?.side ?? 0;

  @override
  int get turnKey => round * 100 + idx;

  @override
  bool get over => _winner != -2;

  @override
  int get winner => _winner;

  @override
  int get applied => _applied;

  int hpOf(int s) => army.where((u) => u.side == s && u.hp > 0).fold<int>(0, (a, u) => a + u.hp);

  DUnit? at(int x, int y) {
    for (final u in army) {
      if (u.hp > 0 && u.x == x && u.y == y) return u;
    }
    return null;
  }

  int rngAt(DUnit u, int x, int y) => u.t.rng + (u.t.rng >= 2 && high.contains(y * kTN + x) ? 1 : 0);

  int dmgFrom(DUnit u, int x, int y) => u.t.atk + (u.t.rng >= 2 && high.contains(y * kTN + x) ? 1 : 0);

  Map<int, int> reach(DUnit u) {
    final occ = {for (final x in army) if (x.hp > 0 && !identical(x, u)) x.y * kTN + x.x};
    final dist = <int, int>{u.y * kTN + u.x: 0};
    final q = Queue<int>()..add(u.y * kTN + u.x);
    while (q.isNotEmpty) {
      final c = q.removeFirst();
      if (dist[c]! >= u.t.mv) continue;
      final cx = c % kTN, cy = c ~/ kTN;
      for (final dd in const [(0, -1), (1, 0), (0, 1), (-1, 0)]) {
        final nx = cx + dd.$1, ny = cy + dd.$2;
        final n = ny * kTN + nx;
        if (nx < 0 || ny < 0 || nx >= kTN || ny >= kTN || rock.contains(n) || occ.contains(n) || dist.containsKey(n)) continue;
        dist[n] = dist[c]! + 1;
        q.add(n);
      }
    }
    return dist;
  }

  void hit(DUnit t, int dd) {
    final a = math.min<int>(t.sh, dd);
    t.sh -= a;
    t.hp = math.max<int>(0, t.hp - (dd - a));
  }

  List<DUnit> volleyAt(int side, int cx, int cy) => [for (final f in army) if (f.hp > 0 && f.side != side && (f.x - cx).abs() <= 1 && (f.y - cy).abs() <= 1) f];

  bool canHeal(DUnit u, DUnit a) => u.type == 2 && a.hp > 0 && a.side == u.side && _md(u.x, u.y, a.x, a.y) <= 3;

  (int, int)? chargeSpot(DUnit u, DUnit f) {
    if (f.hp <= 0 || f.side == u.side) return null;
    if (u.x != f.x && u.y != f.y) return null;
    final dist = _md(u.x, u.y, f.x, f.y);
    if (dist < 1 || dist > 4) return null;
    final sx = (f.x - u.x).sign, sy = (f.y - u.y).sign;
    var x = u.x, y = u.y;
    for (var k = 1; k < dist; k++) {
      x += sx;
      y += sy;
      if (rock.contains(y * kTN + x) || at(x, y) != null) return null;
    }
    return (f.x - sx, f.y - sy);
  }

  DUnit? _unit(String s) {
    final i = int.tryParse(s);
    return i == null || i < 0 || i >= army.length ? null : army[i];
  }

  @override
  bool apply(int seat, String mv) {
    if (over || mv.length < 2 || mv[0] != 't') return false;
    final parts = mv.substring(1).split(',');
    if (parts.length != 4) return false;
    final id = int.tryParse(parts[0]), x = int.tryParse(parts[1]), y = int.tryParse(parts[2]);
    final u = current;
    if (id == null || x == null || y == null || u == null || id != currentId || u.side != seat) return false;
    if (x < 0 || y < 0 || x >= kTN || y >= kTN || !reach(u).containsKey(y * kTN + x)) return false;
    final ox = u.x, oy = u.y;
    u.x = x;
    u.y = y;
    if (!_act(u, parts[3], x == ox && y == oy)) {
      u.x = ox;
      u.y = oy;
      return false;
    }
    _applied++;
    final a0 = army.any((v) => v.side == 0 && v.hp > 0), a1 = army.any((v) => v.side == 1 && v.hp > 0);
    if (!a0 || !a1) {
      _winner = a0 ? 0 : (a1 ? 1 : -1);
      return true;
    }
    idx++;
    _begin();
    return true;
  }

  bool _act(DUnit u, String act, bool stayed) {
    if (act.isEmpty) return false;
    final rest = act.substring(1);
    final kind = act[0];
    if (kind == 'w') return act == 'w';
    if (kind == 'g') {
      if (act != 'g' || u.type != 0 || u.cd > 0) return false;
      u.sh += 4;
      u.cd = u.t.cool;
      return true;
    }
    if (kind == 'h') {
      final t = _unit(rest);
      if (t == null || t.hp <= 0 || t.side == u.side || _md(u.x, u.y, t.x, t.y) > rngAt(u, u.x, u.y)) return false;
      hit(t, dmgFrom(u, u.x, u.y));
      return true;
    }
    if (kind == 'v') {
      final p = rest.split(':');
      if (u.type != 1 || u.cd > 0 || p.length != 2) return false;
      final cx = int.tryParse(p[0]), cy = int.tryParse(p[1]);
      if (cx == null || cy == null || cx < 0 || cy < 0 || cx >= kTN || cy >= kTN || _md(u.x, u.y, cx, cy) > 4) return false;
      for (final f in volleyAt(u.side, cx, cy)) {
        hit(f, 2);
      }
      u.cd = u.t.cool;
      return true;
    }
    if (kind == 'l') {
      final t = _unit(rest);
      if (t == null || u.cd > 0 || !canHeal(u, t)) return false;
      t.hp = math.min<int>(t.maxHp, t.hp + 5);
      u.cd = u.t.cool;
      return true;
    }
    if (kind == 'c') {
      final t = _unit(rest);
      if (t == null || u.type != 3 || u.cd > 0 || !stayed) return false;
      final spot = chargeSpot(u, t);
      if (spot == null) return false;
      u.x = spot.$1;
      u.y = spot.$2;
      hit(t, 6);
      u.cd = u.t.cool;
      return true;
    }
    return false;
  }

  @override
  String timeoutMove() {
    final u = current;
    return u == null ? 'w' : 't$currentId,${u.x},${u.y},w';
  }

  /// Bilgisayar: yetenek fırsatı (iyileştirme, ok yağmuru, hücum), yoksa en
  /// iyi saldırı, yoksa en yakın rakibe yaklaş (gerekirse siper al).
  @override
  String botMove() {
    final u = current;
    if (u == null) return 'w';
    final id = currentId;
    String mv(int x, int y, String act) => 't$id,$x,$y,$act';
    final foes = [for (final f in army) if (f.hp > 0 && f.side != u.side) f];
    final allies = [for (final a in army) if (a.hp > 0 && a.side == u.side) a];
    final rm = reach(u);
    final cells = rm.keys.toList()..sort();
    if (u.cd == 0) {
      if (u.type == 2) {
        final hurt = [for (final a in allies) if (a.maxHp - a.hp >= 5) a];
        final byDist = [...cells]..sort((a, b) {
            final c = rm[a]!.compareTo(rm[b]!);
            return c != 0 ? c : a.compareTo(b);
          });
        for (final h in byDist) {
          for (final a in hurt) {
            final ax = identical(a, u) ? h % kTN : a.x, ay = identical(a, u) ? h ~/ kTN : a.y;
            if (_md(h % kTN, h ~/ kTN, ax, ay) <= 3) return mv(h % kTN, h ~/ kTN, 'l${army.indexOf(a)}');
          }
        }
      }
      if (u.type == 1) {
        String? best;
        var bn = 1;
        for (final h in cells) {
          final hx = h % kTN, hy = h ~/ kTN;
          for (var cy = 0; cy < kTN; cy++) {
            for (var cx = 0; cx < kTN; cx++) {
              if (_md(hx, hy, cx, cy) > 4) continue;
              final n = volleyAt(u.side, cx, cy).length;
              if (n >= 2 && n > bn) {
                bn = n;
                best = mv(hx, hy, 'v$cx:$cy');
              }
            }
          }
        }
        if (best != null) return best;
      }
      if (u.type == 3) {
        for (final f in foes) {
          if (chargeSpot(u, f) != null) return mv(u.x, u.y, 'c${army.indexOf(f)}');
        }
      }
    }
    double? bv;
    String? bp;
    for (final h in cells) {
      final hx = h % kTN, hy = h ~/ kTN;
      for (final f in foes) {
        if (_md(hx, hy, f.x, f.y) > rngAt(u, hx, hy)) continue;
        final dd = dmgFrom(u, hx, hy);
        final kill = dd >= f.hp + f.sh;
        var v = dd + (kill ? 30 : 0) - f.hp * 0.2 - rm[h]! * 0.01;
        if (u.t.rng >= 2) {
          var m = 1 << 20;
          for (final g in foes) {
            m = math.min<int>(m, _md(hx, hy, g.x, g.y));
          }
          v += m * 0.3;
        }
        if (bv == null || v > bv) {
          bv = v;
          bp = mv(hx, hy, 'h${army.indexOf(f)}');
        }
      }
    }
    if (bp != null) return bp;
    if (foes.isEmpty) return mv(u.x, u.y, 'w');
    var tgt = foes.first;
    for (final f in foes) {
      if (_md(u.x, u.y, f.x, f.y) < _md(u.x, u.y, tgt.x, tgt.y)) tgt = f;
    }
    final keep = u.type == 1 || u.type == 2;
    final want = u.t.rng + 1;
    var best = u.y * kTN + u.x;
    (int, int)? key;
    for (final h in cells) {
      final dm = _md(h % kTN, h ~/ kTN, tgt.x, tgt.y);
      final k = (keep ? (dm - want).abs() : dm, rm[h]!);
      if (key == null || k.$1 < key.$1 || (k.$1 == key.$1 && k.$2 < key.$2)) {
        key = k;
        best = h;
      }
    }
    final bx = best % kTN, by = best ~/ kTN;
    final near = foes.any((f) => _md(bx, by, f.x, f.y) <= 3);
    return mv(bx, by, u.type == 0 && u.cd == 0 && near ? 'g' : 'w');
  }

  @override
  String get hash {
    final b = StringBuffer('$round/$idx/$_winner/');
    for (final u in army) {
      b.write('${u.hp},${u.x},${u.y},${u.cd},${u.sh};');
    }
    return b.toString();
  }
}

class TDuelView extends StatefulWidget {
  final StratejiPlay play;
  final bool sandbox;
  const TDuelView({super.key, required this.play, this.sandbox = false});
  @override
  State<TDuelView> createState() => _TDuelViewState();
}

class _TDuelViewState extends State<TDuelView> with Clock, DuelHost {
  /// Seçilen yeni konum (henüz gönderilmedi; null: birim yerinde).
  int? px, py;
  bool aiming = false;
  String note = '';
  bool shown = false;
  bool sentResult = false;

  StratejiPlay get p => widget.play;
  TDuel get g => game as TDuel;

  @override
  int get turnSeconds => 30;

  @override
  void initState() {
    super.initState();
    final m = p.ctx.match;
    final seed = widget.sandbox ? mixSeed([p.seed, DateTime.now().millisecondsSinceEpoch]) : (m?.seed ?? p.seed);
    startClock();
    initDuel(TDuel(seed), widget.sandbox ? null : p.ctx);
  }

  @override
  void onDuelChanged() {
    px = null;
    py = null;
    aiming = false;
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
      p.win(score: 300 + kills * 40 + g.hpOf(viewer) * 5, stars: 3, seconds: seconds, moves: g.round, stats: {'foes_defeated': kills});
    } else {
      p.lose(score: kills * 30, seconds: seconds, moves: g.round, stats: {'foes_defeated': kills});
    }
  }

  void _done() {
    if (widget.sandbox) {
      Navigator.maybePop(context);
    } else {
      _report();
    }
  }

  int _dx(int x) => flip ? kTN - 1 - x : x;
  int _dy(int y) => flip ? kTN - 1 - y : y;

  /// Yerel oyuncunun sırasındaki birim.
  DUnit? get mine => myTurn ? g.current : null;

  int get fx => px ?? g.current?.x ?? 0;
  int get fy => py ?? g.current?.y ?? 0;

  void _send(String act) {
    final u = g.current;
    if (u == null) return;
    final ok = play('t${g.currentId},$fx,$fy,$act');
    p.sfx(ok ? (act == 'w' ? Sfx.tap : Sfx.clear) : Sfx.error);
  }

  void _tap(Offset o) {
    final x = _dx((o.dx / 10).floor()), y = _dy((o.dy / 10).floor());
    if (x < 0 || y < 0 || x >= kTN || y >= kTN || game.over) return;
    final t = g.at(x, y);
    final u = mine;
    if (u == null) {
      if (t != null) setState(() => note = '${st(p.lang, t.t.key)} · ${st(p.lang, 'hp')} ${t.hp}/${t.maxHp}');
      return;
    }
    if (aiming) {
      switch (u.type) {
        case 1:
          if (_md(fx, fy, x, y) <= 4) _send('v$x:$y');
        case 2:
          if (t != null && t.side == u.side) {
            final tx = identical(t, u) ? fx : t.x, ty = identical(t, u) ? fy : t.y;
            if (_md(fx, fy, tx, ty) <= 3) _send('l${g.army.indexOf(t)}');
          }
        case 3:
          if (t != null && g.chargeSpot(u, t) != null) {
            px = null;
            py = null;
            _send('c${g.army.indexOf(t)}');
          }
        default:
          break;
      }
      return;
    }
    if (t != null && t.side != u.side) {
      if (_md(fx, fy, t.x, t.y) <= g.rngAt(u, fx, fy)) {
        _send('h${g.army.indexOf(t)}');
      } else {
        setState(() => note = '${st(p.lang, t.t.key)} · ${st(p.lang, 'hp')} ${t.hp}/${t.maxHp}');
      }
      return;
    }
    if (t != null && !identical(t, u)) {
      setState(() => note = '${st(p.lang, t.t.key)} · ${st(p.lang, 'hp')} ${t.hp}/${t.maxHp}');
      return;
    }
    if (g.reach(u).containsKey(y * kTN + x)) {
      p.sfx(Sfx.place);
      setState(() {
        px = x;
        py = y;
        note = '';
      });
    }
  }

  void _ability() {
    final u = mine;
    if (u == null || u.cd > 0) return;
    if (u.type == 0) {
      _send('g');
      return;
    }
    setState(() => aiming = !aiming);
  }

  @override
  Widget build(BuildContext context) {
    final lang = p.lang;
    final u = mine;
    final cur = g.current;
    final status = note.isNotEmpty ? note : turnText(lang);
    return Stack(children: [
      SScreen(
        bar: SBar(lang: lang, left: '${st(lang, 'round')} ${math.min<int>(g.round, TDuel.maxRounds)}', status: status),
        top: SizedBox(height: 26, child: _timeline()),
        board: TapCanvas(w: kTN * 10.0, h: kTN * 10.0, paint: _paint, onTap: (o) {
          note = '';
          _tap(o);
        }, semantics: st(lang, 'tTitle')),
        bottom: u == null
            ? SizedBox(
                height: 40,
                child: Center(
                  child: cur == null
                      ? const SizedBox()
                      : Text('${st(lang, cur.t.key)} · ${st(lang, 'hp')} ${cur.hp}/${cur.maxHp}', style: TextStyle(color: seatColor(cur.side), fontWeight: FontWeight.w700)),
                ),
              )
            : Row(children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: u.cd == 0 ? _ability : null,
                    icon: Icon(aiming ? Icons.close : Icons.auto_awesome),
                    label: Text(u.cd > 0 ? '${st(lang, u.t.ability)} (${u.cd})' : st(lang, u.t.ability), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(onPressed: () => _send('w'), icon: const Icon(Icons.skip_next), label: Text(st(lang, 'wait'), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ),
              ]),
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

  Widget _timeline() {
    final list = [for (var i = g.idx; i < g.order.length; i++) if (g.army[g.order[i]].hp > 0) g.army[g.order[i]]];
    return ListView(scrollDirection: Axis.horizontal, children: [
      for (var i = 0; i < list.length && !game.over; i++)
        Container(
          width: 24,
          margin: const EdgeInsetsDirectional.only(end: 4),
          decoration: BoxDecoration(
            color: seatColor(list[i].side),
            shape: BoxShape.circle,
            border: Border.all(color: i == 0 ? SColors.gold : Colors.white, width: i == 0 ? 3 : 1),
          ),
          alignment: Alignment.center,
          child: Text('${list[i].t.spd}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
        ),
    ]);
  }

  void _paint(Canvas c) {
    final cur = g.current;
    final u = mine;
    final rm = u != null ? g.reach(u) : const <int, int>{};
    for (var y = 0; y < kTN; y++) {
      for (var x = 0; x < kTN; x++) {
        final k = y * kTN + x;
        final r = Rect.fromLTWH(_dx(x) * 10.0, _dy(y) * 10.0, 10, 10);
        _tile(c, r, (x + y) % 2 == 0, g.high.contains(k), g.rock.contains(k));
        if (u != null && rm.containsKey(k) && !aiming) c.drawRect(r.deflate(1.2), stroke(const Color(0xAA3E6FB0), 0.8));
        if (aiming && u != null) {
          final t = g.at(x, y);
          final ok = switch (u.type) {
            1 => _md(fx, fy, x, y) <= 4,
            2 => t != null && t.side == u.side && _md(fx, fy, identical(t, u) ? fx : t.x, identical(t, u) ? fy : t.y) <= 3,
            3 => t != null && g.chargeSpot(u, t) != null,
            _ => false,
          };
          if (ok) c.drawRect(r.deflate(0.8), fill(const Color(0x33D9A441)));
        }
      }
    }
    if (u != null && px != null) {
      c.drawRect(Rect.fromLTWH(_dx(fx) * 10.0, _dy(fy) * 10.0, 10, 10).deflate(0.6), stroke(SColors.gold, 1.2));
    }
    for (final v in g.army) {
      if (v.hp <= 0) continue;
      final vx = identical(v, u) ? fx : v.x, vy = identical(v, u) ? fy : v.y;
      final o = Offset(_dx(vx) * 10 + 5.0, _dy(vy) * 10 + 5.0);
      if (u != null && v.side != u.side && !aiming && _md(fx, fy, v.x, v.y) <= g.rngAt(u, fx, fy)) {
        c.drawCircle(o, 4.8, stroke(SColors.gold, 1.0));
      }
      c.drawCircle(o, 3.8, fill(seatColor(v.side)));
      if (identical(v, cur)) c.drawCircle(o, 4.4, stroke(Colors.white, 1.0));
      if (v.sh > 0) c.drawCircle(o, 4.2, stroke(const Color(0xFF9CC3E6), 0.8));
      _heroGlyph(c, o, v.type);
      final bx = _dx(vx) * 10 + 1.0, by = _dy(vy) * 10 + 8.8;
      c.drawRect(Rect.fromLTWH(bx, by, 8, 0.9), fill(const Color(0x55000000)));
      c.drawRect(Rect.fromLTWH(bx, by, 8 * clampD(v.hp / v.maxHp, 0, 1), 0.9), fill(SColors.good));
    }
  }
}

import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../texts.dart';

/// Zindan Keşfi: sıra tabanlı, sisli zindanda kat kat iniş.
/// Her hamleden sonra yaratıklar da bir adım atar; merdivene ulaşınca bir
/// kat aşağı inilir, son kattaki merdiven çıkıştır.
const int kZW = 9, kZH = 11;

class ZPuzzle extends SPuzzle {
  final int seed;
  final int d;
  const ZPuzzle(this.seed, this.d);
}

/// Yaratık türü: can, saldırı, hız (0 kımıldamaz, 1 her tur, 2 iki turda bir), diken.
class ZType {
  final String key;
  final int hp, atk, speed, thorns;
  final Color color;
  const ZType(this.key, this.hp, this.atk, this.speed, this.thorns, this.color);
}

const List<ZType> kZTypes = [
  ZType('zSlime', 3, 1, 2, 0, Color(0xFF7FB069)),
  ZType('zBat', 2, 1, 1, 0, Color(0xFF8E6C8A)),
  ZType('zFox', 4, 2, 1, 0, Color(0xFFD9822B)),
  ZType('zHog', 4, 1, 0, 1, Color(0xFF8C6E54)),
  ZType('zGolem', 7, 3, 2, 0, Color(0xFF7D8794)),
];

class ZEnemy {
  final int type;
  int x, y, hp;
  ZEnemy(this.type, this.x, this.y, this.hp);
  ZType get t => kZTypes[type];
}

/// Eşyalar: 0 şifa otu, 1 kılıç bileği, 2 kalkan pulu, 3 bomba, 4 altın.
const List<int> kZItemBag = [0, 0, 0, 0, 1, 2, 3, 3, 4, 4, 4];

class ZFloor {
  final List<List<bool>> open; // [y][x]
  final (int, int) start, stairs;
  final List<ZEnemy> enemies;
  final Map<int, int> items; // y*kZW+x → eşya
  ZFloor(this.open, this.start, this.stairs, this.enemies, this.items);
}

const List<List<int>> _d4 = [
  [0, -1],
  [1, 0],
  [0, 1],
  [-1, 0],
];

int _k(int x, int y) => y * kZW + x;

Map<int, int> zBfs(List<List<bool>> open, int sx, int sy, [Set<int> block = const {}]) {
  final dist = <int, int>{_k(sx, sy): 0};
  final q = Queue<int>()..add(_k(sx, sy));
  while (q.isNotEmpty) {
    final c = q.removeFirst();
    final cx = c % kZW, cy = c ~/ kZW;
    for (final dd in _d4) {
      final nx = cx + dd[0], ny = cy + dd[1];
      if (nx < 0 || ny < 0 || nx >= kZW || ny >= kZH || !open[ny][nx]) continue;
      final n = _k(nx, ny);
      if (dist.containsKey(n) || block.contains(n)) continue;
      dist[n] = dist[c]! + 1;
      q.add(n);
    }
  }
  return dist;
}

ZFloor zMakeFloor(int seed, int d, int fl) {
  final r = SeededRandom(mixSeed([seed, fl, 4401]));
  final open = List.generate(kZH, (_) => List<bool>.filled(kZW, false));
  var x = kZW ~/ 2, y = kZH - 2;
  open[y][x] = true;
  var n = 1;
  final target = (kZW * kZH * 0.48).floor();
  var guard = 0;
  while (n < target && guard++ < 20000) {
    final dd = _d4[r.nextInt(4)];
    final nx = x + dd[0], ny = y + dd[1];
    if (nx > 0 && nx < kZW - 1 && ny > 0 && ny < kZH - 1) {
      x = nx;
      y = ny;
      if (!open[y][x]) {
        open[y][x] = true;
        n++;
      }
    }
  }
  const sx = kZW ~/ 2, sy = kZH - 2;
  final dist = zBfs(open, sx, sy);
  var far = _k(sx, sy);
  dist.forEach((c, v) {
    final cur = dist[far]!;
    if (v > cur || (v == cur && c < far)) far = c;
  });
  final cells = [for (final c in dist.keys) if (c != _k(sx, sy) && c != far) c]..sort();
  final types = <int>[0, 1, if (d >= 3) 2, if (d >= 4) 3, if (d >= 6) 4];
  final ne = 2 + d ~/ 3 + fl ~/ 2;
  final cand = [for (final c in cells) if (dist[c]! >= 4) c];
  r.shuffle(cand);
  final enemies = <ZEnemy>[];
  for (final c in cand.take(ne)) {
    final t = r.pick(types);
    enemies.add(ZEnemy(t, c % kZW, c ~/ kZW, kZTypes[t].hp));
  }
  final occ = {for (final e in enemies) _k(e.x, e.y)};
  final rest = [for (final c in cells) if (!occ.contains(c)) c];
  r.shuffle(rest);
  final ni = 2 + (d < 5 ? 1 : 0) + r.nextInt(2);
  final items = <int, int>{};
  for (final c in rest.take(ni)) {
    items[c] = kZItemBag[r.nextInt(kZItemBag.length)];
  }
  return ZFloor(open, (sx, sy), (far % kZW, far ~/ kZW), enemies, items);
}

/// Eylem: 0 hareket/saldırı (dx, dy), 1 şifa otu, 2 bomba, 3 bekle.
class ZAction {
  final int kind, dx, dy;
  const ZAction(this.kind, [this.dx = 0, this.dy = 0]);
}

class ZSim {
  final int seed, d;
  final int floors;
  int floor = 0;
  late ZFloor f;
  late int px, py;
  int hp, maxHp, atk, def = 0, herbs, bombs, gold = 0, kills = 0, turns = 0;
  int light;
  bool won = false, lost = false;
  late SeededRandom er;
  final Set<int> seen = {};

  /// Son turda olanlar (ses ve kısa bilgi için): 1 vurdun, 2 yara aldın, 3 eşya, 4 kat indin, 5 yaratık yenildi.
  final Set<int> events = {};

  ZSim(this.seed, this.d, {int extraHp = 0, this.herbs = 0, this.bombs = 0, int extraAtk = 0, this.light = 0})
      : floors = 2 + d ~/ 4,
        hp = 12 + extraHp,
        maxHp = 12 + extraHp,
        atk = 2 + extraAtk {
    _enter();
  }

  void _enter() {
    f = zMakeFloor(seed, d, floor);
    px = f.start.$1;
    py = f.start.$2;
    er = SeededRandom(mixSeed([seed, floor, 31]));
    seen.clear();
    _look();
  }

  int get radius => 2 + light;

  bool visible(int x, int y) => (x - px).abs() <= radius && (y - py).abs() <= radius;

  void _look() {
    for (var y = 0; y < kZH; y++) {
      for (var x = 0; x < kZW; x++) {
        if (visible(x, y)) seen.add(_k(x, y));
      }
    }
  }

  ZEnemy? enemyAt(int x, int y) {
    for (final e in f.enemies) {
      if (e.x == x && e.y == y) return e;
    }
    return null;
  }

  bool get over => won || lost;

  void _kill(ZEnemy e) {
    f.enemies.remove(e);
    kills++;
    gold++;
    events.add(5);
  }

  /// Oyuncu eylemi; geçersizse false döner (tur ilerlemez).
  bool act(ZAction a) {
    if (over) return false;
    events.clear();
    switch (a.kind) {
      case 1:
        if (herbs <= 0 || hp >= maxHp) return false;
        herbs--;
        hp = math.min<int>(maxHp, hp + 5);
      case 2:
        if (bombs <= 0) return false;
        bombs--;
        for (final e in [...f.enemies]) {
          if ((e.x - px).abs() + (e.y - py).abs() <= 2) {
            e.hp -= 3;
            if (e.hp <= 0) _kill(e);
          }
        }
        events.add(1);
      case 3:
        break;
      default:
        final nx = px + a.dx, ny = py + a.dy;
        if (nx < 0 || ny < 0 || nx >= kZW || ny >= kZH || (a.dx.abs() + a.dy.abs()) != 1) return false;
        final e = enemyAt(nx, ny);
        if (e != null) {
          e.hp -= atk;
          events.add(1);
          if (e.t.thorns > 0) {
            hp -= e.t.thorns;
            events.add(2);
          }
          if (e.hp <= 0) _kill(e);
        } else {
          if (!f.open[ny][nx]) return false;
          px = nx;
          py = ny;
          final it = f.items.remove(_k(px, py));
          if (it != null) {
            events.add(3);
            switch (it) {
              case 0:
                herbs++;
              case 1:
                atk++;
              case 2:
                def = math.min<int>(2, def + 1);
              case 3:
                bombs++;
              default:
                gold += 3;
            }
          }
          if (px == f.stairs.$1 && py == f.stairs.$2) {
            turns++;
            if (floor + 1 >= floors) {
              won = true;
              return true;
            }
            floor++;
            hp = math.min<int>(maxHp, hp + 3);
            events.add(4);
            _enter();
            return true;
          }
        }
    }
    turns++;
    if (hp <= 0) {
      lost = true;
      return true;
    }
    _enemies();
    _look();
    if (hp <= 0) lost = true;
    if (turns > 600) lost = true;
    return true;
  }

  void _hurt(int a) {
    final dmg = math.max<int>(0, a - def);
    if (dmg > 0) {
      hp -= dmg;
      events.add(2);
    }
  }

  void _enemies() {
    final occ = {for (final e in f.enemies) _k(e.x, e.y)};
    final toMe = zBfs(f.open, px, py);
    for (final e in f.enemies) {
      final t = e.t;
      final adj = (e.x - px).abs() + (e.y - py).abs() == 1;
      if (t.speed == 0) {
        if (adj) _hurt(t.atk);
        continue;
      }
      if (t.speed == 2 && turns % 2 == 1) continue;
      if (adj) {
        _hurt(t.atk);
        continue;
      }
      occ.remove(_k(e.x, e.y));
      if (e.type == 1 && er.chance(0.5)) {
        final dd = _d4[er.nextInt(4)];
        final nx = e.x + dd[0], ny = e.y + dd[1];
        if (nx >= 0 && ny >= 0 && nx < kZW && ny < kZH && f.open[ny][nx] && !occ.contains(_k(nx, ny)) && !(nx == px && ny == py)) {
          e.x = nx;
          e.y = ny;
        }
      } else {
        final me = toMe[_k(e.x, e.y)];
        if (me != null && me <= 6) {
          for (final dd in _d4) {
            final nx = e.x + dd[0], ny = e.y + dd[1];
            final nk = _k(nx, ny);
            final dn = toMe[nk];
            if (dn != null && dn < me && !occ.contains(nk) && !(nx == px && ny == py)) {
              e.x = nx;
              e.y = ny;
              break;
            }
          }
        }
      }
      occ.add(_k(e.x, e.y));
    }
  }

  /// Yapay zekâ oyuncunun önerdiği eylem (ipucu ve doğrulama).
  ZAction bot() {
    final adj = [for (final e in f.enemies) if ((e.x - px).abs() + (e.y - py).abs() == 1) e];
    final near = [for (final e in f.enemies) if ((e.x - px).abs() + (e.y - py).abs() <= 2) e];
    if (hp <= 5 && herbs > 0 && hp < maxHp) return const ZAction(1);
    if (bombs > 0 && near.length >= 2) return const ZAction(2);
    if (bombs > 0 && adj.isNotEmpty && hp <= 4) return const ZAction(2);
    if (adj.isNotEmpty) {
      adj.sort((a, b) {
        final c = a.t.thorns.compareTo(b.t.thorns);
        return c != 0 ? c : a.hp.compareTo(b.hp);
      });
      final e = adj.first;
      return ZAction(0, e.x - px, e.y - py);
    }
    final occ = {for (final e in f.enemies) _k(e.x, e.y)};
    final dist = zBfs(f.open, px, py, occ);
    int? tgt;
    var bd = 99;
    for (final c in f.items.keys.toList()..sort()) {
      final dc = dist[c];
      if (dc != null && dc <= 7 && dc < bd) {
        bd = dc;
        tgt = c;
      }
    }
    final st = _k(f.stairs.$1, f.stairs.$2);
    if (tgt == null && dist.containsKey(st)) tgt = st;
    Map<int, int> back;
    if (tgt == null) {
      back = zBfs(f.open, f.stairs.$1, f.stairs.$2);
    } else {
      back = zBfs(f.open, tgt % kZW, tgt ~/ kZW, occ..remove(tgt));
    }
    var best = -1, bv = 1 << 20;
    for (var i = 0; i < 4; i++) {
      final nk = _k(px + _d4[i][0], py + _d4[i][1]);
      final v = back[nk];
      if (v != null && v < bv && px + _d4[i][0] >= 0 && px + _d4[i][0] < kZW) {
        bv = v;
        best = i;
      }
    }
    if (best < 0) return const ZAction(3);
    return ZAction(0, _d4[best][0], _d4[best][1]);
  }
}

class ZindanKind extends StratejiKind {
  @override
  String get id => 'zindan';
  const ZindanKind();

  @override
  SPuzzle? make(int d, SeededRandom r) => ZPuzzle(r.nextUint32(), d);

  @override
  bool check(SPuzzle p) {
    if (p is! ZPuzzle) return false;
    final s = ZSim(p.seed, p.d);
    var guard = 0;
    while (!s.over && guard++ < 800) {
      if (!s.act(s.bot())) s.act(const ZAction(3));
    }
    return s.won;
  }

  @override
  List<Perk> get perks => const [
        Perk(3, Icons.spa, 'pHerb', 1),
        Perk(8, Icons.favorite, 'pMaxHp', 3),
        Perk(15, Icons.light_mode, 'pLight', 1),
        Perk(25, Icons.brightness_7, 'pBomb', 1),
        Perk(40, Icons.gavel, 'pAtk', 1),
      ];

  @override
  List<GameStat> get stats => const [
        GameStat('runs_won', 'Kazanılan sefer', 'Runs won', scale: 10),
        GameStat('flawless', 'Kusursuz sefer', 'Flawless runs', scale: 10),
        GameStat('creatures', 'Yenilen yaratık', 'Creatures defeated', scale: 30),
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
  late ZSim s;
  ZAction? hint;
  int hints = 0;
  String note = '';
  Offset? _panFrom;
  bool _panDone = false;

  StratejiPlay get p => widget.play;
  ZPuzzle get z => p.puzzle as ZPuzzle;

  ZSim _fresh() => ZSim(
        z.seed,
        z.d,
        herbs: p.has(usta, 0) ? 1 : 0,
        extraHp: p.has(usta, 1) ? 3 : 0,
        light: p.has(usta, 2) ? 1 : 0,
        bombs: p.has(usta, 3) ? 1 : 0,
        extraAtk: p.has(usta, 4) ? 1 : 0,
      );

  @override
  void initState() {
    super.initState();
    s = _fresh();
    startClock();
    loadMeta(p.gameId, () => s = _fresh());
  }

  void _do(ZAction a) {
    if (s.over || ended) return;
    final ok = s.act(a);
    if (!ok) {
      p.sfx(Sfx.error);
      return;
    }
    started = true;
    hint = null;
    if (s.events.contains(4)) {
      p.sfx(Sfx.unlock);
      note = '${st(p.lang, 'floor')} ${s.floor + 1}/${s.floors}';
    } else if (s.events.contains(5)) {
      p.sfx(Sfx.combo);
    } else if (s.events.contains(3)) {
      p.sfx(Sfx.coin);
    } else if (s.events.contains(2)) {
      p.sfx(Sfx.error);
    } else if (s.events.contains(1)) {
      p.sfx(Sfx.clear);
    } else {
      p.sfx(Sfx.tap);
    }
    setState(() {});
    if (s.won) {
      ended = true;
      final stars = starsByHealth(s.hp, s.maxHp) - (hints > 0 ? 1 : 0);
      later(500, () => p.win(score: s.gold * 10 + s.kills * 5 + s.hp * 3 + p.d * 20, stars: stars, seconds: seconds, moves: s.turns, hints: hints, stats: {'creatures': s.kills}));
    } else if (s.lost) {
      ended = true;
      later(600, () => p.lose(score: s.gold * 10 + s.kills * 5, seconds: seconds, moves: s.turns, stats: {'creatures': s.kills}));
    }
  }

  void _tapCell(Offset o) {
    final x = (o.dx / 10).floor(), y = (o.dy / 10).floor();
    if (x < 0 || y < 0 || x >= kZW || y >= kZH) return;
    final dx = x - s.px, dy = y - s.py;
    if (dx == 0 && dy == 0) {
      _do(const ZAction(3));
      return;
    }
    if (dx.abs() + dy.abs() == 1) {
      _do(ZAction(0, dx, dy));
      return;
    }
    final e = s.enemyAt(x, y);
    if (e != null && s.visible(x, y)) {
      setState(() => note = '${st(p.lang, e.t.key)} · ${st(p.lang, 'hp')} ${e.hp} · ${st(p.lang, 'atk')} ${e.t.atk}');
      return;
    }
    // Uzak kareye: yol boyunca bir adım.
    if (!s.f.open[y][x] || !s.seen.contains(_k(x, y))) return;
    final back = zBfs(s.f.open, x, y, {for (final e in s.f.enemies) _k(e.x, e.y)});
    var best = -1, bv = 1 << 20;
    for (var i = 0; i < 4; i++) {
      final nx = s.px + _d4[i][0];
      if (nx < 0 || nx >= kZW) continue;
      final v = back[_k(nx, s.py + _d4[i][1])];
      if (v != null && v < bv) {
        bv = v;
        best = i;
      }
    }
    if (best >= 0) _do(ZAction(0, _d4[best][0], _d4[best][1]));
  }

  Future<void> _hint() async {
    if (s.over) return;
    final ok = await p.ctx.requestHint();
    if (!ok || !mounted) return;
    setState(() {
      hints++;
      hint = s.bot();
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = p.lang;
    final status = note.isNotEmpty
        ? note
        : '${st(lang, 'floor')} ${s.floor + 1}/${s.floors} · ${st(lang, 'atk')} ${s.atk} · ${st(lang, 'def')} ${s.def} · ${st(lang, 'gold')} ${s.gold}';
    final h = hint;
    return SScreen(
      bar: SBar(lang: lang, left: '♥ ${s.hp}/${s.maxHp}', status: status, onHint: s.over ? null : _hint),
      top: PerkStrip(lang: lang, perks: p.perks, usta: usta),
      board: TapCanvas(
        w: kZW * 10,
        h: kZH * 10,
        semantics: st(lang, 'zTitle'),
        paint: (c) => _paint(c, h),
        onTap: _tapCell,
        onPanStart: (o) {
          _panFrom = o;
          _panDone = false;
        },
        onPanUpdate: (o) {
          final f0 = _panFrom;
          if (f0 == null || _panDone) return;
          final v = o - f0;
          if (v.distance < 8) return;
          _panDone = true;
          if (v.dx.abs() > v.dy.abs()) {
            _do(ZAction(0, v.dx > 0 ? 1 : -1, 0));
          } else {
            _do(ZAction(0, 0, v.dy > 0 ? 1 : -1));
          }
        },
        onPanEnd: () => _panFrom = null,
      ),
      bottom: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 6, children: [
        SChip(
          tooltip: st(lang, 'heal'),
          onTap: s.herbs > 0 ? () => _do(const ZAction(1)) : null,
          selected: h?.kind == 1,
          child: IconNum(Icons.spa, '${s.herbs}', color: SColors.good),
        ),
        SChip(
          tooltip: st(lang, 'bomb'),
          onTap: s.bombs > 0 ? () => _do(const ZAction(2)) : null,
          selected: h?.kind == 2,
          child: IconNum(Icons.brightness_7, '${s.bombs}', color: SColors.bad),
        ),
        SChip(
          tooltip: st(lang, 'wait'),
          onTap: () => _do(const ZAction(3)),
          selected: h?.kind == 3,
          child: Text(st(lang, 'wait')),
        ),
      ]),
    );
  }

  void _paint(Canvas c, ZAction? h) {
    c.drawRect(const Rect.fromLTWH(0, 0, kZW * 10, kZH * 10), fill(const Color(0xFF1D1B22)));
    for (var y = 0; y < kZH; y++) {
      for (var x = 0; x < kZW; x++) {
        final k = _k(x, y);
        if (!s.seen.contains(k)) continue;
        final r = Rect.fromLTWH(x * 10.0, y * 10.0, 10, 10);
        final vis = s.visible(x, y);
        if (s.f.open[y][x]) {
          c.drawRect(r.deflate(0.3), fill(Color.lerp(const Color(0xFFCDBB9A), const Color(0xFF6E6352), vis ? ((x + y) % 2) * 0.12 : 0.62)!));
        } else {
          c.drawRect(r, fill(vis ? const Color(0xFF4A4038) : const Color(0xFF2E2924)));
          c.drawLine(r.topLeft + const Offset(1, 3), r.topRight + const Offset(-1, 3), stroke(const Color(0x33FFFFFF), 0.4));
        }
        if (!vis) continue;
        if (x == s.f.stairs.$1 && y == s.f.stairs.$2) _stairs(c, r, s.floor + 1 >= s.floors);
        final it = s.f.items[k];
        if (it != null) _item(c, r.center, it);
      }
    }
    for (final e in s.f.enemies) {
      if (s.visible(e.x, e.y)) _enemy(c, e);
    }
    _hero(c, Offset(s.px * 10 + 5.0, s.py * 10 + 5.0));
    // Işık halkası
    final rr = (s.radius + 0.5) * 10.0;
    c.drawCircle(Offset(s.px * 10 + 5.0, s.py * 10 + 5.0), rr, stroke(const Color(0x33F6D68A), 0.8));
    if (h != null && h.kind == 0) {
      final cx = (s.px + h.dx) * 10 + 5.0, cy = (s.py + h.dy) * 10 + 5.0;
      c.drawCircle(Offset(cx, cy), 4.6, stroke(SColors.gold, 1.2));
    }
  }

  void _stairs(Canvas c, Rect r, bool exit) {
    for (var i = 0; i < 3; i++) {
      c.drawRect(Rect.fromLTWH(r.left + 1.5 + i * 1.2, r.top + 2.5 + i * 2.2, 7 - i * 2.4, 1.6), fill(exit ? SColors.gold : const Color(0xFF3C3530)));
    }
  }

  void _item(Canvas c, Offset o, int it) {
    switch (it) {
      case 0:
        final path = Path()
          ..moveTo(o.dx, o.dy + 3)
          ..quadraticBezierTo(o.dx - 3.5, o.dy - 1, o.dx, o.dy - 3.5)
          ..quadraticBezierTo(o.dx + 3.5, o.dy - 1, o.dx, o.dy + 3)
          ..close();
        c.drawPath(path, fill(const Color(0xFF4F9A6E)));
        c.drawLine(o + const Offset(0, 3), o + const Offset(0, -2.5), stroke(const Color(0xFFDDEFD8), 0.4));
      case 1:
        c.drawLine(o + const Offset(-2.5, 2.5), o + const Offset(2.8, -2.8), stroke(const Color(0xFFDCE3EA), 1.1));
        c.drawLine(o + const Offset(-3, 1), o + const Offset(-1, 3), stroke(const Color(0xFF8C6E54), 1.0));
      case 2:
        final path = Path()
          ..moveTo(o.dx - 3, o.dy - 3)
          ..lineTo(o.dx + 3, o.dy - 3)
          ..lineTo(o.dx + 3, o.dy)
          ..quadraticBezierTo(o.dx + 2.5, o.dy + 3, o.dx, o.dy + 3.8)
          ..quadraticBezierTo(o.dx - 2.5, o.dy + 3, o.dx - 3, o.dy)
          ..close();
        c.drawPath(path, fill(const Color(0xFF3E6FB0)));
      case 3:
        c.drawCircle(o + const Offset(0, 0.6), 2.8, fill(const Color(0xFF2B2B33)));
        c.drawLine(o + const Offset(1.4, -1.6), o + const Offset(2.8, -3.4), stroke(SColors.gold, 0.7));
      default:
        c.drawCircle(o, 2.6, fill(SColors.gold));
        c.drawCircle(o, 1.6, stroke(const Color(0xFFB0812C), 0.5));
    }
  }

  void _hero(Canvas c, Offset o) {
    c.drawCircle(o, 3.8, fill(const Color(0xFF3E6FB0)));
    c.drawCircle(o + const Offset(0, -1.2), 1.7, fill(const Color(0xFFF1D6B8)));
    // fener
    c.drawCircle(o + const Offset(3.2, 1.6), 1.3, fill(const Color(0xFFF6D68A)));
    c.drawCircle(o + const Offset(3.2, 1.6), 2.4, fill(const Color(0x33F6D68A)));
  }

  void _enemy(Canvas c, ZEnemy e) {
    final o = Offset(e.x * 10 + 5.0, e.y * 10 + 5.0);
    final col = e.t.color;
    switch (e.type) {
      case 0:
        final path = Path()
          ..moveTo(o.dx - 3.8, o.dy + 3)
          ..quadraticBezierTo(o.dx - 4, o.dy - 3.5, o.dx, o.dy - 3.2)
          ..quadraticBezierTo(o.dx + 4, o.dy - 3.5, o.dx + 3.8, o.dy + 3)
          ..close();
        c.drawPath(path, fill(col));
      case 1:
        final path = Path()
          ..moveTo(o.dx, o.dy - 1)
          ..lineTo(o.dx - 4.5, o.dy - 3)
          ..lineTo(o.dx - 3, o.dy + 1.5)
          ..lineTo(o.dx, o.dy + 0.5)
          ..lineTo(o.dx + 3, o.dy + 1.5)
          ..lineTo(o.dx + 4.5, o.dy - 3)
          ..close();
        c.drawPath(path, fill(col));
        c.drawCircle(o, 1.6, fill(col));
      case 2:
        final path = Path()
          ..moveTo(o.dx - 3.5, o.dy + 3)
          ..lineTo(o.dx - 3, o.dy - 2)
          ..lineTo(o.dx - 1.8, o.dy - 4)
          ..lineTo(o.dx - 0.6, o.dy - 1.8)
          ..lineTo(o.dx + 0.6, o.dy - 1.8)
          ..lineTo(o.dx + 1.8, o.dy - 4)
          ..lineTo(o.dx + 3, o.dy - 2)
          ..lineTo(o.dx + 3.5, o.dy + 3)
          ..close();
        c.drawPath(path, fill(col));
      case 3:
        for (var i = 0; i < 9; i++) {
          final a = math.pi + i * math.pi / 8;
          c.drawLine(o + Offset(math.cos(a) * 2, math.sin(a) * 2 + 1), o + Offset(math.cos(a) * 4.4, math.sin(a) * 4.4 + 1), stroke(col, 0.7));
        }
        c.drawOval(Rect.fromCenter(center: o + const Offset(0, 1.5), width: 6.5, height: 4), fill(col));
      default:
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: 7.4, height: 7.4), const Radius.circular(1.4)), fill(col));
        c.drawLine(o + const Offset(-2.5, 0.5), o + const Offset(2.5, -0.5), stroke(const Color(0x55000000), 0.5));
    }
    c.drawCircle(o + const Offset(-1.1, -0.6), 0.6, fill(Colors.white));
    c.drawCircle(o + const Offset(1.1, -0.6), 0.6, fill(Colors.white));
    // can noktaları
    for (var i = 0; i < e.hp && i < 7; i++) {
      c.drawCircle(Offset(e.x * 10 + 1.5 + i * 1.2, e.y * 10 + 9.2), 0.45, fill(SColors.bad));
    }
  }
}

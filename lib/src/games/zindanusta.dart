import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../texts.dart';

/// Zindan Ustası: kahramanlar girişten hazineye en kısa yoldan yürür.
/// Duvarla yolu uzat, okçu kulesiyle vur, dikenle yarala, çamurla yavaşlat,
/// nöbetçiyle yolu kes. Hazineye ulaşan her kahraman bir kalp götürür.
const int kZuW = 7, kZuH = 9;

/// Hücre türleri.
class ZuCell {
  static const floor = 0, rock = 1, wall = 2, tower = 3, spike = 4, mud = 5, guard = 6;
}

/// Kurulabilenler: (tür, fiyat, simge, metin anahtarı).
const List<(int, int, IconData, String)> kZuBuilds = [
  (ZuCell.wall, 1, Icons.crop_square, 'zu_wall'),
  (ZuCell.mud, 2, Icons.water_drop, 'zu_mud'),
  (ZuCell.spike, 3, Icons.change_history, 'zu_spike'),
  (ZuCell.guard, 4, Icons.shield_moon, 'zu_guard'),
  (ZuCell.tower, 5, Icons.cell_tower, 'zu_tower'),
];

int zuCost(int kind) => kZuBuilds.firstWhere((b) => b.$1 == kind).$2;

bool zuBlocks(int c) => c == ZuCell.rock || c == ZuCell.wall || c == ZuCell.tower;

/// Kahraman türleri: anahtar, can, hız (kaç adımda bir yürür), saldırı.
const List<(String, int, int, int)> kZuHeroes = [
  ('zu_warrior', 14, 2, 3),
  ('zu_rogue', 8, 1, 2),
  ('zu_cleric', 10, 2, 1),
  ('zu_mage', 7, 2, 2),
];

const List<Color> kZuHeroColors = [Color(0xFF8C6E54), Color(0xFF4F7F52), Color(0xFFD9A441), Color(0xFF5B5FB8)];

/// En kısa yol (dört yön; nöbetçiler geçilebilir sayılır). Yoksa null.
List<int>? zuPath(List<int> g, int start, int goal) {
  final prev = <int, int>{start: -1};
  final q = Queue<int>()..add(start);
  while (q.isNotEmpty) {
    final c = q.removeFirst();
    if (c == goal) break;
    final x = c % kZuW, y = c ~/ kZuW;
    for (final dd in const [
      [0, 1],
      [1, 0],
      [-1, 0],
      [0, -1],
    ]) {
      final nx = x + dd[0], ny = y + dd[1];
      if (nx < 0 || ny < 0 || nx >= kZuW || ny >= kZuH) continue;
      final n = ny * kZuW + nx;
      if (prev.containsKey(n) || zuBlocks(g[n])) continue;
      prev[n] = c;
      q.add(n);
    }
  }
  if (!prev.containsKey(goal)) return null;
  final p = <int>[goal];
  while (p.last != start) {
    p.add(prev[p.last]!);
  }
  return p.reversed.toList();
}

int zuCheb(int a, int b) => math.max<int>((a % kZuW - b % kZuW).abs(), (a ~/ kZuW - b ~/ kZuW).abs());
int zuManh(int a, int b) => (a % kZuW - b % kZuW).abs() + (a ~/ kZuW - b ~/ kZuW).abs();

class ZuPuzzle extends SPuzzle {
  final int d, ent, tre, gold0;
  final List<int> grid;
  final List<List<int>> waves;
  const ZuPuzzle(this.d, this.ent, this.tre, this.grid, this.waves, this.gold0);
}

class ZuHero {
  final int kind;
  int hp, maxHp, pos, cd = 0, slow = 0;
  bool disarm, done = false;
  ZuHero(this.kind, this.hp, this.pos)
      : maxHp = hp,
        disarm = kind == 1;
  int get spd => kZuHeroes[kind].$3;
  int get atk => kZuHeroes[kind].$4;
}

/// Bir dalganın adım adım benzetimi. Izgarayı (diken sökülünce, nöbetçi
/// düşünce) ve nöbetçi canlarını yerinde değiştirir.
class ZuWave {
  final ZuPuzzle z;
  final List<int> g;
  final Map<int, int> guards;
  final Map<int, int> towers;
  final int spikeDmg, towerEvery;
  final List<ZuHero> queue = [];
  final List<ZuHero> act = [];
  int t = 0, leaked = 0, kills = 0, bounty = 0;
  final Set<int> shots = {};
  ZuWave(this.z, int wi, this.g, this.guards, this.towers, {this.spikeDmg = 3, this.towerEvery = 2}) {
    final mult = 1 + 0.15 * wi + 0.09 * z.d;
    for (final k in z.waves[wi]) {
      queue.add(ZuHero(k, (kZuHeroes[k].$2 * mult).floor(), z.ent));
    }
  }

  bool get finished => (queue.isEmpty && act.isEmpty) || t >= 400;

  void tick() {
    if (finished) return;
    t++;
    shots.clear();
    if (queue.isNotEmpty && t.isOdd) act.add(queue.removeAt(0));
    for (final c in towers.keys.toList()) {
      towers[c] = towers[c]! + 1;
      if (towers[c]! < towerEvery) continue;
      final tg = [for (final h in act) if (h.hp > 0 && zuCheb(h.pos, c) <= 2) h];
      if (tg.isEmpty) continue;
      towers[c] = 0;
      final h = tg.reduce((a, b) => b.hp < a.hp ? b : a);
      h.hp -= 2;
      shots.add(c);
    }
    for (final c in guards.keys.toList()) {
      final tg = [for (final h in act) if (h.hp > 0 && zuManh(h.pos, c) <= 1) h];
      if (tg.isNotEmpty) tg.reduce((a, b) => b.hp < a.hp ? b : a).hp -= 2;
    }
    for (final h in act) {
      if (h.hp <= 0) continue;
      if (h.kind == 2 && t % 3 == 0) {
        for (final o in act) {
          if (o.hp > 0 && zuManh(o.pos, h.pos) <= 2) o.hp = math.min<int>(o.maxHp, o.hp + 1);
        }
      }
      if (h.kind == 3 && t.isEven) {
        final near = [for (final c in guards.keys) if (zuManh(c, h.pos) <= 2) c];
        if (near.isNotEmpty) guards[near.first] = guards[near.first]! - 3;
      }
      h.cd++;
      if (h.cd < h.spd) continue;
      h.cd = 0;
      if (h.slow > 0) {
        h.slow--;
        continue;
      }
      final p = zuPath(g, h.pos, z.tre);
      if (p == null) continue;
      if (p.length == 1) {
        h.done = true;
        continue;
      }
      final n = p[1];
      if (guards.containsKey(n)) {
        guards[n] = guards[n]! - h.atk;
        continue;
      }
      h.pos = n;
      final cell = g[n];
      if (cell == ZuCell.spike) {
        if (h.disarm) {
          h.disarm = false;
          g[n] = ZuCell.floor;
        } else {
          h.hp -= spikeDmg;
        }
      } else if (cell == ZuCell.mud) {
        h.slow = 1;
      }
      if (n == z.tre) h.done = true;
    }
    for (final c in [for (final e in guards.entries) if (e.value <= 0) e.key]) {
      guards.remove(c);
      g[c] = ZuCell.floor;
    }
    final next = <ZuHero>[];
    for (final h in act) {
      if (h.hp <= 0) {
        kills++;
        bounty += h.kind == 0 ? 2 : 1;
      } else if (h.done) {
        leaked++;
      } else {
        next.add(h);
      }
    }
    act
      ..clear()
      ..addAll(next);
    if (t >= 400) {
      leaked += act.length + queue.length;
      act.clear();
      queue.clear();
    }
  }
}

/// Bir seferin durumu: ızgara, altın, kalpler, dalga sırası.
class ZuRun {
  final ZuPuzzle z;
  final List<int> g;
  final Map<int, int> guards = {};
  final Map<int, int> towers = {};
  final int guardHp, spikeDmg, towerEvery;
  int gold, hearts, wave = 0, kills = 0;
  bool won = false, lost = false;
  ZuRun(this.z, {int extraGold = 0, int extraHearts = 0, this.guardHp = 10, this.spikeDmg = 3, this.towerEvery = 2})
      : g = [...z.grid],
        gold = z.gold0 + extraGold,
        hearts = 3 + extraHearts;

  bool get over => won || lost;

  /// [kind] [cell]'e kurulabilir mi (yol kapanmamalı).
  bool canBuild(int kind, int cell) {
    if (cell == z.ent || cell == z.tre || g[cell] != ZuCell.floor || gold < zuCost(kind)) return false;
    if (zuBlocks(kind)) {
      g[cell] = kind;
      final ok = zuPath(g, z.ent, z.tre) != null;
      g[cell] = ZuCell.floor;
      return ok;
    }
    return true;
  }

  void build(int kind, int cell) {
    if (!canBuild(kind, cell)) return;
    g[cell] = kind;
    gold -= zuCost(kind);
    if (kind == ZuCell.tower) towers[cell] = 0;
    if (kind == ZuCell.guard) guards[cell] = guardHp;
  }

  /// Kaldırma: bedelin yarısı geri gelir.
  void remove(int cell) {
    final k = g[cell];
    if (k == ZuCell.floor || k == ZuCell.rock) return;
    gold += zuCost(k) ~/ 2;
    g[cell] = ZuCell.floor;
    towers.remove(cell);
    guards.remove(cell);
  }

  ZuWave startWave() => ZuWave(z, wave, g, guards, towers, spikeDmg: spikeDmg, towerEvery: towerEvery);

  void endWave(ZuWave w) {
    hearts -= w.leaked;
    kills += w.kills;
    gold += w.bounty + 6;
    if (hearts <= 0) {
      hearts = 0;
      lost = true;
      return;
    }
    wave++;
    if (wave >= z.waves.length) won = true;
  }

  /// Yapay zekânın önerdiği kurulum (tür, hücre) ya da null.
  (int, int)? botPick() {
    final path = zuPath(g, z.ent, z.tre);
    if (path == null) return null;
    final onPath = path.toSet();
    (double, int, int)? best;
    for (var cell = 0; cell < g.length; cell++) {
      if (g[cell] != ZuCell.floor || cell == z.ent || cell == z.tre) continue;
      for (final kind in const [ZuCell.wall, ZuCell.tower, ZuCell.spike, ZuCell.mud]) {
        final cost = zuCost(kind);
        if (cost > gold) continue;
        final onp = onPath.contains(cell);
        if ((kind == ZuCell.spike || kind == ZuCell.mud) && !onp) continue;
        double sc;
        if (zuBlocks(kind)) {
          g[cell] = kind;
          final np = zuPath(g, z.ent, z.tre);
          g[cell] = ZuCell.floor;
          if (np == null) continue;
          if (kind == ZuCell.wall) {
            sc = (np.length - path.length).toDouble();
          } else {
            sc = np.where((c) => zuCheb(c, cell) <= 2).length * 0.55 + (np.length - path.length) * 0.5;
          }
        } else {
          sc = kind == ZuCell.spike ? 1.6 : 0.9;
        }
        final v = sc / cost;
        if (v > 0.2 && (best == null || v > best.$1)) best = (v, kind, cell);
      }
    }
    return best == null ? null : (best.$2, best.$3);
  }

  void botBuild() {
    var guard = 0;
    while (guard++ < 80) {
      final m = botPick();
      if (m == null) return;
      build(m.$1, m.$2);
    }
  }
}

class ZindanUstaKind extends StratejiKind {
  @override
  String get id => 'zindanusta';
  const ZindanUstaKind();

  @override
  SPuzzle? make(int d, SeededRandom r) {
    final ent = 1 + r.nextInt(kZuW - 2);
    final tre = (kZuH - 1) * kZuW + 1 + r.nextInt(kZuW - 2);
    List<int>? grid;
    for (var a = 0; a < 30 && grid == null; a++) {
      final g = List<int>.filled(kZuW * kZuH, ZuCell.floor);
      for (var i = 0; i < 5 + d ~/ 2; i++) {
        final c = (1 + r.nextInt(kZuH - 2)) * kZuW + r.nextInt(kZuW);
        g[c] = ZuCell.rock;
      }
      if (zuPath(g, ent, tre) != null) grid = g;
    }
    if (grid == null) return null;
    final nw = 3 + d ~/ 3;
    final waves = <List<int>>[];
    for (var w = 0; w < nw; w++) {
      final n = 2 + w + d ~/ 3;
      final top = 1 + math.min<int>(3, w + d ~/ 3);
      waves.add([for (var i = 0; i < n; i++) i == 0 ? 0 : r.nextInt(top)]);
    }
    return ZuPuzzle(d, ent, tre, grid, waves, 14 + d);
  }

  @override
  bool check(SPuzzle p) {
    if (p is! ZuPuzzle) return false;
    if (p.grid.length != kZuW * kZuH || p.waves.isEmpty || zuPath(p.grid, p.ent, p.tre) == null) return false;
    final s = ZuRun(p);
    while (!s.over) {
      s.botBuild();
      final w = s.startWave();
      while (!w.finished) {
        w.tick();
      }
      s.endWave(w);
    }
    return s.won;
  }

  @override
  List<Perk> get perks => const [
        Perk(3, Icons.paid, 'zu_pGold', 3),
        Perk(8, Icons.favorite, 'lives', 1),
        Perk(15, Icons.change_history, 'zu_pSpike', 1),
        Perk(25, Icons.shield_moon, 'zu_pGuard', 4),
        Perk(40, Icons.cell_tower, 'zu_pTower', 0),
      ];

  @override
  List<GameStat> get stats => const [
        GameStat('runs_won', 'Korunan zindan', 'Dungeons defended', scale: 10),
        GameStat('flawless', 'Kalp kaybetmeden', 'No hearts lost', scale: 10),
        GameStat('heroes_stopped', 'Durdurulan kahraman', 'Heroes stopped', scale: 50),
      ];

  @override
  Widget build(StratejiPlay play) => _ZuView(play: play);
}

class _ZuView extends StatefulWidget {
  final StratejiPlay play;
  const _ZuView({required this.play});
  @override
  State<_ZuView> createState() => _ZuViewState();
}

class _ZuViewState extends State<_ZuView> with Clock, MetaLoader {
  late ZuRun s;
  ZuWave? wave;
  int tool = 0; // kKuBuilds sırası; -1 kaldır
  int hints = 0, hintCell = -1, heartsLost = 0;
  String note = '';

  StratejiPlay get p => widget.play;
  ZuPuzzle get z => p.puzzle as ZuPuzzle;
  String get lang => p.lang;

  ZuRun _fresh() => ZuRun(
        z,
        extraGold: p.has(usta, 0) ? 3 : 0,
        extraHearts: p.has(usta, 1) ? 1 : 0,
        spikeDmg: p.has(usta, 2) ? 4 : 3,
        guardHp: p.has(usta, 3) ? 14 : 10,
        towerEvery: p.has(usta, 4) ? 1 : 2,
      );

  @override
  void initState() {
    super.initState();
    s = _fresh();
    startClock();
    loadMeta(p.gameId, () => s = _fresh());
  }

  bool get busy => ended || wave != null;

  void _tap(Offset o) {
    if (busy) return;
    final x = o.dx.floor(), y = o.dy.floor();
    if (x < 0 || y < 0 || x >= kZuW || y >= kZuH) return;
    final cell = y * kZuW + x;
    if (tool < 0) {
      if (s.g[cell] != ZuCell.floor && s.g[cell] != ZuCell.rock) {
        started = true;
        setState(() => s.remove(cell));
        p.sfx(Sfx.coin);
      }
      return;
    }
    final kind = kZuBuilds[tool].$1;
    if (!s.canBuild(kind, cell)) {
      p.sfx(Sfx.error);
      setState(() => note = s.gold < zuCost(kind) ? st(lang, 'zu_noGold') : st(lang, 'zu_blocked'));
      return;
    }
    started = true;
    setState(() {
      s.build(kind, cell);
      note = '';
      hintCell = -1;
    });
    p.sfx(Sfx.place);
  }

  void _start() {
    if (busy) return;
    started = true;
    setState(() {
      wave = s.startWave();
      hintCell = -1;
      note = '';
    });
    _step();
  }

  void _step() {
    final w = wave;
    if (w == null || !mounted) return;
    w.tick();
    setState(() {});
    if (!w.finished) {
      later(160, _step);
      return;
    }
    later(500, () {
      final h0 = s.hearts;
      s.endWave(w);
      heartsLost += h0 - s.hearts;
      p.sfx(w.leaked == 0 ? Sfx.clear : Sfx.error);
      setState(() {
        wave = null;
        note = w.leaked == 0 ? '✓ ${st(lang, 'zu_waveHeld')}' : '✗ −${w.leaked} ♥';
      });
      if (s.won) {
        ended = true;
        p.sfx(Sfx.win);
        final stars = (heartsLost == 0 ? 3 : (s.hearts >= 2 ? 2 : 1)) - (hints > 0 ? 1 : 0);
        later(400, () => p.win(score: s.kills * 30 + s.hearts * 100 + s.gold * 5 + p.d * 30, stars: stars, seconds: seconds, moves: s.wave, hints: hints, stats: {'heroes_stopped': s.kills}));
      } else if (s.lost) {
        ended = true;
        later(500, () => p.lose(score: s.kills * 30, seconds: seconds, moves: s.wave, stats: {'heroes_stopped': s.kills}));
      }
    });
  }

  Future<void> _hint() async {
    if (busy) return;
    final ok = await p.ctx.requestHint();
    if (!ok || !mounted) return;
    final m = s.botPick();
    setState(() {
      hints++;
      if (m == null) {
        note = st(lang, 'zu_ready');
        hintCell = -1;
      } else {
        tool = kZuBuilds.indexWhere((b) => b.$1 == m.$1);
        hintCell = m.$2;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = wave;
    final nextParty = s.wave < z.waves.length ? z.waves[s.wave] : const <int>[];
    final status = note.isNotEmpty ? note : '${st(lang, 'zu_wave')} ${math.min<int>(s.wave + 1, z.waves.length)}/${z.waves.length}';
    return SScreen(
      bar: SBar(lang: lang, left: '♥ ${s.hearts} · ◉ ${s.gold}', status: status, onHint: busy ? null : _hint),
      top: PerkStrip(lang: lang, perks: p.perks, usta: usta),
      board: Column(children: [
        if (w == null && nextParty.isNotEmpty)
          Wrap(spacing: 4, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('${st(lang, 'zu_next')}:', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            for (var k = 0; k < kZuHeroes.length; k++)
              if (nextParty.contains(k))
                Tooltip(
                  message: st(lang, '${kZuHeroes[k].$1}D'),
                  child: Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: CircleAvatar(radius: 7, backgroundColor: kZuHeroColors[k]),
                    label: Text('${st(lang, kZuHeroes[k].$1)} ×${nextParty.where((x) => x == k).length}', style: const TextStyle(fontSize: 11)),
                  ),
                ),
          ]),
        Expanded(
          child: TapCanvas(
            w: kZuW.toDouble(),
            h: kZuH.toDouble(),
            semantics: st(lang, 'zu_title'),
            onTap: _tap,
            paint: (c) => _paint(c, w),
          ),
        ),
      ]),
      bottom: w != null
          ? null
          : Column(mainAxisSize: MainAxisSize.min, children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (var i = 0; i < kZuBuilds.length; i++)
                    Padding(
                      padding: const EdgeInsets.all(2),
                      child: SChip(
                        selected: tool == i,
                        tooltip: st(lang, '${kZuBuilds[i].$4}D'),
                        onTap: () => setState(() => tool = i),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(kZuBuilds[i].$3, size: 16),
                          const SizedBox(width: 3),
                          Text('${st(lang, kZuBuilds[i].$4)} ◉${kZuBuilds[i].$2}', style: const TextStyle(fontSize: 12)),
                        ]),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(2),
                    child: SChip(
                      selected: tool < 0,
                      tooltip: st(lang, 'zu_removeD'),
                      onTap: () => setState(() => tool = -1),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.delete_outline, size: 16),
                        Text(st(lang, 'zu_remove'), style: const TextStyle(fontSize: 12)),
                      ]),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy ? null : _start,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(st(lang, 'zu_start')),
                ),
              ),
            ]),
    );
  }

  void _paint(Canvas c, ZuWave? w) {
    final path = zuPath(s.g, z.ent, z.tre) ?? const <int>[];
    final onPath = path.toSet();
    for (var cell = 0; cell < s.g.length; cell++) {
      final x = (cell % kZuW).toDouble(), y = (cell ~/ kZuW).toDouble();
      final r = Rect.fromLTWH(x, y, 1, 1);
      c.drawRect(r, fill((cell % kZuW + cell ~/ kZuW).isEven ? const Color(0xFF4A4552) : const Color(0xFF524C5B)));
      if (w == null && onPath.contains(cell)) c.drawRect(r.deflate(0.38), fill(const Color(0x55F6D68A)));
      final o = Offset(x + 0.5, y + 0.5);
      switch (s.g[cell]) {
        case ZuCell.rock:
          c.drawOval(r.deflate(0.1), fill(const Color(0xFF7D7480)));
          c.drawOval(Rect.fromLTWH(x + 0.25, y + 0.2, 0.3, 0.2), fill(const Color(0x33FFFFFF)));
        case ZuCell.wall:
          c.drawRect(r.deflate(0.04), fill(const Color(0xFF8C7E6E)));
          for (var k = 1; k < 3; k++) {
            c.drawLine(Offset(x + 0.04, y + k / 3), Offset(x + 0.96, y + k / 3), stroke(const Color(0x55000000), 0.03));
          }
        case ZuCell.tower:
          c.drawRect(Rect.fromLTWH(x + 0.2, y + 0.15, 0.6, 0.75), fill(const Color(0xFF6E5A48)));
          for (var k = 0; k < 3; k++) {
            c.drawRect(Rect.fromLTWH(x + 0.2 + k * 0.22, y + 0.06, 0.14, 0.12), fill(const Color(0xFF6E5A48)));
          }
          if (w != null && w.shots.contains(cell)) c.drawCircle(o, 0.12, fill(SColors.gold));
        case ZuCell.spike:
          for (var k = 0; k < 3; k++) {
            final px = x + 0.2 + k * 0.3;
            final tri = Path()
              ..moveTo(px - 0.1, y + 0.75)
              ..lineTo(px, y + 0.3)
              ..lineTo(px + 0.1, y + 0.75)
              ..close();
            c.drawPath(tri, fill(const Color(0xFFC9C3CC)));
          }
        case ZuCell.mud:
          c.drawOval(r.deflate(0.12), fill(const Color(0xFF6B4A2E)));
          c.drawOval(Rect.fromLTWH(x + 0.3, y + 0.35, 0.25, 0.12), fill(const Color(0x44FFFFFF)));
        case ZuCell.guard:
          c.drawCircle(o, 0.36, fill(const Color(0xFF3F6B35)));
          c.drawCircle(o + const Offset(-0.12, -0.08), 0.06, fill(Colors.white));
          c.drawCircle(o + const Offset(0.12, -0.08), 0.06, fill(Colors.white));
          final hp = s.guards[cell] ?? 0;
          c.drawRect(Rect.fromLTWH(x + 0.15, y + 0.88, 0.7 * clampD(hp / s.guardHp, 0, 1), 0.06), fill(SColors.good));
      }
      if (cell == hintCell) c.drawRect(r.deflate(0.03), stroke(SColors.gold, 0.08));
    }
    // Giriş ve hazine.
    final ex = (z.ent % kZuW).toDouble();
    c.drawRect(Rect.fromLTWH(ex + 0.1, 0.02, 0.8, 0.3), fill(const Color(0xFF2B2630)));
    final tx = (z.tre % kZuW).toDouble(), ty = (z.tre ~/ kZuW).toDouble();
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(tx + 0.15, ty + 0.3, 0.7, 0.5), const Radius.circular(0.08)), fill(const Color(0xFFB07A3E)));
    c.drawRect(Rect.fromLTWH(tx + 0.15, ty + 0.45, 0.7, 0.07), fill(SColors.gold));
    drawLabel(c, '♦', Offset(tx + 0.5, ty + 0.22), 0.3, SColors.gold);
    if (w != null) {
      for (final h in w.act) {
        if (h.hp <= 0) continue;
        final o = Offset(h.pos % kZuW + 0.5, h.pos ~/ kZuW + 0.5);
        c.drawCircle(o, 0.28, fill(kZuHeroColors[h.kind]));
        c.drawCircle(o, 0.28, stroke(Colors.white, 0.04));
        c.drawRect(Rect.fromLTWH(o.dx - 0.3, o.dy - 0.42, 0.6, 0.06), fill(const Color(0x66000000)));
        c.drawRect(Rect.fromLTWH(o.dx - 0.3, o.dy - 0.42, 0.6 * clampD(h.hp / h.maxHp, 0, 1), 0.06), fill(SColors.bad));
      }
    }
  }
}

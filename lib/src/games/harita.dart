import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../texts.dart';

/// Harita Defteri: dört mevsim boyunca keşif kartlarındaki biçimleri 11×11
/// haritaya çiz. Her mevsimin sonunda o mevsimin iki hedef kartı puanlanır.
const int kHN = 11;

/// Araziler: 0 orman, 1 köy, 2 tarla, 3 su, 4 dağ (önceden yerleşik).
const List<String> kHTerrain = ['hd_forest', 'hd_village', 'hd_farm', 'hd_water', 'hd_mountain'];
const List<Color> kHColors = [Color(0xFF4F7F52), Color(0xFFB0563B), Color(0xFFD9B44A), Color(0xFF4A86B8), Color(0xFF8C8178)];
const List<IconData> kHIcons = [Icons.forest, Icons.house, Icons.grass, Icons.water, Icons.landscape];

const List<List<(int, int)>> kHShapes = [
  [(0, 0), (1, 0)],
  [(0, 0), (1, 0), (2, 0)],
  [(0, 0), (0, 1), (1, 1)],
  [(0, 0), (1, 0), (2, 0), (3, 0)],
  [(0, 0), (0, 1), (0, 2), (1, 2)],
  [(0, 0), (1, 0), (2, 0), (1, 1)],
  [(1, 0), (2, 0), (0, 1), (1, 1)],
  [(0, 0), (1, 0), (0, 1), (1, 1)],
  [(0, 0), (1, 0), (0, 1), (1, 1), (0, 2)],
  [(1, 0), (0, 1), (1, 1), (2, 1), (1, 2)],
  [(0, 0)],
];
const int kHSingle = 10;

/// Keşif kartları: zaman bedeli ve iki seçenek (biçim, arazi).
const List<(int, List<(int, int)>)> kHCards = [
  (1, [(1, 0), (1, 3)]),
  (1, [(2, 2), (2, 1)]),
  (2, [(5, 1), (5, 0)]),
  (2, [(7, 2), (7, 3)]),
  (1, [(0, 3), (0, 2)]),
  (2, [(6, 0), (6, 1)]),
  (2, [(8, 2), (3, 2)]),
  (1, [(2, 3), (2, 0)]),
  (2, [(9, 1), (4, 1)]),
  (2, [(4, 3), (4, 0)]),
  (1, [(0, 1), (0, 0)]),
  (2, [(3, 3), (3, 2)]),
];
const List<int> kHLimits = [8, 8, 7, 6];

/// Hedefler: ad anahtarı (açıklaması aynı anahtar + 'D').
const List<String> kHGoals = ['hg_edge', 'hg_lines', 'hg_lake', 'hg_bigvillage', 'hg_mount', 'hg_grove', 'hg_variety', 'hg_hamlet'];
const List<IconData> kHGoalIcons = [Icons.border_outer, Icons.table_rows, Icons.water_drop, Icons.location_city, Icons.terrain, Icons.park, Icons.palette, Icons.cottage];

/// Biçimin sekiz yönü (dört dönüş × ayna), her biri sola-yukarı hizalı.
List<List<(int, int)>> hOrients(int shape) {
  final out = <List<(int, int)>>[];
  for (final flip in const [false, true]) {
    var cur = [for (final (x, y) in kHShapes[shape]) flip ? (-x, y) : (x, y)];
    for (var r = 0; r < 4; r++) {
      final mx = cur.map((c) => c.$1).reduce(math.min);
      final my = cur.map((c) => c.$2).reduce(math.min);
      final norm = [for (final (x, y) in cur) (x - mx, y - my)]..sort((a, b) => a.$2 != b.$2 ? a.$2 - b.$2 : a.$1 - b.$1);
      out.add(norm);
      cur = [for (final (x, y) in cur) (y, -x)];
    }
  }
  return out;
}

final List<List<List<(int, int)>>> _hAll = [for (var s = 0; s < kHShapes.length; s++) hOrients(s)];

/// Tekrarsız yönler (yapay zekâ için).
final List<List<List<(int, int)>>> _hUnique = [
  for (final os in _hAll)
    (() {
      final seen = <String>{};
      return [
        for (final o in os)
          if (seen.add(o.map((c) => '${c.$1},${c.$2}').join(';'))) o
      ];
    })()
];

class HPuzzle extends SPuzzle {
  final int seed, d;
  final List<int> mountains;
  final List<int> goals;
  final List<List<int>> decks;
  final int best, target;
  const HPuzzle(this.seed, this.d, this.mountains, this.goals, this.decks, this.best, this.target);
}

bool hFits(List<int> g, List<(int, int)> o, int ax, int ay) {
  for (final (x, y) in o) {
    final cx = ax + x, cy = ay + y;
    if (cx < 0 || cy < 0 || cx >= kHN || cy >= kHN) return false;
    if (g[cy * kHN + cx] != -1) return false;
  }
  return true;
}

bool hFilled(List<int> g, int x, int y) => x < 0 || y < 0 || x >= kHN || y >= kHN || g[y * kHN + x] != -1;

int _at(List<int> g, int x, int y) => (x < 0 || y < 0 || x >= kHN || y >= kHN) ? -2 : g[y * kHN + x];

/// Hedef puanı.
int hGoal(List<int> g, int goal) {
  var s = 0;
  switch (goal) {
    case 0:
      for (var k = 0; k < kHN * kHN; k++) {
        final x = k % kHN, y = k ~/ kHN;
        if (g[k] == 0 && (x == 0 || y == 0 || x == kHN - 1 || y == kHN - 1)) s++;
      }
    case 1:
      for (var i = 0; i < kHN; i++) {
        var row = true, col = true;
        for (var j = 0; j < kHN; j++) {
          if (g[i * kHN + j] == -1) row = false;
          if (g[j * kHN + i] == -1) col = false;
        }
        if (row) s += 4;
        if (col) s += 4;
      }
    case 2:
      for (var k = 0; k < kHN * kHN; k++) {
        final t = g[k];
        if (t != 2 && t != 3) continue;
        final want = t == 2 ? 3 : 2;
        final x = k % kHN, y = k ~/ kHN;
        if (_at(g, x + 1, y) == want || _at(g, x - 1, y) == want || _at(g, x, y + 1) == want || _at(g, x, y - 1) == want) s++;
      }
    case 3:
      final seen = List<bool>.filled(kHN * kHN, false);
      for (var k = 0; k < kHN * kHN; k++) {
        if (g[k] != 1 || seen[k]) continue;
        var n = 0;
        final stack = [k];
        seen[k] = true;
        while (stack.isNotEmpty) {
          final c = stack.removeLast();
          n++;
          final x = c % kHN, y = c ~/ kHN;
          for (final d in kDirs4) {
            final nx = x + d[0], ny = y + d[1];
            if (_at(g, nx, ny) == 1 && !seen[ny * kHN + nx]) {
              seen[ny * kHN + nx] = true;
              stack.add(ny * kHN + nx);
            }
          }
        }
        if (n > s) s = n;
      }
    case 4:
      for (var k = 0; k < kHN * kHN; k++) {
        if (g[k] != 4) continue;
        final x = k % kHN, y = k ~/ kHN;
        if (hFilled(g, x + 1, y) && hFilled(g, x - 1, y) && hFilled(g, x, y + 1) && hFilled(g, x, y - 1)) s += 3;
      }
    case 5:
      for (var k = 0; k < kHN * kHN; k++) {
        if (g[k] != 0) continue;
        final x = k % kHN, y = k ~/ kHN;
        if (hFilled(g, x + 1, y) && hFilled(g, x - 1, y) && hFilled(g, x, y + 1) && hFilled(g, x, y - 1)) s++;
      }
    case 6:
      for (var y = 0; y < kHN; y++) {
        var mask = 0;
        for (var x = 0; x < kHN; x++) {
          final t = g[y * kHN + x];
          if (t >= 0 && t <= 3) mask |= 1 << t;
        }
        var c = 0;
        for (var b = 0; b < 4; b++) {
          if (mask & (1 << b) != 0) c++;
        }
        if (c >= 3) s += 2;
      }
    default:
      for (var k = 0; k < kHN * kHN; k++) {
        if (g[k] != 1) continue;
        final x = k % kHN, y = k ~/ kHN;
        if (_at(g, x + 1, y) == 0 || _at(g, x - 1, y) == 0 || _at(g, x, y + 1) == 0 || _at(g, x, y - 1) == 0) s++;
      }
  }
  return s;
}

/// [season] mevsiminin iki hedefi (puzzle.goals içindeki sıralar).
(int, int) hActive(HPuzzle z, int season) => (z.goals[season % 4], z.goals[(season + 1) % 4]);

int hSeasonScore(HPuzzle z, List<int> g, int season) {
  final (a, b) = hActive(z, season);
  return hGoal(g, a) + hGoal(g, b);
}

/// Bir mevsimin kartları: deste sırasıyla, zaman sınırı dolana dek.
List<int> hSeasonCards(HPuzzle z, int season, int extraTime) {
  final out = <int>[];
  var t = 0;
  for (final c in z.decks[season]) {
    if (t >= kHLimits[season] + extraTime) break;
    out.add(c);
    t += kHCards[c].$1;
  }
  return out;
}

List<int> hStartGrid(HPuzzle z) {
  final g = List<int>.filled(kHN * kHN, -1);
  for (final m in z.mountains) {
    g[m] = 4;
  }
  return g;
}

/// En iyi yerleştirme: (seçenek, yön, x, y, arazi); seçenek -1 tek kare.
(int, int, int, int, int) hBest(HPuzzle z, List<int> g, int season, int card) {
  final (a, b) = hActive(z, season);
  final (c1, c2) = hActive(z, season + 1);
  final last = season == 3;
  double eval() {
    final now = hGoal(g, a) + hGoal(g, b);
    if (last) return now.toDouble();
    return now + 0.5 * (hGoal(g, c1) + hGoal(g, c2));
  }

  var best = (-1, 0, -1, -1, 0);
  var bv = -1.0;
  final opts = kHCards[card].$2;
  for (var oi = 0; oi < opts.length; oi++) {
    final (shape, terr) = opts[oi];
    final os = _hUnique[shape];
    for (var r = 0; r < os.length; r++) {
      final o = os[r];
      for (var ay = 0; ay < kHN; ay++) {
        for (var ax = 0; ax < kHN; ax++) {
          if (!hFits(g, o, ax, ay)) continue;
          for (final (x, y) in o) {
            g[(ay + y) * kHN + ax + x] = terr;
          }
          final v = eval();
          for (final (x, y) in o) {
            g[(ay + y) * kHN + ax + x] = -1;
          }
          if (v > bv) {
            bv = v;
            best = (oi, r, ax, ay, terr);
          }
        }
      }
    }
  }
  if (best.$3 >= 0) return best;
  // Hiçbir biçim sığmıyorsa: tek kare, istenen arazi.
  for (var k = 0; k < kHN * kHN; k++) {
    if (g[k] != -1) continue;
    for (var terr = 0; terr < 4; terr++) {
      g[k] = terr;
      final v = eval();
      g[k] = -1;
      if (v > bv) {
        bv = v;
        best = (-1, 0, k % kHN, k ~/ kHN, terr);
      }
    }
  }
  return best;
}

void hPlace(List<int> g, (int, int, int, int, int) mv, int card) {
  final (oi, r, ax, ay, terr) = mv;
  if (ax < 0) return;
  final o = oi < 0 ? _hAll[kHSingle][0] : _hUnique[kHCards[card].$2[oi].$1][r];
  for (final (x, y) in o) {
    g[(ay + y) * kHN + ax + x] = terr;
  }
}

/// Yapay zekânın toplam puanı.
int hBot(HPuzzle z) {
  final g = hStartGrid(z);
  var total = 0;
  for (var s = 0; s < 4; s++) {
    for (final c in hSeasonCards(z, s, 0)) {
      hPlace(g, hBest(z, g, s, c), c);
    }
    total += hSeasonScore(z, g, s);
  }
  return total;
}

class HaritaKind extends StratejiKind {
  @override
  String get id => 'harita';
  const HaritaKind();

  @override
  SPuzzle? make(int d, SeededRandom r) {
    final nm = 4 + d ~/ 3;
    final ms = <int>[];
    var guard = 0;
    while (ms.length < nm && guard++ < 500) {
      final x = r.range(1, kHN - 2), y = r.range(1, kHN - 2);
      final k = y * kHN + x;
      if (ms.any((m) => (m % kHN - x).abs() + (m ~/ kHN - y).abs() < 3)) continue;
      ms.add(k);
    }
    if (ms.length < nm) return null;
    final goals = [for (var i = 0; i < kHGoals.length; i++) i];
    r.shuffle(goals);
    final decks = <List<int>>[];
    for (var s = 0; s < 4; s++) {
      final dk = [for (var i = 0; i < kHCards.length; i++) i];
      r.shuffle(dk);
      decks.add(dk);
    }
    final z0 = HPuzzle(r.nextUint32(), d, ms, goals.take(4).toList(), decks, 0, 0);
    final best = hBot(z0);
    final target = (best * (0.70 + 0.02 * d)).floor();
    if (target < 10) return null;
    return HPuzzle(z0.seed, d, ms, z0.goals, decks, best, target);
  }

  @override
  bool check(SPuzzle p) => p is HPuzzle && p.best >= p.target && p.target >= 10 && hBot(p) == p.best;

  @override
  List<Perk> get perks => const [
        Perk(3, Icons.undo, 'undo', 1),
        Perk(8, Icons.hourglass_top, 'hd_time', 1),
        Perk(15, Icons.crop_square, 'hd_single', 1),
        Perk(25, Icons.visibility, 'hd_peek', 0),
        Perk(40, Icons.star, 'hd_bonus', 3),
      ];

  @override
  List<GameStat> get stats => const [
        GameStat('runs_won', 'Tamamlanan harita', 'Maps completed', scale: 10),
        GameStat('flawless', 'Üç yıldızlı harita', 'Three-star maps', scale: 10),
        GameStat('shapes', 'Çizilen biçim', 'Shapes drawn', scale: 100),
      ];

  @override
  Widget build(StratejiPlay play) => _HView(play: play);
}

class _HSnap {
  final List<int> g;
  final int season, pos, time;
  final List<int> scores;
  const _HSnap(this.g, this.season, this.pos, this.time, this.scores);
}

class _HView extends StatefulWidget {
  final StratejiPlay play;
  const _HView({required this.play});
  @override
  State<_HView> createState() => _HViewState();
}

class _HViewState extends State<_HView> with Clock, MetaLoader {
  late List<int> g;
  int season = 0, pos = 0, time = 0;
  List<int> scores = [];
  int opt = 0, rot = 0;
  bool flip = false;
  int? anchor;
  int fallbackTerr = 0;
  bool singleMode = false;
  int undos = 0, singles = 0, extraTime = 0;
  int shapes = 0, hints = 0;
  int goalInfo = -1;
  final List<_HSnap> history = [];

  StratejiPlay get p => widget.play;
  HPuzzle get z => p.puzzle as HPuzzle;

  void _applyPerks() {
    undos = p.has(usta, 0) ? 1 : 0;
    extraTime = p.has(usta, 1) ? 1 : 0;
    singles = p.has(usta, 2) ? 1 : 0;
  }

  @override
  void initState() {
    super.initState();
    g = hStartGrid(z);
    startClock();
    loadMeta(p.gameId, _applyPerks);
  }

  int get limit => season < 4 ? kHLimits[season] + extraTime : 0;
  int get card => z.decks[season][pos];
  bool get canAny {
    for (final (shape, _) in kHCards[card].$2) {
      for (final o in _hUnique[shape]) {
        for (var k = 0; k < kHN * kHN; k++) {
          if (hFits(g, o, k % kHN, k ~/ kHN)) return true;
        }
      }
    }
    return false;
  }

  bool get fallback => !singleMode && !canAny;

  /// Seçili biçimin geçerli yönü.
  List<(int, int)> get orient {
    if (singleMode || fallback) return _hAll[kHSingle][0];
    final shape = kHCards[card].$2[opt].$1;
    return _hAll[shape][(flip ? 4 : 0) + rot];
  }

  int get terrain {
    if (fallback) return fallbackTerr;
    return kHCards[card].$2[opt].$2;
  }

  /// Dokunulan kareye göre gölge kareleri (biçimin ortasına en yakın kare dokunulan kareye gelir).
  List<int>? ghost() {
    final a = anchor;
    if (a == null) return null;
    final o = orient;
    final cx = o.map((c) => c.$1).reduce((x, y) => x + y) / o.length;
    final cy = o.map((c) => c.$2).reduce((x, y) => x + y) / o.length;
    var piv = o.first;
    var bd = 1e9;
    for (final c in o) {
      final dd = (c.$1 - cx) * (c.$1 - cx) + (c.$2 - cy) * (c.$2 - cy);
      if (dd < bd) {
        bd = dd;
        piv = c;
      }
    }
    final ax = a % kHN - piv.$1, ay = a ~/ kHN - piv.$2;
    return [for (final (x, y) in o) (ax + x < 0 || ay + y < 0 || ax + x >= kHN || ay + y >= kHN) ? -1 : (ay + y) * kHN + ax + x];
  }

  bool ghostOk(List<int>? gh) => gh != null && gh.every((k) => k >= 0 && g[k] == -1);

  void _tap(Offset o) {
    if (ended) return;
    final x = (o.dx / 10).floor(), y = (o.dy / 10).floor();
    if (x < 0 || y < 0 || x >= kHN || y >= kHN) return;
    final k = y * kHN + x;
    setState(() {
      if (anchor == k && ghostOk(ghost())) {
        _place();
      } else {
        anchor = k;
      }
    });
    p.sfx(Sfx.tap);
  }

  void _snap() => history.add(_HSnap([...g], season, pos, time, [...scores]));

  void _place() {
    final gh = ghost();
    if (ended || !ghostOk(gh)) {
      p.sfx(Sfx.error);
      return;
    }
    started = true;
    _snap();
    for (final k in gh!) {
      g[k] = terrain;
    }
    shapes++;
    anchor = null;
    if (singleMode) {
      singleMode = false;
      singles--;
      p.sfx(Sfx.place);
      return;
    }
    time += kHCards[card].$1;
    pos++;
    rot = 0;
    flip = false;
    opt = 0;
    if (time >= limit || pos >= z.decks[season].length) {
      scores.add(hSeasonScore(z, g, season));
      p.sfx(Sfx.combo);
      season++;
      pos = 0;
      time = 0;
      if (season >= 4) {
        _finish();
        return;
      }
    } else {
      p.sfx(Sfx.place);
    }
  }

  int get total => scores.fold<int>(0, (a, b) => a + b) + (p.has(usta, 4) ? 3 : 0);

  void _finish() {
    ended = true;
    final sc = total;
    final two = z.target + math.max<int>(1, (z.best - z.target) ~/ 2);
    if (sc >= z.target) {
      p.sfx(Sfx.win);
      final stars = (sc >= z.best ? 3 : (sc >= two ? 2 : 1)) - (hints > 0 ? 1 : 0);
      later(600, () => p.win(score: sc * 10 + p.d * 20, stars: stars, seconds: seconds, moves: shapes, hints: hints, stats: {'shapes': shapes}));
    } else {
      p.sfx(Sfx.lose);
      later(700, () => p.lose(score: sc * 10, seconds: seconds, moves: shapes, stats: {'shapes': shapes}));
    }
  }

  void _undo() {
    if (ended || undos <= 0 || history.isEmpty) return;
    final h = history.removeLast();
    setState(() {
      undos--;
      g = h.g;
      season = h.season;
      pos = h.pos;
      time = h.time;
      scores = h.scores;
      anchor = null;
    });
    p.sfx(Sfx.tap);
  }

  Future<void> _hint() async {
    if (ended) return;
    final ok = await p.ctx.requestHint();
    if (!ok || !mounted) return;
    final mv = hBest(z, [...g], season, card);
    setState(() {
      hints++;
      singleMode = false;
      if (mv.$1 < 0) {
        fallbackTerr = mv.$5;
        anchor = mv.$4 * kHN + mv.$3;
        return;
      }
      opt = mv.$1;
      final shape = kHCards[card].$2[opt].$1;
      final uo = _hUnique[shape][mv.$2];
      final key = uo.map((c) => '${c.$1},${c.$2}').join(';');
      final idx = _hAll[shape].indexWhere((o) => o.map((c) => '${c.$1},${c.$2}').join(';') == key);
      flip = idx >= 4;
      rot = idx % 4;
      // Gölgenin dokunma noktası: yerleşimin pivot karesi.
      final o = orient;
      final cx = o.map((c) => c.$1).reduce((x, y) => x + y) / o.length;
      final cy = o.map((c) => c.$2).reduce((x, y) => x + y) / o.length;
      var piv = o.first;
      var bd = 1e9;
      for (final c in o) {
        final dd = (c.$1 - cx) * (c.$1 - cx) + (c.$2 - cy) * (c.$2 - cy);
        if (dd < bd) {
          bd = dd;
          piv = c;
        }
      }
      anchor = (mv.$4 + piv.$2) * kHN + mv.$3 + piv.$1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = p.lang;
    final (a, b) = season < 4 ? hActive(z, season) : (-1, -1);
    final gh = ghost();
    final ok = ghostOk(gh);
    return SScreen(
      bar: SBar(
        lang: lang,
        left: season < 4 ? st(lang, ['km_spring', 'km_summer', 'km_autumn', 'km_winter'][season]) : '',
        status: '${st(lang, 'score')} $total · ${st(lang, 'target')} ${z.target} · ★★★ ${z.best}',
        onHint: ended ? null : _hint,
        onUndo: undos > 0 && history.isNotEmpty && !ended ? _undo : null,
        extra: [
          if (singles > 0 && !ended)
            IconButton(
              tooltip: st(lang, 'hd_single'),
              onPressed: () => setState(() {
                singleMode = !singleMode;
                anchor = null;
              }),
              icon: Icon(Icons.crop_square, color: singleMode ? SColors.accent : null),
            ),
        ],
      ),
      top: Column(mainAxisSize: MainAxisSize.min, children: [
        PerkStrip(lang: lang, perks: p.perks, usta: usta),
        const SizedBox(height: 6),
        Row(children: [
          for (var i = 0; i < 4; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: SChip(
                  selected: z.goals[i] == a || z.goals[i] == b,
                  tooltip: st(lang, '${kHGoals[z.goals[i]]}D'),
                  onTap: () => setState(() => goalInfo = goalInfo == i ? -1 : i),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                      Text(String.fromCharCode(65 + i), style: const TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(width: 2),
                      Icon(kHGoalIcons[z.goals[i]], size: 16),
                    ]),
                    Text('${hGoal(g, z.goals[i])}', style: const TextStyle(fontSize: 11)),
                  ]),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 4),
        SizedBox(
          height: 34,
          child: Center(
            child: Text(
              goalInfo >= 0 ? '${st(lang, kHGoals[z.goals[goalInfo]])}: ${st(lang, '${kHGoals[z.goals[goalInfo]]}D')}' : '${st(lang, 'hd_time')} $time/$limit · ${scores.isEmpty ? '' : scores.join(' + ')}',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
      ]),
      board: TapCanvas(w: kHN * 10.0, h: kHN * 10.0, paint: (c) => _paint(c, gh, ok), onTap: _tap, semantics: st(lang, 'hd_title')),
      bottom: ended || season >= 4 ? null : _controls(lang, ok),
    );
  }

  Widget _mini(List<(int, int)> o, Color col) => SizedBox(
        width: 34,
        height: 34,
        child: CustomPaint(painter: _MiniShape(o, col)),
      );

  Widget _controls(String lang, bool ok) {
    final cd = kHCards[card];
    final next = pos + 1 < z.decks[season].length ? z.decks[season][pos + 1] : -1;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.hourglass_bottom, size: 16, color: SColors.gold),
        Text(' ${cd.$1}  ', style: const TextStyle(fontWeight: FontWeight.w700)),
        if (fallback)
          for (var t = 0; t < 4; t++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: SChip(
                selected: fallbackTerr == t,
                tooltip: st(lang, kHTerrain[t]),
                onTap: () => setState(() => fallbackTerr = t),
                child: Icon(kHIcons[t], color: kHColors[t]),
              ),
            )
        else
          for (var i = 0; i < cd.$2.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SChip(
                selected: opt == i && !singleMode,
                tooltip: st(lang, kHTerrain[cd.$2[i].$2]),
                onTap: () => setState(() {
                  opt = i;
                  rot = 0;
                  flip = false;
                  singleMode = false;
                }),
                child: _mini(_hAll[cd.$2[i].$1][0], kHColors[cd.$2[i].$2]),
              ),
            ),
        if (p.has(usta, 3) && next >= 0) ...[
          const SizedBox(width: 8),
          Opacity(opacity: 0.55, child: _mini(_hAll[kHCards[next].$2[0].$1][0], kHColors[kHCards[next].$2[0].$2])),
        ],
      ]),
      const SizedBox(height: 6),
      Row(children: [
        IconButton(tooltip: st(lang, 'hd_rotate'), onPressed: () => setState(() => rot = (rot + 1) % 4), icon: const Icon(Icons.rotate_right)),
        IconButton(tooltip: st(lang, 'hd_flip'), onPressed: () => setState(() => flip = !flip), icon: const Icon(Icons.flip)),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: ok ? () => setState(_place) : null,
            icon: const Icon(Icons.check),
            label: FittedBox(fit: BoxFit.scaleDown, child: Text(st(lang, 'hd_place'))),
          ),
        ),
      ]),
    ]);
  }

  void _paint(Canvas c, List<int>? gh, bool ok) {
    c.drawRect(const Rect.fromLTWH(0, 0, kHN * 10.0, kHN * 10.0), fill(const Color(0xFFF2EAD8)));
    for (var k = 0; k < kHN * kHN; k++) {
      final x = k % kHN, y = k ~/ kHN;
      final r = Rect.fromLTWH(x * 10.0, y * 10.0, 10, 10);
      final t = g[k];
      if (t >= 0) {
        c.drawRRect(RRect.fromRectAndRadius(r.deflate(0.4), const Radius.circular(1.2)), fill(kHColors[t]));
        _glyph(c, r.center, t);
      }
      c.drawRect(r, stroke(const Color(0x33000000), 0.25));
    }
    if (gh != null) {
      for (final k in gh) {
        if (k < 0) continue;
        final r = Rect.fromLTWH((k % kHN) * 10.0, (k ~/ kHN) * 10.0, 10, 10);
        c.drawRect(r.deflate(0.6), fill((ok ? kHColors[terrain] : SColors.bad).withValues(alpha: 0.55)));
        c.drawRect(r.deflate(0.6), stroke(ok ? SColors.ink : SColors.bad, 0.6));
      }
    }
  }

  void _glyph(Canvas c, Offset o, int t) {
    final w = stroke(const Color(0xCCFFFFFF), 0.6);
    switch (t) {
      case 0:
        final path = Path()
          ..moveTo(o.dx, o.dy - 3)
          ..lineTo(o.dx + 2.4, o.dy + 1.5)
          ..lineTo(o.dx - 2.4, o.dy + 1.5)
          ..close();
        c.drawPath(path, w);
        c.drawLine(o + const Offset(0, 1.5), o + const Offset(0, 3), w);
      case 1:
        final path = Path()
          ..moveTo(o.dx - 2.5, o.dy + 2.5)
          ..lineTo(o.dx - 2.5, o.dy - 0.5)
          ..lineTo(o.dx, o.dy - 2.8)
          ..lineTo(o.dx + 2.5, o.dy - 0.5)
          ..lineTo(o.dx + 2.5, o.dy + 2.5)
          ..close();
        c.drawPath(path, w);
      case 2:
        for (var i = -2; i <= 2; i += 2) {
          c.drawLine(o + Offset(i.toDouble(), 2.5), o + Offset(i.toDouble(), -2.5), w);
        }
      case 3:
        c.drawLine(o + const Offset(-3, -1), o + const Offset(3, -1), w);
        c.drawLine(o + const Offset(-2, 1.5), o + const Offset(2, 1.5), w);
      default:
        final path = Path()
          ..moveTo(o.dx - 3.5, o.dy + 3)
          ..lineTo(o.dx - 0.5, o.dy - 3)
          ..lineTo(o.dx + 1.2, o.dy)
          ..lineTo(o.dx + 2, o.dy - 1.5)
          ..lineTo(o.dx + 3.5, o.dy + 3)
          ..close();
        c.drawPath(path, fill(const Color(0xFF6E655D)));
    }
  }
}

class _MiniShape extends CustomPainter {
  final List<(int, int)> o;
  final Color color;
  _MiniShape(this.o, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final mx = o.map((c) => c.$1).reduce(math.max) + 1;
    final my = o.map((c) => c.$2).reduce(math.max) + 1;
    final cell = math.min<double>(size.width / math.max<int>(mx, 3), size.height / math.max<int>(my, 3));
    final ox = (size.width - mx * cell) / 2, oy = (size.height - my * cell) / 2;
    for (final (x, y) in o) {
      final r = Rect.fromLTWH(ox + x * cell, oy + y * cell, cell, cell).deflate(0.8);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(2)), Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniShape old) => old.o != o || old.color != color;
}

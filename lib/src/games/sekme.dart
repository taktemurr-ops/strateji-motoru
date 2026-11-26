import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../studio_chrome.dart';
import '../texts.dart';

/// Top Sekme Zindanı: alttan nişan alınıp atılan toplar duvarlardan ve taş
/// muhafızlardan sekerek onları yontar. Her atıştan sonra muhafızlar bir sıra
/// iner; alta varan muhafız bir kalp götürür. Kat bitince üç geliştirmeden
/// biri seçilir. Şans ya da kumar öğesi yok: her şey tohumdan belirlenir.
const int kTsCols = 7, kTsRows = 10;
const double kTsW = 100, kTsH = 140;
const double kTsCw = kTsW / kTsCols, kTsCh = 10;
const double kTsLaunchY = 134;
const double kTsStep = 1.2;

const List<String> kTsUpKeys = ['ts_ball', 'ts_dmg', 'ts_heart', 'ts_fire'];
const List<IconData> kTsUpIcons = [Icons.sports_baseball, Icons.bolt, Icons.favorite, Icons.local_fire_department];

class TsPuzzle extends SPuzzle {
  final int seed, d;

  /// Katlar: her kat sıralardan oluşur, sıra = 7 hücrelik can listesi (0 boş).
  final List<List<List<int>>> floors;
  const TsPuzzle(this.seed, this.d, this.floors);
}

class TsBall {
  double x, y, vx, vy;
  final double dmg;
  bool done = false;
  TsBall(this.x, this.y, this.vx, this.vy, this.dmg);
}

class TsRun {
  final TsPuzzle z;
  int floor = 0, hearts, balls, dmg, fire = 0;

  /// Tahta: satır * 7 + sütun -> kalan can.
  List<int> grid = List<int>.filled(kTsCols * kTsRows, 0);
  int fed = 0; // bu kattan inen sıra sayısı
  int shots = 0, broken = 0;
  List<int> offer = const [];
  final List<TsBall> flying = [];
  int toLaunch = 0;
  double launchT = 0, angle = 0;

  TsRun(this.z, {this.hearts = 3, this.balls = 3, this.dmg = 1, int fire = 0}) {
    this.fire = fire;
    _feed();
    _feed();
  }

  bool get won => floor >= z.floors.length;
  bool get lost => hearts <= 0;
  bool get over => won || lost;
  bool get busy => flying.isNotEmpty || toLaunch > 0;
  bool get choosing => offer.isNotEmpty;
  List<List<int>> get rows => z.floors[math.min(floor, z.floors.length - 1)];
  bool get floorClear => fed >= rows.length && !grid.any((v) => v > 0);

  void _feed() {
    if (won || fed >= rows.length) return;
    final row = rows[fed++];
    for (var c = 0; c < kTsCols; c++) {
      grid[c] = row[c];
    }
  }

  /// Bütün sıralar bir iner; en alttan taşan muhafız kalp götürür.
  void _descend() {
    for (var c = 0; c < kTsCols; c++) {
      if (grid[(kTsRows - 1) * kTsCols + c] > 0) hearts--;
    }
    for (var r = kTsRows - 1; r > 0; r--) {
      for (var c = 0; c < kTsCols; c++) {
        grid[r * kTsCols + c] = grid[(r - 1) * kTsCols + c];
      }
    }
    for (var c = 0; c < kTsCols; c++) {
      grid[c] = 0;
    }
    _feed();
  }

  int cellAt(double x, double y) {
    if (x < 0 || x >= kTsW || y < 0 || y >= kTsRows * kTsCh) return -1;
    return (y ~/ kTsCh) * kTsCols + (x ~/ kTsCw);
  }

  void _hit(int i, double d) {
    final before = grid[i];
    grid[i] = math.max(0, before - d.round());
    if (before > 0 && grid[i] == 0) broken++;
  }

  /// Atış: [a] radyan (yukarı doğru, 0.15..pi-0.15).
  bool shoot(double a) {
    if (over || busy || choosing) return false;
    angle = clampD(a, 0.15, math.pi - 0.15);
    toLaunch = balls;
    launchT = 0;
    shots++;
    return true;
  }

  /// Toplar bir adım ilerler; atış bitince sıra iner.
  void tick() {
    if (toLaunch > 0) {
      launchT -= 1;
      if (launchT <= 0) {
        final first = toLaunch == balls;
        flying.add(TsBall(kTsW / 2, kTsLaunchY, math.cos(angle), -math.sin(angle), dmg + (first ? fire * 2 : 0).toDouble()));
        toLaunch--;
        launchT = 6;
      }
    }
    for (final b in flying) {
      if (b.done) continue;
      var nx = b.x + b.vx * kTsStep, ny = b.y + b.vy * kTsStep;
      if (nx < 0 || nx >= kTsW) {
        b.vx = -b.vx;
        nx = b.x + b.vx * kTsStep;
      }
      if (ny < 0) {
        b.vy = -b.vy;
        ny = b.y + b.vy * kTsStep;
      }
      final cx = cellAt(nx, b.y);
      if (cx >= 0 && grid[cx] > 0) {
        _hit(cx, b.dmg);
        b.vx = -b.vx;
        nx = b.x;
      }
      final cy = cellAt(b.x, ny);
      if (cy >= 0 && grid[cy] > 0) {
        _hit(cy, b.dmg);
        b.vy = -b.vy;
        ny = b.y;
      }
      b.x = nx;
      b.y = ny;
      if (b.y > kTsLaunchY + 2) b.done = true;
      // Neredeyse yatay sekmeler sonsuza dek sürmesin.
      if (b.vy.abs() < 0.12) b.vy = b.vy < 0 ? -0.12 : 0.12;
    }
    flying.removeWhere((b) => b.done);
    if (!busy && shots > 0) _afterVolley();
  }

  bool _settled = true;

  void _afterVolley() {
    if (_settled) return;
    _settled = true;
    if (floorClear) {
      floor++;
      if (!won) offer = _offerFor(floor);
      grid = List<int>.filled(kTsCols * kTsRows, 0);
      fed = 0;
      if (!won) {
        _feed();
        _feed();
      }
    } else {
      _descend();
    }
  }

  /// Atışı başlatıp bitene kadar oynatır (bot ve hızlı ileri).
  void volley(double a) {
    if (!shoot(a)) return;
    _settled = false;
    for (var guard = 0; guard < 6000 && busy; guard++) {
      tick();
    }
    if (busy) {
      flying.clear();
      toLaunch = 0;
    }
    _afterVolley();
  }

  /// Ekran için: atışı başlatır, adımları dışarıdan [tick] ilerletir.
  bool start(double a) {
    final ok = shoot(a);
    if (ok) _settled = false;
    return ok;
  }

  List<int> _offerFor(int f) {
    final r = SeededRandom(mixSeed([z.seed, f, 3301]));
    final pool = [0, 1, 2, 3];
    r.shuffle(pool);
    return pool.take(3).toList();
  }

  void choose(int u) {
    if (!offer.contains(u)) return;
    if (u == 0) balls++;
    if (u == 1) dmg++;
    if (u == 2) hearts++;
    if (u == 3) fire++;
    offer = const [];
  }

  TsRun copy() {
    final c = TsRun._blank(z);
    c.floor = floor;
    c.hearts = hearts;
    c.balls = balls;
    c.dmg = dmg;
    c.fire = fire;
    c.grid = List<int>.of(grid);
    c.fed = fed;
    return c;
  }

  TsRun._blank(this.z)
      : hearts = 0,
        balls = 0,
        dmg = 0;

  int get pressure {
    var p = 0;
    for (var i = 0; i < grid.length; i++) {
      if (grid[i] > 0) p += grid[i] * (1 + i ~/ kTsCols);
    }
    return p;
  }
}

/// Botun nişanı: 15 açı dener, alt sıraları en çok yontanı seçer.
double tsBotAim(TsRun s) {
  var best = math.pi / 2, bv = 1 << 30;
  for (var k = 0; k < 15; k++) {
    final a = 0.25 + k * (math.pi - 0.5) / 14;
    final c = s.copy();
    c.volley(a);
    final v = c.pressure - c.hearts * 1000 + (c.floor > s.floor ? -100000 : 0);
    if (v < bv) {
      bv = v;
      best = a;
    }
  }
  return best;
}

const List<int> kTsBotPref = [0, 1, 3, 2];

/// Botun kalan kalbi (0: kaybetti).
int tsBot(TsPuzzle z) {
  final s = TsRun(z);
  for (var guard = 0; guard < 400 && !s.over; guard++) {
    if (s.choosing) {
      var b = s.offer.first;
      for (final u in s.offer) {
        if (kTsBotPref.indexOf(u) < kTsBotPref.indexOf(b)) b = u;
      }
      s.choose(b);
      continue;
    }
    s.volley(tsBotAim(s));
  }
  return s.won ? s.hearts : 0;
}

class SekmeKind extends StratejiKind {
  @override
  String get id => 'sekme';
  const SekmeKind();

  @override
  SPuzzle? make(int d, SeededRandom r) {
    final nf = 2 + (d + 1) ~/ 3;
    final floors = <List<List<int>>>[];
    for (var f = 0; f < nf; f++) {
      final rows = <List<int>>[];
      for (var k = 0; k < 4 + d ~/ 2 + f; k++) {
        final row = List<int>.filled(kTsCols, 0);
        final n = 2 + r.nextInt(3 + d ~/ 4);
        for (var j = 0; j < n; j++) {
          row[r.nextInt(kTsCols)] = 1 + r.nextInt(2 + d ~/ 2 + f + k ~/ 2);
        }
        rows.add(row);
      }
      floors.add(rows);
    }
    final z = TsPuzzle(r.nextInt(1 << 30), d, floors);
    return tsBot(z) >= 1 ? z : null;
  }

  @override
  bool check(SPuzzle p) => p is TsPuzzle && p.floors.isNotEmpty && tsBot(p) >= 1;

  @override
  Widget build(StratejiPlay play) => _TsView(play: play);

  @override
  List<Perk> get perks => const [
        Perk(3, Icons.sports_baseball, 'ts_ball', 1),
        Perk(8, Icons.favorite, 'ts_heart', 1),
        Perk(15, Icons.bolt, 'ts_dmg', 1),
        Perk(25, Icons.local_fire_department, 'ts_fire', 1),
        Perk(40, Icons.sports_baseball, 'ts_ball', 1),
      ];

  @override
  List<GameStat> get stats => [
        ...super.stats,
        const GameStat('guards_broken', 'Yontulan muhafız', 'Guards broken', scale: 100),
      ];
}

class _TsView extends StatefulWidget {
  final StratejiPlay play;
  const _TsView({required this.play});
  @override
  State<_TsView> createState() => _TsViewState();
}

class _TsViewState extends State<_TsView> with Clock, MetaLoader {
  late TsRun s;
  Timer? loop;
  Offset? aim;
  int hints = 0;

  StratejiPlay get p => widget.play;
  TsPuzzle get z => p.puzzle as TsPuzzle;
  String get lang => p.lang;

  TsRun _fresh() => TsRun(z,
      balls: 3 + (p.has(usta, 0) ? 1 : 0) + (p.has(usta, 4) ? 1 : 0),
      hearts: 3 + (p.has(usta, 1) ? 1 : 0),
      dmg: 1 + (p.has(usta, 2) ? 1 : 0),
      fire: p.has(usta, 3) ? 1 : 0);

  @override
  void initState() {
    super.initState();
    s = _fresh();
    startClock();
    loadMeta(p.gameId, () => s = _fresh());
    loop = Timer.periodic(const Duration(milliseconds: 16), (_) => _frame());
  }

  @override
  void dispose() {
    loop?.cancel();
    super.dispose();
  }

  void _frame() {
    if (!mounted || ended || !s.busy) return;
    final h0 = s.hearts, b0 = s.broken, f0 = s.floor;
    setState(() {
      for (var i = 0; i < 4 && s.busy; i++) {
        s.tick();
      }
    });
    if (s.broken > b0) p.sfx(Sfx.clear);
    if (s.hearts < h0) p.sfx(Sfx.error);
    if (s.floor > f0) p.sfx(Sfx.unlock);
    if (s.over) _end();
  }

  double _angleTo(Offset o) => math.atan2(kTsLaunchY - o.dy, o.dx - kTsW / 2);

  void _fire(Offset o) {
    if (ended || s.busy || s.choosing) return;
    final a = _angleTo(o);
    if (a < 0.1 || a > math.pi - 0.1) return;
    started = true;
    if (s.start(a)) p.sfx(Sfx.tap);
    setState(() => aim = null);
  }

  void _hint() {
    if (ended || s.busy || s.choosing) return;
    hints++;
    final a = tsBotAim(s);
    setState(() => aim = Offset(kTsW / 2 + math.cos(a) * 40, kTsLaunchY - math.sin(a) * 40));
  }

  void _end() {
    if (ended) return;
    ended = true;
    if (s.won) {
      p.sfx(Sfx.win);
      later(400, () => p.win(score: s.broken * 15 + s.hearts * 60 + z.d * 30, stars: s.hearts >= 3 ? 3 : (s.hearts == 2 ? 2 : 1),
          seconds: seconds, moves: s.shots, hints: hints, stats: {'guards_broken': s.broken}));
    } else {
      p.sfx(Sfx.lose);
      later(500, () => p.lose(score: s.broken * 15, seconds: seconds, moves: s.shots, stats: {'guards_broken': s.broken}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final board = TapCanvas(
      w: kTsW,
      h: kTsH,
      paint: _paint,
      semantics: st(lang, 'ts_title'),
      onPanStart: (o) => setState(() => aim = o),
      onPanUpdate: (o) => setState(() => aim = o),
      onPanEnd: () {
        final a = aim;
        if (a != null) _fire(a);
      },
      onTap: _fire,
    );
    return Stack(children: [
      SScreen(
        bar: SBar(
          lang: lang,
          left: '♥ ${s.hearts} · ● ${s.balls}',
          status: '${st(lang, 'floor')} ${math.min(s.floor + 1, z.floors.length)}/${z.floors.length} · ✦ ${s.broken}',
          onHint: ended ? null : _hint,
        ),
        top: PerkStrip(lang: lang, perks: p.perks, usta: usta),
        board: board,
      ),
      if (s.choosing && !ended)
        SPanel(title: st(lang, 'reward'), children: [
          for (final u in s.offer)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SizedBox(
                width: double.infinity,
                child: StudioButton(
                  onPressed: () => setState(() {
                    s.choose(u);
                    p.sfx(Sfx.place);
                  }),
                  icon: kTsUpIcons[u],
                  label: st(lang, kTsUpKeys[u]),
                ),
              ),
            ),
        ]),
    ]);
  }

  void _paint(Canvas c) {
    c.drawRect(const Rect.fromLTWH(0, 0, kTsW, kTsH), fill(const Color(0xFF2B2622)));
    for (var y = 0.0; y < kTsH; y += 8) {
      c.drawLine(Offset(0, y), Offset(kTsW, y), stroke(const Color(0x14FFFFFF), 0.3));
    }
    c.drawLine(const Offset(0, kTsRows * kTsCh), const Offset(kTsW, kTsRows * kTsCh), stroke(const Color(0x66C8553D), 0.6));
    for (var i = 0; i < s.grid.length; i++) {
      final v = s.grid[i];
      if (v <= 0) continue;
      final r = Rect.fromLTWH((i % kTsCols) * kTsCw + 0.6, (i ~/ kTsCols) * kTsCh + 0.6, kTsCw - 1.2, kTsCh - 1.2);
      final col = Color.lerp(const Color(0xFF8C9A7A), const Color(0xFF5B4E7A), clampD(v / 12, 0, 1))!;
      c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(1.6)), fill(col));
      drawLabel(c, '$v', r.center, 4.6, Colors.white);
    }
    for (final b in s.flying) {
      c.drawCircle(Offset(b.x, b.y), 1.3, fill(b.dmg > s.dmg ? const Color(0xFFFF8A3D) : const Color(0xFFF4F1EA)));
    }
    c.drawCircle(const Offset(kTsW / 2, kTsLaunchY), 2.4, fill(const Color(0xFFD9A441)));
    final a = aim;
    if (a != null && !s.busy) {
      final ang = _angleTo(a);
      if (ang > 0.1 && ang < math.pi - 0.1) {
        for (var k = 1; k < 12; k++) {
          c.drawCircle(Offset(kTsW / 2 + math.cos(ang) * k * 6, kTsLaunchY - math.sin(ang) * k * 6), 0.7, fill(const Color(0xAAFFFFFF)));
        }
      }
    }
  }
}

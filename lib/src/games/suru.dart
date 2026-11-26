import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../studio_chrome.dart';
import '../texts.dart';

/// Sürü Avcısı: kendiliğinden ateş eden fener taşıyıcısı, dalga dalga gelen
/// solan gölge yaratıklara karşı süre dolana kadar dayanır. Düşen ışık
/// kırıntıları seviye kazandırır; her seviyede üç yetenekten biri seçilir.
/// Kan yok: vurulan gölgeler ışığa dönüşüp söner.
const double kSuW = 100, kSuH = 140;
const double kSuDt = 0.1;

/// Gölge türleri: can, hız, temas hasarı, ışık değeri, yarıçap.
const List<(double, double, int, int, double)> kSuFoes = [
  (2, 15, 1, 1, 2.6), // kıvılcım gölgesi (hızlı, zayıf)
  (5, 10, 2, 2, 3.4), // gölge
  (14, 6.5, 3, 5, 5.0), // koca gölge (yavaş, dayanıklı)
];

/// Yetenekler.
const List<String> kSuSkillKeys = ['su_dmg', 'su_rate', 'su_multi', 'su_orb', 'su_aura', 'su_speed', 'su_heart', 'su_magnet'];
const List<IconData> kSuSkillIcons = [
  Icons.bolt, Icons.speed, Icons.call_split, Icons.blur_circular, Icons.wb_sunny, Icons.directions_run, Icons.favorite, Icons.attractions,
];

/// Botun yetenek önceliği.
const List<int> kSuBotPref = [2, 1, 0, 3, 4, 6, 5, 7];

class SuPuzzle extends SPuzzle {
  final int seed, d;
  final double duration;

  /// Doğma çizelgesi: (zaman, açı, tür).
  final List<(double, double, int)> spawns;
  final double foeHp;
  const SuPuzzle(this.seed, this.d, this.duration, this.spawns, this.foeHp);
}

class SuFoe {
  final int type;
  double x, y, hp, hitCd = 0;
  SuFoe(this.type, this.x, this.y, this.hp);
}

class SuShot {
  double x, y;
  final double vx, vy;
  double life;
  int pierce;
  final Set<SuFoe> hits = {};
  SuShot(this.x, this.y, this.vx, this.vy, this.life, this.pierce);
}

class SuGem {
  final double x, y;
  final int v;
  const SuGem(this.x, this.y, this.v);
}

class SuSim {
  final SuPuzzle z;
  double t = 0;
  double px = kSuW / 2, py = kSuH / 2;
  int hp, maxHp;
  final List<int> skill = List<int>.filled(8, 0);
  final List<SuFoe> foes = [];
  final List<SuShot> shots = [];
  final List<SuGem> gems = [];
  int next = 0;
  int xp = 0, level = 1, kills = 0;
  double fireCd = 0, orbA = 0;

  /// Seçilmeyi bekleyen yetenek teklifleri (seviye atlayınca dolar).
  List<int> offer = const [];
  int pending = 0;

  SuSim(this.z, {int extraHp = 0, List<int> startSkills = const []})
      : hp = 10 + extraHp,
        maxHp = 10 + extraHp {
    for (final s in startSkills) {
      skill[s]++;
    }
  }

  bool get won => t >= z.duration && hp > 0;
  bool get lost => hp <= 0;
  bool get over => won || lost;
  int get need => 4 + 3 * level;

  double get dmg => 2.0 + skill[0];
  double get rate => 0.6 * math.pow(0.82, skill[1]).toDouble();
  double get speed => 24.0 * (1 + 0.15 * skill[5]);
  double get magnet => 10.0 + 10 * skill[7];
  double get auraR => skill[4] == 0 ? 0 : 8.0 + 4 * skill[4];

  List<int> _offerFor(int lv) {
    final r = SeededRandom(mixSeed([z.seed, lv, 4411]));
    final pool = [for (var i = 0; i < 8; i++) i];
    r.shuffle(pool);
    return pool.take(3).toList();
  }

  void choose(int s) {
    if (pending <= 0 || !offer.contains(s)) return;
    skill[s]++;
    if (s == 6) {
      maxHp += 4;
      hp = math.min(maxHp, hp + 4);
    }
    pending--;
    offer = pending > 0 ? _offerFor(level - pending + 1) : const [];
  }

  SuFoe? _nearest() {
    SuFoe? best;
    var bd = 1e18;
    for (final f in foes) {
      final d = (f.x - px) * (f.x - px) + (f.y - py) * (f.y - py);
      if (d < bd) {
        bd = d;
        best = f;
      }
    }
    return best;
  }

  void _hurt(SuFoe f, double v) {
    f.hp -= v;
  }

  /// [dx],[dy]: hareket yönü (birim ya da sıfır). Seçim bekleniyorsa durur.
  void step(double dx, double dy) {
    if (over || pending > 0) return;
    const dt = kSuDt;
    // hareket
    final len = math.sqrt(dx * dx + dy * dy);
    if (len > 0.01) {
      px = clampD(px + dx / len * speed * dt, 3, kSuW - 3);
      py = clampD(py + dy / len * speed * dt, 3, kSuH - 3);
    }
    // doğma
    while (next < z.spawns.length && z.spawns[next].$1 <= t) {
      final (_, a, ty) = z.spawns[next];
      final x = kSuW / 2 + math.cos(a) * 80, y = kSuH / 2 + math.sin(a) * 95;
      foes.add(SuFoe(ty, clampD(x, -4, kSuW + 4), clampD(y, -4, kSuH + 4), kSuFoes[ty].$1 * z.foeHp));
      next++;
    }
    // gölgeler yaklaşır ve dokunursa ışığı söndürür
    for (final f in foes) {
      final (_, sp, hit, _, rad) = kSuFoes[f.type];
      final ex = px - f.x, ey = py - f.y;
      final d = math.sqrt(ex * ex + ey * ey);
      if (d > 0.01) {
        f.x += ex / d * sp * dt;
        f.y += ey / d * sp * dt;
      }
      f.hitCd -= dt;
      if (d < rad + 2.5 && f.hitCd <= 0) {
        hp -= hit;
        f.hitCd = 0.9;
      }
    }
    // ateş
    fireCd -= dt;
    if (fireCd <= 0) {
      final n = _nearest();
      if (n != null) {
        fireCd = rate;
        final base = math.atan2(n.y - py, n.x - px);
        final k = 1 + skill[2];
        for (var i = 0; i < k; i++) {
          final a = base + (i - (k - 1) / 2) * 0.22;
          shots.add(SuShot(px, py, math.cos(a) * 70, math.sin(a) * 70, 1.1, skill[0] ~/ 2));
        }
      }
    }
    for (final s in shots) {
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.life -= dt;
      for (final f in foes) {
        if (s.life <= 0 || f.hp <= 0 || s.hits.contains(f)) continue;
        final rad = kSuFoes[f.type].$5 + 1.2;
        if ((f.x - s.x) * (f.x - s.x) + (f.y - s.y) * (f.y - s.y) < rad * rad) {
          _hurt(f, dmg);
          s.hits.add(f);
          if (s.pierce-- <= 0) s.life = 0;
        }
      }
    }
    shots.removeWhere((s) => s.life <= 0);
    // dönen küreler
    orbA += dt * 3.2;
    for (var o = 0; o < skill[3]; o++) {
      final a = orbA + o * 2 * math.pi / skill[3];
      final ox = px + math.cos(a) * 12, oy = py + math.sin(a) * 12;
      for (final f in foes) {
        final rad = kSuFoes[f.type].$5 + 2.5;
        if ((f.x - ox) * (f.x - ox) + (f.y - oy) * (f.y - oy) < rad * rad) _hurt(f, 6 * dt);
      }
    }
    // ışık halesi
    final ar = auraR;
    if (ar > 0) {
      for (final f in foes) {
        if ((f.x - px) * (f.x - px) + (f.y - py) * (f.y - py) < ar * ar) _hurt(f, (1.5 + skill[4]) * dt);
      }
    }
    for (final f in foes) {
      if (f.hp <= 0) {
        kills++;
        gems.add(SuGem(f.x, f.y, kSuFoes[f.type].$4));
      }
    }
    foes.removeWhere((f) => f.hp <= 0);
    // ışık kırıntıları
    final m = magnet;
    gems.removeWhere((g) {
      if ((g.x - px) * (g.x - px) + (g.y - py) * (g.y - py) < m * m) {
        xp += g.v;
        return true;
      }
      return false;
    });
    while (xp >= need) {
      xp -= need;
      level++;
      pending++;
    }
    if (pending > 0 && offer.isEmpty) offer = _offerFor(level - pending + 1);
    t += dt;
  }

  /// Bot yönü: yakındaki gölgelerden uzaklaş, kırıntılara ve merkeze yönel.
  (double, double) botDir() {
    var dx = 0.0, dy = 0.0;
    for (final f in foes) {
      final ex = px - f.x, ey = py - f.y;
      final d2 = ex * ex + ey * ey + 1;
      if (d2 < 900) {
        dx += ex / d2 * 30;
        dy += ey / d2 * 30;
      }
    }
    SuGem? g0;
    var gd = 1e18;
    for (final g in gems) {
      final d = (g.x - px) * (g.x - px) + (g.y - py) * (g.y - py);
      if (d < gd) {
        gd = d;
        g0 = g;
      }
    }
    if (g0 != null && gd < 1600) {
      dx += (g0.x - px) / math.sqrt(gd + 1) * 0.6;
      dy += (g0.y - py) / math.sqrt(gd + 1) * 0.6;
    }
    dx += (kSuW / 2 - px) * 0.012;
    dy += (kSuH / 2 - py) * 0.012;
    return (dx, dy);
  }

  void botChoose() {
    while (pending > 0) {
      final o = offer;
      var best = o.first;
      for (final s in o) {
        if (kSuBotPref.indexOf(s) < kSuBotPref.indexOf(best)) best = s;
      }
      choose(best);
    }
  }
}

/// Botun kalan canı (0: dayanamadı).
int suBot(SuPuzzle z) {
  final s = SuSim(z);
  while (!s.over) {
    s.botChoose();
    final (dx, dy) = s.botDir();
    s.step(dx, dy);
  }
  return s.won ? s.hp : 0;
}

class SuruKind extends StratejiKind {
  @override
  String get id => 'suru';
  const SuruKind();

  @override
  SPuzzle? make(int d, SeededRandom r) {
    final duration = 40.0 + 7 * d;
    final spawns = <(double, double, int)>[];
    var t = 1.0;
    while (t < duration - 3) {
      final f = t / duration;
      final burst = 1 + (f * (1 + d * 0.35)).floor();
      final a0 = r.nextDouble() * math.pi * 2;
      for (var i = 0; i < burst; i++) {
        final roll = r.nextDouble();
        final ty = roll < 0.12 + 0.03 * d * f ? 2 : (roll < 0.55 ? 1 : 0);
        spawns.add((t, a0 + (i - burst / 2) * 0.35, ty));
      }
      t += math.max(0.55, 2.0 - 0.1 * d - 1.0 * f);
    }
    final z = SuPuzzle(r.nextInt(1 << 30), d, duration, spawns, 0.9 + 0.06 * d);
    final hp = suBot(z);
    if (hp < 3) return null;
    return z;
  }

  @override
  bool check(SPuzzle p) => p is SuPuzzle && p.spawns.isNotEmpty && p.duration >= 40 && suBot(p) >= 3;

  @override
  Widget build(StratejiPlay play) => _SuView(play: play);

  @override
  List<Perk> get perks => const [
        Perk(3, Icons.favorite, 'pMaxHp', 2),
        Perk(8, Icons.bolt, 'su_dmg', 1),
        Perk(15, Icons.attractions, 'su_magnet', 1),
        Perk(25, Icons.call_split, 'su_multi', 1),
        Perk(40, Icons.blur_circular, 'su_orb', 1),
      ];

  @override
  List<GameStat> get stats => [
        ...super.stats,
        const GameStat('shadows', 'Söndürülen gölge', 'Shadows faded', scale: 200),
      ];
}

class _SuView extends StatefulWidget {
  final StratejiPlay play;
  const _SuView({required this.play});
  @override
  State<_SuView> createState() => _SuViewState();
}

class _SuViewState extends State<_SuView> with Clock, MetaLoader {
  late SuSim s;
  Timer? loop;
  Offset? aim;
  bool go = false;

  StratejiPlay get p => widget.play;
  SuPuzzle get z => p.puzzle as SuPuzzle;
  String get lang => p.lang;

  SuSim _fresh() => SuSim(z, extraHp: p.has(usta, 0) ? 2 : 0, startSkills: [
        if (p.has(usta, 1)) 0,
        if (p.has(usta, 2)) 7,
        if (p.has(usta, 3)) 2,
        if (p.has(usta, 4)) 3,
      ]);

  @override
  void initState() {
    super.initState();
    s = _fresh();
    loadMeta(p.gameId, () => s = _fresh());
  }

  void _start() {
    if (go) return;
    started = true;
    startClock();
    setState(() => go = true);
    loop = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  void _tick() {
    if (!mounted || ended) return;
    final a = aim;
    var dx = 0.0, dy = 0.0;
    if (a != null) {
      dx = a.dx - s.px;
      dy = a.dy - s.py;
      if (dx * dx + dy * dy < 4) dx = dy = 0;
    }
    final hp0 = s.hp, lv0 = s.level;
    setState(() => s.step(dx, dy));
    if (s.hp < hp0) p.sfx(Sfx.error);
    if (s.level > lv0) p.sfx(Sfx.unlock);
    if (s.over) _end();
  }

  void _end() {
    if (ended) return;
    ended = true;
    loop?.cancel();
    if (s.won) {
      p.sfx(Sfx.win);
      later(400, () => p.win(score: s.kills * 10 + s.hp * 30 + z.d * 40, stars: starsByHealth(s.hp, s.maxHp), seconds: seconds,
          moves: s.level, stats: {'shadows': s.kills}));
    } else {
      p.sfx(Sfx.lose);
      later(500, () => p.lose(score: s.kills * 10, seconds: seconds, moves: s.level, stats: {'shadows': s.kills}));
    }
  }

  @override
  void dispose() {
    loop?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = math.max(0, (z.duration - s.t).ceil());
    final board = TapCanvas(
      w: kSuW,
      h: kSuH,
      paint: _paint,
      semantics: st(lang, 'su_title'),
      onTap: (o) {
        if (!go) _start();
        aim = o;
      },
      onPanStart: (o) {
        if (!go) _start();
        aim = o;
      },
      onPanUpdate: (o) => aim = o,
      onPanEnd: () => aim = null,
    );
    return Stack(children: [
      SScreen(
        bar: SBar(lang: lang, left: '♥ ${math.max(0, s.hp)}/${s.maxHp} · Lv ${s.level}', status: '${clock(left)} · ✦ ${s.kills}'),
        top: PerkStrip(lang: lang, perks: p.perks, usta: usta),
        board: board,
        bottom: go
            ? Wrap(spacing: 6, children: [
                for (var i = 0; i < 8; i++)
                  if (s.skill[i] > 0) IconNum(kSuSkillIcons[i], '${s.skill[i]}'),
              ])
            : StudioButton(onPressed: _start, icon: Icons.play_arrow, label: st(lang, 'su_start')),
      ),
      if (s.pending > 0 && !ended)
        SPanel(title: st(lang, 'su_levelUp'), children: [
          for (final k in s.offer)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SizedBox(
                width: double.infinity,
                child: StudioButton(
                  onPressed: () => setState(() {
                    s.choose(k);
                    p.sfx(Sfx.place);
                  }),
                  icon: kSuSkillIcons[k],
                  label: st(lang, kSuSkillKeys[k]),
                ),
              ),
            ),
        ]),
    ]);
  }

  void _paint(Canvas c) {
    c.drawRect(const Rect.fromLTWH(0, 0, kSuW, kSuH), fill(const Color(0xFF26314A)));
    for (var i = 0; i < 9; i++) {
      c.drawCircle(Offset((i * 37) % kSuW, (i * 53) % kSuH), 0.7, fill(const Color(0x55FFFFFF)));
    }
    final ar = s.auraR;
    if (ar > 0) c.drawCircle(Offset(s.px, s.py), ar, fill(const Color(0x33FFE08A)));
    for (final g in s.gems) {
      c.drawCircle(Offset(g.x, g.y), 1.1 + g.v * 0.2, fill(const Color(0xFF8FE3FF)));
    }
    for (final f in s.foes) {
      final rad = kSuFoes[f.type].$5;
      final o = Offset(f.x, f.y);
      c.drawCircle(o, rad, fill(const Color(0xCC1B1430)));
      c.drawCircle(o, rad, stroke(const Color(0xFF7C6BB0), 0.6));
      c.drawCircle(o + Offset(-rad * 0.35, -rad * 0.2), rad * 0.16, fill(const Color(0xFFE8E0FF)));
      c.drawCircle(o + Offset(rad * 0.35, -rad * 0.2), rad * 0.16, fill(const Color(0xFFE8E0FF)));
    }
    for (final sh in s.shots) {
      c.drawCircle(Offset(sh.x, sh.y), 1.0, fill(const Color(0xFFFFE08A)));
    }
    for (var o = 0; o < s.skill[3]; o++) {
      final a = s.orbA + o * 2 * math.pi / s.skill[3];
      c.drawCircle(Offset(s.px + math.cos(a) * 12, s.py + math.sin(a) * 12), 2.2, fill(const Color(0xFFFFC94A)));
    }
    final me = Offset(s.px, s.py);
    c.drawCircle(me, 6, fill(const Color(0x44FFE08A)));
    c.drawCircle(me, 3.2, fill(const Color(0xFFF4F1EA)));
    c.drawCircle(me + const Offset(0, -0.6), 1.4, fill(const Color(0xFFFFB13B)));
    final a = aim;
    if (a != null) c.drawCircle(a, 2, stroke(const Color(0x88FFFFFF), 0.5));
  }
}

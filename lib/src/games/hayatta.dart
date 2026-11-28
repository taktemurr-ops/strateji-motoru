import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../studio_chrome.dart';
import '../texts.dart';

/// Issız Kıyı: kurtarma gemisi gelene kadar hayatta kal. Her gün bir olay ve
/// iki iş; geceleri tokluk ve ısı düşer, hava durumu önceden görünür.
///
/// Kaynaklar: 0 can, 1 tokluk, 2 ısı, 3 erzak, 4 odun, 5 barınak, 6 olta, 7 balta.
const List<String> kResKeys = ['r_health', 'r_food', 'r_warmth', 'r_supplies', 'r_wood', 'r_shelter', 'r_rod', 'r_axe'];
const List<IconData> kResIcons = [
  Icons.favorite,
  Icons.restaurant,
  Icons.local_fire_department,
  Icons.inventory_2,
  Icons.forest,
  Icons.cabin,
  Icons.phishing,
  Icons.carpenter,
];

/// Hava: 0 güneşli, 1 yağmurlu, 2 soğuk, 3 fırtına; gece ısı kaybı.
const List<String> kWxKeys = ['w_sun', 'w_rain', 'w_cold', 'w_storm'];
const List<IconData> kWxIcons = [Icons.wb_sunny, Icons.umbrella, Icons.ac_unit, Icons.thunderstorm];
const List<int> kWxLoss = [1, 2, 3, 3];

/// Olaylar: başlık + iki seçenek (kaynak, değişim).
class KEvent {
  final String key;
  final List<(int, int)> a, b;
  const KEvent(this.key, this.a, this.b);
}

const List<KEvent> kEvents = [
  KEvent('ev_gulls', [(3, -1)], [(0, -1)]),
  KEvent('ev_tree', [(4, 3), (0, -1)], []),
  KEvent('ev_crate', [(3, 2)], [(4, 2)]),
  KEvent('ev_downpour', [(2, -2)], [(4, -2)]),
  KEvent('ev_herbs', [(0, 2), (1, -1)], [(1, 2)]),
  KEvent('ev_boat', [(7, 1), (3, -2)], [(6, 1), (3, -2)]),
  KEvent('ev_cave', [(5, 1), (4, -2)], []),
  KEvent('ev_boar', [(3, -2), (0, 1)], [(0, -2)]),
];

/// İşler: 0 balık, 1 meyve, 2 odun, 3 keşif, 4 dinlen, 5 ye, 6 ateş, 7 barınak.
const List<String> kJobKeys = ['k_fish', 'k_fruit', 'k_wood', 'k_explore', 'k_rest', 'k_eat', 'k_fire', 'k_build'];
const List<IconData> kJobIcons = [Icons.phishing, Icons.eco, Icons.forest, Icons.explore, Icons.bedtime, Icons.restaurant, Icons.local_fire_department, Icons.cabin];

class KPuzzle extends SPuzzle {
  final int seed, d;
  const KPuzzle(this.seed, this.d);
}

class KSim {
  final int seed, d;
  final int days;
  final List<int> wx = [], ev = [], exp = [];
  final List<int> v; // 8 kaynak
  int maxHp;
  int day = 0;

  /// 0 olay seçimi, 1 işler, 2 bitti
  int phase = 0;
  int left = 2;
  bool won = false, lost = false;

  /// Son gecenin kayıpları (tokluk, ısı, can) — kısa bilgi için.
  (int, int, int) lastNight = (0, 0, 0);
  int jobsDone = 0;

  KSim(this.seed, this.d, {int supplies = 0, bool rod = false, int shelter = 0, int wood = 0, int extraHp = 0})
      : days = 6 + d,
        maxHp = 10 + extraHp,
        v = [10 + extraHp, 8, 8, 2 + supplies, 2 + wood, shelter, rod ? 1 : 0, 0] {
    final r = SeededRandom(mixSeed([seed, 8808]));
    for (var i = 0; i < days + 2; i++) {
      wx.add(r.weighted([5, 3, 2 + d ~/ 2, 1 + d ~/ 2]));
    }
    for (var i = 0; i < days; i++) {
      ev.add(r.nextInt(kEvents.length));
    }
    for (var i = 0; i < days * 2; i++) {
      exp.add(r.nextInt(100));
    }
  }

  KEvent get event => kEvents[ev[day]];
  int get weather => wx[day];

  bool optionOk(List<(int, int)> o) => o.every((e) => !(e.$1 == 3 || e.$1 == 4) || v[e.$1] + e.$2 >= 0);

  List<int> _applyEvent(List<int> s, List<(int, int)> o) {
    final t = [...s];
    for (final (k, dv) in o) {
      t[k] = k == 0 ? math.min<int>(maxHp, t[k] + dv) : math.max<int>(0, t[k] + dv);
    }
    t[6] = math.min<int>(1, t[6]);
    t[7] = math.min<int>(1, t[7]);
    t[5] = math.min<int>(3, t[5]);
    return t;
  }

  /// Olay seçimi: 0 ya da 1. Seçenek geçersizse diğeri, ikisi de geçersizse etkisiz.
  void choose(int i) {
    if (phase != 0) return;
    final e = event;
    final opts = [e.a, e.b];
    final ci = clampI(i, 0, 1);
    var o = opts[ci];
    if (!optionOk(o)) o = optionOk(opts[1 - ci]) ? opts[1 - ci] : const <(int, int)>[];
    final t = _applyEvent(v, o);
    for (var k = 0; k < 8; k++) {
      v[k] = t[k];
    }
    phase = 1;
    left = 2;
    if (v[0] <= 0) {
      lost = true;
      phase = 2;
    }
  }

  bool legal(int job) => switch (job) {
        5 => v[3] >= 2,
        6 => v[4] >= 2,
        7 => v[4] >= 4 && v[5] < 3,
        _ => job >= 0 && job <= 7,
      };

  List<int> _applyJob(List<int> s, int job, int ex) {
    final t = [...s];
    switch (job) {
      case 0:
        t[3] += weather == 3 ? 0 : 1 + 2 * t[6] + (ex.isOdd ? 1 : 0);
      case 1:
        t[3] += 2 + (ex % 3 == 0 ? 1 : 0);
      case 2:
        t[4] += 2 + t[7];
      case 3:
        if (ex < 12 && t[6] == 0) {
          t[6] = 1;
        } else if (ex < 24 && t[7] == 0) {
          t[7] = 1;
        } else if (ex < 45) {
          t[3] += 3;
        } else if (ex < 65) {
          t[4] += 3;
        } else if (ex < 80) {
          t[0] -= 2;
        }
      case 4:
        t[0] = math.min<int>(maxHp, t[0] + 2);
      case 5:
        t[3] -= 2;
        t[1] = math.min<int>(10, t[1] + 4);
      case 6:
        t[4] -= 2;
        t[2] = math.min<int>(10, t[2] + 3);
      default:
        t[4] -= 4;
        t[5] += 1;
    }
    return t;
  }

  void work(int job) {
    if (phase != 1 || !legal(job)) return;
    final t = _applyJob(v, job, exp[day * 2 + (2 - left)]);
    for (var k = 0; k < 8; k++) {
      v[k] = t[k];
    }
    jobsDone++;
    left--;
    if (v[0] <= 0) {
      lost = true;
      phase = 2;
      return;
    }
    if (left == 0) _night();
  }

  void _night() {
    final w = weather;
    final h0 = v[0];
    final food = 2 + (d >= 4 ? 1 : 0) + (d >= 8 ? 1 : 0);
    v[1] -= food;
    final warm = math.max<int>(0, kWxLoss[w] - v[5]);
    v[2] -= warm;
    if (w == 3 && v[5] == 0) v[0] -= 1;
    if (v[1] <= 0) {
      v[1] = 0;
      v[0] -= 2;
    }
    if (v[2] <= 0) {
      v[2] = 0;
      v[0] -= 2;
    }
    lastNight = (food, warm, h0 - v[0]);
    if (v[0] <= 0) {
      lost = true;
      phase = 2;
      return;
    }
    day++;
    if (day >= days) {
      won = true;
      phase = 2;
      return;
    }
    phase = 0;
  }

  // ------------------------------------------------------------ yapay zekâ

  double value(List<int> s, int wNext) {
    var x = s[0] * 10.0;
    x += math.min<int>(s[1], 8) * 3 + math.min<int>(s[2], 8) * 3;
    x += math.min<int>(s[3], 8) * 1.6 + math.min<int>(s[4], 10) * 1.2 + s[5] * 6 + s[6] * 5 + s[7] * 4;
    if (s[1] <= 2) x -= 15;
    if (s[2] <= kWxLoss[wNext] - s[5]) x -= 15;
    return x;
  }

  int botChoice() {
    final e = event;
    final aOk = optionOk(e.a), bOk = optionOk(e.b);
    if (!aOk && !bOk) return 0;
    if (!bOk) return 0;
    if (!aOk) return 1;
    return value(_applyEvent(v, e.a), weather) >= value(_applyEvent(v, e.b), weather) ? 0 : 1;
  }

  int botJob() {
    var best = -1;
    var bv = -1e9;
    final ex = exp[day * 2 + (2 - left)];
    for (final j in const [0, 1, 2, 3, 4, 5, 6, 7]) {
      if (!legal(j)) continue;
      final x = value(_applyJob(v, j, ex), weather);
      if (x > bv) {
        bv = x;
        best = j;
      }
    }
    return best;
  }

  void botStep() {
    if (phase == 0) {
      choose(botChoice());
    } else if (phase == 1) {
      work(botJob());
    }
  }
}

class HayattaKind extends StratejiKind {
  @override
  String get id => 'hayatta';
  const HayattaKind();

  @override
  SPuzzle? make(int d, SeededRandom r) => KPuzzle(r.nextUint32(), d);

  @override
  bool check(SPuzzle p) {
    if (p is! KPuzzle) return false;
    final s = KSim(p.seed, p.d);
    var guard = 0;
    while (s.phase != 2 && guard++ < 200) {
      s.botStep();
    }
    return s.won;
  }

  @override
  List<Perk> get perks => const [
        Perk(3, Icons.inventory_2, 'r_supplies', 2),
        Perk(8, Icons.phishing, 'r_rod', 0),
        Perk(15, Icons.cabin, 'r_shelter', 1),
        Perk(25, Icons.forest, 'r_wood', 3),
        Perk(40, Icons.favorite, 'pMaxHp', 2),
      ];

  @override
  List<GameStat> get stats => const [
        GameStat('runs_won', 'Kurtarılış', 'Rescues', scale: 10),
        GameStat('flawless', 'Sağ salim kurtarılış', 'Rescues in full health', scale: 10),
        GameStat('days_survived', 'Atlatılan gün', 'Days survived', scale: 40),
      ];

  @override
  Widget build(StratejiPlay play) => _KView(play: play);
}

class _KView extends StatefulWidget {
  final StratejiPlay play;
  const _KView({required this.play});
  @override
  State<_KView> createState() => _KViewState();
}

class _KViewState extends State<_KView> with Clock, MetaLoader {
  late KSim s;
  int hints = 0;
  int hinted = -1;
  String note = '';

  StratejiPlay get p => widget.play;
  KPuzzle get z => p.puzzle as KPuzzle;

  KSim _fresh() => KSim(
        z.seed,
        z.d,
        supplies: p.has(usta, 0) ? 2 : 0,
        rod: p.has(usta, 1),
        shelter: p.has(usta, 2) ? 1 : 0,
        wood: p.has(usta, 3) ? 3 : 0,
        extraHp: p.has(usta, 4) ? 2 : 0,
      );

  @override
  void initState() {
    super.initState();
    s = _fresh();
    startClock();
    loadMeta(p.gameId, () => s = _fresh());
  }

  void _after(int dayBefore) {
    started = true;
    hinted = -1;
    if (s.day > dayBefore && !s.over) {
      final (f, w, h) = s.lastNight;
      note = '${st(p.lang, 'night')}: −$f ${st(p.lang, 'r_food')} · −$w ${st(p.lang, 'r_warmth')}${h > 0 ? ' · −$h ${st(p.lang, 'r_health')}' : ''}';
      p.sfx(h > 0 ? Sfx.error : Sfx.unlock);
    }
    if (s.won) {
      ended = true;
      p.sfx(Sfx.win);
      final stars = starsByHealth(s.v[0], s.maxHp) - (hints > 0 ? 1 : 0);
      later(500, () => p.win(score: s.days * 40 + s.v[0] * 15 + s.v[3] * 3 + p.d * 30, stars: stars, seconds: seconds, moves: s.jobsDone, hints: hints, stats: {'days_survived': s.day}));
    } else if (s.lost) {
      ended = true;
      later(600, () => p.lose(score: s.day * 40, seconds: seconds, moves: s.jobsDone, stats: {'days_survived': s.day}));
    }
    setState(() {});
  }

  void _choose(int i) {
    if (ended) return;
    final d0 = s.day;
    s.choose(i);
    p.sfx(Sfx.tap);
    _after(d0);
  }

  void _work(int j) {
    if (ended || !s.legal(j)) {
      p.sfx(Sfx.error);
      return;
    }
    final d0 = s.day;
    note = '';
    s.work(j);
    p.sfx(Sfx.place);
    _after(d0);
  }

  Future<void> _hint() async {
    if (ended) return;
    final ok = await p.ctx.requestHint();
    if (!ok || !mounted) return;
    setState(() {
      hints++;
      hinted = s.phase == 0 ? s.botChoice() : s.botJob();
    });
  }

  Widget _meter(int k, Color col) {
    final mx = k == 0 ? s.maxHp : 10;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(children: [
          IconNum(kResIcons[k], '${s.v[k]}/$mx', color: col, size: 13),
          const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: clampD(s.v[k] / mx, 0, 1), minHeight: 7, color: col, backgroundColor: Colors.black12),
          ),
        ]),
      ),
    );
  }

  Widget _effects(List<(int, int)> o) => Wrap(spacing: 6, alignment: WrapAlignment.center, children: [
        if (o.isEmpty) const Icon(Icons.remove, size: 16),
        for (final (k, dv) in o) IconNum(kResIcons[k], dv > 0 ? '+$dv' : '$dv', color: dv > 0 ? SColors.good : SColors.bad),
      ]);

  @override
  Widget build(BuildContext context) {
    final lang = p.lang;
    final status = note.isNotEmpty ? note : '${st(lang, 'day')} ${math.min<int>(s.day + 1, s.days)}/${s.days} · ${st(lang, kWxKeys[s.weather])}';
    return SScreen(
      bar: SBar(lang: lang, left: '☀ ${math.min<int>(s.day + 1, s.days)}', status: status, onHint: ended ? null : _hint),
      top: PerkStrip(lang: lang, perks: p.perks, usta: usta),
      board: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < 3 && s.day + i < s.wx.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(children: [
                Icon(kWxIcons[s.wx[s.day + i]], size: i == 0 ? 30.0 : 22.0, color: i == 0 ? StudioLook.of(context).accent : Colors.white54),
                Text(i == 0 ? st(lang, 'today') : '+$i', style: const TextStyle(fontSize: 11)),
              ]),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [_meter(0, SColors.bad), _meter(1, SColors.gold), _meter(2, const Color(0xFFE07A5F))]),
        const SizedBox(height: 8),
        Wrap(alignment: WrapAlignment.center, spacing: 12, children: [
          for (final k in const [3, 4, 5]) IconNum(kResIcons[k], '${s.v[k]}${k == 5 ? '/3' : ''}', size: 15),
          if (s.v[6] > 0) const Icon(Icons.phishing, color: SColors.good),
          if (s.v[7] > 0) const Icon(Icons.carpenter, color: SColors.good),
        ]),
        const SizedBox(height: 6),
        Expanded(
          child: Stack(children: [
            // Issız kıyı sahnesi: hava durumu, barınak (0-3), ateşin boyu (sıcaklık).
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CustomPaint(painter: _IslandScene(s.weather, s.v[5], s.v[2], s.day)),
              ),
            ),
            SingleChildScrollView(child: s.phase == 0 && !s.over ? _eventCard(lang) : _jobs(lang)),
          ]),
        ),
      ]),
    );
  }

  Widget _eventCard(String lang) {
    final e = s.event;
    return Container(
      margin: const EdgeInsets.all(6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: StudioLook.of(context).accent.withValues(alpha: 0.45), width: 1.2),
      ),
      child: Column(children: [
        Text(st(lang, e.key), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
        const SizedBox(height: 10),
        Row(children: [
          for (final i in const [0, 1])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SChip(
                  selected: hinted == i,
                  onTap: s.optionOk(i == 0 ? e.a : e.b) ? () => _choose(i) : null,
                  child: Opacity(opacity: s.optionOk(i == 0 ? e.a : e.b) ? 1 : 0.4, child: _effects(i == 0 ? e.a : e.b)),
                ),
              ),
            ),
        ]),
      ]),
    );
  }

  Widget _jobs(String lang) => Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < 2; i++) Icon(i < s.left ? Icons.circle : Icons.circle_outlined, size: 12, color: StudioLook.of(context).accent),
        ]),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 3.2,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: [
            for (var j = 0; j < 8; j++)
              SChip(
                selected: hinted == j,
                onTap: s.phase == 1 && s.legal(j) ? () => _work(j) : null,
                child: Opacity(
                  opacity: s.phase == 1 && s.legal(j) ? 1 : 0.4,
                  child: Row(children: [
                    Icon(kJobIcons[j], size: 18),
                    const SizedBox(width: 6),
                    Expanded(child: Text(st(lang, kJobKeys[j]), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                  ]),
                ),
              ),
          ],
        ),
      ]);
}

extension on KSim {
  bool get over => won || lost;
}

/// Hayatta kalma sahnesi (süs): deniz, kumsal, palmiye, barınak, kamp ateşi
/// ve günün havası (güneş / yağmur / soğuk / fırtına).
class _IslandScene extends CustomPainter {
  final int weather, shelter, warmth, day;
  _IslandScene(this.weather, this.shelter, this.warmth, this.day);

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final sky = switch (weather) {
      1 => [const Color(0xFF5B6C7D), const Color(0xFF8FA3B3)],
      2 => [const Color(0xFF9FB8CC), const Color(0xFFDCE7EF)],
      3 => [const Color(0xFF2B2F45), const Color(0xFF4D5570)],
      _ => [const Color(0xFF6EC1E4), const Color(0xFFBFE6F5)],
    };
    final r = Offset.zero & s;
    c.drawRect(r, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: sky).createShader(r));
    if (weather == 0) c.drawCircle(Offset(w * 0.82, h * 0.42), 26, Paint()..color = const Color(0xFFFFE08A));
    // Üstteki olay kartının yazısı açık gökte de okunsun: üstten koyu geçiş.
    final band = Rect.fromLTWH(0, 0, w, h * 0.42);
    c.drawRect(
        band,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xB3101A2E), Color(0x00101A2E)],
          ).createShader(band));
    // Deniz ve dalgalar.
    final seaY = h * 0.6;
    c.drawRect(Rect.fromLTWH(0, seaY, w, h - seaY), Paint()..color = weather == 3 ? const Color(0xFF26415C) : const Color(0xFF2E86AB));
    final wave = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var k = 0; k < 4; k++) {
      final y = seaY + 8 + k * 10.0;
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= w; x += 24) {
        path.quadraticBezierTo(x + 6, y - 4, x + 12, y);
      }
      c.drawPath(path, wave);
    }
    // Kumsal.
    final sand = Path()
      ..moveTo(0, h)
      ..lineTo(0, h * 0.74)
      ..quadraticBezierTo(w * 0.45, h * 0.64, w, h * 0.76)
      ..lineTo(w, h)
      ..close();
    c.drawPath(sand, Paint()..color = weather == 2 ? const Color(0xFFEDE6DA) : const Color(0xFFE9C98B));
    // Palmiye.
    final tx = w * 0.16, ty = h * 0.72;
    c.drawLine(Offset(tx, ty), Offset(tx + 12, ty - h * 0.24), Paint()
      ..color = const Color(0xFF8B5A2B)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round);
    final crown = Offset(tx + 12, ty - h * 0.24);
    for (final a in const [-2.6, -2.0, -1.2, -0.5, 0.2]) {
      c.drawLine(crown, crown + Offset(math.cos(a) * 34, math.sin(a) * 18 + 10), Paint()
        ..color = const Color(0xFF3E8E41)
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round);
    }
    // Barınak: seviyesine göre kazık, çatı, duvar.
    final bx = w * 0.5, by = h * 0.8;
    if (shelter >= 1) {
      for (final dx in const [-26.0, 26.0]) {
        c.drawLine(Offset(bx + dx, by), Offset(bx + dx * 0.2, by - 46), Paint()
          ..color = const Color(0xFF6D4C41)
          ..strokeWidth = 5);
      }
    }
    if (shelter >= 2) {
      c.drawPath(
          Path()
            ..moveTo(bx - 34, by - 10)
            ..lineTo(bx, by - 52)
            ..lineTo(bx + 34, by - 10)
            ..close(),
          Paint()..color = const Color(0xFFB5894E));
    }
    if (shelter >= 3) c.drawRect(Rect.fromLTWH(bx - 24, by - 14, 48, 14), Paint()..color = const Color(0xFF8D6E63));
    // Kamp ateşi: sıcaklık arttıkça büyür.
    final fx = w * 0.78, fy = h * 0.86;
    c.drawLine(Offset(fx - 22, fy + 6), Offset(fx + 22, fy - 3), Paint()
      ..color = const Color(0xFF5D4037)
      ..strokeWidth = 7);
    c.drawLine(Offset(fx - 22, fy - 3), Offset(fx + 22, fy + 6), Paint()
      ..color = const Color(0xFF5D4037)
      ..strokeWidth = 7);
    final fl = 10 + math.min(10, math.max(0, warmth)) * 3.2;
    c.drawOval(Rect.fromCenter(center: Offset(fx, fy - fl / 2), width: fl * 0.9, height: fl), Paint()..color = const Color(0xFFF77F00));
    c.drawOval(Rect.fromCenter(center: Offset(fx, fy - fl / 3), width: fl * 0.45, height: fl * 0.55), Paint()..color = const Color(0xFFFFD166));
    // Hava: yağmur, kar, fırtına şimşeği.
    if (weather == 1 || weather == 3) {
      final rain = Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..strokeWidth = 1.5;
      for (var k = 0; k < 40; k++) {
        final x = (k * 37.0 + day * 11) % w, y = (k * 53.0) % (h * 0.95);
        c.drawLine(Offset(x, y), Offset(x - 4, y + 10), rain);
      }
    }
    if (weather == 2) {
      for (var k = 0; k < 30; k++) {
        c.drawCircle(Offset((k * 41.0 + day * 7) % w, (k * 67.0) % (h * 0.95)), 2.2, Paint()..color = Colors.white);
      }
    }
    if (weather == 3) {
      c.drawPath(
          Path()
            ..moveTo(w * 0.6, h * 0.08)
            ..lineTo(w * 0.55, h * 0.3)
            ..lineTo(w * 0.62, h * 0.3)
            ..lineTo(w * 0.56, h * 0.5),
          Paint()
            ..color = const Color(0xFFFFF3B0)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
    }
  }

  @override
  bool shouldRepaint(covariant _IslandScene o) =>
      o.weather != weather || o.shelter != shelter || o.warmth != warmth || o.day != day;
}

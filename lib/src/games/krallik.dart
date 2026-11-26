import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../studio_chrome.dart';
import '../texts.dart';
import 'krallik_cards.dart';

/// Dört Mevsim Krallık: danışmanların kartlarını sola ya da sağa kaydırarak
/// karar ver. Halk, hazine, ordu ve doğa dengede kalmalı: biri tükenir ya da
/// taşarsa saltanat erken biter. Mevsimler de dengeyi yavaşça değiştirir.
const List<String> kKMeters = ['km_people', 'km_treasury', 'km_army', 'km_nature'];
const List<IconData> kKMeterIcons = [Icons.groups, Icons.savings, Icons.shield, Icons.forest];
const List<Color> kKMeterColors = [Color(0xFFB0563B), Color(0xFFD9A441), Color(0xFF3E6FB0), Color(0xFF4F9A6E)];
const List<String> kKSeasons = ['', 'km_spring', 'km_summer', 'km_autumn', 'km_winter'];
const List<IconData> kKSeasonIcons = [Icons.circle, Icons.local_florist, Icons.wb_sunny, Icons.eco, Icons.ac_unit];
const List<Color> kKSeasonColors = [Colors.grey, Color(0xFF8DBF6A), Color(0xFFE0A93B), Color(0xFFC0703A), Color(0xFF7FA7C9)];
const List<String> kKAdvisors = ['km_w0', 'km_w1', 'km_w2', 'km_w3', 'km_w4'];
const List<IconData> kKAdvisorIcons = [Icons.account_balance, Icons.agriculture, Icons.storefront, Icons.security, Icons.menu_book];

const int kKMin = 0, kKMax = 10, kKStart = 5;

class KPuzzle extends SPuzzle {
  final int seed, d, per;
  final List<int> cards;
  final List<int> seasons;
  final List<int> botFinal;
  const KPuzzle(this.seed, this.d, this.per, this.cards, this.seasons, this.botFinal);
  int get years => cards.length ~/ (per * 4);
}

/// Mevsim sonu değişimi.
List<int> kDrift(int season, int d) {
  final e = [0, 0, 0, 0];
  if (season == 1) {
    e[3] += 1;
  } else if (season == 2) {
    e[1] += 1;
  } else if (season == 3) {
    e[0] += 1;
  } else if (season == 4) {
    e[1] -= 1;
    if (d >= 5) e[0] -= 1;
    if (d >= 8) e[2] -= 1;
  }
  return e;
}

bool kDead(List<int> m) => m.any((x) => x <= kKMin || x >= kKMax);

int kCost(List<int> m) => kDead(m) ? 1000000 : m.fold<int>(0, (a, x) => a + (x - kKStart) * (x - kKStart));

/// [i]. kartta [choice] seçilince oluşan değerler (mevsim sonuysa mevsim etkisiyle).
List<int> kStep(KPuzzle z, List<int> m, int i, int choice) {
  final c = kKCards[z.cards[i]];
  final e = choice == 0 ? c.le : c.re;
  final r = [for (var k = 0; k < 4; k++) m[k] + e[k]];
  if (!kDead(r) && (i + 1) % z.per == 0) {
    final dd = kDrift(z.seasons[i], z.d);
    for (var k = 0; k < 4; k++) {
      r[k] += dd[k];
    }
  }
  return r;
}

/// İki adım ileri bakan yapay zekâ seçimi.
int kBest(KPuzzle z, List<int> m, int i) {
  var best = 0;
  var bv = double.infinity;
  for (final ch in const [0, 1]) {
    final m1 = kStep(z, m, i, ch);
    var v = kCost(m1).toDouble();
    if (i + 1 < z.cards.length && !kDead(m1)) {
      final n = math.min<int>(kCost(kStep(z, m1, i + 1, 0)), kCost(kStep(z, m1, i + 1, 1)));
      v = v * 0.5 + n * 0.5;
    }
    if (v < bv) {
      bv = v;
      best = ch;
    }
  }
  return best;
}

/// Yapay zekânın saltanatı: sona ulaşırsa son değerler, yoksa null.
List<int>? kBot(KPuzzle z) {
  var m = [kKStart, kKStart, kKStart, kKStart];
  for (var i = 0; i < z.cards.length; i++) {
    m = kStep(z, m, i, kBest(z, m, i));
    if (kDead(m)) return null;
  }
  return m;
}

class KrallikKind extends StratejiKind {
  @override
  String get id => 'krallik';
  const KrallikKind();

  @override
  SPuzzle? make(int d, SeededRandom r) {
    final years = 2 + d ~/ 3;
    final per = 2 + (d >= 7 ? 1 : 0);
    final pool = [for (var i = 0; i < kKCards.length; i++) i];
    r.shuffle(pool);
    final used = <int>{};
    final cards = <int>[], seasons = <int>[];
    for (var y = 0; y < years; y++) {
      for (var s = 1; s <= 4; s++) {
        var k = 0;
        for (final ci in pool) {
          if (used.contains(ci)) continue;
          final cs = kKCards[ci].season;
          if (cs != 0 && cs != s) continue;
          used.add(ci);
          cards.add(ci);
          seasons.add(s);
          k++;
          if (k == per) break;
        }
        if (k < per) return null;
      }
    }
    final z0 = KPuzzle(r.nextUint32(), d, per, cards, seasons, const []);
    final fin = kBot(z0);
    if (fin == null) return null;
    return KPuzzle(z0.seed, d, per, cards, seasons, fin);
  }

  @override
  bool check(SPuzzle p) {
    if (p is! KPuzzle || p.botFinal.length != 4) return false;
    final f = kBot(p);
    return f != null && f.join(',') == p.botFinal.join(',');
  }

  @override
  List<Perk> get perks => const [
        Perk(3, Icons.undo, 'undo', 1),
        Perk(8, Icons.visibility, 'km_peek', 0),
        Perk(15, Icons.forward, 'km_skip', 1),
        Perk(25, Icons.celebration, 'km_festival', 1),
        Perk(40, Icons.volunteer_activism, 'km_heir', 1),
      ];

  @override
  List<GameStat> get stats => const [
        GameStat('runs_won', 'Tamamlanan saltanat', 'Reigns completed', scale: 10),
        GameStat('flawless', 'Dengeli saltanat', 'Balanced reigns', scale: 10),
        GameStat('decisions', 'Verilen karar', 'Decisions made', scale: 100),
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
  List<int> m = [kKStart, kKStart, kKStart, kKStart];
  int i = 0;
  int decisions = 0;
  int undos = 0, skips = 0, festivals = 0, heirs = 0;
  final List<(List<int>, int)> history = [];
  double drag = 0;
  int hints = 0;
  int? hint;

  StratejiPlay get p => widget.play;
  KPuzzle get z => p.puzzle as KPuzzle;
  bool get peek => p.has(usta, 1);

  void _applyPerks() {
    undos = p.has(usta, 0) ? 1 : 0;
    skips = p.has(usta, 2) ? 1 : 0;
    festivals = p.has(usta, 3) ? 1 : 0;
    heirs = p.has(usta, 4) ? 1 : 0;
  }

  @override
  void initState() {
    super.initState();
    startClock();
    loadMeta(p.gameId, _applyPerks);
  }

  void _choose(int ch) {
    if (ended || i >= z.cards.length) return;
    started = true;
    history.add(([...m], i));
    var n = kStep(z, m, i, ch);
    if (kDead(n) && heirs > 0) {
      heirs--;
      n = [for (final x in n) (x <= kKMin || x >= kKMax) ? kKStart : x];
      p.sfx(Sfx.unlock);
    }
    setState(() {
      m = n;
      i++;
      decisions++;
      drag = 0;
      hint = null;
    });
    if (kDead(m)) {
      ended = true;
      p.sfx(Sfx.lose);
      later(700, () => p.lose(score: decisions * 10, seconds: seconds, moves: decisions, stats: {'decisions': decisions}));
      return;
    }
    p.sfx(i % z.per == 0 ? Sfx.coin : Sfx.place);
    if (i >= z.cards.length) _win();
  }

  void _win() {
    ended = true;
    final avg = m.fold<int>(0, (a, x) => a + (x - kKStart).abs()) / 4;
    final stars = (avg <= 1 ? 3 : (avg <= 2 ? 2 : 1)) - (hints > 0 ? 1 : 0);
    p.sfx(Sfx.win);
    later(600, () => p.win(score: z.years * 100 + (40 - kCost(m)) * 5 + p.d * 20, stars: stars, seconds: seconds, moves: decisions, hints: hints, stats: {'decisions': decisions}));
  }

  void _skip() {
    if (ended || skips <= 0 || i >= z.cards.length) return;
    started = true;
    history.add(([...m], i));
    setState(() {
      skips--;
      var n = [...m];
      if ((i + 1) % z.per == 0) {
        final dd = kDrift(z.seasons[i], z.d);
        n = [for (var k = 0; k < 4; k++) n[k] + dd[k]];
      }
      m = n;
      i++;
      hint = null;
    });
    p.sfx(Sfx.tap);
    if (kDead(m)) {
      ended = true;
      later(700, () => p.lose(score: decisions * 10, seconds: seconds, moves: decisions));
    } else if (i >= z.cards.length) {
      _win();
    }
  }

  void _festival() {
    if (ended || festivals <= 0) return;
    var k = 0;
    for (var j = 1; j < 4; j++) {
      if ((m[j] - kKStart).abs() > (m[k] - kKStart).abs()) k = j;
    }
    setState(() {
      festivals--;
      m[k] = kKStart;
    });
    p.sfx(Sfx.combo);
  }

  void _undo() {
    if (ended || undos <= 0 || history.isEmpty) return;
    final (mm, ii) = history.removeLast();
    setState(() {
      undos--;
      m = mm;
      i = ii;
      hint = null;
    });
    p.sfx(Sfx.tap);
  }

  Future<void> _hint() async {
    if (ended || i >= z.cards.length) return;
    final ok = await p.ctx.requestHint();
    if (!ok || !mounted) return;
    setState(() {
      hints++;
      hint = kBest(z, m, i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = p.lang;
    final ci = i < z.cards.length ? i : z.cards.length - 1;
    final year = ci ~/ (z.per * 4) + 1;
    final season = z.seasons[ci];
    final c = kKCards[z.cards[ci]];
    final side = drag < -12 ? 0 : (drag > 12 ? 1 : -1);
    final eff = side == 0 ? c.le : (side == 1 ? c.re : null);
    return SScreen(
      bar: SBar(
        lang: lang,
        left: '${st(lang, 'km_year')} $year/${z.years}',
        status: '${st(lang, kKSeasons[season])} · ${z.cards.length - i}',
        onHint: ended ? null : _hint,
        onUndo: undos > 0 && history.isNotEmpty && !ended ? _undo : null,
        extra: [
          if (skips > 0 && !ended) IconButton(tooltip: st(lang, 'km_skip'), onPressed: _skip, icon: const Icon(Icons.forward)),
          if (festivals > 0 && !ended) IconButton(tooltip: st(lang, 'km_festival'), onPressed: _festival, icon: const Icon(Icons.celebration)),
        ],
      ),
      top: Column(mainAxisSize: MainAxisSize.min, children: [
        PerkStrip(lang: lang, perks: p.perks, usta: usta),
        const SizedBox(height: 8),
        Row(children: [for (var k = 0; k < 4; k++) Expanded(child: _meter(lang, k, eff?[k] ?? 0))]),
      ]),
      board: SingleChildScrollView(
        child: Center(
          child: GestureDetector(
          onHorizontalDragUpdate: ended ? null : (e) => setState(() => drag += e.delta.dx),
          onHorizontalDragEnd: ended
              ? null
              : (_) {
                  if (drag < -60) {
                    _choose(0);
                  } else if (drag > 60) {
                    _choose(1);
                  } else {
                    setState(() => drag = 0);
                  }
                },
          child: Transform.translate(
            offset: Offset(clampD(drag, -120, 120), 0),
            child: Transform.rotate(angle: clampD(drag, -120, 120) / 900, child: _card(lang, c, season, side)),
          ),
        ),
        ),
      ),
      bottom: Row(children: [
        Expanded(child: _opt(c.left(p.lang), Icons.arrow_back, 0)),
        const SizedBox(width: 8),
        Expanded(child: _opt(c.right(p.lang), Icons.arrow_forward, 1)),
      ]),
    );
  }

  Widget _opt(String label, IconData icon, int ch) {
    final hl = hint == ch;
    return SChip(
      selected: hl,
      color: hl ? const Color(0xFFF6E3B4) : null,
      onTap: ended ? null : () => _choose(ch),
      child: SizedBox(
        height: 44,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (ch == 0) Icon(icon, size: 18),
          const SizedBox(width: 4),
          Flexible(child: Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
          const SizedBox(width: 4),
          if (ch == 1) Icon(icon, size: 18),
        ]),
      ),
    );
  }

  Widget _meter(String lang, int k, int delta) {
    final v = m[k];
    final warn = v <= 2 || v >= 8;
    return Tooltip(
      message: st(lang, kKMeters[k]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(kKMeterIcons[k], color: studioLift(warn ? SColors.bad : kKMeterColors[k]), size: 26),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(value: clampD(v / kKMax, 0, 1), minHeight: 10, color: warn ? SColors.bad : kKMeterColors[k], backgroundColor: Colors.black12),
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          height: 14,
          child: delta == 0
              ? null
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var j = 0; j < (peek ? delta.abs() : 1); j++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Icon(delta > 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down, size: 14, color: delta > 0 ? StudioLook.good : StudioLook.bad),
                    ),
                ]),
        ),
      ]),
    );
  }

  Widget _card(String lang, KCard c, int season, int side) {
    return LayoutBuilder(builder: (context, box) {
      final w = math.min<double>(box.maxWidth, 360);
      return Container(
        width: w,
        padding: const EdgeInsets.all(16),
        // Danışman kartı: onaylı tasarımın degrade kartı, mevsim renginde kenar.
        decoration: BoxDecoration(
          gradient: StudioLook.of(context).tile,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: kKSeasonColors[season], width: 3),
          boxShadow: [BoxShadow(blurRadius: 18, color: kKSeasonColors[season].withValues(alpha: 0.35))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(kKSeasonIcons[season], color: Color.lerp(kKSeasonColors[season], Colors.white, 0.35)),
            const SizedBox(width: 6),
            Expanded(child: Text(st(lang, kKSeasons[season]), style: TextStyle(color: Color.lerp(kKSeasonColors[season], Colors.white, 0.35), fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 10),
          CircleAvatar(radius: 30, backgroundColor: kKMeterColors[c.who % 4].withValues(alpha: 0.45), child: Icon(kKAdvisorIcons[c.who], size: 32, color: Colors.white)),
          const SizedBox(height: 4),
          Text(st(lang, kKAdvisors[c.who]), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kStudioSubtle)),
          const SizedBox(height: 10),
          Text(c.question(lang), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.3, color: Colors.white)),
          const SizedBox(height: 10),
          SizedBox(
            height: 20,
            child: side < 0
                ? null
                : Text(side == 0 ? c.left(lang) : c.right(lang), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: StudioLook.of(context).accent)),
          ),
        ]),
      );
    });
  }
}

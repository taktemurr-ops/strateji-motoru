import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../studio_chrome.dart';
import '../texts.dart';

/// Vadi Kurucu: sıradaki üç yapıdan birini seç, vadide uygun yere koy.
/// Yapılar komşularına göre puan kazanır; hedef puana ulaş.
const int kVN = 7;

/// Arazi: 0 çayır, 1 orman, 2 su, 3 kaya.
const List<String> kVTerrain = ['v_meadow', 'tForest', 'tWater', 'v_rock'];

/// Yapılar: 0 ev, 1 tarla, 2 oduncu, 3 taş ocağı, 4 pazar, 5 kuyu, 6 park, 7 gözetleme kulesi.
const List<String> kVBuild = ['b_house', 'b_field', 'b_lumber', 'b_quarry', 'b_market', 'b_well', 'b_park', 'b_tower'];
const List<IconData> kVIcons = [Icons.home, Icons.grass, Icons.carpenter, Icons.landscape, Icons.storefront, Icons.water_drop, Icons.park, Icons.cell_tower];
const List<Color> kVColors = [
  Color(0xFFB0563B),
  Color(0xFFD9A441),
  Color(0xFF7A5B3A),
  Color(0xFF8C8C8C),
  Color(0xFF7A4E7E),
  Color(0xFF3E6FB0),
  Color(0xFF4F9A6E),
  Color(0xFF5B4636),
];
const List<int> kVWeights = [6, 3, 2, 2, 2, 2, 2, 1];

class VPuzzle extends SPuzzle {
  final int seed, d;
  final List<int> terrain;
  final List<int> queue;
  final int target, best;
  const VPuzzle(this.seed, this.d, this.terrain, this.queue, this.target, this.best);
}

/// [b] yapıları (−1 boş) ve [t] arazi için toplam puan.
int vScore(List<int> t, List<int> b, {int towerBonus = 0}) {
  var s = 0;
  for (var k = 0; k < kVN * kVN; k++) {
    final x = b[k];
    if (x < 0) continue;
    s += vCell(t, b, k, towerBonus: towerBonus);
  }
  return s;
}

int vCell(List<int> t, List<int> b, int k, {int towerBonus = 0}) {
  final x = b[k];
  final cx = k % kVN, cy = k ~/ kVN;
  final n4 = <int>[];
  for (final dd in const [(0, -1), (1, 0), (0, 1), (-1, 0)]) {
    final nx = cx + dd.$1, ny = cy + dd.$2;
    if (nx >= 0 && ny >= 0 && nx < kVN && ny < kVN) n4.add(ny * kVN + nx);
  }
  switch (x) {
    case 0:
      var v = 0;
      var well = false;
      for (final n in n4) {
        if (b[n] == 0) v++;
        if (b[n] == 5) well = true;
        if (b[n] == 6) v++;
      }
      return v + (well ? 2 : 0);
    case 1:
      return 1 + 2 * n4.where((n) => t[n] == 2).length;
    case 2:
      return 2 * n4.where((n) => t[n] == 1).length;
    case 3:
      return 2 * n4.where((n) => t[n] == 3).length;
    case 4:
      final kinds = <int>{};
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = cx + dx, ny = cy + dy;
          if ((dx == 0 && dy == 0) || nx < 0 || ny < 0 || nx >= kVN || ny >= kVN) continue;
          final o = b[ny * kVN + nx];
          if (o >= 0) kinds.add(o);
        }
      }
      return kinds.length;
    case 5:
      return n4.where((n) => b[n] == 0).length;
    case 6:
      return n4.where((n) => b[n] == 0).length + n4.where((n) => t[n] == 1).length;
    default:
      for (var dy = -2; dy <= 2; dy++) {
        for (var dx = -2; dx <= 2; dx++) {
          final nx = cx + dx, ny = cy + dy;
          if ((dx == 0 && dy == 0) || nx < 0 || ny < 0 || nx >= kVN || ny >= kVN) continue;
          if (b[ny * kVN + nx] == 7) return 0;
        }
      }
      return 4 + towerBonus;
  }
}

/// Açgözlü yerleştirici: görünen [look] yapıdan en çok puan getiren yer.
(int, int) vBest(List<int> t, List<int> b, List<int> visible, {int towerBonus = 0}) {
  final base = vScore(t, b, towerBonus: towerBonus);
  var bi = -1, bk = -1, bv = -1 << 20;
  for (var i = 0; i < visible.length; i++) {
    for (var k = 0; k < kVN * kVN; k++) {
      if (t[k] != 0 || b[k] >= 0) continue;
      b[k] = visible[i];
      final v = vScore(t, b, towerBonus: towerBonus) - base;
      b[k] = -1;
      if (v > bv) {
        bv = v;
        bi = i;
        bk = k;
      }
    }
  }
  return (bi, bk);
}

int vBotScore(List<int> t, List<int> queue, int look) {
  final b = List<int>.filled(kVN * kVN, -1);
  final q = [...queue];
  while (q.isNotEmpty) {
    final vis = q.take(look).toList();
    final (i, k) = vBest(t, b, vis);
    if (i < 0) break;
    b[k] = vis[i];
    q.removeAt(i);
  }
  return vScore(t, b);
}

class VSim {
  final VPuzzle z;
  final List<int> b = List<int>.filled(kVN * kVN, -1);
  late List<int> queue;
  final int look, towerBonus;
  int undos, rerolls;
  List<(List<int>, List<int>)> history = [];
  int placed = 0;

  VSim(this.z, {this.look = 3, this.towerBonus = 0, this.undos = 0, this.rerolls = 0, bool extra = false}) {
    queue = [...z.queue, if (extra) 6];
  }

  List<int> get visible => queue.take(look).toList();
  int get score => vScore(z.terrain, b, towerBonus: towerBonus);
  bool get done => queue.isEmpty || !b.asMap().entries.any((e) => e.value < 0 && z.terrain[e.key] == 0);

  bool canPlace(int k) => k >= 0 && k < kVN * kVN && z.terrain[k] == 0 && b[k] < 0;

  void place(int i, int k) {
    if (i < 0 || i >= visible.length || !canPlace(k)) return;
    history.add(([...b], [...queue]));
    b[k] = queue.removeAt(i);
    placed++;
  }

  bool undo() {
    if (undos <= 0 || history.isEmpty) return false;
    final (bb, qq) = history.removeLast();
    for (var k = 0; k < b.length; k++) {
      b[k] = bb[k];
    }
    queue = qq;
    undos--;
    placed--;
    return true;
  }

  void reroll(SeededRandom r) {
    if (rerolls <= 0 || queue.length < 2) return;
    rerolls--;
    r.shuffle(queue);
  }
}

class VadiKind extends StratejiKind {
  @override
  String get id => 'vadi';
  const VadiKind();

  @override
  SPuzzle? make(int d, SeededRandom r) {
    final t = List<int>.filled(kVN * kVN, 0);
    for (var k = 0; k < t.length; k++) {
      final x = r.nextDouble();
      t[k] = x < 0.14 ? 1 : (x < 0.22 ? 2 : (x < 0.30 ? 3 : 0));
    }
    final free = t.where((x) => x == 0).length;
    final n = 14 + d;
    if (free < n + 2) return null;
    final q = [for (var i = 0; i < n; i++) r.weighted(kVWeights)];
    final best = vBotScore(t, q, 3);
    final target = (best * (0.78 + 0.02 * d)).floor();
    if (target < 12) return null;
    return VPuzzle(r.nextUint32(), d, t, q, target, best);
  }

  @override
  bool check(SPuzzle p) => p is VPuzzle && p.best >= p.target && vBotScore(p.terrain, p.queue, 3) == p.best;

  @override
  List<Perk> get perks => const [
        Perk(3, Icons.undo, 'undo', 1),
        Perk(8, Icons.visibility, 'pChoice', 1),
        Perk(15, Icons.park, 'b_park', 1),
        Perk(25, Icons.shuffle, 'pReroll', 1),
        Perk(40, Icons.cell_tower, 'b_tower', 1),
      ];

  @override
  List<GameStat> get stats => const [
        GameStat('runs_won', 'Kurulan vadi', 'Valleys built', scale: 10),
        GameStat('flawless', 'Üç yıldızlı vadi', 'Three-star valleys', scale: 10),
        GameStat('buildings', 'Kurulan yapı', 'Buildings placed', scale: 100),
      ];

  @override
  Widget build(StratejiPlay play) => _VView(play: play);
}

class _VView extends StatefulWidget {
  final StratejiPlay play;
  const _VView({required this.play});
  @override
  State<_VView> createState() => _VViewState();
}

class _VViewState extends State<_VView> with Clock, MetaLoader {
  late VSim s;
  int pick = 0;
  int hints = 0;
  (int, int)? hint;
  late SeededRandom rr;

  StratejiPlay get p => widget.play;
  VPuzzle get z => p.puzzle as VPuzzle;

  VSim _fresh() => VSim(
        z,
        undos: p.has(usta, 0) ? 1 : 0,
        look: p.has(usta, 1) ? 4 : 3,
        extra: p.has(usta, 2),
        rerolls: p.has(usta, 3) ? 1 : 0,
        towerBonus: p.has(usta, 4) ? 1 : 0,
      );

  @override
  void initState() {
    super.initState();
    rr = SeededRandom(mixSeed([z.seed, 3]));
    s = _fresh();
    startClock();
    loadMeta(p.gameId, () => s = _fresh());
  }

  int get _twoStar => z.target + math.max<int>(1, (z.best - z.target) ~/ 2);

  void _finish() {
    if (!s.done) return;
    ended = true;
    final sc = s.score;
    if (sc >= z.target) {
      p.sfx(Sfx.win);
      final stars = (sc >= z.best ? 3 : (sc >= _twoStar ? 2 : 1)) - (hints > 0 ? 1 : 0);
      later(500, () => p.win(score: sc * 10 + p.d * 20, stars: stars, seconds: seconds, moves: s.placed, hints: hints, stats: {'buildings': s.placed}));
    } else {
      later(600, () => p.lose(score: sc * 10, seconds: seconds, moves: s.placed, stats: {'buildings': s.placed}));
    }
  }

  void _tap(Offset o) {
    if (ended) return;
    final x = (o.dx / 10).floor(), y = (o.dy / 10).floor();
    if (x < 0 || y < 0 || x >= kVN || y >= kVN) return;
    final k = y * kVN + x;
    if (!s.canPlace(k) || pick >= s.visible.length) {
      p.sfx(Sfx.error);
      return;
    }
    final before = s.score;
    started = true;
    s.place(pick, k);
    final gain = s.score - before;
    p.sfx(gain >= 4 ? Sfx.combo : (gain > 0 ? Sfx.place : Sfx.tap));
    setState(() {
      pick = 0;
      hint = null;
    });
    _finish();
  }

  Future<void> _hint() async {
    if (ended) return;
    final ok = await p.ctx.requestHint();
    if (!ok || !mounted) return;
    final h = vBest(z.terrain, [...s.b], s.visible, towerBonus: s.towerBonus);
    setState(() {
      hints++;
      hint = h;
      if (h.$1 >= 0) pick = h.$1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = p.lang;
    final sc = s.score;
    final vis = s.visible;
    final status = '${st(lang, 'score')} $sc · ${st(lang, 'target')} ${z.target} · ★★ $_twoStar · ★★★ ${z.best}';
    return SScreen(
      bar: SBar(
        lang: lang,
        left: '${s.queue.length}',
        status: status,
        onHint: ended ? null : _hint,
        onUndo: s.undos > 0 && s.history.isNotEmpty && !ended
            ? () {
                setState(() => s.undo());
                p.sfx(Sfx.tap);
              }
            : null,
        extra: [
          if (s.rerolls > 0 && !ended)
            IconButton(
              tooltip: st(lang, 'pReroll'),
              onPressed: () {
                setState(() {
                  s.reroll(rr);
                  pick = 0;
                  hint = null;
                });
                p.sfx(Sfx.tap);
              },
              icon: const Icon(Icons.shuffle),
            ),
        ],
      ),
      top: Column(mainAxisSize: MainAxisSize.min, children: [
        PerkStrip(lang: lang, perks: p.perks, usta: usta),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: clampD(sc / math.max<int>(1, z.best), 0, 1), minHeight: 8, color: sc >= z.target ? SColors.good : SColors.gold, backgroundColor: Colors.black12),
        ),
      ]),
      board: TapCanvas(w: kVN * 10.0, h: kVN * 10.0, paint: _paint, onTap: _tap, semantics: st(lang, 'vTitle')),
      bottom: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(pick < vis.length ? '${st(lang, kVBuild[vis[pick]])} · ${_rule(lang, vis[pick])}' : '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < vis.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SChip(
                selected: pick == i,
                color: hint?.$1 == i ? const Color(0xFFF6E3B4) : null,
                tooltip: st(lang, kVBuild[vis[i]]),
                onTap: () => setState(() => pick = i),
                child: Icon(kVIcons[vis[i]], color: kVColors[vis[i]], size: 26),
              ),
            ),
          if (s.queue.length > vis.length) Text('+${s.queue.length - vis.length}', style: const TextStyle(color: kStudioSubtle)),
        ]),
      ]),
    );
  }

  /// Seçili yapının kuralı: kısa, simgelerle.
  String _rule(String lang, int b) => switch (b) {
        0 => '+1 ${st(lang, 'b_house')} · +2 ${st(lang, 'b_well')} · +1 ${st(lang, 'b_park')}',
        1 => '+1 · +2 ${st(lang, 'tWater')}',
        2 => '+2 ${st(lang, 'tForest')}',
        3 => '+2 ${st(lang, 'v_rock')}',
        4 => '+1 / ${st(lang, 'pVariety')}',
        5 => '+1 ${st(lang, 'b_house')}',
        6 => '+1 ${st(lang, 'b_house')} · +1 ${st(lang, 'tForest')}',
        _ => '+${4 + s.towerBonus} · ${st(lang, 'pAlone')}',
      };

  void _paint(Canvas c) {
    const tc = [Color(0xFFCFE0A8), Color(0xFF8DB36F), Color(0xFF8FC1DD), Color(0xFFB8AFA4)];
    for (var k = 0; k < kVN * kVN; k++) {
      final x = k % kVN, y = k ~/ kVN;
      final r = Rect.fromLTWH(x * 10.0, y * 10.0, 10, 10);
      final t = z.terrain[k];
      c.drawRect(r, fill(tc[t]));
      if (t == 1) {
        for (final d in const [Offset(3, 4), Offset(7, 6), Offset(4, 8)]) {
          c.drawCircle(r.topLeft + d, 2, fill(const Color(0xFF4E7A45)));
        }
      } else if (t == 2) {
        c.drawLine(r.topLeft + const Offset(2, 4), r.topLeft + const Offset(8, 4), stroke(const Color(0xAAFFFFFF), 0.5));
        c.drawLine(r.topLeft + const Offset(3, 7), r.topLeft + const Offset(7, 7), stroke(const Color(0xAAFFFFFF), 0.5));
      } else if (t == 3) {
        final path = Path()
          ..moveTo(r.left + 2, r.bottom - 2)
          ..lineTo(r.left + 4.5, r.top + 3)
          ..lineTo(r.left + 8, r.bottom - 2)
          ..close();
        c.drawPath(path, fill(const Color(0xFF8A8076)));
      }
      c.drawRect(r, stroke(const Color(0x22000000), 0.3));
      final b = s.b[k];
      if (b >= 0) {
        c.drawRRect(RRect.fromRectAndRadius(r.deflate(1.2), const Radius.circular(2)), fill(kVColors[b]));
        _bglyph(c, r.center, b);
        final v = vCell(z.terrain, s.b, k, towerBonus: s.towerBonus);
        if (v > 0) drawLabel(c, '$v', r.topRight + const Offset(-2, 2.2), 2.8, Colors.white);
      }
    }
    final h = hint;
    if (h != null && h.$2 >= 0) {
      final x = h.$2 % kVN, y = h.$2 ~/ kVN;
      c.drawRect(Rect.fromLTWH(x * 10.0, y * 10.0, 10, 10).deflate(0.6), stroke(SColors.gold, 1.4));
    }
  }

  void _bglyph(Canvas c, Offset o, int b) {
    final w = stroke(Colors.white, 0.7);
    switch (b) {
      case 0:
        final path = Path()
          ..moveTo(o.dx - 2.5, o.dy + 2.5)
          ..lineTo(o.dx - 2.5, o.dy - 0.5)
          ..lineTo(o.dx, o.dy - 2.8)
          ..lineTo(o.dx + 2.5, o.dy - 0.5)
          ..lineTo(o.dx + 2.5, o.dy + 2.5)
          ..close();
        c.drawPath(path, w);
      case 1:
        for (var i = -2; i <= 2; i += 2) {
          c.drawLine(o + Offset(i.toDouble(), 2.5), o + Offset(i.toDouble(), -2.5), w);
        }
      case 2:
        c.drawLine(o + const Offset(-2, 2), o + const Offset(2, -2), w);
        c.drawLine(o + const Offset(1, -2.5), o + const Offset(2.8, -0.8), w);
      case 3:
        c.drawRect(Rect.fromCenter(center: o, width: 4, height: 3), w);
      case 4:
        c.drawLine(o + const Offset(-2.5, -1), o + const Offset(2.5, -1), w);
        c.drawLine(o + const Offset(-2, -1), o + const Offset(-2, 2.5), w);
        c.drawLine(o + const Offset(2, -1), o + const Offset(2, 2.5), w);
      case 5:
        c.drawCircle(o, 2.2, w);
      case 6:
        c.drawCircle(o + const Offset(0, -0.8), 1.8, fill(const Color(0xFFBFE3B4)));
        c.drawLine(o + const Offset(0, 1), o + const Offset(0, 2.8), w);
      default:
        c.drawLine(o + const Offset(0, 2.8), o + const Offset(0, -2.8), w);
        c.drawLine(o + const Offset(-1.6, -2.8), o + const Offset(1.6, -2.8), w);
    }
  }
}

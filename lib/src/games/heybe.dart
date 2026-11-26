import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../studio_chrome.dart';
import '../texts.dart';
import '../versus.dart';

/// Heybe Savaşları: pazardan alınan eşyalar heybeye yerleştirilir (yer
/// sınırlı, eşyalar döndürülebilir), sonra iki heybe kendiliğinden çarpışır.
/// Bileği taşı ve tılsım yalnız komşu silahları güçlendirir; yerleşim
/// stratejinin yarısıdır. Seferde rakipler "hayalet" heybelerdir; düelloda
/// iki oyuncu sırayla kendi heybesini kurar (çevrimiçi masa, aynı cihaz).

/// Eşya: anahtar, genişlik, yükseklik, fiyat, tür, değer, bekleme (sn).
/// Tür: 0 silah, 1 zırh, 2 şifa, 3 bileği taşı, 4 tılsım, 5 iksir, 6 can.
class HbItem {
  final String key;
  final int w, h, price, kind, val;
  final double cd;
  final IconData icon;
  final Color color;
  const HbItem(this.key, this.w, this.h, this.price, this.kind, this.val, this.cd, this.icon, this.color);
}

const List<HbItem> kHbItems = [
  HbItem('hb_sword', 1, 3, 5, 0, 4, 1.6, Icons.hardware, Color(0xFF9AA3AE)),
  HbItem('hb_dagger', 1, 2, 3, 0, 2, 0.9, Icons.content_cut, Color(0xFFB8C2CC)),
  HbItem('hb_shield', 2, 2, 4, 1, 1, 0, Icons.shield, Color(0xFF8C6E54)),
  HbItem('hb_apple', 1, 1, 2, 2, 2, 3.0, Icons.apple, Color(0xFFD94F4F)),
  HbItem('hb_bow', 1, 3, 5, 0, 3, 1.2, Icons.call_made, Color(0xFF4F7F52)),
  HbItem('hb_stone', 1, 1, 3, 3, 1, 0, Icons.diamond, Color(0xFF6C7A89)),
  HbItem('hb_charm', 1, 1, 3, 4, 15, 0, Icons.auto_awesome, Color(0xFFD9A441)),
  HbItem('hb_potion', 1, 1, 3, 5, 8, 0, Icons.local_drink, Color(0xFF7A4E7E)),
  HbItem('hb_axe', 2, 2, 7, 0, 7, 2.2, Icons.carpenter, Color(0xFF5B4636)),
  HbItem('hb_cloak', 2, 1, 4, 6, 6, 0, Icons.checkroom, Color(0xFF2E5E8C)),
];

const int kHbCols = 5;

/// Heybedeki eşya: tür, sol üst köşe, döndürülmüş mü.
class HbPlaced {
  final int item, x, y;
  final bool rot;
  const HbPlaced(this.item, this.x, this.y, this.rot);
  int get w => rot ? kHbItems[item].h : kHbItems[item].w;
  int get h => rot ? kHbItems[item].w : kHbItems[item].h;
  bool covers(int cx, int cy) => cx >= x && cx < x + w && cy >= y && cy < y + h;
  String get code => '$item,$x,$y,${rot ? 1 : 0}';
}

bool hbFits(List<HbPlaced> bag, int rows, int item, int x, int y, bool rot) {
  final p = HbPlaced(item, x, y, rot);
  if (x < 0 || y < 0 || x + p.w > kHbCols || y + p.h > rows) return false;
  for (final q in bag) {
    if (p.x < q.x + q.w && q.x < p.x + p.w && p.y < q.y + q.h && q.y < p.y + p.h) return false;
  }
  return true;
}

/// İlk sığan yer (önce düz, sonra döndürülmüş).
HbPlaced? hbFirstFit(List<HbPlaced> bag, int rows, int item) {
  for (final rot in const [false, true]) {
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < kHbCols; x++) {
        if (hbFits(bag, rows, item, x, y, rot)) return HbPlaced(item, x, y, rot);
      }
    }
  }
  return null;
}

bool _adj(HbPlaced a, HbPlaced b) {
  final ox = a.x <= b.x + b.w && b.x <= a.x + a.w;
  final oy = a.y <= b.y + b.h && b.y <= a.y + a.h;
  final touchX = (a.x + a.w == b.x || b.x + b.w == a.x) && a.y < b.y + b.h && b.y < a.y + a.h;
  final touchY = (a.y + a.h == b.y || b.y + b.h == a.y) && a.x < b.x + b.w && b.x < a.x + a.w;
  return ox && oy && (touchX || touchY);
}

/// Savaşa hazır heybe: silahlar (hasar, bekleme), zırh, şifa, iksir, can.
class HbSide {
  final List<(double, double)> weapons = [];
  final List<(int, double)> heals = [];
  int armor = 0, potion = 0, maxHp;
  HbSide(List<HbPlaced> bag, int baseHp) : maxHp = baseHp {
    for (final p in bag) {
      final it = kHbItems[p.item];
      switch (it.kind) {
        case 0:
          var dmg = it.val.toDouble();
          var cd = it.cd;
          for (final q in bag) {
            if (!_adj(p, q)) continue;
            final k = kHbItems[q.item].kind;
            if (k == 3) dmg += kHbItems[q.item].val;
            if (k == 4) cd *= 1 - kHbItems[q.item].val / 100;
          }
          weapons.add((dmg, cd));
        case 1:
          armor += it.val;
        case 2:
          heals.add((it.val, it.cd));
        case 5:
          potion += it.val;
        case 6:
          maxHp += it.val;
      }
    }
  }
}

/// İki heybenin çarpışması: (kazanan 0/1, -1 berabere; kalan canlar).
(int, int, int) hbFight(List<HbPlaced> a, List<HbPlaced> b, {int hpA = 20, int hpB = 20}) {
  final s = [HbSide(a, hpA), HbSide(b, hpB)];
  final hp = [s[0].maxHp.toDouble(), s[1].maxHp.toDouble()];
  final wt = [for (final x in s) List<double>.filled(x.weapons.length, 0)];
  final ht = [for (final x in s) List<double>.filled(x.heals.length, 0)];
  final pot = [s[0].potion, s[1].potion];
  const dt = 0.1;
  for (var t = 0.0; t < 30 && hp[0] > 0 && hp[1] > 0; t += dt) {
    for (var i = 0; i < 2; i++) {
      final o = 1 - i;
      for (var w = 0; w < s[i].weapons.length; w++) {
        wt[i][w] += dt;
        final (dmg, cd) = s[i].weapons[w];
        if (wt[i][w] >= cd) {
          wt[i][w] -= cd;
          hp[o] -= math.max(1.0, dmg - s[o].armor);
        }
      }
      for (var h = 0; h < s[i].heals.length; h++) {
        ht[i][h] += dt;
        final (v, cd) = s[i].heals[h];
        if (ht[i][h] >= cd) {
          ht[i][h] -= cd;
          hp[i] = math.min(s[i].maxHp.toDouble(), hp[i] + v);
        }
      }
    }
    for (var i = 0; i < 2; i++) {
      if (pot[i] > 0 && hp[i] > 0 && hp[i] < s[i].maxHp / 2) {
        hp[i] = math.min(s[i].maxHp.toDouble(), hp[i] + pot[i]);
        pot[i] = 0;
      }
    }
  }
  final ra = hp[0] / s[0].maxHp, rb = hp[1] / s[1].maxHp;
  final w = hp[0] <= 0 && hp[1] <= 0 ? -1 : (hp[1] <= 0 ? 0 : (hp[0] <= 0 ? 1 : (ra > rb + 1e-9 ? 0 : (rb > ra + 1e-9 ? 1 : -1))));
  return (w, math.max(0, hp[0].ceil()), math.max(0, hp[1].ceil()));
}

/// Pazar: [n] eşya, tohuma bağlı.
List<int> hbShop(int seed, int round, int seat, int reroll, {int n = 4}) {
  final r = SeededRandom(mixSeed([seed, round, seat, reroll, 6203]));
  return [for (var i = 0; i < n; i++) r.nextInt(kHbItems.length)];
}

int hbIncome(int round) => 8 + round;

/// Eşyanın gücü (bot alımı için kaba ölçü).
double hbWorth(int item, List<HbPlaced> bag) {
  final it = kHbItems[item];
  final weapons = bag.where((p) => kHbItems[p.item].kind == 0).length;
  switch (it.kind) {
    case 0:
      return it.val / it.cd * 3;
    case 1:
      return 2.5 + weapons * 0.2;
    case 2:
      return it.val / it.cd * 3;
    case 3:
    case 4:
      return weapons == 0 ? 0.3 : 2.2;
    case 5:
      return 2.0;
    default:
      return 2.0;
  }
}

/// Bot alışverişi: parası yettikçe en değerli sığan eşyayı alır.
(List<HbPlaced>, int) hbBotShop(List<HbPlaced> bag, int rows, int gold, List<int> shop) {
  final b = List<HbPlaced>.of(bag);
  final left = List<int>.of(shop);
  var g = gold;
  while (true) {
    var best = -1;
    var bv = 0.0;
    HbPlaced? bp;
    for (var i = 0; i < left.length; i++) {
      final it = left[i];
      if (it < 0 || kHbItems[it].price > g) continue;
      final pl = hbFirstFit(b, rows, it);
      if (pl == null) continue;
      final v = hbWorth(it, b) / kHbItems[it].price;
      if (v > bv) {
        bv = v;
        best = i;
        bp = pl;
      }
    }
    if (best < 0 || bp == null) break;
    g -= kHbItems[left[best]].price;
    left[best] = -1;
    b.add(bp);
  }
  return (b, g);
}

/// Seferin [round]. hayalet heybesi (gücü zorlukla artar).
List<HbPlaced> hbGhost(int seed, int d, int round) {
  final r = SeededRandom(mixSeed([seed, round, 881]));
  var bag = <HbPlaced>[];
  var gold = 0;
  final mul = 0.55 + 0.05 * d;
  for (var k = 0; k <= round; k++) {
    gold += (hbIncome(k) * mul).round();
    final shop = [for (var i = 0; i < 4; i++) r.nextInt(kHbItems.length)];
    final res = hbBotShop(bag, 4, gold, shop);
    bag = res.$1;
    gold = res.$2;
  }
  return bag;
}

class HbPuzzle extends SPuzzle {
  final int seed, d, rounds, target;
  const HbPuzzle(this.seed, this.d, this.rounds, this.target);
}

class HbRun {
  final HbPuzzle z;
  int rows;
  int round = 0, gold, lives, wins = 0, reroll = 0;
  List<HbPlaced> bag = [];
  late List<int> shop;
  (int, int, int)? last;
  final bool freeReroll;
  HbRun(this.z, {this.rows = 4, int goldBonus = 0, this.lives = 3, int startItem = -1, this.freeReroll = false})
      : gold = hbIncome(0) + goldBonus {
    shop = hbShop(z.seed, round, 0, reroll);
    if (startItem >= 0) bag.add(hbFirstFit(bag, rows, startItem)!);
  }

  bool get won => wins >= z.target;
  bool get lost => lives <= 0 || (round >= z.rounds && !won);
  bool get over => won || lost;

  bool buy(int slot, int x, int y, bool rot) {
    if (slot < 0 || slot >= shop.length || shop[slot] < 0) return false;
    final it = shop[slot];
    if (kHbItems[it].price > gold || !hbFits(bag, rows, it, x, y, rot)) return false;
    gold -= kHbItems[it].price;
    bag.add(HbPlaced(it, x, y, rot));
    shop[slot] = -1;
    return true;
  }

  bool sell(int i) {
    if (i < 0 || i >= bag.length) return false;
    gold += kHbItems[bag[i].item].price ~/ 2;
    bag.removeAt(i);
    return true;
  }

  int get rerollCost => freeReroll && reroll == 0 ? 0 : 1;

  bool doReroll() {
    if (gold < rerollCost) return false;
    gold -= rerollCost;
    reroll++;
    shop = hbShop(z.seed, round, 0, reroll);
    return true;
  }

  void fight() {
    final res = hbFight(bag, hbGhost(z.seed, z.d, round), hpA: 20, hpB: 18 + 2 * round);
    last = res;
    if (res.$1 == 0) {
      wins++;
    } else if (res.$1 == 1) {
      lives--;
    }
    round++;
    reroll = 0;
    gold += hbIncome(round);
    shop = hbShop(z.seed, round, 0, reroll);
  }

  void botRound() {
    final res = hbBotShop(bag, rows, gold, shop);
    bag = res.$1;
    gold = res.$2;
    shop = [for (final _ in shop) -1];
    fight();
  }
}

int hbBot(HbPuzzle z) {
  final s = HbRun(z);
  while (!s.over) {
    s.botRound();
  }
  return s.won ? s.lives : 0;
}

class HeybeKind extends StratejiKind {
  @override
  String get id => 'heybe';
  const HeybeKind();

  @override
  bool get duel => true;

  @override
  SPuzzle? make(int d, SeededRandom r) {
    final z = HbPuzzle(r.nextInt(1 << 30), d, 7 + d ~/ 2, 4 + d ~/ 3);
    return hbBot(z) >= 1 ? z : null;
  }

  @override
  bool check(SPuzzle p) => p is HbPuzzle && p.target <= p.rounds && hbBot(p) >= 1;

  @override
  Widget build(StratejiPlay play) =>
      play.ctx.match != null || play.ctx.passAndPlay ? HbDuelView(play: play) : _HbView(play: play);

  @override
  List<Perk> get perks => const [
        Perk(3, Icons.paid, 'pGold', 2),
        Perk(8, Icons.favorite, 'lives', 1),
        Perk(15, Icons.backpack, 'hb_pRow', 1),
        Perk(25, Icons.refresh, 'pReroll', 0),
        Perk(40, Icons.hardware, 'hb_sword', 0),
      ];

  @override
  List<GameStat> get stats => [
        ...super.stats,
        const GameStat('bag_wins', 'Kazanılan çarpışma', 'Clashes won', scale: 50),
      ];
}

// ---------------------------------------------------------------- ortak çizim

const double _kCell = 10;

void hbPaintBag(Canvas c, List<HbPlaced> bag, int rows, {int hi = -1, HbPlaced? ghost}) {
  final w = kHbCols * _kCell, h = rows * _kCell;
  final r = RRect.fromRectAndRadius(Rect.fromLTWH(-2, -2, w + 4, h + 4), const Radius.circular(5));
  c.drawRRect(r, fill(const Color(0xFF8A5A36)));
  c.drawRRect(r, stroke(const Color(0xFFD9A441), 0.8));
  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < kHbCols; x++) {
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x * _kCell + 0.5, y * _kCell + 0.5, _kCell - 1, _kCell - 1), const Radius.circular(1.5)),
          fill(const Color(0xFFB98A5E)));
    }
  }
  void one(HbPlaced p, {bool sel = false, bool faint = false}) {
    final it = kHbItems[p.item];
    final rr = RRect.fromRectAndRadius(Rect.fromLTWH(p.x * _kCell + 0.8, p.y * _kCell + 0.8, p.w * _kCell - 1.6, p.h * _kCell - 1.6),
        const Radius.circular(2));
    c.drawRRect(rr, fill(faint ? it.color.withValues(alpha: 0.45) : it.color));
    c.drawRRect(rr, stroke(sel ? const Color(0xFFFFE08A) : const Color(0x66000000), sel ? 1.0 : 0.4));
    drawIconAt(c, it.icon, rr.center, math.min(p.w, p.h) * _kCell * 0.6, Colors.white);
  }

  for (var i = 0; i < bag.length; i++) {
    one(bag[i], sel: i == hi);
  }
  final g = ghost;
  if (g != null) one(g, faint: true);
}

void drawIconAt(Canvas c, IconData icon, Offset center, double size, Color color) {
  final tp = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(fontSize: size, color: color, fontFamily: icon.fontFamily, package: icon.fontPackage, height: 1.0),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
}

/// Pazar şeridi.
Widget hbShopRow(String lang, List<int> shop, int gold, int sel, void Function(int) onPick) {
  return Row(children: [
    for (var i = 0; i < shop.length; i++)
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: shop[i] < 0
              ? const SizedBox(height: 48)
              : SChip(
                  selected: sel == i,
                  onTap: () => onPick(i),
                  tooltip: st(lang, kHbItems[shop[i]].key),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(kHbItems[shop[i]].icon, size: 18),
                    Text('${kHbItems[shop[i]].w}×${kHbItems[shop[i]].h} ◉${kHbItems[shop[i]].price}',
                        maxLines: 1, style: TextStyle(fontSize: 10, color: kHbItems[shop[i]].price > gold ? SColors.bad : null)),
                  ]),
                ),
        ),
      ),
  ]);
}

// ---------------------------------------------------------------- sefer

class _HbView extends StatefulWidget {
  final StratejiPlay play;
  const _HbView({required this.play});
  @override
  State<_HbView> createState() => _HbViewState();
}

class _HbViewState extends State<_HbView> with Clock, MetaLoader {
  late HbRun s;
  int sel = -1;
  int selBag = -1;
  bool rot = false;
  int hints = 0;
  String note = '';

  StratejiPlay get p => widget.play;
  HbPuzzle get z => p.puzzle as HbPuzzle;
  String get lang => p.lang;

  HbRun _fresh() => HbRun(z,
      goldBonus: p.has(usta, 0) ? 2 : 0,
      lives: p.has(usta, 1) ? 4 : 3,
      rows: p.has(usta, 2) ? 5 : 4,
      freeReroll: p.has(usta, 3),
      startItem: p.has(usta, 4) ? 0 : -1);

  @override
  void initState() {
    super.initState();
    s = _fresh();
    startClock();
    loadMeta(p.gameId, () => s = _fresh());
  }

  void _tapBag(Offset o) {
    if (ended) return;
    final x = (o.dx / _kCell).floor(), y = (o.dy / _kCell).floor();
    if (sel >= 0) {
      started = true;
      if (s.buy(sel, x, y, rot)) {
        p.sfx(Sfx.place);
        setState(() => sel = -1);
      } else {
        p.sfx(Sfx.error);
      }
      return;
    }
    final i = s.bag.indexWhere((q) => q.covers(x, y));
    setState(() {
      selBag = i == selBag ? -1 : i;
      note = i >= 0 ? st(lang, kHbItems[s.bag[i].item].key) : '';
    });
  }

  void _sell() {
    if (selBag < 0) return;
    started = true;
    if (s.sell(selBag)) p.sfx(Sfx.coin);
    setState(() => selBag = -1);
  }

  void _fight() {
    if (ended) return;
    started = true;
    setState(() {
      s.fight();
      sel = selBag = -1;
      final r = s.last!;
      note = '${st(lang, r.$1 == 0 ? 'youWon' : (r.$1 == 1 ? 'youLost' : 'draw'))} · ♥ ${r.$2} : ${r.$3}';
      p.sfx(r.$1 == 0 ? Sfx.combo : Sfx.error);
    });
    if (s.over) {
      ended = true;
      if (s.won) {
        later(500, () => p.win(score: s.wins * 80 + s.lives * 40 + z.d * 30, stars: s.lives >= 3 ? 3 : (s.lives == 2 ? 2 : 1), seconds: seconds,
            moves: s.round, hints: hints, stats: {'bag_wins': s.wins}));
      } else {
        later(600, () => p.lose(score: s.wins * 80, seconds: seconds, moves: s.round, stats: {'bag_wins': s.wins}));
      }
    }
  }

  void _hint() {
    if (ended) return;
    // En değerli sığan eşyayı bot gibi seçip yerleştirir.
    final res = hbBotShop(s.bag, s.rows, s.gold, s.shop);
    if (res.$1.length == s.bag.length) {
      p.sfx(Sfx.error);
      return;
    }
    hints++;
    final add = res.$1.last;
    final slot = s.shop.indexOf(add.item);
    setState(() {
      if (slot >= 0 && s.buy(slot, add.x, add.y, add.rot)) p.sfx(Sfx.place);
    });
  }

  @override
  Widget build(BuildContext context) {
    final board = TapCanvas(
      w: kHbCols * _kCell + 6,
      h: s.rows * _kCell + 6,
      semantics: st(lang, 'hb_title'),
      paint: (c) {
        c.translate(3, 3);
        hbPaintBag(c, s.bag, s.rows, hi: selBag);
      },
      onTap: (o) => _tapBag(o - const Offset(3, 3)),
    );
    return SScreen(
      bar: SBar(
        lang: lang,
        left: '♥ ${s.lives} · ◉ ${s.gold}',
        status: note.isNotEmpty ? note : '${st(lang, 'round')} ${s.round + 1}/${z.rounds} · ${st(lang, 'target')} ${s.wins}/${z.target}',
        onHint: ended ? null : _hint,
        extra: [
          IconButton(tooltip: st(lang, 'hb_rotate'), onPressed: () => setState(() => rot = !rot), icon: const Icon(Icons.rotate_90_degrees_ccw)),
        ],
      ),
      top: PerkStrip(lang: lang, perks: p.perks, usta: usta),
      board: board,
      bottom: Column(mainAxisSize: MainAxisSize.min, children: [
        hbShopRow(lang, s.shop, s.gold, sel, (i) => setState(() {
              sel = sel == i ? -1 : i;
              selBag = -1;
              note = st(lang, kHbItems[s.shop[i]].key);
              p.sfx(Sfx.tap);
            })),
        const SizedBox(height: 6),
        Row(children: [
          SChip(
            onTap: ended
                ? null
                : () => setState(() {
                      if (s.doReroll()) p.sfx(Sfx.tap);
                    }),
            child: Text('${st(lang, 'reroll')} ◉${s.rerollCost}'),
          ),
          const SizedBox(width: 6),
          if (selBag >= 0) SChip(onTap: _sell, child: Text(st(lang, 'sell'))),
          const Spacer(),
          StudioButton(onPressed: ended ? null : _fight, icon: Icons.sports_kabaddi, label: st(lang, 'fight')),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------- düello

/// İki oyunculu Heybe düellosu: önce mavi, sonra kırmızı heybesini kurar;
/// kırmızı bitirince çarpışma olur. Can 3; 9 tur sonunda fazla canı olan kazanır.
class HbDuel implements DuelGame {
  static const int maxRounds = 9;
  final int seed;
  final List<List<HbPlaced>> bags = [[], []];
  final List<int> gold = [hbIncome(0), hbIncome(0)];
  final List<int> lives = [3, 3];
  final List<int> rerolls = [0, 0];
  final List<List<int>> shops = [[], []];
  int round = 0, seat = 0, moves = 0;
  (int, int, int)? last;
  HbDuel(this.seed) {
    shops[0] = hbShop(seed, 0, 0, 0);
    shops[1] = hbShop(seed, 0, 1, 0);
  }

  @override
  int get turnSeat => seat;

  @override
  int get turnKey => round * 2 + seat;

  @override
  bool get over => lives[0] <= 0 || lives[1] <= 0 || round >= maxRounds;

  @override
  int get winner {
    if (!over) return -2;
    if (lives[0] > lives[1]) return 0;
    if (lives[1] > lives[0]) return 1;
    return -1;
  }

  @override
  int get applied => moves;

  @override
  bool apply(int s, String mv) {
    if (over || s != seat || mv.isEmpty) return false;
    final ok = _apply(s, mv);
    if (ok) moves++;
    return ok;
  }

  bool _apply(int s, String mv) {
    final op = mv[0];
    final args = mv.length > 1 ? mv.substring(1).split(',').map(int.tryParse).toList() : <int?>[];
    if (args.any((a) => a == null)) return false;
    final a = args.cast<int>();
    switch (op) {
      case 'b':
        if (a.length != 4) return false;
        final slot = a[0];
        if (slot < 0 || slot >= shops[s].length || shops[s][slot] < 0) return false;
        final it = shops[s][slot];
        if (kHbItems[it].price > gold[s] || !hbFits(bags[s], 4, it, a[1], a[2], a[3] == 1)) return false;
        gold[s] -= kHbItems[it].price;
        bags[s].add(HbPlaced(it, a[1], a[2], a[3] == 1));
        shops[s][slot] = -1;
        return true;
      case 's':
        if (a.length != 1 || a[0] < 0 || a[0] >= bags[s].length) return false;
        gold[s] += kHbItems[bags[s][a[0]].item].price ~/ 2;
        bags[s].removeAt(a[0]);
        return true;
      case 'r':
        if (gold[s] < 1) return false;
        gold[s]--;
        rerolls[s]++;
        shops[s] = hbShop(seed, round, s, rerolls[s]);
        return true;
      case 'e':
        if (s == 0) {
          seat = 1;
        } else {
          final res = hbFight(bags[0], bags[1]);
          last = res;
          if (res.$1 == 0) lives[1]--;
          if (res.$1 == 1) lives[0]--;
          round++;
          seat = 0;
          for (var i = 0; i < 2; i++) {
            gold[i] += hbIncome(round);
            rerolls[i] = 0;
            shops[i] = hbShop(seed, round, i, 0);
          }
        }
        return true;
    }
    return false;
  }

  @override
  String botMove() {
    final s = seat;
    final res = hbBotShop(bags[s], 4, gold[s], shops[s]);
    if (res.$1.length > bags[s].length) {
      final add = res.$1[bags[s].length];
      final slot = shops[s].indexOf(add.item);
      if (slot >= 0) return 'b$slot,${add.x},${add.y},${add.rot ? 1 : 0}';
    }
    return 'e';
  }

  @override
  String timeoutMove() => 'e';

  @override
  String get hash => '$round|$seat|${lives.join(',')}|${gold.join(',')}|${bags.map((b) => b.map((p) => p.code).join(';')).join('/')}';
}

class HbDuelView extends StatefulWidget {
  final StratejiPlay play;
  const HbDuelView({super.key, required this.play});
  @override
  State<HbDuelView> createState() => HbDuelViewState();
}

class HbDuelViewState extends State<HbDuelView> with Clock, DuelHost {
  int sel = -1, selBag = -1;
  bool rot = false, shown = false, sent = false;

  StratejiPlay get p => widget.play;
  HbDuel get g => game as HbDuel;
  String get lang => p.lang;

  @override
  int get turnSeconds => 30;

  @override
  void initState() {
    super.initState();
    startClock();
    initDuel(HbDuel(p.ctx.match?.seed ?? p.seed), p.ctx);
  }

  /// Ekranda gösterilen heybe: aynı cihazda sırası gelen, yoksa kendi heyben.
  int get shownSeat => mode == DuelMode.hotseat ? g.seat : viewer;

  @override
  void onDuelChanged() {
    sel = -1;
    selBag = -1;
  }

  @override
  void onDuelOver() {
    ended = true;
    p.sfx(localWon ? Sfx.win : Sfx.error);
    later(700, () => setState(() => shown = true));
    if (dctx != null) later(2600, _report);
  }

  void _report() {
    if (!mounted || sent) return;
    sent = true;
    if (localWon) {
      p.win(score: 300 + g.lives[viewer] * 60, stars: 3, seconds: seconds, moves: g.round, stats: {'bag_wins': g.round});
    } else {
      p.lose(score: g.round * 20, seconds: seconds, moves: g.round);
    }
  }

  void _tapBag(Offset o) {
    if (!myTurn) return;
    final x = (o.dx / _kCell).floor(), y = (o.dy / _kCell).floor();
    if (sel >= 0) {
      if (play('b$sel,$x,$y,${rot ? 1 : 0}')) {
        p.sfx(Sfx.place);
      } else {
        p.sfx(Sfx.error);
      }
      return;
    }
    final i = g.bags[g.seat].indexWhere((q) => q.covers(x, y));
    setState(() => selBag = i == selBag ? -1 : i);
  }

  @override
  Widget build(BuildContext context) {
    final me = shownSeat;
    final last = g.last;
    final status = last != null && !game.over
        ? '${turnText(lang)} · ♥ ${last.$2}:${last.$3}'
        : turnText(lang);
    final board = TapCanvas(
      w: kHbCols * _kCell + 6,
      h: 4 * _kCell + 6,
      semantics: st(lang, 'hb_title'),
      paint: (c) {
        c.translate(3, 3);
        hbPaintBag(c, g.bags[me], 4, hi: selBag);
      },
      onTap: (o) => _tapBag(o - const Offset(3, 3)),
    );
    return Stack(children: [
      SScreen(
        bar: SBar(lang: lang, left: '⚑ ${math.min<int>(g.round + 1, HbDuel.maxRounds)}/${HbDuel.maxRounds}', status: status, extra: [
          IconButton(tooltip: st(lang, 'hb_rotate'), onPressed: () => setState(() => rot = !rot), icon: const Icon(Icons.rotate_90_degrees_ccw)),
        ]),
        top: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconNum(Icons.favorite, '${g.lives[0]}', color: seatColor(0)),
          const SizedBox(width: 12),
          IconNum(Icons.paid, '${g.gold[me]}'),
          const SizedBox(width: 12),
          IconNum(Icons.favorite, '${g.lives[1]}', color: seatColor(1)),
        ]),
        board: board,
        bottom: Column(mainAxisSize: MainAxisSize.min, children: [
          if (myTurn)
            hbShopRow(lang, g.shops[g.seat], g.gold[g.seat], sel, (i) => setState(() {
                  sel = sel == i ? -1 : i;
                  p.sfx(Sfx.tap);
                })),
          const SizedBox(height: 6),
          Row(children: [
            SChip(
                onTap: myTurn
                    ? () {
                        if (play('r')) p.sfx(Sfx.tap);
                      }
                    : null,
                child: Text('${st(lang, 'reroll')} ◉1')),
            const SizedBox(width: 6),
            if (selBag >= 0 && myTurn)
              SChip(
                  onTap: () {
                    if (play('s$selBag')) p.sfx(Sfx.coin);
                  },
                  child: Text(st(lang, 'sell'))),
            const Spacer(),
            StudioButton(
                onPressed: myTurn
                    ? () {
                        if (play('e')) p.sfx(Sfx.place);
                      }
                    : null,
                icon: Icons.skip_next,
                label: st(lang, 'endTurn')),
          ]),
        ]),
      ),
      if (shown)
        DuelResultPanel(
          title: resultText(lang),
          color: game.winner < 0 ? SColors.gold : seatColor(game.winner),
          button: st(lang, 'close'),
          onDone: _report,
        ),
    ]);
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../texts.dart';

/// Otomatik Savaşçı: 6×6 meydanda dizilen birlikler kendiliğinden yürür,
/// menziline giren düşmana vurur, mana dolunca sınıf yeteneğini kullanır.
/// Altın turdan tura taşınır (faizli); seviye alınca sahaya daha çok birlik
/// çıkar; üç aynı birlik birleşip yıldız kazanır; eşyalar birliğe takılır.
const int kOsW = 6, kOsH = 6;

/// Birlik türü: ad, sınıf (0 savaşçı, 1 okçu, 2 büyücü, 3 şifacı, 4 haydut),
/// kademe (= fiyat), can, saldırı, menzil, hız (kaç adımda bir davranır), mana sınırı.
class OsType {
  final String key;
  final int cls, tier, hp, atk, range, spd, mana;
  const OsType(this.key, this.cls, this.tier, this.hp, this.atk, this.range, this.spd, this.mana);
}

const List<OsType> kOsTypes = [
  OsType('os_squire', 0, 1, 12, 2, 1, 3, 60),
  OsType('os_scout', 1, 1, 7, 2, 3, 2, 60),
  OsType('os_apprentice', 2, 1, 6, 1, 2, 3, 40),
  OsType('os_acolyte', 3, 1, 8, 1, 2, 3, 40),
  OsType('os_thief', 4, 1, 8, 3, 1, 2, 70),
  OsType('os_knight', 0, 2, 18, 3, 1, 3, 70),
  OsType('os_ranger', 1, 2, 9, 3, 3, 2, 70),
  OsType('os_priest', 3, 2, 11, 1, 2, 3, 40),
  OsType('os_sorcerer', 2, 3, 9, 2, 2, 3, 50),
  OsType('os_blade', 4, 3, 11, 5, 1, 2, 60),
  OsType('os_paladin', 0, 3, 26, 4, 1, 3, 80),
];

const List<Color> kOsClassColors = [Color(0xFF8C6E54), Color(0xFF4F7F52), Color(0xFF5B5FB8), Color(0xFFD9A441), Color(0xFF7A4E7E)];
const List<IconData> kOsClassIcons = [Icons.shield, Icons.call_made, Icons.auto_awesome, Icons.healing, Icons.flash_on];
const List<IconData> kOsItemIcons = [Icons.hardware, Icons.security, Icons.favorite, Icons.menu_book];

double osStarMul(int star) => star == 1 ? 1.0 : (star == 2 ? 1.8 : 3.0);

/// Sahadaki ya da yedekteki birlik: tür, yıldız, takılı eşya (-1 yok).
class OsPiece {
  final int type;
  int star;
  int item;
  OsPiece(this.type, this.star, [this.item = -1]);
  OsType get t => kOsTypes[type];
  double get value => (t.hp + t.atk * 4) * osStarMul(star) + (item >= 0 ? 6 : 0);
}

/// (tür, yıldız, x, y, eşya)
typedef OsSlot = (int, int, int, int, int);

class OsFighter {
  final int type, star, side, cls;
  int x, y, hp, maxHp, atk, def, mana, cd = 0, healBonus;
  OsFighter(this.type, this.star, this.x, this.y, this.side, this.hp, this.atk, this.def, this.mana, this.healBonus)
      : maxHp = hp,
        cls = kOsTypes[type].cls;
  OsType get t => kOsTypes[type];
  bool get alive => hp > 0;
  int dist(OsFighter o) => math.max<int>((x - o.x).abs(), (y - o.y).abs());
}

List<OsFighter> osSide(List<OsSlot> team, int side) {
  final syn = [0, 0, 0, 0, 0];
  for (final (ty, _, _, _, _) in team) {
    syn[kOsTypes[ty].cls]++;
  }
  return [
    for (final (ty, star, x, y, item) in team)
      () {
        final t = kOsTypes[ty];
        final m = osStarMul(star);
        var hp = (t.hp * m).floor(), atk = (t.atk * m).floor(), def = 0, mana = 0;
        if (item == 0) atk += 2;
        if (item == 1) def += 2;
        if (item == 2) hp += 6;
        if (item == 3) mana += 30;
        final c = syn[t.cls];
        if (c >= 2) {
          if (t.cls == 0) def += 2;
          if (t.cls == 1) atk += 1;
          if (t.cls == 2) mana += 20;
          if (t.cls == 4) mana += 30;
        }
        return OsFighter(ty, star, x, y, side, hp, atk, def, mana, t.cls == 3 && c >= 2 ? 3 : 0);
      }(),
  ];
}

/// Sınıfların iki birlikle açılan ortak gücü (sayı).
List<int> osSynergy(List<OsSlot> team) {
  final syn = [0, 0, 0, 0, 0];
  for (final s in team) {
    syn[kOsTypes[s.$1].cls]++;
  }
  return syn;
}

class OsBattle {
  final List<OsFighter> a, b;
  int ticks = 0;
  bool? result;

  /// Kaybedilirse sağ kalan düşmanların bedeli.
  int survivors = 0;

  /// Son adımda vurulan birlikler (çizim için).
  final Set<OsFighter> hit = {};
  OsBattle(List<OsSlot> mine, List<OsSlot> theirs)
      : a = osSide(mine, 0),
        b = osSide(theirs, 1);

  List<OsFighter> get all => [...a, ...b];

  bool _free(int x, int y) => x >= 0 && y >= 0 && x < kOsW && y < kOsH && !all.any((v) => v.alive && v.x == x && v.y == y);

  void _dmg(OsFighter v, int amount) {
    v.hp -= amount;
    hit.add(v);
  }

  void _cast(OsFighter u, OsFighter tgt, List<OsFighter> ops, List<OsFighter> als) {
    switch (u.cls) {
      case 0:
        u.def += 2;
        if (u.type == 10) u.hp = math.min<int>(u.maxHp, u.hp + 6);
      case 1:
        final xs = [...ops]..sort((p, q) => _cmp(u, p, q));
        for (final v in xs.take(2)) {
          _dmg(v, math.max<int>(1, u.atk - v.def));
        }
      case 2:
        final dmg = (u.type == 2 ? 4 : 7) * u.star;
        _dmg(tgt, dmg);
        for (final v in ops) {
          if (!identical(v, tgt) && v.dist(tgt) <= 1) _dmg(v, dmg ~/ 2);
        }
      case 3:
        final w = als.reduce((p, q) => (q.hp - q.maxHp) < (p.hp - p.maxHp) || ((q.hp - q.maxHp) == (p.hp - p.maxHp) && q.hp < p.hp) ? q : p);
        w.hp = math.min<int>(w.maxHp, w.hp + (u.type == 3 ? 5 : 8) * u.star + u.healBonus);
      default:
        final v = ops.reduce((p, q) => q.hp < p.hp || (q.hp == p.hp && q.dist(u) > p.dist(u)) ? q : p);
        _dmg(v, math.max<int>(1, 2 * u.atk - v.def));
    }
  }

  int _cmp(OsFighter u, OsFighter p, OsFighter q) {
    final dp = u.dist(p), dq = u.dist(q);
    if (dp != dq) return dp.compareTo(dq);
    if (p.hp != q.hp) return p.hp.compareTo(q.hp);
    if (p.x != q.x) return p.x.compareTo(q.x);
    return p.y.compareTo(q.y);
  }

  bool? tick() {
    if (result != null) return result;
    ticks++;
    hit.clear();
    for (final u in all) {
      if (!u.alive) continue;
      u.cd++;
      if (u.cd < u.t.spd) continue;
      u.cd = 0;
      final ops = [for (final v in (u.side == 0 ? b : a)) if (v.alive) v];
      final als = [for (final v in (u.side == 0 ? a : b)) if (v.alive) v];
      if (ops.isEmpty) break;
      final tgt = ops.reduce((p, q) => _cmp(u, q, p) < 0 ? q : p);
      if (u.mana >= u.t.mana) {
        u.mana = 0;
        _cast(u, tgt, ops, als);
        continue;
      }
      if (u.dist(tgt) <= u.t.range) {
        _dmg(tgt, math.max<int>(1, u.atk - tgt.def));
        u.mana += 10;
      } else {
        var bd = u.dist(tgt);
        int? bx, by;
        for (var dx = -1; dx <= 1; dx++) {
          for (var dy = -1; dy <= 1; dy++) {
            if (dx == 0 && dy == 0) continue;
            final nx = u.x + dx, ny = u.y + dy;
            if (!_free(nx, ny)) continue;
            final d = math.max<int>((nx - tgt.x).abs(), (ny - tgt.y).abs());
            if (d < bd) {
              bd = d;
              bx = nx;
              by = ny;
            }
          }
        }
        if (bx != null && by != null) {
          u.x = bx;
          u.y = by;
        }
      }
    }
    if (!b.any((v) => v.alive)) return result = true;
    if (!a.any((v) => v.alive)) {
      survivors = b.where((v) => v.alive).fold<int>(0, (s, v) => s + v.star);
      return result = false;
    }
    if (ticks >= 300) {
      final ha = a.fold<int>(0, (s, v) => s + math.max<int>(0, v.hp));
      final hb = b.fold<int>(0, (s, v) => s + math.max<int>(0, v.hp));
      if (ha >= hb) return result = true;
      survivors = b.where((v) => v.alive).length;
      return result = false;
    }
    return null;
  }

  bool run() {
    while (tick() == null) {}
    return result!;
  }
}

class OsPuzzle extends SPuzzle {
  final int seed, d;
  const OsPuzzle(this.seed, this.d);
}

/// Turun rakip dizilişi (tohumdan; her cihazda aynı).
List<OsSlot> osEnemy(int seed, int d, int rnd) {
  final r = SeededRandom(mixSeed([seed, rnd, 7717]));
  final n = math.min<int>(8, 1 + (rnd + 1) ~/ 2 + (d >= 6 && rnd >= 5 ? 1 : 0));
  final budget = rnd * (0.7 + 0.05 * d);
  final used = <int>{};
  final out = <OsSlot>[];
  for (var i = 0; i < n; i++) {
    final maxT = rnd < 3 ? 1 : (rnd < 6 ? 2 : 3);
    final pool = [for (var j = 0; j < kOsTypes.length; j++) if (kOsTypes[j].tier <= maxT) j];
    final ty = r.pick(pool);
    var star = 1;
    if (budget > 4 + i * 1.6 && r.chance(0.25 + 0.03 * d)) star = 2;
    if (budget > 12 && r.chance(0.04 + 0.012 * d)) star = 3;
    final rows = kOsTypes[ty].range == 1 ? const [1, 0] : const [0, 1];
    final cells = [for (final y in rows) for (var x = 0; x < kOsW; x++) if (!used.contains(y * kOsW + x)) y * kOsW + x];
    final c = cells[r.nextInt(math.min<int>(cells.length, 4))];
    used.add(c);
    out.add((ty, star, c % kOsW, c ~/ kOsW, -1));
  }
  return out;
}

class OsRun {
  final int seed, d, rounds, goldBonus, benchSize;
  int rnd = 1, hp, gold = 0, level, merges = 0, wins = 0;
  bool won = false, lost = false;

  /// Saha: yalnız oyuncunun iki sırası (y = 4, 5). Anahtar y*6+x.
  final Map<int, OsPiece> board = {};
  final List<OsPiece> bench = [];
  final List<int> items = [];
  List<int?> shop = [];
  late SeededRandom sr;

  OsRun(this.seed, this.d, {int extraHp = 0, this.goldBonus = 0, int startLevel = 2, bool extraBench = false, int startItem = -1})
      : rounds = 8 + d ~/ 2,
        hp = 20 + extraHp,
        level = startLevel,
        benchSize = extraBench ? 6 : 5 {
    sr = SeededRandom(mixSeed([seed, 4421]));
    if (startItem >= 0) items.add(startItem);
    _startRound();
  }

  int get cap => level + 1;
  bool get over => won || lost;
  static const int maxLevel = 6;

  void _startRound() {
    gold += 5 + math.min<int>(gold ~/ 10, 2) + goldBonus;
    _roll();
  }

  int get maxTier => level <= 2 ? 1 : (level <= 4 ? 2 : 3);

  void _roll() {
    final pool = [for (var j = 0; j < kOsTypes.length; j++) if (kOsTypes[j].tier <= maxTier) j];
    shop = [for (var i = 0; i < 5; i++) sr.pick(pool)];
  }

  List<OsPiece> get units => [...board.values, ...bench];

  bool canBuy(int i) {
    if (i < 0 || i >= shop.length) return false;
    final ty = shop[i];
    if (ty == null || gold < kOsTypes[ty].tier) return false;
    final same = units.where((u) => u.type == ty && u.star == 1).length;
    return bench.length < benchSize || same >= 2;
  }

  void buy(int i) {
    if (!canBuy(i)) return;
    final ty = shop[i]!;
    gold -= kOsTypes[ty].tier;
    shop[i] = null;
    bench.add(OsPiece(ty, 1));
    _merge(ty, 1);
  }

  void _merge(int ty, int star) {
    final onBoard = [for (final e in board.entries) if (e.value.type == ty && e.value.star == star) e.key];
    final onBench = [for (var i = 0; i < bench.length; i++) if (bench[i].type == ty && bench[i].star == star) i];
    if (onBoard.length + onBench.length < 3) return;
    // Sahadaki birlik varsa o kalır; yoksa yedektekilerin ilki.
    final pieces = <OsPiece>[...onBoard.map((k) => board[k]!), ...onBench.map((i) => bench[i])].take(3).toList();
    final keep = pieces.first;
    var item = keep.item;
    for (final p in pieces.skip(1)) {
      if (p.item >= 0) {
        if (item < 0) {
          item = p.item;
        } else {
          items.add(p.item);
        }
      }
    }
    for (final p in pieces.skip(1)) {
      board.removeWhere((_, v) => identical(v, p));
      bench.removeWhere((v) => identical(v, p));
    }
    keep
      ..star = star + 1
      ..item = item;
    merges++;
    if (star + 1 < 3) _merge(ty, star + 1);
  }

  bool get canLevel => gold >= 4 && level < maxLevel;

  void levelUp() {
    if (!canLevel) return;
    gold -= 4;
    level++;
  }

  bool get canReroll => gold >= 1;

  void reroll() {
    if (!canReroll) return;
    gold--;
    _roll();
  }

  /// Birliği satar (eşyası envantere döner).
  void sellPiece(OsPiece p) {
    gold += kOsTypes[p.type].tier * (p.star == 1 ? 1 : (p.star == 2 ? 3 : 8)) - (p.star == 1 ? 0 : 1);
    if (p.item >= 0) items.add(p.item);
    board.removeWhere((_, v) => identical(v, p));
    bench.removeWhere((v) => identical(v, p));
  }

  /// Sahaya koyma ya da yer değiştirme. [cell] = y*6+x, y ∈ {4,5}.
  bool place(OsPiece p, int cell) {
    final y = cell ~/ kOsW;
    if (y < 4 || y > 5) return false;
    final from = board.entries.where((e) => identical(e.value, p)).map((e) => e.key).toList();
    final there = board[cell];
    if (from.isNotEmpty) {
      board.remove(from.first);
      if (there != null) board[from.first] = there;
      board[cell] = p;
      return true;
    }
    // Yedekten geliyor.
    if (there == null && board.length >= cap) return false;
    bench.removeWhere((v) => identical(v, p));
    if (there != null) bench.add(there);
    board[cell] = p;
    return true;
  }

  void toBench(OsPiece p) {
    if (bench.length >= benchSize) return;
    final k = board.entries.where((e) => identical(e.value, p)).map((e) => e.key).toList();
    if (k.isEmpty) return;
    board.remove(k.first);
    bench.add(p);
  }

  bool equip(int itemIndex, OsPiece p) {
    if (itemIndex < 0 || itemIndex >= items.length) return false;
    final old = p.item;
    p.item = items.removeAt(itemIndex);
    if (old >= 0) items.add(old);
    return true;
  }

  List<OsSlot> get team => [for (final e in board.entries) (e.value.type, e.value.star, e.key % kOsW, e.key ~/ kOsW, e.value.item)];

  List<OsSlot> get enemy => osEnemy(seed, d, rnd);

  void resolve(bool win, int survivors) {
    if (win) {
      wins++;
    } else {
      hp -= 2 + survivors;
      if (hp <= 0) {
        hp = 0;
        lost = true;
        return;
      }
    }
    if (rnd % 3 == 0) items.add(sr.nextInt(4));
    if (rnd >= rounds) {
      won = true;
      return;
    }
    rnd++;
    _startRound();
  }

  // ------------------------------------------------------------ yapay zekâ

  double _score(int ty) {
    final own = units.where((u) => u.type == ty).length;
    return own * 5 + kOsTypes[ty].tier * 3 + kOsTypes[ty].hp / 4;
  }

  /// Önerilen pazar hamlesi: alınacak teklif, -1 yenile, -3 seviye, -2 savaş.
  int botMove() {
    if (canLevel && gold >= 7 && board.length + bench.length >= cap && rnd >= 2) return -3;
    int? best;
    for (var i = 0; i < shop.length; i++) {
      final ty = shop[i];
      if (ty == null || gold < kOsTypes[ty].tier || !canBuy(i)) continue;
      if (best == null || _score(ty) > _score(shop[best]!)) best = i;
    }
    if (best != null) {
      final ty = shop[best]!;
      if (units.length < cap + 3 || units.any((u) => u.type == ty)) return best;
    }
    if (gold >= 12) return -1;
    return -2;
  }

  /// Yapay zekâ dizilişi: en güçlüler sahaya, yakın dövüşçüler önde.
  void arrange() {
    final all = units..sort((p, q) => q.value.compareTo(p.value));
    final pick = all.take(cap).toList();
    final rest = all.skip(cap).toList();
    for (final p in pick) {
      if (items.isEmpty) break;
      if (p.item < 0) p.item = items.removeLast();
    }
    board.clear();
    bench
      ..clear()
      ..addAll(rest.take(benchSize));
    // Fazlalık satılır.
    for (final p in rest.skip(benchSize)) {
      gold += kOsTypes[p.type].tier;
    }
    final front = [for (final p in pick) if (p.t.range == 1) p];
    final back = [for (final p in pick) if (p.t.range > 1) p];
    const cols = [2, 3, 1, 4, 0, 5];
    for (var i = 0; i < front.length && i < 6; i++) {
      board[4 * kOsW + cols[i]] = front[i];
    }
    final restFront = front.skip(6).toList();
    final backs = [...back, ...restFront];
    for (var i = 0; i < backs.length; i++) {
      var cell = (i < 6 ? 5 : 4) * kOsW + cols[i % 6];
      if (board.containsKey(cell)) {
        final free = [for (final rr in const [5, 4]) for (final cc in cols) if (!board.containsKey(rr * kOsW + cc)) rr * kOsW + cc];
        if (free.isEmpty) break;
        cell = free.first;
      }
      board[cell] = backs[i];
    }
  }

  /// Yapay zekâ bir pazar evresini oynar.
  void botShop() {
    var guard = 0;
    while (guard++ < 60) {
      final m = botMove();
      if (m >= 0) {
        buy(m);
      } else if (m == -1) {
        reroll();
      } else if (m == -3) {
        levelUp();
      } else {
        break;
      }
    }
    arrange();
  }
}

class SavasciKind extends StratejiKind {
  @override
  String get id => 'savasci';
  const SavasciKind();

  @override
  SPuzzle? make(int d, SeededRandom r) => OsPuzzle(r.nextUint32(), d);

  @override
  bool check(SPuzzle p) {
    if (p is! OsPuzzle) return false;
    final s = OsRun(p.seed, p.d);
    var guard = 0;
    while (!s.over && guard++ < 40) {
      s.botShop();
      final b = OsBattle(s.team, s.enemy);
      s.resolve(b.run(), b.survivors);
    }
    return s.won;
  }

  @override
  List<Perk> get perks => const [
        Perk(3, Icons.paid, 'pGold', 1),
        Perk(8, Icons.favorite, 'os_pHp', 5),
        Perk(15, Icons.inventory_2, 'os_pBench', 1),
        Perk(25, Icons.trending_up, 'os_pLevel', 1),
        Perk(40, Icons.backpack, 'os_pItem', 0),
      ];

  @override
  List<GameStat> get stats => const [
        GameStat('runs_won', 'Kazanılan sefer', 'Runs won', scale: 10),
        GameStat('flawless', 'Kusursuz sefer', 'Flawless runs', scale: 10),
        GameStat('merges', 'Birleşen birlik', 'Units merged', scale: 20),
      ];

  @override
  Widget build(StratejiPlay play) => _OsView(play: play);
}

class _OsView extends StatefulWidget {
  final StratejiPlay play;
  const _OsView({required this.play});
  @override
  State<_OsView> createState() => _OsViewState();
}

class _OsViewState extends State<_OsView> with Clock, MetaLoader {
  late OsRun s;
  OsBattle? battle;
  OsPiece? sel;
  int selItem = -1;
  int hints = 0, hinted = -9, lostRounds = 0;
  String note = '';

  StratejiPlay get p => widget.play;
  OsPuzzle get z => p.puzzle as OsPuzzle;
  String get lang => p.lang;

  OsRun _fresh() => OsRun(
        z.seed,
        z.d,
        goldBonus: p.has(usta, 0) ? 1 : 0,
        extraHp: p.has(usta, 1) ? 5 : 0,
        extraBench: p.has(usta, 2),
        startLevel: p.has(usta, 3) ? 3 : 2,
        startItem: p.has(usta, 4) ? 0 : -1,
      );

  @override
  void initState() {
    super.initState();
    s = _fresh();
    startClock();
    loadMeta(p.gameId, () => s = _fresh());
  }

  bool get busy => ended || battle != null;

  void _buy(int i) {
    if (busy) return;
    if (!s.canBuy(i)) {
      p.sfx(Sfx.error);
      return;
    }
    started = true;
    final m0 = s.merges;
    s.buy(i);
    p.sfx(s.merges > m0 ? Sfx.combo : Sfx.coin);
    setState(() => hinted = -9);
  }

  void _tapPiece(OsPiece piece) {
    if (busy) return;
    if (selItem >= 0) {
      started = true;
      s.equip(selItem, piece);
      p.sfx(Sfx.place);
      setState(() => selItem = -1);
      return;
    }
    setState(() => sel = identical(sel, piece) ? null : piece);
  }

  void _tapCell(int cell) {
    if (busy) return;
    final there = s.board[cell];
    final cur = sel;
    if (cur == null) {
      if (there != null) _tapPiece(there);
      return;
    }
    if (identical(cur, there)) {
      setState(() => sel = null);
      return;
    }
    started = true;
    if (s.place(cur, cell)) {
      p.sfx(Sfx.place);
    } else {
      p.sfx(Sfx.error);
      setState(() => note = st(lang, 'os_full'));
    }
    setState(() => sel = null);
  }

  void _toBench() {
    final cur = sel;
    if (busy || cur == null) return;
    started = true;
    s.toBench(cur);
    setState(() => sel = null);
  }

  void _sell() {
    final cur = sel;
    if (busy || cur == null) return;
    started = true;
    s.sellPiece(cur);
    p.sfx(Sfx.coin);
    setState(() => sel = null);
  }

  void _fight() {
    if (busy) return;
    if (s.board.isEmpty) {
      p.sfx(Sfx.error);
      setState(() => note = st(lang, 'os_empty'));
      return;
    }
    started = true;
    final b = OsBattle(s.team, s.enemy);
    setState(() {
      battle = b;
      sel = null;
      selItem = -1;
      hinted = -9;
      note = '';
    });
    _step();
  }

  void _step() {
    final b = battle;
    if (b == null || !mounted) return;
    b.tick();
    setState(() {});
    if (b.result == null) {
      later(90, _step);
      return;
    }
    final win = b.result!;
    p.sfx(win ? Sfx.clear : Sfx.error);
    later(800, () {
      if (!win) lostRounds++;
      final hp0 = s.hp;
      s.resolve(win, b.survivors);
      setState(() {
        battle = null;
        note = win ? '✓ ${st(lang, 'round')} ${s.over ? s.rnd : s.rnd - 1}' : '✗ −${hp0 - s.hp} ♥';
      });
      if (s.won) {
        ended = true;
        p.sfx(Sfx.win);
        final stars = (lostRounds == 0 ? 3 : (s.hp >= 12 ? 2 : 1)) - (hints > 0 ? 1 : 0);
        later(400, () => p.win(score: s.wins * 60 + s.hp * 20 + p.d * 30, stars: stars, seconds: seconds, moves: s.rnd, hints: hints, stats: {'merges': s.merges}));
      } else if (s.lost) {
        ended = true;
        later(500, () => p.lose(score: s.wins * 60, seconds: seconds, moves: s.rnd, stats: {'merges': s.merges}));
      }
    });
  }

  Future<void> _hint() async {
    if (busy) return;
    final ok = await p.ctx.requestHint();
    if (!ok || !mounted) return;
    setState(() {
      hints++;
      hinted = s.botMove();
      if (hinted == -2) s.arrange();
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = battle;
    final syn = osSynergy(s.team);
    final status = note.isNotEmpty && b == null ? note : '${st(lang, 'round')} ${s.rnd}/${s.rounds} · ${st(lang, 'units')} ${s.board.length}/${s.cap}';
    return SScreen(
      bar: SBar(lang: lang, left: '♥ ${s.hp} · ◉ ${s.gold} · Lv ${s.level}', status: status, onHint: busy ? null : _hint),
      top: PerkStrip(lang: lang, perks: p.perks, usta: usta),
      board: Column(children: [
        Expanded(child: _field(b)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 2, alignment: WrapAlignment.center, children: [
          for (var c = 0; c < 5; c++)
            if (syn[c] > 0)
              Tooltip(
                message: st(lang, 'os_syn$c'),
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(kOsClassIcons[c], size: 14, color: kOsClassColors[c]),
                  label: Text('${st(lang, 'os_cl$c')} ${syn[c]}${syn[c] >= 2 ? ' ✓' : ''}', style: const TextStyle(fontSize: 11)),
                ),
              ),
        ]),
        if (b == null) _benchRow(),
      ]),
      bottom: b != null ? null : _shopPanel(),
    );
  }

  Widget _field(OsBattle? b) {
    final enemy = b == null ? s.enemy : null;
    return LayoutBuilder(builder: (context, box) {
      final cell = math.min(box.maxWidth / kOsW, box.maxHeight / kOsH);
      return Center(
        child: SizedBox(
          width: cell * kOsW,
          height: cell * kOsH,
          child: Stack(children: [
            Positioned.fill(
              child: TapCanvas(
                w: kOsW.toDouble(),
                h: kOsH.toDouble(),
                semantics: st(lang, 'os_title'),
                onTap: (o) {
                  final x = o.dx.floor(), y = o.dy.floor();
                  if (x >= 0 && x < kOsW && y >= 4 && y < kOsH) _tapCell(y * kOsW + x);
                },
                paint: (c) {
                  for (var y = 0; y < kOsH; y++) {
                    for (var x = 0; x < kOsW; x++) {
                      final mine = y >= 4;
                      final col = (x + y).isEven ? (mine ? const Color(0xFFE3D6BC) : const Color(0xFFD8CDB8)) : (mine ? const Color(0xFFEADFC8) : const Color(0xFFE2D8C4));
                      c.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1), fill(col));
                    }
                  }
                  c.drawLine(const Offset(0, 3), const Offset(6, 3), stroke(const Color(0x33000000), 0.03));
                  if (b != null) {
                    for (final u in b.all) {
                      if (!u.alive) continue;
                      _unit(c, Offset(u.x + 0.5, u.y + 0.5), u.type, u.star, u.side, b.hit.contains(u));
                      c.drawRect(Rect.fromLTWH(u.x + 0.12, u.y + 0.86, 0.76, 0.07), fill(const Color(0x44000000)));
                      c.drawRect(Rect.fromLTWH(u.x + 0.12, u.y + 0.86, 0.76 * clampD(u.hp / u.maxHp, 0, 1), 0.07), fill(u.side == 0 ? SColors.good : SColors.bad));
                      c.drawRect(Rect.fromLTWH(u.x + 0.12, u.y + 0.93, 0.76 * clampD(u.mana / u.t.mana, 0, 1), 0.04), fill(const Color(0xFF5B8DB8)));
                    }
                  } else {
                    for (final (t, star, x, y, _) in enemy!) {
                      _unit(c, Offset(x + 0.5, y + 0.5), t, star, 1, false);
                    }
                    for (final e in s.board.entries) {
                      final x = e.key % kOsW, y = e.key ~/ kOsW;
                      if (identical(e.value, sel)) c.drawRect(Rect.fromLTWH(x + 0.04, y + 0.04, 0.92, 0.92), stroke(SColors.gold, 0.08));
                      _unit(c, Offset(x + 0.5, y + 0.5), e.value.type, e.value.star, 0, false);
                      if (e.value.item >= 0) drawLabel(c, '◆', Offset(x + 0.85, y + 0.15), 0.25, const Color(0xFF5B8DB8));
                    }
                  }
                },
              ),
            ),
          ]),
        ),
      );
    });
  }

  Widget _benchRow() => SizedBox(
        height: 58,
        child: Row(children: [
          IconButton(
            tooltip: st(lang, 'os_bench'),
            onPressed: sel != null && s.board.values.any((v) => identical(v, sel)) && !busy ? _toBench : null,
            icon: const Icon(Icons.arrow_downward),
          ),
          Expanded(
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final piece in s.bench)
                GestureDetector(
                  onTap: () => _tapPiece(piece),
                  child: Container(
                    width: 50,
                    margin: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4EBDD),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: identical(sel, piece) ? SColors.gold : kOsClassColors[piece.t.cls], width: identical(sel, piece) ? 3 : 1.5),
                    ),
                    child: Semantics(
                      label: st(lang, piece.t.key),
                      child: TapCanvas(w: 1, h: 1, paint: (c) => _unit(c, const Offset(0.5, 0.5), piece.type, piece.star, 0, false)),
                    ),
                  ),
                ),
              for (var i = 0; i < s.items.length; i++)
                GestureDetector(
                  onTap: busy ? null : () => setState(() => selItem = selItem == i ? -1 : i),
                  child: Tooltip(
                    message: st(lang, 'os_it${s.items[i]}'),
                    child: Container(
                      width: 42,
                      margin: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCE4E8),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: selItem == i ? SColors.gold : Colors.black26, width: selItem == i ? 3 : 1),
                      ),
                      child: Icon(kOsItemIcons[s.items[i]], color: SColors.ink),
                    ),
                  ),
                ),
            ]),
          ),
          IconButton(tooltip: st(lang, 'sell'), onPressed: sel != null && !busy ? _sell : null, icon: const Icon(Icons.sell)),
        ]),
      );

  Widget _shopPanel() => Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          for (var i = 0; i < s.shop.length; i++) Expanded(child: Padding(padding: const EdgeInsets.all(2), child: _shopCard(i))),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          IconButton.filledTonal(
            tooltip: '${st(lang, 'reroll')} (◉1)',
            onPressed: s.canReroll && !busy
                ? () {
                    started = true;
                    setState(() {
                      s.reroll();
                      hinted = -9;
                    });
                    p.sfx(Sfx.tap);
                  }
                : null,
            icon: Icon(Icons.refresh, color: hinted == -1 ? SColors.gold : null),
          ),
          IconButton.filledTonal(
            tooltip: '${st(lang, 'os_levelUp')} (◉4)',
            onPressed: s.canLevel && !busy
                ? () {
                    started = true;
                    setState(() {
                      s.levelUp();
                      hinted = -9;
                    });
                    p.sfx(Sfx.unlock);
                  }
                : null,
            icon: Icon(Icons.trending_up, color: hinted == -3 ? SColors.gold : null),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: FilledButton.icon(
              onPressed: busy ? null : _fight,
              icon: Icon(hinted == -2 ? Icons.lightbulb : Icons.sports_kabaddi),
              label: Text(st(lang, 'battle')),
            ),
          ),
        ]),
      ]);

  Widget _shopCard(int i) {
    final ty = s.shop[i];
    if (ty == null) return const SizedBox(height: 74);
    final t = kOsTypes[ty];
    final ok = s.canBuy(i);
    return GestureDetector(
      onTap: () => _buy(i),
      child: Opacity(
        opacity: ok ? 1 : 0.45,
        child: Container(
          height: 74,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFFF4EBDD),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: hinted == i ? SColors.gold : kOsClassColors[t.cls], width: hinted == i ? 3 : 1.5),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 28, height: 28, child: TapCanvas(w: 1, h: 1, paint: (c) => _unit(c, const Offset(0.5, 0.5), ty, 1, 0, false))),
              Text(st(lang, t.key), maxLines: 1, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: SColors.ink)),
              Text('${st(lang, 'os_cl${t.cls}')} · ◉${t.tier}', style: TextStyle(fontSize: 9, color: kOsClassColors[t.cls])),
              Text('♥${t.hp} ⚔${t.atk} ↔${t.range}', style: const TextStyle(fontSize: 9, color: SColors.ink)),
            ]),
          ),
        ),
      ),
    );
  }

  /// Birlik çizimi (birim kareye göre): sınıf rengi gövde, sınıf işareti,
  /// yıldızlar; rakip birlikler kırmızı halkalı.
  void _unit(Canvas c, Offset o, int type, int star, int side, bool flash) {
    final t = kOsTypes[type];
    final col = kOsClassColors[t.cls];
    final r = 0.3 + 0.03 * t.tier;
    if (flash) c.drawCircle(o, r + 0.1, fill(const Color(0x66FFFFFF)));
    c.drawCircle(o, r + 0.05, fill(side == 0 ? const Color(0xFF3E6FB0) : const Color(0xFFC8553D)));
    c.drawCircle(o, r, fill(col));
    final ink = stroke(const Color(0xEEFFFFFF), 0.06);
    switch (t.cls) {
      case 0:
        final sh = Path()
          ..moveTo(o.dx - r * 0.5, o.dy - r * 0.5)
          ..lineTo(o.dx + r * 0.5, o.dy - r * 0.5)
          ..lineTo(o.dx + r * 0.45, o.dy + r * 0.1)
          ..lineTo(o.dx, o.dy + r * 0.6)
          ..lineTo(o.dx - r * 0.45, o.dy + r * 0.1)
          ..close();
        c.drawPath(sh, ink);
      case 1:
        c.drawArc(Rect.fromCircle(center: o + Offset(-r * 0.15, 0), radius: r * 0.55), -math.pi / 2, math.pi, false, ink);
        c.drawLine(o + Offset(-r * 0.15, -r * 0.55), o + Offset(-r * 0.15, r * 0.55), ink);
        c.drawLine(o + Offset(-r * 0.5, 0), o + Offset(r * 0.6, 0), ink);
      case 2:
        for (var i = 0; i < 5; i++) {
          final a = -math.pi / 2 + i * 4 * math.pi / 5;
          final b = -math.pi / 2 + (i + 2) * 4 * math.pi / 5;
          c.drawLine(o + Offset(math.cos(a), math.sin(a)) * r * 0.6, o + Offset(math.cos(b), math.sin(b)) * r * 0.6, ink);
        }
      case 3:
        c.drawLine(o + Offset(0, -r * 0.55), o + Offset(0, r * 0.55), stroke(Colors.white, 0.12));
        c.drawLine(o + Offset(-r * 0.55, 0), o + Offset(r * 0.55, 0), stroke(Colors.white, 0.12));
      default:
        c.drawLine(o + Offset(-r * 0.45, r * 0.45), o + Offset(r * 0.45, -r * 0.45), ink);
        c.drawLine(o + Offset(-r * 0.2, r * 0.05), o + Offset(r * 0.05, r * 0.3), ink);
    }
    if (star > 1) drawLabel(c, '★' * star, o + Offset(0, r + 0.1), 0.2, SColors.gold);
  }
}

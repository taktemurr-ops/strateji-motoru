import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import '../core.dart';
import '../texts.dart';

/// Kum Saati Arenası: pazardan birlik al, iki sıralık sahaya diz; savaş
/// kendiliğinden döner. Üç aynı birlik birleşip yıldız kazanır; aynı
/// soydan birlikler birbirini güçlendirir.
class ArType {
  final String key;
  final int hp, atk, spd, tribe, def, heal, thorns;
  final bool ranged;
  final Color color;
  const ArType(this.key, this.hp, this.atk, this.spd, this.ranged, this.tribe, this.color, {this.def = 0, this.heal = 0, this.thorns = 0});
}

/// Soylar: 0 orman (+can), 1 rüzgâr (+hız), 2 taş (+zırh), 3 ışık (+saldırı).
const List<String> kTribeKeys = ['tr_forest', 'tr_wind', 'tr_stone', 'tr_light'];
const List<Color> kTribeColors = [Color(0xFF4F7F52), Color(0xFF5B8DB8), Color(0xFF8C7E6E), Color(0xFFD9A441)];

/// Python modeliyle aynı sıra (adlara göre sıralı).
const List<ArType> kArTypes = [
  ArType('m_firefly', 5, 2, 2, true, 3, Color(0xFFE8C547)),
  ArType('m_owl', 6, 3, 3, true, 1, Color(0xFF8A7BA8)),
  ArType('m_thorn', 8, 2, 3, false, 0, Color(0xFF6E9B58), thorns: 1),
  ArType('m_deer', 9, 2, 4, false, 3, Color(0xFFE6D8A8), heal: 2),
  ArType('m_turtle', 16, 1, 5, false, 2, Color(0xFF7D8C7A), def: 1),
  ArType('m_wolf', 10, 4, 4, false, 2, Color(0xFF8FB3C9)),
  ArType('m_oak', 14, 2, 4, false, 0, Color(0xFF7A5B3A)),
  ArType('m_fox', 7, 2, 2, false, 1, Color(0xFFD9822B)),
];

class ArPiece {
  final int type;
  int star;
  ArPiece(this.type, this.star);
  ArType get t => kArTypes[type];
}

/// Savaştaki canlı birlik.
class ArFighter {
  final int type, star, slot, side;
  int hp, maxHp, atk, spd, def, cd = 0;
  ArFighter(this.type, this.star, this.slot, this.side, this.hp, this.atk, this.spd, this.def) : maxHp = hp;
  ArType get t => kArTypes[type];
  bool get alive => hp > 0;
}

List<ArFighter> arSide(List<(int, int, int)> team, int side) {
  final tribes = [0, 0, 0, 0];
  for (final (ty, _, _) in team) {
    tribes[kArTypes[ty].tribe]++;
  }
  return [
    for (final (ty, star, slot) in team)
      () {
        final t = kArTypes[ty];
        final m = star == 1 ? 1.0 : (star == 2 ? 1.8 : 3.0);
        final c = tribes[t.tribe];
        return ArFighter(
          ty,
          star,
          slot,
          side,
          (t.hp * m).floor() + (t.tribe == 0 && c >= 2 ? 3 : 0) + (t.tribe == 0 && c >= 3 ? 3 : 0),
          (t.atk * m).floor() + (t.tribe == 3 && c >= 2 ? 1 : 0),
          math.max<int>(1, t.spd - (t.tribe == 1 && c >= 2 ? 1 : 0)),
          t.def + (t.tribe == 2 && c >= 2 ? 1 : 0),
        );
      }(),
  ];
}

class ArBattle {
  final List<ArFighter> a, b;
  int ticks = 0;
  bool? result;
  ArBattle(List<(int, int, int)> mine, List<(int, int, int)> theirs)
      : a = arSide(mine, 0),
        b = arSide(theirs, 1);

  void _act(List<ArFighter> me, List<ArFighter> op) {
    for (final u in me) {
      if (!u.alive) continue;
      u.cd++;
      if (u.cd < u.spd) continue;
      u.cd = 0;
      final live = [for (final x in op) if (x.alive) x];
      if (live.isEmpty) return;
      ArFighter tgt;
      if (u.t.ranged) {
        tgt = live.reduce((x, y) => (y.hp < x.hp || (y.hp == x.hp && y.slot < x.slot)) ? y : x);
      } else {
        final front = [for (final x in live) if (x.slot < 3) x];
        final pool = front.isEmpty ? live : front;
        int key(ArFighter x) => (x.slot % 3 - u.slot % 3).abs() * 10 + x.slot;
        tgt = pool.reduce((x, y) => key(y) < key(x) ? y : x);
      }
      tgt.hp -= math.max<int>(1, u.atk - tgt.def);
      if (tgt.t.thorns > 0 && !u.t.ranged) u.hp -= tgt.t.thorns;
      if (u.t.heal > 0 && u.alive) {
        final al = [for (final x in me) if (x.alive) x];
        if (al.isNotEmpty) {
          final w = al.reduce((x, y) => y.hp < x.hp ? y : x);
          w.hp = math.min<int>(w.maxHp + 4, w.hp + u.t.heal * u.star);
        }
      }
    }
  }

  /// Bir adım; savaş bittiyse sonuç döner.
  bool? tick() {
    if (result != null) return result;
    ticks++;
    _act(a, b);
    _act(b, a);
    if (!b.any((x) => x.alive)) return result = true;
    if (!a.any((x) => x.alive)) return result = false;
    if (ticks >= 400) {
      final ha = a.fold<int>(0, (s, x) => s + math.max<int>(0, x.hp));
      final hb = b.fold<int>(0, (s, x) => s + math.max<int>(0, x.hp));
      return result = ha >= hb;
    }
    return null;
  }

  bool run() {
    while (tick() == null) {}
    return result!;
  }
}

class ArPuzzle extends SPuzzle {
  final int seed, d;
  const ArPuzzle(this.seed, this.d);
}

List<(int, int, int)> arEnemy(int seed, int d, int rnd) {
  final r = SeededRandom(mixSeed([seed, rnd, 991]));
  final n = math.min<int>(6, 1 + rnd ~/ 2 + (d >= 8 && rnd >= 4 ? 1 : 0));
  final budget = rnd * (0.85 + 0.035 * d);
  final team = <(int, int)>[];
  for (var i = 0; i < n; i++) {
    final t = r.nextInt(kArTypes.length);
    var star = 1;
    if (budget > 3 + i * 1.5 && r.chance(0.3 + 0.02 * d)) star = 2;
    if (budget > 9 && r.chance(0.05 + 0.015 * d)) star = 3;
    team.add((t, star));
  }
  team.sort((x, y) {
    final rx = kArTypes[x.$1].ranged ? 1 : 0, ry = kArTypes[y.$1].ranged ? 1 : 0;
    if (rx != ry) return rx.compareTo(ry);
    return kArTypes[y.$1].hp.compareTo(kArTypes[x.$1].hp);
  });
  return [for (var i = 0; i < team.length; i++) (team[i].$1, team[i].$2, i)];
}

class ArSim {
  final int seed, d;
  final int rounds;
  int round = 1, lives, gold = 0, rerolls = 0;
  final int goldBonus, capBonus, freeRerolls;

  /// Saha: 6 yuva (0-2 ön sıra, 3-5 arka sıra).
  final List<ArPiece?> board = List<ArPiece?>.filled(6, null);
  List<int?> shop = [];
  late SeededRandom sr;
  bool won = false, lost = false;
  int wins = 0, merges = 0;

  ArSim(this.seed, this.d, {int extraLives = 0, this.goldBonus = 0, this.capBonus = 0, this.freeRerolls = 0, bool starter = false})
      : rounds = 7 + d ~/ 2,
        lives = 3 + extraLives {
    final r = SeededRandom(mixSeed([seed, 1203]));
    sr = SeededRandom(r.nextUint32());
    if (starter) board[0] = ArPiece(6, 2);
    _startRound();
  }

  int get cap => math.min<int>(6, 2 + round ~/ 2 + capBonus);
  int get count => board.where((x) => x != null).length;
  bool get over => won || lost;

  void _startRound() {
    gold = 9 + math.min<int>(round, 3) + goldBonus;
    rerolls = 0;
    _roll();
  }

  void _roll() {
    shop = [for (var i = 0; i < 4; i++) sr.nextInt(kArTypes.length)];
  }

  int owned(int type, int star) => board.where((x) => x != null && x.type == type && x.star == star).length;

  bool canBuy(int i) {
    if (i < 0 || i >= shop.length) return false;
    final t = shop[i];
    if (t == null || gold < 3) return false;
    return count < cap || owned(t, 1) >= 2;
  }

  void buy(int i) {
    if (!canBuy(i)) return;
    final t = shop[i]!;
    gold -= 3;
    shop[i] = null;
    if (owned(t, 1) >= 2) {
      _merge(t, 1, extra: true);
    } else {
      final slot = _freeSlot(kArTypes[t].ranged);
      board[slot] = ArPiece(t, 1);
      if (owned(t, 1) >= 3) _merge(t, 1);
    }
  }

  int _freeSlot(bool ranged) {
    final order = ranged ? const [3, 4, 5, 0, 1, 2] : const [0, 1, 2, 3, 4, 5];
    for (final s in order) {
      if (board[s] == null) return s;
    }
    return 0;
  }

  /// Üç aynı birlik birleşir (yeni alınan [extra] ise sahadaki iki tanesiyle).
  void _merge(int t, int star, {bool extra = false}) {
    var need = extra ? 2 : 3;
    var keep = -1;
    for (var s = 0; s < 6 && need > 0; s++) {
      final x = board[s];
      if (x != null && x.type == t && x.star == star) {
        if (keep < 0) {
          keep = s;
        } else {
          board[s] = null;
        }
        need--;
      }
    }
    if (keep >= 0) {
      board[keep] = ArPiece(t, star + 1);
      merges++;
      if (star + 1 < 3 && owned(t, star + 1) >= 3) _merge(t, star + 1);
    }
  }

  bool get canReroll => rerolls < freeRerolls || gold >= 1;

  void reroll() {
    if (!canReroll) return;
    if (rerolls >= freeRerolls) gold--;
    rerolls++;
    _roll();
  }

  void sell(int slot) {
    if (board[slot] == null) return;
    final p = board[slot]!;
    gold += p.star == 1 ? 1 : (p.star == 2 ? 3 : 6);
    board[slot] = null;
  }

  void swap(int a, int b) {
    final t = board[a];
    board[a] = board[b];
    board[b] = t;
  }

  List<(int, int, int)> get team => [
        for (var s = 0; s < 6; s++)
          if (board[s] != null) (board[s]!.type, board[s]!.star, s)
      ];

  List<(int, int, int)> get enemy => arEnemy(seed, d, round);

  /// Savaşın sonucunu uygular.
  void resolve(bool win) {
    if (win) {
      wins++;
    } else {
      lives--;
      if (lives <= 0) {
        lost = true;
        return;
      }
    }
    if (round >= rounds) {
      won = true;
      return;
    }
    round++;
    _startRound();
  }

  // ------------------------------------------------------------ yapay zekâ

  double want(int t) {
    final own = board.where((x) => x != null && x.type == t && x.star == 1).length;
    final tr = kArTypes[t].tribe;
    final trc = board.where((x) => x != null && x.t.tribe == tr).length;
    return own * 3 + trc * 1.5 + (kArTypes[t].hp + kArTypes[t].atk * 3) / 6;
  }

  /// Önerilen pazar hamlesi: alınacak teklif, -1 yenile, -2 savaş.
  int botShop() {
    final opts = [for (var i = 0; i < shop.length; i++) if (shop[i] != null) i];
    if (gold >= 3 && opts.isNotEmpty) {
      var best = opts.first;
      for (final i in opts) {
        if (want(shop[i]!) > want(shop[best]!)) best = i;
      }
      if (canBuy(best)) return best;
    }
    if (gold >= 4 && rerolls < 2) return -1;
    return -2;
  }

  /// Yapay zekânın dizilişi: tanklar önde, menzilliler arkada.
  void arrange() {
    final ps = [for (final x in board) if (x != null) x];
    ps.sort((x, y) {
      final rx = x.t.ranged ? 1 : 0, ry = y.t.ranged ? 1 : 0;
      if (rx != ry) return rx.compareTo(ry);
      return y.t.hp.compareTo(x.t.hp);
    });
    for (var s = 0; s < 6; s++) {
      board[s] = s < ps.length ? ps[s] : null;
    }
  }
}

class ArenaKind extends StratejiKind {
  @override
  String get id => 'arena';
  const ArenaKind();

  @override
  SPuzzle? make(int d, SeededRandom r) => ArPuzzle(r.nextUint32(), d);

  @override
  bool check(SPuzzle p) {
    if (p is! ArPuzzle) return false;
    final s = ArSim(p.seed, p.d);
    var guard = 0;
    while (!s.over && guard++ < 400) {
      final m = s.botShop();
      if (m >= 0) {
        s.buy(m);
      } else if (m == -1) {
        s.reroll();
      } else {
        s.arrange();
        s.resolve(ArBattle(s.team, s.enemy).run());
      }
    }
    return s.won;
  }

  @override
  List<Perk> get perks => const [
        Perk(3, Icons.paid, 'pGold', 1),
        Perk(8, Icons.favorite, 'lives', 1),
        Perk(15, Icons.refresh, 'pReroll', 1),
        Perk(25, Icons.grid_view, 'pCap', 1),
        Perk(40, Icons.star, 'pStarter', 0),
      ];

  @override
  List<GameStat> get stats => const [
        GameStat('runs_won', 'Kazanılan turnuva', 'Tournaments won', scale: 10),
        GameStat('flawless', 'Kayıpsız turnuva', 'Flawless tournaments', scale: 10),
        GameStat('merges', 'Birleşen birlik', 'Units merged', scale: 20),
      ];

  @override
  Widget build(StratejiPlay play) => _ArView(play: play);
}

class _ArView extends StatefulWidget {
  final StratejiPlay play;
  const _ArView({required this.play});
  @override
  State<_ArView> createState() => _ArViewState();
}

class _ArViewState extends State<_ArView> with Clock, MetaLoader {
  late ArSim s;
  ArBattle? battle;
  int sel = -1;
  int hints = 0;
  int hinted = -9;
  int lostRounds = 0;
  String note = '';

  StratejiPlay get p => widget.play;
  ArPuzzle get z => p.puzzle as ArPuzzle;

  ArSim _fresh() => ArSim(
        z.seed,
        z.d,
        goldBonus: p.has(usta, 0) ? 1 : 0,
        extraLives: p.has(usta, 1) ? 1 : 0,
        freeRerolls: p.has(usta, 2) ? 1 : 0,
        capBonus: p.has(usta, 3) ? 1 : 0,
        starter: p.has(usta, 4),
      );

  @override
  void initState() {
    super.initState();
    s = _fresh();
    startClock();
    loadMeta(p.gameId, () => s = _fresh());
  }

  void _buy(int i) {
    if (ended || battle != null) return;
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

  void _slot(int i) {
    if (ended || battle != null) return;
    if (sel < 0) {
      if (s.board[i] != null) setState(() => sel = i);
      return;
    }
    if (sel == i) {
      setState(() => sel = -1);
      return;
    }
    started = true;
    s.swap(sel, i);
    p.sfx(Sfx.place);
    setState(() => sel = -1);
  }

  void _fight() {
    if (ended || battle != null) return;
    if (s.count == 0) {
      p.sfx(Sfx.error);
      return;
    }
    started = true;
    final b = ArBattle(s.team, s.enemy);
    setState(() {
      battle = b;
      sel = -1;
      hinted = -9;
    });
    _step();
  }

  void _step() {
    final b = battle;
    if (b == null || !mounted) return;
    for (var i = 0; i < 2; i++) {
      if (b.tick() != null) break;
    }
    setState(() {});
    if (b.result == null) {
      later(40, _step);
      return;
    }
    final win = b.result!;
    p.sfx(win ? Sfx.clear : Sfx.error);
    later(700, () {
      if (!win) lostRounds++;
      s.resolve(win);
      setState(() {
        battle = null;
        note = win ? '✓ ${st(p.lang, 'round')} ${s.round - (s.over ? 0 : 1)}' : '✗ −1 ${st(p.lang, 'lives')}';
      });
      if (s.won) {
        ended = true;
        p.sfx(Sfx.win);
        final stars = (lostRounds == 0 ? 3 : (s.lives >= 2 ? 2 : 1)) - (hints > 0 ? 1 : 0);
        later(400, () => p.win(score: s.wins * 50 + s.lives * 40 + p.d * 30, stars: stars, seconds: seconds, moves: s.round, hints: hints, stats: {'merges': s.merges}));
      } else if (s.lost) {
        ended = true;
        later(500, () => p.lose(score: s.wins * 50, seconds: seconds, moves: s.round, stats: {'merges': s.merges}));
      }
    });
  }

  Future<void> _hint() async {
    if (ended || battle != null) return;
    final ok = await p.ctx.requestHint();
    if (!ok || !mounted) return;
    setState(() {
      hints++;
      hinted = s.botShop();
      if (hinted == -2) s.arrange();
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = p.lang;
    final b = battle;
    final status = note.isNotEmpty && b == null
        ? note
        : '${st(lang, 'round')} ${s.round}/${s.rounds} · ${st(lang, 'units')} ${s.count}/${s.cap}';
    final tribes = [0, 0, 0, 0];
    for (final x in s.board) {
      if (x != null) tribes[x.t.tribe]++;
    }
    return SScreen(
      bar: SBar(lang: lang, left: '♥ ${s.lives} · ◉ ${s.gold}', status: status, onHint: ended ? null : _hint),
      top: PerkStrip(lang: lang, perks: p.perks, usta: usta),
      board: Column(children: [
        Expanded(child: b == null ? _enemyPreview(lang) : _battleView(b)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (var t = 0; t < 4; t++)
            if (tribes[t] > 0)
              Chip(
                visualDensity: VisualDensity.compact,
                avatar: CircleAvatar(backgroundColor: kTribeColors[t], radius: 7),
                label: Text('${st(lang, kTribeKeys[t])} ${tribes[t]}${tribes[t] >= 2 ? ' ✓' : ''}', style: const TextStyle(fontSize: 11)),
              ),
        ]),
        const SizedBox(height: 4),
        if (b == null) _boardGrid(lang),
      ]),
      bottom: b != null
          ? null
          : Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                for (var i = 0; i < s.shop.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: _shopCard(lang, i),
                    ),
                  ),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                IconButton.filledTonal(
                  tooltip: st(lang, 'reroll'),
                  onPressed: s.canReroll && !ended
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
                  tooltip: st(lang, 'sell'),
                  onPressed: sel >= 0 && !ended
                      ? () {
                          started = true;
                          setState(() {
                            s.sell(sel);
                            sel = -1;
                          });
                          p.sfx(Sfx.coin);
                        }
                      : null,
                  icon: const Icon(Icons.sell),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: ended ? null : _fight,
                    icon: Icon(hinted == -2 ? Icons.lightbulb : Icons.sports_kabaddi),
                    label: Text(st(lang, 'battle')),
                  ),
                ),
              ]),
            ]),
    );
  }

  Widget _shopCard(String lang, int i) {
    final t = s.shop[i];
    if (t == null) return const SizedBox(height: 74);
    final ty = kArTypes[t];
    final ok = s.canBuy(i);
    return GestureDetector(
      onTap: () => _buy(i),
      child: Opacity(
        opacity: ok ? 1 : 0.45,
        child: Container(
          height: 74,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF4EBDD),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: hinted == i ? SColors.gold : kTribeColors[ty.tribe], width: hinted == i ? 3 : 1.5),
          ),
          child: Column(children: [
            SizedBox(height: 30, width: 30, child: TapCanvas(w: 20, h: 20, paint: (c) => _creature(c, const Offset(10, 10), t, 1, 7))),
            Text(st(lang, ty.key), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: SColors.ink)),
            Text('♥${ty.hp} ⚔${ty.atk} ◉3', style: const TextStyle(fontSize: 9, color: SColors.ink)),
          ]),
        ),
      ),
    );
  }

  Widget _boardGrid(String lang) => SizedBox(
        height: 150,
        child: Column(children: [
          for (final row in const [
            [3, 4, 5],
            [0, 1, 2],
          ])
            Expanded(
              child: Row(children: [
                for (final i in row)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _slot(i),
                      child: Container(
                        margin: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: i < 3 ? const Color(0xFFE8DCC4) : const Color(0xFFDCE4E8),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: sel == i ? SColors.gold : Colors.black12, width: sel == i ? 3 : 1),
                        ),
                        child: s.board[i] == null
                            ? Center(child: Icon(i < 3 ? Icons.shield_outlined : Icons.my_location, color: Colors.black26, size: 18))
                            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                SizedBox(width: 34, height: 34, child: TapCanvas(w: 20, h: 20, paint: (c) => _creature(c, const Offset(10, 10), s.board[i]!.type, 1, 7))),
                                Text('★' * s.board[i]!.star, style: const TextStyle(color: SColors.gold, fontSize: 12)),
                              ]),
                      ),
                    ),
                  ),
              ]),
            ),
        ]),
      );

  Widget _enemyPreview(String lang) {
    final e = s.enemy;
    return Column(children: [
      Text(st(lang, 'nextFoe'), style: const TextStyle(fontWeight: FontWeight.w700)),
      Expanded(
        child: TapCanvas(
          w: 90,
          h: 50,
          paint: (c) {
            for (final (t, star, slot) in e) {
              final col = slot % 3, row = slot < 3 ? 1 : 0;
              final o = Offset(15 + col * 30.0, 14 + row * 22.0);
              _creature(c, o, t, -1, 8);
              drawLabel(c, '★' * star, o + const Offset(0, 10), 5, SColors.gold);
            }
          },
        ),
      ),
    ]);
  }

  Widget _battleView(ArBattle b) => TapCanvas(
        w: 90,
        h: 100,
        paint: (c) {
          c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 90, 100), const Radius.circular(6)), fill(const Color(0xFFEADBC0)));
          c.drawLine(const Offset(4, 50), const Offset(86, 50), stroke(const Color(0x33000000), 0.6));
          for (final u in [...b.a, ...b.b]) {
            if (!u.alive) continue;
            final col = u.slot % 3;
            final y = u.side == 0 ? (u.slot < 3 ? 62.0 : 84.0) : (u.slot < 3 ? 38.0 : 16.0);
            final o = Offset(15 + col * 30.0, y);
            _creature(c, o, u.type, u.side == 0 ? 1 : -1, 8);
            c.drawRect(Rect.fromLTWH(o.dx - 7, o.dy + 9, 14, 1.4), fill(const Color(0x44000000)));
            c.drawRect(Rect.fromLTWH(o.dx - 7, o.dy + 9, 14 * clampD(u.hp / u.maxHp, 0, 1), 1.4), fill(u.side == 0 ? SColors.good : SColors.bad));
          }
        },
      );

  /// Yaratık çizimi; [dir] 1 yukarı bakar, -1 aşağı.
  void _creature(Canvas c, Offset o, int type, int dir, double r) {
    final t = kArTypes[type];
    final body = fill(t.color);
    switch (type) {
      case 0: // ateşböceği
        c.drawCircle(o, r * 0.75, fill(const Color(0x55F6D68A)));
        c.drawOval(Rect.fromCenter(center: o, width: r * 0.7, height: r * 1.1), body);
        c.drawOval(Rect.fromCenter(center: o + Offset(-r * 0.45, 0), width: r * 0.6, height: r * 0.35), fill(const Color(0xAAFFFFFF)));
        c.drawOval(Rect.fromCenter(center: o + Offset(r * 0.45, 0), width: r * 0.6, height: r * 0.35), fill(const Color(0xAAFFFFFF)));
      case 1: // baykuş
        c.drawOval(Rect.fromCenter(center: o, width: r * 1.3, height: r * 1.6), body);
        c.drawCircle(o + Offset(-r * 0.3, -r * 0.25 * dir), r * 0.28, fill(Colors.white));
        c.drawCircle(o + Offset(r * 0.3, -r * 0.25 * dir), r * 0.28, fill(Colors.white));
        c.drawCircle(o + Offset(-r * 0.3, -r * 0.25 * dir), r * 0.12, fill(SColors.ink));
        c.drawCircle(o + Offset(r * 0.3, -r * 0.25 * dir), r * 0.12, fill(SColors.ink));
      case 2: // diken
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          c.drawLine(o, o + Offset(math.cos(a), math.sin(a)) * r * 0.95, stroke(const Color(0xFF3F6B35), r * 0.12));
        }
        c.drawCircle(o, r * 0.55, body);
      case 3: // geyik
        c.drawOval(Rect.fromCenter(center: o, width: r * 1.1, height: r * 1.3), body);
        c.drawLine(o + Offset(-r * 0.3, -r * 0.5 * dir), o + Offset(-r * 0.7, -r * 1.0 * dir), stroke(const Color(0xFF8C6E54), r * 0.12));
        c.drawLine(o + Offset(r * 0.3, -r * 0.5 * dir), o + Offset(r * 0.7, -r * 1.0 * dir), stroke(const Color(0xFF8C6E54), r * 0.12));
        c.drawCircle(o + Offset(0, r * 0.2 * dir), r * 0.18, fill(const Color(0xFFF4F1EA)));
      case 4: // kaplumbağa
        c.drawOval(Rect.fromCenter(center: o, width: r * 1.7, height: r * 1.3), body);
        c.drawOval(Rect.fromCenter(center: o, width: r * 1.1, height: r * 0.8), stroke(const Color(0x66000000), r * 0.08));
        c.drawCircle(o + Offset(0, -r * 0.8 * dir), r * 0.3, fill(const Color(0xFF9BAA8F)));
      case 5: // kristal kurt
        final path = Path()
          ..moveTo(o.dx, o.dy - r * 0.9 * dir)
          ..lineTo(o.dx + r * 0.8, o.dy)
          ..lineTo(o.dx, o.dy + r * 0.9 * dir)
          ..lineTo(o.dx - r * 0.8, o.dy)
          ..close();
        c.drawPath(path, body);
        c.drawPath(path, stroke(const Color(0xAAFFFFFF), r * 0.08));
      case 6: // meşe
        c.drawRect(Rect.fromCenter(center: o + Offset(0, r * 0.4 * dir), width: r * 0.5, height: r * 0.9), fill(const Color(0xFF6B4A2E)));
        c.drawCircle(o + Offset(0, -r * 0.2 * dir), r * 0.75, fill(const Color(0xFF4F7F52)));
      default: // tilki
        final path = Path()
          ..moveTo(o.dx - r * 0.8, o.dy - r * 0.8 * dir)
          ..lineTo(o.dx - r * 0.3, o.dy - r * 0.3 * dir)
          ..lineTo(o.dx + r * 0.3, o.dy - r * 0.3 * dir)
          ..lineTo(o.dx + r * 0.8, o.dy - r * 0.8 * dir)
          ..lineTo(o.dx + r * 0.6, o.dy + r * 0.3 * dir)
          ..lineTo(o.dx, o.dy + r * 0.8 * dir)
          ..lineTo(o.dx - r * 0.6, o.dy + r * 0.3 * dir)
          ..close();
        c.drawPath(path, body);
    }
  }
}

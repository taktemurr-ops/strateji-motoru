import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import 'texts.dart';

/// Strateji oyunlarından birinin kurulmuş bölümü (tohum + zorluk + harita).
abstract class SPuzzle {
  const SPuzzle();
}

class SLevel {
  final String kind;
  final int d;
  final SPuzzle puzzle;
  const SLevel(this.kind, this.d, this.puzzle);
}

/// Ustalık puanıyla açılan kalıcı kazanım. Etiketi: "+[amount] [metin]".
class Perk {
  /// Açılması için gereken ustalık puanı.
  final int need;
  final IconData icon;

  /// texts.dart anahtarı.
  final String key;
  final int amount;
  const Perk(this.need, this.icon, this.key, this.amount);

  String label(String lang) => amount == 0 ? st(lang, key) : '${amount > 0 ? '+' : ''}$amount ${st(lang, key)}';
}

/// Strateji türü: bölüm üretir, yapay zekâ oyuncuyla kazanılabilirliğini
/// denetler ve ekranı kurar.
abstract class StratejiKind {
  const StratejiKind();
  String get id;

  /// Zorluk 1..10 için deterministik bölüm (kurulamazsa null).
  SPuzzle? make(int d, SeededRandom r);

  /// Yapay zekâ oyuncu bölümü temel donanımla kazanabiliyor mu?
  bool check(SPuzzle p);

  Widget build(StratejiPlay play);

  /// İki kişilik düellosu var mı (bilgisayara karşı, çevrimiçi masa, aynı cihaz).
  bool get duel => false;

  /// Kalıcı kazanımlar (artan eşiklerle).
  List<Perk> get perks;

  List<GameStat> get stats => const [
        GameStat('runs_won', 'Kazanılan sefer', 'Runs won', scale: 10),
        GameStat('flawless', 'Kusursuz sefer', 'Flawless runs', scale: 10),
      ];

  List<MissionTemplate> get missions => const [
        MissionTemplate('win', 'runs_won', [3, 10, 25]),
        MissionTemplate('flawless', 'flawless', [1, 5, 15]),
      ];
}

SPuzzle realizeStrateji(StratejiKind k, int d, int seed) {
  for (var dd = d; dd >= 1; dd--) {
    for (var a = 0; a < 25; a++) {
      SPuzzle? p;
      try {
        p = k.make(dd, SeededRandom(mixSeed([seed, a, dd, 9137])));
      } catch (_) {
        p = null;
      }
      if (p != null && k.check(p)) return p;
    }
  }
  throw StateError('strateji bölümü kurulamadı: ${k.id} $d');
}

class StratejiRules extends GameRules<SLevel> {
  @override
  final String gameId;
  final StratejiKind kind;
  final int levels;
  StratejiRules({required this.gameId, required this.kind, this.levels = 100000});

  @override
  int get levelCount => levels;

  @override
  List<String> get optionalMechanics => const [];

  /// Düellolu türlerde ana sayfa "Bilgisayara karşı" ve "Çevrimiçi masa" sunar.
  @override
  int get localPlayers => kind.duel ? 2 : 0;

  @override
  List<GameModeId> get modes => const [GameModeId.campaign, GameModeId.daily, GameModeId.weekly, GameModeId.challenge];

  @override
  List<GameStat> get gameStats => kind.stats;

  @override
  List<MissionTemplate> get missionTemplates => kind.missions;

  @override
  SLevel generate(LevelSpec spec) {
    final d = clampI(spec.difficulty, 1, 10);
    return SLevel(kind.id, d, realizeStrateji(kind, d, spec.seed));
  }

  @override
  Validation validate(SLevel puzzle, LevelSpec spec) =>
      puzzle.kind == kind.id && kind.check(puzzle.puzzle) ? const Validation.ok() : const Validation.fail('invalid');
}

/// Ustalık puanları: her kazanılan seferde artar, cihazda saklanır.
/// Depolama yoksa (test, eklentisiz ortam) bellekte tutulur.
class Meta {
  static final Map<String, int> _mem = {};

  static String _key(String gameId) => 'strateji.usta.$gameId';

  static Future<int> load(String gameId) async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getInt(_key(gameId)) ?? (_mem[gameId] ?? 0);
    } catch (_) {
      return _mem[gameId] ?? 0;
    }
  }

  static Future<int> add(String gameId, int points) async {
    final v = await load(gameId) + points;
    _mem[gameId] = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_key(gameId), v);
    } catch (_) {}
    return v;
  }

  /// Sefer sonunda kazanılan ustalık puanı.
  static int pointsFor(int d, int stars) => 1 + d ~/ 3 + (stars >= 3 ? 1 : 0);
}

class StratejiPlay {
  final PlayContext ctx;
  final String gameId;
  final SPuzzle puzzle;
  final int d;
  final int seed;
  final List<Perk> perks;
  const StratejiPlay({required this.ctx, required this.gameId, required this.puzzle, required this.d, required this.seed, required this.perks});

  String get lang => ctx.lang;

  void sfx(Sfx s) => ctx.sfx(s);

  /// Açık kazanımların sayısı (ustalık puanına göre).
  int unlockedCount(int usta) => perks.where((p) => p.need <= usta).length;

  /// [usta] puanla [i]. kazanım açık mı?
  bool has(int usta, int i) => i < perks.length && perks[i].need <= usta;

  void win({int score = 0, int stars = 3, int seconds = 0, int moves = 0, int hints = 0, Map<String, int> stats = const {}}) {
    final s = clampI(stars, 1, 3);
    unawaited(Meta.add(gameId, Meta.pointsFor(d, s)));
    ctx.finish(RoundResult(
      won: true,
      score: score < 0 ? 0 : score,
      stars: s,
      seconds: seconds,
      moves: moves,
      hintsUsed: hints,
      gameStats: {'runs_won': 1, if (s == 3 && hints == 0) 'flawless': 1, ...stats},
    ));
  }

  void lose({int score = 0, int seconds = 0, int moves = 0, Map<String, int> stats = const {}}) {
    ctx.finish(RoundResult(won: false, score: score < 0 ? 0 : score, seconds: seconds, moves: moves, gameStats: stats));
  }
}

/// Strateji oyunlarının ortak sahnesi.
class StratejiStage extends StatelessWidget {
  final PlayContext ctx;
  final StratejiRules rules;
  const StratejiStage({super.key, required this.ctx, required this.rules});

  @override
  Widget build(BuildContext context) {
    final lv = ctx.generated.puzzle as SLevel;
    return rules.kind.build(StratejiPlay(
      ctx: ctx,
      gameId: rules.gameId,
      puzzle: lv.puzzle,
      d: lv.d,
      seed: ctx.spec.seed,
      perks: rules.kind.perks,
    ));
  }
}

StratejiRules stratejiRules(String gameId, StratejiKind kind) => StratejiRules(gameId: gameId, kind: kind);

/// Ustalık puanını yükleyen ve yalnızca oyuncu ilk hamlesini yapmadan önce
/// kazanımları uygulayan ortak durum katmanı.
mixin MetaLoader<T extends StatefulWidget> on State<T> {
  int usta = 0;
  bool metaReady = false;

  /// Oyuncu ilk hamlesini yaptı mı? Yaptıysa kazanımlar bu seferi değiştirmez.
  bool started = false;

  void loadMeta(String gameId, void Function() apply) {
    Meta.load(gameId).then((v) {
      if (!mounted) return;
      setState(() {
        usta = v;
        metaReady = true;
        if (!started) apply();
      });
    });
  }
}

/// Kazanımlar şeridi: ustalık puanı, açık ve kilitli kazanımlar.
class PerkStrip extends StatelessWidget {
  final String lang;
  final List<Perk> perks;
  final int usta;
  const PerkStrip({super.key, required this.lang, required this.perks, required this.usta});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 30,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: SColors.gold.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.military_tech, size: 16, color: SColors.ink),
            const SizedBox(width: 4),
            Text('${st(lang, 'mastery')} $usta', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SColors.ink)),
          ]),
        ),
        for (final p in perks)
          Container(
            margin: const EdgeInsetsDirectional.only(start: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.need <= usta ? scheme.surface.withValues(alpha: 0.95) : scheme.surface.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.need <= usta ? SColors.good : Colors.black12),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(p.need <= usta ? p.icon : Icons.lock_outline, size: 14, color: p.need <= usta ? SColors.good : Colors.black38),
              const SizedBox(width: 4),
              Text(p.need <= usta ? p.label(lang) : '${p.need}', style: TextStyle(fontSize: 11, color: p.need <= usta ? null : Colors.black45)),
            ]),
          ),
      ]),
    );
  }
}

/// Simge + sayı (kart etkileri, kaynaklar).
class IconNum extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final double size;
  const IconNum(this.icon, this.text, {super.key, this.color = SColors.ink, this.size = 14});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: size + 2, color: color),
        const SizedBox(width: 2),
        Text(text, style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: color)),
      ]);
}

/// Ekranın ortasında kısa bir bilgi kartı (ödül seçimi, raunt sonucu).
class SPanel extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const SPanel({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 460),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(blurRadius: 16, color: Colors.black26)],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          ...children,
        ]),
      ),
    );
  }
}

/// Yıldız: kalan can oranına göre.
int starsByHealth(int hp, int maxHp) {
  if (maxHp <= 0) return 1;
  final r = hp / maxHp;
  return r >= 0.6 ? 3 : (r >= 0.3 ? 2 : 1);
}

// ---------------------------------------------------------------- ortak yardımcılar

class SColors {
  static const paper = Color(0xFFF4F1EA);
  static const ink = Color(0xFF22303F);
  static const good = Color(0xFF4F9A6E);
  static const bad = Color(0xFFC8553D);
  static const accent = Color(0xFF3E6FB0);
  static const gold = Color(0xFFD9A441);
  static const soft = Color(0xFFE6E0D4);
  static const line = Color(0xFFB9AE9B);

  /// Sıcak, doğal tonlar.
  static const List<Color> warm = [
    Color(0xFFB23A48),
    Color(0xFF2E5E8C),
    Color(0xFFD9A441),
    Color(0xFF4F7F52),
    Color(0xFF7A4E7E),
    Color(0xFFE07A5F),
    Color(0xFF3A8D8C),
    Color(0xFF5B4636),
  ];
}

/// Saat ve iptal edilebilen gecikmeler.
mixin Clock<T extends StatefulWidget> on State<T> {
  int seconds = 0;
  bool ended = false;
  Timer? _t;
  final List<Timer> _later = [];

  void startClock() {
    _t?.cancel();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!ended && mounted) setState(() => seconds++);
    });
  }

  void later(int ms, VoidCallback f) {
    _later.add(Timer(Duration(milliseconds: ms), () {
      if (mounted) f();
    }));
  }

  @override
  void dispose() {
    _t?.cancel();
    for (final t in _later) {
      t.cancel();
    }
    super.dispose();
  }

  String clock([int? s]) {
    final v = s ?? seconds;
    return '${v ~/ 60}:${(v % 60).toString().padLeft(2, '0')}';
  }
}

int clampI(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
double clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// Üst çubuk: solda bilgi, ortada durum; ipucu, geri al ve baştan düğmeleri.
class SBar extends StatelessWidget {
  final String lang;
  final String left;
  final String status;
  final VoidCallback? onHint;
  final VoidCallback? onUndo;
  final VoidCallback? onReset;
  final List<Widget> extra;
  const SBar({super.key, required this.lang, this.left = '', this.status = '', this.onHint, this.onUndo, this.onReset, this.extra = const []});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      height: 48,
      decoration: BoxDecoration(color: scheme.surface.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        if (left.isNotEmpty) Text(left, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(status, maxLines: 1))),
        ...extra,
        if (onUndo != null) IconButton(tooltip: st(lang, 'undo'), onPressed: onUndo, icon: const Icon(Icons.undo)),
        if (onReset != null) IconButton(tooltip: st(lang, 'reset'), onPressed: onReset, icon: const Icon(Icons.restart_alt)),
        if (onHint != null) IconButton(tooltip: st(lang, 'hint'), onPressed: onHint, icon: const Icon(Icons.lightbulb_outline)),
      ]),
    );
  }
}

/// Mantıksal birimlerle çizilen, dokunuşları aynı birimlere çeviren tuval.
/// [w] × [h] birimlik alan kullanılabilir yere oranı korunarak sığdırılır.
class TapCanvas extends StatelessWidget {
  final double w;
  final double h;
  final void Function(Canvas c) paint;
  final void Function(Offset p)? onTap;
  final void Function(Offset p)? onLongPress;
  final void Function(Offset p)? onPanStart;
  final void Function(Offset p)? onPanUpdate;
  final VoidCallback? onPanEnd;
  final String? semantics;
  const TapCanvas({
    super.key,
    required this.w,
    required this.h,
    required this.paint,
    this.onTap,
    this.onLongPress,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.semantics,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final mw = box.maxWidth.isFinite ? box.maxWidth : 360.0;
      final mh = box.maxHeight.isFinite ? box.maxHeight : 360.0;
      final k = math.min(mw / w, mh / h);
      final size = Size(w * k, h * k);
      Offset lp(Offset o) => o / k;
      final ps = onPanStart, pu = onPanUpdate, pe = onPanEnd, t = onTap, lpr = onLongPress;
      return Center(
        child: Semantics(
          label: semantics,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: t == null ? null : (e) => t(lp(e.localPosition)),
            onLongPressStart: lpr == null ? null : (e) => lpr(lp(e.localPosition)),
            onPanStart: ps == null ? null : (e) => ps(lp(e.localPosition)),
            onPanUpdate: pu == null ? null : (e) => pu(lp(e.localPosition)),
            onPanEnd: pe == null ? null : (_) => pe(),
            child: CustomPaint(size: size, painter: _FnPainter(paint, k)),
          ),
        ),
      );
    });
  }
}

class _FnPainter extends CustomPainter {
  final void Function(Canvas c) fn;
  final double k;
  _FnPainter(this.fn, this.k);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(k);
    fn(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FnPainter old) => true;
}

Paint fill(Color c) => Paint()
  ..color = c
  ..isAntiAlias = true;

Paint stroke(Color c, double w) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..isAntiAlias = true;

/// Ortalanmış kısa yazı (mantıksal birimlerle).
void drawLabel(Canvas c, String s, Offset center, double size, Color color, {FontWeight weight = FontWeight.w700}) {
  if (s.isEmpty) return;
  final tp = TextPainter(
    text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color, fontWeight: weight, height: 1.0)),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout();
  tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
}

/// Hızlı ızgara yardımcıları.
const List<List<int>> kDirs4 = [
  [0, -1],
  [1, 0],
  [0, 1],
  [-1, 0],
];

const List<List<int>> kDirs8 = [
  [-1, -1],
  [0, -1],
  [1, -1],
  [1, 0],
  [1, 1],
  [0, 1],
  [-1, 1],
  [-1, 0],
];

/// Tek sütun düzeni: çubuk, tahta, isteğe bağlı alt düğmeler.
class SScreen extends StatelessWidget {
  final Widget bar;
  final Widget board;
  final Widget? top;
  final Widget? bottom;
  const SScreen({super.key, required this.bar, required this.board, this.top, this.bottom});

  @override
  Widget build(BuildContext context) {
    final t = top, b = bottom;
    return Column(children: [
      bar,
      if (t != null) Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 0), child: t),
      Expanded(child: Padding(padding: const EdgeInsets.all(10), child: board)),
      if (b != null) Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 10), child: b),
    ]);
  }
}

/// Altta kullanılan yuvarlak köşeli seçim düğmesi.
class SChip extends StatelessWidget {
  final Widget child;
  final bool selected;
  final VoidCallback? onTap;
  final Color? color;
  final String? tooltip;
  const SChip({super.key, required this.child, this.selected = false, this.onTap, this.color, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.surface;
    final w = Material(
      color: selected ? Color.lerp(c, scheme.primary, 0.35) : c,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? scheme.primary : Colors.black12, width: selected ? 2.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: child),
      ),
    );
    final tt = tooltip;
    return tt == null ? w : Tooltip(message: tt, child: w);
  }
}

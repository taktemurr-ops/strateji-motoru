import 'dart:async';

import 'package:flutter/material.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/services/audio.dart';

import 'core.dart';
import 'texts.dart';

/// İki kişilik sıra tabanlı düello (Altıgen Savaş, Sıra Tabanlı Taktik).
/// Durum yalnızca hamle günlüğünden türer: aynı tohum + aynı hamleler →
/// iki cihazda aynı durum.
abstract class DuelGame {
  /// Sıradaki koltuk (0 mavi, 1 kırmızı).
  int get turnSeat;

  /// Her yeni sırada değişen anahtar (tur sayacı bunu izler).
  int get turnKey;

  bool get over;

  /// Kazanan koltuk; -1 berabere; oyun sürüyorsa -2.
  int get winner;

  /// Uygulanan hamle sayısı.
  int get applied;

  /// [seat] koltuğunun hamlesi. Kurala aykırıysa durum değişmez, false.
  bool apply(int seat, String mv);

  /// Sıradaki koltuk için bilgisayarın hamlesi (her zaman geçerli).
  String botMove();

  /// Süre dolunca oynanan hamle (turu bitir / bekle).
  String timeoutMove();

  /// Durumun özeti: iki cihazda karşılaştırmak için.
  String get hash;
}

/// Maç bağlantısı üzerinden sıralı hamle günlüğü. Her hamle "<sıra>|<hamle>"
/// biçiminde gider; eksik sıra gelene kadar sonrakiler bekletilir, aynı sıra
/// iki kez gelirse ikincisi yok sayılır. Geri dönüşte geçmiş baştan uygulanır.
class StratNet {
  final MatchLink link;
  final int me;
  final int opp;
  final void Function(int seat, String mv) onMove;

  /// Beklenen bir sonraki hamle sırası.
  int next = 0;
  final Map<int, (int, String)> _buf = {};
  StreamSubscription<(int, String)>? _sub;

  StratNet(this.link, this.onMove)
      : me = link.mySeat,
        opp = link.mySeat == 0 ? 1 : 0;

  static (int, String)? parse(String raw) {
    final i = raw.indexOf('|');
    if (i <= 0) return null;
    final n = int.tryParse(raw.substring(0, i));
    if (n == null || n < 0) return null;
    return (n, raw.substring(i + 1));
  }

  void start() {
    for (final (s, raw) in link.history) {
      _take(s, raw);
    }
    _sub = link.moves.listen((e) => _take(e.$1, e.$2));
  }

  void _take(int seat, String raw) {
    final p = parse(raw);
    if (p == null || p.$1 < next) return;
    _buf.putIfAbsent(p.$1, () => (seat, p.$2));
    while (_buf.containsKey(next)) {
      final e = _buf.remove(next)!;
      next++;
      onMove(e.$1, e.$2);
    }
  }

  /// Rakip bağlantıyı kopardı mı (artık bilgisayar oynar).
  bool get oppGone => link.dropped.contains(opp);

  /// Yerelde uygulanmış hamleyi yayınla ([seat] rakipse onun adına).
  void send(int seat, String mv) {
    final raw = '$next|$mv';
    next++;
    unawaited(link.send(raw, asSeat: seat == me ? null : seat).catchError((Object _) {}));
  }

  void finish(int winner) => unawaited(link.finish(winner, iWon: winner == me).catchError((Object _) {}));

  void dispose() {
    _sub?.cancel();
    _buf.clear();
  }
}

enum DuelMode { online, bot, hotseat }

/// Düello ekranlarının ortak katmanı: kip, ağ, tur süresi, bilgisayar
/// hamleleri ve sonuç.
mixin DuelHost<T extends StatefulWidget> on State<T> {
  late DuelGame game;
  DuelMode mode = DuelMode.hotseat;
  StratNet? net;

  /// Ekranın alt tarafında görünen koltuk.
  int viewer = 0;

  /// Sıradaki oyuncunun kalan süresi (saniye).
  int turnLeft = 0;
  int _key = -1;
  Timer? _tick;
  Timer? _botT;
  bool _ready = false;
  bool reported = false;

  /// Maçı başlatan bağlam (aynı cihazda iki kişilik deneme maçında null).
  PlayContext? dctx;

  int get turnSeconds;

  /// Bilgisayarın hamle arası bekleme süresi.
  int get botDelayMs => 420;

  /// Ekran seçimleri temizlensin (her durum değişiminde).
  void onDuelChanged() {}

  /// Maç bitti (bir kez).
  void onDuelOver();

  void initDuel(DuelGame g, PlayContext? ctx) {
    game = g;
    dctx = ctx;
    final m = ctx?.match;
    if (ctx != null && m != null) {
      viewer = m.mySeat;
      mode = ctx.role(viewer == 0 ? 1 : 0) == SeatRole.remote ? DuelMode.online : DuelMode.bot;
      final n = StratNet(m, _remote);
      net = n;
      n.start();
    } else {
      mode = DuelMode.hotseat;
      viewer = 0;
    }
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _second());
    _ready = true;
    _after(quiet: true);
  }

  bool isHuman(int seat) => mode == DuelMode.hotseat || seat == viewer;

  bool isBot(int seat) => !isHuman(seat) && (mode == DuelMode.bot || (net?.oppGone ?? false));

  bool get myTurn => !game.over && isHuman(game.turnSeat);

  bool get oppGone => mode == DuelMode.online && (net?.oppGone ?? false);

  /// Ekranın döndürülmesi: çevrimiçi maçta ikinci koltuk kendi ordusunu altta görür.
  bool get flip => mode != DuelMode.hotseat && viewer == 1;

  void _remote(int seat, String mv) {
    // Kendi hamlelerimiz yalnızca geri dönüşte (geçmişten) gelir.
    if (game.apply(seat, mv) && _ready && seat != viewer) dctx?.sfx(Sfx.place);
    if (_ready) _after();
  }

  /// Yerel oyuncunun hamlesi; kurala uygunsa uygulanır ve yayınlanır.
  bool play(String mv) {
    if (game.over || !isHuman(game.turnSeat)) return false;
    final seat = game.turnSeat;
    if (!game.apply(seat, mv)) return false;
    net?.send(seat, mv);
    _after();
    return true;
  }

  void _forced(int seat, String mv) {
    if (game.apply(seat, mv)) {
      net?.send(seat, mv);
    } else {
      final t = game.timeoutMove();
      if (game.apply(seat, t)) net?.send(seat, t);
    }
  }

  void _after({bool quiet = false}) {
    if (!mounted) return;
    if (game.turnKey != _key) {
      _key = game.turnKey;
      turnLeft = turnSeconds;
    }
    _botT?.cancel();
    if (game.over) {
      _finish();
    } else if (isBot(game.turnSeat)) {
      _botT = Timer(Duration(milliseconds: botDelayMs), () {
        if (!mounted || game.over || !isBot(game.turnSeat)) return;
        _forced(game.turnSeat, game.botMove());
        _after();
      });
    }
    onDuelChanged();
    if (!quiet) setState(() {});
  }

  void _second() {
    if (!mounted || game.over) return;
    if (turnLeft > 0) turnLeft--;
    if (turnLeft == 0 && isHuman(game.turnSeat)) {
      _forced(game.turnSeat, game.timeoutMove());
      _after();
      return;
    }
    if (isBot(game.turnSeat) && !(_botT?.isActive ?? false)) {
      _after();
      return;
    }
    setState(() {});
  }

  void _finish() {
    if (reported) return;
    reported = true;
    _tick?.cancel();
    net?.finish(game.winner);
    onDuelOver();
  }

  /// Yerel oyuncu kazandı mı (aynı cihazda: biri kazandıysa).
  bool get localWon => mode == DuelMode.hotseat ? game.winner >= 0 : game.winner == viewer;

  String resultText(String lang) {
    final w = game.winner;
    if (w == -1) return st(lang, 'draw');
    if (mode == DuelMode.hotseat) return st(lang, w == 0 ? 'blueWins' : 'redWins');
    return st(lang, w == viewer ? 'youWon' : 'youLost');
  }

  /// Üst çubuktaki durum: kimin sırası, süre.
  String turnText(String lang) {
    if (game.over) return resultText(lang);
    final s = game.turnSeat;
    final who = mode == DuelMode.hotseat ? st(lang, s == 0 ? 'blueTurn' : 'redTurn') : (isHuman(s) ? st(lang, 'yourTurn') : st(lang, 'enemyTurn'));
    final gone = oppGone ? ' · ${st(lang, 'oppLeft')}' : '';
    return '$who · ${turnLeft ~/ 60}:${(turnLeft % 60).toString().padLeft(2, '0')}$gone';
  }

  Color seatColor(int seat) => seat == 0 ? SColors.accent : SColors.bad;

  @override
  void dispose() {
    _tick?.cancel();
    _botT?.cancel();
    net?.dispose();
    super.dispose();
  }
}

/// Maç sonu kartı.
class DuelResultPanel extends StatelessWidget {
  final String title;
  final Color color;
  final String button;
  final VoidCallback onDone;
  const DuelResultPanel({super.key, required this.title, required this.color, required this.button, required this.onDone});

  @override
  Widget build(BuildContext context) => SPanel(title: title, children: [
        Icon(Icons.flag, size: 40, color: color),
        const SizedBox(height: 10),
        FilledButton(onPressed: onDone, child: Text(button)),
      ]);
}

/// Aynı cihazda iki kişilik deneme maçı (sefer ekranından açılır).
void openHotseat(BuildContext context, Widget Function() view) {
  Navigator.push(context, MaterialPageRoute<void>(builder: (_) => Scaffold(body: SafeArea(child: view()))));
}

import 'core.dart';
import 'games/altigen.dart';
import 'games/arena.dart';
import 'games/deste.dart';
import 'games/hayatta.dart';
import 'games/taktik.dart';
import 'games/vadi.dart';
import 'games/zindan.dart';

/// Strateji ve Roguelike türleri.
const Map<String, StratejiKind> kStratejiKinds = {
  'zindan': ZindanKind(),
  'deste': DesteKind(),
  'altigen': AltigenKind(),
  'taktik': TaktikKind(),
  'hayatta': HayattaKind(),
  'arena': ArenaKind(),
  'vadi': VadiKind(),
};

StratejiRules stratejiRulesFor(String gameId, String kind) => stratejiRules(gameId, kStratejiKinds[kind]!);

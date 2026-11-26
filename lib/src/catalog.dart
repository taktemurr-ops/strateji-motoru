import 'core.dart';
import 'games/altigen.dart';
import 'games/arena.dart';
import 'games/deste.dart';
import 'games/harita.dart';
import 'games/hayatta.dart';
import 'games/heybe.dart';
import 'games/kale.dart';
import 'games/krallik.dart';
import 'games/savasci.dart';
import 'games/sekme.dart';
import 'games/suru.dart';
import 'games/taktik.dart';
import 'games/vadi.dart';
import 'games/zar.dart';
import 'games/zindan.dart';
import 'games/zindanusta.dart';

/// Strateji ve Roguelike türleri.
const Map<String, StratejiKind> kStratejiKinds = {
  'zindan': ZindanKind(),
  'deste': DesteKind(),
  'altigen': AltigenKind(),
  'taktik': TaktikKind(),
  'hayatta': HayattaKind(),
  'arena': ArenaKind(),
  'vadi': VadiKind(),
  'zar': ZarKind(),
  'krallik': KrallikKind(),
  'harita': HaritaKind(),
  'savasci': SavasciKind(),
  'zindanusta': ZindanUstaKind(),
  'suru': SuruKind(),
  'heybe': HeybeKind(),
  'sekme': SekmeKind(),
  'kale': KaleKind(),
};

StratejiRules stratejiRulesFor(String gameId, String kind) => stratejiRules(gameId, kStratejiKinds[kind]!);

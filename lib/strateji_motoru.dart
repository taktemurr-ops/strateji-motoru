/// Strateji ve Roguelike ailesinin ortak motoru: zindan keşfi, deste seferi,
/// altıgen savaş, sıra tabanlı taktik, ıssız kıyıda hayatta kalma, kum saati
/// arenası, vadi kurucu, zar macerası, dört mevsim krallık ve harita defteri.
/// Bölüm üretimi, yapay zekâ doğrulaması, ustalık kazanımları ve oyun ekranları.
library;

export 'src/catalog.dart';
export 'src/core.dart' show StratejiStage, StratejiRules, StratejiKind, SLevel, SPuzzle, Perk, Meta, stratejiRules;
export 'src/games/harita.dart' show hOrients, hGoal, kHN;
export 'src/games/krallik_cards.dart' show kKCards, KCard;
export 'src/games/zar.dart' show ZPuzzle, zBot;
export 'src/texts.dart';

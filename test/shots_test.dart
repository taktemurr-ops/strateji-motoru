// Oyun testi görüntüleri: her oyun telefonda (393×852) 1. bölüm açılış,
// dokunuşlarla 20 sn oynanmış hâl, 10. bölüm açılış, Arapça (RTL) ve Japonca;
// tablette (1280×800) 1. bölüm. Görüntü sayfası build/shots/<oyun>_sayfa.png.
// Yalnız "shots" işinde çalışır: flutter test --tags shots --run-skipped
@Tags(['shots'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strateji_motoru/strateji_motoru.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/studio_look.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';

Future<void> _fonts() async {
  Future<void> load(String family, Iterable<File> files) async {
    final l = FontLoader(family);
    var n = 0;
    for (final f in files) {
      if (!f.existsSync()) continue;
      l.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
      n++;
    }
    if (n > 0) await l.load();
  }

  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
  final mf = Directory('${artifacts.path}/material_fonts');
  if (mf.existsSync()) {
    final all = mf.listSync().whereType<File>().toList();
    await load('Roboto', all.where((f) => f.path.contains('Roboto-') && f.path.endsWith('.ttf')));
    await load('MaterialIcons', all.where((f) => f.path.contains('MaterialIcons')));
  }
  const noto = '/usr/share/fonts/truetype/noto';
  await load('Noto Naskh Arabic', [File('$noto/NotoNaskhArabic-Regular.ttf'), File('$noto/NotoNaskhArabic-Bold.ttf')]);
  await load('Noto Sans CJK JP', [File('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc')]);
  await load('Noto Color Emoji', [File('/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf')]);
}

final _key = GlobalKey();

PlayContext _ctx(GeneratedLevel gl, String lang) => PlayContext(
      spec: gl.spec,
      generated: gl,
      resume: const {},
      pieceColors: const [Color(0xFF3E6FB0), Color(0xFFC8553D), Color(0xFF4F9A6E)],
      background: const [Color(0xFF203040), Color(0xFF304050)],
      colorBlind: false,
      reducedMotion: false,
      leftHanded: false,
      lang: lang,
      t: (k, [p = const {}]) => k,
      finish: (_) {},
      saveResume: (_) {},
      requestHint: () async => true,
      requestBooster: () async => true,
      requestContinue: () async => false,
      sfx: (_) {},
    );

Widget _host(Widget child, String lang) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: lang == 'ar' ? 'Noto Naskh Arabic' : (lang == 'ja' ? 'Noto Sans CJK JP' : 'Roboto'),
        fontFamilyFallback: const ['Noto Color Emoji'],
        extensions: [StudioLook.fromSeed(const Color(0xFF2E7D32))],
      ),
      home: RepaintBoundary(
        key: _key,
        child: Scaffold(
          backgroundColor: const Color(0xFF1A2348),
          body: SafeArea(
            child: Directionality(textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr, child: child),
          ),
        ),
      ),
    );

Future<ui.Image> _grab(WidgetTester t) async {
  await t.pump(const Duration(milliseconds: 50));
  late ui.Image img;
  await t.runAsync(() async {
    final b = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    img = await b.toImage(pixelRatio: 1);
  });
  return img;
}

Future<void> _save(WidgetTester t, List<ui.Image> imgs, String name) async {
  await t.runAsync(() async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    var x = 0.0, h = 0.0;
    for (final i in imgs) {
      c.drawImage(i, Offset(x, 0), Paint());
      x += i.width + 8;
      if (i.height > h) h = i.height.toDouble();
    }
    final img = await rec.endRecording().toImage(x.round(), h.round());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/shots').createSync(recursive: true);
    File('build/shots/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<void> _open(WidgetTester t, Widget w, String lang, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(_host(w, lang));
  await t.pump(const Duration(seconds: 1));
}

/// Kullanıcı gibi: ekranın her yerine sırayla dokun, arada zaman geçsin.
Future<void> _play(WidgetTester t, Size size, int seconds) async {
  var k = 0;
  for (var s = 0; s < seconds; s++) {
    for (var j = 0; j < 4; j++) {
      final x = 20 + ((k * 97) % (size.width - 40));
      final y = 70 + ((k * 151) % (size.height - 100));
      k++;
      await t.tapAt(Offset(x, y));
      await t.pump(const Duration(milliseconds: 250));
      // Açılan pencereyi kapat (geri).
      final nav = t.state<NavigatorState>(find.byType(Navigator).first);
      if (nav.canPop()) {
        nav.pop();
        await t.pump(const Duration(milliseconds: 100));
      }
    }
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _fonts();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const games = {'zindan': 'oyun-zindan-kesfi', 'deste': 'oyun-deste-kurma', 'hayatta': 'oyun-hayatta-kalma', 'zar': 'oyun-zar-macerasi', 'altigen': 'oyun-altigen-savas-oyunu', 'taktik': 'oyun-sira-tabanli-taktik', 'savasci': 'oyun-otomatik-savasci', 'zindanusta': 'oyun-zindan-ustasi', 'arena': 'oyun-kum-saati-arenasi', 'vadi': 'oyun-vadi-kurucu', 'krallik': 'oyun-dort-mevsim-krallik', 'harita': 'oyun-harita-defteri', 'suru': 'oyun-suru-avcisi', 'sekme': 'oyun-top-sekme-zindani', 'heybe': 'oyun-heybe-savaslari', 'kale': 'oyun-kale-kusatmasi'};
  final only = Platform.environment['SHOTS_ONLY'] ?? '';
  const tel = Size(393, 852), tab = Size(1280, 800);

  for (final g in games.entries) {
    if (only.isNotEmpty && !only.split(',').contains(g.value)) continue;
    testWidgets(g.value, (t) async {
      addTearDown(t.view.reset);
      final rules = stratejiRulesFor(g.value, g.key);
      final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: rules.optionalMechanics);
      final l1 = rules.build(planner.spec(1)), l10 = rules.build(planner.spec(10));
      final shots = <ui.Image>[];
      await _open(t, StratejiStage(ctx: _ctx(l1, 'tr'), rules: rules), 'tr', tel);
      shots.add(await _grab(t));
      await _play(t, tel, 20);
      shots.add(await _grab(t));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
      await _open(t, StratejiStage(ctx: _ctx(l10, 'tr'), rules: rules), 'tr', tel);
      await _play(t, tel, 6);
      shots.add(await _grab(t));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
      for (final lang in const ['ar', 'ja']) {
        await _open(t, StratejiStage(ctx: _ctx(l1, lang), rules: rules), lang, tel);
        shots.add(await _grab(t));
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 1));
      }
      await _save(t, shots, '${g.value}_sayfa');
      await _open(t, StratejiStage(ctx: _ctx(l1, 'tr'), rules: rules), 'tr', tab);
      await _play(t, tab, 4);
      await _save(t, [await _grab(t)], '${g.value}_tablet');
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 3));
      // ignore: avoid_print
      print('SONUC|${g.value}|tamam|${t.takeException()}');
    });
  }
}

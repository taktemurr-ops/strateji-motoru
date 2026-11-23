# strateji-motoru

Strateji ve Roguelike ailesinin ortak motoru. On oyun türü:

| Tür | Oyun | Özet |
|---|---|---|
| `zindan` | Zindan Keşfi | Sisli zindanda sıra tabanlı kat kat iniş; yaratıklar her adımda hareket eder. |
| `deste` | Deste Seferi | Deste kurarak karşılaşmalar; rakip niyetleri önceden görünür, her zaferde kart ödülü. |
| `altigen` | Altıgen Savaş | Altıgen haritada ordu savaşı; arazi, köy iyileşmesi, sancak ele geçirme. |
| `taktik` | Sıra Tabanlı Taktik | Hız sırasına göre oynayan bölük; yetenekler ve bekleme süreleri. |
| `hayatta` | Issız Kıyı | Günlük olaylar, iki iş, gece kayıpları ve hava tahmini ile hayatta kalma. |
| `arena` | Kum Saati Arenası | Pazar, iki sıralı saha, birleşerek yıldız kazanan birlikler, soy bonusları. |
| `vadi` | Vadi Kurucu | Komşuluğa göre puanlanan yapılarla vadi kurma; hedef ve en iyi skor. |
| `zar` | Zar Macerası | Zar torbası kurma: at, tut, bir kez yeniden at, mücevheri eyleme ata; ödülle yüz güçlendir ya da yeni zar al. |
| `krallik` | Dört Mevsim Krallık | Sağa/sola kaydırılan 240 karar kartı (TR/EN); halk, hazine, ordu ve doğayı yıllar boyunca dengede tut. |
| `harita` | Harita Defteri | 11×11 haritaya keşif biçimleri çiz; her mevsim iki hedef kartı puanlanır. |

- Her bölüm tohumdan deterministik üretilir ve **yapay zekâ oyuncu** temel donanımla kazanabiliyorsa kabul edilir (`StratejiKind.check`).
- 100.000 bölüm; kampanya, günlük, haftalık ve meydan okuma modları.
- **Ustalık:** her kazanılan seferde `1 + zorluk/3 (+1 üç yıldız)` puan; her oyunda 5 kalıcı kazanım açılır (cihazda saklanır).
- İpucu: yapay zekânın önerdiği hamleyi gösterir.
- Bütün arayüz metinleri ve içerik adları 33 dilde (`lib/src/texts.dart`). Dört Mevsim Krallık kart metinleri TR/EN; diğer dillerde İngilizce gösterilir.

Bağımlılık: [studio-core](https://github.com/taktemurr-ops/studio-core).

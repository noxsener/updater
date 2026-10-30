# Codenfast Updater

Tek uygulama; sunucudaki `catalog.json` içindeki ürünleri listeler.
- Windows / Linux / macOS: **İndir → Güncelle → Aç** (dosya senkronizasyonu)
- Android / iOS: ürünün Play Store / App Store sayfasını açar

Katalog adresi derleme zamanında verilir:
`flutter run --dart-define=CATALOG_URL=http://localhost:8000/catalog.json`
(varsayılan: `https://media.codenfast.com/catalog.json`). Sunucudan gelen tüm URL'ler `https` olmak zorunda; yalnızca `localhost`, `127.0.0.1`, `10.0.2.2` için `http` kabul edilir.

## Ekran (masaüstü)

- **Keşfet / Kurulu / Güncellemeler** sekmeleri; Güncellemeler üzerinde sayı rozeti ve **Tümünü güncelle**.
- Açılışta kurulu uygulamaların güncellemeleri toplu denetlenir.
- Arama kutusu (ad, açıklama, kategori) ve katalogdaki `category` alanına göre kategori filtresi.
- Karta tıklayınca detay sayfası: açıklama, kurulu/son sürüm, indirme boyutu, varyant seçimi, **Kaldır**.
- Kurulumda işletim sisteminin uygulama menüsüne kısayol eklenir, kaldırınca silinir:
  Linux `~/.local/share/applications/codenfast-<id>-<variant>.desktop`, macOS `~/Applications/<Ad>.app`,
  Windows Başlat menüsü `<Ad>.lnk`. Linux'ta `logoUrl` png/svg ise menü ikonu olarak kullanılır.
- Mobilde yalnızca Keşfet + arama; kart düğmesi mağaza sayfasını açar.

`id` alanları (`app` ve `variant`) dosya yolunda kullanıldığı için yalnızca `A-Z a-z 0-9 . _ -` içerebilir.

## catalog.json

```json
{ "apps": [ {
  "id": "flykobi", "name": "Codenfast Flykobi", "category": "İş", "description": "...", "logoUrl": "https://.../logo.png",
  "mobile": { "android": "https://play.google.com/...", "ios": "https://apps.apple.com/..." },
  "variants": [
    { "id": "standard", "name": "Standart", "desktop": {
        "windows": { "manifestUrl": "https://.../win/files.json", "launch": { "exe": "flykobi2.exe", "args": [] } },
        "linux":   { "manifestUrl": "https://.../linux/files.json", "launch": { "exe": "flykobi2" } },
        "macos":   { "manifestUrl": "https://.../mac/files.json",   "launch": { "exe": "flykobi2.app/Contents/MacOS/flykobi2" } } } },
    { "id": "ozel-x", "name": "Özel Sürüm X", "desktop": { "...": "..." } }
  ] } ] }
```

- **Varyant (özel sürüm):** aynı ürünün kendi `manifestUrl` ve `launch` ayarına sahip kopyasıdır. Tek varyant varsa seçici görünmez. Her varyant ayrı dizine kurulur: `<AppSupport>/apps/<id>/<variantId>/`.
- `launch.exe`: kurulum dizinine göre göreli yol. `args` opsiyonel (örn. JDK ile `-jar sgn.jar`).
- Bir işletim sistemi için `desktop` girdisi yoksa kart "sürüm yok" gösterir.

## files.json (ürün/varyant/işletim sistemi başına)

```json
{ "version": "1.2.3",
  "osFileList": [ { "os": "linux", "fileList": [
    { "name": "app.jar", "fileSize": 123, "sha256": "…", "path": "lib", "url": "https://…/lib/app.jar" } ] } ] }
```

`version` ve `sha256` opsiyoneldir; `sha256` yoksa yalnızca boyut doğrulanır. "Güncelleme var" kararı, manifest içeriğinin hash'i kurulu kayıttan (`installed.json`) farklıysa verilir. `.zip` dosyaları indirildikten sonra otomatik açılır.

## Yayın yönetimi (`--admin`)

```
./codenfast_updater --admin          # geliştirmede: flutter run -d linux -t lib/main_admin.dart
```

Klasör seç → manifest üret → SCP ile yükle → sunucudaki `catalog.json`'u güncelle. Elle JSON yazmak gerekmez.

1. **Sunucu:** adres, port, kullanıcı, SSH anahtar dosyası, uzak kök dizin (`/home/KULLANICI/media`) ve herkese açık adres (`https://media.codenfast.com`). Ayarlar kaydedilir; parola/anahtar içeriği saklanmaz. Sistemin `ssh`/`scp` komutu kullanılır, etkileşimsizdir (`BatchMode`); parolalı anahtar için `ssh-agent` gerekir. İlk bağlantıda sunucu anahtarı otomatik kabul edilir (`accept-new`).
2. **Klasör:** işletim sistemi, sürüm ve yoksayılacak desenler. Yoksayılan dosyalar manifeste girmez **ve yüklenmez**.
3. **Ürün/varyant:** "Katalogu çek" ile sunucudaki katalog gelir; ürün ve varyant çipine tıklayınca form dolar. Yeni id yazarsanız yeni ürün/varyant oluşur.
4. **Başlatma:** çalıştırılacak dosya (taranan dosyalardan seçilebilir) ve argümanlar.

Dosyalar `<kök>/<appId>/<variantId>/<os>/` altına gider, manifest adresi `<açık adres>/<appId>/<variantId>/<os>/files.json` olur.

Yayın sırası: bağlantı → katalog çek/birleştir/doğrula → klasörler → dosyalar → `files.json` → `catalog.json`. Manifest dosyalardan sonra yüklendiği için istemciler yeni sürümü ancak her şey yerindeyken görür; `files.json` ve `catalog.json` önce `.tmp` olarak yüklenip `mv` ile yerine konur, eski katalog `catalog.json.bak` olarak saklanır. Katalogdaki bilinmeyen alanlar korunur.

Dosya yolları yalnızca `A-Z a-z 0-9 . _ -` içerebilir (boşluklu adlar URL'yi ve uzak kabuğu bozar); aksi halde ekran yeniden adlandırmanızı ister. Dosyalar klasör başına toplu `scp` ile gider; çok sayıda alt klasörü olan yüklerde (örn. açılmış JDK) yavaş olabilir, bunlar için `.zip` kullanmak daha hızlıdır (istemci zip'i kendisi açar).

## Manifest üretici

```
dart run bin/generate.dart --root ./dist/linux --os linux --version 1.2.3 \
  --base-url https://media.codenfast.com/flykobi/linux --output ./dist/linux/files.json
./codenfast_updater --generate ...   # derlenmiş uygulama ile aynı
```

| Bayrak | Anlamı |
| :--- | :--- |
| `--root` | Taranacak dizin (varsayılan: geçerli dizin) |
| `--os` | `windows` / `linux` / `macos` (varsayılan: çalıştığı sistem) |
| `--version` | Manifeste yazılır |
| `--base-url` | Her dosyanın `url` alanının öneki |
| `--output` | Çıktı yolu (varsayılan `files.json`) |
| `--ignore` | Tekrarlanabilir veya virgüllü ignore deseni |

Ignore desenleri: `*.log`, `build/`, `src/gen/*.dart`, `**/temp`, `secrets/key.pem`, `Thumbs.db`.

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

## Windows kurucuları (MSI / Inno Setup)

Windows hedefine `installer` eklenirse uygulama dosya senkronu yerine **kurucuyla** kurulur. `manifestUrl` kurucu dosyayı (sha256 doğrulamalı) dağıtır, `launch.exe` kurulu uygulamanın yoludur.

```json
"windows": {
  "manifestUrl": "https://.../flykobi/std/windows/files.json",
  "launch": { "exe": "%ProgramFiles%\\Flykobi\\flykobi.exe" },
  "installer": { "type": "inno", "file": "FlykobiSetup.exe", "displayName": "Flykobi", "args": [] }
}
```

- `type`: `msi` → `msiexec /i <dosya> /qn /norestart`; `inno` → `<dosya> /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-`. `args` bunlara eklenir (örn. `ALLUSERS=1`). Kurucu UAC ile (makine başına) çalışır; `0`, `1641`, `3010` başarı sayılır.
- **Kurulu mu / sürüm:** kayıt defterindeki "Programlar ve Özellikler" listesinden `displayName` ile (önek, büyük/küçük harf duyarsız) bulunur; gösterilen sürüm `DisplayVersion`'dır. MSI ürün kodu her sürümde değiştiği için ad kullanılır.
- **Güncelleme:** manifestteki `version` kurulu `DisplayVersion`'dan farklıysa "Güncelle" çıkar (`1.2` ile `1.2.0` aynı sayılır) ve kurucu üstüne kurulur. `version` yoksa manifest parmak izine bakılır. Bu yüzden kurucu uygulamalarda manifest `version` yazılmalıdır.
- **Aç:** `launch.exe` ortam değişkenleri açılarak kullanılır; göreliyse kayıt defterindeki kurulum klasörüne göre çözülür.
- **Kaldır:** kayıt defterindeki `QuietUninstallString` (MSI'da `msiexec /x {ürün-kodu} /qn`) çalışır; program listeden kalkmazsa hata verilir.
- Başarılı kurulumdan sonra indirilen kurucu dosyaları silinir. Portable uygulamalar `installer` olmadan eskisi gibi çalışır.

## Bağımlılıklar (VC++ Redist, DirectX...)

Uygulamalar ortak bileşenleri `requires` ile ister; bileşenler katalogdaki `dependencies` listesinde tanımlanır. Kurulumda uygulamadan **önce**, yalnızca eksikse kurulur; biri kurulamazsa uygulama kurulmaz. Kaldırma bağımlılıkları silmez (ortaktır).

```json
{ "dependencies": [ {
    "id": "vcredist-2022", "name": "VC++ 2015-2022 (x64)",
    "desktop": { "windows": {
      "manifestUrl": "https://.../_deps/vcredist-2022/windows/files.json",
      "run": { "exe": "vc_redist.x64.exe", "args": ["/install", "/quiet", "/norestart"] },
      "detect": { "registryKey": "HKLM\\SOFTWARE\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\x64", "registryValue": "Installed", "equals": "1" },
      "successCodes": [0, 1638, 1641, 3010]
  } } } ],
  "apps": [ { "id": "flykobi", "requires": ["vcredist-2022"], "...": "..." } ] }
```

- Dosyalar uygulamalarla aynı `files.json` düzeniyle (sha256 doğrulamalı) `<AppSupport>/deps/<id>/<os>/` altına inip `run` çalıştırılır. Klasör birden çok dosya içerebilir (DirectX: `DXSETUP.exe` + `.cab`'lar).
- `detect`: `registryKey` (+ `registryValue`, `equals`; yalnızca Windows) ve/veya `file` (`%ProgramFiles%` gibi değişkenler açılır). Sağlanıyorsa kurucu çalışmaz. Yoksa daha önce kurulduğu ve manifestin değişmediği kayıttan anlaşılır.
- Windows'ta kurucu UAC ile (yönetici izniyle) çalışır; diğer sistemlerde izinsiz doğrudan çalışır.
- **Linux paketleri (apt):** Linux hedefinde `manifestUrl`/`run` yerine `"apt": { "packages": ["libgtk-3-0"], "offlineManifestUrl": ".../_deps/libs/linux/files.json" }` verilir. Kurulu olmayan paketler için önce `https://checkip.amazonaws.com` denenir: yanıt gelirse `apt-get install -y`, gelmezse `offlineManifestUrl`'deki `.deb` dosyaları indirilip `dpkg -i` ile kurulur (çevrimdışı pakette bağımlı `.deb`'lerin hepsi bulunmalı). Root değilse `pkexec` parola penceresi açar. `apt-get` olmayan dağıtımlarda bağımlılık atlanır. Paket adları `a-z 0-9 + . : _ -` ile sınırlıdır.
- `successCodes` verilmezse `0, 1638, 1641, 3010` başarı sayılır.

## İşletim sistemleri / ISO (`downloads`)

Kurulmayan, yalnızca indirilen büyük dosyalar (ISO vb.) için ayrı bir bölüm. Masaüstünde **İşletim Sistemleri** sekmesi (katalogda en az bir kayıt varsa) görünür. Dosya, işletim sisteminin **İndirilenler** klasörüne iner.

```json
{ "downloads": [ {
  "id": "ubuntu", "name": "Ubuntu Desktop", "version": "26.04", "category": "İşletim Sistemleri",
  "description": "...", "logoUrl": "https://.../logo.png",
  "files": [
    { "name": "Desktop (amd64)", "fileName": "ubuntu-26.04-desktop-amd64.iso",
      "url": "https://media.codenfast.com/_files/ubuntu/ubuntu-26.04-desktop-amd64.iso",
      "sha256": "<64 hane>", "size": 6200000000 },
    { "name": "Desktop (arm64)", "fileName": "ubuntu-26.04-desktop-arm64.iso",
      "url": "https://releases.ubuntu.com/.../ubuntu-26.04-desktop-arm64.iso", "sha256": "<64 hane>" }
  ] } ] }
```

- `files` birden çoksa kartta seçici çıkar. `url` kendi sunucumuz ya da harici yansı olabilir (https zorunlu).
- `sha256` zorunludur; doğrulanmadan dosya son adını almaz, uyuşmazsa silinir. `size` isteğe bağlıdır.
- İndirme **durdurulabilir ve devam eder**: yarım dosya `<ad>.part` olarak kalır, sunucu `Range` destekliyorsa kaldığı yerden sürer.
- `fileName` yalnızca `A-Z a-z 0-9 . _ -` içerebilir. Aynı ad zaten indirilmiş ve sha256'sı doğruysa yeniden indirilmez.

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

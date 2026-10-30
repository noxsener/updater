# Sunucu Kurulumu ve İlk Yayın

Hazırlanan içerik `store_dist/` klasöründedir (6 uygulama, Linux; Android için Play Store linki). Bu klasör sunucu kökünün birebir kopyasıdır.

```
store_dist/
├── catalog.json
└── <appId>/
    ├── logo.png
    └── standard/linux/
        ├── files.json
        └── <uygulama dosyaları...>
```

| appId | Ad | Sürüm | Linux çalıştırılabilir | Play Store paketi |
| :--- | :--- | :--- | :--- | :--- |
| `flykobi` | Codenfast Flykobi | 1.0.2 | `flykobi2` | `com.codenfast.flykobi2` |
| `player` | Codenfast Player | 1.0.2 | `codenfast_player` | `com.codenfast.music_player` |
| `download-manager` | Codenfast Download Manager | 1.0.2 | `download_manager` | `com.codenfast.download_manager` |
| `sound-recorder` | Codenfast Sound Recorder | 1.0.0 | `CodenFastRecorder` | `com.codenfast.soundrecorder` |
| `converter` | Codenfast Converter | 1.0.0 | `converter` | `com.codenfast.converter` |
| `sticcker` | Codenfast Sticcker | 1.0.0 | `sticcker` | `com.codenfast.sticcker` |

Android girdileri `https://play.google.com/store/apps/details?id=<paket>` biçimindedir; mobilde kart düğmesi bu sayfayı açar.

## 1. Sunucu (hazır)

Nginx `media.codenfast.com` için kuruludur ve `~/media` klasörünü sunar; ek ayar gerekmez. Katalog adresi: `https://media.codenfast.com/catalog.json`.

Tek şart: nginx'in `.json` dosyalarını önbelleğe almaması (veya kısa tutması). Yeni sürüm görünmezse `curl -sI .../catalog.json` ile `Cache-Control` başlığına bakın.

## 2. İçeriği yükleyin

**Yöntem A — rsync (önerilen, ilk yükleme için):** (`KULLANICI`, `SUNUCU` ve `PORT` değerlerini kendinizinkilerle değiştirin)

```bash
cd ~/StudioProjects/updater
rsync -av -e "ssh -p PORT" --progress store_dist/ KULLANICI@SUNUCU:~/media/
```

Sıra önemli değil; istemciler `catalog.json`'dan başladığı için en son onu yüklemek isterseniz:

```bash
rsync -av -e "ssh -p PORT" --exclude catalog.json store_dist/ KULLANICI@SUNUCU:~/media/
rsync -av -e "ssh -p PORT" store_dist/catalog.json KULLANICI@SUNUCU:~/media/
```

**Yöntem B — yönetim ekranı (sonraki sürümler için):**

```bash
./codenfast_updater --admin      # geliştirmede: flutter run -d linux -t lib/main_admin.dart
```

Uzak kök dizin olarak sunucudaki **mutlak yolu** (`/home/KULLANICI/media`; `~` yazmayın) girip her uygulamanın `build/linux/x64/release/bundle` klasörünü, ilgili ürünle ve `standard` varyantıyla yayınlayın. Ayrıntı: `YAYIN_YONETIMI.md`.

## 3. Doğrulayın

```bash
curl -s https://media.codenfast.com/catalog.json | python3 -m json.tool | head
curl -sI https://media.codenfast.com/flykobi/standard/linux/files.json | head -1       # 200
curl -sI https://media.codenfast.com/flykobi/logo.png | head -1                         # 200
curl -sI https://media.codenfast.com/flykobi/standard/linux/flykobi2 | head -1          # 200
```

Sonra Updater'ı açıp bir uygulamayı **İndir → Aç** ile deneyin.

## 4. Updater'ı sunucuya yönlendirin

Varsayılan katalog adresi artık `https://media.codenfast.com/catalog.json` (`lib/services/catalog_service.dart`); ek bir şey gerekmez. Farklı bir adres için derlerken verin:

```bash
flutter build linux --release --dart-define=CATALOG_URL=https://media.codenfast.com/catalog.json
```

## 5. Yeni sürüm çıkarınca

1. Uygulamayı derleyin (`flutter build linux --release`), `pubspec.yaml` sürümünü artırın.
2. `tools/prepare_store.sh` ile `store_dist/`'i yeniden üretin **veya** `--admin` ekranından yayınlayın.
3. Yöntem A kullanıyorsanız `rsync` tekrar çalıştırın. Kullanıcılar manifest içeriği değiştiği için güncellemeyi otomatik görür.

`tools/prepare_store.sh` proje klasörlerini `~/StudioProjects` altında, adresi `https://media.codenfast.com` varsayar; `PROJECTS=` ve `BASE_URL=` ortam değişkenleriyle değişir.

## Bilmeniz gerekenler

- **Metinleri ben yazdım:** katalogdaki kategori ve kısa açıklamalar tahminidir. `tools/prepare_store.sh` içindeki `APPS` listesinden ya da yayından sonra `catalog.json`'dan düzeltin.
- **Logolar:** Android `ic_launcher.png` (xxxhdpi) kullanıldı; Sound Recorder için `assets/icons/app_icon.png`. **Converter** ve **Sound Recorder**'ın Android ikonu ~1,4 KB; büyük olasılıkla Flutter varsayılan ikonu. Gerçek logoları `<appId>/logo.png` olarak değiştirin.
- **Sticcker:** Linux derlemesi `tray_manager` eklentisindeki bir uyarı hata sayıldığı için başarısız oluyordu. `sticcker/linux/CMakeLists.txt` 44. satıra Download Manager'daki gibi `-Wno-error=deprecated-declarations` ekledim.
- **Derleme yan etkisi:** Linux derlemeleri Music Player, Sound Recorder, Converter ve Sticcker'da `pubspec.lock` ve `analysis_options.yaml` dosyalarını güncelledi (`git diff` ile bakın, istemezseniz geri alın).
- **Yalnızca Linux + Android:** Windows/macOS girdileri yok; kartlarda "sürüm yok" görünür. Flykobi ve Download Manager'ın mevcut Linux paketi yeniden derlenmedi, sürüm ve içerik `build/` klasöründeki halidir.
- **Test edilmedi:** sunucuya yükleme ve Play Store linklerinin açılması denenmedi.
- `store_dist/` (~200 MB) `.gitignore`'a eklendi.

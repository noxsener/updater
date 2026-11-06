# Yayın Yönetimi (`--admin`)

Yönetim ekranı ayrı bir uygulama değil; aynı program `--admin` parametresiyle açılır.

```
./codenfast_updater --admin
```

Amaç: bir klasördeki dosyaları okuyup `files.json` ve `catalog.json`'u otomatik üretmek ve SCP ile sunucuya yüklemek. Elle JSON yazmak gerekmez.

## Ekran

- **Sol:** katalogdaki tüm uygulamalar. Arama kutusu ad, id, kategori ve açıklamada arar; kategori listesiyle süzülür. Yüzlerce kayıtta da akıcıdır. **Yeni** düğmesi yeni uygulama başlatır.
- **Sağ üst:** katalogu yenile, **Sunucu ayarları** (adres, port, kullanıcı, SSH anahtarı, uzak kök dizin, herkese açık https adresi; pencerede bağlantı testi var). Ayarlar kaydedilir; parola veya anahtar içeriği saklanmaz. Açılışta ayarlar geçerliyse katalog kendiliğinden çekilir.
- **Bilgiler sekmesi:** ad, kategori, açıklama, logo, Play/App Store linkleri. **Katalogu güncelle** yalnızca `catalog.json`'u değiştirir; klasör seçmek veya dosya yüklemek gerekmez. Değişiklik varsa sekmede `•` görünür, düğme ancak o zaman açılır. **Katalogdan sil** uygulamayı katalogdan çıkarır (sunucudaki dosyalar silinmez, eski katalog `catalog.json.bak` olur).
- **Yayın sekmesi:** klasör, işletim sistemi, sürüm, yoksay deseni, varyant ve çalıştırılacak dosya/argümanlar. **Tara ve önizle** her dosyanın `sha256` ve boyutunu hesaplar, manifesti üretir ve sorunları listeler; sorun yoksa **Sunucuya yükle ve yayınla** açılır.
- **Windows kurulum şekli (Yayın sekmesi, Windows seçiliyken):** *Portable (dosya senkronu)*, *MSI* ya da *Inno Setup*. MSI/Inno seçilince klasörde kurucu dosya, kurulu program adı (Programlar ve Özellikler'deki ad; kurulu mu/sürüm/kaldırma buna bakar), ek parametreler ve kurulu uygulamanın yolu (`%ProgramFiles%\\Uygulama\\app.exe`) girilir. **Sürüm** alanını doldurun: güncelleme, bu değerin kurulu `DisplayVersion`'dan farklı olmasına bakar. Aynı uygulamayı sonradan *Portable* olarak yayınlarsanız `installer` kaydı katalogdan kalkar.
- **Yeni uygulama:** kimliği (yalnızca `A-Z a-z 0-9 . _ -`) ve adı girip ya "Kataloğa ekle" (örn. yalnızca mağaza linki olan harici uygulamalar) ya da Yayın sekmesinden dosyalarıyla birlikte yayınlayın.
- **Bağımlılıklar (üst çubuktaki yapboz simgesi):** ortak kurucuları yayınlar. Kimlik/ad/açıklama ortaktır; **Windows / Linux / macOS sekmelerinin** her biri kendi klasörünü, kurucusunu, denetim ölçütünü ve taramasını tutar (katalogda hedefi tanımlı sekmede ✓ görünür) ve ayrı yayınlanır. Kurucunun olduğu klasör taranır, `<kök>/_deps/<id>/<os>/` altına yüklenir ve `catalog.json`'daki `dependencies`'e yazılır (çalıştırılacak dosya, argümanlar, "kurulu mu?" ölçütü). Uygulamanın **Bilgiler** sekmesinde "Gerekli bağımlılıklar" çipleriyle seçilir; seçim sırası kurulum sırasıdır. Linux seçilince **apt paketleri** alanı çıkar: paket listesi doluysa klasör `.deb` dosyalarını (çevrimdışı yedek) içerir; **"Uygulama klasörünü tara"** uygulamanın ELF dosyalarını `ldd` ile tarayıp `dpkg -S` ile paket adlarını bulur ve temiz Docker imajında zaten olanları eler (yalnızca Linux makinede; `ldd` incelenen dosyayı çalıştırabilir, güvendiğin uygulamayı tara). **"Bu makineden seç"** bu makinede elle kurduğun paketleri (`apt-mark showmanual`) listeler, temiz imajda zaten olanları eler; arama kutusu ve "Yalnızca lib*" süzgeciyle çoklu seçip listeye topluca eklersin. **"Paketlerden .deb indir"** bu paketleri bağımlılıklarıyla Docker'da (`apt-get --download-only`) indirip klasör alanına yazar. "Yalnızca paket listesini kaydet" dosya yüklemeden katalogu günceller. Bir uygulamanın kullandığı bağımlılık silinemez.
- **İşletim sistemleri / ISO (üst çubuktaki albüm simgesi):** kayıt bilgileri (ad, sürüm, kategori, açıklama, logo) ve dosyalar yönetilir. Dosya iki yoldan eklenir: **Sunucuya yükle** (yerel dosya seçilir; sha256 ve boyut hesaplanır, `<kök>/_files/<id>/<ad>` altına yüklenir, ardından katalog güncellenir) ya da **Harici URL** (https adresi + yayıncının sha256 değeri; dosya yüklenmez). Bir kayıtta birden çok dosya (mimari/sürüm) olabilir; listedeki dosyaya tıklayınca forma yüklenir, ✕ katalogdan çıkarır. Yükleme `scp` ile yapılır ve yarıda kesilirse baştan başlar; çok büyük dosyaları sunucuya kendin kopyalayıp "Harici URL" ile kaydetmek daha rahat olabilir.
- **Alt panel:** işlem günlüğü.

Her katalog kaydı, sunucudaki **güncel** `catalog.json` üzerinde yalnızca ilgili uygulamayı değiştirir; başkasının aynı anda yaptığı değişiklikler ezilmez (aynı uygulamayı eş zamanlı düzenleme hariç).

## Sunucu düzeni

```
<kök>/catalog.json
<kök>/<appId>/<variantId>/<os>/files.json
<kök>/<appId>/<variantId>/<os>/<dosyalar...>
<kök>/_deps/<depId>/<os>/files.json   (bağımlılıklar)
<kök>/_files/<id>/<dosyaAdı>           (ISO vb. indirilebilir dosyalar)
```

Manifest adresi: `<açık adres>/<appId>/<variantId>/<os>/files.json`

## Yayın sırası

1. Bağlantıyı dener.
2. Sunucudaki `catalog.json`'u çeker, ürünü/varyantı ekler veya günceller, doğrular. (Sunucuda yoksa boş katalogla başlar.)
3. Uzak klasörleri oluşturur.
4. Dosyaları yükler.
5. `files.json`'u yükler.
6. Eski kataloğu `catalog.json.bak` olarak yedekler, yeni `catalog.json`'u yükler.

Güvenlik ve tutarlılık:
- Manifest dosyalardan sonra yüklendiği için kullanıcılar yeni sürümü ancak her şey yerindeyken görür.
- `files.json` ve `catalog.json` önce `.tmp` olarak yüklenip `mv` ile yerine taşınır; yarım dosya görünmez.
- Katalogdaki bilinmeyen alanlar korunur.
- Yoksayılan dosyalar (ör. `secrets/`) manifeste girmez ve sunucuya gönderilmez.
- Uzak yollar kısıtlı karakter kümesiyle sınırlıdır; uzak kabukta komut enjeksiyonuna karşı reddedilir.

## Kısıtlar

- **SSH:** sistemin `ssh` ve `scp` komutları kullanılır, etkileşimsiz çalışır (`BatchMode`). Parolalı anahtar için `ssh-agent` açık olmalı. İlk bağlantıda sunucu anahtarı otomatik kabul edilir (`accept-new`).
- **Dosya adları:** yollar yalnızca `A-Z a-z 0-9 . _ -` içerebilir. Boşluklu adlar URL'yi ve uzak kabuğu bozduğu için ekran reddeder; yeniden adlandırın veya yoksayın. Boşluklu `.app` klasörleri bu yüzden sorun çıkarır.
- **Hız:** dosyalar klasör başına toplu `scp` ile gider. Çok klasörlü yüklerde (örn. açılmış JDK) yavaş olabilir; tek bir `.zip` olarak yüklemek çok daha hızlıdır, istemci zip'i kendisi açar.
- **Test:** SSH/SCP katmanı sahte komutlarla test edildi (`test/publisher_test.dart`); gerçek sunucuya yükleme ve ekrandaki etkileşimler henüz elle denenmedi. Ekran widget testi, tema `google_fonts` ile ağdan font çektiği için yazılamadı.

## İlgili dosyalar

| Dosya | Görev |
| :--- | :--- |
| `lib/admin/admin_app.dart` | Yönetim ekranı |
| `lib/admin/publisher.dart` | Tarama, katalog birleştirme, yükleme sırası |
| `lib/admin/ssh_client.dart` | `ssh`/`scp` sarmalayıcı, uzak yol doğrulama |
| `lib/admin/catalog_doc.dart` | `catalog.json` düzenleme (bilinmeyen alanları korur) |
| `lib/admin/admin_config.dart` | Sunucu ayarlarının saklanması |
| `lib/generator/generator.dart` | Manifest üretici (CLI ile ortak) |

#!/usr/bin/env bash
# Linux paketlerini sunucu düzenine hazırlar ve files.json + catalog.json üretir.
# Kullanım: tools/prepare_store.sh [çıktı_dizini]   (varsayılan: ./store_dist)
set -euo pipefail

BASE_URL="${BASE_URL:-https://media.codenfast.com}"
PROJECTS="${PROJECTS:-$HOME/StudioProjects}"
OUT="$(realpath -m "${1:-store_dist}")"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

# id | ad | kategori | açıklama | proje klasörü | Linux çalıştırılabilir | Android paketi | logo (projeye göre)
APPS=(
  "flykobi|Codenfast Flykobi|İş|İşletme yönetim platformu.|flykobi2_client|flykobi2|com.codenfast.flykobi2|android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"
  "player|Codenfast Player|Medya|Müzik ve video oynatıcı.|music_player|codenfast_player|com.codenfast.music_player|android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"
  "download-manager|Codenfast Download Manager|Araçlar|İnternet indirme yöneticisi.|download_manager|download_manager|com.codenfast.download_manager|android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"
  "sound-recorder|Codenfast Sound Recorder|Medya|Profesyonel ses kayıt uygulaması.|sound_recorder|CodenFastRecorder|com.codenfast.soundrecorder|assets/icons/app_icon.png"
  "converter|Codenfast Converter|Araçlar|Dosya dönüştürücü.|converter|converter|com.codenfast.converter|android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"
  "sticcker|Codenfast Sticcker|Üretkenlik|Masaüstü yapışkan notlar.|sticcker|sticcker|com.codenfast.sticcker|android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"
)

rm -rf "$OUT"; mkdir -p "$OUT"
apps_json=""
for row in "${APPS[@]}"; do
  IFS='|' read -r id name cat desc dir exe pkg logo <<<"$row"
  src="$PROJECTS/$dir"
  bundle="$src/build/linux/x64/release/bundle"
  [ -x "$bundle/$exe" ] || { echo "HATA: $bundle/$exe yok (flutter build linux --release)"; exit 1; }
  version="$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' "$src/pubspec.yaml" | head -1)"
  dest="$OUT/$id/standard/linux"
  mkdir -p "$dest"
  cp -a "$bundle/." "$dest/"
  cp "$src/$logo" "$OUT/$id/logo.png"
  (cd "$HERE" && dart run bin/generate.dart --root "$dest" --os linux --version "$version" \
      --base-url "$BASE_URL/$id/standard/linux" --output "$dest/files.json" --ignore files.json >/dev/null)
  # files.json kendi taramasına girmesin diye üretimden sonra dosya listesinde yoktur
  entry=$(cat <<JSON
    { "id": "$id", "name": "$name", "category": "$cat", "description": "$desc",
      "logoUrl": "$BASE_URL/$id/logo.png",
      "mobile": { "android": "https://play.google.com/store/apps/details?id=$pkg" },
      "variants": [ { "id": "standard", "name": "Standart", "desktop": {
        "linux": { "manifestUrl": "$BASE_URL/$id/standard/linux/files.json", "launch": { "exe": "$exe" } } } } ] }
JSON
)
  apps_json+="${apps_json:+,
}$entry"
  echo "ok  $id $version ($(du -sh "$dest" | cut -f1))"
done
printf '{ "apps": [\n%s\n] }\n' "$apps_json" > "$OUT/catalog.json"
python3 -m json.tool "$OUT/catalog.json" >/dev/null && echo "catalog.json geçerli"
echo "Hazır: $OUT"

#!/bin/bash
# Double-clique sur ce fichier : il lit tes dossiers dans "projets" et "a-propos.txt", puis met le site à jour.
cd "$(dirname "$0")" || exit 1
OUT="projets.js"
THUMBMAX=1400

esc()     { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
htmlesc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/"/\&quot;/g' -e 's/</\&lt;/g'; }
urlenc()  { printf '%s' "$1" | sed -e 's/ /%20/g' -e 's/#/%23/g' -e 's/?/%3F/g'; }
getinfo() { [ -f "$1" ] && tr -d '\r' < "$1" | grep -i "^$2:" | head -1 | sed -e 's/^[^:]*:[[:space:]]*//'; }
getall()  { [ -f "$1" ] && tr -d '\r' < "$1" | grep -i "^$2:" | sed -e 's/^[^:]*:[[:space:]]*//' | sed -e '/^$/d'; }

# crée une miniature légère (grille et galerie) ; l'original reste utilisé pour l'agrandissement
mkthumb() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -s "$dst" ] && [ ! "$src" -nt "$dst" ]; then return 0; fi
  rm -f "$dst"
  case "$src" in
    *.gif|*.GIF|*.avif|*.AVIF) return 1 ;;
  esac
  if command -v sips >/dev/null 2>&1; then
    case "$src" in
      *.jpg|*.JPG|*.jpeg|*.JPEG) sips -Z $THUMBMAX -s format jpeg -s formatOptions 80 "$src" --out "$dst" >/dev/null 2>&1 ;;
      *) sips -Z $THUMBMAX "$src" --out "$dst" >/dev/null 2>&1 ;;
    esac
  elif command -v magick >/dev/null 2>&1; then
    magick "$src" -resize "${THUMBMAX}x${THUMBMAX}>" -quality 80 "$dst" >/dev/null 2>&1
  elif command -v convert >/dev/null 2>&1; then
    convert "$src" -resize "${THUMBMAX}x${THUMBMAX}>" -quality 80 "$dst" >/dev/null 2>&1
  else
    return 1
  fi
  [ -s "$dst" ] || { rm -f "$dst"; return 1; }
}

count=0
{
  echo "/* Fichier généré automatiquement par mettre-a-jour.command. Ne pas modifier à la main. */"

  # ---------- page info ----------
  A="a-propos.txt"
  textes=""; n=0
  while IFS= read -r l; do
    [ $n -gt 0 ] && textes="$textes,"; textes="$textes\"$(esc "$l")\""; n=$((n+1))
  done < <(getall "$A" texte)
  links=""; n=0
  addlink() { [ $n -gt 0 ] && links="$links,"; links="$links{label:\"$(esc "$1")\",href:\"$(esc "$2")\"}"; n=$((n+1)); }
  mail=$(getinfo "$A" email); [ -n "$mail" ] && addlink "$mail" "mailto:$mail"
  insta=$(getinfo "$A" instagram)
  if [ -n "$insta" ]; then
    case "$insta" in
      http*) addlink "instagram" "$insta" ;;
      *) h=$(printf '%s' "$insta" | sed -e 's/^@//'); addlink "@$h" "https://instagram.com/$h" ;;
    esac
  fi
  while IFS= read -r l; do
    lab=$(printf '%s' "${l%%|*}" | sed -e 's/[[:space:]]*$//')
    url=$(printf '%s' "${l#*|}" | sed -e 's/^[[:space:]]*//')
    [ -n "$lab" ] && [ -n "$url" ] && addlink "$lab" "$url"
  done < <(getall "$A" lien)
  echo "const about = { texte:[${textes}], links:[${links}] };"

  # ---------- projets ----------
  echo "const projects = ["
  for dir in projets/*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    imgs=$(find "$dir" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.avif' \) | sort)
    [ -z "$imgs" ] && continue
    title=$(printf '%s' "$name" | sed -E 's/^[0-9]+[-_ ]*//; s/[-_]/ /g')
    info="${dir}infos.txt"
    t=$(getinfo "$info" titre); [ -n "$t" ] && title="$t"
    date=$(getinfo "$info" date)
    text=$(getinfo "$info" texte)
    [ $count -gt 0 ] && echo ","
    list=""; tlist=""; k=0
    while IFS= read -r f; do
      rel="${f#projets/}"; th="miniatures/$rel"
      mkthumb "$f" "$th" || th="$f"
      [ $k -gt 0 ] && { list="$list,"; tlist="$tlist,"; }
      list="$list\"$(esc "$(urlenc "$f")")\""
      tlist="$tlist\"$(esc "$(urlenc "$th")")\""
      k=$((k+1))
    done <<< "$imgs"
    printf '  { title:"%s", date:"%s", text:"%s", images:[%s], thumbs:[%s] }' "$(esc "$title")" "$(esc "$date")" "$(esc "$text")" "$list" "$tlist"
    count=$((count+1))
  done
  echo ""
  echo "];"
} > "$OUT"

# ---------- aperçu de partage (titre, description, image) dans index.html ----------
SITE=$(getinfo a-propos.txt site | sed -e 's:/*$::')
DESC=$(getinfo a-propos.txt description); [ -z "$DESC" ] && DESC="Portfolio de maxène boukhellouf, graphiste."
{
  echo '<!-- og:start -->'
  echo "<meta name=\"description\" content=\"$(htmlesc "$DESC")\">"
  echo '<meta property="og:type" content="website">'
  echo '<meta property="og:title" content="maxène boukhellouf">'
  echo "<meta property=\"og:description\" content=\"$(htmlesc "$DESC")\">"
  echo '<meta name="twitter:card" content="summary_large_image">'
  if [ -n "$SITE" ]; then
    echo "<meta property=\"og:url\" content=\"$(htmlesc "$SITE")/\">"
    echo "<meta property=\"og:image\" content=\"$(htmlesc "$SITE")/images/apercu.jpg\">"
  fi
  echo '<!-- og:end -->'
} > .og.tmp
if grep -q '<!-- og:start -->' index.html; then
  awk 'BEGIN{while((getline l < ".og.tmp")>0) blk=blk l "\n"} /<!-- og:start -->/{printf "%s", blk; skip=1} skip&&/<!-- og:end -->/{skip=0; next} !skip{print}' index.html > .index.new && mv .index.new index.html
fi
rm -f .og.tmp

echo ""
echo "✅ Site mis à jour : $count projet(s) trouvé(s)."
[ -z "$SITE" ] && echo "ℹ️  Pour l'aperçu de partage (image), renseigne « site: » dans a-propos.txt puis relance."
echo "Tu peux fermer cette fenêtre."

#!/bin/bash
# Icon-Themes verwalten, mit Bild-Vorschau (fzf + kitty).
#
#   icon-theme.sh                    Menü
#   icon-theme.sh theme              Installiertes Theme aktivieren
#   icon-theme.sh online [SUCHE]     Themes auf gnome-look.org ansehen und laden
#   icon-theme.sh loeschen           Installierte Themes löschen
#   icon-theme.sh ordner [PFAD]      Ordner-Icon setzen/zurücksetzen
#   icon-theme.sh install DATEI|DIR  Theme aus .tar.*/.zip oder Ordner installieren

ICON_DIRS=("$HOME/.local/share/icons" "$HOME/.icons" "/usr/share/icons")
USER_ICONS="$HOME/.local/share/icons"
CACHE="$HOME/.cache/icon-theme-picker"
ONLINE="$CACHE/online"
OCS="https://api.pling.com/ocs/v1/content/data"   # gnome-look.org, Kategorie 132 = Full Icon Themes
SELF="$(realpath "$0")"
SAMPLES=(folder user-home folder-documents folder-download folder-music folder-pictures
         folder-videos user-trash text-x-generic image-x-generic audio-x-generic video-x-generic
         application-pdf package-x-generic text-x-script firefox org.gnome.Nautilus utilities-terminal)

mkdir -p "$CACHE" "$ONLINE"

# ── Hilfsfunktionen ──────────────────────────────────────────────────────────

current_theme() { gsettings get org.gnome.desktop.interface icon-theme | tr -d "'"; }

theme_path() {
    local d
    for d in "${ICON_DIRS[@]}"; do
        [ -f "$d/$1/index.theme" ] && { echo "$d/$1"; return; }
    done
}

# Zeilen: "● <TAB>Name" (aktiv) bzw. "  <TAB>Name"
list_themes() {
    local d t cur
    cur=$(current_theme)
    for d in "${ICON_DIRS[@]}"; do
        for t in "$d"/*/index.theme; do
            [ -f "$t" ] || continue
            grep -q '^Directories=' "$t" || continue   # Cursor-Themes ausfiltern
            basename "$(dirname "$t")"
        done
    done | grep -vxE 'hicolor|locolor|default' | sort -u | while read -r t; do
        [ "$t" = "$cur" ] && printf '●\t%s\n' "$t" || printf ' \t%s\n' "$t"
    done
}

# Alle Icon-Dateien eines Themes, größte/skalierbare Version zuerst
icon_files() {
    find -L "$1" -type f \( -name '*.svg' -o -name '*.png' \) -not -path '*symbolic*' 2>/dev/null |
        awk '{ s = 0
               if ($0 ~ /scalable/) s = 1000
               else if (match($0, /[0-9]+x[0-9]+|\/[0-9]+\//)) { v = substr($0, RSTART, RLENGTH); gsub(/[^0-9x]/, "", v); split(v, a, "x"); s = a[1] }
               if ($0 ~ /@[23]x/) s -= 1
               print s "\t" $0 }' | sort -t$'\t' -k1,1rn | cut -f2
}

to_png() {   # to_png QUELLE ZIEL GRÖSSE
    case "$1" in
        *.svg) rsvg-convert -w "$3" -h "$3" -a "$1" -o "$2" 2>/dev/null ;;
        *)     magick "$1" -resize "${3}x${3}" "$2" 2>/dev/null ;;
    esac
}

show_image() {   # show_image BILD [ZEILEN_OBEN_BELEGT]
    local top="${2:-0}"
    kitty icat --clear --transfer-mode=memory --unicode-placeholder --stdin=no \
        --place="${FZF_PREVIEW_COLUMNS}x$((FZF_PREVIEW_LINES - top))@0x0" "$1" | sed '$d' | sed $'$s/$/\e[m/'
}

set_gtk_ini() {
    local f
    for f in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
        mkdir -p "$(dirname "$f")"
        [ -f "$f" ] || echo '[Settings]' > "$f"
        if grep -q '^gtk-icon-theme-name=' "$f"; then
            sed -i "s/^gtk-icon-theme-name=.*/gtk-icon-theme-name=$1/" "$f"
        else
            echo "gtk-icon-theme-name=$1" >> "$f"
        fi
    done
}

apply_theme() {
    gsettings set org.gnome.desktop.interface icon-theme "$1"
    set_gtk_ini "$1"
    echo "Icon-Theme: $1"
    restart_nautilus
}

restart_nautilus() {
    pgrep -x nautilus > /dev/null && nautilus -q && echo "Nautilus neu gestartet – einfach wieder öffnen."
}

ask() {   # ask FRAGE [j|n]  – Default steht im zweiten Argument
    local a
    if [ "${2:-n}" = j ]; then read -rp "$1 [J/n] " a; [[ ! "$a" =~ ^[nN] ]]
    else                       read -rp "$1 [j/N] " a; [[ "$a" =~ ^[jJyY] ]]; fi
}

# ── Vorschau lokaler Themes ──────────────────────────────────────────────────

build_theme_preview() {
    local name="$1" path img tmp files n f i=0
    path=$(theme_path "$name")
    [ -n "$path" ] || return
    img="$CACHE/theme-$name.png"
    if [ ! -f "$img" ] || [ "$path/index.theme" -nt "$img" ]; then
        tmp=$(mktemp -d)
        files=$(icon_files "$path")
        for n in "${SAMPLES[@]}"; do
            f=$(grep -m1 -E "/$n\.(svg|png)$" <<< "$files") || continue
            to_png "$f" "$tmp/$(printf %02d $i).png" 96 && i=$((i + 1))
        done
        [ "$i" -gt 0 ] && montage "$tmp"/*.png -tile 6x -geometry 96x96+14+14 -background none "$img.tmp.png" 2>/dev/null &&
            mv "$img.tmp.png" "$img"
        rm -rf "$tmp"
    fi
}

preview_theme() {
    local img="$CACHE/theme-$1.png"
    build_theme_preview "$1"
    echo "$1  —  $(theme_path "$1")"
    [ -f "$img" ] && show_image "$img" 1 || echo "(keine Vorschau möglich)"
}

preview_icon() {
    local img="$CACHE/icon-$(echo "$1" | md5sum | cut -c1-16).png"
    [ -f "$1" ] || { echo "Eigenes Icon entfernen, Ordner bekommt wieder das Theme-Icon."; return; }
    [ -f "$img" ] || to_png "$1" "$img" 256
    basename "$1"
    show_image "$img" 1
}

# Vorschaubilder im Hintergrund erzeugen, damit Blättern flüssig ist
warm_previews() {
    ( list_themes | cut -f2 | while read -r t; do build_theme_preview "$t"; done ) &> /dev/null &
    echo $!
}

pick_themes() {   # pick_themes PROMPT HEADER [fzf-Optionen…]  → Namen, eine pro Zeile
    local prompt="$1" header="$2"; shift 2
    list_themes | fzf --prompt="$prompt" --header="$header" --delimiter='\t' \
        --preview="'$SELF' _preview-theme {2}" --preview-window=right,65% "$@" | cut -f2
}

# ── Online (gnome-look.org) ──────────────────────────────────────────────────

# online_list SORT [SUCHE]  – SORT: down (Downloads), new, high (Bewertung)
# Ausgabe: ID <TAB> formatierte Zeile; Ergebnis wird 12 h gecacht
online_list() {
    local sort="${1:-down}" q="$2" f page data
    f="$ONLINE/list-$sort-$(printf %s "$q" | md5sum | cut -c1-12).jsonl"
    if [ ! -s "$f" ] || [ -n "$(find "$f" -mmin +720)" ]; then
        : > "$f.tmp"
        for page in 0 1 2 3 4; do
            data=$(curl -fsG "$OCS" -d categories=132 -d format=json -d pagesize=100 \
                -d sortmode="$sort" -d page="$page" --data-urlencode "search=$q") || break
            jq -c '.data[]' <<< "$data" >> "$f.tmp"
            [ "$(jq '.data | length' <<< "$data")" -lt 100 ] && break
        done
        [ -s "$f.tmp" ] || { rm -f "$f.tmp"; return 1; }
        mv "$f.tmp" "$f"
    fi
    echo "$f" > "$ONLINE/current"
    jq -r '[.id, .name, (.downloads | tonumber), .score, .changed[0:10], .personid] | @tsv' "$f" |
        awk -F'\t' '{ d = $3
                      if (d >= 1e6) d = sprintf("%.1fM", d / 1e6); else if (d >= 1e3) d = sprintf("%.0fk", d / 1e3)
                      printf "%s\t%-36.36s ⬇%6s  ★%3s  %s  %s\n", $1, $2, d, $4, $5, $6 }'
}

online_item() { jq -c --argjson id "$1" 'select(.id == $id)' "$(cat "$ONLINE/current")" | head -n1; }

online_pics() { jq -r 'to_entries[] | select(.key | test("^previewpic[0-9]+$")) | select(.value != "") | .value' <<< "$1"; }

online_pic_file() {   # online_pic_file ID N URL  → Pfad (lädt bei Bedarf)
    local f="$ONLINE/pic-$1-$2.${3##*.}"
    [ -s "$f" ] || curl -fsL --max-time 15 -o "$f" "$3" || rm -f "$f"
    echo "$f"
}

# Bildindex pro Eintrag: Datei enthält "ID N"
pic_index() {
    local id n
    [ -f "$ONLINE/picidx" ] && read -r id n < "$ONLINE/picidx"
    [ "$id" = "$1" ] && echo "${n:-1}" || echo 1
}

pic_step() {   # pic_step ID +1|-1
    local n
    n=$(( $(pic_index "$1") + $2 ))
    echo "$1 $n" > "$ONLINE/picidx"
}

preview_online() {
    local id="$1" item pics total n url img
    item=$(online_item "$id")
    mapfile -t pics < <(online_pics "$item")
    total=${#pics[@]}
    jq -r '"\(.name)  v\(.version)  von \(.personid)\n⬇ \(.downloads)  ★ \(.score)  aktualisiert \(.changed[0:10])  —  \(.detailpage)"' <<< "$item"
    if [ "$total" -eq 0 ]; then echo; echo "(keine Bilder)"; return; fi
    n=$(pic_index "$id")
    n=$(( ((n - 1) % total + total) % total + 1 ))
    echo "Bild $n/$total   (Shift-← / Shift-→)"
    url=${pics[n - 1]}
    img=$(online_pic_file "$id" "$n" "$url")
    [ -s "$img" ] && show_image "$img" 3 || echo "(Bild konnte nicht geladen werden)"
}

# Erste Bilder der obersten Einträge schon mal laden
warm_online() {
    (
        jq -r '[.id, .previewpic1] | @tsv' "$(cat "$ONLINE/current")" | head -n 40 |
            while IFS=$'\t' read -r id url; do
                [ -n "$url" ] && online_pic_file "$id" 1 "$url" > /dev/null &
                (( $(jobs -r | wc -l) >= 6 )) && wait -n
            done
        wait
    ) &> /dev/null &
    echo $!
}

online_download() {
    local id="$1" item files picks tmp i name link
    # Download-Links laufen ab, darum frisch abfragen
    item=$(curl -fsG "$OCS/$id" -d format=json | jq -c '.data[0]') || { echo "Konnte Eintrag $id nicht abrufen."; return 1; }
    files=$(jq -r 'range(1; 100) as $i | select((.["downloadlink\($i)"] // "") != "")
                   | [$i, .["downloadname\($i)"], ((.["downloadsize\($i)"] // 0) / 1024 * 10 | round / 10 | tostring) + " MB"] | @tsv' <<< "$item")
    [ -n "$files" ] || { echo "Keine Downloads bei diesem Eintrag."; return 1; }

    if [ "$(wc -l <<< "$files")" -eq 1 ]; then
        picks=$files
    else
        picks=$(fzf -m --prompt='Datei > ' --header='Tab = mehrere wählen   Enter = laden' \
            --delimiter='\t' --with-nth=2.. --height=~20 --reverse <<< "$files") || return
    fi

    tmp=$(mktemp -d)
    while IFS=$'\t' read -r i name _; do
        name=$(basename "$name")
        link=$(jq -r --arg k "downloadlink$i" '.[$k]' <<< "$item")
        echo "Lade $name …"
        curl -fL --progress-bar -o "$tmp/$name" "$link" && install_from "$tmp/$name"
    done <<< "$picks"
    rm -rf "$tmp"
}

cmd_online() {
    local q="$1" pick warm
    echo "Lade Liste von gnome-look.org …"
    online_list down "$q" > "$ONLINE/start" || { echo "Keine Verbindung?"; return 1; }
    warm=$(warm_online)
    while pick=$(fzf --prompt='Online > ' --delimiter='\t' --with-nth=2 < "$ONLINE/start" \
            --header=$'Enter = herunterladen   Shift-←/→ = Bilder   Ctrl-S = online nach Eingabe suchen\nAlt-D = meiste Downloads   Alt-N = neueste   Alt-B = beste Bewertung' \
            --preview="'$SELF' _preview-online {1}" --preview-window=right,60% \
            --bind="shift-right:execute-silent('$SELF' _pic {1} 1)+refresh-preview" \
            --bind="shift-left:execute-silent('$SELF' _pic {1} -1)+refresh-preview" \
            --bind="ctrl-s:reload('$SELF' _online-list down {q})+clear-query" \
            --bind="alt-d:reload('$SELF' _online-list down)" \
            --bind="alt-n:reload('$SELF' _online-list new)" \
            --bind="alt-b:reload('$SELF' _online-list high)"); do
        online_download "$(cut -f1 <<< "$pick")"
        ask "Noch ein Theme ansehen?" n || break
    done
    kill "$warm" 2> /dev/null
}

# ── Befehle ──────────────────────────────────────────────────────────────────

cmd_theme() {
    local pick warm
    warm=$(warm_previews)
    pick=$(pick_themes 'Icon-Theme > ' 'Enter = übernehmen   ● = aktiv')
    kill "$warm" 2> /dev/null
    [ -n "$pick" ] && apply_theme "$pick"
}

cmd_loeschen() {
    local cur warm picks t d path pkg users=() pkgs=() other
    cur=$(current_theme)
    warm=$(warm_previews)
    picks=$(pick_themes 'Löschen > ' 'Tab = markieren   Ctrl-A = alle Treffer   Enter = löschen' -m --bind=ctrl-a:select-all)
    kill "$warm" 2> /dev/null
    [ -n "$picks" ] || return

    while read -r t; do
        path=$(theme_path "$t")
        if [ "$t" = "$cur" ]; then
            echo "Übersprungen: $t ist gerade aktiv – erst ein anderes Theme wählen."
        elif [[ "$path" == "$HOME"/* ]]; then
            users+=("$path")
        elif pkg=$(pacman -Qoq "$path/index.theme" 2> /dev/null); then
            pkgs+=("$pkg")
        else
            echo "Übersprungen: $path gehört zu keinem Paket, bitte von Hand löschen."
        fi
    done <<< "$picks"

    if [ ${#users[@]} -gt 0 ]; then
        echo; echo "Wird gelöscht:"; printf '  %s\n' "${users[@]/#$HOME/\~}"
        # Warnen, wenn ein verbleibendes Theme davon erbt
        for path in "${users[@]}"; do
            t=$(basename "$path")
            other=$(for d in "${ICON_DIRS[@]}"; do grep -lE "^Inherits=(.*,)?$t(,|$)" "$d"/*/index.theme 2> /dev/null; done |
                xargs -r -n1 dirname | xargs -r -n1 basename | grep -vxF -f <(printf '%s\n' "${users[@]##*/}"))
            [ -n "$other" ] && echo "  ⚠ $t wird noch gebraucht von: $(paste -sd' ' <<< "$other")"
        done
        if ask "Wirklich löschen?" n; then
            for path in "${users[@]}"; do
                rm -rf "${path:?}" "$CACHE/theme-$(basename "$path").png"
            done
            echo "${#users[@]} Theme(s) gelöscht."
        fi
    fi

    if [ ${#pkgs[@]} -gt 0 ]; then
        mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | sort -u)
        echo; echo "System-Themes, gehören zu Paketen: ${pkgs[*]}"
        ask "Mit 'sudo pacman -Rns ${pkgs[*]}' entfernen?" n && sudo pacman -Rns "${pkgs[@]}"
    fi
}

cmd_ordner() {
    local dir="$1" path pick
    if [ -z "$dir" ]; then
        dir=$(find "$HOME" -mindepth 1 -maxdepth 2 -type d -not -path '*/.*' 2>/dev/null | sed "s|^$HOME/||" | sort |
            fzf --prompt='Ordner > ' --preview="gio info -a metadata::custom-icon '$HOME/{}' | tail -n1") || return
        dir="$HOME/$dir"
    fi
    [ -d "$dir" ] || { echo "Kein Ordner: $dir"; return 1; }

    path=$(theme_path "$(current_theme)")
    pick=$( { echo "↺ zurücksetzen"
              icon_files "$path" | grep -E '/[^/]*folder[^/]*\.(svg|png)$' | grep -vE -- '-open\.|-drag-accept' |
                  awk -F/ '!seen[$NF]++ { print $NF "\t" $0 }' | sort | cut -f2
            } | fzf --prompt="Icon für ${dir/#$HOME/\~} > " --with-nth=-1 --delimiter=/ \
                    --preview="'$SELF' _preview-icon {}" --preview-window=right,55%) || return

    if [ "$pick" = "↺ zurücksetzen" ]; then
        gio set "$dir" -t unset metadata::custom-icon
        echo "Zurückgesetzt: $dir"
    else
        gio set "$dir" metadata::custom-icon "file://$pick"
        echo "${dir/#$HOME/\~} -> $(basename "$pick")"
    fi
    restart_nautilus
}

extract() {   # extract ARCHIV ZIEL
    case "$1" in
        *.zip)        unzip -q "$1" -d "$2" ;;
        *.tar*|*.tgz) tar -xf "$1" -C "$2" ;;
        *)            return 1 ;;
    esac
}

# Theme(s) aus Archiv oder Ordner nach ~/.local/share/icons kopieren
install_from() {
    local src="$1" tmp t dir name found=0 inner
    [ -e "$src" ] || { echo "Gibt's nicht: $src"; return 1; }
    tmp=$(mktemp -d)
    if [ -d "$src" ]; then cp -a "$src" "$tmp/"; else extract "$src" "$tmp" || { echo "Unbekanntes Format: $src"; rm -rf "$tmp"; return 1; }; fi

    # Manche Packs stecken nochmal in Archiven
    if ! find "$tmp" -name index.theme | grep -q .; then
        while read -r inner; do extract "$inner" "$(dirname "$inner")"; done < <(find "$tmp" -type f \( -name '*.tar*' -o -name '*.zip' -o -name '*.tgz' \))
    fi

    mkdir -p "$USER_ICONS"
    while read -r t; do
        dir=$(dirname "$t")
        if [ "$dir" = "$tmp" ]; then name=$(basename "$src"); name=${name%%.*}; else name=$(basename "$dir"); fi
        [ -e "$USER_ICONS/$name" ] && echo "Aktualisiert: $name" || echo "Installiert: $name"
        rm -rf "${USER_ICONS:?}/$name"
        cp -a "$dir" "$USER_ICONS/$name"
        gtk-update-icon-cache -qf "$USER_ICONS/$name" 2>/dev/null
        found=1
    done < <(find "$tmp" -name index.theme -exec grep -l '^Directories=' {} +)
    rm -rf "$tmp"
    [ "$found" = 1 ] || { echo "Kein Icon-Theme (index.theme) gefunden in $(basename "$src")."; return 1; }
}

cmd_install() {
    install_from "$1" || return
    ask "Jetzt Theme auswählen?" j && cmd_theme
}

menu() {
    local choice p
    while choice=$(printf '%s\n' "Theme aktivieren" "Online ansehen & herunterladen" "Themes löschen" \
                       "Ordner-Icon ändern" "Aus Datei/Ordner installieren" |
                   fzf --prompt='Icons > ' --header="Aktiv: $(current_theme)   Esc = beenden" --height=~12 --reverse); do
        case "$choice" in
            "Theme aktivieren")   cmd_theme ;;
            "Online"*)            cmd_online ;;
            "Themes löschen")     cmd_loeschen ;;
            "Ordner-Icon ändern") cmd_ordner ;;
            "Aus Datei"*)         read -rep "Pfad zu .tar.xz/.zip/Ordner: " p; cmd_install "${p/#\~/$HOME}" ;;
        esac
        echo
    done
}

# ── Einstieg ─────────────────────────────────────────────────────────────────

# Interne Aufrufe aus fzf
case "$1" in
    _preview-theme)  preview_theme "$2"; exit ;;
    _preview-icon)   preview_icon "$2"; exit ;;
    _preview-online) preview_online "$2"; exit ;;
    _online-list)    online_list "$2" "$3"; exit ;;
    _pic)            pic_step "$2" "$3"; exit ;;
esac

# Ohne Terminal (z.B. per Hyprland-Keybind) in kitty öffnen
[ -t 1 ] || exec kitty --class icon-theme-picker -e env ICON_PICKER_WINDOW=1 "$SELF" "$@"

case "$1" in
    "")       menu; exit ;;
    theme)    cmd_theme ;;
    online)   cmd_online "$2" ;;
    loeschen|löschen|delete) cmd_loeschen ;;
    ordner)   cmd_ordner "$2" ;;
    install)  cmd_install "$2" ;;
    *)        sed -n '2,9p' "$SELF" | sed 's/^# \?//'; exit ;;
esac

# Eigenes Fenster bei Einzelbefehl kurz offen lassen, damit man die Meldung sieht
[ -n "$ICON_PICKER_WINDOW" ] && read -rsn1 -p "Taste drücken zum Schließen…"

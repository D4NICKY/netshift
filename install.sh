#!/bin/sh
# shellcheck shell=dash

JSDELIVR_API="https://data.jsdelivr.com/v1/packages/gh/yandexru45/netshift"
JSDELIVR_CDN="https://cdn.jsdelivr.net/gh/yandexru45/netshift"
DOWNLOAD_DIR="/tmp/netshift"
COUNT=3

PKG_IS_APK=0
command -v apk >/dev/null 2>&1 && PKG_IS_APK=1

rm -rf "$DOWNLOAD_DIR"
mkdir -p "$DOWNLOAD_DIR"

msg() {
    printf "\033[32;1m%s\033[0m\n" "$1"
}

pkg_is_installed () {
    local pkg_name="$1"

    if [ "$PKG_IS_APK" -eq 1 ]; then
        apk list --installed | grep -q "$pkg_name"
    else
        opkg list-installed | grep -q "$pkg_name"
    fi
}

pkg_remove() {
    local pkg_name="$1"

    if [ "$PKG_IS_APK" -eq 1 ]; then
        apk del "$pkg_name"
    else
        opkg remove --force-depends "$pkg_name"
    fi
}

pkg_list_update() {
    if [ "$PKG_IS_APK" -eq 1 ]; then
        apk update
    else
        opkg update
    fi
}

pkg_install() {
    local pkg_file="$1"

    if [ "$PKG_IS_APK" -eq 1 ]; then
        apk add --allow-untrusted "$pkg_file"
    else
        opkg install --force-downgrade --force-reinstall "$pkg_file"
    fi
}

update_config() {
    printf "\033[48;5;196m\033[1m╔══════════════════════════════════════════════════════════════════════╗\033[0m\n"
    printf "\033[48;5;196m\033[1m║ ! Обнаружена старая версия NetShift.                                 ║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Если продолжите обновление, вам потребуется настроить NetShift заново.║\033[0m\n"
    printf "\033[48;5;196m\033[1m║ Старая конфигурация будет сохранена в /etc/config/netshift-070       ║\033[0m\n"
    printf "\033[48;5;196m\033[1m╚══════════════════════════════════════════════════════════════════════╝\033[0m\n"

    echo ""
    msg "Continue? (yes/no)"

    while true; do
            read -r -p '' CONFIG_UPDATE
            case $CONFIG_UPDATE in

            yes|y|Y)
                mv /etc/config/netshift /etc/config/netshift-070
                wget -O /etc/config/netshift "${JSDELIVR_CDN}@main/netshift/files/etc/config/netshift"
                msg "NetShift config has been reset to default. Your old config saved in /etc/config/netshift-070"
                break
                ;;
            *)
                msg "Exit"
                exit 1
                ;;
        esac
    done
}

podkop_is_installed() {
    if [ -f "/etc/config/podkop" ] || command -v podkop >/dev/null 2>&1 || [ -x "/etc/init.d/podkop" ]; then
        return 0
    fi
    return 1
}

migrate_from_podkop() {
    msg "Migrating from podkop to NetShift..."

    if [ -x "/etc/init.d/podkop" ]; then
        /etc/init.d/podkop stop 2>/dev/null || true
        /etc/init.d/podkop disable 2>/dev/null || true
    fi

    if [ -f "/etc/config/podkop" ]; then
        [ ! -f "/etc/config/netshift" ] && cp /etc/config/podkop /etc/config/netshift 2>/dev/null || true
        [ ! -f "/etc/config/podkop.bak.pre-netshift" ] && cp /etc/config/podkop /etc/config/podkop.bak.pre-netshift 2>/dev/null || true
        rm -f /etc/config/podkop 2>/dev/null || true
    fi

    if [ -d "/etc/podkop" ] && [ ! -d "/etc/netshift" ]; then
        cp -r /etc/podkop /etc/netshift 2>/dev/null || true
    fi

    if pkg_is_installed luci-i18n-podkop; then pkg_remove luci-i18n-podkop*; fi
    if pkg_is_installed luci-app-podkop; then pkg_remove luci-app-podkop; fi
    if pkg_is_installed "^podkop" || command -v podkop >/dev/null 2>&1; then pkg_remove podkop; fi

    msg "Migration complete."
}

download_release_asset() {
    url="$1"
    filename="$2"
    filepath="$DOWNLOAD_DIR/$filename"

    attempt=0
    while [ $attempt -lt $COUNT ]; do
        msg "Download $filename via jsDelivr (count $((attempt + 1)))..."
        if wget -O "$filepath" "$url"; then
            if [ -s "$filepath" ]; then
                msg "$filename successfully downloaded"
                return 0
            fi
        fi
        msg "Download error for $filename. Retrying..."
        rm -f "$filepath"
        attempt=$((attempt + 1))
    done

    msg "Failed to download $filename after $COUNT attempts"
    return 1
}

get_latest_version() {
    if command -v curl >/dev/null 2>&1; then
        curl -s "$JSDELIVR_API" | grep -o '"tags":{[^}]*' | grep -o '"latest":"[^"]*' | cut -d'"' -f4
    else
        wget -qO- "$JSDELIVR_API" | grep -o '"tags":{[^}]*' | grep -o '"latest":"[^"]*' | cut -d'"' -f4
    fi
}

main() {
    check_system
    sing_box

    pkg_list_update || { echo "Packages list update failed"; exit 1; }

    if [ -f "/etc/init.d/netshift" ]; then
        msg "NetShift is already installed. Upgrading..."
    else
        msg "Installing NetShift..."
    fi

    local ext release_tag
    if [ "$PKG_IS_APK" -eq 1 ]; then
        ext="apk"
    else
        ext="ipk"
    fi

    release_tag=$(get_latest_version)

    if [ -n "$release_tag" ]; then
        msg "Latest NetShift release: $release_tag (via jsDelivr CDN)"
        for pkg in netshift luci-app-netshift; do
            if [ "$ext" = "ipk" ]; then
                filename="${pkg}-${release_tag}-r1-all.${ext}"
            else
                filename="${pkg}-${release_tag}-r1.${ext}"
            fi
            
            download_release_asset "${JSDELIVR_CDN}@${release_tag}/${filename}?cdn=raw" "$filename"
        done

        if pkg_is_installed luci-i18n-netshift-ru; then
            filename="luci-i18n-netshift-ru-${release_tag}.${ext}"
            download_release_asset "${JSDELIVR_CDN}@${release_tag}/${filename}?cdn=raw" "$filename"
        fi
    else
        msg "Failed to determine latest version from jsDelivr API"
        exit 1
    fi

    if ! ls "$DOWNLOAD_DIR"/*netshift* >/dev/null 2>&1; then
        msg "No packages were downloaded successfully"
        exit 1
    fi

    for pkg in netshift luci-app-netshift; do
        file=""
        for f in "$DOWNLOAD_DIR"/"$pkg"*; do
            if [ -f "$f" ]; then
                file=$(basename "$f")
                break
            fi
        done
        if [ -n "$file" ]; then
            msg "Installing $file..."
            pkg_install "$DOWNLOAD_DIR/$file"
            sleep 3
        fi
    done

    ru=""
    for f in "$DOWNLOAD_DIR"/luci-i18n-netshift-ru*; do
        if [ -f "$f" ]; then
            ru=$(basename "$f")
            break
        fi
    done
    if [ -n "$ru" ]; then
        if pkg_is_installed luci-i18n-netshift-ru; then
            msg "Upgrading Russian translation..."
            pkg_remove luci-i18n-netshift*
            pkg_install "$DOWNLOAD_DIR/$ru"
        else
            msg "Install Russian translation? y/n"
            read -r -p '' RUS
            case $RUS in
                y|Y)
                    pkg_remove luci-i18n-netshift*
                    pkg_install "$DOWNLOAD_DIR/$ru"
                    ;;
            esac
        fi
    fi

    find "$DOWNLOAD_DIR" -type f -name '*netshift*' -exec rm {} \;
}

check_system() {
    MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || echo "Unknown")
    msg "Router model: $MODEL"

    if podkop_is_installed; then
        migrate_from_podkop
        return
    fi
}

sing_box() {
    if ! pkg_is_installed "^sing-box"; then
        return
    fi
}

main "$@"

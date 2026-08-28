#!/bin/sh
# shellcheck shell=dash

JSDELIVR_API="https://data.jsdelivr.com/v1/packages/gh/yandexru45/netshift"
JSDELIVR_CDN="https://cdn.jsdelivr.net/gh/yandexru45/netshift"
MIRROR_BASE="https://gh.ddlc.top/https://github.com/yandexru45/netshift/releases/download"

DOWNLOAD_DIR="/tmp/netshift"
COUNT=3

PKG_IS_APK=0
command -v apk >/dev/null 2>&1 && PKG_IS_APK=1

rm -rf "$DOWNLOAD_DIR"
mkdir -p "$DOWNLOAD_DIR"

msg() {
    printf "\033[32;1m%s\033[0m\n" "$1"
}

pkg_is_installed() {
    local pkg_name="$1"
    if [ "$PKG_IS_APK" -eq 1 ]; then
        apk list --installed 2>/dev/null | grep -q "$pkg_name"
    else
        opkg list-installed 2>/dev/null | grep -q "$pkg_name"
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

download_file() {
    local url="$1"
    local filepath="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -sL --connect-timeout 5 -m 20 -o "$filepath" "$url"
    else
        wget -qO "$filepath" "$url"
    fi
}

get_latest_version() {
    local raw_json=""
    local ver=""
    
    # 1. Запрос к jsDelivr API
    if command -v curl >/dev/null 2>&1; then
        raw_json=$(curl -sL --connect-timeout 5 -m 10 "$JSDELIVR_API")
    else
        raw_json=$(wget -qO- "$JSDELIVR_API" 2>/dev/null)
    fi

    # Надежный парсинг версии через sed без использования grep
    if [ -n "$raw_json" ]; then
        ver=$(echo "$raw_json" | sed -n 's/.*"latest":"\([^"]*\)".*/\1/p')
    fi

    # 2. Если jsDelivr не вернул версию, берем тег через зеркало gh.ddlc.top
    if [ -z "$ver" ]; then
        local location=""
        if command -v curl >/dev/null 2>&1; then
            location=$(curl -sI --connect-timeout 5 "https://gh.ddlc.top/https://github.com/yandexru45/netshift/releases/latest" | awk -F': ' '/[L|l]ocation/ {print $2}' | tr -d '\r')
        else
            location=$(wget --spider --server-response "https://gh.ddlc.top/https://github.com/yandexru45/netshift/releases/latest" 2>&1 | awk -F': ' '/[L|l]ocation/ {print $2}' | tr -d '\r')
        fi
        
        if [ -n "$location" ]; then
            ver="${location##*/}"
        fi
    fi

    echo "$ver"
}

download_release_asset() {
    local version="$1"
    local filename="$2"
    local filepath="$DOWNLOAD_DIR/$filename"

    local url_jsdelivr="${JSDELIVR_CDN}@${version}/${filename}?cdn=raw"
    local url_mirror="${MIRROR_BASE}/${version}/${filename}"

    attempt=0
    while [ $attempt -lt $COUNT ]; do
        msg "Downloading $filename (attempt $((attempt + 1)))..."
        
        # Попытка через jsDelivr CDN
        download_file "$url_jsdelivr" "$filepath"
        if [ -s "$filepath" ]; then
            msg "$filename downloaded successfully (via jsDelivr)"
            return 0
        fi

        # Попытка через зеркало GitHub
        download_file "$url_mirror" "$filepath"
        if [ -s "$filepath" ]; then
            msg "$filename downloaded successfully (via gh.ddlc.top)"
            return 0
        fi

        rm -f "$filepath"
        attempt=$((attempt + 1))
    done

    msg "Failed to download $filename"
    return 1
}

main() {
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
        msg "Latest NetShift release version: $release_tag"
        
        for pkg in netshift luci-app-netshift; do
            if [ "$ext" = "ipk" ]; then
                filename="${pkg}-${release_tag}-r1-all.${ext}"
            else
                filename="${pkg}-${release_tag}-r1.${ext}"
            fi
            
            download_release_asset "$release_tag" "$filename"
        done

        if pkg_is_installed luci-i18n-netshift-ru; then
            filename="luci-i18n-netshift-ru-${release_tag}.${ext}"
            download_release_asset "$release_tag" "$filename"
        fi
    else
        msg "Failed to determine latest version"
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
            sleep 2
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
        fi
    fi

    find "$DOWNLOAD_DIR" -type f -name '*netshift*' -exec rm {} \;
    msg "NetShift installation finished!"
}

main "$@"

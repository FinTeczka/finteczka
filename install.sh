#!/usr/bin/env bash
# FinTeczka - instalacja i aktualizacja jednym poleceniem (Debian / Ubuntu / kontener LXC, x64 oraz ARM64).
#
# Świeża instalacja albo aktualizacja do najnowszej wersji:
#   curl -fsSL https://raw.githubusercontent.com/finteczka/finteczka/main/install.sh | sudo bash
#
# Konkretna wersja (np. v1.0.0):
#   curl -fsSL https://raw.githubusercontent.com/finteczka/finteczka/main/install.sh | sudo FINTECZKA_VERSION=v1.0.0 bash
#
# Po instalacji dostępne jest polecenie:
#   sudo finteczka-update
set -euo pipefail

REPO="${FINTECZKA_REPO:-finteczka/finteczka}"
VERSION="${FINTECZKA_VERSION:-latest}"

[ "$(id -u)" -eq 0 ] || { echo "Uruchom skrypt jako root (np. przez sudo)." >&2; exit 1; }

case "$(uname -m)" in
  x86_64|amd64)   RID="linux-x64" ;;
  aarch64|arm64)  RID="linux-arm64" ;;
  *)
    echo "Nieobsługiwana architektura: $(uname -m). Obsługiwane: x86_64 (linux-x64) i aarch64 (linux-arm64)." >&2
    exit 1
    ;;
esac

if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1 || ! command -v sha256sum >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl tar coreutils ca-certificates >/dev/null
  else
    echo "Wymagane narzędzia: curl, tar, sha256sum." >&2
    exit 1
  fi
fi

ASSET="finteczka-${RID}.tar.gz"
if [ "$VERSION" = "latest" ]; then
  BASE_URL="https://github.com/${REPO}/releases/latest/download"
else
  BASE_URL="https://github.com/${REPO}/releases/download/${VERSION}"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Pobieram FinTeczkę (${RID}, wersja: ${VERSION}) z ${REPO}..."
curl -fL --retry 3 --retry-delay 2 -o "${TMP}/${ASSET}" "${BASE_URL}/${ASSET}"
curl -fsSL --retry 3 --retry-delay 2 -o "${TMP}/SHA256SUMS" "${BASE_URL}/SHA256SUMS"

echo "Sprawdzam sumę kontrolną SHA-256..."
(
  cd "$TMP"
  grep -E "[[:space:]](\./)?${ASSET}$" SHA256SUMS > SHA256SUMS.one \
    || { echo "Brak wpisu dla ${ASSET} w pliku SHA256SUMS." >&2; exit 1; }
  sha256sum -c SHA256SUMS.one
)

tar -xzf "${TMP}/${ASSET}" -C "$TMP"
PKG_DIR="$(find "$TMP" -maxdepth 2 -name FinTeczka.Web -type f -printf '%h\n' | head -n1)"
[ -n "$PKG_DIR" ] && [ -f "${PKG_DIR}/FinTeczka.Web" ] || { echo "Nieprawidłowa zawartość paczki ${ASSET}." >&2; exit 1; }

if [ -x /opt/finteczka/FinTeczka.Web ]; then
  echo "Wykryto istniejącą instalację - uruchamiam bezpieczną aktualizację (z kopią danych i rollbackiem)..."
  bash "${PKG_DIR}/update.sh"
else
  echo "Instaluję FinTeczkę jako usługę systemową..."
  bash "${PKG_DIR}/install.sh"
fi

# Wygodny skrót do przyszłych aktualizacji: sudo finteczka-update [vX.Y.Z]
cat > /usr/local/bin/finteczka-update <<EOF
#!/usr/bin/env bash
set -euo pipefail
export FINTECZKA_REPO="\${FINTECZKA_REPO:-${REPO}}"
export FINTECZKA_VERSION="\${1:-\${FINTECZKA_VERSION:-latest}}"
curl -fsSL "https://raw.githubusercontent.com/\${FINTECZKA_REPO}/main/install.sh" | bash
EOF
chmod 755 /usr/local/bin/finteczka-update

echo "Wskazówka: kolejne aktualizacje uruchomisz jednym poleceniem: sudo finteczka-update"

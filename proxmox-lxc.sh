#!/usr/bin/env bash
# FinTeczka - automatyczne utworzenie i instalacja kontenera LXC na hoście Proxmox VE.
#
# Uruchom w powłoce hosta Proxmox (jako root):
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/finteczka/finteczka/main/proxmox-lxc.sh)"
#
# Tryb bez pytań (zmienne opcjonalne):
#   UNATTENDED=1 CTID=107 IP=10.1.0.107/24 GW=10.1.0.1 STORAGE=local-lvm BRIDGE=vmbr0 HOSTKEY=1 \
#     bash -c "$(curl -fsSL https://raw.githubusercontent.com/finteczka/finteczka/main/proxmox-lxc.sh)"
set -euo pipefail

REPO="${FINTECZKA_REPO:-finteczka/finteczka}"
VERSION="${FINTECZKA_VERSION:-latest}"
UNATTENDED="${UNATTENDED:-0}"

[ "$(id -u)" -eq 0 ] || { echo "Uruchom skrypt jako root na hoście Proxmox VE." >&2; exit 1; }
command -v pct >/dev/null 2>&1 && command -v pveam >/dev/null 2>&1 && command -v pvesm >/dev/null 2>&1 \
  || { echo "Ten skrypt należy uruchomić na hoście Proxmox VE (brak poleceń pct/pveam/pvesm)." >&2; exit 1; }

# Czytanie odpowiedzi z /dev/tty pozwala działać także przy uruchomieniu przez pipe (curl | bash).
HAS_TTY=0
if [ "$UNATTENDED" != "1" ] && [ -r /dev/tty ] && [ -w /dev/tty ]; then
  HAS_TTY=1
fi

ask() {
  local prompt="$1" default="$2" reply=""
  if [ "$HAS_TTY" -eq 1 ]; then
    printf "%s [%s]: " "$prompt" "$default" >/dev/tty
    IFS= read -r reply </dev/tty || reply=""
  fi
  printf "%s" "${reply:-$default}"
}

ask_yn() {
  local prompt="$1" default="$2" reply=""
  if [ "$HAS_TTY" -eq 1 ]; then
    printf "%s [%s]: " "$prompt" "$default" >/dev/tty
    IFS= read -r reply </dev/tty || reply=""
  fi
  reply="${reply:-$default}"
  case "$reply" in
    t|T|tak|TAK|y|Y|yes|YES|1) return 0 ;;
    *) return 1 ;;
  esac
}

DEFAULT_CTID="${CTID:-$(pvesh get /cluster/nextid 2>/dev/null || echo 107)}"
DEFAULT_HOSTNAME="${HOSTNAME_CT:-finteczka}"
DEFAULT_CORES="${CORES:-2}"
DEFAULT_MEMORY="${MEMORY:-1024}"
DEFAULT_SWAP="${SWAP:-512}"
DEFAULT_DISK="${DISK_GB:-8}"
DEFAULT_BRIDGE="${BRIDGE:-vmbr0}"
DEFAULT_IP="${IP:-dhcp}"
DEFAULT_GW="${GW:-$(ip route 2>/dev/null | awk '/^default/ {print $3; exit}')}"

# Wykrywanie domyślnego magazynu dla dysku kontenera (rootdir) i szablonów (vztmpl).
pick_storage() {
  local content="$1" preferred="$2" list
  list="$(pvesm status --content "$content" 2>/dev/null | awk 'NR>1 && $3=="active" {print $1}')"
  if echo "$list" | grep -qx "$preferred"; then
    echo "$preferred"
  else
    echo "$list" | head -n1
  fi
}

DEFAULT_STORAGE="${STORAGE:-$(pick_storage rootdir local-lvm)}"
DEFAULT_TMPL_STORAGE="${TMPL_STORAGE:-$(pick_storage vztmpl local)}"
[ -n "$DEFAULT_STORAGE" ] || { echo "Nie znaleziono aktywnego magazynu Proxmox z obsługą kontenerów (rootdir)." >&2; exit 1; }
[ -n "$DEFAULT_TMPL_STORAGE" ] || { echo "Nie znaleziono aktywnego magazynu Proxmox na szablony (vztmpl)." >&2; exit 1; }

echo "============================================================"
echo "  FinTeczka - kreator kontenera LXC dla Proxmox VE"
echo "============================================================"
echo "Naciśnij Enter, aby zaakceptować wartości domyślne."
echo ""

CTID="$(ask "Numer kontenera (CTID)" "$DEFAULT_CTID")"
HOSTNAME_CT="$(ask "Nazwa hosta" "$DEFAULT_HOSTNAME")"
STORAGE="$(ask "Magazyn na dysk kontenera" "$DEFAULT_STORAGE")"
TMPL_STORAGE="$(ask "Magazyn na szablon Debiana" "$DEFAULT_TMPL_STORAGE")"
CORES="$(ask "Liczba rdzeni CPU" "$DEFAULT_CORES")"
MEMORY="$(ask "Pamięć RAM (MB)" "$DEFAULT_MEMORY")"
DISK_GB="$(ask "Rozmiar dysku (GB)" "$DEFAULT_DISK")"
BRIDGE="$(ask "Mostek sieciowy" "$DEFAULT_BRIDGE")"
IP="$(ask "Adres IP (dhcp albo np. 10.1.0.107/24)" "$DEFAULT_IP")"
GW_CFG=""
if [ "$IP" != "dhcp" ]; then
  GW="$(ask "Brama domyślna (gateway)" "$DEFAULT_GW")"
  [ -n "$GW" ] && GW_CFG=",gw=${GW}"
fi

SETUP_HOSTKEY=1
if [ "${HOSTKEY:-}" = "0" ]; then
  SETUP_HOSTKEY=0
elif [ "${HOSTKEY:-}" != "1" ]; then
  if ! ask_yn "Utworzyć od razu plik klucza sejfu na hoście (/srv/finteczka-hostkey-${CTID}, zalecane)?" "T"; then
    SETUP_HOSTKEY=0
  fi
fi

if pct status "$CTID" >/dev/null 2>&1; then
  echo "Kontener o numerze ${CTID} już istnieje. Wybierz inny numer." >&2
  exit 1
fi

echo ""
echo "Podsumowanie:"
echo "  CTID:       ${CTID} (${HOSTNAME_CT})"
echo "  Zasoby:     ${CORES} vCPU, ${MEMORY} MB RAM, ${DISK_GB} GB na ${STORAGE}"
echo "  Sieć:       ${BRIDGE}, IP: ${IP}${GW_CFG}"
echo "  Sejf kluczy: $([ "$SETUP_HOSTKEY" -eq 1 ] && echo "tak (/srv/finteczka-hostkey-${CTID})" || echo "nie (można dodać później)")"
echo ""
if [ "$HAS_TTY" -eq 1 ]; then
  ask_yn "Rozpocząć tworzenie kontenera i instalację FinTeczki?" "T" || { echo "Przerwano."; exit 0; }
fi

echo "--> Aktualizuję listę szablonów Proxmox..."
pveam update >/dev/null
TEMPLATE="$(pveam available --section system | awk '{print $2}' | grep '^debian-13-standard' | sort -V | tail -n1 || true)"
if [ -z "$TEMPLATE" ]; then
  TEMPLATE="$(pveam available --section system | awk '{print $2}' | grep '^debian-12-standard' | sort -V | tail -n1 || true)"
fi
[ -n "$TEMPLATE" ] || { echo "Nie znaleziono szablonu debian-13-standard ani debian-12-standard." >&2; exit 1; }

if ! pveam list "$TMPL_STORAGE" 2>/dev/null | awk '{print $1}' | grep -q "/${TEMPLATE}$"; then
  echo "--> Pobieram szablon ${TEMPLATE} do ${TMPL_STORAGE}..."
  pveam download "$TMPL_STORAGE" "$TEMPLATE"
else
  echo "--> Szablon ${TEMPLATE} jest już pobrany."
fi

echo "--> Tworzę nieuprzywilejowany kontener LXC ${CTID}..."
pct create "$CTID" "${TMPL_STORAGE}:vztmpl/${TEMPLATE}" \
  --hostname "$HOSTNAME_CT" \
  --unprivileged 1 \
  --features nesting=1 \
  --cores "$CORES" \
  --memory "$MEMORY" \
  --swap "$DEFAULT_SWAP" \
  --rootfs "${STORAGE}:${DISK_GB}" \
  --net0 "name=eth0,bridge=${BRIDGE},ip=${IP}${GW_CFG}" \
  --timezone Europe/Warsaw \
  --onboot 1

echo "--> Uruchamiam kontener ${CTID}..."
pct start "$CTID"

echo "--> Czekam na gotowość sieci w kontenerze..."
NET_OK=0
for _ in $(seq 1 30); do
  if pct exec "$CTID" -- bash -c 'ip -4 addr show scope global | grep -q "inet "' 2>/dev/null; then
    NET_OK=1
    break
  fi
  sleep 1
done
[ "$NET_OK" -eq 1 ] || { echo "Kontener ${CTID} nie uzyskał adresu IPv4 w ciągu 30 s. Sprawdź ustawienia sieci (${BRIDGE})." >&2; exit 1; }

echo "--> Przygotowuję pakiety bazowe w kontenerze..."
pct exec "$CTID" -- bash -c 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates >/dev/null'

echo "--> Instaluję FinTeczkę wewnątrz kontenera..."
pct exec "$CTID" -- env FINTECZKA_REPO="$REPO" FINTECZKA_VERSION="$VERSION" bash -c \
  'curl -fsSL "https://raw.githubusercontent.com/${FINTECZKA_REPO}/main/install.sh" | bash'

HOSTKEY_DIR="/srv/finteczka-hostkey-${CTID}"
if [ "$SETUP_HOSTKEY" -eq 1 ]; then
  echo "--> Konfiguruję sejf kluczy na hoście (${HOSTKEY_DIR})..."
  U="$(pct exec "$CTID" -- id -u finteczka)"
  G="$(pct exec "$CTID" -- id -g finteczka)"
  mkdir -p "$HOSTKEY_DIR"
  test -e "${HOSTKEY_DIR}/host.key" || openssl rand -out "${HOSTKEY_DIR}/host.key" 32
  chown -R "$((100000 + U)):$((100000 + G))" "$HOSTKEY_DIR"
  chmod 500 "$HOSTKEY_DIR"
  chmod 400 "${HOSTKEY_DIR}/host.key"

  pct set "$CTID" --mp1 "${HOSTKEY_DIR},mp=/etc/finteczka/hostkey,ro=1"
  pct exec "$CTID" -- sed -i 's|^FINTECZKA_Secrets__HostKeyFile=.*|FINTECZKA_Secrets__HostKeyFile=/etc/finteczka/hostkey/host.key|' /etc/finteczka/finteczka.env
  pct exec "$CTID" -- chmod 600 /etc/finteczka/finteczka.env

  echo "--> Restartuję kontener, aby podpiąć punkt montowania mp1 (program sam przeniesie sekrety do sejfu)..."
  pct reboot "$CTID"
  SERVICE_OK=0
  for _ in $(seq 1 30); do
    if pct exec "$CTID" -- systemctl is-active --quiet finteczka 2>/dev/null; then
      SERVICE_OK=1
      break
    fi
    sleep 1
  done
  if [ "$SERVICE_OK" -ne 1 ]; then
    echo "UWAGA: usługa finteczka nie zgłosiła stanu active w ciągu 30 s. Sprawdź dziennik:" >&2
    pct exec "$CTID" -- journalctl -u finteczka -n 30 --no-pager >&2 || true
    exit 1
  fi
fi

CT_IP="$(pct exec "$CTID" -- hostname -I 2>/dev/null | awk '{print $1}')"
echo ""
echo "============================================================"
echo "  FinTeczka została zainstalowana!"
echo "============================================================"
echo "  Adres aplikacji:    http://${CT_IP:-<adres-kontenera>}:8080"
echo "  Kontener LXC:       ${CTID} (${HOSTNAME_CT})"
if [ "$SETUP_HOSTKEY" -eq 1 ]; then
  echo "  Plik klucza sejfu:  ${HOSTKEY_DIR}/host.key (poza kopią kontenera)"
  echo "  Po pierwszym zalogowaniu ustaw hasło odzyskiwania w: Ustawienia -> Sejf kluczy serwera."
fi
echo "  Aktualizacja:       pct exec ${CTID} -- finteczka-update"
echo "  Logi usługi:        pct exec ${CTID} -- journalctl -u finteczka -n 50 --no-pager"
echo "============================================================"

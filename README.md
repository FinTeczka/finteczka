# FinTeczka

**Twoje finanse. Wreszcie czytelnie. Zaszyfrowane dla innych.**

Osobisty monitor finansów na Twoim serwerze: portfel inwestycyjny (akcje, ETF-y, obligacje skarbowe, kryptowaluty), pomocnicze zestawienia do PIT-38 i symulator podatkowy, wydatki z wyciągów bankowych, nieruchomości i media, majątek netto oraz czerwona teczka dla bliskich.

- Strona programu i zrzuty ekranu: **https://finteczka.pl**
- Instrukcja użytkownika: **https://finteczka.pl/instrukcja/**
- Wszystkie wydania i lista zmian: [Releases](https://github.com/finteczka/finteczka/releases)

---

## Szybka instalacja

### 1. Proxmox VE - kontener LXC (zalecane, jedno polecenie na hoście)

Uruchom w powłoce hosta Proxmox jako `root` (tworzy nieuprzywilejowany kontener LXC na Debianie, instaluje FinTeczkę i opcjonalnie konfiguruje plik klucza sejfu poza kopią kontenera):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/finteczka/finteczka/main/proxmox-lxc.sh)"
```

Kolejne aktualizacje z hosta Proxmox:
```bash
pct exec <CTID> -- finteczka-update
```

---

### 2. Debian / Ubuntu / istniejący kontener LXC (x64 oraz ARM64)

Jedno polecenie rozpoznaje architekturę (`linux-x64` lub `linux-arm64`), sprawdza sumę kontrolną SHA-256 i instaluje usługę systemową `finteczka` (port `8080`):

```bash
curl -fsSL https://raw.githubusercontent.com/finteczka/finteczka/main/install.sh | sudo bash
```

Kolejne aktualizacje (z automatyczną kopią danych i przywracaniem poprzedniej wersji w razie błędu):
```bash
sudo finteczka-update
```

---

### 3. Docker / Podman (multi-arch: `linux/amd64`, `linux/arm64`)

```bash
mkdir -p finteczka && cd finteczka
curl -fsSLO https://raw.githubusercontent.com/finteczka/finteczka/main/docker-compose.yml
docker compose up -d
```

Po chwili program działa pod adresem `http://<adres-serwera>:8080`.

Aktualizacja w Dockerze:
```bash
docker compose pull && docker compose up -d
```

---

## Ręczne pobranie paczki

Paczki dla Linuksa (`finteczka-linux-x64.tar.gz`, `finteczka-linux-arm64.tar.gz`) oraz plik sum kontrolnych `SHA256SUMS` znajdziesz na stronie [Releases](https://github.com/finteczka/finteczka/releases/latest).

```bash
tar xzf finteczka-linux-x64.tar.gz
cd finteczka-linux-x64 && sudo ./install.sh
```

Za serwerem pośredniczącym (Caddy, nginx, Traefik) wymagana jest obsługa WebSocketów oraz wpisanie adresu IP proxy w `FINTECZKA_Hosting__TrustedProxies`.

---

## Zgłaszanie błędów i brakujących formatów importu

Znalazłeś błąd albo masz plik z banku/biura maklerskiego, którego FinTeczka jeszcze nie rozpoznaje? Załóż zgłoszenie w zakładce **Issues** (pamiętaj o usunięciu prawdziwych kwot i danych osobowych z przykładowych plików).

## Licencja i zastrzeżenia

Program udostępniany jest w postaci skompilowanej na zasadach licencji do użytku osobistego - szczegóły w [LICENSE.md](LICENSE.md). Wykaz składników osób trzecich znajduje się w [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

FinTeczka nie jest doradztwem inwestycyjnym ani podatkowym - wyliczenia mają charakter pomocniczy, a za decyzje i treść zeznań podatkowych odpowiada użytkownik.

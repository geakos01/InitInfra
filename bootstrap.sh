#!/usr/bin/env bash
#
# InitInfra - belepesi pont egy friss Ubuntu 24.04 gepen.
#
#   curl -fsSL https://raw.githubusercontent.com/geakos01/InitInfra/main/bootstrap.sh | sudo bash
#
# Ujra is futtathato: ha a repo mar ott van, csak frissiti es ujra lefuttatja
# a playbookot. A playbook idempotens, tehat ez nem csinal kart.
#
# Kornyezeti valtozok (mind opcionalis):
#   INITINFRA_REPO   a klonozando repo             (alap: a lenti publikus)
#   INITINFRA_REF    ag vagy cimke                 (alap: main)
#   INITINFRA_DIR    hova kerul a repo             (alap: /opt/initinfra)
#   GITHUB_TOKEN     privat repohoz olvasasi token (alap: nincs)
#   SKIP_VERIFY      1 eseten a zaro ellenorzes kimarad
#
set -euo pipefail

REPO="${INITINFRA_REPO:-https://github.com/geakos01/InitInfra.git}"
REF="${INITINFRA_REF:-main}"
DIR="${INITINFRA_DIR:-/opt/initinfra}"
LEPESEK=6

export DEBIAN_FRONTEND=noninteractive

# --- Kiiratas ---------------------------------------------------------------
lepes() { printf '\n==> [%s/%s] %s\n' "$1" "$LEPESEK" "$2"; }
info()  { printf '    %s\n' "$1"; }
hiba()  { printf '\nHIBA: %s\n' "$1" >&2; exit 1; }

# --- 0. Elofeltetelek -------------------------------------------------------
[ "$(id -u)" -eq 0 ] || hiba "root-kent kell futnia. Igy hivd:
    curl -fsSL <url>/bootstrap.sh | sudo bash"

if [ -r /etc/os-release ]; then
    . /etc/os-release
    if [ "${ID:-}" != "ubuntu" ] || [ "${VERSION_ID:-}" != "24.04" ]; then
        info "FIGYELEM: ez a telepito Ubuntu 24.04-re keszult, itt ${PRETTY_NAME:-ismeretlen} fut."
        info "Folytatom, de szamits ra, hogy valami maskepp viselkedik."
    fi
fi

# --- 1. A cloud-init bevarasa ----------------------------------------------
# Egy frissen inditott felhogepen a cloud-init meg percekig dolgozik, es
# kozben FOGJA az apt zarat. Enelkul a lenti elso apt-get azonnal elhasal:
# "Could not get lock /var/lib/apt/lists/lock". Belefutottunk.
lepes 1 "Varakozas a cloud-init befejezesere"
if command -v cloud-init > /dev/null 2>&1; then
    cloud-init status --wait > /dev/null 2>&1 || true
    info "kesz: $(cloud-init status 2>/dev/null || echo ismeretlen)"
else
    info "nincs cloud-init a gepen, tovabb"
fi

# --- 2. Az apt megkemenyitese ----------------------------------------------
# Ez MEG A TELEPITES ELOTT kell, nem eleg az Ansible-ben. Az apt-nak
# alapertelmezesben NINCS idokorlata: meressel kiderult, hogy egy megakadt
# CDN-kapcsolaton 25 percig "fut" nulla CPU-idovel, visszajelzes nelkul.
#
# Az idokorlat onmagaban NEM ELEG - a kapcsolatok CLOSE-WAIT allapotban
# ragadnak, amire a Timeout nem vonatkozik. A Pipeline-Depth "0" az, ami
# tenylegesen megoldja.
#
# Ugyanezt a fajlt a base szerepkor is kiirja, azonos tartalommal - igy a
# playbook nem fogja "megvaltozott"-nak latni.
lepes 2 "Az apt idokorlatjanak beallitasa"
cat > /etc/apt/apt.conf.d/99-initinfra-halozat <<'KONFIG'
// Az Ansible generalja - kezzel ne szerkeszd.
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
Acquire::ftp::Timeout "30";
Acquire::Retries "3";
// A HTTP pipelining kikapcsolasa. Az idokorlat ONMAGABAN NEM ELEG:
// meressel kiderult, hogy a kapcsolatok CLOSE-WAIT allapotban
// ragadnak (a tuloldal lezarta, az apt varakozik tovabb), amire a
// Timeout nem vonatkozik. Pipelining nelkul az upgrade 5,5 perc alatt
// lefutott a korabbi vegtelen akadas helyett.
Acquire::http::Pipeline-Depth "0";
Acquire::ForceIPv4 "true";
KONFIG
info "/etc/apt/apt.conf.d/99-initinfra-halozat"

# --- 3. Ansible es make -----------------------------------------------------
# A felho-image-en a "git" MAR OTT VAN, a "make" es az "ansible" viszont nincs.
#
# Az "ansible" csomag kell, nem az "ansible-core": a szerepkorok hasznaljak a
# community.general (ufw, timezone) es az ansible.posix (sysctl, mount)
# gyujtemenyeket, amiket csak a nagy csomag hoz magaval.
#
# A DPkg::Lock::Timeout arra jo, ha valami mas (peldaul egy meg futo
# unattended-upgrade) epp fogja a zarat: varunk rea, nem hasalunk el.
lepes 3 "Az ansible, a make es a git telepitese"
APT_OPTS=(-y -o DPkg::Lock::Timeout=300)
apt-get "${APT_OPTS[@]}" update
apt-get "${APT_OPTS[@]}" install ansible make git
info "$(ansible --version | head -1)"

# --- 4. A repo ---------------------------------------------------------------
# A tokent SEHOL nem irjuk a lemezre: nem a remote URL-be kerul, hanem egy
# fejlecbe, amit csak erre a hivasra adunk at. Igy a .git/config tiszta marad,
# es a repo privatta tetele utan sem kell atirni semmit.
lepes 4 "A repo letoltese: $REPO ($REF)"
GIT_AUTH=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
    GIT_AUTH=(-c "http.extraheader=Authorization: Basic $(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 -w0)")
    info "GITHUB_TOKEN hasznalataval"
fi

if [ -d "$DIR/.git" ]; then
    info "mar letezik, frissites"
    git "${GIT_AUTH[@]}" -C "$DIR" fetch --quiet origin "$REF"
    git -C "$DIR" checkout --quiet "$REF"
    git -C "$DIR" reset --quiet --hard "origin/$REF"
else
    mkdir -p "$(dirname "$DIR")"
    git "${GIT_AUTH[@]}" clone --quiet --branch "$REF" "$REPO" "$DIR"
fi
info "$(git -C "$DIR" log -1 --format='%h %s')"

# --- 5. A playbook ----------------------------------------------------------
# Innentol az Ansible dolgozik. Pull modell: a playbook a CELGEPEN fut, nem
# tavolrol - ugyanazon az uton, ahogy a fejlesztes kozben is futtattuk.
lepes 5 "A playbook futtatasa (ez elso alkalommal 15-30 perc)"
make -C "$DIR" dev

# --- 6. Ellenorzes ----------------------------------------------------------
lepes 6 "A gep ellenorzese"
if [ "${SKIP_VERIFY:-0}" = "1" ]; then
    info "kihagyva (SKIP_VERIFY=1)"
else
    make -C "$DIR" verify
fi

cat <<'ZARO'

===========================================================================
 Kesz. A gep all.

 Innen tovabb:
   cd /opt/initinfra && make verify     ellenorzes barmikor
   sudo cat /opt/stack/.env             a generalt jelszavak es tokenek

 Az admin feluletek SZANDEKOSAN csak loopbackon hallgatnak. A gepedrol
 SSH-alaguton keresztul ered el oket:

   ssh -L 8080:127.0.0.1:8080 -L 3000:127.0.0.1:3000 <felhasznalo>@<gep>

   Airflow   http://127.0.0.1:8080
   Grafana   http://127.0.0.1:3000
===========================================================================
ZARO

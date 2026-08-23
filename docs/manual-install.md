# Kézi telepítés — munkanapló

> A ROADMAP 1. fázisának terméke. **Minden parancs itt le van írva úgy, ahogy
> ténylegesen működött**, sorrendben. Ez a fájl az Ansible bemenete: a 2. fázisban
> ezeket fordítjuk szerepkörökre.
>
> Ha valami itt nincs leírva, az nem történt meg. Ha kézzel babráltál a VM-en és
> nem írtad le, dobd el a VM-et és kezdd újra — különben a repó és a gép elválik
> egymástól.

**Célgép:** Ubuntu 24.04.4 LTS, 4 mag / 8 GB / 40 GB, Multipass VM (`infra`).

---

## 0. Kiindulás

Szűz Ubuntu 24.04 szerver, SSH-val elérve. A fejlesztői VM létrehozása:

```bash
multipass launch 24.04 --name infra --cpus 4 --memory 8G --disk 40G
```

> **A VM IP-je minden újraindításkor megváltozik.** Három újraindítás, három cím:
> `172.31.207.195` → `172.31.199.53` → `172.31.197.191` → `172.31.197.103`. A
> `multipass info` ráadásul néha a régi címet is listázza, tehát próbálgatni kellene.
>
> **Ne az IP-t használd, hanem a nevet:** a Hyper-V DNS-e feloldja a
> `<vm-nev>.mshome.net` alakot, és követi a változást:
>
> ```bash
> ssh ubuntu@infra.mshome.net
> ```
>
> Ez fejlesztői kényelem; az éles gépen fix IP vagy valódi DNS-név lesz.

---

## 1. Rendszerfrissítés

```bash
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a

sudo -E apt-get update -qq
sudo -E apt-get upgrade -y -qq
sudo -E apt-get install -y -qq ca-certificates curl gnupg
```

**Miért a két környezeti változó:**

- `DEBIAN_FRONTEND=noninteractive` — nem tesz fel kérdéseket (konfigfájl-ütközés stb.)
- `NEEDRESTART_MODE=a` — az Ubuntu 24.04 `needrestart`-ja különben interaktív listát
  dob fel az újraindítandó szolgáltatásokról, és **megakasztja a telepítést**

Újraindítás szükségességének ellenőrzése:

```bash
[ -f /var/run/reboot-required ] && echo "kell" || echo "nem kell"
```

---

## 2. Docker — a hivatalos repóból

**Nem** az Ubuntu `docker.io` csomagjából: az régebbi, és a `compose` plugin sem jár vele.

```bash
# 2.1 GPG kulcs
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# 2.2 A repo felvétele
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 2.3 Telepítés
sudo -E apt-get update -qq
sudo -E apt-get install -y -qq \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 2.4 A felhasználó a docker csoportba
sudo usermod -aG docker ubuntu
```

**Amit telepített (2026-08-21):**

| | |
|---|---|
| Docker | 29.7.2 |
| Docker Compose | v5.5.0 |
| buildx | v0.36.1 |

A `docker.service` telepítéskor magától `enabled` + `active` lesz, nem kell külön
bekapcsolni.

> **A csoporttagság csak új munkamenetben él.** A `usermod` után a *futó* SSH
> munkamenet még nem látja; lépj ki és vissza, csak utána megy a `docker` `sudo` nélkül.
> Ansible-ben ez `meta: reset_connection`, vagy `become: true` a Docker-taskokon.

Ellenőrzés:

```bash
docker --version && docker compose version
docker run --rm hello-world
```

---

## 3. Gép-higiénia

### 3.1 Időzóna

```bash
sudo timedatectl set-timezone Europe/Budapest
```

> Ansible-ben ez változó legyen (`timezone`), ne bedrótozva.

### 3.2 Swap

4 GB swapfile. Kell, mert a tréning memóriaigénye ingadozik, és swap nélkül az OOM
killer egyszerűen kilövi a folyamatot.

```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab

# Swappiness: inkább a lapcache-t dobja el, mint hogy swapeljen
printf "vm.swappiness=10\n" | sudo tee /etc/sysctl.d/99-swappiness.conf
sudo sysctl -p /etc/sysctl.d/99-swappiness.conf
```

> A méret (`4G`) is változó legyen. A dev VM 8 GB RAM-os, az éles gép akár 32 GB —
> ott más méret indokolt.

Az `/etc/fstab` sor nélkül az újraindítás után nincs swap. **Ellenőrizve: túlélte
az újraindítást.**

### 3.3 Tűzfal

**A sorrend nem mindegy.** Előbb engedélyezd a 22-est, csak utána kapcsold be az
`ufw`-t — különben kizárod magad a gépből.

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment "ssh"
sudo ufw --force enable
```

### 3.4 fail2ban és unattended-upgrades

```bash
sudo -E apt-get install -y -qq fail2ban unattended-upgrades
```

**Ubuntu 24.04-en mindkettő működik alapból, konfiguráció nélkül:**

- `fail2ban` — `active`, az `sshd` jail bekapcsolva
- `unattended-upgrades` — `active`, a `/etc/apt/apt.conf.d/20auto-upgrades` már be van
  állítva (`Update-Package-Lists "1"`, `Unattended-Upgrade "1"`)

> Ettől függetlenül **az Ansible írjon ki explicit `jail.local`-t** (bantime, findtime,
> maxretry). Nem azért, mert most rossz, hanem mert a disztró alapértelmezései verzióról
> verzióra változhatnak — a „szabványosított install" célja épp az, hogy ne a disztró
> döntsön helyettünk.

---

## 4. ⚠ A Docker megkerüli az ufw-t

**Ez a fázis legfontosabb felfedezése, és a tervet is érinti.**

### A probléma

A Docker közvetlenül az iptables `FORWARD` láncába ír, az `ufw` szabályai elé. Ezért
**a publikált konténer-portok akkor is elérhetők kívülről, ha az `ufw` tiltja őket.**

Bizonyítás — `ufw` `deny incoming`, a 8099 sehol nincs engedélyezve:

```bash
docker run -d --name ufwtest -p 8099:80 nginx:alpine
```

| Port | `ufw status` szerint | Valóság kívülről |
|---|---|---|
| 8099 (Docker publikálja) | tiltva | **HTTP 200 — átmegy** |
| 8098 (nincs mögötte semmi) | tiltva | nem elérhető ✅ |

Vagyis az `ufw status` megnyugtató képet mutatna, miközben az admin felületek a világ
felé nyitva állnának. **A terv `publish_web_ui` + `allowed_ips` megoldása így nem
működne.**

### A megoldás: a `DOCKER-USER` lánc

A Docker ezt a láncot **a saját szabályai előtt** dolgozza fel, és sosem írja felül —
ide kell tenni a szűrést.

Két buktató van benne, és mindkettőbe belefutottunk:

**(a) A `--dport` nem a publikált portra illeszkedik.** A `DOCKER-USER` a DNAT *után*
fut, tehát ott már a konténer belső portja (80) látszik, nem a publikált (8099). Ezért
kell a `--ctorigdstport`, ami a conntrack eredeti — DNAT előtti — cél-portjára illeszkedik.

**(b) `--ctdir ORIGINAL` nélkül a konténer válaszát is eldobod.** A conntrack „eredeti
cél-portja" a visszairányú csomagokra is 8099, így a `DROP` a választ is elkapja. A
tünet megtévesztő: az `ACCEPT` szabály számlálója **nő** (a SYN átmegy), a kapcsolat
mégsem jön létre — mert a válasz hal meg.

A működő szabálypár:

```bash
iptables -A DOCKER-USER -p tcp -s <engedélyezett-ip> \
  -m conntrack --ctorigdstport <publikált-port> --ctdir ORIGINAL -j ACCEPT
iptables -A DOCKER-USER -p tcp \
  -m conntrack --ctorigdstport <publikált-port> --ctdir ORIGINAL -j DROP
```

**Ellenőrizve:**

| Forrás | Eredmény |
|---|---|
| Engedélyezett IP | HTTP 200 ✅ |
| Nem engedélyezett IP | blokkolva ✅ |
| SSH (ufw kezeli, nem Docker) | érintetlen ✅ |

### Perzisztencia

Az `iptables -A` nem éli túl az újraindítást. Az `ufw` `after.rules`-ába kell tenni:

```
# BEGIN INITINFRA DOCKER-USER
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -p tcp -s 1.2.3.4 -m conntrack --ctorigdstport 3000 --ctdir ORIGINAL -j ACCEPT
-A DOCKER-USER -p tcp -m conntrack --ctorigdstport 3000 --ctdir ORIGINAL -j DROP
-A DOCKER-USER -j RETURN
COMMIT
# END INITINFRA DOCKER-USER
```

Utána `sudo ufw reload`.

**Ellenőrizve: teljes újraindítás után is élt** — a szabályok megvoltak, a
`--restart unless-stopped` konténer magától visszajött, a kívülről jövő kérés HTTP
200-at kapott.

### Két dolog az Ansible-nek

**A `:DOCKER-USER - [0:0]` sor a kulcs az idempotenciához.** Ez reseteli a láncot
`ufw reload`-kor, így az újragenerált szabályok nem duplázódnak.

**A blokkot mindig ki kell írni, akkor is, ha nincs engedélyezett IP.** Amikor a
blokkot *eltávolítottuk* az `after.rules`-ból és újratöltöttük az `ufw`-t, a szabályok
**bennmaradtak az élő láncban** — mert a resetelő sor is eltűnt velük együtt. Ha a
sablon üres blokkot ír ki (csak a `:DOCKER-USER - [0:0]` és a `RETURN`), a lánc
tisztára áll, és a kikapcsolás is működik.

### Amit ez nem old meg

A loopbackre kötött portokat (`127.0.0.1:3000:3000`) ez nem érinti — azokat a Docker
eleve nem publikálja kifelé, ott nincs mit szűrni. **Az alapértelmezés maradjon ez**;
a `DOCKER-USER` szabályok csak akkor kellenek, ha `publish_web_ui: true`.

---

## 5. PostgreSQL

### 5.1 Könyvtár és titkok

A titkok **a gépen generálódnak, sosem a repóban**:

```bash
sudo mkdir -p /opt/stack/initdb
sudo chown -R ubuntu:ubuntu /opt/stack
```

Az `/opt/stack/.env` tartalma (a jelszavak `openssl rand -hex 24` kimenetei), `chmod 600`:

```
POSTGRES_AIRFLOW_DB=airflow
POSTGRES_AIRFLOW_USER=airflow
POSTGRES_AIRFLOW_PASSWORD=<48 hex karakter>
POSTGRES_APP_DB=app
POSTGRES_APP_USER=app
POSTGRES_APP_PASSWORD=<48 hex karakter>
REDIS_MAXMEMORY=512mb
```

> **`-hex`, nem `-base64`.** A base64 kimenetében van `/`, `+` és `=`; ezek elszállnak
> a `psql` string-literáljában és a compose `${...}` interpolációjában is. A hex csak
> `[0-9a-f]`, tehát mindenhol biztonságos. 24 bájt = 48 karakter, bőven elég.

### 5.2 A compose fájl

```yaml
name: initinfra

services:
  postgres:
    image: postgres:16
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_AIRFLOW_DB}
      POSTGRES_USER: ${POSTGRES_AIRFLOW_USER}
      POSTGRES_PASSWORD: ${POSTGRES_AIRFLOW_PASSWORD}
      APP_DB: ${POSTGRES_APP_DB}
      APP_USER: ${POSTGRES_APP_USER}
      APP_PASSWORD: ${POSTGRES_APP_PASSWORD}
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./initdb:/docker-entrypoint-initdb.d:ro
    ports:
      - "127.0.0.1:5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_AIRFLOW_USER} -d $${POSTGRES_AIRFLOW_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

volumes:
  postgres-data:
```

> **A `$$` a healthcheckben nem elgépelés.** A compose a `${...}`-t saját maga
> behelyettesítené a `.env`-ből; a `$$` azt mondja neki, hogy hagyja békén, és a
> konténeren belüli shell oldja fel futásidőben.

> **Nincs `version:` kulcs.** A modern Compose elavultnak jelöli és figyelmeztet rá.

### 5.3 A második adatbázis

Az image csak egy adatbázist hoz létre (`POSTGRES_DB`). Az alkalmazásét init-szkript
csinálja: `/opt/stack/initdb/10-app-db.sh`, futtathatóra állítva. Tartalma:

```bash
#!/bin/bash
set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER "$APP_USER" WITH PASSWORD '$APP_PASSWORD';
    CREATE DATABASE "$APP_DB" OWNER "$APP_USER";
EOSQL
```

> **Ez CSAK az első indításkor fut le**, üres adatkönyvtár esetén. Ha a volume már
> létezik, a `postgres` image átugorja — mérve: két újraindítás után is pontosan
> egyszer szerepelt a logban. Utólagos séma-változtatásra tehát **nem alkalmas**;
> arra migrációs eszköz kell.

### 5.4 Indítás és ellenőrzés

```bash
cd /opt/stack
docker compose config --quiet     # a fájl érvényes-e
docker compose up -d
docker compose ps                 # (healthy) ~9 mp alatt
```

Ellenőrizve:

| | |
|---|---|
| PostgreSQL verzió | 16.15 |
| `airflow` DB | megvan, tulajdonos `airflow` |
| `app` DB | megvan, tulajdonos `app` |
| Belépés az `app` userrel a saját DB-jébe | működik |
| `127.0.0.1:5432` kívülről | **zárva** (`TcpTestSucceeded: False`) |

> **A loopback-kötés az, ami ténylegesen véd** — nem az `ufw`. A 4. szakasz csapdája
> ide nem ér el, mert a Docker eleve nem publikálja kifelé a portot.

---

## 6. Redis

A compose-hoz hozzáadva:

```yaml
  redis:
    image: redis:7.2
    restart: unless-stopped
    command:
      - redis-server
      - --save
      - ""
      - --appendonly
      - "no"
      - --maxmemory
      - ${REDIS_MAXMEMORY}
      - --maxmemory-policy
      - allkeys-lru
    tmpfs:
      - /data
    ports:
      - "127.0.0.1:6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 10s
```

> **A `command` listás formában kell.** A `--save ""` üres sztringje a stringes
> formában elveszne a shell-feldolgozásban. Listaként a Docker pontosan azt adja át,
> ami ott áll.

> **`tmpfs: /data`, mert a `redis` image `VOLUME /data`-t deklarál.** Enélkül minden
> újralétrehozásnál keletkezik egy névtelen volume. Ráadásul a **Compose átörökíti a
> névtelen volume-ot** a konténer újralétrehozásakor, tehát a `tmpfs` utólagos
> hozzáadása önmagában nem takarítja el — a régi volume ott maradt a konténeren, a
> `tmpfs` csak fölé mountolódott. Ki kell kényszeríteni:
>
> ```bash
> docker compose rm -sfv redis && docker compose up -d redis
> docker volume prune -f
> ```
>
> **`docker compose down -v` SOHA** — az a `postgres-data` named volume-ot is törölné.

A **tényleges futási** konfiguráció ellenőrzése (a terv ezt külön kéri, mert a beírt és
az érvényes érték nem ugyanaz):

```bash
docker compose exec -T redis redis-cli ping                        # PONG
docker compose exec -T redis redis-cli config get maxmemory        # 536870912
docker compose exec -T redis redis-cli config get maxmemory-policy # allkeys-lru
docker compose exec -T redis redis-cli config get appendonly       # no
docker compose exec -T redis redis-cli config get save             # <üres>
```

A `/data` üres marad — nincs RDB és nincs AOF fájl.

---

## Amit az újraindítás-próbák igazoltak

Három teljes `sudo systemctl reboot`, mindegyik után ellenőrizve:

| | |
|---|---|
| swap, időzóna, `ufw`, `fail2ban` | túlélte |
| `DOCKER-USER` szabályok (`after.rules`-ból) | túlélte |
| konténerek (`restart: unless-stopped`) | maguktól visszajöttek, ~19 mp alatt healthy |
| Postgres adat (named volume) | **megmaradt** |
| Redis adat (tmpfs) | **elveszett — ez a tervezett viselkedés (11. döntés)** |
| az `initdb` szkript | **nem futott újra** |
| a VM IP-je | **mindháromszor megváltozott** |

---

## Állapot a fázis végén

```
docker:      29.7.2          compose: v5.5.0
szolgáltatások:
  postgres   healthy   127.0.0.1:5432
  redis      healthy   127.0.0.1:6379
volume-ok:   initinfra_postgres-data   (és semmi más)
ufw:         active    (csak 22/tcp)
fail2ban:    active
swap:        4G        swappiness: 10
időzóna:     Europe/Budapest
DOCKER-USER: üres
```

---

## Nyitott pontok a 2. fázisnak

- A `mem_limit` értékek **változóból** jöjjenek: az éles gép 32 GB, a dev VM 8 GB.
  Bedrótozott limitekkel a VM-en elfogyna a memória.
- A `REDIS_MAXMEMORY`, a swap mérete és az időzóna ugyanígy `group_vars` alapértelmezés.
- A `DOCKER-USER` blokk sablonja **mindig renderelődjön**, akkor is, ha üres.
- A `docker` csoporttagság miatt a Docker-taskok előtt `meta: reset_connection` kell,
  vagy `become: true`.
- Az `initdb` szkript egyszeri természete miatt a séma-változtatásokhoz külön út kell.

---

## Következő lépések (ROADMAP 1. fázis)

- [x] 1. Rendszerfrissítés
- [x] 2. Docker a hivatalos repóból
- [x] 3. Gép-higiénia (`ufw`, `fail2ban`, `unattended-upgrades`, swap, időzóna)
- [x] 4. Minimális `docker-compose.yml` Postgresszel
- [x] 5. Redis
- [ ] 6. Az `app` image: `FROM apache/airflow:3.3.1-python3.12`
- [ ] 7. Airflow négy komponense, LocalExecutorral
- [ ] 8. Prometheus, exporterek, Grafana
- [ ] 9. Jupyter

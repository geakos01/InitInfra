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

## 6. Az `app` image

Ez a közös image: ebből fut az Airflow négy komponense, a Jupyter és a FastAPI végpont
is — így egyetlen Python-környezet van a gépen.

### 6.1 Honnan jött a függőséglista

Nem tippelve: a modellkód **tényleges `import` sorait** gyűjtöttük ki (36 releváns
`.py` fájl), a verziókat pedig a fejlesztői venv `dist-info` mappáiból olvastuk ki.

> **Az `environment.json` nem függőséglista.** A meglévő projektben így hívott fájl a
> titkokat tartalmazza. Ne innen indulj.

A talált külső függőségek három csoportra estek: **mag** (modell + API), **kereső**
(`spacy`, `faiss`, `sentence-transformers`, `bm25s`), **kosár** (`mlxtend`, `fim`).
Az image csak a **magot** viszi; a másik kettő ügyfélspecifikus, azoknak az
`extra_python_packages` változó való.

### 6.2 A döntő kérdés: pandas 2 vagy 3

Az alap image **pandas 3.0.5**-öt hoz, a modellkód viszont **2.3.x**-re íródott. A
pandas 3.0 major váltás (copy-on-write, string dtype), tehát ez nem apróság.

A kérdés eldöntéséhez nem tippeltünk, hanem megnéztük az Airflow **tényleges**
függőségeit a PyPI `requires_dist`-jéből:

```bash
curl -s https://pypi.org/pypi/apache-airflow-core/3.3.1/json
```

**Az `apache-airflow-core` 3.3.1 nem függ a pandastól és a numpytól.** A pandas csak
opcionális extraként szerepel (`apache-airflow-providers-common-sql[pandas]`). Tehát a
visszaléptetés szabad — és mérve is: a pandas 2.3.2-re rontása után az
`airflow version`, az `airflow providers list` és a `pip check` is hibátlan.

Amit viszont **tilos** felülírni, mert az `airflow-core` megköti:

```
sqlalchemy[asyncio] >= 2.0.50     <- a fejlesztői venv 2.0.43-a a minimum ALATT van
fastapi  >= 0.129.0, < 0.137.0
uvicorn  >= 0.37.0
pydantic >= 2.11.0
```

### 6.3 A Dockerfile

```dockerfile
FROM apache/airflow:3.3.1-python3.12

USER airflow

# 1. réteg: torch, CPU-only. Külön rétegben, mert ritkán változik és nagy.
RUN pip install --no-cache-dir       --index-url https://download.pytorch.org/whl/cpu       torch==2.9.0

# 2. réteg: minden más. Ez változik gyakran, ezért van a torch után.
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt
```

> **`--index-url`, nem `--extra-index-url`.** Az `--extra-index-url` mellett a pip a
> PyPI CUDA-s buildjét választaná, ami ~2,5 GB nvidia libet hoz magával — olyan gépre,
> ahol sosem lesz GPU. Az `--index-url` kizárja a PyPI-t; a PyTorch CPU-s indexe a
> torch saját függőségeit is tartalmazza, tehát a feloldás sikerül. Ellenőrizve, hogy
> a `torch-2.9.0+cpu-cp312-cp312-manylinux_2_28_x86_64.whl` létezik.

> **A torch külön rétegben van.** Így a `requirements.txt` módosítása nem építi újra a
> legnagyobb és leglassabb réteget.

### 6.4 Építés és ellenőrzés

```bash
cd /opt/stack/app
docker build -t initinfra/app:dev .
```

> **Az image entrypointja elkapja a parancsokat.** A `docker run ... pip check` az
> Airflow súgóját írja ki, mert az entrypoint `airflow`-nak adja tovább. Használj
> `python -m pip`-et, vagy `--entrypoint`-ot.

Az ellenőrzés eredménye:

| | |
|---|---|
| Image méret | 4,61 GB (az alap 3,21 GB volt) |
| `python -m pip check` | `No broken requirements found` |
| 16 modul együttes importja | mind OK |
| `torch` | **2.9.0+cpu**, `cuda.is_available() == False` |
| `airflow version` | 3.3.1 |
| `airflow providers list` | betöltődik |

A ténylegesen feloldott verziók:

```
pandas 2.3.2      numpy 2.3.3       scikit-learn 1.7.2
torch 2.9.0+cpu   pytorch-lightning 2.5.5   optuna 4.5.0
psycopg2-binary 2.9.10   asyncpg 0.31.0     redis 6.4.0
sqlalchemy 2.0.51 fastapi 0.136.3   uvicorn 0.52.1
pydantic 2.13.4   websockets 16.1.1  APScheduler 3.11.3
```

> **A `websockets` 16.1.1 lett** a fejlesztői venv 15.0.1-e helyett. Ellenőrizve:
> a szerveroldali kód (`logger_api/app.py`) a **FastAPI** `WebSocket`-jét használja,
> nem ezt a könyvtárat — a `websockets` csak kliens-szkriptekben szerepel,
> `connect()`-tel, ami a 16-osban is megvan. Nincs porting-teher.

---

## 7. Az Airflow négy komponense (LocalExecutor)

Kiindulás a hivatalos compose fájl, de három dolog kikerül belőle:

```bash
curl -O https://airflow.apache.org/docs/apache-airflow/3.3.1/docker-compose.yaml
```

| Amit a hivatalos ad | Nálunk |
|---|---|
| `CeleryExecutor` | **`LocalExecutor`** |
| `airflow-worker`, `flower` | **kimarad** — Celery-specifikusak |
| `redis` mint **broker** | a mi Redisünk az **alkalmazásé**; az Airflow nem is látja |

A kész fájl: [`stack/docker-compose.yml`](../stack/docker-compose.yml).

### 7.1 Miért LocalExecutor

Egy gép, egy ügyfél — a Celery horizontális skálázása itt nem hasznosul, cserébe
két konténert és egy broker-függőséget hozna a telepítőbe.

> **Ha valaha Celeryre váltanál: külön broker Redis kell.** A meglévő Redis
> `maxmemory-policy allkeys-lru`-val fut (session cache, eldobható). A
> `maxmemory-policy` viszont **instance-szintű, nem adatbázis-szintű** — hiába
> tennéd a Celeryt `SELECT 1`-be, memórianyomás alatt a Redis kidobhatna egy
> task-üzenetet, és a task csendben elveszne. A Celery brokernek `noeviction` kell.

A tréning OOM-kockázatát `mem_limit` fedi a scheduleren: a taskok a scheduler
gyerekfolyamatai, és a cgroup OOM killer a legnagyobb folyamatot lövi ki — azaz a
tréninget, nem a schedulert.

### 7.2 A titkok

```bash
# Fernet kulcs az image sajat cryptography-javal, nem tippelt formatummal
docker run --rm initinfra/app:dev python -c   "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"

openssl rand -hex 32   # AIRFLOW_JWT_SECRET
openssl rand -hex 12   # admin jelszo
```

> **A `AIRFLOW__API_AUTH__JWT_SECRET` alapértelmezése a hivatalos fájlban
> `airflow_jwt_secret`.** Ezt kötelező felülírni — enélkül bárki, aki ismeri a
> defaultot, érvényes tokent tud gyártani.

### 7.3 A DB migráció és az admin user

Nem kézzel futtatjuk az `airflow db migrate`-et. Az image entrypointja kezeli a
`_AIRFLOW_DB_MIGRATE` és `_AIRFLOW_WWW_USER_CREATE` változókat — ezért hívja az
`airflow-init` explicit a `/entrypoint airflow version`-t. A többi service
`depends_on: airflow-init: condition: service_completed_successfully`.

```bash
cd /opt/stack
docker compose up airflow-init     # egyszer fut le, exit 0
docker compose up -d
```

### 7.4 A modellkód kapcsolati adatai

Ez elsőre kimaradt, és a füst-teszt buktatta ki: a compose csak az `AIRFLOW__*`
változókat adta át, így **a DAG-ok sehogy nem érték volna el a Postgrest**. Az
`x-airflow-common` környezetébe fel kell venni:

```yaml
    POSTGRES_HOST: postgres
    POSTGRES_PORT: '5432'
    POSTGRES_APP_DB: ${POSTGRES_APP_DB}
    POSTGRES_APP_USER: ${POSTGRES_APP_USER}
    POSTGRES_APP_PASSWORD: ${POSTGRES_APP_PASSWORD}
    REDIS_HOST: redis
    REDIS_PORT: '6379'
```

### 7.5 Ellenőrzés

Nem elég, hogy „fut". A [`tests/smoke_test_dag.py`](../tests/smoke_test_dag.py)
végigfuttat egy valódi DAG-ot — nem `airflow dags test`-tel, mert az megkerülné az
executort, hanem igazi triggerrel a scheduleren keresztül.

```bash
cp tests/smoke_test_dag.py /opt/app/dags/
docker compose exec -T airflow-scheduler airflow dags unpause initinfra_smoke_test
docker compose exec -T airflow-scheduler airflow dags trigger initinfra_smoke_test --run-id proba-1
```

Az eredmény a task logjában:

```
KONYVTARAK: torch 2.9.0+cpu (cuda: False), pandas 2.3.2, numpy 2.3.3, sklearn 1.7.2
ADATBAZIS:  PostgreSQL 16.15      <- a task sajat maga csatlakozott
MINDEN RENDBEN
```

Amit ez bizonyít: a task-végrehajtás működik (Task Execution API), a modellkönyvtárak
elérhetők a **task** környezetében (nem csak a shellben), és a task eléri az
alkalmazás adatbázisát.

További ellenőrzések:

| | |
|---|---|
| `/api/v2/monitor/health` | mind a 4 komponens `healthy` |
| `airflow config get-value core executor` | `LocalExecutor` |
| `airflow dags list` | csak a saját DAG — nincsenek példák |
| `/api/v2/dags` hitelesítés nélkül | **401** |
| Bejelentkezés `/auth/token`-nel | JWT megjön, a DAG listázható |
| 8080 kívülről | **zárva** |

> **Két CLI-buktató.** Az `airflow dags list-runs -d <dag>` a 3.3-ban súgót ír ki
> (a `-d` nem az, ami a 2.x-ben volt) — a futás állapotát a `task_instance`
> táblából érdemes nézni. És a `docker compose exec ... pip` az Airflow-nak adja
> tovább a parancsot; `python -m pip` kell.

**Újraindítás-próba:** mind a 6 service magától visszajött, **20 mp alatt healthy**,
és a korábbi futás 3 sikeres task-példánya megmaradt a DB-ben.

---

## 8. Observability

Hét új konténer: Prometheus, Grafana, node-exporter, cAdvisor, és három exporter
(Postgres, Redis, statsd). Konfigurációk: [`stack/prometheus/`](../stack/prometheus/),
[`stack/grafana/`](../stack/grafana/).

### 8.1 Egy hibás verzió a tervben

A hét image közül **egy tag nem létezett**: a DESIGN `cAdvisor v0.60.5`-öt írt a
`gcr.io/cadvisor/cadvisor` alatt. A valóság: a projekt átköltözött a
**`ghcr.io/google/cadvisor`** alá, ahol a legfrissebb **`v0.57.0`**; a régi
regisztrátumban `v0.52.1` a legújabb.

```bash
# Erdemes MINDEN pinnelt taget igy ellenorizni telepites elott
docker manifest inspect ghcr.io/google/cadvisor:v0.57.0
```

### 8.2 Az egyetlen push-út

Minden metrikát a Prometheus **húz**. Egyetlen kivétel az Airflow, ami nem tud
Prometheus-végpontot adni: statsd-n **tol** UDP 9125-re, és a statsd-exporter
fordítja Prometheus-formára a 9102-n.

```yaml
    AIRFLOW__METRICS__STATSD_ON: 'true'
    AIRFLOW__METRICS__STATSD_HOST: statsd-exporter
    AIRFLOW__METRICS__STATSD_PORT: '9125'
    AIRFLOW__METRICS__STATSD_PREFIX: airflow
```

### 8.3 A statsd mapping — ez volt a lépés érdemi munkája

Az Airflow a **dag_id-t és a task_id-t a metrika NEVÉBE ágyazza**:

```
airflow.ti.finish.napi_betoltes.kicsomagolas.success
airflow.dag.napi_betoltes.kicsomagolas.scheduled_duration
airflow.dag_processing.last_duration.dags-folder/smoke_test_dag.py
```

Mapping nélkül minden DAG/task/állapot kombinációra **külön metrikanév** keletkezik.
Ez Prometheusban kezelhetetlen: nem lehet aggregálni, és minden új DAG új neveket szül.
A mapping ezeket címkékké alakítja — a végeredmény
[`stack/prometheus/statsd-mapping.yml`](../stack/prometheus/statsd-mapping.yml), 19 szabállyal.

Négy buktató, mind méréssel derült ki:

> **(a) A glob `*` csak TELJES, pontokkal határolt szegmenst fog meg.** Az
> `airflow.operator_failures_*` szegmensen belüli joker — a statsd-exporter
> `invalid match` hibával **el sem indul**. Ilyenkor `match_type: regex` kell.

> **(b) A regexet YAML-ben APOSZTRÓFFAL kell írni.** Dupla idézőjelben a `\.` érvénytelen
> escape, és a config betöltése elszáll: `found unknown escape character`.

> **(c) A `.py` kiterjesztés extra pont-szegmenst csinál.** A
> `airflow.dag_processing.last_duration.*` glob ezért **nem** fogja meg a
> `...last_duration.dags-folder/smoke_test_dag.py` nevet — regex kell, ami átível a
> pontokon.

> **(d) A kimeneti névből nem lehet visszafejteni a nyerset.** A statsd-exporter a
> pontokból is aláhúzást csinál, így az `airflow_dag_processing_last_run_seconds_ago_X`
> névről nem látszik, hogy a forrás `last_run.seconds_ago.X` volt-e vagy
> `last_run_seconds_ago.X`. Mindkét alakra kellett szabály.

Ezért van egy **általános szabály** is a végén, ami minden jövőbeli
`airflow.dag.<dag>.<task>.<bármi>`-t elkap — hogy ne kelljen minden új Airflow-verziónál
újra vadászni.

**Az ellenőrzés módja számít:** a Prometheus a régi sorozatneveket a retention idejéig
megőrzi, tehát ott a javítás után is látszanának. Közvetlenül az exportert kell kérdezni:

```bash
docker compose exec -T prometheus wget -qO- http://statsd-exporter:9102/metrics   | grep -E "^airflow_" | sed "s/[{ ].*//" | sort -u
```

Végeredmény: **78 `airflow_*` metrikanév, nulla beégetett azonosítóval.**

### 8.4 A `publish_web_ui` élesben

A Grafanán próbáltuk ki, mert ez az egyetlen felület, amit publikálni akarhatsz:

| Beállítás | Kívülről |
|---|---|
| `0.0.0.0:3000`, `DOCKER-USER` szabály **nélkül** | **HTTP 200 — a világ felé nyitva** |
| `0.0.0.0:3000` + `DOCKER-USER` az engedélyezett IP-vel | HTTP 200 ✅ |
| `0.0.0.0:3000` + `DOCKER-USER` **más** IP-vel | blokkolva ✅ |
| `127.0.0.1:3000` (az alapértelmezés) | zárva ✅ |

Az `ufw` egyik esetben sem segített — pontosan ahogy a 4. szakasz leírja.

> **A Hyper-V alhálózat a gazdagép újraindításakor újraosztódik.** Az `allowed_ips`-ba
> írt `172.31.192.1` egyszer csak `172.25.144.1` lett, és a szabály némán elkezdett
> mindent blokkolni. Fejlesztői környezetben ez bosszantó; **éles gépen viszont ez a
> normális működés** — ott az ügyfél fix IP-je szerepel. A tanulság inkább az, hogy egy
> IP-alapú szabály hibája **timeoutként** jelentkezik, nem hibaüzenetként, tehát nehéz
> diagnosztizálni.

### 8.5 Ellenőrzés

```bash
curl -s "http://127.0.0.1:9090/api/v1/targets?state=any"   # 6/6 up
curl -s -u admin:... http://127.0.0.1:3000/api/datasources # Prometheus, default
```

| | |
|---|---|
| Prometheus targetek | **6/6 UP** (node, cadvisor, postgres, redis, airflow, prometheus) |
| `node_memory_MemAvailable_bytes` | 5,97 GB |
| `count(container_last_seen)` | 14 konténer |
| `pg_up` / `redis_up` | 1 / 1 |
| Grafana adatforrás | Prometheus, `isDefault`, `editable: false` |
| Újraindítás után | 13/13 service, **6/6 target UP**, 30 mp |

> **Három exporternek nincs healthcheckje** (`node-exporter`, `postgres-exporter`,
> `redis-exporter`) — az image-ekben nincs `wget`/`curl`. A `docker compose ps` ezért
> csak `Up`-ot mutat náluk, nem `healthy`-t. A tényleges egészségüket a Prometheus
> target-állapota mutatja, ami megbízhatóbb is. A 2. fázisban a verify lépés ezt
> nézze, ne a konténer-státuszt.

---

## 9. Jupyter

Ugyanabból az `app` image-ből fut, mint az Airflow — a notebookok pontosan azokat a
könyvtárakat és verziókat látják, mint a DAG-ok. Nincs külön venv, amit karban kellene
tartani.

### 9.1 A Jupyter nincs benne az alap image-ben

```bash
docker run --rm initinfra/app:dev python -c "import importlib.util as u; print(u.find_spec('jupyterlab'))"
# None
```

Hozzá kell adni a `requirements.txt`-hez. Feloldott verzió: **`jupyterlab==4.6.3`**
(jupyter-server 2.20.0, ipykernel 7.3.0). A `pip check` utána is tiszta, az Airflow 3.3.1
sértetlen. Az image 4,61 → **4,78 GB**.

### 9.2 Az entrypointot felül kell írni

```bash
docker run --rm initinfra/app:dev jupyter --version
# Usage: airflow [-h] GROUP_OR_COMMAND ...
```

Az Airflow image entrypointja **minden parancsot az airflow CLI-nek ad tovább**. Ezért:

```yaml
    entrypoint: ["/bin/bash", "-c"]
    command:
      - >
        jupyter lab --ip=0.0.0.0 --port=8888 --no-browser
        --IdentityProvider.token="${JUPYTER_TOKEN}"
        --ServerApp.root_dir=/opt/notebooks
```

> A token-kapcsoló a JupyterLab 4-ben `--IdentityProvider.token`, nem a régi
> `--NotebookApp.token`.

### 9.3 ⚠ A named volume-ok tulajdonos-csapdája

Ez kétszer is megfogott, és általános szabály lett belőle.

**A Docker csak akkor örökli a tulajdonost az image-ből, ha a könyvtár LÉTEZIK benne.**
Ha nem, `root:root`-ként hozza létre — és az UID 50000-es folyamat nem tud beleírni:

```
PermissionError: [Errno 13] Permission denied: '/home/airflow/.jupyter/migrated'
```

A tünet alattomos: a **szerver elindul és `healthy` lesz**, csak a tényleges munka
(notebook mentése, futtatása) bukik el. A javítás az image-ben van, nem a compose-ban:

```dockerfile
USER root
RUN mkdir -p /home/airflow/.jupyter /opt/notebooks  && chown -R 50000:0 /home/airflow/.jupyter /opt/notebooks
USER airflow
```

> **A `/home/airflow`-ra SOHA ne mountolj volume-ot.** A `pip` oda telepít
> (`/home/airflow/.local/lib/python3.12/site-packages`) — egy volume ott eltüntetné a
> torch-ot és minden mást. Csak alkönyvtárat (`/home/airflow/.jupyter`) szabad.

### 9.4 A modellkód csak olvasható

Első nekifutásra a `/opt/app`-ot írhatóan mountoltam, és a notebook-futtatás
`Permission denied`-del elszállt (a `/opt/app` a hoston UID 1000, a konténer 50000).

A jogosultság javítása helyett a **tervet** javítottuk: a `/opt/app` git-kezelt
könyvtár, amit `git pull` frissít. Ha a Jupyter oda mentene notebookokat, azok
ütköznének a következő pull-lal. Ezért:

```yaml
    volumes:
      - /opt/app:/opt/app:ro      # a modellkod, csak olvasva
      - notebooks:/opt/notebooks  # a munka, kulon named volume-ban
    environment:
      PYTHONPATH: /opt/app        # hogy a modellkod importalhato legyen
```

### 9.5 Ellenőrzés

A szerver futása nem elég — a **kernelt** kell próbára tenni. Egy notebook, amit
`jupyter execute` futtat:

```
torch:  2.9.0+cpu | cuda: False
pandas: 2.3.2 | numpy: 2.3.3
postgres: PostgreSQL 16.15            <- a notebook sajat maga csatlakozott
redis: ok | policy: allkeys-lru       <- irt es olvasott is
KERNEL OK                              hibas cellak: 0
```

| | |
|---|---|
| Token nélkül `/api/contents` | **403** ✅ |
| Rossz tokennel | **403** ✅ |
| 8888 kívülről | **zárva** ✅ |
| `/opt/app` írása a konténerből | tiltva (szándékosan) ✅ |
| `/opt/notebooks` írása | működik ✅ |

> **A 9. döntés itt élesedik:** a Jupyter teljes körű kódfuttatás a gépen, az éles
> adatbázis elérésével. Ezt soha ne tedd ki szélesebb körben, mint a saját címed —
> ha egyáltalán publikálod.

---

## Amit az újraindítás-próbák igazoltak

Hat teljes `sudo systemctl reboot`, mindegyik után ellenőrizve:

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
szolgáltatások: 14 db - postgres, redis, airflow x4, jupyter, prometheus,
             grafana, node-exporter, cadvisor, postgres/redis/statsd-exporter
             minden admin port 127.0.0.1-en
image:       initinfra/app:dev 4.78 GB
image-ek:    initinfra/app:dev (4.61GB), postgres:16, redis:7.2
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
- [x] 6. Az `app` image: `FROM apache/airflow:3.3.1-python3.12`
- [x] 7. Airflow négy komponense, LocalExecutorral
- [x] 8. Prometheus, exporterek, Grafana
- [x] 9. Jupyter

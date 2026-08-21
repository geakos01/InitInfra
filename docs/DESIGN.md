# InitInfra — tervezési dokumentum

> Állapot: **tervezés lezárva**, implementáció még nem kezdődött el.
> Utolsó frissítés: 2026-08-20

## 1. Mi ez

Egy szűz Linux szerverből egyetlen paranccsal működő futtatókörnyezetet csinál.
A telepítés végén a gépen fut és egymással kommunikál:

- **PostgreSQL** — az Airflow metadata DB-je és az alkalmazás adatbázisa
- **Redis** — session history a recommenderhez
- **Airflow** — ütemezés
- **Prometheus + Grafana + exporterek** — metrikák
- **Jupyter** — interaktív munka az éles adaton
- **`app` image** — a modellkód futtatókörnyezete (torch és társai)

## 2. Mi *nem* ez

Ez **nem** dobozos termék és nem multi-tenant sablon. Minden ügyfélnél a modellezés
személyre szabott; ez a repo kizárólag a **telepítést** szabványosítja.

Tudatosan kimarad a v1-ből:

| Kihagyva | Miért |
|---|---|
| Backup | Külön kör lesz; jelenleg nincs ügyféladat a gépeken |
| Alerting (Alertmanager) | Előbb legyen mit riasztani |
| Reverse proxy + TLS (Caddy) | A hozzáférés alapból SSH tunnelen megy; IP-szűrt publikálás kapcsolóval elérhető — lásd #9 |
| Modellkód, DAG-ok | `git pull`-lal kerülnek a gépre, kézzel |
| Tenancy, árazás, termékarchitektúra | Nem ennek a repónak a dolga |

**Ezek ismert hiányok, nem elfelejtett dolgok.** A backup különösen: amint valódi
ügyféladat kerül egy gépre, újra kell nyitni.

## 3. Architektúra

**Minden szolgáltatás konténerben fut.** Egyetlen kezelőfelület, egyetlen logolási hely.

A hoston mindössze két dolog marad, mert ezeket nem lehet konténerbe tenni: **maga a
Docker**, és az **alap gép-higiénia** (ufw, fail2ban, unattended-upgrades, swap,
időzóna). Se Python, se venv, se alkalmazás-szintű systemd unit nincs a gépen.

```
┌──────────────────────── Linux gép ────────────────────────┐
│                                                           │
│  app image (torch + modellkód-függőségek)                 │
│  ├── airflow-apiserver     :8080                          │
│  ├── airflow-scheduler                                    │
│  ├── airflow-dag-processor                                │
│  ├── airflow-triggerer                                    │
│  ├── api (FastAPI)         :8000                          │
│  └── jupyter               :8888                          │
│                                                           │
│  hivatalos image-ek                                       │
│  ├── postgres              :5432                          │
│  ├── redis                 :6379                          │
│  ├── prometheus            :9090                          │
│  ├── grafana               :3000                          │
│  ├── node-exporter         :9100                          │
│  ├── cadvisor              :8081                          │
│  ├── postgres-exporter     :9187                          │
│  ├── redis-exporter        :9121                          │
│  └── statsd-exporter       :9102                          │
│                                                           │
│  /opt/app  ←  git pull ide, bind-mountolva a konténerekbe │
│                                                           │
│  Admin portok: loopback. Az API kifelé nyitható.          │
└───────────────────────────────────────────────────────────┘
```

| Konténer | Image | Port | Szerep |
|---|---|---|---|
| `airflow-apiserver` | `app` (saját build) | 8080 | Airflow webes felület és API |
| `airflow-scheduler` | `app` | — | Ütemezés; itt futnak a taskok |
| `airflow-dag-processor` | `app` | — | A DAG fájlok beolvasása |
| `airflow-triggerer` | `app` | — | Deferrable operátorok |
| `api` | `app` | 8000 | A FastAPI logger végpont (a modellkódból) |
| `jupyter` | `app` | 8888 | Interaktív munka az éles adaton |
| `postgres` | `postgres:16` | 5432 | Airflow metadata és alkalmazás-adatbázis |
| `redis` | `redis:7.2` | 6379 | Session history a recommenderhez |
| `prometheus` | `prom/prometheus:v3.5.5` | 9090 | Metrika-gyűjtés |
| `grafana` | `grafana/grafana:13.1.4` | 3000 | Vizualizáció |
| `node-exporter` | `prom/node-exporter:v1.12.1` | 9100 | Gép CPU/RAM/disk |
| `cadvisor` | `gcr.io/cadvisor/cadvisor:v0.60.5` | 8081 | Konténerenkénti erőforrás-használat |
| `postgres-exporter` | `prometheuscommunity/postgres-exporter:v0.20.1` | 9187 | Adatbázis-metrikák |
| `redis-exporter` | `oliver006/redis_exporter:v1.89.0` | 9121 | Redis-metrikák |
| `statsd-exporter` | `prom/statsd-exporter:v0.29.0` | 9102 | Airflow DAG-metrikák |

**Az admin felületek `127.0.0.1`-re vannak kötve**; kifelé alapból csak a 22-es SSH port
nyitva. **Kivétel az `api`**: azt a webshop kliensei hívják, tehát kifelé nyitható —
lásd lentebb.

A statsd-exporter emellett a `9125/udp`-n fogadja az Airflow metrikáit — ez csak a
konténerek belső hálózatán érhető el, kifelé nincs publikálva.

### Ki kivel beszél

A Postgres és a Redis **szerver**: sosem kezdeményez, csak fogad. A többi kapcsolat
kezdeményező szerint:

| Kezdeményező | Cél | Mit csinál |
|---|---|---|
| `airflow-apiserver` | Postgres | metadata olvasás/írás |
| `airflow-scheduler` | Postgres | ütemezés állapota |
| `airflow-dag-processor` | Postgres | DAG-ok szerializálása |
| `airflow-triggerer` | Postgres | deferred taskok |
| Airflow **task** | `airflow-apiserver` | Task Execution API — a 3.x újdonsága |
| `airflow-scheduler` | `statsd-exporter` (9125/udp) | metrikák küldése |
| `jupyter` | Postgres, Redis | notebookból, kódból |
| `api` | Postgres, Redis | logírás batch-ben, session history, inference |
| **kívülről** (webshop / ügyfél backend) | `api` | websocket, logok beküldése |
| `postgres-exporter` | Postgres | statisztikák |
| `redis-exporter` | Redis | `INFO` |
| `cadvisor` | Docker socket, host `/sys` | konténer-erőforrások |
| `node-exporter` | host `/proc`, `/sys` | hálózat nélkül, csak fájlrendszer |
| `prometheus` | mind az öt exporter + önmaga | scrape |
| `grafana` | **csak** `prometheus` | egyetlen datasource |

Két dolgot érdemes fejben tartani:

- **A Grafana nem beszél az exporterekkel.** Ha egy metrika hiányzik a dashboardból, a
  hibát a Prometheus target-listáján kell keresni, nem a Grafanában.
- **Az Airflow → statsd az egyetlen push-alapú kapcsolat**, minden más pull. Ezért ha
  az Airflow-metrikák hiányoznak, az nem scrape-hiba, hanem a `statsd_on` beállítás.

### A FastAPI végpont

A logger végpont a **modellkód része** (`/opt/app`), nem az InitInfra szolgáltatása —
ügyfelenként más. Ugyanezen a gépen fut, és ugyanahhoz a Postgreshez és Redishez
beszél, mint az Airflow.

A **felügyelete** viszont telepítési kérdés, ezért az InitInfra ad neki egy `api`
service-t a compose-ban, ugyanabból az `app` image-ből. A parancs és a hálózati
láthatóság gépenkénti változó:

```yaml
# group_vars/<gép>.yml
api_enabled: true
api_command: "uvicorn logger_api.app:app --host 0.0.0.0 --port 8000"
api_port: 8000
api_allowed_ips: []            # üres = a világ felé nyitva (frontendről hívják)
# api_allowed_ips: [1.2.3.4]   # csak az ügyfél backend szervere
```

Az `api_allowed_ips` azért változó, mert ügyfelenként más: van, ahol a látogató
böngészője hívja közvetlenül (publikus kell legyen), és van, ahol csak az ügyfél
backend szervere (elég egyetlen IP-t beengedni).

A `restart: unless-stopped` gondoskodik róla, hogy leállás után azonnal újrainduljon —
nem kell hozzá külön figyelő mechanizmus —, a `depends_on` pedig arról, hogy a Postgres
és a Redis előbb legyen kész.

**Kódfrissítés menete:**

```bash
cd /opt/app && git pull
cd /opt/stack && docker compose restart api
```

Rebuild nincs: az image csak a függőségektől változik, a kódtól nem. A restart azért
kell, mert a futó uvicorn már betöltötte a modulokat — ez natív futtatásnál is így
lenne. Ha ezt is meg akarod spórolni, az `api_command`-hoz vehető `--reload`, és akkor
a `git pull` önmagában elég.

A **DAG-oknál még restart sem kell**: a dag-processor magától újraolvassa a fájlokat.

### Miért minden konténerben

Korábban egy hibrid modell szerepelt itt (infra konténerben, Python natívan a hoston).
Azt három dolog buktatta meg:

1. **A natív Airflow telepítése a legtörékenyebb rész.** Constraint fájlos pip install,
   config generálás, `airflow db migrate`, admin user, és négy kézzel írt systemd unit.
   Konténerben ugyanez a hivatalos compose-topológia. Mivel a projekt célja épp egy
   **megbízható telepítő**, nem érdemes a legnehezebb darabot kézzel megírni.
2. **Két kezelőfelület.** A hibridben egyes szolgáltatásokat `systemctl`, másokat
   `docker compose` kezelt volna, két külön logolási hellyel.
3. **Indítási sorrend.** A natív Airflow újraindításkor hamarabb indult volna, mint a
   konténeres Postgres, és hibára futott volna. Konténerben ez egy
   `depends_on: condition: service_healthy` sor.

A hibrid egyetlen valódi előnye — az azonnali, végleges `pip install` a gépen — a
munkamódszered miatt nem számít: lokálisan fejlesztesz, a szerveren csak `git pull` van.

### Az `app` image

Egy saját image tartalmazza a torch-ot és a modellkód összes függőségét. Ezt használja
mind a négy Airflow komponens és a Jupyter is — így a notebook és a DAG **bitre azonos**
környezetben fut.

A **kód nincs benne**: a `/opt/app`-ból bind-mountolva érkezik, ahova te `git pull`-lal
teszed. Ezért a kód szerkesztése nem jár image-újraépítéssel.

Rétegsorrend a Dockerfile-ban: a lassan változó nehéz csomagok (torch) külön rétegben,
a gyorsan változó alkalmazás-függőségek fölötte. Így egy új kis csomag hozzáadása
másodperces rebuild, nem perces.

### Honnan jön a függőséglista

Ez egy valós fogas kérdés: az `app` image-et a **telepítéskor** kell felépíteni, a
modellkód viszont csak **utána** kerül a gépre (`git clone /opt/app`). Ha a
`requirements.txt` csak az ügyfél kódrepójában lenne, a telepítő nem tudná felépíteni
az image-et.

Megoldás: **az alap-függőséglista az InitInfra repóban lakik** (`stack/app/requirements.txt`),
és tartalmazza a közös alapot — Airflow providerek, torch, pandas, numpy, psycopg2,
redis, scikit-learn. Az ügyfélspecifikus extra csomagok is **ide** kerülnek, gépenként,
nem a modellkód repójába. Így a telepítés önmagában teljes, és a `requirements.txt`
ugyanabban a repóban verziózódik, amiben a gép többi beállítása.

### Lokális és szerveroldali környezet egyezése

Mivel lokálisan fejlesztesz és a szerveren futtatsz, a két környezetnek egyeznie kell.
A `requirements.txt` a szerződés a kettő között — az image ebből épül. Ha akarod,
ugyanezt az image-et lokálisan is futtathatod, és akkor a „nálam működik" kategória
teljesen megszűnik; ez viszont már nem ennek a repónak a hatásköre.

## 4. Döntések

| # | Döntés | Eredmény | Indoklás |
|---|---|---|---|
| 1 | Scope | Telepítés szabványosítása | A modellezés ügyfélspecifikus, nem ide tartozik |
| 2 | Futtatási modell | **Minden konténerben** | Egy kezelőfelület; a natív Airflow túl törékeny egy telepítőhöz |
| 3 | Python környezet | Egy közös `app` image | A notebook és a DAG azonos környezetben fut |
| 4 | Modellkód | `/opt/app`-ból bind-mountolva | Szerkesztés nem jár rebuilddel |
| 5 | Függőséglista | Az InitInfra repóban | A telepítő önmagában teljes legyen |
| 6 | Telepítő | Ansible | Idempotens újrafuttatás és sablonozás |
| 7 | Telepítés módja | Pull — `curl \| bash` a gépen | Szűz gép, egy parancs, semmi előkészület |
| 8 | Dev környezet | Eldobható Ubuntu VM | Valódi Linux; a Docker Desktop elrejtené a jogosultsági hibákat |
| 9 | Hozzáférés | Alapból 127.0.0.1 + SSH tunnel; gépenként kapcsolható publikálás IP-szűréssel | Biztonságos alapértelmezés, de nem zárja be a publikálás útját |
| 10 | Perzisztencia | Named volume | A Docker intézi a jogosultságot; backup nélkül a bind mount előnye elesik |
| 11 | Redis | Nincs perzisztencia | A Python újraépíti a session historyt a DB-ből |
| 12 | Executor | LocalExecutor | Egy gép, kevés DAG; a Redis így nem kap broker szerepet |
| 13 | Titkok | A gépen generálva, `.env`-be | A repo titokmentes marad |
| 14 | Extrák | Exporterek és gép-higiénia | Enélkül a Grafana üres, a disk pedig megtelik |
| 15 | Repo | Dev alatt publikus, élesben privát | A bootstrap így a legegyszerűbb |
| 16 | Kód-kihelyezés | Scope-on kívül, `git pull`-lal | Gépenként eltérő |
| 17 | FastAPI végpont | `api` konténer az `app` image-ből | Egyetlen függőségkészlet; szabványos felügyelet, gépenként állítható láthatóság |

### Kiemelendő indoklások

**Redis perzisztencia nélkül (#11)** — ez elsőre hibának néz ki. Nem az: a session
history a Postgresben lévő logokból újraépíthető, és a Python oldal ezt meg is teszi
induláskor. Ezért `save ""`, AOF kikapcsolva, `maxmemory` és `allkeys-lru`.

**LocalExecutor és a nagy tréningek (#12)** — a taskok a scheduler konténerében futnak.
Egy nagy tréning tehát elvben megölheti a schedulert. Első védelem: `mem_limit` a
scheduler service-en, hogy legalább a host és a Postgres ne sérüljön. Ha ez kevés, a
következő lépés a tréning kiemelése `DockerOperator`-ral saját, limitált konténerbe —
ugyanabból az `app` image-ből. A CeleryExecutor csak ezután jön szóba, és akkor a
brokernek **külön Redis instance** kell, mert a jelenlegi `allkeys-lru` mellett
üzenetek veszhetnének el.

**Hozzáférés a webes felületekhez (#9)** — két üzemmód, gépenként választható a
`group_vars`-ból. Az alapértelmezés a biztonságosabb, de a másik nincs elzárva.

**Alapértelmezés — csak loopback, SSH tunnellel:**

```bash
ssh -L 3000:localhost:3000 \
    -L 8080:localhost:8080 \
    -L 8888:localhost:8888 \
    -L 9090:localhost:9090 \
    user@szerver
```

Sorrendben: Grafana, Airflow, Jupyter, Prometheus. Nulla támadási felület, nincs DNS,
nincs tanúsítvány — és bárhonnan működik, telefonról is, SSH klienssel.

**Opcionális — publikálás IP-szűréssel** (`publish_web_ui: true`). Ez a mód a jelenlegi
rendszeredet követi: a szolgáltatások a külső interfészre kötve, saját jelszavas
belépéssel, de az ufw csak a felsorolt címekről engedi be a kapcsolatot:

```yaml
# group_vars/<gép>.yml
publish_web_ui: true
allowed_ips:
  - 1.2.3.4      # iroda
  - 5.6.7.8      # otthon
```

A két mód között a különbség mindössze a compose port-bindingje (`127.0.0.1` helyett
`0.0.0.0`) és néhány ufw szabály — ezért érdemes változónak hagyni, nem eldönteni.

**Ha a publikálást használod, két dologra figyelj:**

- **Titkosítás.** IP-szűrés mellett is a nyílt interneten megy a forgalom. Sima HTTP-n
  a jelszó és a session cookie olvasható. Ilyenkor érdemes a Caddyt is felvenni TLS-ért
  — IP-szűréssel együtt is működik, és a tanúsítvány automatikus.
- **Dinamikus IP.** Ha otthonról nem fix az IP-d, a szabályt frissíteni kell, és több
  gépnél ez halmozódik. Ilyenkor gyakran egyszerűbb a tunnel.

**A Jupytert egyik módban se tedd ki szélesebb körnek, mint a saját címed.** Token-alapú
védelme van, és gyakorlatilag távoli kódfuttatás az éles adat mellett.

## 5. Verziók

Minden pinnelve, `latest` sehol. Ellenőrizve 2026-08-20-án.

| Komponens | Verzió | Megjegyzés |
|---|---|---|
| Ubuntu | 24.04 LTS | 2029-ig támogatott. A 26.04 kijött, de `.1` point release még nincs |
| Airflow | 3.3.1 | 2026-08-12; az `app` image alapja |
| Python | 3.12 | Az `apache/airflow:3.3.1-python3.12` variánsból; a torch ezt biztosan támogatja |
| PostgreSQL | 16 | |
| Redis | 7.2 | A 7.4+ licencváltása (RSALv2/SSPL) miatt |
| Prometheus | v3.5.5 | LTS ág; a legújabb v3.14.0 |
| Grafana | 13.1.4 | |
| node-exporter | v1.12.1 | |
| cAdvisor | v0.60.5 | A 8080 ütközne az Airflow-val, ezért 8081-en |
| postgres-exporter | v0.20.1 | |
| redis-exporter | v1.89.0 | |
| statsd-exporter | v0.29.0 | Az Airflow metrikáihoz |

A Python verziót azért kell explicit pinnelni, mert az `apache/airflow` image több
Python-variánsban jelenik meg, és a torch nem minden verzióhoz ad wheelt egyszerre.

### Airflow 3.x — figyelem

A 3.x **más szolgáltatás-topológia**, mint a 2.x, amin a jelenlegi rendszer fut:

- `webserver` → `api-server`
- a `dag-processor` külön, kötelező komponens
- `execution_date` → `logical_date`, `schedule_interval` → `schedule`
- a taskok a Task Execution API-n keresztül kommunikálnak

A DAG-ok portolásához a `ruff` `AIR3xx` szabálycsoportja nagy részt automatikusan javít.

## 6. A telepítés menete

```bash
ssh root@<szerver-ip>
curl -fsSL https://raw.githubusercontent.com/<user>/InitInfra/main/bootstrap.sh | bash
```

A `bootstrap.sh` mindössze ennyit tesz:

```bash
apt-get update && apt-get install -y ansible git
git clone https://github.com/<user>/InitInfra /opt/initinfra
cd /opt/initinfra
ansible-playbook -i localhost, -c local site.yml
```

Onnantól az Ansible dolgozik helyben. Az utolsó lépés a **verify**, ami ellenőrzi,
hogy a szolgáltatások tényleg élnek és beszélnek egymással.

> **Az első telepítés hosszabb**, jellemzően 10–20 perc, mert az `app` image
> felépítéséhez le kell tölteni a torch-ot (több GB). A későbbi futtatások gyorsak,
> mert a rétegek gyorsítótárazva vannak.

A `bootstrap.sh` opcionális `GITHUB_TOKEN`-t is elfogad, hogy a repo priváttá tétele
után egy sor változtatás legyen, ne átírás.

Telepítés után a modellkód külön kerül fel:

```bash
git clone <ügyfél-repo> /opt/app
cd /opt/stack && docker compose restart
```

Rebuild itt nincs: a kód bind-mountolva van, az `app` image már készen áll.

### Könyvtárak a gépen

Három külön dolog, és fontos nem összekeverni őket:

| Útvonal | Mi | Ki írja |
|---|---|---|
| `/opt/initinfra` | Az InitInfra repo klónja — a playbook forrása | `git pull` |
| `/opt/stack` | A generált futtatókörnyezet: compose fájlok, `.env`, Dockerfile, requirements | **Az Ansible generálja** — kézzel ne szerkeszd |
| `/opt/app` | A modellkód | `git pull` az ügyfél repójából |

A `docker compose` parancsokat mindig a `/opt/stack`-ből futtatod.

**A `/opt/stack` tartalmát a playbook újragenerálja minden futáskor**, tehát az ott
kézzel írt módosítások elvesznek. Ha valamit tartósan változtatni akarsz, azt a
repóban kell — ezért van a függőséglista is változóként, lásd lentebb.

## 7. Fejlesztői kör

### Az installer fejlesztése

Fejlesztés közben **ugyanaz az út, mint élesben**: a kód GitHubon keresztül jut a gépre.

```bash
# a fejlesztőgépen
git commit -am "wip" && git push

# a VM-en
cd /opt/initinfra && git pull && make dev
```

A `make dev` nem másol sehonnan — csak lefuttatja helyben azt, ami már ott van
(`ansible-playbook -i localhost, -c local`).

**Miért nem `rsync`?** Mert a bootstrap élesben is `git pull`-lal szerzi meg a repót.
Ha fejlesztés közben megkerülnénk ezt, pont azt az utat nem tesztelnénk, amit
szállítunk — és a hiba akkor derülne ki, amikor a legdrágább. Cserébe minden
próbához kell egy commit; nyugodtan `wip` üzenettel, a végén összevonva.

> A fejlesztőgépen a WSL2 **nem szükséges**. Eredetileg az `rsync` miatt szerepelt a
> tervben, de az `rsync` kiesett — ráadásul a WSL2 és a Multipass VM külön virtuális
> hálózaton ül, így el sem érik egymást. A VM-hez `ssh` vagy `multipass shell` kell,
> mindkettő megy Git Bashből és PowerShellből is.

**Az arany szabály: a VM eldobható.** Ha valami nem megy, a javítás a repóban történik,
a VM-et pedig eldobod és újra létrehozod (`multipass delete --purge`, vagy Hyper-V
snapshot visszaállítás). Ha kézzel javítasz a VM-en, a végén lesz egy működő géped és
egy nem működő repód — ez a klasszikus bukás sablonépítésnél.

**Amit a VM bizonyít:** hogy a stack feláll. **Amit nem:** valós terhelést, valós
logvolument, és azt, hogy mit bír az inference, miközben a tréning eszi a CPU-t.

### Sorrend: előbb kézzel, aztán Ansible

Ne az Ansible-t tanuld és az installt tervezd egyszerre — az két ismeretlen egyszerre
debuggolva. Előbb SSH-n, kézzel végig kell csinálni a telepítést a VM-en, és leírni a
működő parancsokat. Utána jön a fordítás Ansible-re.

### A modellkód fejlesztése

Lokálisan fejlesztesz, `git push`, a szerveren `git pull`. A kód bind-mountolva van,
tehát a `pull` után nincs teendő. Új függőség esetén viszont igen.

**Kísérletezés a gépen — azonnali, de csak a konténer újralétrehozásáig él:**

```bash
cd /opt/stack && docker compose exec jupyter pip install valami
```

**Véglegesítés — a repóban, nem a gépen.** A `/opt/stack/requirements.txt`-et az
Ansible generálja, tehát ott hiába írnád át: a következő futásnál felülíródna. A
gépenkénti extra csomagok változóként élnek:

```yaml
# group_vars/<gép>.yml
extra_python_packages:
  - valami==1.2.3
```

Majd újra lefuttatod a playbookot, ami újragenerálja a requirements-et, újraépíti az
`app` image-et és újraindítja a konténereket.

Ugyanezt a csomagot a **lokális környezetedbe is** fel kell venni, különben elcsúszik
a két oldal — ez az a hiba, amit a 11. szakasz kockázati táblája is említ.

## 8. Tervezett repo-felépítés

```
InitInfra/
├── bootstrap.sh          ← ezt futtatod a szűz gépen
├── site.yml              ← a fő playbook
├── Makefile              ← make dev / make verify
├── inventory/hosts.yml
├── group_vars/
│   ├── all.yml           ← verziók, portok, közös beállítások
│   └── <gép>.yml         ← gépenkénti: publish_web_ui, extra_python_packages
├── docs/
│   ├── DESIGN.md         ← ez a fájl
│   └── adr/              ← később
└── roles/
    ├── base/             ufw, fail2ban, swap, unattended-upgrades, timezone
    ├── docker/           docker-ce és log rotation (max-size, max-file)
    ├── stack/            compose fájlok, app Dockerfile + requirements.txt, up -d
    └── verify/           ellenőrzések
```

Négy szerepkör — a hibrid modellben hét lett volna. Ez a Docker-döntés közvetlen
haszna: kevesebb Ansible-t kell írnod és tanulnod.

### Építési sorrend

Rétegenként, és **minden réteg végén zöld a verify**, mielőtt tovább:

1. Váz — `git init`, `.gitattributes`, `.gitignore`, inventory, group_vars
2. `base` és `docker`
3. `stack` — Postgres és Redis
4. `stack` — az `app` image és az Airflow négy komponense (ez fog a legtöbbet visszaszólni)
5. `stack` — Prometheus, exporterek, Grafana
6. `stack` — Jupyter

### A verify a „kész" definíciója

Nem érzés, hanem script. Ellenőrzi, hogy:

- a Postgres fogad kapcsolatot, és megvan mindkét adatbázis a megfelelő userekkel
- a Redis válaszol `PONG`-gal, és a policy tényleg `allkeys-lru`
- mind a négy Airflow konténer `healthy`, és az API health endpointja `healthy`
- a Prometheusban **minden target `UP`** — ez fogja ki a legtöbb csendes hibát
- a Grafana datasource feloldódik
- a Jupyter válaszol
- ha `api_enabled`, az `api` konténer fut és a healthcheckje zöld

Ugyanez a script fut majd minden éles gépen telepítés után.

## 9. Windows-specifikus buktatók

A fejlesztés Windowsról megy, a célgép Linux:

- **CRLF** — Windowson szerkesztett `.sh` fájl Linuxon `bad interpreter: /bin/bash^M`
  hibával hal meg. Kell `.gitattributes` `* text=auto eol=lf` beállítással, **még az
  első commit előtt** — utólag már be vannak égetve a rossz sorvégek.
- **Exec bit** — a git Windowson nem kezeli jól a futtatási jogot. Vagy
  `git update-index --chmod=+x`, vagy a scripteket mindig `bash valami.sh` formában hívjuk.
- **Titkok a publikus repóban** — a git history örökre megőrzi. A `.env` a legelső
  committól `.gitignore`-ban. A későbbi priváttá tétel ezen már nem segít.

## 10. Feltételezések

Ezek nincsenek külön megvitatva, de a terv rájuk épül:

- Egy Postgres instance, két adatbázissal (`airflow` és az alkalmazásé), külön userekkel
- A modellkód a `/opt/app`-ba kerül `git pull`-lal, és onnan van bind-mountolva
- A DAG-ok a `/opt/app/dags`-ban laknak, és `/opt/airflow/dags`-ként vannak bemountolva
  (`AIRFLOW__CORE__DAGS_FOLDER`)
- Az Airflow task-logok külön named volume-ban, nem a kód mellett
- Az adatbázis-mentés majd `pg_dump`-pal fog történni, nem volume-másolással

## 11. Ismert kockázatok

| Kockázat | Hatás | Kezelés |
|---|---|---|
| Nagy tréning megöli a scheduler konténert | Áll az ütemezés | `mem_limit`; ha kevés, tréning `DockerOperator`-ral külön konténerbe |
| A tréning elveszi a CPU-t az inference elől | Lassú ajánló végpont | `OMP_NUM_THREADS` és `cpus` limit a tréning konténeren |
| Nincs backup | Diszkhiba = teljes adatvesztés | **Nyitott.** Az első éles ügyfél előtt rendezni kell |
| Nincs alerting | Hétvégi leállás hétfőn derül ki | **Nyitott.** Elfogadott, amíg nincs SLA |
| Az `AIRFLOW_HOME` megváltozik | A meglévő rendszerből átemelt DAG-ok abszolút útvonalai eltörnek (`/home/geakos/airflow` → `/opt/airflow`) | A portoláskor feltérképezni |
| Lokális és szerveroldali környezet elcsúszik | „Nálam működik" | A `requirements.txt` a szerződés; az image ebből épül |
| A torch letöltése lassú vagy elakad | Az első telepítés elhasal | A build külön lépés, újrafuttatható; a réteg cache-elődik |

## 12. Változásnapló

**2026-08-20 — a hibrid modell elvetve.** Az eredeti terv szerint az infrastruktúra
konténerben, a Python világ (venv, Airflow, Jupyter) natívan futott volna a hoston. Ez
azért került be, hogy a gépen közvetlenül lehessen `pip install`-t futtatni.

Elvetve, mert: (a) konténerben is lehet `pip install`-t futtatni, csak nem véglegeset;
(b) a natív Airflow telepítése lett volna a telepítő legtörékenyebb része, négy kézzel
írt systemd unittal; (c) a hibrid két kezelőfelületet és egy indítási sorrend-problémát
hozott volna. A döntő érv: a fejlesztés lokálisan történik, a szerver csak futtat,
tehát a natív venv kényelmi előnye nem érvényesült volna.

**2026-08-20 — a FastAPI végpont bekerült a stackbe.** Eredetileg kimaradt, mert a
modellkód része. A felügyelete viszont telepítési kérdés: kézzel indítva újraindítás
után nem jönne vissza. Először natív systemd unit merült fel, de az visszahozta volna a
második Python környezetet a hostra — ezért `api` konténer lett, ugyanabból az `app`
image-ből. A hálózati láthatósága gépenkénti változó, mert egyes ügyfeleknél a
látogató böngészője hívja, másoknál csak az ügyfél backend szervere.

**2026-08-20 — a webes hozzáférés kapcsolóvá vált.** Eredetileg kizárólag SSH tunnel
szerepelt a tervben. Kiderült, hogy a jelenlegi rendszer publikált felületeket használ
jelszavas belépéssel és ufw IP-szűréssel — ez legitim megoldás. Ezért a publikálás
gépenkénti kapcsoló lett (`publish_web_ui`), az alapértelmezés viszont maradt a
loopback + tunnel.

**2026-08-20 — a függőséglista helye tisztázva.** A Docker-váltás után kiderült, hogy
az `app` image-et a telepítéskor kell felépíteni, a modellkód viszont csak utána kerül
a gépre. Ezért a `requirements.txt` az InitInfra repóba került, nem a modellkód mellé.

**2026-08-21 — az `rsync`-es fejlesztői hurok elvetve, a WSL2 opcionális lett.** A terv
szerint a kód `rsync`-kel került volna a VM-re, és ehhez kellett volna a WSL2 (a Git
Bashben nincs `rsync`). A dev környezet felállításakor kiderült, hogy **a WSL2 el sem
éri a Multipass VM-et**: külön virtuális hálózaton ülnek, az `ssh` timeoutol. Két út
maradt: megjavítani a WSL hálózatát (`networkingMode=mirrored`), vagy elhagyni az
`rsync`-et.

Az `rsync` esett ki, és nem kényszerből: a bootstrap élesben `git pull`-lal szerzi meg
a repót, tehát az `rsync` pont a szállított utat kerülte volna meg. Így minden
fejlesztői iteráció egyben a produkciós út tesztje is. Ára: minden próbához kell egy
commit. A WSL2 telepítve maradhat kényelmi shellnek, de kikerült a dokumentált
munkamenetből.

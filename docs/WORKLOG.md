# InitInfra — munkamenet-napló

> Munkamenet-szintű napló: hol tartunk, mi dőlt el, mi jön. **Nem** commitonkénti —
> azt a git log rögzíti, a tervezési döntések változásait pedig a
> [DESIGN.md](DESIGN.md) 12. szakasza.

---

## Jelenlegi állapot

> Ha új beszélgetésben veszed fel a fonalat, **ez az egyetlen blokk, amit el kell
> olvasni** — plusz a [DESIGN.md](DESIGN.md)-t (mit építünk és miért) és a
> [ROADMAP.md](ROADMAP.md)-t (milyen sorrendben).

**Hol tartunk:** a ROADMAP **0–8. fázisa kész**. Egy szűz Ubuntu 24.04-ből
**egyetlen paranccsal** áll a teljes stack, és ez **két egymást követő friss VM-en**
végigment: 10-11 perc, `ok=56, changed=35`, verify **28/28**, kilépési kód 0.

```bash
curl -fsSL https://raw.githubusercontent.com/geakos01/InitInfra/main/bootstrap.sh | sudo bash
```

**Következő a 9. fázis: az igazi gép.** A Rackforest szerveren ugyanez az egy parancs.
Utána jön az ügyfélkód a `/opt/app`-ba, és ha kell, a felületek publikálása
(`publish_web_ui` + `allowed_ips` a `group_vars/<gép>.yml`-ben).

### A repó

| | |
|---|---|
| `docs/DESIGN.md` | a teljes terv, 17 döntés indoklással + változásnapló |
| `docs/ROADMAP.md` | 10 fázis, fázisonként kész-kritériummal |
| `docs/manual-install.md` | **az 1. fázis terméke** — a kézi telepítés minden parancsa, indoklással |
| `docs/WORKLOG.md` | ez a fájl |
| `bootstrap.sh` | **a publikus belépési pont** — `curl … | sudo bash` egy szűz gépen |
| `site.yml`, `ansible.cfg`, `Makefile` | `make dev`, `make verify`, `make lint`, `make idempotens` |
| `inventory/`, `group_vars/all.yml` | pull modell (`localhost`), minden gépfüggő változó |
| `roles/base/` | apt-megkeményítés, időzóna, swap, ufw, fail2ban, unattended-upgrades |
| `roles/docker/` | Docker a hivatalos repóból + a `DOCKER-USER` blokk |
| `roles/stack/` | az `app` image, Postgres, Redis, Airflow ×4, observability, Jupyter, `api` |
| `roles/verify/` | 29 ellenőrzés; nem változtat semmit, `make verify` indítja |
| `app/`, `stack/` | az 1. fázisban **kézzel bizonyított** referencia-fájlok |
| `tests/` | füst-teszt DAG, minta-végpont, websocket kliens |
| `scripts/setup-dev.sh` | wizard a 0.2–0.4 lépésekhez |

### A fejlesztői környezet

| | |
|---|---|
| Gazdagép | Windows 11, Ryzen 7 5700, 31.8 GB RAM |
| Cél-VM | `infra` (Multipass/Hyper-V) — Ubuntu 24.04.4, 4 mag / 8 GB / 40 GB |
| Hozzáférés | **`ssh ubuntu@infra.mshome.net`** — az IP minden újraindításkor változik, a név nem |
| Kód a VM-re | `git push` → a VM-en `cd /opt/initinfra && git pull && make dev` |
| `.env` (a fejlesztőgépen) | `VM_NAME`, `VM_HOST`, `GH_OWNER` — **gitignore-olt** |
| GitHub | `geakos01/InitInfra`, publikus |

### Mi fut most a VM-en

Mind a 15 szolgáltatás, Ansible-ből: `postgres`, `redis`, `airflow-{apiserver,
scheduler,dag-processor,triggerer}`, `jupyter`, `api`, `prometheus`, `grafana`,
`node-exporter`, `cadvisor`, `postgres-exporter`, `redis-exporter`, `statsd-exporter`.

Kívülről **egyedül a `8000`** (API) érhető el — a hét admin port zárt. 6/6 Prometheus
target UP.

Frissen telepített gépen **14 szolgáltatás** fut: az `api` addig kimarad, amíg az
ügyfél kódja nincs a `/opt/app`-ban. Ilyenkor a verify 28/28, kóddal 29/29.

### Amire figyelni kell

**A projektről:**

- A `/opt/stack` a célgépen **generált** — amit ott kézzel javítasz, elvész
- A dev VM **eldobható**: hiba esetén a repóban javítunk, nem a gépen
- **`docker compose down -v` SOHA** éles gépen: a `postgres-data`-t is törli
- A titkok a gépen keletkeznek (`/opt/stack/.secrets/`), sosem a repóban

**Technikai buktatók, mind méréssel:**

- **A Docker megkerüli az `ufw`-t** — a publikált portokat a `DOCKER-USER` láncban kell
  szűrni, `--ctorigdstport` + `--ctdir ORIGINAL` szabályokkal
- **Az `apt` végtelenül tud várni** — `Pipeline-Depth 0` és `ForceIPv4` nélkül órákig
  „fut" nulla CPU-idővel
- Minden **named volume célkönyvtárát az image-ben** kell létrehozni, helyes
  tulajdonossal — különben `root:root` lesz, és a szolgáltatás `healthy`, de nem működik
- **Chown-pingpong**: ha két rendszer ugyanazt a fájlt húzza, a playbook sosem lesz
  idempotens (a `--diff` mutatja meg)
- A `.env` **szóközös értékeit idézőjelezni** kell
- **A `/home/airflow`-ra soha ne mountolj volume-ot** — a `pip` oda telepít

**A fejlesztőgépről:**

- A Git Bash `grep`-je összeomlik és **csendben üres eredményt ad** — keresésre Pythont
- A `pkill -f <minta>` megeheti a saját munkamenetet, ha a minta a parancssorában is
  szerepel — PID szerint ölj

### A terv egy bekezdésben

Egy szűz Linux gépből egyetlen `curl | bash` paranccsal működő futtatókörnyezetet
csinálunk. **Minden szolgáltatás konténerben** fut; a hoston csak Docker és alap
gép-higiénia van. Egy közös `app` image szolgálja ki az Airflow négy komponensét, a
Jupytert és a FastAPI végpontot. A telepítő **Ansible**, pull modellben — a célgépen
fut, nem távolról. Ubuntu 24.04, minden verzió pinnelve.

**Nyitott, tudatosan:** backup (`pg_dump`), alerting, TLS a publikált felületek előtt,
ADR-ek.

---

## 2026-08-20 — Tervezés lezárva, 0.1 fázis kész

### Mi történt

**A teljes terv megszületett.** 17 döntés, egyesével végiggrillezve. A folyamat során
két nagy irányváltás volt:

1. **Hibrid → minden konténerben.** Eredetileg az infra ment volna konténerbe, a Python
   világ (venv, Airflow, Jupyter) pedig natívan a hostra. Elvetve, mert a natív Airflow
   telepítése lett volna a telepítő legtörékenyebb része, és két kezelőfelületet hozott
   volna. A döntő érv: a fejlesztés lokálisan történik, a szerver csak futtat.
2. **A FastAPI végpont bekerült a stackbe.** Először kimaradt (a modellkód része), majd
   natív systemd unitként merült fel — de az visszahozta volna a második Python
   környezetet. Végül `api` konténer lett, ugyanabból az `app` image-ből.

**0.1 fázis kész:** `git init -b main`, `.gitattributes` (`eol=lf`) az első commit
előtt, `.gitignore`, commitok. A `git ls-files --eol` mindenhol `i/lf w/lf`-et mutat.

**Munkaeszközök beállítva:** WORKLOG szokás, `setup-dev.sh` wizard, és a projekt
engedélylistája. A hangjelzés (Stop hook, `tada.wav`) már korábban is megvolt a
felhasználó globális beállításaiban — nem nyúltunk hozzá.

### Egy megjegyzés az engedélylistáról

A transcript-elemzés kiderítette, hogy a ténylegesen használt read-only parancsokat
(`grep`, `cat`, `ls`, `head`, `tail`, `find`, `wc`, `sed`, és **minden read-only git
alparancs**) a Claude Code eleve auto-allow-olja. Ezért a `.claude/settings.json`-be
csak öt előretekintő szabály került (`multipass info`, `docker compose ps/logs/config`).
Szándékosan **nem** került bele az `ssh`, `rsync`, `ansible-playbook` és a
`docker compose up` — mindegyik vagy távoli kódfuttatás, vagy állapotot módosít.

---

## 2026-08-21 — A fejlesztői környezet áll (0.2–0.4 fázis)

### Mi történt

**Egy hardveres blokkolóba futottunk, mielőtt bármi telepíthető lett volna.** A
`wsl --install -d Ubuntu-24.04` letöltötte a disztrót, de a regisztráció elhasalt
`HCS_E_HYPERV_NOT_INSTALLED` hibával. A vizsgálat kiderítette, hogy nem a Hyper-V
kapcsoló hiányzott, hanem mélyebben volt a baj:

```
HypervisorPresent             : False
VirtualizationFirmwareEnabled : False    <- a gyokerok
```

Az **AMD SVM ki volt kapcsolva a BIOS-ban**. A `VirtualMachinePlatform` hiába
mutatta magát „Enabled"-nek — firmware-támogatás nélkül a hypervisor nem indul el.
Ez azért érdemel feljegyzést, mert a Windows WMI-állapota **félrevezető**: a
funkció „Enabled", miközben használhatatlan.

A feloldás egyetlen újraindítással ment: `Enable-WindowsOptionalFeature ... -NoRestart`
elevált shellből, majd `shutdown /r /fw /t 0` — ez egyenesen a UEFI-be indít újra,
így nem kell a `Del` billentyűt időzíteni.

**Utána minden simán ment:** WSL2 Ubuntu 24.04.4, Multipass 1.16.3 (hyperv backend),
`infra` VM, SSH kulcs, `.env`.

### Két döntés, amit érdemes tudni

**A WSL2 kikerült a munkamenetből.** Telepítés után derült ki, hogy **el sem éri a
Multipass VM-et** — külön virtuális hálózaton ülnek, az `ssh` timeoutol. A WSL azért
volt a tervben, hogy onnan `rsync`-eljünk (a Git Bashben nincs `rsync`). Az `rsync`
helyett a `git push` / `git pull` hurok mellett döntöttünk: ez pontosan az az út,
amit a bootstrap élesben használ, tehát minden iteráció a produkciós utat is teszteli.
A WSL telepítve maradt (systemd bekapcsolva), de semmi nem függ tőle.

**A repo publikus lett, a terv szerint.** Felmerült, hogy maradjon privát a 8. fázisig
(a tokenmentes `curl | bash` teszt az egyetlen, aminek tényleg kell a publikusság),
de a 15. döntés szó szerinti követése mellett döntöttünk. Publikálás előtt a követett
fájlok és a teljes git history át lett fésülve titkokra — tiszta.

---

## 2026-08-21 (folytatás) — 1. fázis, 1–3. lépés

Rendszerfrissítés, Docker a hivatalos repóból, gép-higiénia. Minden parancs a
[manual-install.md](manual-install.md)-ben.

### A fázis hozadéka: a Docker megkerüli az ufw-t

Ez nem apró részlet, hanem **a terv egy hibás feltevése**. A DESIGN úgy fogalmazott,
hogy a `publish_web_ui: true` módban „néhány ufw szabály" korlátozza a hozzáférést az
`allowed_ips` címekre. Méréssel kiderült, hogy ez nem működött volna.

A bizonyítás: `ufw` `deny incoming`, a 8099-es port sehol nem engedélyezve, mégis:

| Port | `ufw` szerint | Kívülről |
|---|---|---|
| 8099 (Docker publikálja) | tiltva | **HTTP 200** |
| 8098 (nincs mögötte semmi) | tiltva | nem elérhető |

Vagyis az `ufw status` megnyugtató képet mutatott volna, miközben az admin felületek a
világ felé nyitva állnak. A megoldás a `DOCKER-USER` lánc; a recept két nem nyilvánvaló
elemet igényel (`--ctorigdstport`, `--ctdir ORIGINAL`), mindkettőt méréssel találtuk meg.
A második különösen alattomos: nélküle az `ACCEPT` szabály számlálója **nő**, a kapcsolat
mégsem jön létre — mert a konténer válaszát dobja el a saját `DROP` szabályunk.

### Két kisebb tanulság

**A VM IP-je újraindításkor megváltozott** (`172.31.207.195` → `172.31.199.53`). A
`multipass info` a régit is listázta, a működőt próbálgatással kellett megtalálni.

**Az `after.rules`-ból eltávolított blokk szabályai bennmaradnak az élő láncban** — mert
a resetelő `:DOCKER-USER - [0:0]` sor is eltűnik velük. Ezért a sablon **mindig** írja ki
a blokkot, üresen is, különben a kikapcsolás nem működik.

---

## 2026-08-21 (2) — Postgres és Redis áll a VM-en (1. fázis, 4–5. lépés)

### Mi történt

A stack első két szolgáltatása fut a `/opt/stack`-ben: **egy Postgres 16, két
adatbázissal** (`airflow` és `app`, külön userekkel, a másodikat `initdb` szkript
hozza létre), és egy **Redis 7.2 perzisztencia nélkül**. Mindkettő `healthy`,
mindkettő `127.0.0.1`-re kötve, a jelszavak a gépen generálva (`openssl rand -hex 24`).

Három teljes újraindítással ellenőrizve: a Postgres adata megmarad, a Redisé eltűnik,
a konténerek maguktól visszajönnek, az `initdb` szkript nem fut újra.

### Három dolog, ami menet közben derült ki

**A VM IP-je minden újraindításkor más.** Négy cím négy indítás alatt. A megoldás nem
az `.env` frissítgetése, hanem a `infra.mshome.net` név — a Hyper-V DNS-e feloldja és
követi a változást. Az `.env`-ben ezért `VM_HOST` lett a mérvadó, a `VM_IP` csak
tájékoztató.

**A Compose átörökíti a névtelen volume-okat.** A `redis` image `VOLUME /data`-t
deklarál, ezért keletkezett egy névtelen volume. Utólag hozzáadtam a `tmpfs: /data`-t,
de a régi volume **ott maradt a konténeren** — a `tmpfs` csak fölé mountolódott, és a
`docker volume prune` sem vitte el, mert használatban volt. `docker compose rm -sfv redis`
kellett hozzá. Az Ansible-nek tudnia kell erről, különben a gépeken csendben gyűlnek a
volume-ok.

**A `-hex` nem stílus kérdése a jelszógenerálásnál.** Az `openssl rand -base64`
kimenetében `/`, `+` és `=` is van; ezek elszállnak a `psql` string-literáljában és a
compose `${...}` interpolációjában is.

---

## 2026-08-23 — Az `app` image és az Airflow (1. fázis, 6–7. lépés)

### Mi történt

Megépült a közös `app` image, és **fut az Airflow**: négy komponens LocalExecutorral,
mind `healthy`, és egy valódi DAG végig is futott rajta — nem `airflow dags test`-tel,
ami megkerülné az executort, hanem igazi triggerrel.

A füst-teszt kimenete a task logjából:

```
KONYVTARAK: torch 2.9.0+cpu (cuda: False), pandas 2.3.2, numpy 2.3.3, sklearn 1.7.2
ADATBAZIS:  PostgreSQL 16.15      <- a task sajat maga csatlakozott
MINDEN RENDBEN
```

Ez azt bizonyítja, ami a terv lényege: **egyetlen image szolgálja ki az Airflow-t és a
modellkódot**, és a taskok elérik az alkalmazás adatbázisát.

### A függőség-kérdés, amit méréssel döntöttünk el

Az alap image pandas **3.0.5**-öt hoz, a modellkód **2.3.x**-re íródott. A pandas 3.0
major váltás, tehát ez nem apróság volt. A PyPI `requires_dist`-je adta meg a választ:
**az `apache-airflow-core` 3.3.1 nem függ a pandastól** — csak opcionális extraként
szerepel. A visszaléptetés után az `airflow version`, a `providers list` és a
`pip check` is hibátlan.

Amit viszont **nem** másoltunk át a fejlesztői venv-ből: az `sqlalchemy 2.0.43`. Az
Airflow minimuma `>= 2.0.50`, tehát a lokális verzió a küszöb alatt van.

### Executor: maradt a LocalExecutor

Felmerült a CeleryExecutor. A tisztázás során kiderült, hogy a valódi akadály nem az,
hogy „az Airflow nem használ Redist" (ma valóban nem) — hanem hogy **a Celery maga
tenné azzá**: a broker a Redis. És mivel a `maxmemory-policy` instance-szintű, a
meglévő, `allkeys-lru`-s Redis brokerként **csendben eldobhatna task-üzeneteket**.
Külön broker Redis kellene hozzá.

A döntés a kevesebb mozgó alkatrész mellett szólt: a telepítőnek ügyfélnél,
felügyelet nélkül kell működnie. A tréning OOM-kockázatát `mem_limit` fedi — a cgroup
OOM killer a legnagyobb folyamatot (a tréninget) lövi ki, nem a schedulert.

### Amit a füst-teszt buktatott ki

A compose csak az `AIRFLOW__*` változókat adta át a konténereknek, így **a DAG-ok
sehogy nem érték volna el a Postgrest**. Enélkül a stack „működőnek" látszott volna,
és az első valódi DAG-nál derült volna ki. Ezért ér a füst-teszt annyit, amennyit.

---

## 2026-08-23 (2) — Observability (1. fázis, 8. lépés)

### Mi történt

Hét új konténer: Prometheus, Grafana, node-exporter, cAdvisor és három exporter.
**6/6 Prometheus target UP**, a Grafana egyetlen adatforrása a Prometheus, minden
admin port loopbackre kötve. Újraindítás után 13/13 service és 6/6 target visszajött
30 másodperc alatt.

### A tervben volt egy hibás verzió

A hét pinnelt image közül **egy tag nem létezett**: a cAdvisor `v0.60.5` a
`gcr.io/cadvisor/cadvisor` alatt. A projekt átköltözött a `ghcr.io/google/cadvisor`
alá, ahol `v0.57.0` a legfrissebb. A DESIGN javítva. A tanulság: a pinnelt tageket
`docker manifest inspect`-tel érdemes ellenőrizni, mielőtt a telepítő nekifut.

### A statsd mapping volt az érdemi munka

Az Airflow a `dag_id`-t és a `task_id`-t a metrika **nevébe** ágyazza. Mapping nélkül
minden DAG/task/állapot kombináció külön metrikanevet szül — Prometheusban
kezelhetetlen. Négy buktató, mind méréssel derült ki:

1. A glob `*` csak **teljes** pont-szegmenst fog meg; szegmensen belüli jokerhez
   `match_type: regex` kell, különben a statsd-exporter **el sem indul**.
2. A regexet YAML-ben **aposztróffal** kell írni — dupla idézőjelben a `\.`
   érvénytelen escape.
3. A DAG-fájlnév `.py` kiterjesztése extra pont-szegmenst csinál, amit a glob nem visz át.
4. A kimeneti névből **nem lehet visszafejteni a nyerset** (a pontból is aláhúzás lesz),
   ezért `last_run.seconds_ago` és `last_run_seconds_ago` alakra is kellett szabály.

Ezért került a végére egy általános szabály, ami a jövőbeli
`airflow.dag.<dag>.<task>.<bármi>`-t is elkapja. Végeredmény: 78 `airflow_*`
metrikanév, **nulla beégetett azonosítóval**.

**Az ellenőrzés módja is tanulság**: a Prometheus a régi sorozatneveket a retention
idejéig megőrzi, tehát ott a javítás után is látszottak volna. Közvetlenül az
exportert kellett kérdezni.

### A publish_web_ui élesben is bizonyítva

A Grafanán próbáltuk ki: publikálva, `DOCKER-USER` szabály nélkül **a világ felé
nyitva** (HTTP 200); a szabállyal az engedélyezett IP-ről 200, másról blokkolva.
Az `ufw` egyik esetben sem segített.

Közben kiderült, hogy **a Hyper-V alhálózat a gazdagép újraindításakor újraosztódik**:
a `172.31.192.1` egyszer csak `172.25.144.1` lett, és a szabály némán mindent
blokkolni kezdett. Éles gépen ez nem probléma (ott fix ügyfél-IP van), de a hibakép
tanulságos: egy rossz IP a szabályban **timeoutként** jelentkezik, nem hibaüzenetként.

---

## 2026-08-23 (3) — Jupyter (1. fázis, 9. lépés)

### Mi történt

A Jupyter ugyanabból az `app` image-ből fut, mint az Airflow. A kernel bizonyítottan
működik: egy `jupyter execute`-tal futtatott notebook importálta a torch-ot, csatlakozott
a Postgreshez és a Redishez, nulla hibás cellával.

A `jupyterlab` nem volt az alap image-ben — hozzáadva, feloldott verzió `4.6.3`.
Az image 4,61 → 4,78 GB.

### A named volume-ok tulajdonos-csapdája — ez kétszer is megfogott

**A Docker csak akkor örökli a tulajdonost az image-ből, ha a könyvtár létezik benne.**
Ha nem, `root:root`-ként hozza létre, és az UID 50000-es folyamat nem tud beleírni.
Előbb a `/home/airflow/.jupyter`-rel, majd a `/opt/notebooks`-szal futottunk bele.

A tünet alattomos: **a szerver elindul és `healthy` lesz**, csak a tényleges munka bukik
el. Ha csak a konténer-státuszt néztük volna, működőnek hittük volna.

Általános szabály lett belőle: minden könyvtárat, amire named volume kerül, **az
image-ben kell létrehozni** a helyes tulajdonossal.

Kapcsolódó tanulság: a **`/home/airflow`-ra soha nem szabad volume-ot mountolni** —
a `pip` oda telepít (`.local/lib/python3.12/site-packages`), egy volume eltüntetné a
torch-ot és minden mást.

### Egy tervezési hiba, amit a hiba javítása helyett a terv javításával oldottunk meg

Elsőre a `/opt/app`-ot írhatóan mountoltam a Jupyterbe, és a notebook-mentés
`Permission denied`-del elszállt (host UID 1000 vs konténer 50000).

A jogosultság megpiszkálása helyett kiderült, hogy **oda nem is szabad írni**: a
`/opt/app` git-kezelt, `git pull` frissíti, és bármi, amit a Jupyter odament, ütközne
a következő pull-lal. Így lett a modellkód **csak olvasható**, a notebookok pedig külön
named volume-ba kerültek, `PYTHONPATH=/opt/app` mellett.

---

## 2026-08-24 — Az 1. fázis lezárva (10. lépés: az `api`)

### Mi történt

Megvan a 15. szolgáltatás, és ezzel **a kézi telepítés teljes**. Egy szűz Ubuntu
24.04-ből eljutottunk oda, hogy minden fut, mindent újraindítás-próbán is átvittünk,
és minden parancs le van írva a `manual-install.md`-ben.

Az `api` a stack egyetlen eleme, ami valóban kifelé néz, és az egyetlen, aminek a
*kódja* nem az InitInfra része. Ezért a portja és a parancsa is változó. A
vezetékezést egy minta-végponttal bizonyítottuk, ami a leírt utat járja: websocket →
típus eldöntése → opcionálisan Redis (session history, 8 napos TTL) → batch Postgres.

### Egy csendes hiba, ami éles gépen fájt volna

Az `API_COMMAND` értékében szóközök vannak. A Docker Compose ezt idézőjelek nélkül is
jól kezeli — **de amint egy shell `source`-olja a `.env`-et**, a bash a második szót
parancsnak nézi:

```
./.env: line 19: logger_api.app:app: command not found
```

A saját ellenőrző parancsaimban bukott ki. Egy operátor-szkriptben ugyanez csendben
rossz dolgot csinálna. A megoldás idézőjel — a Compose lehúzza, a shell megérti.

### A fázis mérlege

Öt olyan dolog derült ki, ami a tervben nem szerepelt, és mindegyik méréssel:

1. **A Docker megkerüli az `ufw`-t** — a publikált portok szűrése a `DOCKER-USER`
   láncban történik, `--ctorigdstport` és `--ctdir ORIGINAL` szabályokkal.
2. **A cAdvisor pinnelt verziója nem létezett** — a projekt regisztrátumot váltott.
3. **Az Airflow a `dag_id`-t a metrikanevekbe ágyazza** — statsd mapping nélkül
   kezelhetetlen metrikarobbanás. 19 szabály lett belőle.
4. **A named volume-ok tulajdonosa** `root:root`, ha a könyvtár nem létezik az
   image-ben — és a tünet félrevezető: a szolgáltatás `healthy` lesz, csak a munka bukik.
5. **A `.env` szóközös értékeit idézőjelezni kell**, különben a `source` elhasal.

A közös bennük, hogy egyik sem látszott volna abból, hogy „elindult a konténer". Ezért
futott minden lépés végén valódi terhelés: DAG-trigger, notebook-végrehajtás,
websocket-forgalom.

---

## 2026-08-24 — A 2. fázis kész: Ansible váz, `base` és `docker`

### Mi történt

Megszületett az Ansible váz (`ansible.cfg`, `site.yml`, `inventory`, `group_vars`,
`Makefile`) és az első két szerepkör. **Friss VM-en, nulláról lefutott**
(`ok=27, changed=18, failed=0`), a második futás pedig `changed=0` — ez a fázis
tényleges kritériuma.

A VM-et szándékosan eldobtuk és újraépítettük. Megérte: a kézzel beállított gépen
minden `ok`-ot írt volna, és **három valódi hiba maradt volna rejtve**.

### Amit csak a nulláról-próba talált meg

**1. A `cloud-init` fogja az apt zárat.** Percekig fut egy friss gépen, és az első
`apt-get` azonnal elhasal: `Could not get lock`. A bootstrapnek `cloud-init status
--wait`-tel kell kezdenie.

**2. Az `apt`-nak nincs időkorlátja.** Az `apt-get upgrade` **25 percig „futott" nulla
CPU-idővel** — egy meg nem érkező HTTP-válaszra várt. Alapértelmezésben ez örökre így
maradt volna, visszajelzés nélkül.

**3. Az időkorlát önmagában nem elég** — és ez a legtanulságosabb. A javításom
*helyesnek látszott*: az `apt-config dump` visszaigazolta, hogy a `Timeout 30`
érvényben van. Mégis megint megakadt. A `ss -tnp` mutatta meg, miért: a kapcsolatok
**`CLOSE-WAIT` állapotban ragadtak** — a túloldal lezárta, az apt várt tovább —, amire
az olvasási időkorlát nem vonatkozik.

A megoldás a HTTP pipelining kikapcsolása. Ráadásul kiderült, hogy ezen a gépen
**az IPv6 hirdetve van, de nem működik** (`curl -6` azonnal elhasal, `curl -4` megy) —
bérelt szervereken ez a kombináció egyáltalán nem ritka. `Pipeline-Depth 0` és
`ForceIPv4` mellett az upgrade 329 mp alatt lefutott, exit 0.

### Egy saját hiba, ami tanulságos

A beragadt folyamatot `pkill -f "apt/methods"`-szal próbáltam megölni — és **a saját
ssh-munkamenetemet lőttem le**, mert a minta szerepelt a parancssoromban is.
Hibaelhárító szkriptekben PID szerint kell ölni, nem minta szerint. Ugyanez a
`pgrep`-nél is félrevezetett: „fut az apt-get" jelzést adott, miközben csak önmagára
illeszkedett.

### A Makefile-ról

Az első változat awk `printf`-jében `` és `
` szerepelt. Ezek írás közben valódi
vezérlőkarakterré alakultak, a beágyazott újsor pedig kettétörte a receptet:
`missing separator`. A színezés nem éri meg ezt a törékenységet — a `help` most
`sed` + `column` párossal áll elő, escape nélkül.

---

## 2026-08-25 — A 3. fázis kész: `stack` szerepkör, Postgres és Redis

### Mi történt

A `stack` szerepkör felépíti a `/opt/stack`-et: `.env`, `docker-compose.yml`,
initdb-szkript, majd elindítja a Postgrest és a Redist. A fázis kritériuma teljesült —
mindkét adatbázis megvan a saját userével, a Redis `PONG`-gal válaszol, és a policy
**tényleg** `allkeys-lru`. A teljes playbook `ok=34, changed=0`.

### A titkok idempotenciája volt az igazi feladat

Ha minden futás új jelszót generálna, a meglévő adatbázis elérhetetlenné válna. Az
első megoldásom a `.env` visszaolvasásával próbálkozott Jinja-szűrőkön keresztül — és
**csendben nem működött**: a YAML behajtogatott blokkjában a `'
'` nem újsor, hanem
két karakter, ezért a `split` nem darabolt semmit. A jelszavak minden futásnál újra
keletkeztek.

Ez a fajta hiba a legveszélyesebb: a playbook *lefutott*, `failed=0`-t írt, és csak a
`changed=2` árulta el, hogy valami nem stimmel. Éles gépen a második futás tette volna
tönkre az adatbázis-hozzáférést.

A megoldás az `ansible.builtin.password` lookup, ami eleve erre való: ha a fájl
létezik, visszaolvassa; ha nem, generál. Fontos részlet, hogy a lookup a **vezérlő**
gépen fut — pull modellben ugyanaz a gép, de nem rootként, hanem az ansible-t futtató
felhasználóként, ezért a könyvtárat előre létre kell hozni az ő tulajdonában.

### Egy jogosultsági döntés

A `.env`-et először `root:root 0600`-ra tettem. Emiatt a `docker compose ps` is csak
`sudo`-val ment, mert a Compose olvassa a `.env`-et — ez az operátornak
elfogadhatatlan súrlódás.

A csoport `docker` lett, `0640`-nel. Ez **nem gyengít semmit**: a `docker` csoport
tagsága amúgy is root-egyenértékű, hiszen bárki, aki tagja, be tudja mountolni a `/`-t
egy konténerbe.

---

## 2026-08-25 (2) — A 4. fázis kész: `app` image és Airflow Ansible-ből

### Mi történt

A roadmap szerint ez volt „a legnehezebb rész" — de a nehezét az 1. fázisban már
megoldottuk, így itt tényleg fordítás volt. Az `app` image a `stack` szerepkörből
épül, a Dockerfile sablon lett (az alap image és a torch verziója `group_vars`-ból
jön), és az Airflow négy komponense a compose sablonba került.

A bizonyíték nem az, hogy „elindult": egy valódi DAG **végigfutott** az Ansible által
épített stacken, 3/3 sikeres taskkal, és a task saját maga csatlakozott a Postgreshez.

### Két idempotencia-csapda

**Az image-építés.** Ha egyszerűen `docker build`-et futtatnánk minden körben, az
mindig `changed`-et írna. A megoldás két lépés: előbb `docker image inspect`
(`changed_when: false`), és a build csak akkor fut, ha az image nincs meg. A
forrásfájlok változását külön handler kapja el.

**Chown-pingpong.** A `/opt/stack/config` és `/opt/stack/plugins` könyvtárat az
Ansible `ubuntu:ubuntu`-ra állította, az `airflow-init` konténer viszont minden
induláskor visszaírta `50000:0`-ra. Így **minden futás `changed=1` lett volna, örökre** —
két rendszer húzta egymás ellen ugyanazt a fájlt. A javítás: az Ansible eleve azt a
tulajdonost állítsa be, amit az Airflow vár.

Ez utóbbi jó példa arra, miért nem elég a „lefutott hibátlanul" mérce. A playbook
`failed=0`-t írt, minden szolgáltatás `healthy` volt — a hiba csak a `--diff`
kimenetéből derült ki.

---

## 2026-08-25 (3) — Az 5. és 6. fázis kész: a teljes stack Ansible-ből

### Mi történt

Observability (Prometheus, Grafana, öt exporter), majd Jupyter és az `api`. Ezzel
**mind a 15 szolgáltatás Ansible-ből épül**, a teljes playbook `ok=43, changed=0`.

Az ellenőrzés nem állt meg a konténer-státusznál:

| | |
|---|---|
| Prometheus | 6/6 target UP, 152 Airflow-metrika |
| statsd mapping | 55 metrikanév, **0 beégetett azonosítóval** |
| Jupyter | 403 token nélkül, 200 tokennel |
| API kívülről | `postgres:true, redis:true` |
| Websocket | 5 üzenet → 3 Redisbe, 5 sor Postgresbe |
| Admin portok (7) | mind zárt kívülről |

### Amit menet közben bekötöttünk

A `DOCKER-USER` lánc eddig **mindig üres volt**: a `docker_user_rules` változó
sosem töltődött fel, tehát a tervben leírt IP-szűrés papíron létezett, de nem lépett
volna működésbe. Mostantól a `publish_web_ui` + `allowed_ips` és az `api_allowed_ips`
változókból áll elő.

### A 4. fázis chown-pingpongja itt is visszaköszönt

A Jupyternél ugyanaz a csapda: a named volume célkönyvtárát (`/opt/notebooks`,
`/home/airflow/.jupyter`) **az image-ben kell létrehozni** a helyes tulajdonossal,
különben a Docker `root:root`-ként csinálja meg, és a konténer nem tud beleírni. Ez a
Dockerfile sablonjába került, `{{ airflow_uid }}`-vel.

---

## 2026-08-25 — A 7. fázis kész: `bootstrap.sh` és `make verify`

### Mi történt

Két dolog született meg, és mindkettő méréssel van alátámasztva.

**A `verify` szerepkör: 29 ellenőrzés, egyetlen parancsban.** Nem változtat semmit,
és nem áll meg az első hibánál — mindegyik ellenőrzés lefut, a végén pedig egyben
látszik, mi rossz. Egy első hibánál eldobó ellenőrzés csak a *legelső* problémát
mutatná meg, a többit elrejtené.

A szerkezete szándékosan adat, nem kód: a `roles/verify/vars/main.yml` egy lista,
minden eleme egy név + egy héjparancs. **A parancsok kilépési kódja dönt** — nincs
kimenet-elemzés, nincs reguláris kifejezésekbe rejtett logika. Új szolgáltatás a
stackben = egy új sor a listában.

Az ellenőrzések nem elméletiek: mindegyik parancs **kézzel le lett futtatva a VM-en**,
mielőtt a listába került. Ezt fedik le:

| Terület | Amit néz |
|---|---|
| Gép | időzóna, swap, swappiness, apt-időkorlát, automatikus frissítés |
| Tűzfal | ufw aktív, SSH engedve, fail2ban él, `DOCKER-USER` lánc, **admin portok csak loopbackon** |
| Docker | daemon fut, a felhasználók a `docker` csoportban, **minden szolgáltatás fut és egészséges** |
| Adatok | mindkét Postgres-adatbázis fogad kapcsolatot, Redis `PONG` + `allkeys-lru` + `appendonly no` |
| Airflow | mind a négy komponens `healthy`, a felület válaszol, nincs DAG import hiba |
| Megfigyelés | **minden Prometheus target UP**, Grafana + adatforrás, statsd-metrikák érkeznek |
| Jupyter, API | token nélkül 403 / tokennel 200, az API portja hallgat |

**A `bootstrap.sh`: a publikus belépési pont.** Hat lépés, `curl … | sudo bash`.
Mindegyik lépése egy olyan hibából származik, amibe a 2. fázisban ténylegesen
belefutottunk: megvárja a `cloud-init`-et (különben az apt zár foglalt), **a telepítés
előtt** írja ki az apt-időkorlátot (a `Pipeline-Depth 0` nélkül az apt órákig „fut"
nulla CPU-idővel), telepíti az `ansible`-t és a `make`-et (a `git` már ott van a
felhő-image-en), klónoz, futtat, majd ellenőriz.

A `GITHUB_TOKEN` **nem kerül a lemezre**: nem a remote URL-be íródik, hanem egy
`http.extraheader`-be, amit csak az adott hívás kap meg. Így a repo priváttá tétele
után sem kell átírni semmit, és a `.git/config` tiszta marad.

### Egy ellenőrzés, ami sosem bukik, semmit nem ér

Ezért a `verify`-t **mindkét irányban** kipróbáltuk. Megállítottuk a
`redis-exporter`-t, és a jelentés pontosan ezt írta:

```
[ HIBA ] Docker: minden szolgaltatas fut es egeszseges   -> rc=1 redis-exporter=exited/-
[ HIBA ] Prometheus: minden target UP                    -> rc=1 redis=down
27 / 29 ellenorzes rendben.
```

Két különböző ellenőrzés fogta meg ugyanazt a hibát, két különböző oldalról — és a
`make` nem nulla kilépési kóddal állt le. Indítás után újra 29/29.

### A titkok tulajdonosa: egy csendes csapda a bootstrapben

A jelszavakat a `password` lookup állítja elő, ami a **vezérlő gépen** fut — vagyis az
`ansible`-t indító felhasználó nevében. Fejlesztés közben ez az `ubuntu`, a
bootstrapben viszont **root**. Egy root-ként létrehozott `0600`-as fájlt az `ubuntu`
később már nem tudna visszaolvasni: a következő `make dev` `Permission denied`-del állt
volna meg — egy olyan gépen, ahol addig minden működött.

A javítás egy záró lépés a `secrets.yml`-ben, ami minden futás végén egységesíti a
tulajdonost. Így mindegy, milyen sorrendben fut a kettő. Ellenőrizve: `sudo make dev`
után `make dev` ugyanúgy `ok=45, changed=0`, és fordítva is.

### Mérleg

| | |
|---|---|
| `make verify` | 29/29 zöld, hibás gépen pirosra vált és megnevezi a hibást |
| Playbook | `ok=45, changed=0` — root-ként és `ubuntu`-ként is |
| `bootstrap.sh` | a meglévő gépen végigfutott, a záró verify zöld |

Amit a bootstrap **még nem** bizonyított: hogy egy szűz gépen is végigmegy. Az a
8. fázis, és az az igazi teszt.

---

## 2026-08-25 (2) — A 8. fázis kész: nulláról, hat friss VM-en

### Mi történt

Hat friss VM, mindegyiken **egyetlen parancs**, semmi kézi beavatkozás:

```bash
curl -fsSL https://raw.githubusercontent.com/geakos01/InitInfra/main/bootstrap.sh | sudo bash
```

A végleges kód **két egymást követő szűz gépen** ment végig hibátlanul:

| | 1. kör | 2. kör |
|---|---|---|
| Idő | 11 perc 21 mp | 9 perc 51 mp |
| Playbook | `ok=56, changed=35` | `ok=56, changed=35` |
| Verify | 28/28 | 28/28 |
| Kilépési kód | 0 | 0 |

A két futás `PLAY RECAP`-je **karakterre azonos**. Utána a gépen `make dev` →
`changed=0`, újraindítás után 30 másodperccel újra 28/28.

### A négy hiba, amit csak a nulláról-próba talált meg

Egyik sem látszott a fejlesztői gépen, mert ott már minden a helyén volt.

**1. A verify feltételezte, hogy az ügyfél kódja már ott van.** Üres `/opt/app`
mellett az `uvicorn` `ModuleNotFoundError`-ral elszáll, a `restart: unless-stopped`
pedig **örökké újraindítja**. Egy végtelenül újrainduló konténer pont akkor teszi
használhatatlanná a „minden szolgáltatás fut" ellenőrzést, amikor a legtöbbet érné:
közvetlenül telepítés után.

A javítás nem a verify-ban van, hanem eggyel feljebb: az `api` szolgáltatás **be sem
kerül a compose fájlba**, amíg nincs kód a helyén — és a playbook ezt ki is mondja.
A verify pedig nem a szándékból (`api_enabled`) indul ki, hanem a **ténylegesen
legenerált** compose-ból: `docker compose config --services`. Így a kettő nem tud
elcsúszni egymástól.

**2. Egy elszakadt kapcsolat eldöntötte az egész telepítést.** A második körben a
229. megabájtnál:

```
failed to copy: read tcp …->18.172.242.124:443: read: connection reset by peer
```

Több gigabájt image letöltésénél ez nem kivétel, hanem a normális működés része. A
`docker build` és a `docker compose up` mostantól **háromszor próbálkozik**. A Docker
rétegenként gyorsítótáraz, tehát az újrapróbálkozás onnan folytatja, ahol abbahagyta —
és ezt élőben is láttuk: a félbemaradt telepítés a következő futásban `changed=1`-gyel
befejeződött.

**3. A playbook „kész"-t jelentett, mielőtt a stack működött volna.** A
`docker compose up -d` visszatérése csak annyit jelent, hogy a konténerek
**elindultak**. Az Airflow ilyenkor még lefuttatja a db-migrációt és az első ütemezői
kört: friss gépen fél–két perc. Emiatt a bootstrap záró ellenőrzése **pirosat írt egy
tökéletesen jó gépre**.

A playbook mostantól megvárja, hogy mind a négy komponens `healthy` legyen. A
végleges futásban ez hat újrapróbálkozás volt — pontosan az a fél perc, ami korábban
elrontotta. Egy telepítőnek azt kell jelentenie, hogy a rendszer **működik**, nem azt,
hogy a konténereket létrehoztuk.

**4. A bootstrap után a `git pull` megtagadta a működést.** A repót root klónozza, a
git 2.35 óta pedig idegen tulajdonú repóban `dubious ownership`-pel elhasal. A
dokumentált fejlesztői út (`git pull && make dev` a saját felhasználóval) tehát
**pont a telepítés után** tört el. A bootstrap most átadja a repót a `$SUDO_USER`-nek.

### Egy ötödik, ami a bootstrapből jött

A jelszavakat a `password` lookup állítja elő, ami a **vezérlő gépen** fut — vagyis
az `ansible`-t indító felhasználó nevében. Ez a bootstrapben root, kézzel viszont
`ubuntu`. Egy root-ként létrehozott `0600`-as titkot az `ubuntu` később nem tudott
volna visszaolvasni: a következő `make dev` `Permission denied`-del állt volna meg egy
addig működő gépen. A `secrets.yml` most minden futás végén egységesíti a tulajdonost.

### Amit a nulláról-próbáról érdemes megjegyezni

**Az első sikeres futás nem bizonyít semmit.** Az első tiszta körünk 7,5 perc alatt
zölden végigment — a második ugyanazzal a kóddal elhasalt. Nem a kód változott, hanem
a hálózat. Ha csak egyszer futtattuk volna, ma is azt hinnénk, hogy kész vagyunk, és
az első ügyfélnél derült volna ki.

**A hibák fele nem a telepítésben volt, hanem abban, hogy mit jelentünk késznek.**
A 2., 3. és 4. pont mind erről szól: a telepítő túl korán mondta, hogy kész, vagy
olyat ellenőrzött, ami még nem lehetett igaz.

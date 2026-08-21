# InitInfra — építési útmutató

> A **mit és miért** a [DESIGN.md](DESIGN.md)-ben van. Ez a fájl a **hogyan jutunk oda**.
> Utolsó frissítés: 2026-08-20

## Alapelvek, amiket végig tarts

1. **A VM eldobható.** Ha valami nem megy, a javítás a repóban történik, nem a gépen.
   Kézi javítás a VM-en = működő gép és nem működő repo.
2. **Minden fázis végén zöld a verify.** Piros verifyjel nem megyünk tovább.
3. **Előbb kézzel, aztán Ansible.** Ne az Ansible-t tanuld és az installt tervezd
   egyszerre.
4. **A `/opt/stack` generált.** Amit ott javítasz, a következő futásnál elvész.

---

## 0. fázis — Előkészítés

**Kb. 1 óra.**

### 0.1 A repo váza

**Ez a sorrend nem felcserélhető** — a `.gitattributes`-nek az első commit *előtt* kell
léteznie, különben a rossz sorvégek beleégnek a történetbe:

```bash
cd InitInfra
git init
printf '* text=auto eol=lf\n' > .gitattributes
printf '.env\n*.retry\n__pycache__/\n' > .gitignore
git add .gitattributes .gitignore docs/
git commit -m "Váz: sorvégek, gitignore, tervdokumentáció"
```

### 0.2 WSL2

Nem control node — az Ansible a célgépen fut —, de innen `rsync`-elsz és `ssh`-zol:

```powershell
wsl --install -d Ubuntu-24.04
```

### 0.3 Az eldobható VM

```bash
multipass launch 24.04 --name infra --cpus 4 --memory 8G --disk 40G
multipass info infra          # innen az IP
```

Tedd fel az SSH kulcsodat, hogy `ssh`-val és `rsync`-kel is elérd. Hyper-V-vel is
mehet, csak akkor csinálj **snapshotot a friss telepítésről**, mert oda fogsz
visszaállni sokszor.

### 0.4 GitHub repo

A 8. fázis `curl | bash` tesztje csak akkor működik, ha a repo elérhető GitHubról —
ezért ezt már most be kell állítani, nem a végén:

```bash
gh repo create InitInfra --public --source=. --remote=origin --push
```

Publikus, ahogy a 15. döntésben szerepel — fejlesztés alatt így a `curl | bash`
tokenmentes. Élesítéskor válik priváttá.

**Kész, ha:** `ssh ubuntu@<vm-ip>` működik, a `git log` egy commitot mutat, és a repo
látszik GitHubon.

---

## 1. fázis — Kézi telepítés, jegyzeteléssel

**Fél–egy nap. Ez a legfontosabb fázis, ne ugord át.**

SSH-zz be a VM-re, és csináld végig kézzel a teljes telepítést. Minden működő
parancsot írj le egy `docs/manual-install.md`-be, ahogy haladsz.

Sorrend:

1. `apt update && apt upgrade`
2. Docker telepítése a hivatalos repóból (nem az Ubuntu csomagból)
3. `ufw`, `fail2ban`, `unattended-upgrades`, swap, időzóna
4. Egy minimális `docker-compose.yml` Postgresszel — indul-e, csatlakozik-e
5. Redis hozzá
6. Az `app` image Dockerfile-ja: `FROM apache/airflow:3.3.1-python3.12`, requirements
7. Az Airflow négy komponense a hivatalos compose alapján, LocalExecutorral
8. Prometheus, exporterek, Grafana
9. Jupyter

**Ez a fázis produkálja az Ansible bemenetét.** Amikor kész, a jegyzeted egy működő,
sorrendbe rakott parancslista lesz — onnan a fordítás már mechanikus.

**Kész, ha:** kézzel feltelepítve minden fut, és a `docs/manual-install.md`-ben minden
parancs le van írva, működő sorrendben.

> Az `apache/airflow` hivatalos compose fájlja jó kiindulás, de **CeleryExecutorra
> van beállítva**. Nálunk LocalExecutor lesz, tehát a `worker` és a `flower` service
> kimarad, a `redis` pedig nem broker, hanem az alkalmazásé.

---

## 2. fázis — Váz, `base` és `docker` szerepkör

**Fél nap** (az első Ansible-lel a tanulási görbe is benne van).

```
site.yml
Makefile
inventory/hosts.yml
group_vars/all.yml
roles/base/tasks/main.yml
roles/docker/tasks/main.yml
```

A `base` és `docker` szerepkör az 1. fázis jegyzeteinek 1–3. pontja, Ansible-re fordítva.

**A `Makefile` is itt születik meg**, nem a 7. fázisban — mert innentől minden fázisban
ezt fogod használni:

```bash
make dev     # rsync a VM-re, majd ansible-playbook -i localhost, -c local
```

**Kész, ha:** friss VM-en lefut hibátlanul, **és másodszorra is** — a második futás
minden taskra `ok`-ot ír, nem `changed`-et. Ha a második futás is `changed`, ott
valami nem idempotens.

---

## 3. fázis — `stack`: Postgres és Redis

**2–3 óra.**

- compose fájl sablonként, a `group_vars`-ból jövő verziókkal és portokkal
- a titkok generálása első futáskor, `.env`-be, **idempotensen** (ha már van, ne írja felül)
- két adatbázis, két user
- Redis: `save ""`, AOF ki, `maxmemory`, `allkeys-lru`

**Kész, ha:** a verify első két pontja zöld — a Postgres fogad kapcsolatot mindkét
adatbázisra, a Redis `PONG`-gal válaszol és a policy tényleg `allkeys-lru`.

---

## 4. fázis — `stack`: az `app` image és az Airflow

**Kb. egy nap. Ez a legnehezebb rész, számíts rá.**

- Dockerfile: `apache/airflow:3.3.1-python3.12` alapon, a torch külön rétegben
- requirements generálása a `group_vars` alapján (alap + `extra_python_packages`)
- négy service: `apiserver`, `scheduler`, `dag-processor`, `triggerer`
- `depends_on: condition: service_healthy` a Postgresre
- init: `airflow db migrate`, admin user létrehozása
- `AIRFLOW__CORE__EXECUTOR=LocalExecutor`, Fernet key és JWT secret a `.env`-ből
- `mem_limit` a scheduleren

**Tipikus elakadások itt:** a bind-mountolt könyvtárak tulajdonjoga (`AIRFLOW_UID`), a
`db migrate` sorrendje, és hogy a `dag-processor` külön komponens a 3.x-ben.

**Kész, ha:** mind a négy konténer `healthy`, az API health endpointja `healthy`, és
a webes felület elérhető.

---

## 5. fázis — `stack`: megfigyelés

**Fél nap.**

- Prometheus a scrape configgal (minden exporter + saját maga)
- node-exporter, cAdvisor (8081!), postgres-exporter, redis-exporter, statsd-exporter
- Airflow `statsd_on = True`, a statsd-exporter felé
- Grafana provisionált datasource-szal

**Kész, ha:** a Prometheus target-listáján **minden sor `UP`**. Ez az egyetlen
ellenőrzés, ami a legtöbb csendes hibát kifogja.

---

## 6. fázis — `stack`: Jupyter és API

**Kb. 2 óra.** Mindkettő ugyanabból az `app` image-ből, a `/opt/app` bemountolva.

- **Jupyter**: token a `.env`-ből, `127.0.0.1`-re kötve
- **API**: `api_command` a `group_vars`-ból, `restart: unless-stopped`,
  `depends_on` a Postgresre és Redisre, a láthatóság `api_allowed_ips` szerint

Az API-t üres `/opt/app`-pal nem tudod tesztelni, hiszen a kód még nincs ott. A
fázis célja, hogy a service *definíciója* kész legyen, és `api_enabled: false` mellett
ne törjön el a stack.

**Kész, ha:** a Jupyter SSH tunnelen megnyílik és `import torch` működik benne;
az `api` service pedig `api_enabled: false`-szal kimarad, `true`-val pedig elindul
(akár hibával, ha nincs még kód — az rendben van ebben a fázisban).

---

## 7. fázis — `bootstrap.sh` és a verify összefésülése

**Fél nap.**

A `verify` szerepkör **nem itt születik**: minden fázis a saját ellenőrzéseivel bővíti,
ahogy haladsz (3. fázisban a Postgres és Redis, 4-ben az Airflow, és így tovább). Itt
csak összefésülöd őket egyetlen, önállóan futtatható egésszé, és kiegészíted azzal,
amit fázis közben nem néztél: minden konténer fut-e, minden Prometheus target `UP`-e.

A `bootstrap.sh` a publikus belépési pont: ansible és git telepítése, klónozás,
playbook futtatása. Opcionális `GITHUB_TOKEN`-nel, hogy a repo priváttá tétele után
ne kelljen átírni.

**Kész, ha:** `make verify` önmagában fut és zöld, egy már telepített gépen.

---

## 8. fázis — Éles próba nulláról

**1–2 óra.**

Töröld a VM-et, és csináld végig a **valódi utat**, semmi `make dev`:

```bash
multipass delete --purge infra
multipass launch 24.04 --name infra --cpus 4 --memory 8G --disk 40G
# majd a VM-en:
curl -fsSL https://raw.githubusercontent.com/<user>/InitInfra/main/bootstrap.sh | bash
```

**Ez az igazi teszt.** Ha ez elsőre végigmegy és a verify zöld, kész a v1.

Csináld meg **kétszer**, két friss VM-en. Az első sikeres futás gyakran szerencse
(gyorsítótárazott image, véletlenül megmaradt fájl); a második mondja meg, hogy tényleg
reprodukálható.

---

## 9. fázis — Az igazi gép

A Rackforest szerveren ugyanaz az egy parancs. Utána:

```bash
git clone <ügyfél-repo> /opt/app
cd /opt/stack && docker compose restart
```

Ha publikálni akarod a felületeket, előtte állítsd be a `group_vars/<gép>.yml`-ben a
`publish_web_ui: true`-t és az `allowed_ips`-t.

---

## Időbecslés

| Fázis | Idő |
|---|---|
| 0. Előkészítés | 1 óra |
| 1. Kézi telepítés | fél–egy nap |
| 2. Váz, base, docker | fél nap |
| 3. Postgres, Redis | 2–3 óra |
| 4. app image, Airflow | **egy nap** |
| 5. Megfigyelés | fél nap |
| 6. Jupyter és API | 2 óra |
| 7. bootstrap, verify összefésülés | fél nap |
| 8. Éles próba | 1–2 óra |

Összesen nagyjából **4–5 munkanap**, az Ansible tanulásával együtt. A 4. fázis fogja a
legtöbb időt enni — ha ott elakadsz, az a normális, nem a te hibád.

---

## Amit ne csinálj

- **Ne javíts kézzel a VM-en**, ha már a 2. fázisnál jársz. Javíts a repóban, dobd el a
  VM-et, futtasd újra.
- **Ne szerkeszd a `/opt/stack`-et.** Generált; a következő futásnál elvész.
- **Ne commitold a `.env`-et.** A repo fejlesztés alatt publikus, a git history pedig
  örök.
- **Ne ugord át a verifyt** azzal, hogy „látom, hogy fut". A Prometheus target-lista
  rendszeresen mutat olyan hibát, ami egyébként hetekig észrevétlen maradna.
- **Ne kezdd a 4. fázissal**, mert az a legérdekesebb. A Postgres nélkül az Airflow el
  sem indul.

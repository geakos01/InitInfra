# InitInfra

Egy szűz Ubuntu 24.04-ből működő gépi tanulási futtatókörnyezet, **egyetlen paranccsal**,
körülbelül tíz perc alatt.

```bash
curl -fsSL https://raw.githubusercontent.com/geakos01/InitInfra/main/bootstrap.sh | sudo bash
```

A telepítő a végén maga ellenőrzi le magát. Ha zölden zárul, a gép áll.

---

## Mit rak fel

Tizenöt szolgáltatás, négy csoportban. Minden verzió rögzítve — `latest` sehol.

| | |
|---|---|
| **Adat** | PostgreSQL 16 (két adatbázis), Redis 7.2 |
| **Ütemezés** | Airflow 3.3.1 négy komponense, `LocalExecutor` |
| **Megfigyelés** | Prometheus, Grafana, és öt exporter (gép, konténer, Postgres, Redis, statsd) |
| **Munka** | JupyterLab és egy FastAPI végpont — ugyanabból a Python-környezetből, mint az Airflow |

Az Airflow, a Jupyter és az API **ugyanazt az image-et** használja: egy Python-környezet,
egy `requirements.txt`. Amit a notebookban kipróbálsz, az a DAG-ban is fut.

## Mit nem csinál

A modellezés **nem** ennek a része. Ez a projekt a gépet szabványosítja — azt, ami
minden telepítésnél ugyanaz. A modell, a DAG-ok és az API kódja a `/opt/app`-ba kerül,
külön repóból, ügyfelenként más.

---

## Alapfogalmak három mondatban

**Pull modell.** A playbook a célgépen fut, saját magára (`-i localhost, -c local`).
A telepítéshez nem kell semmi a te gépeden, csak egy URL.

**Idempotens.** Ugyanaz a parancs kétszer futtatva nem csinál kárt. A második futásnak
`changed=0`-t kell írnia — ha nem, ott valami minden körben újra dolgozik.

**Ellenőrzött.** A `make verify` közel harminc mérést végez a futó gépen (a pontos szám a beállításoktól függ). Nem azt nézi, hogy „fut-e",
hanem hogy jól van-e — mert a legdrágább hibák azok, ahol a rendszer egészségesnek
mondja magát.

---

## Napi használat

A gépen, a telepítés után:

```bash
cd /opt/initinfra

make verify     # Készen áll a gép? Mér, de nem változtat semmit.
make dev        # A playbook futtatása. Ez a fő parancs.
make check      # Mit változtatna? Lásd lentebb — csak telepített gépen.
make diff       # Pontosan melyik sor változna.
make idempotens # Kétszer futtat, és hibát jelez, ha a második változtat.
```

A `make check` **csak már telepített gépen ad értelmes választ.** Szűz gépen
elhasal, és ez nem hiba: száraz módban a korábbi lépések nem hozzák létre azt az
állapotot, amire a későbbiek épülnek (a `/swapfile` nem jön létre, tehát a
jogosultságát sem lehet beállítani). Első telepítéskor egyből `make dev`.

A munkamódszer: **a repóban javítasz, a gépen futtatod.**

```bash
git pull && make dev
```

A `/opt/stack` a célgépen **generált**. Amit ott kézzel átírsz, a következő futásnál
elvész.

---

## Hozzáférés

Alapértelmezésben **egyetlen admin felület sem néz kifelé**. Az Airflow, a Grafana, a
Prometheus és a Jupyter mind a gép hurokcímén hallgat; SSH-alagúton éred el őket:

```bash
ssh -L 8080:127.0.0.1:8080 -L 3000:127.0.0.1:3000 felhasznalo@gep
```

Ezután a saját böngésződben: Airflow a `127.0.0.1:8080`, Grafana a `127.0.0.1:3000`.
A jelszavak a gépen keletkeznek: `sudo cat /opt/stack/.env`.

Ha mégis publikálni akarod őket, a `group_vars`-ban:

```yaml
publish_web_ui: true
allowed_ips: [1.2.3.4]      # kötelező — IP-lista nélkül a telepítő megtagadja
```

A szűrést ilyenkor a `DOCKER-USER` iptables-lánc végzi, **nem az ufw**: a Docker
közvetlenül az iptables `FORWARD` láncába ír, az ufw szabályai elé, ezért egy publikált
konténer-port ufw-vel nem szűrhető. Mérés és részletek:
[docs/manual-install.md](docs/manual-install.md) 4. szakasz.

---

## A saját kódod

A `/opt/app`-ot a playbook mar letrehozta, a te tulajdonodban. **Ne `sudo`-val
klonozz** — root tulajdonu repoban a kesobbi `git pull` `dubious ownership`-pel
megtagadna a mukodest:

```bash
git clone <a-te-repod> /opt/app
cd /opt/initinfra && make dev
```

Privat repohoz **deploy key** kell (a repo Settings → Deploy keys menujeben, iras
nelkul). Jelszot es tokent ne tegyel a szerver lemezere:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_app -N ""
cat ~/.ssh/id_app.pub        # ezt masold be a GitHubon
```

A `/opt/app/dags`-ba tett DAG-fájlokat az Airflow magától megtalálja. Az `api`
szolgáltatás — ami addig szándékosan kimarad, mert kód nélkül csak végtelenül
újraindulna — ekkor indul el.

---

## Beállítás

Minden gépfüggő kapcsoló a `group_vars/all.yml`-ben van; a verziók és portok a
`roles/stack/defaults/main.yml`-ben.

| Amit meg akarsz változtatni | Fájl |
|---|---|
| Időzóna, swap, tűzfal, publikálás | `group_vars/all.yml` |
| Verziók, portok, memóriakorlát | `roles/stack/defaults/main.yml` |
| Python-csomagok | `roles/stack/files/requirements.txt` |
| A szolgáltatások | `roles/stack/templates/docker-compose.yml.j2` |
| Az ellenőrzések | `roles/verify/vars/main.yml` |

---

## Dokumentáció

| | |
|---|---|
| [docs/manual-install.md](docs/manual-install.md) | **A legértékesebb fájl.** Az egész telepítés kézzel, parancsról parancsra, mindegyik mellett egy „Miért" blokkal. Ha nem érted, mit csinál egy task, itt megtalálod sima shell-parancsként. |
| [docs/DESIGN.md](docs/DESIGN.md) | A terv: 17 döntés indoklással, és a változásnapló. |
| [docs/ROADMAP.md](docs/ROADMAP.md) | A fázisok, fázisonként kész-kritériummal. |
| [docs/WORKLOG.md](docs/WORKLOG.md) | Munkamenet-napló: mi dőlt el, mi derült ki méréssel, mibe futottunk bele. |

---

## Követelmények

Ubuntu 24.04, legalább 4 mag / 8 GB RAM / 40 GB lemez. A telepítés kb. 6 GB
konténer-image-et tölt le.

## Ha elakadsz

1. `make verify` — megmondja, melyik ellenőrzés bukott és milyen kilépési kóddal.
   Nem áll meg az első hibánál, tehát egyben látod az összeset.
2. `cd /opt/stack && sudo docker compose logs <szolgáltatás> --tail 50`
3. [docs/manual-install.md](docs/manual-install.md) — mi lett volna a dolga.

Egy fejlesztői VM **eldobható**: ha menthetetlenül elromlott, ne javítsd. Javíts a
repóban, dobd el a gépet, futtasd újra. Tíz perc.

# InitInfra — munkamenet-napló

> Munkamenet-szintű napló: hol tartunk, mi dőlt el, mi jön. **Nem** commitonkénti —
> azt a git log rögzíti, a tervezési döntések változásait pedig a
> [DESIGN.md](DESIGN.md) 12. szakasza.

---

## Jelenlegi állapot

> Ezt a blokkot mindig frissítjük. Ha új beszélgetésben veszed fel a fonalat, ez az
> egyetlen dolog, amit el kell olvasni — plusz a [DESIGN.md](DESIGN.md)-t és a
> [ROADMAP.md](ROADMAP.md)-t.

**Hol tartunk:** a tervezés lezárva (17 döntés), a ROADMAP **0.1 fázisa kész**.
A következő a **0.2–0.4**, amit a `scripts/setup-dev.sh` végigvezet.

**Mi van kész:**

| | |
|---|---|
| `docs/DESIGN.md` | a teljes terv — mit építünk és miért, 17 döntés indoklással |
| `docs/ROADMAP.md` | 10 fázisú építési útmutató, fázisonként kész-kritériummal |
| `docs/WORKLOG.md` | ez a fájl |
| `scripts/setup-dev.sh` | interaktív wizard a 0.2–0.4 lépésekhez |
| `.gitattributes` | `* text=auto eol=lf` — az első commit óta, ez nem véletlen |
| `.claude/settings.json` | 5 read-only parancs engedélylistája |
| git | `main` ág, tiszta munkafa |

**Mi a következő teendő, sorrendben:**

1. `bash scripts/setup-dev.sh` — WSL2, eldobható Ubuntu VM, GitHub repo
   (a `gh` telepítve van, de **nincs bejelentkezve** — a script elindítja a `gh auth login`-t)
2. Utána a **ROADMAP 1. fázisa**: kézzel végigtelepíteni mindent a VM-en, és a működő
   parancsokat leírni a `docs/manual-install.md`-be. Ez adja a 2. fázis Ansible-jének
   a bemenetét.

**A terv lényege egy bekezdésben:** egy szűz Linux gépből egyetlen `curl | bash`
paranccsal működő futtatókörnyezetet csinálunk. **Minden szolgáltatás konténerben**
fut (15 db); a hoston csak Docker és alap gép-higiénia van. Egy közös `app` image
szolgálja ki az Airflow négy komponensét, a Jupytert és a FastAPI végpontot. A telepítő
**Ansible**, pull modellben — a célgépen fut, nem távolról. Ubuntu 24.04, minden verzió
pinnelve.

**Nyitott, tudatosan:** backup, alerting, TLS a publikált felületek előtt, ADR-ek.

**Amire figyelni kell:**

- A fejlesztés Windowsról megy, a célgép Linux — a CRLF és az exec bit valódi buktató
- A `/opt/stack` a célgépen **generált**; amit ott kézzel javítasz, elvész
- A dev VM **eldobható**: hiba esetén a repóban javítunk, nem a gépen

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

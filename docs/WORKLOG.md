# InitInfra — munkamenet-napló

> Munkamenet-szintű napló: hol tartunk, mi dőlt el, mi jön. **Nem** commitonkénti —
> azt a git log rögzíti, a tervezési döntések változásait pedig a
> [DESIGN.md](DESIGN.md) 12. szakasza.

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

**Dokumentáció:** `DESIGN.md` (mit és miért) és `ROADMAP.md` (hogyan jutunk oda).

**0.1 fázis kész:** `git init -b main`, `.gitattributes` (`eol=lf`) az első commit
előtt, `.gitignore`, két commit. A `git ls-files --eol` mindenhol `i/lf w/lf`-et mutat.

### Ami eldőlt, röviden

Minden szolgáltatás konténerben (15 db); a hoston csak Docker és gép-higiénia.
Egy közös `app` image az Airflow négy komponensének, a Jupyternek és az API-nak.
Ansible, pull modellben (`curl | bash` a gépen). Ubuntu 24.04. LocalExecutor.
Redis perzisztencia nélkül. Titkok a gépen generálva. Hozzáférés alapból SSH tunnelen,
gépenként kapcsolható IP-szűrt publikálással.

### Ami nyitva maradt

- **Backup** és **alerting** — tudatosan kihagyva a v1-ből
- **TLS a publikált felületek előtt** — ellenőrizendő a jelenlegi rendszeren
- **ADR-ek** — egyelőre a DESIGN.md változásnaplója látja el a szerepüket

### Következő lépés

ROADMAP 0.2–0.4: WSL2, eldobható Ubuntu VM, és a GitHub repo létrehozása
(`gh auth login` kell hozzá — a gh telepítve van, de nincs bejelentkezve).

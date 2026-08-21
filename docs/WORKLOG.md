# InitInfra — munkamenet-napló

> Munkamenet-szintű napló: hol tartunk, mi dőlt el, mi jön. **Nem** commitonkénti —
> azt a git log rögzíti, a tervezési döntések változásait pedig a
> [DESIGN.md](DESIGN.md) 12. szakasza.

---

## Jelenlegi állapot

> Ezt a blokkot mindig frissítjük. Ha új beszélgetésben veszed fel a fonalat, ez az
> egyetlen dolog, amit el kell olvasni — plusz a [DESIGN.md](DESIGN.md)-t és a
> [ROADMAP.md](ROADMAP.md)-t.

**Hol tartunk:** a tervezés lezárva (17 döntés), a ROADMAP **0.1–0.4 fázisa kész**.
A fejlesztői környezet áll. A következő a **ROADMAP 1. fázisa**.

**Mi van kész:**

| | |
|---|---|
| `docs/DESIGN.md` | a teljes terv — mit építünk és miért, 17 döntés indoklással |
| `docs/ROADMAP.md` | 10 fázisú építési útmutató, fázisonként kész-kritériummal |
| `docs/WORKLOG.md` | ez a fájl |
| `scripts/setup-dev.sh` | interaktív wizard a 0.2–0.4 lépésekhez (idempotens, újrafuttatható) |
| `.gitattributes` | `* text=auto eol=lf` — az első commit óta, ez nem véletlen |
| `.claude/settings.json` | 5 read-only parancs engedélylistája |
| git | `main` ág, publikus GitHub repo, `origin` beállítva |

**A fejlesztői környezet (0.2–0.4):**

| | |
|---|---|
| Gazdagép | ASUS TUF B550M-PLUS, Ryzen 7 5700, 31.8 GB RAM, 16 szál |
| WSL2 | `Ubuntu-24.04`, user `geakos`, systemd be — **opcionális, nem használjuk** |
| Multipass | 1.16.3, backend `hyperv` |
| Cél-VM | `infra` — Ubuntu 24.04.4 LTS, 4 mag / 8 GB / 40 GB |
| Hozzáférés | `ssh ubuntu@$VM_IP` (alapértelmezett kulcs), vagy `multipass shell infra` |
| Kód a VM-re | `git push` a fejlesztőgépen, `git pull` a VM-en — **nincs rsync** |
| `.env` | `VM_NAME`, `VM_IP` — **gitignore-olt**, nem kerül a repóba |

**Mi a következő teendő:**

A **ROADMAP 1. fázisa**: kézzel végigtelepíteni mindent a VM-en, és a működő
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
- A VM IP-je Hyper-V NAT-os, és **újraindításkor változhat** — ha az ssh nem megy,
  `multipass info infra` és frissítsd a `.env`-et (vagy futtasd újra a `setup-dev.sh`-t)
- A `mem_limit` értékeket a 2. fázisban **változóból** generáljuk, ne bedrótozva: a
  valódi gép 32 GB, a dev VM 8 GB — a bedrótozott limitek a VM-en elfogynának

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

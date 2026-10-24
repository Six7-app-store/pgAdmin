# pgAdmin 4 – PostgreSQL-Administration mit Beispieldatenbank

Jedes Team bekommt eine eigene VM mit PostgreSQL, der Beispieldatenbank
[Pagila](https://github.com/devrimgunduz/pagila) (Film- und Videoverleih)
und pgAdmin 4 im Browser. Die Datenbank ist in pgAdmin schon als Server
eingetragen.

## User-Management

- **Ein pgAdmin-Konto pro Team**, alle Mitglieder teilen sich den Login
- Login ist eine E-Mail-Adresse aus dem Teamnamen:
  `Team #1` → `team-1@example.com`. Das Passwort wird zufällig erzeugt
- Die Zugangsdaten zeigt der App Store nach dem Deployment jedem
  Teammitglied an und verschickt sie per Mail

Der Datenbanknutzer für Pagila ist `pagila_user` mit dem Passwort `pagila`.
pgAdmin fragt danach, sobald man den Server `pagila (local)` öffnet.

## VM-Deployment

| | |
|---|---|
| VMs gesamt | **eine pro Team** (höchstens `max_teams`, Standard 15) |
| Größe | wählbar: `gp1.small`, `gp1.medium`, `gp1.large` (Standard `gp1.small`) |
| Festplatte | wählbar: 10–200 GB, Standard ist die Platte des Flavors (10 GB) |
| Erreichbar über | HTTP auf Port 80 unter `/pgadmin4`, wählbar über IPv6 (Standard), IPv4 oder beides |
| Floating IP | Nein |

## Konfigurierbare Variablen

| Variable | Beschreibung | Standard |
|---|---|---|
| `flavor` | Größe der Team-VM | `gp1.small` |
| `disk_size_gb` | Festplatte in GB, `0` nutzt die Platte des Flavors | `0` |
| `max_teams` | Obergrenze für Team-VMs in einem Deployment | `15` |
| `ip_mode` | Adressfamilie: `ipv4`, `ipv6` oder `dual` | `ipv6` |
| `network_uuid` | Netz mit öffentlicher IPv6, für `ipv6` und `dual` | `DHBWV6` |
| `network_v4_uuid` | Netz mit öffentlich gerouteter IPv4, für `ipv4` und `dual` | leer |
| `shared_secgroup_id` | ID der gemeinsamen Security Group | `default` |

`ip_mode` funktioniert wie bei der
[Ubuntu-App](https://github.com/Six7-app-store/Ubuntu-App#adressfamilie-ip_mode).
Die Security Group der App öffnet Port 80 je gewählter Familie.

## Einrichtung beim Boot

Es wird kein Image mehr gebaut (ADR 0010 im deployment-Repo). cloud-init legt
die Dateien aus [`tofu/files/`](tofu/files/) und das Teamkonto ab, danach
erledigt [`pgadmin-setup.sh`](tofu/files/pgadmin-setup.sh) den Rest:

1. PostgreSQL aus Ubuntu und `pgadmin4-web` aus dem Paketarchiv von
   pgadmin.org installieren
2. Pagila von GitHub laden und `pagila_user` die Rechte geben
3. `setup-web.sh` richtet pgAdmin unter Apache ein und legt dabei das
   Teamkonto an
4. `setup.py load-servers` trägt die Datenbank aus
   [`servers.json`](tofu/files/servers.json) für das Teamkonto ein

Das Skript meldet erst Erfolg, wenn die Anmeldeseite antwortet. Scheitert ein
Schritt, scheitert `cloud-final.service`, und der App Store zeigt das
Deployment als fehlgeschlagen mit den passenden Zeilen aus der Konsole
(ADR 0011). Das Protokoll steht auf der VM in
`/var/log/cloud-init-output.log`.

Wie lange die Einrichtung auf newstack dauert, ist noch nicht gemessen.

## Prüfen ohne Cloud

```bash
cd tofu
tofu init -backend=false
tofu fmt -check -recursive
tofu validate
tofu test
```

Die Tests mocken alle Provider und brauchen keinen OpenStack-Zugang. Die CI
([`.github/workflows/opentofu.yml`](.github/workflows/opentofu.yml)) fährt
dieselben Schritte und prüft zusätzlich das Setup-Skript mit ShellCheck.

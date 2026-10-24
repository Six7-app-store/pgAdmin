# -----------------------------------------------------------------------------
# Einrichtung der Team-VM beim ersten Boot
#
# Ersetzt das fruehere Packer-Image (ADR 0010 im deployment-Repo). cloud-init
# legt die Dateien aus tofu/files/ und das Teamkonto ab, pgadmin-setup.sh
# installiert danach PostgreSQL und pgAdmin und laedt die Beispieldatenbank.
#
# Die Konfiguration wird mit yamlencode gebaut statt als Template: yamlencode
# quotet jeden Wert selbst, auch Teamnamen mit "#" oder ":".
# -----------------------------------------------------------------------------

locals {
  app_files = [
    for f in sort(fileset("${path.module}/files", "**")) : {
      path        = "/opt/pgadmin/${f}"
      encoding    = "gz+b64"
      content     = base64gzip(file("${path.module}/files/${f}"))
      permissions = endswith(f, ".sh") ? "0755" : "0644"
    }
  ]

  cloud_init_config = {
    for team in local.teams_list : team => {
      write_files = concat(
        local.app_files,

        # Login des Teams, je eine Zeile E-Mail und Passwort. Das
        # Setup-Skript loescht die Datei, sobald pgAdmin das Konto kennt.
        [
          {
            path        = "/etc/pgadmin-team/account"
            permissions = "0600"
            content     = "${local.team_account_email[team]}\n${random_password.team_passwords[team].result}\n"
          },
        ],

        # ip_mode = dual: die IPv4-Schnittstelle, die OpenTofu nach dem Boot
        # anhaengt. Ihre Default-Route ueber das Gateway des IPv4-Netzes steht
        # in einer eigenen Tabelle, und nur Pakete mit ihrer Adresse als
        # Absender nehmen diese Tabelle. Sonst gingen Antworten ueber die
        # Hauptschnittstelle hinaus, und Neutrons Port-Security verwirft sie
        # als gefaelschten Absender. Gleiches Muster wie der Staging-Aufbau
        # im deployment-Repo.
        local.dual ? [
          {
            path        = "/etc/netplan/60-secondary-ipv4.yaml"
            permissions = "0600"
            content = yamlencode({
              network = {
                version = 2
                ethernets = {
                  secondary = {
                    match           = { macaddress = local.secondary[team].mac }
                    dhcp4           = true
                    dhcp6           = false
                    accept-ra       = false
                    dhcp4-overrides = { use-routes = false }
                    routes          = [{ to = "default", via = local.secondary_gateway, table = 100 }]
                    routing-policy  = [{ from = local.secondary[team].ipv4, table = 100 }]
                  }
                }
              }
            })
          },
        ] : [],
      )

      runcmd = concat(
        local.dual ? [
          # Die IPv4-Schnittstelle kommt erst nach dem Boot dazu. Bis zu
          # fuenf Minuten auf ihre MAC warten, dann die netplan-Datei oben
          # anwenden. Kommt sie nicht, bleibt die VM ueber IPv6 erreichbar.
          ["sh", "-c", "for i in $(seq 1 60); do if ip -o link | grep -qi \"$1\"; then netplan apply; break; fi; sleep 5; done", "sh", local.secondary[team].mac],
        ] : [],
        [
          # Als letzter Befehl: sein Exit-Code entscheidet, ob cloud-final
          # als fehlgeschlagen gilt.
          ["bash", "/opt/pgadmin/pgadmin-setup.sh"],
        ],
      )

      final_message = "pgAdmin fuer Team ${team} bereit"
    }
  }

  cloud_init = {
    for team, config in local.cloud_init_config : team => "#cloud-config\n${yamlencode(config)}"
  }
}

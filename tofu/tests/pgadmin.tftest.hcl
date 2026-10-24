# Prüft, wie Team-VMs, Teamkonten und Einrichtung aus den Variablen
# entstehen. Alle Provider sind gemockt: der Test braucht keinen
# OpenStack-Zugang und legt nichts an.
#
#   cd tofu && tofu init -backend=false && tofu test

mock_provider "openstack" {
  mock_data "openstack_images_image_v2" {
    defaults = {
      id = "00000000-0000-0000-0000-00000000image"
    }
  }
  mock_resource "openstack_networking_port_v2" {
    defaults = {
      all_fixed_ips = ["141.72.10.7", "2001:db8:4::7"]
      mac_address   = "fa:16:3e:00:00:07"
    }
  }
}

mock_provider "random" {}

variables {
  users = {
    "Team #1" = [{ email = "Anna.Alt@dhbw.de" }, { email = "ben@dhbw.de" }]
    "b"       = [{ email = "cem@dhbw.de" }]
  }
}

run "eine_vm_und_ein_konto_je_team" {
  command = apply

  assert {
    condition     = length(openstack_compute_instance_v2.team_vm) == 2
    error_message = "Jedes Team braucht genau eine VM."
  }
  assert {
    condition     = openstack_compute_instance_v2.team_vm["Team #1"].name == "pgadmin-team-1"
    error_message = "Der VM-Name muss ein gueltiger Hostname sein (\"Team #1\" -> team-1)."
  }
  assert {
    condition     = output.user_accounts["Team #1-Anna-Alt"].username == "team-1@example.com" && output.user_accounts["Team #1-ben"].username == "team-1@example.com"
    error_message = "Alle Mitglieder eines Teams teilen sich das Teamkonto."
  }
  assert {
    condition     = output.user_accounts["Team #1-Anna-Alt"].auth == output.user_accounts["Team #1-ben"].auth
    error_message = "Das Teamkonto hat ein Passwort fuer alle Mitglieder."
  }
}

run "einrichtung_je_team" {
  command = apply

  assert {
    condition     = startswith(local.cloud_init["b"], "#cloud-config\n")
    error_message = "user_data muss mit #cloud-config beginnen."
  }
  assert {
    condition     = startswith(one([for f in yamldecode(local.cloud_init["b"]).write_files : f.content if f.path == "/etc/pgadmin-team/account"]), "b@example.com\n")
    error_message = "Die erste Zeile der Kontodatei ist die E-Mail des Teamkontos."
  }
  assert {
    condition     = contains([for f in yamldecode(local.cloud_init["b"]).write_files : f.path], "/opt/pgadmin/servers.json")
    error_message = "Der Servereintrag fuer Pagila muss auf der VM liegen."
  }
  assert {
    condition     = yamldecode(local.cloud_init["b"]).runcmd[length(yamldecode(local.cloud_init["b"]).runcmd) - 1] == ["bash", "/opt/pgadmin/pgadmin-setup.sh"]
    error_message = "Das Setup-Skript muss zuletzt laufen, sein Exit-Code entscheidet ueber cloud-final."
  }
}

run "zugang_ueber_ipv6" {
  command = apply

  assert {
    condition     = alltrue([for a in values(output.user_accounts) : a.ip == "2001:db8:4::7" && a.port == 80 && a.protocol == "web"])
    error_message = "Im Standardnetz ist nur IPv6 oeffentlich - die Zugangsdaten muessen sie nennen."
  }
  assert {
    condition     = output.team_vms["b"].url == "http://[2001:db8:4::7]/pgadmin4"
    error_message = "Die URL muss auf /pgadmin4 zeigen, IPv6 in eckigen Klammern."
  }
  assert {
    condition     = keys(openstack_networking_secgroup_rule_v2.http) == ["IPv6"]
    error_message = "Ohne Auswahl gilt ipv6: nur eine HTTP-Regel fuer IPv6."
  }
}

run "zugang_ueber_ipv4" {
  command = apply

  variables {
    ip_mode         = "ipv4"
    network_v4_uuid = "00000000-0000-0000-0000-0000000000v4"
  }

  assert {
    condition     = output.team_vms["b"].url == "http://141.72.10.7/pgadmin4"
    error_message = "Die URL muss die IPv4 der VM nennen."
  }
  assert {
    condition     = keys(openstack_networking_secgroup_rule_v2.http) == ["IPv4"]
    error_message = "ipv4 braucht genau eine HTTP-Regel fuer IPv4."
  }
}

run "dual_haengt_ipv4_als_zweite_schnittstelle_an" {
  command = apply

  variables {
    ip_mode         = "dual"
    network_v4_uuid = "00000000-0000-0000-0000-0000000000v4"
  }

  assert {
    condition     = length(openstack_compute_interface_attach_v2.team_v4) == 2
    error_message = "dual braucht je Team-VM eine IPv4-Schnittstelle als zweiten Port."
  }
  assert {
    condition     = toset(keys(openstack_networking_secgroup_rule_v2.http)) == toset(["IPv4", "IPv6"])
    error_message = "dual braucht HTTP-Regeln fuer beide Familien."
  }
}

run "zu_viele_teams_werden_abgelehnt" {
  command = plan

  variables {
    max_teams = 1
  }

  expect_failures = [terraform_data.team_limit]
}

run "unbekannter_flavor_wird_abgelehnt" {
  command = plan

  variables {
    flavor = "gpu.huge"
  }

  expect_failures = [var.flavor]
}

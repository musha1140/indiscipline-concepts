# Switchboard relay on the Pi (`gsl`)

The relay holds one shared JSON document so every Switchboard browser on the tailnet sees the same channels, intake queue, receipts and engagements. It listens on 127.0.0.1 only; `tailscale serve` publishes it as HTTPS to tailnet devices and nothing on the public internet can reach it. Sealed channel bodies arrive as AES-GCM ciphertext and stay that way on disk.

## What it changes on the Pi

Creates a system user `switchboard`, the folders `/opt/switchboard`, `/etc/switchboard`, `/var/lib/switchboard`, one systemd unit, and one `tailscale serve` mapping on port 443 to 8787. Nothing existing is overwritten unless a file with the same path already exists. Check first with:

    ls -la /opt/switchboard /etc/switchboard /var/lib/switchboard; systemctl status switchboard-relay; tailscale serve status

Undo: `sudo systemctl disable --now switchboard-relay`, `tailscale serve reset`, then remove the three folders and the user.

## Install (run on `gsl` over SSH, from the repo checkout)

    sudo useradd --system --no-create-home --shell /usr/sbin/nologin switchboard
    sudo install -d -o switchboard -g switchboard -m 750 /var/lib/switchboard
    sudo install -d -m 755 /opt/switchboard /etc/switchboard
    sudo install -m 644 tools/relay/switchboard_relay.py /opt/switchboard/
    sudo install -m 644 tools/relay/switchboard-relay.service /etc/systemd/system/
    printf 'SWITCHBOARD_TOKEN=%s\nSWITCHBOARD_DATA=/var/lib/switchboard/state.json\n' "$(python3 -c 'import secrets;print(secrets.token_urlsafe(32))')" | sudo tee /etc/switchboard/relay.env >/dev/null
    sudo chmod 640 /etc/switchboard/relay.env && sudo chgrp switchboard /etc/switchboard/relay.env
    sudo systemctl daemon-reload && sudo systemctl enable --now switchboard-relay
    sudo tailscale serve --bg 8787

Read the token once with `sudo cat /etc/switchboard/relay.env`, then in Switchboard open Relay and enter `https://gsl.<your-tailnet>.ts.net` and that token. The exact hostname is printed by `tailscale serve status`.

## Allowed origins

Defaults to `https://gas-lighting.com` and `https://musha1140.github.io`. Add others with `SWITCHBOARD_ORIGINS=` in `/etc/switchboard/relay.env` and restart the service.

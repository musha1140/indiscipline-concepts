# Indiscipline concepts

Published presentation files only. Editable React source, design data, credentials and private review services are excluded.

Preview: https://gas-lighting.com/indiscipline-concepts/

- Discipline: presentation.html
- The Court: presentation-paper.html
- Red: presentation-red.html

The October 16, 2026 poster is in site/assets/oct16-poster.svg. Its original wordmark, emblem and QR regions are sourced from the band's existing poster. Confirm the QR destination and event details before printing.

Existing tickets and music destinations are retained. Photographs still use the band's existing image host. These are design concepts for review.

## Switchboard

Gas-Lighting LLC's client messaging console, with Indiscipline as the first client workspace: https://gas-lighting.com/indiscipline-concepts/switchboard/

- The Floor comes first. Before anyone posts in a client's channels or signs an engagement step, both teams seat their people (lead, member or observer, and who may sign) and agree working terms: reply window, hours, time zone, decision rule, escalation and scope. A lead from each side accepts the same hashed version, and only the accepted version is enforced. Later changes become a pending version that takes effect when both leads accept again. Client members see nothing but the Floor until they hold a seat on the open version.
- Direct links open a view: `#floor:o-ind` opens the Indiscipline floor. Each seat has an Invite link that carries the seat and the relay address; the person opens it, enters the relay token sent to them separately, and that browser becomes their seat. People can carry a Discord tag.
- Channels per client, a unified inbox, threads, quick switcher (Ctrl K) and search. Leads' messages are tagged with the side they speak for.
- Intake: inbound email is screened onto an 8 by 8 token board and a person releases, holds or discards it. Thin signal is reported as unknown, never as safe. Every decision is a hash-chained receipt.
- Watermarked messages: an invisible zero-width mark records author, time and a hash of the visible words. Verify a copy reports intact, altered, damaged or absent.
- Sealed channels: AES-GCM with a PBKDF2 passphrase, encrypted in the browser before storage or relay.
- Engagement: ordered sign-offs between GSL and the client, each step hashed onto the last, with a proof run that detects edits.
- Members are per-organization memberships with an explicit role (client, coworker, team, contractor). The same person in two organizations is two records.
- Data stays in the browser unless a relay is set. tools/relay/ runs the relay on the Pi tailnet node `gsl`, reachable only inside the tailnet.

## Tools (not deployed)

- tools/relay/: Switchboard state relay and its systemd unit.
- tools/aws/: AWS Agent Toolkit setup for Windows, profile `gsl`, project Region us-east-2. Run `powershell -ExecutionPolicy Bypass -File .\tools\aws\setup-agent-toolkit.ps1`.

## Deployment

The workflow deploys only site/ through GitHub Pages, using the account's inherited custom domain. This repository does not contain the editable application source or its private comment service.

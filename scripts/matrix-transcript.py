#!/usr/bin/env python3
"""Export the full transcript of a Matrix room as plain text.

Usage: matrix-transcript.py ROOM [-o FILE]
  ROOM  a room id (!abc:server), an alias (#name:server) or a client URL
        (https://sable.josevictor.me/!space%3Aserver/!room%3Aserver)

Reads the room with the first token in secrets/k8s-secrets.enc.yaml that has
access to it (bridge appservice tokens included), so no login is needed.
Encrypted rooms are not supported - their events cannot be read this way.
"""

import argparse
import json
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

HOMESERVER = "https://matrix.josevictor.me"
SECRETS = Path(__file__).resolve().parent.parent / "secrets" / "k8s-secrets.enc.yaml"
TOKEN_SUFFIXES = ("_as_token", "_matrix_token", "_matrix_access_token")


def api(path, token, params=None):
    url = f"{HOMESERVER}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as err:
            raise RuntimeError(json.load(err).get("error", str(err)))
        except OSError:
            if attempt == 3:
                raise
            time.sleep(2 * (attempt + 1))


def candidate_tokens():
    plain = subprocess.run(
        ["sops", "-d", str(SECRETS)], check=True, capture_output=True, text=True
    ).stdout
    for line in plain.splitlines():
        key, _, value = line.partition(": ")
        if key.endswith(TOKEN_SUFFIXES) and value:
            yield key, value.strip().strip("\"'")


def resolve_room(room, token):
    if room.startswith("#"):
        alias = urllib.parse.quote(room, safe="")
        return api(f"/_matrix/client/v3/directory/room/{alias}", token)["room_id"]
    return room


def pick_token(room):
    """First token that can read the room, plus the resolved room id."""
    for name, token in candidate_tokens():
        try:
            room_id = resolve_room(room, token)
            api(f"/_matrix/client/v3/rooms/{urllib.parse.quote(room_id, safe='')}/state/m.room.create/", token)
            print(f"using {name}", file=sys.stderr)
            return token, room_id
        except RuntimeError:
            continue
    sys.exit(f"no token in {SECRETS.name} can read {room}")


def fetch_events(room_id, token):
    room = urllib.parse.quote(room_id, safe="")
    names, events, start = {}, [], None
    for member in api(f"/_matrix/client/v3/rooms/{room}/members", token).get("chunk", []):
        if display := (member.get("content") or {}).get("displayname"):
            names[member["state_key"]] = display
    while True:
        params = {"dir": "b", "limit": "1000"}
        if start:
            params["from"] = start
        page = api(f"/_matrix/client/v3/rooms/{room}/messages", token, params)
        chunk = page.get("chunk", [])
        events.extend(chunk)
        print(f"fetched {len(events)} events", file=sys.stderr)
        end = page.get("end")
        if not chunk or not end or end == start:
            break
        start = end
    events.reverse()
    return names, events


def render(names, events, room_id):
    by_id = {event["event_id"]: event for event in events}
    media = {"m.image": "imagem", "m.video": "vídeo", "m.audio": "áudio", "m.file": "arquivo"}

    def who(user_id):
        return names.get(user_id, user_id)

    def stamp(event):
        moment = datetime.fromtimestamp(event["origin_server_ts"] / 1000, timezone.utc)
        return moment.astimezone().strftime("%Y-%m-%d %H:%M:%S")

    def text_of(event):
        content = event.get("content") or {}
        if event.get("unsigned", {}).get("redacted_because"):
            return "[mensagem apagada]"
        body = content.get("body", "")
        if kind := media.get(content.get("msgtype")):
            return f"[{kind}: {body}]" if body else f"[{kind}]"
        if content.get("msgtype") == "m.location":
            return f"[localização: {body}]"
        return body

    room_name = next(
        (e["content"]["name"] for e in reversed(events) if e["type"] == "m.room.name"), ""
    )
    lines = [
        f"Sala: {room_name}",
        f"Room ID: {room_id}",
        f"Exportado em: {datetime.now().astimezone().strftime('%Y-%m-%d %H:%M:%S %Z')}",
        f"Fuso horário dos timestamps: {datetime.now().astimezone().tzname()}",
        "=" * 72,
        "",
    ]

    for event in events:
        when, sender = stamp(event), who(event["sender"])
        kind = event["type"]
        content = event.get("content") or {}
        if kind == "m.room.message":
            relation = content.get("m.relates_to") or {}
            prefix = ""
            if relation.get("rel_type") == "m.replace":
                prefix = "(editado) "
                body = (content.get("m.new_content") or content).get("body", "")
            else:
                body = text_of(event)
            if reply_to := relation.get("m.in_reply_to"):
                if source := by_id.get(reply_to.get("event_id")):
                    prefix += f"(respondendo a {who(source['sender'])}) "
                body = "\n".join(l for l in body.split("\n") if not l.startswith("> ")).lstrip("\n")
            lines.append(f"[{when}] {sender}: {prefix}{body}".replace("\n", "\n    "))
        elif kind == "m.reaction":
            relation = content.get("m.relates_to") or {}
            source = by_id.get(relation.get("event_id"))
            target = f" a mensagem de {who(source['sender'])}" if source else ""
            lines.append(f"[{when}] {sender} reagiu com {relation.get('key', '?')}{target}")
        elif kind == "m.room.member":
            verb = {"join": "entrou", "leave": "saiu", "invite": "foi convidado", "ban": "foi banido"}
            subject = content.get("displayname") or event.get("state_key")
            lines.append(f"[{when}] -- {subject} {verb.get(content.get('membership'), '?')} --")
        elif kind == "m.room.name":
            lines.append(f"[{when}] -- nome da sala definido: {content.get('name', '')} --")
        elif kind == "m.room.topic":
            lines.append(f"[{when}] -- tópico definido --")
        elif kind == "m.room.create":
            lines.append(f"[{when}] -- sala criada --")

    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("room", help="room id, alias or client URL")
    parser.add_argument("-o", "--output", help="write to this file instead of stdout")
    args = parser.parse_args()

    room = args.room
    if room.startswith("http"):
        room = urllib.parse.unquote(urllib.parse.urlparse(room).path.rstrip("/").split("/")[-1])

    token, room_id = pick_token(room)
    names, events = fetch_events(room_id, token)
    transcript = render(names, events, room_id)

    if args.output:
        Path(args.output).write_text(transcript)
        print(f"wrote {args.output}", file=sys.stderr)
    else:
        sys.stdout.write(transcript)


if __name__ == "__main__":
    main()

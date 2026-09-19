# Sidecar + event rules that post camera uploads from SFTPGo into Matrix.
#
# SFTPGo's event manager cannot post an image to Matrix on its own: Matrix needs
# two chained calls (upload the media, then send a message referencing the mxc://
# URI it returns) and an action cannot read the previous action's response. So the
# rule below calls a small relay running as a sidecar in the sftpgo pod, which
# reads the uploaded file from the shared volume and makes both calls.
{ homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;

  relayPort = 9000;

  # Where the camera writes: /<camera-id>/<YYYY-MM-DD>/01/pic/<HHMMSSmmm>.jpg
  # relative to the cameraman user's home. Recordings land in .../rec/*.h264 and
  # are deliberately not matched.
  snapshotPattern = "/*/*/*/pic/*.jpg";
  cameraUser = "cameraman";

  eventData = {
    version = 17;

    event_actions = [
      {
        name = "cctv-matrix-post";
        description = "Hand the uploaded snapshot to the Matrix relay sidecar";
        type = 1; # HTTP
        options.http_config = {
          endpoint = "http://127.0.0.1:${toString relayPort}/notify";
          method = "POST";
          timeout = 60;
          query_parameters = [
            {
              key = "fs_path";
              value = "{{.FsPath}}";
            }
            {
              key = "name";
              value = "{{.ObjectName}}";
            }
          ];
        };
      }
    ];

    event_rules = [
      {
        name = "cctv-person-detection";
        description = "Post person-detection snapshots to the CCTV Matrix room";
        status = 1;
        trigger = 1; # filesystem event
        conditions = {
          fs_events = [ "upload" ];
          options = {
            names = [{ pattern = cameraUser; }];
            fs_paths = [{ pattern = snapshotPattern; }];
            event_statuses = [ 1 ]; # only successful uploads
          };
        };
        actions = [
          {
            name = "cctv-matrix-post";
            order = 1;
            relation_options = {
              is_failure_action = false;
              stop_on_failure = false;
              execute_sync = false;
            };
          }
        ];
      }
    ];
  };
in
{
  kubernetes.resources.configMaps = {
    "sftpgo-matrix-relay" = {
      metadata.namespace = namespace;
      data."relay.py" = ''
        #!/usr/bin/env python3
        """Post files uploaded to SFTPGo into a Matrix room.

        Runs as a sidecar in the sftpgo pod. SFTPGo's event manager calls
        POST /notify?fs_path=...&name=... ; this reads the file from the shared
        volume, uploads it to the homeserver media repository and sends an
        m.image (or m.file) message referencing the returned mxc:// URI.
        """

        import json
        import mimetypes
        import os
        import time
        import urllib.parse
        import urllib.request
        from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

        HOMESERVER = os.environ["MATRIX_HOMESERVER"].rstrip("/")
        ROOM_ID = os.environ["MATRIX_ROOM_ID"]
        ACCESS_TOKEN = os.environ["MATRIX_ACCESS_TOKEN"]
        PORT = int(os.environ.get("RELAY_PORT", "9000"))
        MAX_BYTES = int(os.environ.get("RELAY_MAX_BYTES", str(32 * 1024 * 1024)))


        def log(message):
            print(time.strftime("%Y-%m-%dT%H:%M:%S"), message, flush=True)


        def matrix(method, path, payload, content_type):
            request = urllib.request.Request(
                HOMESERVER + path,
                data=payload,
                method=method,
                headers={
                    "Authorization": "Bearer " + ACCESS_TOKEN,
                    "Content-Type": content_type,
                },
            )
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response)


        def post_to_matrix(fs_path, name):
            with open(fs_path, "rb") as handle:
                payload = handle.read(MAX_BYTES + 1)
            if len(payload) > MAX_BYTES:
                raise ValueError(name + " is larger than " + str(MAX_BYTES) + " bytes")

            mimetype = mimetypes.guess_type(name)[0] or "application/octet-stream"
            upload = matrix(
                "POST",
                "/_matrix/media/v3/upload?filename=" + urllib.parse.quote(name),
                payload,
                mimetype,
            )
            event = {
                "msgtype": "m.image" if mimetype.startswith("image/") else "m.file",
                "body": name,
                "url": upload["content_uri"],
                "info": {"mimetype": mimetype, "size": len(payload)},
            }
            sent = matrix(
                "PUT",
                "/_matrix/client/v3/rooms/%s/send/m.room.message/sftpgo%d"
                % (urllib.parse.quote(ROOM_ID), time.time_ns()),
                json.dumps(event).encode(),
                "application/json",
            )
            return sent["event_id"]


        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
                fs_path = (query.get("fs_path") or [""])[0]
                name = (query.get("name") or [""])[0] or os.path.basename(fs_path)
                try:
                    event_id = post_to_matrix(fs_path, name)
                except Exception as err:
                    log("failed to post %s: %s" % (fs_path, err))
                    self.send_response(500)
                    self.end_headers()
                    return
                log("posted %s as %s" % (fs_path, event_id))
                self.send_response(204)
                self.end_headers()

            def log_message(self, *args):
                pass


        log("relaying sftpgo uploads to %s on %s" % (ROOM_ID, HOMESERVER))
        ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
      '';
    };

    # Loaded by sftpgo on every start via SFTPGO_LOADDATA_FROM, so the rule stays
    # declarative here instead of being clicked together in the admin UI.
    "sftpgo-event-rules" = {
      metadata.namespace = namespace;
      data."loaddata.json" = builtins.toJSON eventData;
    };
  };
}

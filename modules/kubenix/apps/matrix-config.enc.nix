{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets = {
        "synapse-env" = {
          metadata = {
            namespace = namespace;
          };
          stringData = {
            "postgres-password" = kubenix.lib.secretsFor "postgresql_admin_password";
            "macaroon-secret-key" = kubenix.lib.secretsFor "synapse_macaroon_secret_key";
            "form-secret" = kubenix.lib.secretsFor "synapse_form_secret";
            "registration-shared-secret" = kubenix.lib.secretsFor "synapse_registration_shared_secret";
          };
        };

        "synapse-signing-key" = {
          metadata = {
            namespace = namespace;
          };
          stringData = {
            "matrix.josevictor.me.key" = kubenix.lib.secretsFor "synapse_signing_key";
          };
        };

        "mautrix-whatsapp-registration" = {
          metadata = {
            namespace = namespace;
          };
          stringData = {
            "registration.yaml" = kubenix.lib.toYamlStr {
              id = "whatsapp";
              url = "http://mautrix-whatsapp.${namespace}.svc.cluster.local:29318";
              as_token = kubenix.lib.secretsInlineFor "mautrix_whatsapp_as_token";
              hs_token = kubenix.lib.secretsInlineFor "mautrix_whatsapp_hs_token";
              sender_localpart = "whatsappbot";
              namespaces = {
                users = [
                  {
                    exclusive = true;
                    regex = "@whatsappbot:josevictor\\.me";
                  }
                  {
                    exclusive = true;
                    regex = "@whatsapp_.*:josevictor\\.me";
                  }
                ];
                rooms = [ ];
                aliases = [ ];
              };
            };
          };
        };

        # mautrix-whatsapp v0.11+/v26+ megabridge config format
        "mautrix-whatsapp-config" = {
          metadata = {
            namespace = namespace;
          };
          stringData = {
            "config.yaml" = kubenix.lib.toYamlStr {
              # WhatsApp network-specific settings
              network = {
                displayname_template = "{{or .BusinessName .PushName .JID}} (WA)";
                os_name = "Mautrix-WhatsApp bridge";
                browser_name = "unknown";

                # History sync settings - sync ALL conversations including DMs
                history_sync = {
                  # -1 = sync ALL conversations (groups AND private chats)
                  max_initial_conversations = -1;
                  # Request full sync (1 year instead of 3 months)
                  request_full_sync = true;
                  # Wait for history sync payloads before starting backfill
                  dispatch_wait = "1m";
                  # Media request settings
                  media_requests = {
                    auto_request_media = true;
                    request_method = "immediate";
                    max_async_handle = 2;
                  };
                };
              };

              # Homeserver connection
              homeserver = {
                address = "http://synapse-matrix-synapse.${namespace}.svc.cluster.local:8008";
                domain = "josevictor.me";
              };

              # Appservice settings
              appservice = {
                address = "http://mautrix-whatsapp.${namespace}.svc.cluster.local:29318";
                hostname = "0.0.0.0";
                port = 29318;
                id = "whatsapp";
                bot = {
                  username = "whatsappbot";
                  displayname = "WhatsApp Bridge Bot";
                  avatar = "mxc://maunium.net/NeXNQarUbrlYBiPCpprYsRqr";
                };
                as_token = kubenix.lib.secretsInlineFor "mautrix_whatsapp_as_token";
                hs_token = kubenix.lib.secretsInlineFor "mautrix_whatsapp_hs_token";
                ephemeral_events = true;
                async_transactions = false;
              };

              # Database configuration
              database = {
                type = "postgres";
                uri = "postgres://postgres:${kubenix.lib.secretsInlineFor "postgresql_admin_password"}@postgresql-18-hl.${namespace}.svc.cluster.local:5432/mautrix_whatsapp?sslmode=disable";
                max_open_conns = 20;
                max_idle_conns = 2;
                max_conn_idle_time = null;
                max_conn_lifetime = null;
              };

              # Bridge settings
              bridge = {
                username_template = "whatsapp_{{.}}";
                command_prefix = "!wa";
                # Enable private chat portal metadata
                private_chat_portal_meta = true;
                # Create a space for rooms
                personal_filtering_spaces = true;
                permissions = {
                  "*" = "relay";
                  "@jose:josevictor.me" = "admin";
                  "@admin:josevictor.me" = "admin";
                };
                relay = {
                  enabled = true;
                  message_formats = {
                    "m.text" = "<b>{{ .Sender.Displayname }}</b>: {{ .Message }}";
                    "m.notice" = "<b>{{ .Sender.Displayname }}</b>: {{ .Message }}";
                    "m.emote" = "* <b>{{ .Sender.Displayname }}</b> {{ .Message }}";
                    "m.file" = "<b>{{ .Sender.Displayname }}</b> sent a file";
                    "m.image" = "<b>{{ .Sender.Displayname }}</b> sent an image";
                    "m.audio" = "<b>{{ .Sender.Displayname }}</b> sent an audio file";
                    "m.video" = "<b>{{ .Sender.Displayname }}</b> sent a video";
                    "m.location" = "<b>{{ .Sender.Displayname }}</b> sent a location";
                    "m.sticker" = "<b>{{ .Sender.Displayname }}</b> sent a sticker";
                  };
                };
              };

              # Logging
              logging = {
                min_level = "info";
                writers = [
                  {
                    type = "stdout";
                    format = "pretty-colored";
                  }
                ];
              };
            };
          };
        };
      };
    };
  };
}

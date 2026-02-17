{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;

  # User provisioning script for declarative Matrix user creation
  userProvisioningScript = ''
    #!/bin/sh
    set -e

    SYNAPSE_URL="http://synapse-matrix-synapse.${namespace}.svc.cluster.local:8008"
    SHARED_SECRET="$REGISTRATION_SHARED_SECRET"

    echo "Checking if user provisioning has already completed..."
    # Check if all users already exist - if so, exit early
    admin_exists=$(curl -s -o /dev/null -w "%{http_code}" "$SYNAPSE_URL/_matrix/client/v3/register/available?username=admin" || echo "000")
    jose_exists=$(curl -s -o /dev/null -w "%{http_code}" "$SYNAPSE_URL/_matrix/client/v3/register/available?username=jose" || echo "000")
    zeh_exists=$(curl -s -o /dev/null -w "%{http_code}" "$SYNAPSE_URL/_matrix/client/v3/register/available?username=zeh" || echo "000")

    if [ "$admin_exists" = "400" ] && [ "$jose_exists" = "400" ] && [ "$zeh_exists" = "400" ]; then
      echo "All users already exist. Provisioning already completed, skipping..."
      exit 0
    fi

    echo "Waiting for Synapse to be ready..."
    until curl -sf "$SYNAPSE_URL/_matrix/client/versions" > /dev/null 2>&1; do
      echo "Synapse not ready, waiting..."
      sleep 5
    done
    echo "Synapse is ready!"

    generate_mac() {
      local nonce="$1" user="$2" password="$3" admin="$4"
      if [ "$admin" = "true" ]; then admin_str="admin"; else admin_str="notadmin"; fi
      printf "%s\0%s\0%s\0%s" "$nonce" "$user" "$password" "$admin_str" | \
        openssl dgst -sha1 -hmac "$SHARED_SECRET" | awk '{print $2}'
    }

    register_user() {
      local username="$1" password="$2" displayname="$3" admin="$4"
      echo "Processing user: $username"

      status=$(curl -s -o /dev/null -w "%{http_code}" "$SYNAPSE_URL/_matrix/client/v3/register/available?username=$username")
      if [ "$status" = "400" ]; then
        echo "User $username already exists, skipping..."
        return 0
      fi

      nonce=$(curl -sf "$SYNAPSE_URL/_synapse/admin/v1/register" | jq -r '.nonce')
      if [ -z "$nonce" ] || [ "$nonce" = "null" ]; then
        echo "Failed to get nonce for $username"
        return 1
      fi

      mac=$(generate_mac "$nonce" "$username" "$password" "$admin")

      response=$(curl -sf -X POST "$SYNAPSE_URL/_synapse/admin/v1/register" \
        -H "Content-Type: application/json" \
        -d "{
          \"nonce\": \"$nonce\",
          \"username\": \"$username\",
          \"password\": \"$password\",
          \"displayname\": \"$displayname\",
          \"admin\": $admin,
          \"mac\": \"$mac\"
        }" 2>&1) || true

      if echo "$response" | grep -q "user_id"; then
        echo "Successfully created user: $username"
      elif echo "$response" | grep -q "User ID already taken"; then
        echo "User $username already exists"
      else
        echo "Failed to create user $username: $response"
      fi
    }

    echo "Starting user provisioning..."
    register_user "admin" "$ADMIN_PASSWORD" "Admin" true
    register_user "jose" "$JOSE_PASSWORD" "Jose Victor" false
    register_user "zeh" "$ZEH_PASSWORD" "Zeh" true
    echo "User provisioning complete!"
  '';
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
              # NOTE: mautrix-whatsapp does NOT support room_name_template (GitHub issue #795 open)
              # Only user displayname_template is available in the network section above
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
                  "@zeh:josevictor.me" = "admin";
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

        "mautrix-discord-registration" = {
          metadata = {
            namespace = namespace;
          };
          stringData = {
            "registration.yaml" = kubenix.lib.toYamlStr {
              id = "discord";
              url = "http://mautrix-discord.${namespace}.svc.cluster.local:29334";
              as_token = kubenix.lib.secretsInlineFor "mautrix_discord_as_token";
              hs_token = kubenix.lib.secretsInlineFor "mautrix_discord_hs_token";
              sender_localpart = "discordbot";
              namespaces = {
                users = [
                  {
                    exclusive = true;
                    regex = "@discordbot:josevictor\\.me";
                  }
                  {
                    exclusive = true;
                    regex = "@discord_.*:josevictor\\.me";
                  }
                ];
                rooms = [ ];
                aliases = [ ];
              };
            };
          };
        };

        "mautrix-discord-config" = {
          metadata = {
            namespace = namespace;
          };
          stringData = {
            "config.yaml" = kubenix.lib.toYamlStr {
              homeserver = {
                address = "http://synapse-matrix-synapse.${namespace}.svc.cluster.local:8008";
                domain = "josevictor.me";
              };
              appservice = {
                address = "http://mautrix-discord.${namespace}.svc.cluster.local:29334";
                hostname = "0.0.0.0";
                port = 29334;
                id = "discord";
                bot = {
                  username = "discordbot";
                  displayname = "Discord Bridge Bot";
                };
                as_token = kubenix.lib.secretsInlineFor "mautrix_discord_as_token";
                hs_token = kubenix.lib.secretsInlineFor "mautrix_discord_hs_token";
                database = {
                  type = "postgres";
                  uri = "postgres://postgres:${kubenix.lib.secretsInlineFor "postgresql_admin_password"}@postgresql-18-hl.${namespace}.svc.cluster.local:5432/mautrix_discord?sslmode=disable";
                };
              };
              bridge = {
                username_template = "discord_{{.}}";
                # Room naming pattern: discord/servername/channelname
                channel_name_template = "discord/{{.GuildName}}/{{if or (eq .Type 3) (eq .Type 4)}}{{.Name}}{{else}}{{.Name}}{{end}}";
                guild_name_template = "{{.Name}}";
                command_prefix = "!dc";
                permissions = {
                  "*" = "relay";
                  "@jose:josevictor.me" = "admin";
                  "@admin:josevictor.me" = "admin";
                  "@zeh:josevictor.me" = "admin";
                };
                encryption = {
                  allow = false;
                };
                relay = {
                  enabled = true;
                  message_formats = {
                    "m.text" = "<b>{{ .Sender.Displayname }}</b>: {{ .Message }}";
                    "m.notice" = "<b>{{ .Sender.Displayname }}</b>: {{ .Message }}";
                  };
                };
              };
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

        "mautrix-slack-registration" = {
          metadata = {
            namespace = namespace;
          };
          stringData = {
            "registration.yaml" = kubenix.lib.toYamlStr {
              id = "slack";
              url = "http://mautrix-slack.${namespace}.svc.cluster.local:29333";
              as_token = kubenix.lib.secretsInlineFor "mautrix_slack_as_token";
              hs_token = kubenix.lib.secretsInlineFor "mautrix_slack_hs_token";
              sender_localpart = "slackbot";
              namespaces = {
                users = [
                  {
                    exclusive = true;
                    regex = "@slackbot:josevictor\\.me";
                  }
                  {
                    exclusive = true;
                    regex = "@slack_.*:josevictor\\.me";
                  }
                ];
                rooms = [ ];
                aliases = [ ];
              };
            };
          };
        };

        "mautrix-slack-config" = {
          metadata = {
            namespace = namespace;
          };
          stringData = {
            "config.yaml" = kubenix.lib.toYamlStr {
              homeserver = {
                address = "http://synapse-matrix-synapse.${namespace}.svc.cluster.local:8008";
                domain = "josevictor.me";
              };

              database = {
                type = "postgres";
                uri = "postgres://postgres:${kubenix.lib.secretsInlineFor "postgresql_admin_password"}@postgresql-18-hl.${namespace}.svc.cluster.local:5432/mautrix_slack?sslmode=disable";
              };

              appservice = {
                address = "http://mautrix-slack.${namespace}.svc.cluster.local:29333";
                hostname = "0.0.0.0";
                port = 29333;
                id = "slack";
                bot = {
                  username = "slackbot";
                  displayname = "Slack Bridge Bot";
                };
                as_token = kubenix.lib.secretsInlineFor "mautrix_slack_as_token";
                hs_token = kubenix.lib.secretsInlineFor "mautrix_slack_hs_token";
                username_template = "slack_{{.}}";
              };

              # Slack connector settings (bridgev2 format)
              connector = {
                # Room naming pattern: slack/workspacename/channelname
                channel_name_template = "slack/{{.Team.Name}}/{{.Name}}";
                team_name_template = "{{.Name}}";
              };

              bridge = {
                command_prefix = "!slack";
                permissions = {
                  "*" = "relay";
                  "@jose:josevictor.me" = "admin";
                  "@admin:josevictor.me" = "admin";
                  "@zeh:josevictor.me" = "admin";
                };
                relay = {
                  enabled = false;
                };
                encryption = {
                  allow = false;
                };
              };

              backfill = {
                enabled = false;
              };

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

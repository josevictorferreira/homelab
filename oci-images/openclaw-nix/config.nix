# oci-images/openclaw-nix/config.nix
# OpenClaw gateway configuration as Nix attrset
# Rendered to JSON at build time. ${ENV} placeholders are substituted at runtime by entrypoint.sh
{
  agents = {
    list = [
      {
        id = "main";
        identity = {
          name = "Mel";
          theme = "minha fiel assistente";
          emoji = "🐕";
        };
      }
    ];
    defaults = {
      workspace = "/state/workspace";
      model.primary = "kimi-coding/k2p5";
      userTimezone = "America/Sao_Paulo";
      timeoutSeconds = 600;
      memorySearch = {
        provider = "gemini";
        model = "gemini-embedding-001";
      };
    };
  };

  session = {
    scope = "per-sender";
    reset = {
      mode = "daily";
      atHour = 4;
    };
    idleMinutes = 60;
  };

  tools = {
    allow = [
      "exec"
      "read"
      "write"
      "edit"
      "process"
      "web_search"
      "web_fetch"
      "canvas"
      "nodes"
      "message"
      "cron"
      "gateway"
      "browser"
      "sessions_list"
      "sessions_history"
      "sessions_send"
      "sessions_spawn"
      "session_status"
      "agents_list"
    ];
    deny = [ ];
    web.search = {
      provider = "perplexity";
      perplexity = {
        baseUrl = "https://openrouter.ai/api/v1";
        model = "perplexity/sonar-pro";
        apiKey = "\${OPENROUTER_API_KEY}";
      };
    };
  };

  messages.tts = {
    auto = "always";
    provider = "elevenlabs";
    summaryModel = "google/gemini-2.0-flash";
    elevenlabs = {
      apiKey = "\${ELEVENLABS_API_KEY}";
      voiceId = "GOkMqfyKMLVUcYfO2WbB";
      modelId = "eleven_multilingual_v2";
      seed = 91;
      voiceSettings = {
        stability = 0.5;
        similarityBoost = 0.75;
        style = 0.0;
        useSpeakerBoost = true;
        speed = 1.0;
      };
    };
  };

  plugins.allow = [
    "matrix"
    "whatsapp"
  ];

  gateway = {
    mode = "local";
    port = 18789;
    bind = "lan";
    controlUi = {
      dangerouslyAllowHostHeaderOriginFallback = true;
    };
  };

  logging = {
    level = "debug";
    file = "/logs/openclaw.log";
  };

  channels = {
    matrix = {
      enabled = true;
      homeserver = "http://synapse-matrix-synapse:8008";
      accessToken = "\${OPENCLAW_MATRIX_TOKEN}";
      userId = "@openclaw:josevictor.me";
      encryption = false;
      dm = {
        policy = "allowlist";
        allowFrom = [
          "@jose:josevictor.me"
          "@admin:josevictor.me"
          "@zeh:josevictor.me"
        ];
      };
      autoJoin = "allowlist";
      autoJoinAllowList = [
        "@jose:josevictor.me"
        "@admin:josevictor.me"
        "@zeh:josevictor.me"
      ];
      mediaMaxMb = 150;
      groupPolicy = "disabled";
    };
    whatsapp = {
      dmPolicy = "allowlist";
      allowFrom = [ "\${WHATSAPP_NUMBER}" ];
      groupPolicy = "allowlist";
      groupAllowFrom = [ "\${WHATSAPP_NUMBER}" ];
      ackReaction = {
        emoji = "👀";
        direct = true;
        group = "mentions";
      };
    };
  };

  env = {
    MOONSHOT_API_KEY = "\${MOONSHOT_API_KEY}";
    ELEVENLABS_API_KEY = "\${ELEVENLABS_API_KEY}";
    OPENROUTER_API_KEY = "\${OPENROUTER_API_KEY}";
  };

  models = {
    mode = "merge";
    providers."kimi-coding" = {
      baseUrl = "https://api.kimi.com/coding";
      apiKey = "\${MOONSHOT_API_KEY}";
      api = "anthropic-messages";
      models = [
        {
          id = "k2p5";
          name = "Kimi K2.5";
          reasoning = false;
          input = [ "text" ];
          contextWindow = 256000;
          maxTokens = 8192;
        }
      ];
    };
  };
}

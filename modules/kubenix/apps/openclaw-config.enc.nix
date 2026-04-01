{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  configData = {
    env = {
      ALIBABA_CODING_PLAN_API_KEY = "\${ALIBABA_CODING_PLAN_API_KEY}";
      COPILOT_GITHUB_TOKEN = "\${COPILOT_GITHUB_TOKEN}";
      ELEVENLABS_API_KEY = "\${ELEVENLABS_API_KEY}";
      GEMINI_API_KEY = "\${GEMINI_API_KEY}";
      KIRA_MATRIX_TOKEN = "\${KIRA_MATRIX_TOKEN}";
      LUNA_MATRIX_TOKEN = "\${LUNA_MATRIX_TOKEN}";
      MEL_MATRIX_TOKEN = "\${MEL_MATRIX_TOKEN}";
      SPIKE_MATRIX_TOKEN = "\${SPIKE_MATRIX_TOKEN}";
      MINIMAX_API_KEY = "\${MINIMAX_API_KEY}";
      KIMI_API_KEY = "\${KIMI_API_KEY}";
      OPENROUTER_API_KEY = "\${OPENROUTER_API_KEY}";
      Z_AI_API_KEY = "\${Z_AI_API_KEY}";
    };
    browser = {
      enabled = true;
      evaluateEnabled = true;
      headless = true;
      executablePath = "/bin/chromium";
      noSandbox = true;
    };
    models = {
      mode = "merge";
      providers = {
        alibaba-coding-plan = {
          baseUrl = "https://coding-intl.dashscope.aliyuncs.com/v1";
          apiKey = "\${ALIBABA_CODING_PLAN_API_KEY}";
          api = "openai-completions";
          models = [
            {
              id = "qwen3.5-plus";
              name = "qwen3.5-plus";
              reasoning = false;
              input = [
                "text"
                "image"
              ];
              cost = {
                input = 0;
                output = 0;
                cacheRead = 0;
                cacheWrite = 0;
              };
              contextWindow = 1000000;
              maxTokens = 65536;
            }
            {
              id = "qwen3-max-2026-01-23";
              name = "qwen3-max-2026-01-23";
              reasoning = false;
              input = [ "text" ];
              cost = {
                input = 0;
                output = 0;
                cacheRead = 0;
                cacheWrite = 0;
              };
              contextWindow = 262144;
              maxTokens = 65536;
            }
            {
              id = "qwen3-coder-next";
              name = "qwen3-coder-next";
              reasoning = false;
              input = [ "text" ];
              cost = {
                input = 0;
                output = 0;
                cacheRead = 0;
                cacheWrite = 0;
              };
              contextWindow = 262144;
              maxTokens = 65536;
            }
            {
              id = "qwen3-coder-plus";
              name = "qwen3-coder-plus";
              reasoning = false;
              input = [ "text" ];
              cost = {
                input = 0;
                output = 0;
                cacheRead = 0;
                cacheWrite = 0;
              };
              contextWindow = 1000000;
              maxTokens = 65536;
            }
          ];
        };
        moonshotai = {
          baseUrl = "https://api.kimi.com/coding";
          apiKey = "\${KIMI_API_KEY}";
          api = "anthropic-messages";
          models = [
            {
              id = "k2p5";
              name = "Kimi K2.5";
              reasoning = true;
              input = [
                "text"
                "image"
              ];
              contextWindow = 262144;
              maxTokens = 8192;
            }
          ];
        };
        minimax = {
          baseUrl = "https://api.minimaxi.com/anthropic";
          apiKey = "\${MINIMAX_API_KEY}";
          api = "anthropic-messages";
          models = [
            {
              id = "MiniMax-M2.5";
              name = "MiniMax M2.5";
              reasoning = true;
              input = [ "text" ];
              cost = {
                input = 15;
                output = 60;
                cacheRead = 2;
                cacheWrite = 10;
              };
              contextWindow = 200000;
              maxTokens = 8192;
            }
            {
              id = "MiniMax-M2.7";
              name = "MiniMax M2.7";
              reasoning = true;
              input = [ "text" ];
              cost = {
                input = 15;
                output = 60;
                cacheRead = 2;
                cacheWrite = 10;
              };
              contextWindow = 200000;
              maxTokens = 8192;
            }
          ];
        };
        zai-coding-plan = {
          baseUrl = "https://api.z.ai/api/anthropic";
          apiKey = "\${Z_AI_API_KEY}";
          api = "anthropic-messages";
          models = [
            {
              id = "glm-5";
              name = "GLM-5";
              reasoning = true;
              input = [ "text" ];
              contextWindow = 120000;
              maxTokens = 8192;
            }
            {
              id = "glm-5.1";
              name = "GLM-5.1";
              reasoning = true;
              input = [ "text" ];
              contextWindow = 120000;
              maxTokens = 8192;
            }
            {
              id = "glm-5-turbo";
              name = "GLM-5 Turbo";
              reasoning = true;
              input = [ "text" ];
              contextWindow = 120000;
              maxTokens = 8192;
            }
          ];
        };
      };
    };
    agents = {
      defaults = {
        model = {
          primary = "minimax/MiniMax-M2.7";
          fallbacks = [
            "moonshotai/k2p5"
            "zai-coding-plan/glm-5.1"
            "alibaba-coding-plan/qwen3.5-plus"
          ];
        };
        imageModel = {
          primary = "github-copilot/gemini-3-flash-preview";
          fallbacks = [
            "alibaba-coding-plan/qwen3.5-plus"
            "moonshotai/k2p5"
          ];
        };
        userTimezone = "America/Sao_Paulo";
        memorySearch = {
          enabled = true;
          sources = [
            "memory"
            "sessions"
          ];
          extraPaths = [ ".learnings" ];
          experimental = {
            sessionMemory = true;
          };
          provider = "gemini";
          model = "gemini-embedding-001";
          store = {
            vector = {
              enabled = true;
            };
          };
          query = {
            hybrid = {
              enabled = true;
            };
          };
        };
        contextPruning = {
          mode = "cache-ttl";
          ttl = "30m";
        };
        compaction = {
          reserveTokensFloor = 20000;
          memoryFlush = {
            enabled = true;
            softThresholdTokens = 4000;
            prompt = "Write any lasting notes to memory/YYYY-MM-DD.md; reply with NO_REPLY if nothing to store.";
            systemPrompt = "Session nearing compaction. Store durable memories now.";
          };
        };
        humanDelay = {
          mode = "natural";
        };
        timeoutSeconds = 600;
        subagents = {
          maxConcurrent = 4;
          archiveAfterMinutes = 60;
          model = "zai-coding-plan/glm-5-turbo";
          runTimeoutSeconds = 900;
        };
        sandbox = {
          browser = {
            enabled = false;
            headless = true;
          };
        };
      };
      list = [
        {
          id = "mel";
          workspace = "/home/node/.openclaw/workspace-mel";
          identity = {
            name = "Mel";
            theme = "minha fiel assistente";
            emoji = "🐕";
            avatar = "avatars/mel.png";
          };
          model = {
            primary = "moonshotai/k2p5";
            fallbacks = [
              "zai-coding-plan/glm-5-turbo"
              "minimax/MiniMax-M2.5"
              "alibaba-coding-plan/qwen3.5-plus"
            ];
          };
        }
        {
          id = "kira";
          workspace = "/home/node/.openclaw/workspace-kira";
          identity = {
            name = "Kira";
            theme = "minha fiel contadora";
            emoji = "🐕";
            avatar = "avatars/kira.png";
          };
          model = {
            primary = "zai-coding-plan/glm-5-turbo";
            fallbacks = [
              "minimax/MiniMax-M2.7"
              "moonshotai/k2p5"
              "alibaba-coding-plan/qwen3.5-plus"
            ];
          };
          tools = {
            deny = [
              "gateway"
              "nodes"
              "agents_list"
            ];
          };
        }
        {
          id = "luna";
          workspace = "/home/node/.openclaw/workspace-luna";
          identity = {
            name = "Luna";
            theme = "minha fiel companheira";
            emoji = "🐕";
            avatar = "avatars/luna.png";
          };
          model = {
            primary = "alibaba-coding-plan/qwen3.5-plus";
            fallbacks = [
              "zai-coding-plan/glm-5-turbo"
              "moonshotai/k2p5"
              "minimax/MiniMax-M2.5"
            ];
          };
        }
        {
          id = "spike";
          workspace = "/home/node/.openclaw/workspace-spike";
          identity = {
            name = "Spike";
            theme = "meu fiel companheiro";
            emoji = "🐕";
          };
          model = {
            primary = "minimax/MiniMax-M2.7";
            fallbacks = [
              "moonshotai/k2p5"
              "zai-coding-plan/glm-5.1"
              "alibaba-coding-plan/qwen3.5-plus"
            ];
          };
        }
        {
          id = "spare";
          workspace = "/home/node/.openclaw/workspace-spare";
          identity = {
            name = "Spare";
            theme = "meu nó reserva";
            emoji = "⚙️";
          };
          tools = {
            exec = {
              host = "node";
              node = "nixos-desktop";
            };
          };
        }
      ];
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
        "image"
        "message"
        "gateway"
        "cron"
        "browser"
        "sessions_list"
        "sessions_history"
        "sessions_send"
        "sessions_spawn"
        "session_status"
        "agents_list"
      ];
      deny = [ ];
      web = {
        search = {
          provider = "perplexity";
          perplexity = {
            apiKey = "\${OPENROUTER_API_KEY}";
            baseUrl = "https://openrouter.ai/api/v1";
            model = "perplexity/sonar-pro";
          };
        };
      };
      media = {
        concurrency = 2;
        audio = {
          enabled = true;
          models = [
            {
              type = "cli";
              command = "sh";
              args = [
                "-c"
                "curl -s -X POST https://api.elevenlabs.io/v1/speech-to-text -H \\\"xi-api-key: \${ELEVENLABS_API_KEY}\\\" -F model_id=scribe_v2 -F \\\"file=@{{`{{MediaPath}}`}}\\\" -F tag_audio_events=true -F language_code=por | jq -r .text"
              ];
            }
          ];
        };
        video = {
          enabled = true;
          maxBytes = 52428800;
          models = [
            {
              provider = "github-copilot";
              model = "gemini-3-flash-preview";
            }
          ];
        };
      };
    };
    bindings = [
      {
        agentId = "spike";
        match = {
          channel = "matrix";
          accountId = "@spike";
        };
      }
      {
        agentId = "kira";
        match = {
          channel = "matrix";
          accountId = "@kira";
        };
      }
      {
        agentId = "luna";
        match = {
          channel = "matrix";
          accountId = "@luna";
        };
      }
      {
        agentId = "mel";
        match = {
          channel = "matrix";
          accountId = "@mel";
        };
      }
    ];
    broadcast = {
      strategy = "parallel";
    };
    messages = {
      removeAckAfterReply = true;
      ackReactionScope = "all";
      tts = {
        auto = "inbound";
        provider = "elevenlabs";
        summaryModel = "moonshotai/k2p5";
        providers = {
          elevenlabs = {
            apiKey = "\${ELEVENLABS_API_KEY}";
            voiceId = "GOkMqfyKMLVUcYfO2WbB";
            modelId = "eleven_v3";
            seed = 91;
            voiceSettings = {
              stability = 0.5;
              similarityBoost = 0.75;
              style = 0;
              useSpeakerBoost = true;
              speed = 1;
            };
          };
        };
      };
      commands = {
        native = "auto";
        nativeSkills = "auto";
        restart = true;
        ownerDisplay = "raw";
      };
      session = {
        scope = "per-sender";
        idleMinutes = 60;
        reset = {
          mode = "daily";
          atHour = 4;
        };
      };
      channels = {
        whatsapp = {
          enabled = true;
          dmPolicy = "allowlist";
          allowFrom = [ "+554388109393" ];
          groupAllowFrom = [ "+554388109393" ];
          groupPolicy = "allowlist";
          ackReaction = {
            emoji = "👀";
            direct = true;
            group = "mentions";
          };
          debounceMs = 0;
          mediaMaxMb = 50;
        };
        matrix = {
          enabled = true;
          autoJoin = "always";
          groups = {
            "*" = {
              allow = true;
              requireMention = false;
            };
          };
          dm = {
            allowFrom = [ "@zeh:josevictor.me" ];
            policy = "allowlist";
          };
          encryption = true;
          mediaMaxMb = 150;
          accounts = {
            mel = {
              name = "Mel";
              homeserver = "https://matrix.josevictor.me";
              accessToken = "\${MEL_MATRIX_TOKEN}";
              userId = "@mel:josevictor.me";
              allowPrivateNetwork = true;
            };
            kira = {
              name = "Kira";
              homeserver = "https://matrix.josevictor.me";
              accessToken = "\${KIRA_MATRIX_TOKEN}";
              userId = "@kira:josevictor.me";
              allowPrivateNetwork = true;
            };
            luna = {
              name = "Luna";
              homeserver = "https://matrix.josevictor.me";
              accessToken = "\${LUNA_MATRIX_TOKEN}";
              userId = "@luna:josevictor.me";
              allowPrivateNetwork = true;
            };
            spike = {
              name = "Spike";
              homeserver = "https://matrix.josevictor.me";
              accessToken = "\${SPIKE_MATRIX_TOKEN}";
              userId = "@spike:josevictor.me";
              allowPrivateNetwork = true;
            };
            default = {
              groupPolicy = "allowlist";
              groupAllowFrom = [ "@zeh:josevictor.me" ];
              homeserver = "https://matrix.josevictor.me";
              allowPrivateNetwork = true;
            };
          };
        };
      };
      talk = {
        voiceId = "GOkMqfyKMLVUcYfO2WbB";
        modelId = "eleven_v3";
        outputFormat = "mp3_44100_128";
        apiKey = "\${ELEVENLABS_API_KEY}";
        interruptOnSpeech = true;
      };
      gateway = {
        port = 18789;
        mode = "local";
        bind = "lan";
        controlUi = {
          dangerouslyAllowHostHeaderOriginFallback = true;
        };
      };
      logging = {
        level = "debug";
      };
      memory = {
        backend = "builtin";
        citations = "on";
      };
      skills = {
        allowBundled = [ ];
        install = {
          nodeManager = "npm";
        };
      };
      plugins = {
        enabled = true;
        allow = [
          "matrix"
          "whatsapp"
          "memory-core"
          "lobster"
        ];
        slots = {
          memory = "memory-core";
        };
        entries = {
          matrix = {
            enabled = true;
          };
          lobster = {
            enabled = true;
          };
        };
      };
    };
  };
in
{
  kubernetes.resources.secrets.openclaw-config = {
    metadata.namespace = namespace;
    stringData = {
      NODE_ENV = "production";
      OPENCLAW_DATA_DIR = "/home/node/.openclaw";
      OPENCLAW_CONFIG_PATH = "/home/node/.openclaw/openclaw.json";
      OPENCLAW_GATEWAY_TOKEN = kubenix.lib.secretsFor "openclaw_gateway_token";
      TS_AUTHKEY = kubenix.lib.secretsFor "openclaw_tailscale_authkey";
      GEMINI_API_KEY = kubenix.lib.secretsFor "gemini_api_key";
      OPENROUTER_API_KEY = kubenix.lib.secretsFor "openrouter_api_key_openclaw";
      Z_AI_API_KEY = kubenix.lib.secretsFor "z_ai_api_key";
      COPILOT_GITHUB_TOKEN = kubenix.lib.secretsFor "copilot_github_token";
      MINIMAX_API_KEY = kubenix.lib.secretsFor "minimax_api_key";
      KIMI_API_KEY = kubenix.lib.secretsFor "moonshot_api_key";
      OPENCLAW_MATRIX_TOKEN = kubenix.lib.secretsFor "openclaw_matrix_token";
      MEL_MATRIX_TOKEN = kubenix.lib.secretsFor "mel_matrix_token";
      KIRA_MATRIX_TOKEN = kubenix.lib.secretsFor "kira_matrix_token";
      LUNA_MATRIX_TOKEN = kubenix.lib.secretsFor "luna_matrix_token";
      SPIKE_MATRIX_TOKEN = kubenix.lib.secretsFor "spike_matrix_token";
      ELEVENLABS_API_KEY = kubenix.lib.secretsFor "elevenlabs_api_key";
      GITHUB_TOKEN = kubenix.lib.secretsFor "github_token";
      SEARXNG_URL = kubenix.lib.secretsFor "searxng_url";
      WHATSAPP_NUMBER = kubenix.lib.secretsFor "whatsapp_number";
      WHATSAPP_BOT_NUMBER = kubenix.lib.secretsFor "whatsapp_bot_number";
      ALIBABA_CODING_PLAN_API_KEY = kubenix.lib.secretsFor "alibaba_coding_plan_api_key";
    };
  };

  kubernetes.resources.configMaps.openclaw-config = {
    metadata.namespace = namespace;
    data = {
      "config-template.json" = builtins.toJSON configData;
    };
  };
}

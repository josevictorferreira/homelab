{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
  configName = "openclaw-test-config";
  configData = {
    env = {
      OPENAI_API_KEY = "\${OPENAI_API_KEY}";
      ALIBABA_CODING_PLAN_API_KEY = "\${ALIBABA_CODING_PLAN_API_KEY}";
      COPILOT_GITHUB_TOKEN = "\${COPILOT_GITHUB_TOKEN}";
      ELEVENLABS_API_KEY = "\${ELEVENLABS_API_KEY}";
      GEMINI_API_KEY = "\${GEMINI_API_KEY}";
      MINIMAX_API_KEY = "\${MINIMAX_API_KEY}";
      KIMI_API_KEY = "\${KIMI_API_KEY}";
      OPENROUTER_API_KEY = "\${OPENROUTER_API_KEY}";
      Z_AI_API_KEY = "\${Z_AI_API_KEY}";
    };

    logging = {
      level = "info";
      consoleLevel = "info";
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
              api = "openai-completions";
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
              api = "openai-completions";
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
              api = "openai-completions";
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
              api = "openai-completions";
            }
            {
              id = "qwen3.6-plus";
              name = "Qwen3.6 Plus";
              reasoning = true;
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
              api = "openai-completions";
            }
            {
              id = "glm-5";
              name = "GLM-5";
              reasoning = true;
              input = [ "text" ];
              cost = {
                input = 0;
                output = 0;
                cacheRead = 0;
                cacheWrite = 0;
              };
              contextWindow = 120000;
              maxTokens = 8192;
              api = "openai-completions";
            }
          ];
        };

        minimax = {
          baseUrl = "https://api.minimax.io/v1";
          apiKey = "\${MINIMAX_API_KEY}";
          api = "openai-completions";
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

        kimi-coding = {
          baseUrl = "https://api.kimi.com/coding/";
          apiKey = "\${KIMI_API_KEY}";
          api = "anthropic-messages";
          models = [
            {
              id = "k2p6";
              name = "Kimi K2.6";
              reasoning = false;
              input = [ "text" ];
              cost = {
                input = 0;
                output = 0;
                cacheRead = 0;
                cacheWrite = 0;
              };
              contextWindow = 256000;
              maxTokens = 8192;
            }
          ];
        };
      };
    };

    agents.defaults = {
      model = {
        primary = "kimi-coding/k2p6";
        fallbacks = [
          "kimi-coding/k2p6"
          "alibaba-coding-plan/glm-5"
          "alibaba-coding-plan/qwen3.5-plus"
        ];
      };
      imageModel = {
        primary = "github-copilot/gemini-3-flash-preview";
        fallbacks = [
          "alibaba-coding-plan/qwen3.5-plus"
          "kimi-coding/k2p6"
        ];
      };
      userTimezone = "America/Sao_Paulo";
      timeoutSeconds = 600;
      subagents = {
        maxConcurrent = 4;
        archiveAfterMinutes = 60;
        model = "alibaba-coding-plan/glm-5";
        runTimeoutSeconds = 900;
      };
      sandbox.browser = {
        enabled = false;
        headless = true;
      };
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
        "gateway"
        "cron"
        "sessions_list"
        "sessions_history"
        "sessions_send"
        "sessions_spawn"
        "session_status"
        "agents_list"
      ];
      deny = [ ];
      exec = {
        security = "full";
        ask = "off";
      };
      web.search.provider = "perplexity";
      elevated.enabled = false;
    };

    gateway = {
      port = 18789;
      mode = "local";
      bind = "lan";
      controlUi = {
        allowedOrigins = [
          "http://localhost:18789"
          "http://127.0.0.1:18789"
          "https://openclaw-test.${homelab.domain}"
          "http://openclaw-test.${homelab.domain}"
        ];
        dangerouslyAllowHostHeaderOriginFallback = true;
      };
      auth = {
        mode = "token";
        token = "\${OPENCLAW_GATEWAY_TOKEN}";
        rateLimit = {
          maxAttempts = 10;
          windowMs = 60000;
          lockoutMs = 300000;
        };
      };
    };

    plugins = {
      enabled = true;
      allow = [
        "github-copilot"
        "google"
        "kimi"
        "minimax"
        "openai"
        "perplexity"
      ];
      entries = {
        github-copilot.enabled = true;
        google.enabled = true;
        kimi.enabled = true;
        minimax.enabled = true;
        openai.enabled = true;
        perplexity = {
          enabled = true;
          config.webSearch = {
            apiKey = "\${OPENROUTER_API_KEY}";
            baseUrl = "https://openrouter.ai/api/v1";
            model = "perplexity/sonar-pro";
          };
        };
      };
    };
  };
in
{
  kubernetes.resources.secrets.${configName} = {
    metadata = {
      name = configName;
      inherit namespace;
    };
    stringData = {
      NODE_ENV = "production";
      OPENCLAW_DATA_DIR = "/root/.openclaw";
      OPENCLAW_STATE_DIR = "/root/.openclaw";
      OPENCLAW_CONFIG_PATH = "/root/.openclaw/openclaw.json";
      OPENCLAW_GATEWAY_TOKEN = kubenix.lib.secretsFor "openclaw_gateway_token";
      GEMINI_API_KEY = kubenix.lib.secretsFor "gemini_api_key";
      OPENROUTER_API_KEY = kubenix.lib.secretsFor "openrouter_api_key_openclaw";
      Z_AI_API_KEY = kubenix.lib.secretsFor "z_ai_api_key";
      COPILOT_GITHUB_TOKEN = kubenix.lib.secretsFor "copilot_github_token";
      MINIMAX_API_KEY = kubenix.lib.secretsFor "minimax_api_key";
      KIMI_API_KEY = kubenix.lib.secretsFor "moonshot_api_key";
      OPENAI_API_KEY = kubenix.lib.secretsFor "openai_api_key";
      ELEVENLABS_API_KEY = kubenix.lib.secretsFor "elevenlabs_api_key";
      ALIBABA_CODING_PLAN_API_KEY = kubenix.lib.secretsFor "alibaba_coding_plan_api_key";
    };
  };

  kubernetes.resources.configMaps.${configName} = {
    metadata = {
      name = configName;
      inherit namespace;
    };
    data."config-template.json" = builtins.toJSON configData;
  };
}

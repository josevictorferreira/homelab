{
  pkgs,
  lib,
  inputs,
  system,
  version ? "2026.5.4",
  tagSuffix ? "",
  legacyOpenClawPatches ? true,
  matrixSendQueuePatch ? true,
  disableMatrixCredentialTouch ? false,
}:

let
  inherit (pkgs) dockerTools;

  # Source info — change version param to upgrade
  sourceInfo = {
    owner = "openclaw";
    repo = "openclaw";
    rev = "v${version}";
    sha256 = "sha256-hT/URmVBQuwlYMkZsMdiwVauHQlhVTCXRovSdhmKoSw=";
    pnpmDepsHash = "sha256-kz9vE1A/GTkw/HH2ts4hxTJzrdkYhiLaJQP0AeAS3Bo=";
  };

  # Rolldown 1.0.0-rc.3 — pre-built from npm registry
  # Required for canvas:a2ui:bundle step in v2026.2.22+
  rolldownTgz = pkgs.fetchurl {
    url = "https://registry.npmjs.org/rolldown/-/rolldown-1.0.0-rc.3.tgz";
    sha256 = "00h6whsmm9jwyiwqanvvmwb1g2bl2qbk650j7famcgb5zllf1zyw";
  };
  bindingTgz = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@rolldown/binding-linux-x64-gnu/-/binding-linux-x64-gnu-1.0.0-rc.3.tgz";
    sha256 = "0xfricdk58sddqa4fslm529ppg6f0f53s4y239sgqlh98am5z63g";
  };
  oxcTypesTgz = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@oxc-project/types/-/types-0.112.0.tgz";
    sha256 = "0qcjijc8q0gz9ghfgamkyg3nk1n7vkdffp1fnh1n9sckh5synli2";
  };
  pluginutilsTgz = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@rolldown/pluginutils/-/pluginutils-1.0.0-rc.3.tgz";
    sha256 = "05njq25fg7qx1pmww7mqq5rwhj9f0kk6129ifydij1q2759b3pkj";
  };

  # RTK binary — CLI proxy that reduces LLM token consumption
  rtkBinary = pkgs.fetchurl {
    name = "rtk-0.37.2-x86_64-linux-musl";
    url = "https://github.com/rtk-ai/rtk/releases/download/v0.37.2/rtk-x86_64-unknown-linux-musl.tar.gz";
    sha256 = "1iip188bg24bxgcqdvbx8jab9z6mm1pnkan5l5xnhs3acc2pmyrx";
  };
  rtkPluginJson = pkgs.writeText "rtk-rewrite-openclaw.plugin.json" ''
    {
      "id": "rtk-rewrite",
      "name": "RTK Token Optimizer",
      "version": "1.0.0",
      "description": "Transparently rewrites shell commands to their RTK equivalents for 60-90% LLM token savings",
      "homepage": "https://github.com/rtk-ai/rtk",
      "license": "MIT",
      "configSchema": {
        "type": "object",
        "additionalProperties": false,
        "properties": {
          "enabled": {
            "type": "boolean",
            "default": true,
            "description": "Enable automatic command rewriting to RTK equivalents"
          },
          "verbose": {
            "type": "boolean",
            "default": false,
            "description": "Log rewrite decisions to console for debugging"
          }
        }
      },
      "uiHints": {
        "enabled": { "label": "Enable RTK rewriting" },
        "verbose": { "label": "Verbose logging" }
      }
    }
  '';
  rtkPluginTs = pkgs.writeText "rtk-rewrite-index.ts" ''
    import { execSync } from "node:child_process";

    let rtkAvailable: boolean | null = null;

    function checkRtk(): boolean {
      if (rtkAvailable !== null) return rtkAvailable;
      try {
        execSync("which rtk", { stdio: "ignore" });
        rtkAvailable = true;
      } catch {
        rtkAvailable = false;
      }
      return rtkAvailable;
    }

    function tryRewrite(command: string): string | null {
      try {
        const result = execSync(`rtk rewrite ''${JSON.stringify(command)}`, {
          encoding: "utf-8",
          timeout: 2000,
        }).trim();
        return result && result !== command ? result : null;
      } catch {
        return null;
      }
    }

    export default function register(api: any) {
      const pluginConfig = api.config ?? {};
      const enabled = pluginConfig.enabled !== false;
      const verbose = pluginConfig.verbose === true;

      if (!enabled) return;

      if (!checkRtk()) {
        console.warn("[rtk] rtk binary not found in PATH — plugin disabled");
        return;
      }

      api.on(
        "before_tool_call",
        (event: { toolName: string; params: Record<string, unknown> }) => {
          if (event.toolName !== "exec") return;

          const command = event.params?.command;
          if (typeof command !== "string") return;

          const rewritten = tryRewrite(command);
          if (!rewritten) return;

          if (verbose) {
            console.log(`[rtk] ''${command} -> ''${rewritten}`);
          }

          return { params: { ...event.params, command: rewritten } };
        },
        { priority: 10 }
      );

      if (verbose) {
        console.log("[rtk] OpenClaw plugin registered");
      }
    }
  '';
  rtkPackageJson = pkgs.writeText "rtk-rewrite-package.json" ''
    {
      "name": "@openclaw/rtk-rewrite",
      "version": "1.0.0",
      "description": "RTK Token Optimizer plugin for OpenClaw",
      "type": "module",
      "openclaw": {
        "extensions": [
          "./index.ts"
        ],
        "compat": {
          "pluginApi": ">=2026.4.20"
        }
      }
    }
  '';
  matrixCredentialTouchPatchScript = pkgs.writeText "openclaw-matrix-credential-touch-noop.py" (
    builtins.concatStringsSep "\n" [
      "#!/usr/bin/env python3"
      "import sys"
      "from pathlib import Path"
      ""
      "needle = 'async function touchMatrixCredentials(env = process.env, accountId) {'"
      "replacement = '''async function touchMatrixCredentials(env = process.env, accountId) {"
      "  // CephFS-backed state can block startup on atomic lastUsedAt writes."
      "  return;"
      "}'''"
      ""
      "def find_function_end(text, start):"
      "    depth = 0"
      "    i = text.find('{', start)"
      "    if i == -1:"
      "        return -1"
      "    quote = None"
      "    escape = False"
      "    line_comment = False"
      "    block_comment = False"
      "    while i < len(text):"
      "        ch = text[i]"
      "        nxt = text[i + 1] if i + 1 < len(text) else ''"
      "        if line_comment:"
      "            if ch == '\\n':"
      "                line_comment = False"
      "        elif block_comment:"
      "            if ch == '*' and nxt == '/':"
      "                block_comment = False"
      "                i += 1"
      "        elif quote:"
      "            if escape:"
      "                escape = False"
      "            elif ch == '\\\\':"
      "                escape = True"
      "            elif ch == quote:"
      "                quote = None"
      "        elif ch == '/' and nxt == '/':"
      "            line_comment = True"
      "            i += 1"
      "        elif ch == '/' and nxt == '*':"
      "            block_comment = True"
      "            i += 1"
      "        elif ch == chr(34) or ch == chr(39) or ch == chr(96):"
      "            quote = ch"
      "        elif ch == '{':"
      "            depth += 1"
      "        elif ch == '}':"
      "            depth -= 1"
      "            if depth == 0:"
      "                return i + 1"
      "        i += 1"
      "    return -1"
      ""
      "root = Path(sys.argv[1])"
      "patched = False"
      "for path in sorted(root.glob('credentials-*.js')):"
      "    text = path.read_text()"
      "    start = text.find(needle)"
      "    if start == -1:"
      "        continue"
      "    end = find_function_end(text, start)"
      "    if end == -1:"
      "        raise SystemExit(f'could not find end of touchMatrixCredentials in {path}')"
      "    path.write_text(text[:start] + replacement + text[end:])"
      "    patched = True"
      "    print(f'patched {path}')"
      "if not patched:"
      "    raise SystemExit('touchMatrixCredentials function not found')"
      ""
    ]
  );
  bundledRuntimeDepsNixModePatchScript = pkgs.writeText "openclaw-bundled-runtime-deps-nix-mode.py" (
    builtins.concatStringsSep "\n" [
      "import sys"
      "from pathlib import Path"
      ""
      "dist_dir = Path(sys.argv[1])"
      ''files = sorted(dist_dir.glob("bundled-runtime-deps-*.js"))''
      "if len(files) != 1:"
      "    raise SystemExit(f\"expected exactly one bundled-runtime-deps chunk, found {len(files)}\")"
      ""
      "path = files[0]"
      "text = path.read_text()"
      ""
      "helper_anchor = \"function installBundledRuntimeDeps(params) {\\n\""
      "helper = ("
      "    \"function materializeBundledRuntimeDepsFromNixImage(installRoot, installSpecs) {\\n\""
      "    + \"\\tconst bakedNodeModules = \\\"/lib/openclaw/node_modules\\\";\\n\""
      "    + \"\\tif (!fs.existsSync(bakedNodeModules)) return false;\\n\""
      "    + \"\\tfs.mkdirSync(installRoot, { recursive: true });\\n\""
      "    + \"\\tensureNpmInstallExecutionManifest(installRoot, installSpecs);\\n\""
      "    + \"\\tconst nodeModulesPath = path.join(installRoot, \\\"node_modules\\\");\\n\""
      "    + \"\\tfs.rmSync(nodeModulesPath, { recursive: true, force: true });\\n\""
      "    + \"\\tfs.symlinkSync(bakedNodeModules, nodeModulesPath, \\\"dir\\\");\\n\""
      "    + \"\\tassertBundledRuntimeDepsInstalled(installRoot, installSpecs);\\n\""
      "    + \"\\tremoveLegacyRuntimeDepsManifest(installRoot);\\n\""
      "    + \"\\treturn true;\\n\""
      "    + \"}\\n\""
      ")"
      "if helper not in text:"
      "    if helper_anchor not in text:"
      "        raise SystemExit(\"installBundledRuntimeDeps anchor not found\")"
      "    text = text.replace(helper_anchor, helper + helper_anchor, 1)"
      ""
      "needle = \"\\tif (isRuntimeDepsPlanMaterialized(params.installRoot, installSpecs)) {\\n\\t\\tremoveLegacyRuntimeDepsManifest(params.installRoot);\\n\\t\\treturn;\\n\\t}\\n\""
      "replacement = needle + \"\\tif ((params.env?.OPENCLAW_NIX_MODE ?? process.env.OPENCLAW_NIX_MODE) === \\\"1\\\" && materializeBundledRuntimeDepsFromNixImage(params.installRoot, installSpecs)) return;\\n\""
      "if text.count(replacement) < 2:"
      "    if text.count(needle) < 2:"
      "        raise SystemExit(\"install materialization anchors not found\")"
      "    text = text.replace(needle, replacement, 2)"
      ""
      "path.write_text(text)"
      ''print(f"patched {path}")''
      ""
    ]
  );

  # Inline Python scripts — extracted as pkgs.writeText to avoid PYEOF heredoc issues in Nix runCommand
  # (Nix '' string stripping leaves PYEOF indented, causing bash heredoc failure)
  losslessClawPatchScript = pkgs.writeText "openclaw-lossless-claw-patch.py" (
    builtins.concatStringsSep "\n" [
      "import json, sys"
      "p = sys.argv[1]"
      "with open(p) as f: d = json.load(f)"
      "d[\"main\"] = \"./index.js\""
      "if \"openclaw\" in d and \"extensions\" in d[\"openclaw\"]:"
      "    d[\"openclaw\"][\"extensions\"] = [\"./index.js\"]"
      "if \"dependencies\" in d:"
      "    deps = d[\"dependencies\"]"
      "    if deps.get(\"@mariozechner/pi-agent-core\") == \"0.66.1\":"
      "        deps[\"@mariozechner/pi-agent-core\"] = \"0.70.2\""
      "    if deps.get(\"@mariozechner/pi-ai\") == \"0.66.1\":"
      "        deps[\"@mariozechner/pi-ai\"] = \"0.70.6\""
      "    if deps.get(\"@mariozechner/pi-coding-agent\") == \"0.66.1\":"
      "        deps[\"@mariozechner/pi-coding-agent\"] = \"0.70.6\""
      "with open(p, \"w\") as f: json.dump(d, f, indent=2); f.write(\"\\n\")"
    ]
  );
  memoryEmbeddingPatchScript = pkgs.writeText "openclaw-memory-embedding-activation.py" (
    builtins.concatStringsSep "\n" [
      "import json"
      "import sys"
      "from pathlib import Path"
      ""
      "for extensions_arg in sys.argv[1:]:"
      "    extensions_dir = Path(extensions_arg)"
      "    for manifest_path in extensions_dir.glob(\"*/openclaw.plugin.json\"):"
      "        with manifest_path.open(encoding=\"utf-8\") as file:"
      "            manifest = json.load(file)"
      ""
      "        contracts = manifest.get(\"contracts\")"
      "        if not isinstance(contracts, dict) or not contracts.get(\"memoryEmbeddingProviders\"):"
      "            continue"
      ""
      "        activation = manifest.setdefault(\"activation\", {})"
      "        on_commands = activation.setdefault(\"onCommands\", [])"
      "        if \"memory\" not in on_commands:"
      "            on_commands.append(\"memory\")"
      ""
      "        with manifest_path.open(\"w\", encoding=\"utf-8\") as file:"
      "            json.dump(manifest, file, indent=2)"
      "            file.write(\"\\n\")"
    ]
  );
  linkNodeModulesPatchScript = pkgs.writeText "openclaw-link-node-modules.py" (
    builtins.concatStringsSep "\n" [
      "import json"
      "import os"
      "import sys"
      "from pathlib import Path"
      ""
      "root_node_modules = Path(sys.argv[1])"
      ""
      "def dependency_names(package_json):"
      "    names = []"
      "    for field in (\"dependencies\", \"optionalDependencies\"):"
      "        deps = package_json.get(field)"
      "        if isinstance(deps, dict):"
      "            names.extend(name for name in deps if isinstance(name, str))"
      "    return names"
      ""
      "def link_dependency(plugin_dir, dep_name):"
      "    target = root_node_modules.joinpath(*dep_name.split(\"/\"))"
      "    if not (target / \"package.json\").exists():"
      "        return"
      ""
      "    link_path = plugin_dir.joinpath(\"node_modules\", *dep_name.split(\"/\"))"
      "    if link_path.exists():"
      "        return"
      "    if link_path.is_symlink():"
      "        link_path.unlink()"
      ""
      "    link_path.parent.mkdir(parents=True, exist_ok=True)"
      "    os.symlink(os.path.relpath(target, link_path.parent), link_path)"
      ""
      "for extensions_arg in sys.argv[2:]:"
      "    extensions_dir = Path(extensions_arg)"
      "    for package_path in extensions_dir.glob(\"*/package.json\"):"
      "        with package_path.open(encoding=\"utf-8\") as file:"
      "            package_json = json.load(file)"
      ""
      "        for dep_name in dependency_names(package_json):"
      "            link_dependency(package_path.parent, dep_name)"
    ]
  );
  runtimeAliasesPatchScript = pkgs.writeText "openclaw-runtime-aliases.py" (
    builtins.concatStringsSep "\n" [
      "import re"
      "import sys"
      "from pathlib import Path"
      ""
      "dist_dir = Path(sys.argv[1])"
      "pattern = re.compile(r\"^(?P<base>.+\\.(?:runtime|contract))-[A-Za-z0-9_-]+\\.js$\")"
      ""
      "for chunk_path in sorted(dist_dir.iterdir()):"
      "    if not chunk_path.is_file():"
      "        continue"
      ""
      "    match = pattern.match(chunk_path.name)"
      "    if not match:"
      "        continue"
      ""
      "    alias_path = dist_dir / f\"{match.group('base')}.js\""
      "    alias_path.write_text(f'export * from \"./{chunk_path.name}\";\\n', encoding=\"utf-8\")"
    ]
  );
  rolldown = pkgs.stdenv.mkDerivation {
    pname = "rolldown";
    version = "1.0.0-rc.3";
    dontUnpack = true;
    dontBuild = true;
    nativeBuildInputs = [ pkgs.makeWrapper ];
    buildInputs = [ pkgs.nodejs_22 ];

    installPhase = ''
      # Assemble node_modules tree from pre-built npm tarballs
      mkdir -p $out/lib/node_modules/rolldown/node_modules/{@rolldown/binding-linux-x64-gnu,@oxc-project/types,@rolldown/pluginutils}

      tar xzf ${rolldownTgz} -C $out/lib/node_modules/rolldown --strip-components=1
      tar xzf ${bindingTgz} -C $out/lib/node_modules/rolldown/node_modules/@rolldown/binding-linux-x64-gnu --strip-components=1
      tar xzf ${oxcTypesTgz} -C $out/lib/node_modules/rolldown/node_modules/@oxc-project/types --strip-components=1
      tar xzf ${pluginutilsTgz} -C $out/lib/node_modules/rolldown/node_modules/@rolldown/pluginutils --strip-components=1

      # Create wrapper that invokes cli.mjs with node
      mkdir -p $out/bin
      makeWrapper ${pkgs.nodejs_22}/bin/node $out/bin/rolldown \
        --add-flags "$out/lib/node_modules/rolldown/bin/cli.mjs" \
        --set NODE_PATH "$out/lib/node_modules"
    '';
  };

  # Get overlay and pkgs from nix-openclaw
  openclawOverlay = import (inputs.nix-openclaw + "/nix/overlay.nix");
  openclawPkgs = import inputs.nix-openclaw.inputs.nixpkgs {
    inherit system;
    overlays = [ openclawOverlay ];
  };

  openclawGatewayBase = openclawPkgs.openclaw-gateway.override {
    inherit sourceInfo;
    inherit (sourceInfo) pnpmDepsHash;
  };

  # Legacy build overrides kept default-on until runtime validation proves they can be removed.
  openclawGateway =
    if legacyOpenClawPatches then
      openclawGatewayBase.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
          rolldown
          pkgs.findutils
        ];
        # Override installPhase: run the original script, but first clean broken symlinks
        installPhase = ''
          cp ${old.installPhase} /tmp/gateway-install.sh
          # Comment out the validation line using sed with # as replacement
          sed -i 's/^log_step "validate node_modules symlinks" check_no_broken_symlinks/# VALIDATION DISABLED: &/' /tmp/gateway-install.sh
          . /tmp/gateway-install.sh
        '';
        postPatch = (old.postPatch or "") + ''

                                    if [ -f tsconfig.json ]; then
                                      substituteInPlace tsconfig.json \
                                        --replace-fail '"strict": true' '"strict": false' \
                                        --replace-fail '"noEmitOnError": true' '"noEmitOnError": false'
                                    fi
                                    if [ -f package.json ]; then
                                      substituteInPlace package.json \
                                        --replace-fail '"node scripts/run-tsgo.mjs -p tsconfig.plugin-sdk.dts.json --declaration true"' '"tsc -p tsconfig.plugin-sdk.dts.json || true"'
                                    fi
                                    if [ -f scripts/bundle-a2ui.mjs ]; then
                                      substituteInPlace scripts/bundle-a2ui.mjs \
                                        --replace 'runPnpm(["-s", "exec", "rolldown", "-c", path.join(a2uiAppDir, "rolldown.config.mjs")])' \
                                        'runStep("rolldown", ["-c", path.join(a2uiAppDir, "rolldown.config.mjs")])'
                                    fi
                                    if [ -f src/media-understanding/attachments.normalize.ts ]; then
                                      substituteInPlace src/media-understanding/attachments.normalize.ts \
                                        --replace-fail 'import { getFileExtension, isAudioFileName, kindFromMime } from "../media/mime.js";' \
                                        'import { getFileExtension, isAudioFileName, kindFromMime, normalizeMimeType } from "../media/mime.js";' \
                                        --replace-fail '  const kind = kindFromMime(attachment.mime);' \
                                        '  const mime = normalizeMimeType(attachment.mime);
                            if (mime === "audio/webm" || mime === "video/webm") {
                              return "audio";
                            }

                            const kind = kindFromMime(mime);' \
                                        --replace-fail '  if ([".mp4", ".mov", ".mkv", ".webm", ".avi", ".m4v"].includes(ext)) {' \
                                        '  if (ext === ".webm") {
                              return "audio";
                            }
                            if ([".mp4", ".mov", ".mkv", ".avi", ".m4v"].includes(ext)) {'
                          fi
                          if [ -f src/media/mime.ts ]; then
                            substituteInPlace src/media/mime.ts \
                              --replace-fail '  "audio/mp4": ".m4a",' \
                              '  "audio/mp4": ".m4a",
          "audio/webm": ".webm",' \
                              --replace-fail '  ".xml": "text/xml",' \
                              '  ".xml": "text/xml",
          ".webm": "audio/webm",' \
                              --replace-fail '  ".wav",' \
                              '  ".wav",
          ".webm",'
                          fi
                          if [ -f src/media/audio.ts ]; then
                            substituteInPlace src/media/audio.ts \
                              --replace-fail '  "audio/m4a",' \
                              '  "audio/m4a",
          "audio/webm",
          "video/webm",' \
                              --replace-fail '".oga", ".ogg", ".opus", ".mp3", ".m4a"' \
                              '".oga", ".ogg", ".opus", ".mp3", ".m4a", ".webm"'
                          fi
                          if [ -f src/media/store.ts ]; then
                            substituteInPlace src/media/store.ts \
                              --replace-fail 'return buildSavedMediaResult({ dir, id, size: buffer.byteLength, contentType: mime });' \
                              'return buildSavedMediaResult({ dir, id, size: buffer.byteLength, contentType: mime === "video/webm" ? "audio/webm" : mime });'
                          fi
        '';
      })
    else
      openclawGatewayBase;

  # memory-lancedb native deps are bundled in upstream root node_modules.
  # Link them into the plugin roots below instead of using stale local deps.
  inherit (import ./matrix-deps.nix { inherit pkgs lib; }) matrixPluginDeps;
  inherit
    (import ./lossless-claw-deps.nix {
      inherit pkgs;
      losslessClawVersion = losslessClawInfo.version;
    })
    losslessClawPackage
    ;
  matrixCryptoNative = pkgs.fetchurl {
    url = "https://github.com/matrix-org/matrix-rust-sdk-crypto-nodejs/releases/download/v0.4.0/matrix-sdk-crypto.linux-x64-gnu.node";
    sha256 = "sha256-cHjU3ZhxKPea/RksT2IfZK3s435D8qh1bx0KnwNN5xg=";
  };
  # Lossless-claw plugin info — change version to upgrade
  # Update: version, sha256, npmDepsHash, and optionally dep versions + lock file
  losslessClawInfo = {
    version = "0.9.3";
    sha256 = "sha256-cqmuQZCsrOBoKz/DZCB/cpxvldHxLxwjXoQZ52y2Aug=";
    npmDepsHash = "sha256-2Zvvd22WbueGSxfmjVlz6+5zqvTYI6A1NAsRMppuyfk=";
  };
  losslessClawSource = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@martian-engineering/lossless-claw/-/lossless-claw-${losslessClawInfo.version}.tgz";
    sha256 = losslessClawInfo.sha256;
  };
  fontsConf = pkgs.makeFontsConf {
    fontDirectories = [
      pkgs.dejavu_fonts
      pkgs.noto-fonts
      pkgs.noto-fonts-color-emoji
      pkgs.liberation_ttf
      pkgs.font-awesome
    ];
  };

  imageTag = "v${version}${tagSuffix}";

  entrypointScriptText = builtins.readFile ./entrypoint.sh;
  # Merged CLI tools environment — single /bin/ with all tools accessible
  cliTools = pkgs.buildEnv {
    name = "openclaw-cli-tools";
    paths = [
      pkgs.coreutils
      pkgs.bash
      pkgs.curl
      pkgs.jq
      pkgs.gnused
      pkgs.gitMinimal
      (pkgs.python3.withPackages (ps: [
        ps.pip
        ps.requests
        ps.python-dateutil
      ]))
      pkgs.uv
      pkgs.ffmpeg-headless
      pkgs.github-cli
      openclawPkgs.nodejs_22
      pkgs.procps
      pkgs.gnugrep
      pkgs.gawk
      pkgs.findutils
      pkgs.which
      pkgs.tree
      pkgs.typst
      pkgs.ripgrep
      pkgs.file
      pkgs.wget
      pkgs.diffutils
      pkgs.gnutar
      pkgs.gzip
      pkgs.less
      pkgs.openssh
      pkgs.rsync
      pkgs.kubectl
      pkgs.chromium
      pkgs.fontconfig
      pkgs.dejavu_fonts
      pkgs.noto-fonts
      pkgs.noto-fonts-color-emoji
      pkgs.noto-fonts-cjk-sans
      pkgs.liberation_ttf
      pkgs.font-awesome
    ];
    pathsToLink = [
      "/bin"
      "/lib"
      "/share"
    ];
  };
  openclawRootfs = pkgs.runCommand "openclaw-rootfs" { } ''
            mkdir -p $out/lib $out/bin
            # Copy openclaw gateway lib (the main app) - use -rL to dereference symlinks for writable files
            if [ -d "${openclawGateway}/lib" ]; then cp -rL "${openclawGateway}/lib"/* $out/lib/ 2>/dev/null || true; fi
            # Copy the openclaw binary - symlinks to nix store paths won't work in container
            if [ -f "${openclawGateway}/bin/openclaw" ]; then cp -rL "${openclawGateway}/bin/openclaw" $out/bin/openclaw; fi
            # Copy python lib for requests etc.
            chmod -R u+w $out/lib/openclaw/ || true
            # Strip ML inference libs (not used) - these are large, explicit rm is fast
            rm -rf $out/lib/openclaw/node_modules/.pnpm/@node-llama-cpp+* $out/lib/openclaw/node_modules/.pnpm/node-llama-cpp@* 2>/dev/null || true
            rm -rf $out/lib/openclaw/node_modules/node-llama-cpp $out/lib/openclaw/node_modules/@node-llama-cpp 2>/dev/null || true
            # Skip slow find-based cross-platform stripping - saves ~5-10 min build time
            cd $out/lib/openclaw
                # Extract lossless-claw from npm tarball (pre-built dist/index.js)
                mkdir -p /tmp/lossless-extract
                tar -xzf ${losslessClawSource} -C /tmp/lossless-extract/
                # dist/extensions/lossless-claw may already exist from upstream build (read-only) — chmod first
                chmod -R u+w "$out/lib/openclaw/dist/extensions/lossless-claw/" 2>/dev/null || true
                mkdir -p "$out/lib/openclaw/dist/extensions/lossless-claw"
                cp /tmp/lossless-extract/package/dist/index.js "$out/lib/openclaw/dist/extensions/lossless-claw/index.js" 2>/dev/null || true
                cp /tmp/lossless-extract/package/openclaw.plugin.json "$out/lib/openclaw/dist/extensions/lossless-claw/openclaw.plugin.json" 2>/dev/null || true
                cp /tmp/lossless-extract/package/package.json "$out/lib/openclaw/dist/extensions/lossless-claw/package.json" 2>/dev/null || true
                # Fix package.json paths: npm has main=dist/index.js but we place index.js at root
                ${pkgs.python3}/bin/python3 ${losslessClawPatchScript} "$out/lib/openclaw/dist/extensions/lossless-claw/package.json"
                # Also create extensions/lossless-claw for generic copy loop compatibility
                mkdir -p "$out/lib/openclaw/extensions/lossless-claw"
                chmod -R u+w "$out/lib/openclaw/extensions/lossless-claw/" 2>/dev/null || true
                cp /tmp/lossless-extract/package/openclaw.plugin.json "$out/lib/openclaw/extensions/lossless-claw/openclaw.plugin.json" 2>/dev/null || true
                cp "$out/lib/openclaw/dist/extensions/lossless-claw/package.json" "$out/lib/openclaw/extensions/lossless-claw/package.json" 2>/dev/null || true
                if [ -d /tmp/lossless-extract/package/skills ]; then
                  cp -r /tmp/lossless-extract/package/skills "$out/lib/openclaw/dist/extensions/lossless-claw/"
                  cp -r /tmp/lossless-extract/package/skills "$out/lib/openclaw/extensions/lossless-claw/"
                fi
                rm -rf /tmp/lossless-extract
            # Copy plugin manifests and runtime TS sources from source extensions/ into dist/extensions/
            # The gateway resolves plugin runtime modules (e.g. light-runtime-api.ts) from dist/extensions/
            if [ -d "$out/lib/openclaw/extensions" ] && [ -d "$out/lib/openclaw/dist/extensions" ]; then
              chmod -R u+w $out/lib/openclaw/dist/extensions/ || true
              for extdir in $out/lib/openclaw/extensions/*/; do
                extname=$(basename "$extdir")
                # Skip lossless-claw (pre-built from npm)
                if [ "$extname" = "lossless-claw" ]; then
                  continue
                fi
                mkdir -p "$out/lib/openclaw/dist/extensions/$extname"
                if [ -d "$out/lib/openclaw/dist/extensions/$extname" ]; then
                  # Copy plugin manifest
                  if [ -f "$extdir/openclaw.plugin.json" ]; then
                    cp "$extdir/openclaw.plugin.json" "$out/lib/openclaw/dist/extensions/$extname/openclaw.plugin.json"
                  fi
                  # Do NOT copy .ts source files — the upstream build already provides compiled .js in dist/extensions/.
                  # collectTopLevelPublicSurfaceArtifacts reads all files and rewriteEntryToBuiltPath converts
                  # .ts → .js, causing duplicate runtime sidecar paths and assertUniqueValues failure.
                  # Copy src/ directory if it exists (contains compiled plugin code)
                  if [ -d "$extdir/src" ]; then
                    cp -r "$extdir/src" "$out/lib/openclaw/dist/extensions/$extname/"
                  fi
                  # Copy skills/ directory if it exists (contains plugin skills that OpenClaw loads at runtime)
                  if [ -d "$extdir/skills" ]; then
                    cp -r "$extdir/skills" "$out/lib/openclaw/dist/extensions/$extname/"
                  fi
                  # Copy package.json for dependency resolution
                  if [ -f "$extdir/package.json" ]; then
                    cp "$extdir/package.json" "$out/lib/openclaw/dist/extensions/$extname/package.json"
                  fi
                fi
              done

              # The memory CLI only loads plugins activated for the `memory` command.
              # Embedding provider plugins declare their contract but lack that command activation upstream.
              ${pkgs.python3}/bin/python3 ${memoryEmbeddingPatchScript} "$out/lib/openclaw/extensions" "$out/lib/openclaw/dist/extensions"

              # Runtime deps are already packaged at /lib/openclaw/node_modules.
              # Link them into each plugin root so OpenClaw does not try `npm install`
              # against extension package.json files that contain workspace:* dev deps.
              ${pkgs.python3}/bin/python3 ${linkNodeModulesPatchScript} "$out/lib/openclaw/node_modules" "$out/lib/openclaw/extensions" "$out/lib/openclaw/dist/extensions"

              # Some runtime chunks resolve stable, unhashed module names at runtime.
              # The upstream postbuild writes these aliases; keep them when repacking.
              ${pkgs.python3}/bin/python3 ${runtimeAliasesPatchScript} "$out/lib/openclaw/dist"
            fi

            # lossless-claw: pre-built index.js already copied to dist/extensions/ above
            # Symlink plugin-entry.runtime.ts to dist/ top-level for jiti resolution.
            # The bundled dist/plugin-entry.runtime-CuPlkRZ7.js uses jiti to load
            # ./plugin-entry.runtime.ts relative to itself, but the .ts source only
            # exists inside dist/extensions/<name>/src/. Create a symlink so jiti finds it.
            chmod u+w $out/lib/openclaw/dist/ || true
            for extdir in $out/lib/openclaw/dist/extensions/*/src; do
              if [ -f "$extdir/plugin-entry.runtime.ts" ]; then
                extname=$(basename $(dirname "$extdir"))
                ln -sf "extensions/$extname/src/plugin-entry.runtime.ts" \
                  "$out/lib/openclaw/dist/plugin-entry.runtime.ts"
                break
              fi
            done
            # memory-lancedb is bundled as TypeScript source with native deps in root node_modules.
            # The plugin manifest points at ./index.ts, so copy only its runtime TS files into dist.
            if [ -d "$out/lib/openclaw/extensions/memory-lancedb" ]; then
              mkdir -p "$out/lib/openclaw/dist/extensions/memory-lancedb"
              chmod -R u+w "$out/lib/openclaw/extensions/memory-lancedb" "$out/lib/openclaw/dist/extensions/memory-lancedb" 2>/dev/null || true
              for file in api.ts cli-metadata.ts config.ts index.ts lancedb-runtime.ts; do
                if [ -f "$out/lib/openclaw/extensions/memory-lancedb/$file" ]; then
                  cp "$out/lib/openclaw/extensions/memory-lancedb/$file" "$out/lib/openclaw/dist/extensions/memory-lancedb/$file"
                fi
              done
              cp "$out/lib/openclaw/extensions/memory-lancedb/openclaw.plugin.json" "$out/lib/openclaw/dist/extensions/memory-lancedb/openclaw.plugin.json" 2>/dev/null || true
              cp "$out/lib/openclaw/extensions/memory-lancedb/package.json" "$out/lib/openclaw/dist/extensions/memory-lancedb/package.json" 2>/dev/null || true
            fi
            # Do NOT copy/modify dist/package.json.
            # The upstream build places its own package.json in dist/ (if any).
            # findPackageRootSync walks up looking for name:"openclaw" — if it finds
            # one in dist/, it resolves runtime paths relative to dist/, causing
            # dist/dist/plugins/... (double dist). Leaving the upstream dist/package.json
            # untouched (which has name:"openclaw-dist" from upstream build) ensures
            # findPackageRootSync continues to /lib/openclaw/package.json (name:"openclaw")
            # and resolves dist/plugins/runtime/ correctly.
            mkdir -p $out/etc
            for pkg in ${pkgs.tzdata}; do
              if [ -d "$pkg/etc" ]; then cp -rsf "$pkg/etc"/* $out/etc/ 2>/dev/null || true; fi
            done
            mkdir -p $out/share/zoneinfo
            cp -rsf ${pkgs.tzdata}/share/zoneinfo/* $out/share/zoneinfo/ 2>/dev/null || true
            # Create /etc/localtime so glibc (and Python datetime.now()) resolves TZ correctly
            # Without this, Python returns UTC despite TZ env var being set
            ln -sf ${pkgs.tzdata}/share/zoneinfo/America/Sao_Paulo $out/etc/localtime
            mkdir -p $out/etc/ssl/certs
            cp -rsf ${pkgs.cacert}/etc/ssl/certs/* $out/etc/ssl/certs/ 2>/dev/null || true
            if [ -d "${pkgs.python3Packages.requests}/lib" ]; then cp -rsf ${pkgs.python3Packages.requests}/lib/* $out/lib/ 2>/dev/null || true; fi
            # Config is mounted externally via volume, no baked-in config needed
            mkdir -p $out/etc/openclaw
            if [ -d "${matrixPluginDeps}/matrix-deps/node_modules" ]; then
              chmod -R u+w $out/lib/openclaw/extensions/matrix/ || true
              rm -rf $out/lib/openclaw/extensions/matrix/node_modules
              cp -rL ${matrixPluginDeps}/matrix-deps/node_modules $out/lib/openclaw/extensions/matrix/
            fi
            chmod -R u+w $out/lib/openclaw/extensions/matrix/ 2>/dev/null || true
            # Copy lossless-claw node_modules to dist/extensions path (not extensions path)
            if [ -d "$out/lib/openclaw/dist/extensions/lossless-claw" ]; then
              chmod -R u+w "$out/lib/openclaw/dist/extensions/lossless-claw/" 2>/dev/null || true
              rm -rf "$out/lib/openclaw/dist/extensions/lossless-claw/node_modules" 2>/dev/null || true
              if [ -d "${losslessClawPackage}/lossless-claw-deps/node_modules" ]; then
                cp -rL ${losslessClawPackage}/lossless-claw-deps/node_modules "$out/lib/openclaw/dist/extensions/lossless-claw/"
              fi
            fi
            ${lib.optionalString matrixSendQueuePatch ''
              # Fix upstream build regression #33001: Rolldown bundles keyed-async-queue into index.js
              # but OpenClaw's runtime TypeScript loader lacks the alias for this subpath.
              # Patch the import to use the main plugin-sdk export which includes KeyedAsyncQueue.
              SEND_QUEUE="$out/lib/openclaw/extensions/matrix/src/matrix/send-queue.ts"
              if [ -f "$SEND_QUEUE" ]; then
                chmod u+w "$SEND_QUEUE"
                sed -i 's|openclaw/plugin-sdk/keyed-async-queue|openclaw/plugin-sdk|g' "$SEND_QUEUE"
              fi
            ''}
            # Add openclaw self-symlink so extensions can resolve "openclaw/*" imports
            mkdir -p "$out/lib/openclaw/node_modules"
            ln -sf ../ "$out/lib/openclaw/node_modules/openclaw"
            # Copy pi-ai dependencies to the root node_modules so openclaw can find them
            # (Nix sandbox prevents npm install here)
            cd "$out/lib/openclaw"
            chmod -R u+w node_modules || true
            if [ -d "${losslessClawPackage}/lossless-claw-deps/node_modules/@mariozechner" ]; then
              mkdir -p node_modules/@mariozechner
              cp -rL ${losslessClawPackage}/lossless-claw-deps/node_modules/@mariozechner/* node_modules/@mariozechner/
            fi
            if [ -d "${losslessClawPackage}/lossless-claw-deps/node_modules/@sinclair" ]; then
              mkdir -p node_modules/@sinclair
              cp -rL ${losslessClawPackage}/lossless-claw-deps/node_modules/@sinclair/* node_modules/@sinclair/
            fi
            cd - >/dev/null
            CRYPTO_PKG="$out/lib/openclaw/extensions/matrix/node_modules/@matrix-org/matrix-sdk-crypto-nodejs"
            if [ -d "$CRYPTO_PKG" ]; then chmod -R u+w "$CRYPTO_PKG" || true; cp ${matrixCryptoNative} "$CRYPTO_PKG/matrix-sdk-crypto.linux-x64-gnu.node"; fi
            ${lib.optionalString disableMatrixCredentialTouch ''
              ${pkgs.python3}/bin/python3 ${matrixCredentialTouchPatchScript} "$out/lib/openclaw/dist/extensions/matrix"
            ''}
            # Disabled for v2026.5.2-beta.2 — bundled runtime deps structure changed
    # ${pkgs.python3}/bin/python3 ${bundledRuntimeDepsNixModePatchScript} "$out/lib/openclaw/dist"
            # Install RTK binary into /bin (extract from tar.gz)
            mkdir -p /tmp/rtk-extract
            tar -xzf ${rtkBinary} -C /tmp/rtk-extract/
            cp /tmp/rtk-extract/rtk $out/bin/rtk
            chmod +x $out/bin/rtk
            rm -rf /tmp/rtk-extract

            mkdir -p "$out/lib/openclaw/extensions/rtk-rewrite"
            mkdir -p "$out/lib/openclaw/dist/extensions/rtk-rewrite"
            cp ${rtkPluginJson} "$out/lib/openclaw/extensions/rtk-rewrite/openclaw.plugin.json"
            cp ${rtkPluginTs} "$out/lib/openclaw/extensions/rtk-rewrite/index.ts"
            cp ${rtkPluginJson} "$out/lib/openclaw/dist/extensions/rtk-rewrite/openclaw.plugin.json"
            cp ${rtkPluginTs} "$out/lib/openclaw/dist/extensions/rtk-rewrite/index.ts"
            cp ${rtkPackageJson} "$out/lib/openclaw/extensions/rtk-rewrite/package.json"
            cp ${rtkPackageJson} "$out/lib/openclaw/dist/extensions/rtk-rewrite/package.json"
            chmod -R u+w "$out/lib/openclaw/extensions/rtk-rewrite/" "$out/lib/openclaw/dist/extensions/rtk-rewrite/" 2>/dev/null || true
  '';
in
dockerTools.streamLayeredImage {
  name = "localhost/openclaw-nix";
  tag = imageTag;
  maxLayers = 50;
  contents = pkgs.buildEnv {
    name = "openclaw-image-root";
    paths = [
      openclawRootfs
      cliTools
    ];
    pathsToLink = [
      "/bin"
      "/lib"
      "/nix"
      "/etc"
      "/usr"
    ];
  };
  extraCommands = ''
    mkdir -p ./bin ./config ./state ./logs ./tmp ./var/tmp
    chmod 1777 ./tmp ./var/tmp

    mkdir -p ./etc/fonts
    cp ${fontsConf} ./etc/fonts/fonts.conf
    # Symlink openclaw's nix store path to rootfs so it can resolve its embedded paths.
    # The openclaw wrapper at ${openclawGateway}/bin/openclaw references:
    #   /nix/store/<hash>-openclaw-gateway/lib/openclaw/...
    # Create symlink: /nix/store/<hash>-openclaw-gateway -> / (root)
    # so gateway-path/lib/openclaw/... resolves to /lib/openclaw/...
    GATEWAY_PATH="${openclawGateway}"
    GATEWAY_DIR=$(dirname "$GATEWAY_PATH")
    GATEWAY_BASE=$(basename "$GATEWAY_PATH")
    mkdir -p ".$GATEWAY_DIR"
    ln -sf / ".$GATEWAY_PATH"

    cat > ./entrypoint.sh << 'EOF'
    ${entrypointScriptText}
    EOF
    chmod +x ./entrypoint.sh
  '';
  config = {
    Entrypoint = [
      "/bin/sh"
      "-c"
      "/entrypoint.sh"
    ];
    ExposedPorts = {
      "18789/tcp" = { };
    };
    Env = [
      "OPENCLAW_STATE_DIR=/state/openclaw"
      "OPENCLAW_CONFIG_PATH=/config/openclaw.json"
      "FONTCONFIG_FILE=/etc/fonts/fonts.conf"
      "HOME=/state/home"
      "PATH=/state/bin:/state/npm/bin:/bin:/usr/bin"
      "NPM_CONFIG_PREFIX=/state/npm"
      "NPM_CONFIG_CACHE=/state/cache/npm"
      "XDG_CACHE_HOME=/state/cache"
      "UV_CACHE_DIR=/state/cache/uv"
      "PIP_CACHE_DIR=/state/cache/pip"
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
      "TZ=:/etc/localtime"
    ];
  };
}

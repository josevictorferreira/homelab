{
  pkgs ? import <nixpkgs> {
    config = {
      allowUnfree = true;
      rocmSupport = true;
    };
  },
}:

let
  version = "0.2.1";
  src = pkgs.fetchFromGitHub {
    owner = "docling-project";
    repo = "docling-serve";
    rev = "v${version}";
    hash = "sha256-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX=";
  };

  uvSyncExtraArgs = "--no-group pypi --group rocm --no-extra flash-attn";

  fetchHfModel =
    {
      name,
      repo,
      hash,
    }:
    pkgs.fetchzip {
      name = "${name}-model";
      url = "https://huggingface.co/${repo}/resolve/main.zip?download=true";
      inherit hash;
      stripRoot = false;
    };

  models = {
    layout = fetchHfModel {
      name = "layout";
      repo = "ibm/docling-pdf-layout";
      hash = "sha256-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX=";
    };
    tableformer = fetchHfModel {
      name = "tableformer";
      repo = "ibm/docling-pdf-tableformer";
      hash = "sha256-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX=";
    };
    picture_classifier = fetchHfModel {
      name = "picture_classifier";
      repo = "ibm/docling-pdf-classifier-v1";
      hash = "sha256-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX=";
    };
    easyocr = fetchHfModel {
      name = "easyocr";
      repo = "docling/easyocr-model";
      hash = "sha256-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX=";
    };
  };

  modelsList = "layout tableformer picture_classifier easyocr";

  # Tesseract with required languages
  tesseract = pkgs.tesseract5.withLanguages [
    "eng"
    "fra"
    "spa"
    "deu"
    "ita"
    "chi_sim"
    "jpn"
  ];

  # Derivation to build the docling-serve environment
  doclingEnv = pkgs.stdenv.mkDerivation {
    name = "docling-serve-${version}";
    inherit src;

    nativeBuildInputs = with pkgs; [
      uv
      python312
      unzip
    ];

    buildInputs = with pkgs; [
      poppler_utils
      tesseract
      rocmPackages.clr
      rocmPackages.rocblas
      rocmPackages.hipblas
      rocmPackages.miopen
      rocmPackages.rocm-smi
    ];

    installPhase = ''
      runHook preInstall

      export UV_COMPILE_BYTECODE=1
      export UV_LINK_MODE=copy
      export UV_PROJECT_ENVIRONMENT=$out/opt/app-root
      export DOCLING_SERVE_ARTIFACTS_PATH=$out/opt/app-root/src/.cache/docling/models
      export HOME=$TMPDIR
      export OMP_NUM_THREADS=4
      export LANG=en_US.UTF-8
      export LC_ALL=en_US.UTF-8
      export PYTHONIOENCODING=utf-8
      export TESSDATA_PREFIX=${tesseract}/share/tessdata

      mkdir -p $out/opt/app-root/src

      cp $src/pyproject.toml $out/opt/app-root/src/
      cp $src/uv.lock $out/opt/app-root/src/

      cd $out/opt/app-root/src

      umask 002
      UV_SYNC_ARGS="--frozen --no-install-project --no-dev --all-extras"
      uv sync $UV_SYNC_ARGS ${uvSyncExtraArgs} --no-extra flash-attn

      FLASH_ATTENTION_SKIP_CUDA_BUILD=TRUE uv sync $UV_SYNC_ARGS ${uvSyncExtraArgs} --no-build-isolation-package=flash-attn

      echo "Copying prefetched models..."
      mkdir -p $DOCLING_SERVE_ARTIFACTS_PATH
      ${builtins.concatStringsSep "\n" (
        map (model: ''
          cp -r ${models.${model}} $DOCLING_SERVE_ARTIFACTS_PATH/${model}
        '') (pkgs.lib.splitString " " modelsList)
      )}

      cp -r $src/docling_serve $out/opt/app-root/src/docling_serve

      uv sync --frozen --no-dev --all-extras ${uvSyncExtraArgs}

      chmod -R 775 $out/opt/app-root
      chmod -R g=u $out/opt/app-root/src/.cache

      runHook postInstall
    '';

    postFixup = ''
      for bin in $out/opt/app-root/bin/*; do
        wrapProgram $bin \
          --prefix LD_LIBRARY_PATH : "${
            pkgs.lib.makeLibraryPath (
              with pkgs;
              [
                rocmPackages.clr
                rocmPackages.rocblas
                rocmPackages.miopen
              ]
            )
          }"
      done
    '';
  };
in
pkgs.dockerTools.buildLayeredImage {
  name = "ghcr.io/josevictorferreira/docling-rocm";
  tag = "latest";

  contents = [
    doclingEnv
  ]
  ++ (with pkgs; [
    python312
    poppler_utils
    tesseract
    rocmPackages.clr
    rocmPackages.rocblas
    rocmPackages.hipblas
    rocmPackages.miopen
    rocmPackages.rocm-smi
    busybox
  ]);

  extraCommands = ''
    # Additional setup (runs before contents are copied)
    mkdir -p /opt/app-root/src/.cache
    chmod -R 775 /opt/app-root
  '';

  config = {
    Cmd = [
      "/opt/app-root/bin/docling-serve"
      "run"
    ];
    ExposedPorts."5001/tcp" = { };
    User = "1001:1001";
    WorkingDir = "/opt/app-root/src";
    Env = [
      "OMP_NUM_THREADS=4"
      "LANG=en_US.UTF-8"
      "LC_ALL=en_US.UTF-8"
      "PYTHONIOENCODING=utf-8"
      "DOCLING_SERVE_ARTIFACTS_PATH=/opt/app-root/src/.cache/docling/models"
      "TESSDATA_PREFIX=${tesseract}/share/tessdata"
      "LD_LIBRARY_PATH=${
        pkgs.lib.makeLibraryPath (
          with pkgs;
          [
            rocmPackages.clr
            rocmPackages.rocblas
            rocmPackages.miopen
          ]
        )
      }"
    ];
  };

  maxLayers = 120;
}

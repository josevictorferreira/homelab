{ stdenvNoCC, lib, kubernetes-helm, cacert }:

{ chart ? null
, chartUrl ? null
, repo ? null
, version ? null
, sha256
, untar ? true
}:

assert chartUrl != null || (repo != null && chart != null);
assert chartUrl == null || lib.hasPrefix "oci://" chartUrl;
assert repo == null || lib.hasPrefix "oci://" repo;

stdenvNoCC.mkDerivation {
  name =
    let
      base = if chartUrl != null then chartUrl else "${repo}/${chart}";
      clean = lib.replaceStrings [ "oci://" "/" ":" "@" ] [ "" "-" "-" "-" ] base;
    in
    "${clean}-${if version == null then "dev" else version}";

  nativeBuildInputs = [ kubernetes-helm cacert ];

  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  outputHash = sha256;

  buildCommand = ''
    set -euo pipefail
    export HOME="$PWD"
    export HELM_CACHE_HOME="$PWD/.cache/helm"
    export HELM_CONFIG_HOME="$PWD/.config/helm"
    export HELM_DATA_HOME="$PWD/.local/share/helm"
    export HELM_REGISTRY_CONFIG="$PWD/registry.json"
    export HELM_EXPERIMENTAL_OCI=1

    mkdir -p chart

    if [ -n "${chartUrl}" ]; then
      ref="${chartUrl}"
    else
      ref="${repo}/${chart}"
    fi

    echo "Pulling OCI Helm chart: $ref ${version}"
    helm pull "$ref" \
      ${if untar then "--untar" else ""} \
      ${if version == null then "" else "--version ${version}"} \
      --destination ./chart

    if ${if untar then "true" else "false"}; then
      # Helm untars into chart/<name>/
      cp -r chart/*/ "$out"
    else
      mkdir -p "$out"
      cp chart/*.tgz "$out/"
    fi
  '';
}

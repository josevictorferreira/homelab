---
name: "kubenix-code"
description: "Kubenix code specialist for writing Kubernetes manifests as Nix modules using kubenix.evalModules and kubernetes.resources."
metadata:
  triggers: "kubenix, kubenix code, kubenix module, kubenix manifest, kubernetes.resources, k8s nix, kubernetes nix, write kubenix, kubenix pod, kubenix deployment, nix kubernetes manifests"
allowed-tools:
  - Read*
  - Grep*
  - Glob*
  - Edit*
  - Write*
compatibility: opencode
---

# Kubenix Code

Use this skill when writing or reviewing Kubenix code: Kubernetes manifests expressed as Nix modules.

## Core Pattern

Kubenix entrypoint:

```nix
{ kubenix ? import ../../../.. }:

kubenix.evalModules.${builtins.currentSystem} {
  module = { kubenix, ... }: {
    imports = [ kubenix.modules.k8s ];

    kubernetes.resources.pods.example.spec.containers.ex.image = "nginx";
  };
}
```

Rules:
- `kubenix.evalModules.<system>` evaluates a Kubenix module set.
- The module arg `{ kubenix, ... }` is a different Kubenix object than the outer default arg.
- Always import definitions before declaring resources: `imports = [ kubenix.modules.k8s ];`.
- Put Kubernetes objects under `kubernetes.resources`.
- Resource shape mirrors Kubernetes API, but uses plural resource groups and injects names from attr keys.

## Naming Model

```nix
kubernetes.resources.pods.example.spec.containers.ex.image = "nginx";
```

Means:
- `pods` → Kubernetes Pod resource collection.
- `example` → `metadata.name = "example"`.
- `containers` → container collection.
- `ex` → container `name = "ex"`.
- `image = "nginx"` → container image.

Prefer readable attr keys. They become Kubernetes names where Kubenix expects named collections.

## API Mapping

Kubenix mostly follows Kubernetes API fields. When unsure:

```sh
kubectl explain pod.spec.containers
kubectl explain deployment.spec.template.spec.containers
```

Convert API paths to Kubenix under plural resources:

```nix
kubernetes.resources.pods.<name>.spec.containers.<container-name> = {
  image = "nginx";
};
```

## Verification

For a standalone example containing the `evalModules` call:

```sh
nix eval -f . --json config.kubernetes.generated
```

Expected output is a Kubernetes `List` manifest with:
- top-level `apiVersion = "v1"`
- top-level `kind = "List"`
- `items = [ ... ]`
- generated Kubenix labels/annotations, including project/k8s-version/hash.

## Minimal Pod Example

```nix
{ kubenix ? import ../../../.. }:

kubenix.evalModules.${builtins.currentSystem} {
  module = { kubenix, ... }: {
    imports = [ kubenix.modules.k8s ];

    kubernetes.resources.pods = {
      example.spec.containers = {
        ex.image = "nginx";
      };
    };
  };
}
```

Generates a Pod named `example` with one container named `ex`, image `nginx`.

## Style

- Keep code close to Kubernetes API names.
- Use attr nesting for clarity; avoid clever generators unless many near-identical resources exist.
- Prefer explicit resource/container names over computed names.
- If writing inside this repo, also follow dendritic Nix rules from `maintaining-dendritic-nix-config`.

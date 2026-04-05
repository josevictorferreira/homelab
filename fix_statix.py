with open("modules/kubenix/apps/personal-finance-dashboard.nix", "r") as f:
    content = f.read()

content = content.replace("kubernetes.resources.deployments.${name} = {", "kubernetes.resources = {\n    deployments.${name} = {")

# find kubernetes.resources.services
idx = content.find("kubernetes.resources.services.${name} = {")
content = content[:idx] + "  };\n\n  services.${name} = {" + content[idx + len("kubernetes.resources.services.${name} = {"):]

# find kubernetes.resources.ingresses
idx2 = content.find("kubernetes.resources.ingresses.${name} = {")
content = content[:idx2] + "  };\n\n  ingresses.${name} = {" + content[idx2 + len("kubernetes.resources.ingresses.${name} = {"):]

# close resources
content = content + "\n  };\n}"

# We also need to fix the final closing brace of the file because we injected resources. Wait, the original file ends with `}`. So we need to remove the original `}`.
content = content.strip()
if content.endswith("}"):
    content = content[:-1]

content += "  };\n}\n"

# apply the string literal replacements for task 4 and task 5 since git checkout reverted them!
content = content.replace('ingressClassName = "cilium";', 'ingressClassName = kubenix.lib.defaultIngressClass;')
content = content.replace('secretName = "wildcard-tls";', 'secretName = kubenix.lib.defaultTLSSecret;')
content = content.replace('persistentVolumeClaim.claimName = "cephfs-shared-storage-root";', 'persistentVolumeClaim.claimName = kubenix.lib.sharedStorage.rootPVC;')

with open("modules/kubenix/apps/personal-finance-dashboard.nix", "w") as f:
    f.write(content)


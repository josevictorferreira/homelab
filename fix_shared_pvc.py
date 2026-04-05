import os
import re

FILES_TO_PROCESS = [
    "modules/kubenix/apps/immich.nix",
    "modules/kubenix/apps/qui.nix",
    "modules/kubenix/apps/sftpgo.nix",
    "modules/kubenix/apps/qbittorrent.nix",
    "modules/kubenix/apps/openclaw-nix.nix",
    "modules/kubenix/apps/personal-finance-dashboard.nix",
    "modules/kubenix/backup/shared-subfolders-proton-sync.nix",
    "modules/kubenix/backup/shared-subfolders-backup.nix"
]

def ensure_kubenix_arg(content, filename):
    if "kubenix" not in content[:content.find(":")]:
        # find the first '{' before the first ':'
        colon_idx = content.find(":")
        if colon_idx != -1:
            first_brace = content.find("{")
            if first_brace != -1 and first_brace < colon_idx:
                print(f"Injecting kubenix into {filename}")
                return content[:first_brace+1] + " kubenix, " + content[first_brace+1:]
    return content

for filename in FILES_TO_PROCESS:
    try:
        with open(filename, "r") as f:
            content = f.read()
            
        original_content = content
            
        # Ensure kubenix is in arguments
        content = ensure_kubenix_arg(content, filename)
        
        # Replace occurrences
        content = content.replace('"cephfs-shared-storage-root"', 'kubenix.lib.sharedStorage.rootPVC')
        content = content.replace('"cephfs-shared-storage-downloads"', 'kubenix.lib.sharedStorage.downloadsPVC')
        
        if content != original_content:
            print(f"Updated {filename}")
            with open(filename, "w") as f:
                f.write(content)
        else:
            print(f"No changes needed for {filename}")
    except Exception as e:
        print(f"Error processing {filename}: {e}")

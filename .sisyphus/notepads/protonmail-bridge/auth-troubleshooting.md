# ProtonMail Bridge Authentication

## Current Status
- Bridge is running in CLI mode with TTY enabled
- kubectl attach/exec TTY issues preventing direct CLI access

## Alternative Authentication Methods

### Method 1: Non-Interactive Setup Script
Create a script that runs inside the pod to automate login:

```bash
#!/bin/bash
# Run this inside the pod via kubectl exec without TTY

# Kill existing bridge
pkill -9 proton-bridge 2>/dev/null
rm -f /root/.cache/protonmail/bridge-v3/bridge-v3.lock

# Start bridge with input redirection
echo -e "login\nyour-email@proton.me\nyour-password\ninfo\nexit" | /protonmail/proton-bridge --cli
```

### Method 2: Use expect (if available)
Install expect and create an expect script to automate the interactive prompts.

### Method 3: Direct API/Config
Check if proton-bridge supports credential files or env vars for non-interactive auth.

### Method 4: Web Interface
Some bridge versions have a web interface on localhost that could be port-forwarded.

## Recommended Next Steps

1. Try Method 1 with echo pipe
2. If that fails, install expect in the container
3. Or modify deployment to use hostNetwork and access via local browser

## Commands to Try

```bash
# Method 1 - Echo pipe approach
kubectl exec -n apps protonmail-bridge-0 -- /bin/bash -c "
  pkill -9 proton-bridge 2>/dev/null
  rm -f /root/.cache/protonmail/bridge-v3/bridge-v3.lock
  sleep 1
  echo -e 'login\nyour-email@proton.me\nyour-password' | /protonmail/proton-bridge --cli
"
```

```bash
# Install expect and use it
kubectl exec -n apps protonmail-bridge-0 -- apt-get install -y expect

# Then create expect script
```

## Note
The kubectl TTY issues might be environment-specific. The bridge itself is working - it's just the interactive access that's problematic.

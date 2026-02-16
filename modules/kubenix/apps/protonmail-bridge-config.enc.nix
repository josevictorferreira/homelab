{ kubenix, homelab, ... }:

{
  imports = [
    ./protonmail-bridge.nix
  ];

  # ProtonMail Bridge uses interactive CLI authentication
  # No additional secrets or configuration needed here
}

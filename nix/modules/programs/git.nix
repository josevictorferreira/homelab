{ pkgs, ... }:
{
  programs.git = {
    enable = true;
    config = {
      user.name = "Jose Victor Ferreira";
      user.email = "root@josevictor.me";
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
      push.followTags = true;
      pull.rebase = true;
      fetch = {
        prune = true;
        tags = true;
      };
    };
  };
}

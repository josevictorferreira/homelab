{ ... }:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    enableLsColors = true;

    shellAliases = {
      ll = "ls -l";
      la = "ls -la";
      l = "ls -CF";
      g = "git";
      v = "vim";
      c = "clear";
      h = "history";
      grep = "grep --color=auto";
      m = "make";
    };

    ohMyZsh = {
      enable = true;
      plugins = [
        "git"
        "z"
      ];
      theme = "robbyrussell";
    };

    histSize = 10000;
  };
}

{ pkgs, ... }:
{
  environment.variables = { EDITOR = "vim"; };

  environment.systemPackages = with pkgs; [
    ((vim_configurable.override {  }).customize{
      name = "vim";
      # Install plugins for example for syntax highlighting of nix files
      vimrcConfig.packages.myplugins = with pkgs.vimPlugins; {
        start = [ vim-nix vim-lastplace ];
        opt = [];
      };
      vimrcConfig.customRC = ''
        set number
        set relativenumber
        set expandtab
        set shiftwidth=4
        set tabstop=4
        set background=dark
        set nocompatible
        set backspace=indent,eol,start
        syntax on
        set clipboard=unnamedplus
      '';
    }
  )];
}

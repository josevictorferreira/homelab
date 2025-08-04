{ lib, config, pkgs, ... }:

let
  cfg = config.programs.vim;
in
{
  options.programs.vim = {
    enable = lib.mkEnableOption "Enable Vim as default editor";
  };

  config = lib.mkIf cfg.enable {
    environment.variables = { EDITOR = "vim"; };

    environment.systemPackages = with pkgs; [
      ((vim_configurable.override { }).customize {
        name = "vim";
        vimrcConfig.packages.myplugins = with pkgs.vimPlugins; {
          start = [ vim-nix vim-lastplace ];
          opt = [ ];
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
      )
    ];
  };
}

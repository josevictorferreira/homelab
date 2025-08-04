{ lib, config, ... }:

let
  cfg = config.locale;
in
{
  options.locale = {
    enable = lib.mkEnableOption "Enable locale settings";
    timeZone = lib.mkOption {
      type = lib.types.str;
      default = "UTC";
      description = "The system time zone.";
    };
    defaultLocale = lib.mkOption {
      type = lib.types.str;
      default = "en_US.UTF-8";
      description = "The default locale for the system.";
    };
    xkbLayout = lib.mkOption {
      type = lib.types.str;
      default = "us";
      description = "The keyboard layout.";
    };
  };

  config = lib.mkIf cfg.enable {
    time.timeZone = cfg.timeZone;
    i18n.defaultLocale = cfg.defaultLocale;
    services.xserver.xkb.layout = cfg.xkbLayout;
    i18n.locales = [ cfg.defaultLocale ];
  };
}

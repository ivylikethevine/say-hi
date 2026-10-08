# SPDX-License-Identifier: MIT
# The home-manager module: what `hi --install` does for a clone, said through
# home-manager's own options - the package on the profile and hi's rc block in
# each shell home-manager manages. It writes no file of its own, and settings
# stay in ~/.config/say-hi.
#
# The blocks are scripts/rc.sh's rc_lines, line for line, and each line is
# tagged as rc_tagged tags it: the tag is how `hi --doctor` and `hi --install`
# know an rc is wired, and neither can rewrite a file home-manager owns.
# tests/packaging/packaging_ci_test.sh fails when the two part.
self:
{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  cfg = config.programs.say-hi;

  home = "${cfg.package}/share";

  marker = "# added by hi during install";
  tag =
    line:
    let
      pad = lib.max 0 (45 - builtins.stringLength line);
    in
    "${line}${lib.concatStrings (lib.genList (_: " ") pad)} ${marker}";
  tagged =
    block:
    lib.concatMapStrings (line: "${tag line}\n") (lib.splitString "\n" (lib.removeSuffix "\n" block));

  bash =
    let
      rc = "${home}/say-hi/common/bash.sh";
    in
    ''
      export _HI_HOME="${home}"
      [[ $- == *i* && -r "${rc}" ]] && source "${rc}"
    '';

  zsh =
    let
      rc = "${home}/say-hi/common/zsh.zsh";
    in
    ''
      export _HI_HOME="${home}"
      [ -r "${rc}" ] && source "${rc}"
    '';

  fish =
    let
      rc = "${home}/say-hi/common/config.fish";
    in
    ''
      set -gx _HI_HOME "${home}"
      if status is-interactive; and test -r "${rc}"
        if string match -qr '^([4-9]|3\.([4-9]|[1-9][0-9]))\.' -- $version
          source "${rc}"
        else
          echo "hi needs fish 3.4 or newer (this is $version); not loaded" >&2
        end
      end
    '';
in
{
  options.programs.say-hi = {
    enable = lib.mkEnableOption "say-hi, your shell config on every host you say hi to";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "say-hi.packages.\${pkgs.stdenv.hostPlatform.system}.default";
      description = "The say-hi package whose tree the shells source.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    programs.bash.initExtra = tagged bash;
    programs.fish.interactiveShellInit = tagged fish;
    # initContent replaced initExtra in home-manager 25.05
    programs.zsh =
      if options.programs.zsh ? initContent then
        { initContent = tagged zsh; }
      else
        { initExtra = tagged zsh; };
  };
}

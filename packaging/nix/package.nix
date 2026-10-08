# SPDX-License-Identifier: MIT
# The package flake.nix builds: scripts/install.sh's packaging mode stages the
# tree, as every other channel has it do, and the staged files move under $out.
{
  lib,
  stdenvNoCC,
  runtimeShell,
  src,
  version,
  # the man page's date; packaging/stamp.sh refuses to guess one
  date,
}:

stdenvNoCC.mkDerivation {
  pname = "say-hi";
  inherit version src;

  # install.sh finds the tree as $_HI_HOME/say-hi, so the unpacked source has
  # to be a directory of that name
  postUnpack = ''
    mv "$sourceRoot" say-hi
    sourceRoot=say-hi
  '';

  dontConfigure = true;
  dontBuild = true;

  # The tree is what a session sends to a target, where an interpreter path
  # into the nix store does not exist.
  dontPatchShebangs = true;

  # Run through bash by name: the build sandbox has no /usr/bin/env for the
  # scripts' own shebangs. install_tree's /usr/bin link and /etc/profile.d
  # snippet name paths a store has none of, and stay behind in the stage.
  installPhase = ''
    runHook preInstall

    stage="$NIX_BUILD_TOP/stage"
    DESTDIR="$stage" bash scripts/install.sh --prefix /usr/share
    bash packaging/stamp.sh --root "$stage" --version "$version" --date ${lib.escapeShellArg date}

    mkdir -p "$out/bin" "$out/share"
    mv "$stage/usr/share/say-hi" "$stage/usr/share/man" "$out/share/"

    # A wrapper, not a link: the export is what a new process (tmux's
    # update-environment, another machine's hi probing this one) reads the
    # tree's place from.
    cat >"$out/bin/hi" <<EOF
    #!${runtimeShell}
    export _HI_HOME="$out/share"
    exec ${runtimeShell} "$out/share/say-hi/hi.sh" "\$@"
    EOF
    chmod 0755 "$out/bin/hi"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    got="$("$out/bin/hi" --version)"
    want="$version (package at $out/share/say-hi)"
    [ "$got" = "$want" ] || {
      echo "hi --version: got [$got], want [$want]" >&2
      exit 1
    }

    runHook postInstallCheck
  '';

  meta = {
    description = "Your shell config, on every host you say hi to - sshrc supercharged";
    homepage = "https://github.com/ivylikethevine/say-hi";
    license = lib.licenses.mit;
    mainProgram = "hi";
    platforms = lib.platforms.unix;
  };
}

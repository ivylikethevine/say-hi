# The tap formula. Publish by copying this file to Formula/say-hi.rb in a repo
# named ivylikethevine/homebrew-tap; `brew install ivy/tap/say-hi` then works with
# no review and no approval. packaging/bump.sh rewrites the url and sha256.
#
# say-hi.rb -> class SayHi: Homebrew's Formulary.class_s camel-cases across the dash.
class SayHi < Formula
  # capitalised because `brew audit --strict` requires it; the other channels
  # keep the "sshrc supercharged" phrasing, which no linter of theirs objects to
  desc "Your shell config, on every host you say hi to - sshrc supercharged"
  homepage "https://github.com/ivylikethevine/say-hi"
  url "https://github.com/ivylikethevine/say-hi/releases/download/v0.1.2/say-hi-0.1.2.tar.gz"
  sha256 "643879e8c1c43323046c83d08438faaca967c4df49c943381f91d41ee8d29cae"
  license "MIT"
  head "https://github.com/ivylikethevine/say-hi.git", branch: "main"

  # No dependencies at all, deliberately.
  #
  # `ssh` and `base64` are the two binaries hi cannot work without, and both
  # ship with macOS and with every Linux base system this formula could land
  # on. `uses_from_macos "openssh"` was here and `brew audit --strict` rejects
  # it - that macro is for formulae macOS provides *to Homebrew*, which openssh
  # is not. `depends_on "openssh"` would be worse: it would build a second sshd
  # on Linux for a client hi already has.
  #
  # No `depends_on "bash"` either: hi is written for bash 3.2 precisely so that
  # macOS's own /bin/bash can run it.

  def install
    # This list is _HI_PACKAGE_CONTENTS in scripts/install.sh, repeated because
    # a formula cannot call install.sh: install_tree hardcodes /usr/bin and
    # /etc/profile.d, neither of which exists inside a brew prefix. The
    # packaging suite (tests/packaging/packaging_test.sh) fails if the two lists
    # drift apart.
    #
    # It must land in a directory named say-hi - every path in the project
    # resolves against $_HI_HOME/say-hi, so libexec is the _HI_HOME here.
    (libexec/"say-hi").install "common", "scripts", "settings",
                               "hi.sh", "load.sh", "LICENSE.md", "README.md"
    chmod 0755, libexec/"say-hi/hi.sh"

    # The keg's copy of hi.sh, and the man page's .TH footer, answer with the
    # formula's version. The tarball carries no stamp - every channel writes it
    # at build time, and packaging/stamp.sh is the one implementation they all
    # call (see its header for why not in git). packaging/ rides the tarball
    # but is deliberately not installed: it is build-time only.
    #
    # --date is the version here rather than a day, and only here: the other
    # channels have a real $SOURCE_DATE_EPOCH to date the page by, and a
    # formula build has none - Time.now would make every keg build differ.
    # stamp.sh refuses to guess a date, so this has to be said out loud.
    #
    # Two explicit paths rather than --root: brew's launcher and man page are
    # unrelated locations, not one install_tree layout. The page is installed
    # plain, on brew's manpath, rather than gzipped into /usr/share.
    system buildpath/"packaging/stamp.sh", "--version", version,
           "--date", version,
           "--launcher", libexec/"say-hi/hi.sh",
           "--man", buildpath/"docs/hi.1"
    man1.install "docs/hi.1"

    # A wrapper rather than bin.install_symlink. Not because hi.sh needs it to
    # find itself - it walks the symlink and would resolve the keg fine
    # (GLOSSARY: HI.33) - but because the `export` puts _HI_HOME in the
    # environment the session inherits. That is the job install.sh's rc line
    # does on every other channel, and a formula does not write rc files.
    (bin/"hi").write <<~SH
      #!/bin/sh
      export _HI_HOME="#{libexec}"
      exec "#{libexec}/say-hi/hi.sh" "$@"
    SH
  end

  def caveats
    <<~EOS
      `hi` is on your PATH now, but your shells are not wired up yet. To get the
      header, prompt, aliases and editor configs in your own shells, run:

        #{libexec}/say-hi/scripts/install.sh --no-link

      That writes only to your rc files and ~/.config/say-hi - never into the keg.
      --no-link is what skips the /usr/bin/hi symlink: Homebrew already put `hi`
      on your PATH, and on macOS /usr/bin is read-only under SIP anyway.

      Re-run it as `hi --configure` any time to revisit the feature toggles.
      `hi --update` will tell you to update through Homebrew, which is correct -
      run `brew upgrade say-hi` instead.
    EOS
  end

  test do
    # The wiring that actually matters and the thing most likely to break: the
    # tree is where _HI_HOME says it is, and sourcing core.sh from the keg
    # resolves _HI_ROOT back to the keg rather than to $HOME.
    assert_equal "#{libexec}/say-hi", shell_output(
      "_HI_HOME=#{libexec} /bin/bash -c 'source #{libexec}/say-hi/common/core.sh; printf %s \"$_HI_ROOT\"'",
    )

    # ...and that the wrapper exports it for a caller who has not.
    assert_match libexec.to_s, (bin/"hi").read
  end
end

# Runs a Homebrew formula's real `def install` without brew, against a tag's tree
# laid out as the release tarball is, then checks what `hi --version` and the man
# page answer. Stubs only what the formula calls, with Pathname#install moving as
# brew's does. No sandbox, bottle or audit: a mac's brew job still has the last word.
#
#   ruby scratch/formula_install.rb packaging/homebrew/say-hi.rb v0.8.3
require "fileutils"
require "open3"
require "pathname"
require "tmpdir"

class Pathname
  def install(*sources)
    mkpath
    sources.each { |s| FileUtils.mv(s.to_s, join(File.basename(s.to_s)).to_s) }
  end

  def write(content)
    dirname.mkpath
    File.write(to_s, content)
  end
end

class Formula
  include FileUtils

  %i[desc homepage url sha256 license head test].each do |dsl|
    define_singleton_method(dsl) { |*_args, **_opts, &_blk| nil }
  end

  attr_reader :buildpath, :version, :prefix

  def initialize(buildpath, prefix, version)
    @buildpath = buildpath
    @prefix = prefix
    @version = version
  end

  def libexec = prefix/"libexec"
  def bin = prefix/"bin"
  def man1 = prefix/"share/man/man1"

  def system(*args)
    Kernel.system(*args.map(&:to_s)) or abort("FAILED: #{args.join(" ")}")
  end
end

formula, ref = ARGV
abort("usage: formula_install.rb <formula.rb> <tag>") unless formula && ref
load File.expand_path(formula)
version = ref.delete_prefix("v")

ENV.delete_if { |name, _| name.start_with?("_HI_") }

Dir.mktmpdir("formula_install.") do |tmp|
  root = Pathname(tmp).realpath
  archive = root/"src.tar"
  Kernel.system("git", "archive", "--prefix=say-hi-#{version}/", "-o", archive.to_s, ref, exception: true)
  Kernel.system("tar", "-x", "-f", archive.to_s, "-C", root.to_s, exception: true)
  ENV["HOME"] = (root/"home").tap(&:mkpath).to_s
  ENV["XDG_CONFIG_HOME"] = (root/"home/.config").to_s

  build = root/"say-hi-#{version}"
  prefix = root/"Cellar/say-hi/#{version}"
  Dir.chdir(build) { SayHi.new(build, prefix, version).install }
  (prefix/"bin/hi").chmod(0o755)

  got, status = Open3.capture2e((prefix/"bin/hi").to_s, "--version")
  want = "#{version} (package at #{prefix}/libexec/say-hi)"
  abort("FAILED: hi --version: #{got}") unless status.success? && got.include?(want)
  th = (prefix/"share/man/man1/hi.1").readlines.grep(/^\.TH /).first.to_s
  abort("FAILED: man page: #{th}") unless th.include?(%("say-hi #{version}"))
  puts "ok: #{got.lines.first.to_s.strip}", "ok: #{th.strip}"
end

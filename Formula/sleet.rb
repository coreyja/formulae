# -*- ruby -*-

require 'formula'
require 'fileutils'

BREWGEM_RUBYBINDIR = '/usr/local/bin'
BREWGEM_GEM_PATH = "#{BREWGEM_RUBYBINDIR}/gem"
BREWGEM_RUBY_PATH = "#{BREWGEM_RUBYBINDIR}/ruby"

class RubyGemsDownloadStrategy < AbstractDownloadStrategy
  def fetch
    ohai "Fetching sleet from gem source"
    HOMEBREW_CACHE.cd do
      ENV['GEM_SPEC_CACHE'] = "#{HOMEBREW_CACHE}/gem_spec_cache"
      system BREWGEM_GEM_PATH, "fetch", "sleet", "--version", resource.version
    end
  end

  def cached_location
    Pathname.new("#{HOMEBREW_CACHE}/sleet-#{resource.version}.gem")
  end

  def clear_cache
    cached_location.unlink if cached_location.exist?
  end
end

class Sleet < Formula
  url "sleet", :using => RubyGemsDownloadStrategy
  version "0.4.0"
  sha256 '3952899f88c3b40c32925ff01d2a0fbeda194392dbfa67e6e40d6a3e934ce52c'
  depends_on 'ruby'
  depends_on 'cmake' => :build

  def install
    # Copy user's RubyGems config to temporary build home.
    buildpath_gemrc = "#{ENV['HOME']}/.gemrc"
    if File.exists?("#{ENV['HOME']}/.gemrc") && !File.exists?(buildpath_gemrc)
      FileUtils.cp("#{ENV['HOME']}/.gemrc", buildpath_gemrc)
    end

    # set GEM_HOME and GEM_PATH to make sure we package all the dependent gems
    # together without accidently picking up other gems on the gem path since
    # they might not be there if, say, we change to a different rvm gemset
    ENV['GEM_HOME']="#{prefix}"
    ENV['GEM_PATH']="#{prefix}"

    # Use /usr/local/bin at the front of the path instead of Homebrew shims,
    # which mess with Ruby's own compiler config when building native extensions
    if defined?(HOMEBREW_SHIMS_PATH)
      ENV['PATH'] = ENV['PATH'].sub(HOMEBREW_SHIMS_PATH.to_s, '/usr/local/bin')
    end

    system BREWGEM_GEM_PATH, "install", cached_download,
             "--no-ri",
             "--no-rdoc",
             "--no-wrapper",
             "--no-user-install",
             "--install-dir", prefix,
             "--bindir", bin

    raise "gem install 'sleet' failed with status #{$?.exitstatus}" unless $?.success?

    bin.rmtree if bin.exist?
    bin.mkpath

    brew_gem_prefix = prefix+"gems/sleet-#{version}"

    completion_for_bash = Dir[
                            "#{brew_gem_prefix}/completion{s,}/sleet.{bash,sh}",
                            "#{brew_gem_prefix}/**/sleet{_,-}completion{s,}.{bash,sh}"
                          ].first
    bash_completion.install completion_for_bash if completion_for_bash

    completion_for_zsh = Dir[
                           "#{brew_gem_prefix}/completions/sleet.zsh",
                           "#{brew_gem_prefix}/**/sleet{_,-}completion{s,}.zsh"
                         ].first
    zsh_completion.install completion_for_zsh if completion_for_zsh

    gemspec = Gem::Specification::load("#{prefix}/specifications/sleet-#{version}.gemspec")
    ruby_libs = Dir.glob("#{prefix}/gems/*/lib")
    gemspec.executables.each do |exe|
      file = Pathname.new("#{brew_gem_prefix}/#{gemspec.bindir}/#{exe}")
      (bin+file.basename).open('w') do |f|
        f << <<-RUBY
#!#{BREWGEM_RUBY_PATH} --disable-gems
ENV['GEM_HOME']="#{prefix}"
ENV['GEM_PATH']="#{prefix}"
require 'rubygems'
$:.unshift(#{ruby_libs.map(&:inspect).join(",")})
load "#{file}"
        RUBY
      end
    end
  end
end

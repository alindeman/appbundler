require "appbundler/version"
require 'bundler'
require 'pp'

module Appbundler

  class App

    BINSTUB_FILE_VERSION=1

    attr_reader :app_root
    attr_reader :target_bin_dir

    def self.demo
      demo = new("/Users/ddeleo/oc/chef")

      knife = demo.executables.grep(/knife/).first
      puts demo.binstub(knife)
    end

    def initialize(app_root, target_bin_dir)
      @app_root = app_root
      @target_bin_dir = target_bin_dir
    end

    def write_executable_stubs
      executables.each do |real_executable_path|
        basename = File.basename(real_executable_path)
        File.open(File.join(target_bin_dir, basename), "wb", 0755) do |f|
          f.write(binstub(real_executable_path))
        end
      end
    end

    def name
      File.basename(app_root)
    end

    def gemfile_lock
      File.join(app_root, "Gemfile.lock")
    end

    def shebang
      "#!#{Gem.ruby}\n"
    end

    # A specially formatted comment that documents the format version of the
    # binstub files we generate.
    #
    # This comment should be unusual enough that we can reliably (enough)
    # detect whether a binstub was created by Appbundler and parse it to learn
    # what version of the format it uses. If we ever need to support reading or
    # mutating existing binstubs, we'll know what file version we're starting
    # with.
    def file_format_comment
      "#--APP_BUNDLER_BINSTUB_FORMAT_VERSION=#{BINSTUB_FILE_VERSION}--\n"
    end

    # Ruby code (as a string) that clears GEM_HOME and GEM_PATH environment
    # variables. In an omnibus context, this is important so users can use
    # things like rvm 
    def env_sanitizer
      %Q{ENV["GEM_HOME"] = ENV["GEM_PATH"] = nil}
    end

    def runtime_activate
      @runtime_activate ||= begin
        statements = runtime_dep_specs.map {|s| %Q|gem "#{s.name}", "= #{s.version}"|}
        activate_code = ""
        activate_code << env_sanitizer << "\n"
        activate_code << statements.join("\n") << "\n"
        activate_code << %Q|$:.unshift "#{app_lib_dir}"\n|
        activate_code
      end
    end

    def binstub(bin_file)
      shebang + file_format_comment + runtime_activate + "Kernel.load '#{bin_file}'\n"
    end

    def executables
      bin_dir_glob = File.join(app_root, "bin", "*")
      Dir[bin_dir_glob]
    end

    def app_lib_dir
      File.join(app_root, "lib")
    end

    def runtime_dep_specs
      add_dependencies_from(app_spec)
    end

    def app_dependency_names
      @app_dependency_names ||= app_spec.dependencies.map(&:name)
    end

    def app_spec
      spec_for(name)
    end

    def gemfile_lock_specs
      parsed_gemfile_lock.specs
    end

    def parsed_gemfile_lock
      @parsed_gemfile_lock ||= Bundler::LockfileParser.new(IO.read(gemfile_lock))
    end

    private

    def add_dependencies_from(spec, collected_deps=[])
      spec.dependencies.each do |dep|
        next if collected_deps.any? {|s| s.name == dep.name }
        next_spec = spec_for(dep.name)
        collected_deps << next_spec
        add_dependencies_from(next_spec, collected_deps)
      end
      collected_deps
    end

    def spec_for(dep_name)
      gemfile_lock_specs.find {|s| s.name == dep_name } or raise "No spec #{dep_name}"
    end
  end

end

if __FILE__ == $PROGRAM_NAME
  Appbundler::App.demo
end
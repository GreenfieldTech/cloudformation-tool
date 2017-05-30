require 'zlib'
require 'yaml'
require 'base64'

module CloudFormationTool
  class CloudInit
    include Storable
    
    attr_reader :path
    
    def initialize(path)
      @path = path
      log "Loading #{path}"
      begin
        @initfile = YAML.load(File.read(path)).to_h
      rescue Errno::ENOENT => e
        raise CloudFormationTool::Errors::AppError.new("Error reading #{@path}: " + e.message)
      end
    end
  
    def compile
      basepath = File.dirname(path)
      basepath = "." if basepath.empty?
      @initfile['write_files'] = (@initfile['write_files'] || []).collect do |file|
        if file['file']
          begin
            read_file_content(basepath + "/" + file.delete('file'), file)
          rescue Errno::EISDIR => e
            raise CloudFormationTool::Errors::AppError, "#{path} - error loading embedded file for #{file['path']}: " + e.message
          rescue Errno::ENOENT => e
            raise CloudFormationTool::Errors::AppError, "#{path} - error loading embedded file for #{file['path']}: " + e.message
          end
        else
          file
        end
      end
      @initfile['write_files'] += (@initfile.delete('write_directories') || []).collect do |directory|
        realdir = "#{basepath}/#{directory['source']}"
        raise CloudFormationTool::Errors::AppError.new("Cloud-init file #{path} references missing directory #{realdir}") unless File.exist? realdir
        read_dir_files(realdir, directory['target'])
      end.flatten
      "#cloud-config\n" + @initfile.to_yaml
    end
    
    def encode(allow_gzip = true)
      yamlout = compile
      if allow_gzip and yamlout.size > 16384 # max AWS EC2 user data size - try compressing it
        yamlout = Zlib::Deflate.new(nil, 31).deflate(yamlout, Zlib::FINISH) # 31 is the magic word to have deflate create a gzip compatible header
      end
      if yamlout.size > 16384 # still to big, we should upload to S3 and create an include file
        url = upload  make_filename('init'),
                      yamlout, 'text/cloud-config'
        log "Wrote cloud config to #{url}"
        [ "#include", url ].join "\n"  
      else
        yamlout
      end
    end
    
    def read_file_content(filepath, spec)
      spec['encoding'] = 'base64'
      spec['content'] = Base64.strict_encode64(File.read(filepath))
      spec
    end
    
    def read_dir_files(source, target)
      Dir.entries(source).select do |entry|
        entry !~ /^\.{1,2}$/
      end.collect do |entry|
        path = source + "/" + entry
        targetpath = target + "/" + entry
        if File.directory? path
          read_dir_files(path, targetpath)
        else
          [ read_file_content(path, {
            'path' => targetpath,
            'permissions' => (("%o" % File.stat(path).mode)[-4..-1])
          }) ]
        end
      end.flatten
    end
    
    def to_base64
      Base64.encode64(encode)
    end
    
  end
end

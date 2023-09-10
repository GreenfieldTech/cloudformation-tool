require 'yaml'
require 'base64'

module CloudFormationTool
  class CloudFormation
    
    Autoloaded.class {  }
    
    def self.parse(path)
      CloudFormation.new(path)
    end
    
    attr_reader :basedir
    
    def initialize(path)
      $MAX_USER_DATA_SIZE = 16384 if $MAX_USER_DATA_SIZE.nil?
      log "Loading #{path}"
      @path = path
      @path = "#{@path}/cloud-formation.yaml" if File.directory? @path
      @path = "#{@path}.yaml" if !File.exist? @path and File.exist? "#{@path}.yaml"
      @basedir = File.dirname(@path)
      @compiled = false
      @params = nil
      begin
        text = File.read(@path)
        # remove comments because white space seen between comments can seriously psych Psych
        text.gsub!(/^#.*\n/,'')
        text = fixShorthand(text)
        @data = YAML.load(text, filename: @path, permitted_classes: [Date, Symbol]).to_h
      rescue Psych::SyntaxError => e
        e.message =~ /line (\d+) column (\d+)/
        lines = text.split "\n"
        raise CloudFormationTool::Errors::AppError, "Error parsing #{path} at line #{e.line} column #{e.column}:\n" +
          "#{lines[e.line-1]}\n" +
          "#{(' ' * (e.column - 1 ))}^- #{e.problem} #{e.context}"
      rescue Errno::ENOENT => e
        raise CloudFormationTool::Errors::AppError, "Error reading #{path}: #{e.message}"
      end
    end
    
    def compile(parameters = nil)
      @params = parameters unless parameters.nil?
      embed_includes
      @data = load_files(@data)
    end
    
    def to_yaml(parameters = {})
      @params = parameters
      compile.to_yaml
    end
    
    def fixShorthand(text)
      text.gsub(/(?:(\s*)([^![:space:]]+))?(\s+)!(\w+)/) do |match|
        case $4
        when *%w(Base64 FindInMap GetAtt GetAZs ImportValue Join Select Sub Split
          And Equals If Not Or)
          ($2.nil? ? "" : "#{$1}#{$2}\n#{$1} ") + "#{$3}\"Fn::#{$4}\":"
        when 'Ref'
          "#{$1}#{$2}\n#{$1} #{$3}#{$4}:"
        else
          match
        end
      end
    end
    
    def fixrefs(data, rmap)
      case data
      when Hash
        data.inject({}) do |h,(k,v)|
          h[k] = if k == "Ref"
            rmap[v] || v
          else
            fixrefs(v,rmap)
          end
          h
        end
      when Array
        data.collect do |item|
          fixrefs(item, rmap)
        end
      else
        return data
      end
    end
   
    def embed_includes_future
      (@data.delete(@data.keys.find{|k| k.start_with? 'Include'}) || []).each do |path|
        case path
        when Hash
        when String
          embed_included_path path
        end
      end
    end
    
    def embed_includes
      (@data.delete(@data.keys.find{|k| k.start_with? 'Include'}) || []).each do |path|
        realpath = "#{@basedir}/#{path}"
        cfile_key = File.dirname(realpath).gsub(%r{/(.)}){|m| $1.upcase }.gsub(/\W+/,'')
        rewrites = Hash.new
        CloudFormation.new(realpath).compile.each do |category, catdata|
          # some categories are meta-data that we can ignore from includes
          next if %w(AWSTemplateFormatVersion Description).include? category
          
          case category
          when "Parameters"
            (@data[category]||={}).each do |name, param|
              if catdata.has_key? name
                next if param['Default'] == catdata[name]['Default']
                 
                if catdata[name].has_key?('Override') and catdata[name]['Override'] == false
                  catdata.delete(name)
                else
                  newname = "#{cfile_key}z#{name}"
                  log "Rewriting conflicting parameter #{name} (='#{catdata[name]['Default']}') to #{newname}"
                  catdata[newname] = catdata.delete name
                  rewrites[name] = newname
                end
              else
                @data[category][name] = param
              end
            end
          else
            case catdata
            when Hash
              # warn against duplicate entities, resources or outputs
              (@data[category] ||= {}).keys.each do |key|
                if catdata.has_key? key
                  raise CloudFormationTool::Errors::AppError, "Error compiling #{path} - duplicate '#{category}' item: #{key}"
                end 
              end
              catdata = fixrefs(catdata, rewrites)
              # add included properties
              @data[category].merge! catdata
            when Array
              if @data[category].nil?
                @data[category] = catdata
              elsif @data[category].is_a? Array
                @data[category] += catdata
              else
                raise CloudFormationTool::Errors::AppError, "Error compiling #{path} - conflicting types for '#{category}'"
              end
            else
              if @data[category].nil?
                @data[category] = catdata
              else
                raise CloudFormationTool::Errors::AppError, "Error compiling #{path} - I do not know how to merge non-list non-dictionary '#{category}'!"
              end
            end
          end
          
        end
      end
    end
    
    def resolveVal(value)
      case value
      when Hash
        if value.key? 'Ref'
          if @params.nil?
            # no parameters, we are probably in a sub template, just return the ref and hope
            # a parent template has what it takes to resolve the ref
            value
          else # parameters are set for this template - we can try to resolve
            res = @params[value['Ref']] || ((@data['Parameters']||{})[value['Ref']] || {})['Default']
            if res.nil?
              raise CloudFormationTool::Errors::AppError, "Reference #{value['Ref']} can't be resolved"
            end
            res
          end
        else
          raise CloudFormationTool::Errors::AppError, "Value #{value} is not a valid value or reference"
        end
      else
        value
      end
    end
    
    def load_files(data, restype = nil)
      case data
      when Array
        data.collect { |data| load_files(data, restype) }
      when Hash
        # remember the current resource type
        restype = data['Type'] if restype.nil? and data.key?('Type')
        data.inject({}) do |dict, (key, val)|
          dict[key] = case restype
            when 'AWS::AutoScaling::LaunchConfiguration', 'AWS::EC2::LaunchTemplate'
              if (key == "UserData") and (val["File"]) 
                # Support LaunchConfiguration UserData from file
                CloudInit.new("#{@basedir}/#{val["File"]}").to_base64
              elsif (key == "UserData") and (val["FileTemplate"]) 
                # Support LaunchConfiguration UserData from file with substitutions
                { "Fn::Base64" => { "Fn::Sub" => CloudInit.new("#{@basedir}/#{val["FileTemplate"]}").compile } }
              else
                load_files(val, restype)
              end
            when 'AWS::Lambda::Function'
              if key == 'Code'
                LambdaCode.new(val, self, data['Runtime']).to_cloudformation
              else
                load_files(val, restype)
              end
            when 'AWS::CloudFormation::Stack'
              if key == 'Properties' and val.key?('Template')
                NestedStack.new(val, self).to_cloudformation
              else
                load_files(val, restype)
              end
            else
              load_files(val, restype)
          end
          dict
        end
      else
        data
      end
    end
    
    def each
      compile['Parameters'].each do |name, param|
        yield name, param['Default']
      end
    end
  end
end

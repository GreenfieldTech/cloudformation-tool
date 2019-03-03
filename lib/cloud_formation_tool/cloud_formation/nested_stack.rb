module CloudFormationTool
  class CloudFormation
    
    class NestedStack
      include Storable
      
      def initialize(props, tpl)
        @tpl = tpl
        @data = props
        if props.key?('Template')
          path = props['Template']
          path = if path.start_with? "/" then path else "#{@tpl.basedir}/#{path}" end
          @content = CloudFormation.new(path).to_yaml
          @data['TemplateURL'] = upload(make_filename('yaml'), @content, mime_type: 'text/yaml', gzip: false)
          @data.delete('Template')
        end
      end
      
      def to_cloudformation
        @data
      end

    end
  end
end

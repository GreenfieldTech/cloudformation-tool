require 'set'

module CloudFormationTool
  module CLI
    
    class Recycle < Clamp::Command
      include CloudFormationTool
      
      parameter "STACK_NAME", "Name of the stack to recycle servers in"
      parameter "ASG_NAME", "Name of the auto scaling group in which to recycle all servers"
      
      def execute
        st = CloudFormation::Stack.new(stack_name)
        st.asgroups.select do |res|
          asg_name.nil? or (res.logical_resource_id == asg_name)
        end.collect do |res|
          Thread.new do
            grp = res.group
            torecycle = cursize = grp.instances.size
            puts "#{grp.name}: Recyclying #{cursize} instance" + (cursize > 1 ? "s" : "")
            while torecycle > 0
              grp.set_desired_capacity(desired_capacity: (cursize + 1))
              while grp.instances.size != (cursize + 1)
                sleep 5
                grp.reload
              end 
              grp.set_desired_capacity(desired_capacity: cursize)
              while grp.instances.size != cursize
                sleep 5
                grp.reload
              end 
              torecycle -= 1
              puts "#{grp.name}: Left to recycle - #{torecycle}"
            end
          end
        end.each(&:join)
      end
    end
  end
end
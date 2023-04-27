VERSION := $(shell ruby -r ./lib/cloud_formation_tool/version.rb -e 'puts CloudFormationTool::VERSION')

all: cloudformation-tool-$(VERSION).gem

%.gem:
	gem build
	[ -f $*.gem ]

push: cloudformation-tool-$(VERSION).gem
	gem push cloudformation-tool-$(VERSION).gem

clean:
	rm -f cloudformation-tool-*.gem

.PHONY: all clean push

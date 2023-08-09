# cloudformation-tool

A pre-compiler for CloudFormation YAML files, allowing modularization of large CloudFormation
templates. 

By breaking a large template into distinct modules, including allowing parts to be
loaded from git submodules or even to be downloaded on the fly, very large CloudFormation 
configurations become manageable and useful.

## Syntax

This tool is based on the CloudFormation YAML syntax (as it is a bit more human friendly than
the original JSON syntax) and extend it with a few more operation to allow for the 
modularization of templates. The following additional syntaxes are supported:

### Including Additional Sub-templates

The CloudFormation pre-compiler introduces a new top-level element called `Include`.

This element specifies a list of additional template files to be loaded and merged into
the current template file. 

Loading is done using the same file resolution rules as the
`compile` CLI command:
 - resolution is done relative to the directory of the current file
 - if the path specified is missing the `.yaml` extension and a valid file with the extension
   exist, it will be loaded instead.
 - if the path specified is a directory, the file `cloud-formation.yaml` will be loaded 
   from that directory

The merged file must be a valid CloudFormation template - it should have at least a top-level
`Resources` entry and can have any other top-level entry that a standard CloudFormation
template can include (see below regarding the merging of parameters). The sub-template will
be merged back to the top template without nesting - e.g. all resources specified in a
sub-template are standard resources in the top-level `Resources` list.

As logical resource names as well as parameters are merged into a single name space, these
can be referenced directly from any file. Unless as specified for parameter merging below, the
names used can be directly addressed as done in a normal CloudFormation template.

#### Parameter merging

A sub-template may specify parameters just like a standard CloudFormation template, and as
long as each parameter is specified uniquely (i.e. only once) in the entire set of sub-templates
that are being loaded, then they are just merged into a flat list and all parameters can be
used equally from all sub-templates.

If the same parameter name is mentioned in more than one file, then special merging rules take
effect:
 1. If the same parameter is named in more than one file, and in all instances the default
    value is exactly the same, than the merging is done normally - we basically ignore the
    duplicate settings.
 1. If the same parameter is named in more than one file, and uses different default value,
    then the new parameter is renamed using a path-specific template (i.e. based on the path
    to the sub-template where the new copy was encountered) and any use of that parameter in
    the current sub-template is also renamed automatically, as if there is full scoping of the
    nested sub-template (though the mangled name is not very readable due to YAML restrictions
    on the available characters for names). Uses of the duplicate parameter in sub-templates
    other than the one where it was defined should use the mangled form if they mean the new
    parameter or the original form if they mean the original parameter

#### Example:

```
AWSTemplateFormatVersion: "2010-09-09"
Description: "Example cloud formation template"
Parameters:
  DomainName:
    Description: "The DNS domain name for the system"
    Type: String
    Default: example.com
  AMI:
    Description: "The AMI ID for the image to deploy"
    Type: String
    Default: ami-af4333cf

Resources:
  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: 172.20.0.0/16
      EnableDnsSupport: true
      EnableDnsHostnames: true
  SecurityGroupExample:
    Type: AWS::EC2::SecurityGroup
    Properties:
      VpcId: !Ref VPC 
      GroupDescription: example security group
      SecurityGroupIngress:
        - { IpProtocol: icmp, CidrIp: 0.0.0.0/0, FromPort: -1, ToPort: -1 }
        - { IpProtocol: tcp, CidrIp: 0.0.0.0/0, FromPort: 22, ToPort: 22 }

Include:
 - network
 - servers/global
 - outputs.yaml
```

#### Logical resource merging

Logical resources are not mangled - if multiple resources with the same name are defined in 
multiple sub-templates, this is an error that would cause the tool to abort.

### Loading user data files

When specifying a user-data block for a `LaunchConfiguration` resource, `Instance`
resource, or a `LaunchTemplate` resource, the user-data can be loaded from an external
YAML file (only YAML formatted user-data is currently supported, sorry) by specifying the
`UserData` element as a map with the single field `File` that is set with the relative
path to the user-data file. The user-data file is expected to be a cloud-init configuration
file with the default extension `.init` (but there really aren't any filename requirements).

Alternatively, the field `FileTemplate` can be used under `UserData` to load an external
cloud-init configuration file that includes variable place holders for the
(CloudFormation intrinsic function Sub)[http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-sub.html].
The `FileTemplate` mode supports all the features described above as well as it performs
the parsing detailed below, except compression and S3 offloading - as doing so prevents
CloudFormation from performing the substitution operation. As a result, if the resulting
cloud-init file is larger than 16KB you should expect that the template will fail to create
the stack.

#### User data file parsing

The reference file will be loaded and parsed as a ("Cloud Config data" file)[http://cloudinit.readthedocs.io/en/latest/topics/format.html#cloud-config-data]
with the special `write_files` and `write_directories` enhancement (see below). 
The result is then checked that it does not exceed the user-data size limitation.
If the file is bigger than can fit in the AWS user-data block, it will first be compressed
using gzip and if it is still too large, it will be uploaded to S3 and the user-data block
will be set with a cloud-init download reference to the S3 object.

##### Enhanced `write_files`

The ("Cloud Config data" format supports deploying files)[http://cloudinit.readthedocs.io/en/latest/topics/examples.html#writing-out-arbitrary-files]
into the instance using the `write_files` module. This normally requires the file content
to be embedded directly into the cloud-config YAML format. The cloudformation-tool supports
specifying external files to be loaded, allowing deployed files to be managed externally to
the cloud-config data (for example, if you enjoy using syntax aware editors to edit them,
are binary, or just too large).

To use an external file in `write_files` instead of specifying the file content using the
`content` field, use a `file` field to specify the relative path to the file to be loaded.

##### `write_directories`

In the case that you want to deploy multiple files to the same directory, instead of
listing each and every file as a `write_files` entries (which can get tedious after
a while, even with the `file` extension), `cftool` offers another cloud-init extension
as a category named `write_directories`. 

The `write_directories` section is a list where each entry specifies a local
directory that would be deployed (with all files it includes, recursively - so make
sure it only includes files you want to deploy) to a target directory on the deployed
server. For each entry specify a `source` attribute that points to a local directory
relative to the location of the cloud-init file, and a `target` attribute set to an
absolute URL to where to deploy the source directory.  

#### Example:

`cloud-formation.yaml`:

```
  LaunchConfigurationForServer:
    Type: AWS::AutoScaling::LaunchConfiguration
    Properties:
      AssociatePublicIpAddress: true
      IamInstanceProfile: !Ref InstanceProfileForServer
      ImageId: !Ref AMI # read from parameters
      InstanceType: !Ref InstanceType # read from parameters
      KeyName: !Ref KeyName # read from parameters
      SecurityGroups:
        - Ref: SecurityGroupExample
      UserData:
        File: config.init 
```

`config.init`:

```
#cloud-config

write_files:
 - path: /etc/default/my-app
   permissions: '0755'
   file: my-app.config

write_directory:
 - source: my-app-data
   target: /usr/share/my-app
```

### Loading Lambda code

When specifying the `Code` property of a `AWS::Lambda::Function` resource, instead of
specifying the S3 bucket and object key, either of the following fields may be used:
  - The field `URL` may be used to specify an HTTP URL	from which the code is to be uploaded to AWS Lambda. The tool 
    will download the code file from the specified URL, upload it to S3 and specify the correct S3 location for 
    CloudFormation.
  - The field `Path` may be used to specify a local file or directory containing the code to be uploaded.
    If the path specifies a directory, it will be compressed and uploaded to S3 as a Zip file. If the path is a
    single file, it will be converted to a `ZipFile`, allowing implicit use of the CloudFormation `cfn-response` module
    and the AWS SDK, but the file is also subject to all `ZipFile` restrictions - such as limited to 4KB size.

#### Example:

```
  LambdaExample:
    Type: AWS::Lambda::Function
    Properties:
      FunctionName: !Join [ "-", [ route53-update, !Ref SystemTag ] ]
      Runtime: java8
      Code:
         URL: https://github.com/GreenfieldTech/lambda-route53-updates/releases/download/0.2.5/lambda-route53-updates-0.2.5.jar
      Description: Update DNS with autoscaling servers
      MemorySize: 256
      Timeout: 60
      Handler: net.gftc.aws.route53.NotifyRecords
      Environment:
        Variables: # set variables here, see lambda-route53-updates for documentation ...
      Role: !GetAtt [ LambdaExecutionRole, Arn ]
```

### Nested Stacks Modules

The CloudFormation pre-compiler supports loading local templates as "nested stacks" using the
CloudFormation `AWS::CloudFormation::Stack` resource type.

Instead of first pre-deploying a template to S3 to be used for a nested stack, use the
`Template` property (instead of the `TemplateURL` property) to point to a local
sub-template. The sub-template will be compiled separately and deployed automatically to
an S3 bucket before deploying the compiled template to CloudFormation.

The `monitor` tool (also used during `create` operation) supports nested stacks by
automatically detecting nested stack updates in the main stack's event stream and will
start streaming the nested stack events - this allows the user to more easily locate problems
with nested stacks.

Currently there's no automatic resolution of references between nested and parent stacks, so
make sure to set up nested stack parameters for all resources that should be referenced from
the parent stack.

#### Example

`cloud-formation.yaml`:

```
AWSTemplateFormatVersion: "2010-09-09"
Description: "CloudFormation template with nested stacks"
Parameters:
  DomainName:
    Description: "The DNS domain name for the system"
    Type: String
    Default: example.com
  AMI:
    Description: "The AMI ID for the image to deploy"
    Type: String
    Default: ami-af4333cf

Resources:
  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: 172.20.0.0/16
      EnableDnsSupport: true
      EnableDnsHostnames: true
  SecurityGroupExample:
    Type: AWS::EC2::SecurityGroup
    Properties:
      VpcId: !Ref VPC 
      GroupDescription: example security group
      SecurityGroupIngress:
        - { IpProtocol: icmp, CidrIp: 0.0.0.0/0, FromPort: -1, ToPort: -1 }
        - { IpProtocol: tcp, CidrIp: 0.0.0.0/0, FromPort: 22, ToPort: 22 }
  ServiceStack:
    Type: AWS::CloudFormation::Stack
    Properties:
      Template: service.yaml
      Parameters:
        DomainName: !Ref DomainName
        AMI: !Ref AMI
        VPC: !Ref VPC
```

`service.yaml`:

```
AWSTemplateFormatVersion: "2010-09-09"
Description: "Service nested stack"
Parameters:
  DomainName:
    Description: "The DNS domain name for the system"
    Type: String
  AMI:
    Description: "The AMI ID for the image to deploy"
    Type: String
  VPC:
    Description: "The VPC into which to deploy the service"
    Type: String

Resources:
  Subnet:
    Type: AWS::EC2::Subnet
    Properties:
      AvailabilityZone: !Select [ 0, !GetAZs { Ref: "AWS::Region" } ]
      CidrBlock: 172.20.0.0/24
      MapPublicIpOnLaunch: true
      VpcId: !Ref VPC
  Ec2Instance: 
    Type: AWS::EC2::Instance
    Properties: 
      ImageId: !Ref AMI
      KeyName: "secret" 
      NetworkInterfaces: 
        - AssociatePublicIpAddress: "true"
          DeviceIndex: "0"
          SubnetId: !Ref Subnet 
```

## Caching

Some resource compilation may require uploading to S3, such as Lambda code or cloud-init setup
files. In such cases, the tool will take precaution not to update the uploaded file (and thus
cause a CloudFormation update) unless the content has changed. This is done by comparing the
MD5 hash of the compiled object with the MD5 hash of the previously uploaded object, and
re-uploading and updating CloudFormation only if a change in the actual content as been 
detected.

## Usage

The CloudFormation Tool uses a "sub-command CLI syntax" (like GIT, for example).

Usage: `cftool [options] <command> <command-options...>`

The following commands are supported:

 - `list` - List names and status of existing CloudFormation stacks
 - `parameters` - List parameters defined in the specified CloudFormation template and
   their default values.
 - `compile` - Compile a CloudFormation template set (including all caching needed) and
   output the resulting valid CloudFormation template to the console.
 - `create` - Create or update a CloudFormation stack by compiling the specified template
   set and uploading it to CloudFormation. If no stack with the specified name exists, then
   a new stack will be created, otherwise the existing stack will be updated. After sending the
   template to CloudFormation, the tool will immediately start `monitor` mode until the
   operation has completed successfully or with an error. Parameters can be specified on the
   command line - like for the AWS CLI - or loaded from a file or URL.
 - `monitor` - Track and display ongoing events for the named stack.
 - `status` - Check if the names stack exists or not
 - `delete` - Delete the specified stack. After issuing the delete command, the tool will
   immediately start `monitor` mode until the operation has completed. 
 - `servers` - List EC2 instances created and managed by this stack, per autoscaling group, including servers in nested stacks.
 - `groups` - list autoscaling groups managed by the stack, including groups in nested stacks.
 - `recycle` - recycle servers in an autoscaling group in a stack by scaling the group up and down.
 - `scale` - set the scale of an autoscaling group managed by a stack to a specific desired value.
 - `invalidate` - send an invalidation request to a CloudFront distribution managed by a stack.
 - `output` - retrieve output values from a stack.

Please see the specific help for each command by running `cftool <command> --help` for
more details and specific options.

### Region Selection

The AWS region to be used can be select by specifying top level option (i.e. before the command name) `-r <region>`, by providing the standard environment variable `AWS_DEFAULT_REGION` or it will default to `us-west-1`

### Credentials Selection

The tool will use the standard AWS credentials selection process, except when you want to use AWS CLI configured credential profiles, you may select to use a profile other than "default" by specifying the top level option (i.e. before the command name) `-p <profile>`, by providing the standard environment variable `AWS_DEFAULT_PROFILE` or by having a file called `.awsprofile` - whose content is the name of a valid AWS credentials profile - in a parent directory (at any level up to the root directory).

## Library API

The cloudformatin tool can also be consumed as a library by other applications - for example an application that needs to perform high-level business-logic oriented
operations for a specific application deployed in a stack, using the cloudformation tool abstraction of CloudFormation templates and stacks.

### Usage as a library

To use the cloudformatin tool as a library, require `cloud_formation_tool`.

### CloudFormation templates

The cloudformation pre-compiler can be used to manipulate pre-compiled templates.

To access the pre-compiler, initialize a `CloudFormationTool::CloudFormation` with the path to the local template resource (either a file or a directory that can be
parsed by the pre-compiler).

The initial template resource will be loaded but will not be fully parsed - and included elements will not be read - until the `compile` method is called.

The following method calls are available on the `CloudFormation` instance:

#### `compile(parameters = nil)`

Pre-compiles the template, with the provided parameter `Hash`, if provided. Returns a `Hash` repsenting the compiled template.

#### `to_yaml`

Pre-compiles the template and returns a YAML rendering of the CloudFormation template, suitable for deploying to AWS CloudFormation.

#### `each`

Yields a tuple for each defined template parameter, that includes the parameter's name and its default value (if set, `nil` otherwise).

### CloudFormation stacks

The cloudformation tool's abstraction of a CloudFormation stack can be used to manipulate stack resouces, such as autoscaling groups or instances in a stack context.

To access the stack API, initialize a `CloudFormationTool::CloudFormation::Stack` with the name of the stack. You can then access the following methods:

#### `exist?`

Check if a stack exists.

#### `create(template, params = {})`

Create or update a stack by deploying the specified template. The template can be any local file or directory resource that can be parsed by the cloudformation pre-compiler.

#### `delete`

Deletes the stack

#### `stack_id`

Return the AWS CloudFormation stack identifier for the stack, which is the ARN of the stack.

#### `output`

Returns the output values of the stack

#### `resources`

Return a list of resources in the stack and all of its nested stacks

#### `asgroups`

Return a list of autoscaling groups in the stack and all of its nested stacks. The returned values are AWS SDK CloudFormation resources, extended with a set of methods
to help manage autoscaling groups:

##### `group`

Returns the AWS SDK `Aws::AutoScaling::AutoScalingGroup` object for the autoscaling group.

#### `cdns`

Return a list of CloudFront CDN distributions in the stack and all of its nested stacks. The returnd values are AWS SDK CloudFormation resources, extended with a set of
methods to help manage CloudFront distributions:

##### `distribution`

Returns the AWS SDK `Aws::CloudFront::Types::Distribution` object for the CloudFront distribution.

##### `domain_names`

Returns the comma delimited list of the distribution aliases domain names

##### `invalidate(path)`

Creates a new invalidation in the CloudFront distribution with the specified path expression

#### `each`

Yields CloudFormation stack events, in the order they were created. Subsequent calls to `each` will not repeat events previously yielded and will only yield additional
events created since the last call to `each`.

#### `see_event`

Mark all events since the last call to `each` (or from stack creation, if `each` was not previously called) as "seen" so they will not be yielded in future calls to `each`.

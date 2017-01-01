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

When specifying a user-data block for a `LaunchConfiguration` resource or an `Instance`
resource, the user-data can be loaded from an external YAML file (only YAML formatted user-data
is currently supported, sorry) by specifying the `UserData` element as a map with the single
field `File` that is set with the relative path to the user-data file. The user-data file is
expected to be a cloud-init file with the extension `.init`. 

The loaded file will be checked that it does not exceed the user-data size limitation. If the
file is bigger than can fit in the AWS user-data block, it will first be compressed using gzip
and if it is still too large, it will be uploaded to S3 and the user-data block will be set 
with a cloud-init download reference to the S3 object.

#### Example:

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

### Loading Lambda code

When specifying the `Code` property of a `AWS::Lambda::Function` resource, instead of
specifying the S3 bucket and object key, the field `URL` may be used to specify an HTTP URL
from which the code is to be uploaded to AWS Lambda. The tool will download the code file from
the specified URL, upload it to S3 and specify the correct S3 location for CloudFormation.

In the future we plan to add support for specifying `File` to upload from a local file.

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
   operation has completed successfully or with an error.
 - `monitor` - Track and display ongoing events for the named stack.
 - `status` - Check if the names stack exists or not
 - `delete` - Delete the specified stack. After issuing the delete command, the tool will
   immediately start `monitor` mode until the operation has completed. 
 - `servers` - List EC2 instances created and managed by this stack.

Please see the specific help for each command by running `cftool <command> --help` for
more details and specific options.

### Region Selection

The AWS region to be used can be select by specifying top level option (i.e. before the command name) `-r <region>`, by providing the standard environment variable `AWS_DEFAULT_REGION` or it will default to `us-west-1`

### Credentials Selection

The tool will use the standard AWS credentials selection process, except when you want to use AWS CLI configured credential profiles, you may select to use a profile other than "default" by specifying the top level option (i.e. before the command name) `-p <profile>`, by providing the standard environment variable `AWS_DEFAULT_PROFILE` or by having a file called `.awsprofile` - whose content is the name of a valid AWS REGION - in a parent directory (at any level up to the root directory).

# networksetup

This module is able to contol several aspects of networking configuration for
RedHat based OSes.

#### Table of Contents

1. [Description](#description)
2. [Setup - The basics of getting started with networksetup](#setup)
    * [What networksetup affects](#what-networksetup-affects)
    * [Setup requirements](#setup-requirements)
    * [Beginning with networksetup](#beginning-with-networksetup)
3. [Usage - Configuration options and additional functionality](#usage)
4. [Limitations - OS compatibility, etc.](#limitations)
5. [Development - Guide for contributing to the module](#development)

## Description

This module is able to contol several aspects of networking configuration for
RedHat based OSes.

It is possible to match IP address to interface MAC address and setup loopback
interface

There is ability to add IP address to existing interface and setup IP address
alias

## Setup

### What networksetup affects **OPTIONAL**

If it's obvious what your module touches, you can skip this section. For example, folks can probably figure out that your mysql_instance module affects their MySQL instances.

If there's more that they should know about, though, this is the place to mention:

* Files, packages, services, or operations that the module will alter, impact, or execute.
* Dependencies that your module automatically installs.
* Warnings or other important notices.

### Setup Requirements **OPTIONAL**

### Beginning with networksetup

The very basic steps needed for a user to get the module up and running. This can include setup steps, if necessary, or it can be an example of the most basic use of the module.

## Usage

Include usage examples for common use cases in the **Usage** section. Show your users how to use your module to solve problems, and be sure to include code examples. Include three to five examples of the most important or common tasks a user can accomplish with your module. Show users how to accomplish more complex tasks that involve different types, classes, and functions working in tandem.

## Reference

See [REFERENCE.md](REFERENCE.md) for details.

## Limitations

It supports only CentOS 7+ operating systems

## Development

Please submit GitHub pull request for review.
Rspec unit tests are required for any introduced changes

## Release Notes/Contributors/Etc. **Optional**

See [CHANGELOG.md](CHANGELOG.md) for details

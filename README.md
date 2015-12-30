# Simple C# to Swift Converter

This is a simple Ruby tool to aid in the conversion of C# to Swift. 

Unlike most of the commercial tools that I have tried, such as [Oxidizer](http://docs.elementscompiler.com/Tools/Oxidizer/) this tool is designed to be used one file at a time.  

Because no tool is yet powerful enough to truly convert an entire project without programmer assistance I wanted something that would get me 80% of the way there by dealing with most of the typing intensive tasks, letting me focus on the framework related issues.

Install the tool with:

```bash
gem install csharp_2_swift
```

Then run it on some C# code like so:

```bash
csharp_2_swift -o SomeCode.swift SomeCode.cs
```

Let me know how you get on!

## Development

This stuff is mostly here as a reminder to me.  It really needs to go in the `Rakefile`.

### Debugging

Because of the standard Ruby directory layout, running the tools from the command line requires a little more effort:

```bash
ruby -e 'load($0=ARGV.shift);CSharp2Swift.new.execute(ARGV)' -- lib/csharp_2_swift.rb --help
```

### Publishing

Here's what you need to do to publish a Ruby gem.  First time only:

```bash
curl -u <yourname> https://rubygems.org/api/v1/api_key.yaml > ~/.gem/credentials; chmod 0600 ~/.gem/credentials
```

Then, in the case of these tools:

```bash
gem build csharp_2_swift.gemspec
gem push csharp_2_swift-<version>.gem
```

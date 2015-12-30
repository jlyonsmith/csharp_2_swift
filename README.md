# Simple C# to Swift Converter

This is a simple Ruby script to aid in the conversion of C# to Swift.  It's designed to be used one file at a time, unlike most of the commercial tools that I have tried.

```bash
gem install csharp_2_swift
```

## Development

### Debugging

Because of the standard Ruby directory layout, running the tools from the command line requires a little more effort:

```bash
ruby -e 'load($0=ARGV.shift);CSharp2Swift.new.execute' -- lib/csharp_2_swift.rb --help
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

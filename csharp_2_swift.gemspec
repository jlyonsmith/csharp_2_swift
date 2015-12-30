Gem::Specification.new do |s|
  s.name = 'csharp_2_swift'
  s.version = '1.0.0'
  s.date = '2015-12-29'
  s.summary = "Simple C# to Swift Converter"
  s.description = %Q(A tool that does a rough conversion of C# code to Swift.
It hits the major stuff, like re-ordering parameters, field/property declarations, for loop syntax
and lets you figure out the library related stuff.
)
  s.authors = ["John Lyon-smith"]
  s.email = "john@jamoki.com"
  s.files = [
      "lib/csharp_2_swift.rb"]
  s.executables = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.homepage = 'http://rubygems.org/gems/csharp_2_swift'
  s.license  = 'MIT'
  s.required_ruby_version = '~> 2.0'
  s.add_runtime_dependency "colorize", ["~> 0.7.7"]
end

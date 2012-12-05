begin
  require 'thor'
  require 'thor/group'
  require 'rbvmomi'
  require 'json'
  require 'rest_client'
rescue LoadError
  require 'rubygems'
  require 'thor'
  require 'thor/group'
  require 'rbvmomi'
  require 'json'
  require 'rest_client'
end

require 'templatize/cli'

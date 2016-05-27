#!/usr/bin/env ruby

require 'logger'
require 'pathname'
require 'pp'
require 'rexml/document'
require 'rexml/xpath'
require 'yaml'


def usage
  "usage: #{Pathname.new( $0 ).basename} {DIR}"
end


################################################################################

unless ARGV.size == 1 and Pathname.new( ARGV.first ).directory?
  puts "#{usage()}\n"
  exit ( ARGV.empty? ? 0 : 1 )
end


logger = Logger.new( $stderr )

dir = Pathname.new( ARGV.shift )

Dir.chdir( dir.to_s ) do
  Pathname.glob( 'page[0-9][0-9].html' ).sort {|a,b| a.to_s <=> b.to_s }.each do |file|
    source = REXML::Document.new( file.read )
    target = REXML::Document.new( '<html></html>' )

    #<div class="article-text-\d+">
    #<h1 strcontenttype='Heading'>
    #<h2 strcontenttype='Header'>
    #<h3 strcontenttype='Headline'>
    #<h4 strcontenttype='Subheading'>
    #<h5 strcontenttype='Text'>
    #<h6 strcontenttype='Caption'>
    #<p strcontenttype='Author'>
    #<p strcontenttype='Basetext'>

    head = REXML::Element.new( 'head' )
    target.root << head
    body = REXML::Element.new( 'body' )
    target.root << body

    head << REXML::Element.new( 'meta charset="utf-8"' )
    head << REXML::XPath.first( source, '/*/title' )

    articles = REXML::XPath.match( source, '//div' )
    articles.delete_if {|a| /article-text-\d+/.match( a.attributes[ 'class' ] ).nil? }

    articles.each {|a| body << a }
      
    # Remove all attributes.
    nodes = REXML::XPath.match( target, '//*' )
    nodes.each {|n| n.attributes.keys.each {|a| n.delete_attribute( a ) } }

    # Add id to earch article div.
    REXML::XPath.match( body, './*' ).each do |a|
      id = REXML::XPath.first( a, './*' ).text.strip

      id = id.gsub( /ä/, 'ae' ).gsub( /ö/, 'oe' ).gsub( /ü/, 'ue' )
      id = id.gsub( /Ä/, 'Ae' ).gsub( /Ö/, 'Oe' ).gsub( /Ü/, 'Ue' )
      id.gsub( /ß/, 'ss' )
      id.gsub!( /[^\w\s]/, '' )
      id.gsub!( /\s+/, '_' )

      a.add_attribute( 'id', id )
    end

    # TODO: Convert each <br/> node in a paragraph into </p><p>?!
    # TODO: Remove <br/> in non-paragraphs.

    REXML::Formatters::Pretty.new.write( target, $stdout )
    break
  end
end

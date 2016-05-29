#!/usr/bin/env ruby

require 'logger'
require 'pathname'
require 'rexml/document'
require 'rexml/xpath'
require 'yaml'


def usage
  "usage: #{Pathname.new( $0 ).basename} {DIR}"
end

def calc_and_set_id( article )
  id = REXML::XPath.first( article, './*' ).text.strip

  id = id.gsub( /ä/, 'ae' ).gsub( /ö/, 'oe' ).gsub( /ü/, 'ue' )
  id = id.gsub( /Ä/, 'Ae' ).gsub( /Ö/, 'Oe' ).gsub( /Ü/, 'Ue' )
  id.gsub( /ß/, 'ss' )
  id.gsub!( /[^\w\s_-]/, '' )
  id.gsub!( /\s+/, '_' )

  article.add_attribute( 'id', id )

  id
end

def convert_br( article )
  children = []
  REXML::XPath.match( article, './*' ).each do |child|
    child.remove

    if child.name == 'p' and REXML::XPath.first( child, './br' )
      text = ''
      REXML::Formatters::Default.new.write( child, text )

      text.gsub!( /\n+/m, ' ' )
      text.strip!
      text.sub!( /^<p>/, '' )
      text.sub!( /<\/p>$/, '' )

      parts = text.split( /<br\s*\/>/ )
      parts.map! {|p| p.strip }
      parts.delete_if {|p| p.empty? }

      paragraphs = [ [ ] ]
      parts.each do |part|
        if part.split( /\s+/ ).size < 12
          paragraphs.last << part
        else
          paragraphs << [ part ]
        end
      end

      paragraphs.each do |paragraph|
        tmp = REXML::Document.new( "<p>#{paragraph.join( '<br/>' )}</p>" )
        children << tmp.root
      end
    elsif REXML::XPath.first( child, './br' )
      REXML::XPath.match( child, './br' ).each {|br| br.remove }
      children << child
    else
      children << child
    end
  end

  children.each {|c| article << c }

  REXML::XPath.match( article, './p' ).each do |p|
    p.remove if p.text.nil? and p.elements.empty?
  end

  article
end

def convert_h5( article )
  children = []
  REXML::XPath.match( article, './*' ).each do |child|
    child.remove

    if child.name == 'h5'
      text = ''
      REXML::Formatters::Default.new.write( child, text )

      text.gsub!( /(<\/?)h5>/m, '\1p>' )

      children << REXML::Document.new( text ).root
    else
      children << child
    end
  end

  children.each {|c| article << c }

  article
end

def merge_first_two_p_if_short( article )
  children = []

  c = REXML::XPath.match( article, './*' )

  # Only consider articles without headline.
  return unless c.size > 1 and c[ 0 ].name == 'p' and c[ 1 ].name == 'p'

  # Ignore first p if it starts with 'Zu ' or ends with ':'.
  if c[ 0 ].text.strip =~ /^Zu\s/ or c[ 0 ].text.strip =~ /:$/m
    return unless c.size > 2

    c[ 0 ].remove
    children << c[ 0 ]

    # Reload!
    c = REXML::XPath.match( article, './*' )
  end

  # Measure combined text length, do nothing if too long.
  l = c[ 0 .. 1 ].reduce( 0 ) {|m,x| m += x.text.strip.split( /\s+/m ).size }
  return if l > 12

  parts = []
  REXML::XPath.match( article, './*' ).each_with_index do |child,i|
    child.remove

    if i < 2
      tmp = ''
      REXML::Formatters::Default.new.write( child, tmp )

      tmp.gsub!( /\n+/m, ' ' )
      tmp.sub!( /^\s*<[^\/>]+>/, '' )
      tmp.sub!( /<\/[^>]+>\s*$/, '' )

      parts << tmp

      if i > 0
        children << REXML::Document.new( "<p>#{parts.join( ' ' )}</p>" ).root
      end
    else
      children << child
    end
  end

  children.each {|c| article << c }

  article
end

def add_headline_if_missing( article )
  return if REXML::XPath.first( article, './*' ).name =~ /^h/i

  merge_first_two_p_if_short( article )

  children = [ ]
  if t = article.attributes[ 'title' ]
    h1 = REXML::Element.new( 'h1' )
    h1.text = t

    children = [ h1 ]
    REXML::XPath.match( article, './*' ).each do |child|
      child.remove
      children << child
    end
  else
    REXML::XPath.match( article, './*' ).each_with_index do |child,i|
      child.remove

      if i.zero?
        text = ''
        REXML::Formatters::Default.new.write( child, text )

        text.gsub!( /\n+/m, ' ' )
        text.sub!( /^\s*<[^\/>]+>/, '<h1>' )
        text.sub!( /<\/[^>]+>\s*$/, '</h1>' )

        children << REXML::Document.new( text ).root
      else
        children << child
      end
    end
  end

  children.each {|c| article << c }

  # Reset id of article.
  calc_and_set_id( article )

  article
end

def remove_if_empty( article )
  article.remove unless REXML::XPath.first( article, './p' )

  article
end


################################################################################

unless ARGV.size == 1 and Pathname.new( ARGV.first ).directory?
  puts "#{usage()}\n"
  exit ( ARGV.empty? ? 0 : 1 )
end


logger = Logger.new( $stderr )

dir = Pathname.new( ARGV.shift )

# Default is current date.
date = Time.now.strftime( '%d.%m.%Y' )

# Try to extract date from dirname.
m = /(\d{4})(\d{2})(\d{2})/.match( dir.basename.to_s )
date = "#{m[ 3 ]}.#{m[ 2 ]}.#{m[ 1 ]}"

# Process pages.
Dir.chdir( dir.to_s ) do
  outdir = Pathname.new( 'epub' ).join( 'content' )
  outdir.mkpath

  Pathname.glob( 'page[0-9][0-9].html' ).sort {|a,b| a.to_s <=> b.to_s }.each do |file|
    page = file.basename.to_s.gsub( /[^\d]/, '' ).sub( /^0/, '' )

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
    head << REXML::Element.new( 'meta charset="utf-8"' )
    target.root << head
    body = REXML::Element.new( 'body' )
    target.root << body

    title = REXML::XPath.first( source, '/*/title' )
    if title.text.nil? || title.text.strip.empty?
      title.text = "Sächsische Zeitung - #{date} - Seite #{page}"
    else
      title.text = "Sächsische Zeitung - #{date} - Seite #{page} - #{title.text}"
    end
    head << title

    articles = REXML::XPath.match( source, '//div' )
    articles.delete_if {|a| /article-text-\d+/.match( a.attributes[ 'class' ] ).nil? }

    # Ignore empty pages ...
    next if articles.empty?

    articles.each {|article| body << article }

    # Remove all attributes.
    nodes = REXML::XPath.match( target, '//*' )
    nodes.each {|n| n.attributes.keys.each {|a| n.delete_attribute( a ) } }

    # Process articles.
    REXML::XPath.match( body, './*' ).each do |article|
      calc_and_set_id( article )
      convert_h5( article )
      convert_br( article )
      add_headline_if_missing( article )
      remove_if_empty( article )
    end

    outdir.join( file.basename.to_s ).open( 'w' ) do |handle|
      REXML::Formatters::Pretty.new.write( target, handle )
    end
  end
end

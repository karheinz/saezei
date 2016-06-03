#!/usr/bin/env ruby

require 'logger'
require 'pathname'
require 'rexml/document'
require 'securerandom'
require 'zip'


def usage
  "usage: #{Pathname.new( $0 ).basename} {DIR}"
end


unless ARGV.size == 1 and Pathname.new( ARGV.first ).directory?
  puts "#{usage()}\n"
  exit ( ARGV.empty? ? 0 : 1 )
end

logger = Logger.new( $stderr )

dir = Pathname.new( ARGV.shift ).join( 'epub' )
unless dir.join( 'content' ).directory?
  logger.error "directory #{dir.basename}/epub/content does not exist"
  exit 1
end

################################################################################

# Skeletons.
mimetype = "applicaton/epub+zip"

container_xml =<<EOF
<?xml version='1.0' encoding='utf-8'?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
  <rootfiles>
    <rootfile full-path="content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
EOF

toc_ncx_skeleton =<<EOF
<?xml version='1.0' encoding='utf-8'?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1" xml:lang="de">
  <head>
    <meta name="dtb:uid"/>
    <meta content="1" name="dtb:depth"/>
    <meta content="Saezei Compiler" name="dtb:generator"/>
    <meta content="0" name="dtb:totalPageCount"/>
    <meta content="0" name="dtb:maxPageNumber"/>
  </head>
  <docTitle><text /></docTitle>
  <navMap />
</ncx>
EOF
toc_ncx = REXML::Document.new( toc_ncx_skeleton )

content_opf_skeleton =<<EOF
<?xml version='1.0' encoding='utf-8'?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookID" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title />
    <dc:creator opf:role="aut" />
    <dc:language />
    <dc:identifier id="BookID" opf:scheme="UUID" />
  </metadata>
  <manifest>
    <item href="toc.ncx" id="ncx" media-type="application/x-dtbncx+xml"/>
  </manifest>
  <spine toc="ncx" />
</package>
EOF
content_opf = REXML::Document.new( content_opf_skeleton )

################################################################################

# Process pages.
Dir.chdir( dir.to_s ) do
  Pathname.new( 'mimetype' ).open( 'w' ) do |handle|
    handle.write( mimetype )
  end

  meta_inf = Pathname.new( 'META-INF' )
  meta_inf.mkpath

  meta_inf.join( 'container.xml' ).open( 'w' ) do |handle|
    handle.write( container_xml )
  end

  date_ymd = nil
  count = 0

  # Title page.
  logger.info "processing title page"
  nav_point = REXML::Element.new( 'navPoint' )
  nav_point.add_attribute( 'id', SecureRandom.uuid )
  nav_point.add_attribute( 'playOrder', count += 1 )
  nav_point_label = REXML::Element.new( 'navLabel' )
  nav_point_label_text = REXML::Element.new( 'text' )
  nav_point_label_text.text = "Titelseite"
  nav_point_label << nav_point_label_text
  nav_point_content = REXML::Element.new( 'content' )
  nav_point_content.add_attribute( 'src', 'content/titlepage.xhtml' )
  nav_point << nav_point_label
  nav_point << nav_point_content
  nav_map = REXML::XPath::first( toc_ncx, '/ncx/navMap' )
  nav_map << nav_point

  id = 'titlepage'
  item = REXML::Element.new( 'item' )
  item.add_attribute( 'href', 'content/titlepage.xhtml' )
  item.add_attribute( 'id', id )
  item.add_attribute( 'media-type', 'application/xhtml+xml' )
  manifest = REXML::XPath.first( content_opf, '/package/manifest' )
  manifest << item
  itemref = REXML::Element.new( 'itemref' )
  itemref.add_attribute( 'idref', id )
  spine = REXML::XPath.first( content_opf, '/package/spine' )
  spine << itemref

  # Other pages.
  Pathname.glob( 'content/page[0-9][0-9].xhtml' ).sort {|a,b| a.to_s <=> b.to_s }.each do |file|
    page_num = file.basename.to_s.gsub( /[^\d]/, '' ).sub( /^0/, '' )

    logger.info "processing page #{page_num}"

    page = REXML::Document.new( file.read )

    full_title = REXML::XPath::first( page, '/html/head/title' ).text.gsub( /\n+/m, ' ' ).strip
    _, date, site, category  = full_title.split( /\s*-\s*/ )

    date_ymd = "#{date[ 6 .. 9 ]}-#{date[ 3 .. 4 ]}-#{date[ 0 .. 1 ]}"

    if page_num == '1'
      uuid = SecureRandom.uuid

      node = REXML::XPath::first( toc_ncx, '/ncx/head/meta[@name="dtb:uid"]' )
      node.add_attribute( 'content', uuid )
      node = REXML::XPath::first( toc_ncx, '/ncx/docTitle/text' )
      node.text = date_ymd

      node = REXML::XPath::first( content_opf, '/package/metadata/dc:identifier' )
      node.text = uuid
      node = REXML::XPath::first( content_opf, '/package/metadata/dc:creator' )
      node.text = "Sächsische Zeitung"
      node = REXML::XPath::first( content_opf, '/package/metadata/dc:title' )
      node.text = date_ymd
    end

    # Add entry to toc.ncx
    nav_point = REXML::Element.new( 'navPoint' )
    nav_point.add_attribute( 'id', SecureRandom.uuid )
    nav_point.add_attribute( 'playOrder', count += 1 )
    nav_point_label = REXML::Element.new( 'navLabel' )
    nav_point_label_text = REXML::Element.new( 'text' )
    nav_point_label_text.text = "#{site}: #{category}"
    nav_point_label << nav_point_label_text
    nav_point_content = REXML::Element.new( 'content' )
    nav_point_content.add_attribute( 'src', file.to_s )

    nav_point << nav_point_label
    nav_point << nav_point_content
    
    nav_map = REXML::XPath::first( toc_ncx, '/ncx/navMap' )
    nav_map << nav_point

    # Add entry to content.opf
    id = file.basename( '.xhtml' ).to_s
    item = REXML::Element.new( 'item' )
    item.add_attribute( 'href', file.to_s )
    item.add_attribute( 'id', id )
    item.add_attribute( 'media-type', 'application/xhtml+xml' )

    manifest = REXML::XPath.first( content_opf, '/package/manifest' )
    manifest << item

    itemref = REXML::Element.new( 'itemref' )
    itemref.add_attribute( 'idref', id )

    spine = REXML::XPath.first( content_opf, '/package/spine' )
    spine << itemref
  end

  # Write files.
  Pathname.new( 'toc.ncx' ).open( 'w' ) do |handle|
    REXML::Formatters::Pretty.new.write( toc_ncx, handle )
  end
  Pathname.new( 'content.opf' ).open( 'w' ) do |handle|
    REXML::Formatters::Pretty.new.write( content_opf, handle )
  end

  # Zip to Y-m-d_Saechsische_Zeitung.epub
  if date_ymd
    file = Pathname.new( "#{date_ymd}_Saechsische_Zeitung.epub" )
    file.unlink if file.file?

    Zip::File.open( file.to_s, Zip::File::CREATE ) do |handle|
      [ 'mimetype', 'content.opf', 'toc.ncx' ].each do |file|
        handle.add( file, file )
      end
      [ 'content', 'META-INF' ].each do |dir|
        Pathname.glob( "#{dir}/*" ).sort {|a,b| a.to_s <=> b.to_s }.each do |file|
          handle.add( file.to_s, file.to_s )
        end
      end
    end
  else
    exit 1
  end
end


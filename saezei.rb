#!/usr/bin/env ruby

require 'logger'
require 'net/http'
require 'openssl'
require 'pathname'
require 'rexml/document'
require 'yaml'

require 'selenium-webdriver'


def usage
  "usage: #{Pathname.new( $0 ).basename} {BASEDIR}"
end

def calc_dirname( logger, basedir, title )
  matches = /(\d{2})\.(\d{2})\.(\d{4})/.match( title )

  dir = Time.now.strftime( '%Y%m%d' )

  if matches
    dir = "#{matches[ 3 ]}#{matches[ 2 ]}#{matches[ 1 ]}"
  else
    logger.warn( "Couldn't determine date of newspaper!" )
  end

  basedir.join( dir )
end

def calc_rc_filename()
  Pathname.new( ENV[ 'HOME' ] ).join( '.saezeirc' )
end

def get_username_and_password()
  begin
    YAML.load( calc_rc_filename().read ) || {}
  rescue
    {}
  end
end

def calc_page_filename( dir, number )
  dir.join( "page#{number.to_s.rjust( 2, '0' )}.html" )
end

def last_page_read( dir )
  result = 0

  tmp = Pathname.glob( dir.join( 'page[0-9][0-9].html' ).to_s ).sort.last

  if tmp
    matches = /\d+/.match( tmp.basename.to_s )
    result = matches ? matches[ 0 ].to_i : 0
  end

  result
end

def enter_iframe( driver )
  canvas = driver.find_element( :css, 'iframe.detail-frame' )
  driver.switch_to.frame( canvas ) if canvas
end

def to_overview( driver )
  # Back to overview:
  # - Button1 => Übersicht
  # - Button2 => Seitenübersicht
  driver.execute_script( '$( ".filterbar-button button" )[ 1 ].click();' )
  wait = Selenium::WebDriver::Wait.new( :timeout => 5 )
  wait.until { driver.find_element( :css, 'div.newspaper-image-container-overview' ) }
end

def process_page( driver, logger, page, number, category, dir )
  logger.info "processing page #{number} (#{category})"

  page.click()

  sleep 2
  enter_iframe( driver )

  wait = Selenium::WebDriver::Wait.new( :timeout => 5 )
  wait.until { driver.find_element( :css, 'div.newspaper-article' ) }

  wrapper = driver.find_element( :css, "div.page.p#{number}" )
  articles = wrapper.find_elements( :css, 'div.newspaper-article' )

  logger.info "#{articles.size} articles found"

  state = 1
  articles.each_with_index do |article,i|
    # Zoom out first!
    driver.execute_script( '$( "div.newspaper-container" ).zoom( "zoomOut", null );' )

    logger.info "processing article #{i + 1} (#{article.attribute( 'data-articleid' )})"
    next if article.attribute( 'data-articleid' ) == '0'

    begin
      driver.execute_script( '$( "div.newspaper-toolbar" ).toggle( false );' )
      article.click
    rescue Exception => e
      logger.error "#{e.message}"
      next
    ensure
      sleep 1
    end

    driver.execute_script( '$( "button.toolbar-text" ).click();' )
    driver.execute_script( '$( "button.close" ).click();' )
  end

  # Write result to file.
  content =  "<div><title>#{category}</title>"
  content << driver.execute_script( 'return $( "div.article-text-modal" ).html();' )
  content << '</div>'

  # Cleanup!
  content.gsub!( /<([bh])r[^\/>]*>/, '<\1r />' )

  doc = REXML::Document.new( content )
  calc_page_filename( dir, number ).open( 'w' ) do |handle|
    REXML::Formatters::Pretty.new.write( doc, handle )
  end

  to_overview( driver )
end

def fetch_newspaper_title_image( driver, logger )
  image = driver.find_element( :css => 'img.newspaper-image.thumb' )

  if image
    logger.info "Fetching thumbnail of title page."

    matches = /^(https?):\/\/([^:\/]+)(:\d+)?(.*)/.match( image.attribute( 'src' ) )
    secure = ( matches[ 1 ] == 'https' )
    domain = matches[ 2 ]
    port = matches[ 3 ] || ( matches[ 1 ] == 'http' ? '80' : '443' )
    image_path = Pathname.new( matches[ 4 ] )

    handle = Net::HTTP.new( domain, port )
    handle.use_ssl = secure
    handle.verify_mode = OpenSSL::SSL::VERIFY_NONE

    cookies = driver.manage.all_cookies.select {|c| c[ :domain ] == domain and c[ :secure ] == secure }
    cookies_string = cookies.map {|c| "#{c[ :name ]}=#{c[ :value ]}" }.join( ', ' )

    response = handle.get( image_path.to_s, 'Cookie' => cookies_string )
    Pathname.new( "page01#{image_path.extname}" ).open( 'wb' ) do |file|
      file.write( response.body )
    end
  else
    logger.warn "Thumbnail of title page not available."
  end
end

################################################################################

unless ARGV.size == 1 and Pathname.new( ARGV.first ).directory?
  puts "#{usage()}\n"
  exit ( ARGV.empty? ? 0 : 1 )
end

rc = get_username_and_password()
unless rc[ 'username' ] and rc[ 'password' ]
  calc_rc_filename().open( 'w' ) do |handle|
    handle.write( YAML.dump( { 'username' => nil, 'password' => nil } ) )
  end

  puts "Please add your username and password to #{calc_rc_filename()}"
  exit 0
end


logger = Logger.new( $stderr )

domain, port = 'www.meine-sz.de', '80'

driver = Selenium::WebDriver.for :firefox
driver.manage.timeouts.implicit_wait = 10

logger.info "Connecting to: http#{domain == '443' ? 's' : '' }://#{domain}"
driver.get "http#{domain == '443' ? 's' : '' }://#{domain}"

logger.info "Performing login."
form = driver.find_element( :name => 'loginform' )
form.find_element( :id => 'LoginName' ).send_keys rc[ 'username' ]
form.find_element( :id => 'LoginPassword' ).send_keys rc[ 'password' ]
form.find_element( :css => 'button.btn-primary' ).click

logger.info "Open current newspaper."
driver.find_element( :css, 'div.newspaper-image-container' ).click

sleep 5

dir = calc_dirname( logger, Pathname.new( ARGV.shift ), driver.title )
logger.info "Will write results to #{dir}"
dir.mkpath

# Enter iframe.
enter_iframe( driver )

# Fetch title page.
fetch_newspaper_title_image( driver, logger )

# To overview.
to_overview( driver )

# Process pages.
count = last_page_read( dir )

if count == 0
  first_page = driver.find_element( :css, '.newspaper-image-container' )
  process_page( driver, logger, first_page, count += 1, 'Titelseite', dir )
end

finished = false
while true
  pages = [ nil ]
  categories = [ nil ]
  overviews = driver.find_elements( :css, 'div.newspaper-image-container-overview' )
  overviews.each_with_index do |overview,i|
    # Remember category!
    tmp_c = [ '' ]
    if footer = overview.find_element( :css, 'div.newspaper-image-container-footer' )
      footer_text = driver.execute_script( 'return arguments[ 0 ].innerHTML;', footer )
      tmp_c = footer_text.split( '/' ).map {|c| c.strip }
    end

    tmp_p = overview.find_elements( :css, 'div.newspaper-image-container' )
    while tmp_p.size > tmp_c.size
      tmp_c << tmp_c.first
    end

    categories += tmp_c
    pages += tmp_p

    if pages.size > count
      process_page( driver, logger, pages[ count ], count + 1, categories[ count ], dir )
      count += 1
      break
    elsif overviews.size == ( i + 1 )
      nil
    else
      next
    end

    finished = true
  end

  break if finished
end

logger.info "processed #{count} pages"

driver.close

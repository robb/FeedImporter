#!/usr/bin/env ruby
require 'uri'
require 'net/http'
require 'rubygems'
require 'nokogiri'
require 'soundcloud'
require 'open-uri'

def colorize(text, color_code)
	"\033[#{color_code}m#{text}\033[0m"
end

def resolve(uri)
	response = Net::HTTP.get_response(uri)

	unless response['location'].nil? and response['Location'].nil?
		resolve URI.parse(response['location']) or
		URI.parse(response['Location'])
	else
        response.body
	end
end

def authenticate
	require 'settings'

	settings = load_settings

	puts "SoundCloud username:"
	username = gets.chomp

	puts "SoundCloud password:"
	password = gets.chomp

	client = Soundcloud.new({
		:client_id      => settings[:client_id],
		:client_secret  => settings[:client_secret],
		:username       => username,
		:password       => password
	})

	user = client.get('/me')

	puts colorize("Logged in as #{user.fullName or user.username}", 32)

	client
end

def download_file(url, path)
	file = File.new path, 'wb'

	data = resolve URI.parse(url)
	file.write data
	file.close
end

begin
	soundcloud = authenticate

	# Feed loading
	puts "What is the URL of the RSS feed?"
	feed_uri  = URI.parse gets.chomp
	
	unless feed_uri.host and feed_uri.scheme == 'http'
		puts colorize("Invalid URL", 31)
		exit
	end

	puts "Loading feed..."
	feed_data = resolve feed_uri
	doc = Nokogiri::XML(feed_data)

	if doc.xpath('/rss').length == 0
		puts colorize("That does not look like an RSS feed", 31)
		exit
	end

	# Upload feed items as tracks to SoundCloud
	doc.xpath('/rss/channel/item').each do |item|
		title = item.xpath('title').text
		url   = item.xpath('enclosure').first().attributes['url'].to_s

		path = url.match(/\/([a-zA-Z0-9\.\-\_]+\.[a-zA-Z0-9\.\-\_]+)$/)[1]

		if File.exists? path
			puts "#{title} already exists at #{path}"
		else
			puts "Downloading #{title}"
			download_file url, path
		end

		puts "Uploading track to SoundCloud"
		track = soundcloud.post('/tracks', :track => {
			:title       => title,
			:description => item.xpath('description').text,
			:asset_data  => File.new(path),
			:sharing     => 'private'
		})

		puts "Successfully uploaded to #{track.permalink_url}"
	end
 
rescue Soundcloud::ResponseError => e
	puts colorize("An error occured:", 31)
	puts e.to_s
end
require 'sinatra'

def send_sms_response(data)
  builder = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
    xml.answer(:type => 'sync') {
      xml.body(:paid => false) {
        xml.cdata data
      }
    }
  end

  content_type 'application/xml'
  return builder.to_xml

end

post '/partners/startmobile' do
  require 'nokogiri'
  require 'faraday'

  xml_doc  = Nokogiri::XML(request.body.read).remove_namespaces!
  stop_code = xml_doc.xpath('//body').text.strip

  # Some stops during quarantine have no transport
  no_transport_stops = [1, 5, 72, 77, 85, 86, 87, 88, 89, 90, 91, 92, 93, 139, 140, 141, 142, 143, 144, 145, 157, 158, 159, 160, 162, 163, 164, 165, 182, 183, 184, 185, 193, 232, 233, 234, 235, 271, 276, 277, 295, 296, 297, 302, 303, 306, 310, 314, 322, 324, 326, 355, 356, 357, 358, 359, 360, 366, 367, 368, 412, 413, 414, 415, 416, 471, 472, 473, 506, 507, 570, 571, 572, 573, 627, 646, 647, 660, 663, 666, 667, 668, 669, 670, 680, 681, 682, 683, 697, 703, 729, 730, 735, 743, 746, 757, 758, 759, 760, 764, 765, 769, 770, 802, 803, 1006, 1007, 1071, 1072, 1074, 1075, 1076, 1077, 1107, 1108, 1114, 1116, 1171, 1180, 1193, 1194]
  if no_transport_stops.include? stop_code.to_i
    return send_sms_response "На цій зупинці на час карантину транспорту немає"
  end

  api_url = ENV['API_URL'] || 'https://api2.lad.lviv.ua'

  response = Faraday.get "#{api_url}/stops/#{stop_code}"

  return send_sms_response "Код зупинки має бути числом, на кшталт 128" if response.status == 400
  return send_sms_response "Неправильний код зупинки" if response.status == 404

  begin
    data = JSON.parse(response.body)
  rescue JSON::ParserError => e
    data = []
  end

  halt 503 if data.empty?

  timetable = {};
  currentHour = (Time.new).hour

  data['timetable'].each do |item|
    next if (5..21).include?(currentHour) && item['route'].include?("Н") # Do not show night routes during daytime
    timetable[item['route']] = [] unless timetable.key? item['route']

    timetable[item['route']] << item['time_left'] if timetable[item['route']].length < 2
  end

  result = []
  timetable.each do |key, row|
    joined_times = row.join(', ').gsub(/хв/, 'm').gsub(/г/, 'h')
    result << "#{key}: #{joined_times}"
  end

  while result.join("\n").length > 160
    result.pop
  end

  result.sort! do |x, y|
    x[0..3] <=> y[0..3]
  end

  return send_sms_response (result.count > 0) ? result.join("\n") : "Відсутні дані про прибуття транспорту на цю зупинку у найближчі 15 хв"
end

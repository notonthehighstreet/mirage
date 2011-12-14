module Mirage
  class MockResponse
    class << self

      def add response
        stored_response_sets = responses[response.name]||={}
        stored_response_set = (stored_response_sets[response.pattern] ||= {})

        old_response = stored_response_set.delete(response.http_method)
        stored_response_set[response.http_method] = response

        response.response_id = old_response ? old_response.response_id : next_id
      end


      def get_response name, http_method, body, query_string
        find_response(body, query_string, responses[name], http_method) || default_response(body, http_method, name, query_string)
      end

      def find id
        responses.values.each do |response_sets|
          response_sets.values.each do |response_set|
            response_set.values.each do |response|
              return response if response.response_id == id
            end
          end
        end
      end

      def delete(response_id)
        responses.values.each do |response_sets|
          response_sets.values.each do |response_set|
            response_set.each do |method, response|
              response_set.delete(method) if response.response_id == response_id
            end
          end
        end
      end

      def clear
        responses.clear
        @next_id = 0
      end

      def backup
        snapshot.clear and snapshot.replace(responses.deep_clone)
      end

      def revert
        responses.clear and responses.replace(snapshot.deep_clone)
      end

      def all
        all_responses = []
        responses.values.each do |response_sets|
          response_sets.values.each do |response_set|
            response_set.values.each do |response|
              all_responses << response
            end
          end
        end
        all_responses
      end

      def default_response(body, http_method, name, query_string)
        default_response_sets = find_default_responses(name)

        until default_response_sets.empty?
          record = find_response(body, query_string, default_response_sets.delete_at(0), http_method)
          return record if record && record.default?
        end
      end

      private
      def find_response(body, query_string, response_set, http_method)
        return unless response_set
        http_method = http_method.upcase
        pattern_match = response_set.keys.find_all { |pattern| pattern != :basic }.find { |pattern| (body =~ pattern || query_string =~ pattern) }

        if pattern_match
          record = response_set[pattern_match][http_method]
        else
          record = response_set[:basic]
          record = record[http_method] if record
        end
        record
      end

      def find_default_responses(name)
        matches = responses.keys.find_all { |key| name.index(key) == 0 }.sort { |a, b| b.length <=> a.length }
        matches.collect { |key| responses[key] }
      end

      def responses
        @responses ||={}
      end

      def snapshot
        @snapshot ||={}
      end

      def next_id
        @next_id||= 0
        @next_id+=1
      end

    end

    attr_reader :response_id, :delay, :name, :pattern, :http_method, :content_type
    attr_accessor :response_id

    def initialize name, value, content_type, http_method, pattern=nil, delay=0, default=false, file=false
      @name, @value, @content_type, @http_method, @pattern, @delay, @default, @file = name, value, content_type, http_method.to_s.upcase, pattern, delay, default, file
      MockResponse.add self
    end

    def default?
      'true' == @default
    end

    def file?
      @file == 'true'
    end


    def value(body='', request_parameters={}, query_string='')
      return @value if file?

      value = @value
      value.scan(/\$\{([^\}]*)\}/).flatten.each do |pattern|

        if (parameter_match = request_parameters[pattern])
          value = value.gsub("${#{pattern}}", parameter_match)
        end

        [body, query_string].each do |string|
          if (string_match = find_match(string, pattern))
            value = value.gsub("${#{pattern}}", string_match)
          end
        end

      end
      value
    end

    private
    def find_match(string, regex)
      string.scan(/#{regex}/).flatten.first
    end
  end
end

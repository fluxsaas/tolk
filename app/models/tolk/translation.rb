# encoding: UTF-8

module Tolk
  class Translation < ActiveRecord::Base
    set_table_name "tolk_translations"

    scope :containing_text, lambda {|query| where("tolk_translations.text LIKE ?", "%#{query}%") }

    serialize :text
    validates_presence_of :text, :if => proc {|r| r.primary.blank? && !r.explicit_nil }
    validate :check_matching_variables, :if => proc { |tr| tr.primary_translation.present? }

    validates_uniqueness_of :phrase_id, :scope => :locale_id

    belongs_to :phrase, :class_name => 'Tolk::Phrase'
    belongs_to :locale, :class_name => 'Tolk::Locale'
    validates_presence_of :locale_id


    attr_accessor :force_set_primary_update
    before_save :set_primary_updated

    before_save :set_previous_text

    attr_accessor :primary
    before_validation :fix_text_type, :unless => proc {|r| r.primary }

    attr_accessor :explicit_nil
    before_validation :set_explicit_nil

    def up_to_date?
      not out_of_date?
    end

    def out_of_date?
      primary_updated?
    end

    def primary_translation
      @_primary_translation ||= begin
        if locale && !locale.primary?
          phrase.translations.primary
        end
      end
    end

    def text=(value)
      value = value.to_s if value.kind_of?(Fixnum)
      super unless value.to_s == text
    end

    def value
      if text.is_a?(String) && /^\d+$/.match(text)
        text.to_i
      else
        text
      end
    end

    def self.detect_variables(search_in)
      case search_in
        when String then Set.new(search_in.scan(/\{\{(\w+)\}\}/).flatten + search_in.scan(/\%\{(\w+)\}/).flatten)
        when Array then search_in.inject(Set[]) { |carry, item| carry + detect_variables(item) }
        when Hash then search_in.values.inject(Set[]) { |carry, item| carry + detect_variables(item) }
        else Set[]
      end
    end

    def variables
      self.class.detect_variables(text)
    end

    def variables_match?
      self.variables == primary_translation.variables
    end

    private

    def set_explicit_nil
      if self.text == '~'
        self.text = nil
        self.explicit_nil = true
      end
    end

    def fix_text_type
      if primary_translation.present?
        if self.text.is_a?(String) && !primary_translation.text.is_a?(String)
          self.text = begin
            YAML.load(self.text.strip)
          rescue ArgumentError
            nil
          end
        end

        self.text = nil if primary_translation.text.class != self.text.class
      end

      true
    end

    def set_primary_updated
      self.primary_updated = self.force_set_primary_update ? true : false
      true
    end

    def set_previous_text
      self.previous_text = self.text_was if text_changed?
      true
    end

    def check_matching_variables
      unless variables_match?
        if primary_translation.variables.empty?
          self.errors.add(:text, "The original does not contain variables, so they should not be included.")
        else
          self.errors.add(:text, "The translation should contain the variables #{variables.to_a.to_sentence}.")
        end
      end
    end
  end
end

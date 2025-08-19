# frozen_string_literal: true

# Parses an uploaded invoice PDF into a structured hash suitable for front-end prefill.
# Implementation attempts to:
# 1) Extract text via HexaPDF
# 2) Ask OpenAI to return strict JSON that conforms to our schema
# Falls back to filename-derived invoice number when parsing fails.
class InvoicePdfParser
  Result = Struct.new(
    :invoice_number,
    :invoice_date,
    :notes,
    :line_items,
    keyword_init: true,
  )

  # uploaded_io: an IO-like object (e.g., params[:file].tempfile)
  # original_filename: string
  def self.parse(uploaded_io:, original_filename:)
    text = extract_text(uploaded_io)
    parsed = call_openai_and_parse(text) if text.present?

    if parsed.is_a?(Hash)
      invoice_number = parsed["invoiceNumber"].to_s
      invoice_date_str = parsed["invoiceDate"].to_s
      notes = parsed["notes"].presence
      line_items = Array(parsed["lineItems"]).map do |li|
        {
          description: li["description"].to_s,
          quantity: (li["quantity"].to_f rescue 0.0),
          hourly: !!li["hourly"],
          pay_rate_in_subunits: (li["pay_rate_in_subunits"].to_i rescue 0),
        }
      end

      date = begin
        Date.iso8601(invoice_date_str)
      rescue
        Date.current
      end

      return Result.new(
        invoice_number: invoice_number,
        invoice_date: date,
        notes: notes,
        line_items: line_items,
      )
    end

    # Fallback to filename-based inference
    base = File.basename(original_filename.to_s, File.extname(original_filename.to_s))
    Result.new(
      invoice_number: base.presence || "",
      invoice_date: Date.current,
      notes: "Imported from #{original_filename}",
      line_items: [],
    )
  rescue => e
    Rails.logger.error("InvoicePdfParser failed: #{e.class}: #{e.message}")
    Result.new(invoice_number: "", invoice_date: Date.current, notes: nil, line_items: [])
  end

  # --- Optional future extensions below ---
  def self.extract_text(uploaded_io)
    require "hexapdf"
    uploaded_io.rewind if uploaded_io.respond_to?(:rewind)
    doc = HexaPDF::Document.open(uploaded_io)
    doc.pages.map { |page| page.to_text }.join("\n")
  rescue => e
    Rails.logger.warn("HexaPDF extraction failed: #{e.class}: #{e.message}")
    ""
  end

  def self.call_openai_and_parse(text)
    client = OpenAI::Client.new
    prompt = <<~PROMPT
      You are a strictly validating JSON extractor. Given the following invoice text, extract exactly this JSON schema:
      {
        "invoiceNumber": string,
        "invoiceDate": string (format YYYY-MM-DD),
        "notes": string (optional),
        "lineItems": [
          { "description": string, "quantity": number, "hourly": boolean, "pay_rate_in_subunits": integer }
        ]
      }
      Only output JSON. No explanations.

      ---
      #{text}
    PROMPT

    resp = client.chat(parameters: {
      model: "gpt-4o-mini",
      messages: [
        { role: "system", content: "You output only strict JSON that matches the requested schema." },
        { role: "user", content: prompt },
      ],
      temperature: 0.1,
    })
    content = resp.dig("choices", 0, "message", "content")
    JSON.parse(content) if content.present?
  rescue => e
    Rails.logger.warn("OpenAI parsing failed: #{e.class}: #{e.message}")
    nil
  end
end

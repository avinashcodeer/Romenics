require "test_helper"
require "shrine/plugins/default_url"

describe Shrine::Plugins::DefaultUrl do
  before do
    @attacher = attacher { plugin :default_url }
    @shrine   = @attacher.shrine_class
  end

  describe "Attacher" do
    describe "#url" do
      it "returns block value when attachment is missing" do
        @attacher.class.default_url { "default_url" }

        assert_equal "default_url", @attacher.url
      end

      it "returns nil when no block is given and attachment is missing" do
        assert_nil @attacher.url
      end

      it "returns attachment URL if attachment is present" do
        @attacher.class.default_url { "default_url" }

        @attacher.attach(fakeio)

        assert_equal @attacher.file.url, @attacher.url
      end

      it "evaluates the block in context of the attacher instance" do
        @attacher.class.default_url { to_s }

        assert_equal @attacher.to_s, @attacher.url
      end

      it "yields the given URL options to the block" do
        @attacher.class.default_url { |**options| options.to_json }

        assert_equal '{"foo":"bar"}', @attacher.url(foo: "bar")
      end

      it "accepts :host" do
        @shrine.plugin :default_url, host: "https://example.com"
        @attacher.class.default_url { "/bar/baz" }
        assert_equal "https://example.com/bar/baz", @attacher.url

        @shrine.plugin :default_url, host: "https://example.com/foo"
        assert_equal "https://example.com/foo/bar/baz", @attacher.url
      end

      it "doesn't override previously set default URL if no block is given" do
        @attacher.class.default_url { "default_url" }
        @shrine.plugin :default_url

        assert_equal "default_url", @attacher.url
      end
    end
  end
end

require "test_helper"
require "shrine/plugins/derivatives"
require "dry-monitor"

describe Shrine::Plugins::Derivatives do
  before do
    @attacher = attacher { plugin :derivatives }
    @shrine   = @attacher.shrine_class
  end

  describe "Attachment" do
    before do
      @shrine.plugin :model

      @attacher = @shrine::Attacher.new

      @model_class = model_class(:file_data)
      @model_class.include @shrine::Attachment.new(:file)
    end

    describe "#<name>_derivatives" do
      it "returns the hash of derivatives" do
        @attacher.add_derivatives({ one: fakeio })

        model = @model_class.new(file_data: @attacher.column_data)

        assert_equal @attacher.derivatives, model.file_derivatives
      end

      it "forward arguments" do
        @attacher.add_derivatives({ one: fakeio, two: { three: fakeio } })

        model = @model_class.new(file_data: @attacher.column_data)

        assert_equal @attacher.derivatives[:one],         model.file_derivatives(:one)
        assert_equal @attacher.derivatives[:two][:three], model.file_derivatives(:two, :three)
      end

      it "returns empty hash for no derivatives" do
        model = @model_class.new(file_data: nil)

        assert_equal Hash.new, model.file_derivatives
      end
    end

    describe "#<name>_derivatives!" do
      it "creates derivatives" do
        @attacher.class.derivatives :reversed do |original|
          { reversed: StringIO.new(original.read.reverse) }
        end

        file  = @attacher.upload(fakeio("file"))
        model = @model_class.new(file_data: file.to_json)
        model.file_derivatives!(:reversed)

        assert_equal "elif", model.file_derivatives[:reversed].read
      end

      it "creates default derivatives" do
        @attacher.class.derivatives do |original|
          { reversed: StringIO.new(original.read.reverse) }
        end

        file  = @attacher.upload(fakeio("file"))
        model = @model_class.new(file_data: file.to_json)
        model.file_derivatives!

        assert_equal "elif", model.file_derivatives[:reversed].read
      end

      it "accepts original file" do
        @attacher.class.derivatives :reversed do |original|
          { reversed: StringIO.new(original.read.reverse) }
        end

        model = @model_class.new(file_data: nil)
        model.file_derivatives!(:reversed, fakeio("file"))

        assert_equal "elif", model.file_derivatives[:reversed].read
      end

      it "accepts processor options" do
        @attacher.class.derivatives :options do |original, **options|
          { options: StringIO.new(options.to_s) }
        end

        file  = @attacher.upload(fakeio("file"))
        model = @model_class.new(file_data: file.to_json)
        model.file_derivatives!(:options, foo: "bar")

        assert_equal '{:foo=>"bar"}', model.file_derivatives[:options].read
      end

      it "is not defined for entity attachments" do
        @model_class = model_class(:file_data)
        @model_class.include @shrine::Attachment.new(:file, model: false)

        refute @model_class.method_defined?(:file_derivatives!)
      end
    end

    describe "#<name>" do
      it "returns derivatives with arguments" do
        @attacher.add_derivatives({ one: fakeio })

        model = @model_class.new(file_data: @attacher.column_data)

        assert_equal @attacher.derivatives[:one], model.file(:one)
      end

      it "still returns original file without arguments" do
        @attacher.attach(fakeio)

        model = @model_class.new(file_data: @attacher.column_data)

        assert_equal @attacher.file, model.file
      end

      it "raises exception when #[] is used with symbol key" do
        @attacher.attach(fakeio)

        model = @model_class.new(file_data: @attacher.column_data)

        assert_raises(Shrine::Error) { model.file[:one] }
      end

      it "still allows calling #[] with string keys" do
        @attacher.attach(fakeio)

        model = @model_class.new(file_data: @attacher.column_data)

        assert_equal @attacher.file.size, model.file["size"]
      end
    end

    describe "#<name>_url" do
      it "returns derivative URL with arguments" do
        @attacher.add_derivatives({ one: fakeio })

        model = @model_class.new(file_data: @attacher.column_data)

        assert_equal @attacher.derivatives[:one].url, model.file_url(:one)
        assert_equal @attacher.derivatives[:one].url, model.file_url(:one, foo: "bar")
      end

      it "still returns original file URL without arguments" do
        @attacher.attach(fakeio)

        model = @model_class.new(file_data: @attacher.column_data)

        assert_equal @attacher.file.url, model.file_url
        assert_equal @attacher.file.url, model.file_url(foo: "bar")
      end
    end
  end

  describe "Attacher" do
    describe "#initialize" do
      it "initializes derivatives to empty hash" do
        attacher = @shrine::Attacher.new

        assert_equal Hash.new, attacher.derivatives
      end

      it "accepts derivatives" do
        derivatives = { one: @attacher.upload(fakeio) }
        attacher    = @shrine::Attacher.new(derivatives: derivatives)

        assert_equal derivatives, attacher.derivatives
      end

      it "forwards additional options to super" do
        attacher = @shrine::Attacher.new(store: :other_store)

        assert_equal :other_store, attacher.store_key
      end
    end

    describe "#get" do
      it "returns original file without arguments" do
        @attacher.attach(fakeio)

        assert_equal @attacher.file, @attacher.get
      end

      it "retrieves selected derivative" do
        @attacher.add_derivatives({ one: fakeio })

        assert_equal @attacher.derivatives[:one], @attacher.get(:one)
      end

      it "retrieves selected nested derivative" do
        @attacher.add_derivatives({ one: { two: fakeio } })

        assert_equal @attacher.derivatives[:one][:two], @attacher.get(:one, :two)
      end
    end

    describe "#get_derivatives" do
      it "returns all derivatives without arguments" do
        @attacher.add_derivatives({ one: fakeio })

        assert_equal @attacher.derivatives, @attacher.get_derivatives
      end

      it "retrieves derivative with given name" do
        @attacher.add_derivatives({ one: fakeio })

        assert_equal @attacher.derivatives[:one], @attacher.get_derivatives(:one)
      end

      it "retrieves nested derivatives" do
        @attacher.add_derivatives({ one: { two: fakeio } })

        assert_equal @attacher.derivatives[:one][:two], @attacher.get_derivatives(:one, :two)
      end

      it "handles string keys" do
        @attacher.add_derivatives({ one: { two: fakeio } })

        assert_equal @attacher.derivatives[:one][:two], @attacher.get_derivatives("one", "two")
      end

      it "handles array indices" do
        @attacher.add_derivatives({ one: [fakeio] })

        assert_equal @attacher.derivatives[:one][0], @attacher.get_derivatives(:one, 0)
      end
    end

    describe "#url" do
      describe "without arguments" do
        it "returns original file URL" do
          @attacher.attach(fakeio)

          assert_equal @attacher.file.url, @attacher.url
        end

        it "returns nil when original file is missing" do
          assert_nil @attacher.url
        end

        it "returns default URL when original file is missing" do
          @shrine::Attacher.default_url { "default_url" }

          assert_equal "default_url", @attacher.url
        end

        it "passes options to the default URL block" do
          @shrine::Attacher.default_url { |foo:, **| foo }

          assert_equal "bar", @attacher.url(foo: "bar")
        end
      end

      describe "with arguments" do
        it "returns derivative URL" do
          @attacher.add_derivatives({ one: fakeio })

          assert_equal @attacher.derivatives[:one].url, @attacher.url(:one)
        end

        it "returns nested derivative URL" do
          @attacher.add_derivatives({ one: { two: fakeio } })

          assert_equal @attacher.derivatives[:one][:two].url, @attacher.url(:one, :two)
        end

        it "passes URL options to derivative URL" do
          @attacher.add_derivatives({ one: fakeio })

          @attacher.derivatives[:one].expects(:url).with(foo: "bar")

          @attacher.url(:one, foo: "bar")
        end

        it "returns nil when derivative is not present" do
          assert_nil @attacher.url(:one)
        end

        it "handles string keys" do
          @attacher.add_derivatives({ one: fakeio })

          assert_equal @attacher.derivatives[:one].url, @attacher.url(:one)
        end

        it "works with default URL" do
          @shrine::Attacher.default_url { "default_url" }

          @attacher.add_derivatives({ one: fakeio })

          assert_equal @attacher.derivatives[:one].url, @attacher.url(:one)
          assert_equal "default_url",                   @attacher.url(:two)
        end

        it "passes :derivative to default URL block" do
          @shrine::Attacher.default_url { |derivative:, **| derivative.inspect }

          assert_equal ":one",         @attacher.url(:one)
          assert_equal "[:one, :two]", @attacher.url(:one, :two)
        end

        it "passes options to the default URL block" do
          @shrine::Attacher.default_url { |foo:, **| foo }

          assert_equal "bar", @attacher.url(:one, foo: "bar")
        end
      end
    end

    describe "#promote" do
      it "uploads cached derivatives to permanent storage" do
        @attacher.attach_cached(fakeio)
        @attacher.add_derivative(:one, fakeio, storage: :cache)

        @attacher.promote

        assert_equal :store, @attacher.file.storage_key
        assert_equal :store, @attacher.derivatives[:one].storage_key
      end

      it "forwards promote options" do
        @attacher.attach_cached(fakeio)

        @attacher.promote(location: "foo")

        assert_equal "foo", @attacher.file.id
      end

      it "works with backgrounding plugin" do
        @attacher = attacher do
          plugin :backgrounding
          plugin :derivatives
        end

        @attacher.promote_block do |attacher|
          @job = Fiber.new { @attacher.promote }
        end

        @attacher.attach_cached(fakeio)
        @attacher.add_derivative(:one, fakeio, storage: :cache)

        @attacher.promote_cached

        assert_equal :cache, @attacher.file.storage_key
        assert_equal :cache, @attacher.derivatives[:one].storage_key

        @job.resume

        assert_equal :store, @attacher.file.storage_key
        assert_equal :store, @attacher.derivatives[:one].storage_key
      end

      it "creates derivatives when :create_on_promote is enabled" do
        @attacher.class.derivatives { { one: StringIO.new } }

        @attacher.attach_cached(fakeio)
        @attacher.promote

        assert_empty @attacher.derivatives

        @shrine.plugin :derivatives, create_on_promote: true

        @attacher.attach_cached(fakeio)
        @attacher.promote

        assert_instance_of @shrine::UploadedFile, @attacher.derivatives.fetch(:one)
      end
    end

    describe "#promote_derivatives" do
      it "uploads cached derivatives to permanent storage" do
        @attacher.add_derivative(:one,   fakeio("one"),   storage: :cache)
        @attacher.add_derivative(:two,   fakeio("two"),   storage: :store)
        @attacher.add_derivative(:three, fakeio("three"), storage: :other_store)

        derivatives = @attacher.derivatives

        @attacher.promote_derivatives

        assert_equal :store,       @attacher.derivatives[:one].storage_key
        assert_equal :store,       @attacher.derivatives[:two].storage_key
        assert_equal :other_store, @attacher.derivatives[:three].storage_key

        assert_equal "one",   @attacher.derivatives[:one].read
        assert_equal "two",   @attacher.derivatives[:two].read
        assert_equal "three", @attacher.derivatives[:three].read

        refute_equal derivatives[:one],   @attacher.derivatives[:one]
        assert_equal derivatives[:two],   @attacher.derivatives[:two]
        assert_equal derivatives[:three], @attacher.derivatives[:three]
      end

      it "handles nested derivatives" do
        @attacher.add_derivatives({ one: { two: fakeio } }, storage: :cache)
        @attacher.promote_derivatives

        assert_equal :store, @attacher.derivatives[:one][:two].storage_key
      end

      it "passes correct :derivative parameter to the uploader" do
        @attacher.add_derivatives({ one: fakeio, two: { three: fakeio } }, storage: :cache)
        @shrine.expects(:upload).with { |*, o| o[:derivative] == :one }
        @shrine.expects(:upload).with { |*, o| o[:derivative] == [:two, :three] }
        @attacher.promote_derivatives
      end

      it "forwards promote options" do
        @attacher.add_derivative(:one, fakeio, storage: :cache)

        @attacher.promote_derivatives(location: "foo")

        assert_equal "foo", @attacher.derivatives[:one].id
      end

      it "doesn't clear original file" do
        @attacher.attach_cached(fakeio)
        @attacher.add_derivative(:one, fakeio, storage: :cache)

        @attacher.promote_derivatives

        assert_equal :cache, @attacher.file.storage_key
      end
    end

    describe "#destroy" do
      it "deletes derivatives" do
        @attacher.attach(fakeio)
        @attacher.add_derivatives({ one: fakeio })

        @attacher.destroy

        refute @attacher.file.exists?
        refute @attacher.derivatives[:one].exists?
      end

      it "works with backgrounding plugin" do
        @attacher = attacher do
          plugin :backgrounding
          plugin :derivatives
        end

        @attacher.destroy_block do |attacher|
          @job = Fiber.new { @attacher.destroy }
        end

        @attacher.attach(fakeio)
        @attacher.add_derivatives({ one: fakeio })

        @attacher.destroy_attached

        assert @attacher.file.exists?
        assert @attacher.derivatives[:one].exists?

        @job.resume

        refute @attacher.file.exists?
        refute @attacher.derivatives[:one].exists?
      end
    end

    describe "#delete_derivatives" do
      it "deletes set derivatives" do
        @attacher.add_derivatives({ one: fakeio })

        @attacher.delete_derivatives

        refute @attacher.derivatives[:one].exists?
      end

      it "deletes given derivatives" do
        derivatives = { one: @attacher.upload(fakeio) }

        @attacher.delete_derivatives(derivatives)

        refute derivatives[:one].exists?
      end

      it "works with nested derivatives" do
        derivatives = { one: { two: @attacher.upload(fakeio) } }

        @attacher.delete_derivatives(derivatives)

        refute derivatives[:one][:two].exists?
      end

      it "works with top level array" do
        derivatives = [@attacher.upload(fakeio)]

        @attacher.delete_derivatives(derivatives)

        refute derivatives[0].exists?
      end
    end

    describe "#create_derivatives" do
      it "calls processor, then uploads and saves results" do
        @attacher.class.derivatives :reversed do |original|
          { reversed: StringIO.new(original.read.reverse) }
        end

        @attacher.attach fakeio("file")
        @attacher.create_derivatives(:reversed)

        assert_kind_of Shrine::UploadedFile, @attacher.derivatives[:reversed]
        assert_equal "elif", @attacher.derivatives[:reversed].read
      end

      it "calls default processor" do
        @attacher.class.derivatives do |original|
          { reversed: StringIO.new(original.read.reverse) }
        end

        @attacher.attach fakeio("file")
        @attacher.create_derivatives

        assert_kind_of Shrine::UploadedFile, @attacher.derivatives[:reversed]
        assert_equal "elif", @attacher.derivatives[:reversed].read
      end

      it "forwards original file to processor" do
        @attacher.class.derivatives :reversed do |original|
          { reversed: StringIO.new(original.read.reverse) }
        end

        @attacher.create_derivatives(:reversed, fakeio("file"))

        assert_equal "elif", @attacher.derivatives[:reversed].read
      end

      it "forwards additional options to processor" do
        @attacher.class.derivatives :options do |original, **options|
          { options: StringIO.new(options.to_s) }
        end

        @attacher.attach fakeio("file")
        @attacher.create_derivatives(:options, foo: "bar")

        assert_equal '{:foo=>"bar"}', @attacher.derivatives[:options].read
      end

      it "accepts :storage" do
        @attacher.class.derivatives :reversed do |original|
          { reversed: StringIO.new(original.read.reverse) }
        end

        @attacher.create_derivatives(:reversed, fakeio("file"), storage: :cache)

        assert_equal :cache, @attacher.derivatives[:reversed].storage_key
        assert_equal "elif", @attacher.derivatives[:reversed].read
      end
    end

    describe "#add_derivatives" do
      it "uploads given files to permanent storage" do
        @attacher.add_derivatives({ one: fakeio })

        assert_equal :store, @attacher.derivatives[:one].storage_key
      end

      it "merges new derivatives with existing derivatives" do
        @attacher.add_derivatives({ one: fakeio })
        @attacher.add_derivatives({ two: fakeio })

        assert_kind_of Shrine::UploadedFile, @attacher.derivatives[:one]
        assert_kind_of Shrine::UploadedFile, @attacher.derivatives[:two]
      end

      it "returns added derivatives" do
        derivatives = @attacher.add_derivatives({ one: fakeio("one") })

        assert_equal @attacher.derivatives, derivatives
      end

      it "forwards additional options for uploading" do
        @attacher.add_derivatives({ one: fakeio }, storage: :other_store)

        assert_equal :other_store, @attacher.derivatives[:one].storage_key
      end
    end

    describe "#add_derivative" do
      it "uploads given file to permanent storage" do
        @attacher.add_derivative(:one, fakeio)

        assert_equal :store, @attacher.derivatives[:one].storage_key
      end

      it "merges new derivative with existing derivatives" do
        @attacher.add_derivative(:one, fakeio)
        @attacher.add_derivative(:two, fakeio)

        assert_kind_of Shrine::UploadedFile, @attacher.derivatives[:one]
        assert_kind_of Shrine::UploadedFile, @attacher.derivatives[:two]
      end

      it "returns added derivative" do
        derivative = @attacher.add_derivative(:one, fakeio("one"))

        assert_instance_of @shrine::UploadedFile, derivative
        assert_equal "one", derivative.read
      end

      it "forwards additional options for uploading" do
        @attacher.add_derivative(:one, fakeio, storage: :other_store)

        assert_equal :other_store, @attacher.derivatives[:one].storage_key
      end
    end

    describe "#upload_derivatives" do
      it "uploads given files to permanent storage" do
        derivatives = @attacher.upload_derivatives({ one: fakeio })

        assert_kind_of Shrine::UploadedFile, derivatives[:one]
        assert_equal :store, derivatives[:one].storage_key
        assert derivatives[:one].exists?
      end

      it "passes derivative name to the uploader" do
        @shrine.expects(:upload).with { |*, o| o[:derivative] == :one }
        @attacher.upload_derivatives({ one: fakeio })

        @shrine.expects(:upload).with { |*, o| o[:derivative] == [:one, :two] }
        @attacher.upload_derivatives({ one: { two: fakeio } })
      end

      it "accepts additional options" do
        derivatives = @attacher.upload_derivatives({ one: fakeio }, storage: :other_store)

        assert_equal :other_store, derivatives[:one].storage_key
        assert derivatives[:one].exists?
      end

      it "works with nested derivatives" do
        derivatives = @attacher.upload_derivatives({ one: { two: fakeio } })

        assert_kind_of Shrine::UploadedFile, derivatives[:one][:two]
        assert_equal :store, derivatives[:one][:two].storage_key
        assert derivatives[:one][:two].exists?
      end

      it "coerces string keys" do
        io = fakeio
        derivatives = @attacher.upload_derivatives({ "one" => io })
        assert_kind_of Shrine::UploadedFile, derivatives[:one]

        io = fakeio
        derivatives = @attacher.upload_derivatives({ "one" => { "two" => io } })
        assert_kind_of Shrine::UploadedFile, derivatives[:one][:two]
      end
    end

    describe "#upload_derivative" do
      it "uploads given IO to permanent storage" do
        derivative = @attacher.upload_derivative(:one, fakeio("one"))

        assert_instance_of @shrine::UploadedFile, derivative
        assert_equal :store, derivative.storage_key
        assert derivative.exists?
        assert_equal "one", derivative.read
      end

      it "infers destination storage from :storage plugin option" do
        @shrine.plugin :derivatives, storage: :other_store
        derivative = @attacher.upload_derivative(:one, fakeio)
        assert_equal :other_store, derivative.storage_key

        minitest = self
        @shrine.plugin :derivatives, storage: -> (name) {
          minitest.assert_equal :one, name
          minitest.assert_kind_of Shrine::Attacher, self
          :other_store
        }
        derivative = @attacher.upload_derivative(:one, fakeio)
        assert_equal :other_store, derivative.storage_key
      end

      it "infers destination storage from Attacher.derivative_storage value" do
        @attacher.class.derivatives_storage :other_store
        derivative = @attacher.upload_derivative(:one, fakeio)
        assert_equal :other_store, derivative.storage_key

        minitest = self
        @attacher.class.derivatives_storage do |name|
          minitest.assert_equal :one, name
          minitest.assert_kind_of Shrine::Attacher, self
          :other_store
        end
        derivative = @attacher.upload_derivative(:one, fakeio)
        assert_equal :other_store, derivative.storage_key
      end

      it "uses :storage option passed to the method" do
        derivative = @attacher.upload_derivative(:one, fakeio, storage: :other_store)

        assert_equal :other_store, derivative.storage_key
      end

      it "refreshes Tempfile descriptor" do
        tempfile = Tempfile.new
        File.write(tempfile.path, "content")

        derivative = @attacher.upload_derivative(:one, tempfile)

        assert_equal "content", derivative.read
      end

      it "ensures binary mode" do
        @attacher.store.storage.expects(:upload).with { |file, *| file.binmode? }

        @attacher.upload_derivative(:one, Tempfile.new)
      end

      it "passes derivative name to the uploader" do
        @shrine.expects(:upload).with { |*, o| o[:derivative] == :one }
        @attacher.upload_derivative(:one, fakeio)
      end

      it "sets :action to :derivatives" do
        @shrine.expects(:upload).with { |*, o| o[:action] == :derivatives }

        @attacher.upload_derivative(:one, fakeio)
      end

      it "forwards additional options for uploading" do
        derivative = @attacher.upload_derivative(:one, fakeio, location: "foo")

        assert_equal "foo", derivative.id
      end

      it "deletes uploaded files" do
        @attacher.upload_derivative(:one, file = tempfile("file"))

        refute File.exist?(file.path)
      end

      it "skips deletion when :delete is false" do
        @attacher.upload_derivative(:one, file = tempfile("file"), delete: false)

        assert File.exist?(file.path)
      end
    end

    describe "#process_derivatives" do
      it "calls the registered processor" do
        @attacher.class.derivatives :reversed do |original|
          { reversed: StringIO.new(original.read.reverse) }
        end

        @attacher.attach fakeio("file")
        files = @attacher.process_derivatives(:reversed)

        assert_instance_of StringIO, files[:reversed]
        assert_equal "elif", files[:reversed].read
      end

      it "calls the default processor" do
        @attacher.class.derivatives do |original|
          { reversed: StringIO.new(original.read.reverse) }
        end

        @attacher.attach fakeio("file")
        files = @attacher.process_derivatives

        assert_instance_of StringIO, files[:reversed]
        assert_equal "elif", files[:reversed].read
      end

      it "passes downloaded attached file" do
        minitest = self
        @attacher.class.derivatives :reversed do |original|
          minitest.assert_instance_of Tempfile, original

          { reversed: StringIO.new(original.read.reverse) }
        end

        @attacher.attach fakeio("file")
        @attacher.process_derivatives(:reversed)
      end

      it "allows passing source file" do
        @attacher.class.derivatives :reversed do |original|
          { reversed: StringIO.new(original.read.reverse) }
        end

        files = @attacher.process_derivatives(:reversed, fakeio("other"))

        assert_instance_of StringIO, files[:reversed]
        assert_equal "rehto", files[:reversed].read
      end

      it "allows passing source file with default processor" do
        @attacher.class.derivatives do |original|
          { reversed: StringIO.new(original.read.reverse) }
        end

        files = @attacher.process_derivatives(fakeio("other"))

        assert_instance_of StringIO, files[:reversed]
        assert_equal "rehto", files[:reversed].read
      end

      it "downloads source UploadedFile" do
        @attacher.class.derivatives :path do |original|
          { path: StringIO.new(original.path) }
        end

        file   = @attacher.upload(fakeio("file"))
        result = @attacher.process_derivatives(:path, file)

        assert_match /^#{Dir.tmpdir}/, result[:path].read
      end

      it "does not download source UploadedFile with raw_source" do
        @attacher.class.derivatives :original_class, raw_source: true do |original|
          { original_class: StringIO.new(original.class.inspect) }
        end

        file   = @attacher.upload(fakeio("file"))
        result = @attacher.process_derivatives(:original_class, file)

        assert_match /::UploadedFile\Z/, result[:original_class].read
      end

      it "downloads source non-file IO" do
        @attacher.class.derivatives :path do |original|
          { path: original.respond_to?(:path) ? StringIO.new(original.path) : nil }
        end

        result = @attacher.process_derivatives(:path, StringIO.new("fake content"))

        assert result[:path]
        assert_match /^#{Dir.tmpdir}/, result[:path].read
      end

      it "does not download source StringIO with raw_source" do
        @attacher.class.derivatives :original_class, raw_source: true do |original|
          { original_class: StringIO.new(original.class.inspect) }
        end

        result = @attacher.process_derivatives(:original_class, StringIO.new("stringIO"))

        assert_equal "StringIO", result[:original_class].read
      end

      it "forwards additional options" do
        @attacher.class.derivatives :options do |original, **options|
          { options: StringIO.new(options.to_s) }
        end

        @attacher.attach(fakeio)
        files = @attacher.process_derivatives(:options, foo: "bar")

        assert_equal '{:foo=>"bar"}', files[:options].read
      end

      it "evaluates block in context of Attacher instance" do
        this = nil
        @attacher.class.derivatives :reversed do |original|
          this = self
          { reversed: StringIO.new(original.read.reverse) }
        end

        @attacher.attach(fakeio)
        @attacher.process_derivatives(:reversed)

        assert_equal @attacher, this
      end

      it "handles string keys" do
        @attacher.class.derivatives :symbol_reversed do |original|
          { reversed: StringIO.new(original.read.reverse) }
        end

        @attacher.attach fakeio("file")
        @attacher.process_derivatives("symbol_reversed")

        @attacher.class.derivatives "string_reversed" do |original|
          { reversed: StringIO.new(original.read.reverse) }
        end

        @attacher.attach fakeio("file")
        @attacher.process_derivatives(:string_reversed)
      end

      it "fails if process result is not a Hash" do
        @attacher.class.derivatives :reversed do |original|
          :invalid
        end

        @attacher.attach(fakeio)

        assert_raises Shrine::Error do
          @attacher.process_derivatives(:reversed)
        end
      end

      it "fails if processor was not found" do
        @attacher.attach(fakeio)

        assert_raises Shrine::Error do
          @attacher.process_derivatives(:unknown)
        end
      end

      it "doesn't fail for missing default processor" do
        @attacher.attach(fakeio)
        @attacher.process_derivatives

        assert_equal Hash.new, @attacher.derivatives
      end

      it "fails if no file is attached" do
        @attacher.class.derivatives :reversed do |original|
          { reversed: StringIO.new(original.read.reverse) }
        end

        assert_raises Shrine::Error do
          @attacher.process_derivatives(:reversed)
        end
      end

      describe "with instrumentation" do
        before do
          @shrine.plugin :instrumentation, notifications: Dry::Monitor::Notifications.new(:test)

          @attacher.class.derivatives :reversed do |original|
            { reversed: StringIO.new(original.read.reverse) }
          end

          @attacher.attach(fakeio)
        end

        it "logs derivatives processing" do
          @shrine.plugin :derivatives

          assert_logged /^Derivatives \(\d+ms\) – \{.+\}$/ do
            @attacher.process_derivatives(:reversed)
          end
        end

        it "sends derivatives processing event" do
          @shrine.plugin :derivatives

          @shrine.subscribe(:derivatives) { |event| @event = event }
          @attacher.process_derivatives(:reversed, foo: "bar")

          refute_nil @event
          assert_equal :derivatives,     @event.name
          assert_equal :reversed,        @event[:processor]
          assert_equal Hash[foo: "bar"], @event[:processor_options]
          assert_instance_of Tempfile,   @event[:io]
          assert_equal @attacher,        @event[:attacher]
          assert_equal @shrine,          @event[:uploader]
          assert_kind_of Integer,        @event.duration
        end

        it "allows swapping log subscriber" do
          @shrine.plugin :derivatives, log_subscriber: -> (event) { @event = event }

          refute_logged /^Derivatives/ do
            @attacher.process_derivatives(:reversed)
          end

          refute_nil @event
        end

        it "allows disabling log subscriber" do
          @shrine.plugin :derivatives, log_subscriber: nil

          refute_logged /^Derivatives/ do
            @attacher.process_derivatives(:reversed)
          end
        end
      end
    end

    describe "#remove_derivatives" do
      it "removes top level derivatives" do
        @attacher.add_derivatives({ one: fakeio, two: fakeio, three: fakeio })

        derivatives = @attacher.derivatives.dup
        two, three  = @attacher.remove_derivatives(:two, :three)

        assert_equal Hash[one: derivatives[:one]], @attacher.derivatives

        assert_equal derivatives[:two],   two
        assert_equal derivatives[:three], three

        assert two.exists?
        assert three.exists?
      end

      it "removes nested derivatives" do
        @attacher.add_derivatives({ nested: { one: fakeio, two: fakeio, three: fakeio } })

        derivatives = { nested: @attacher.derivatives[:nested].dup }
        two, three  = @attacher.remove_derivatives([:nested, :two], [:nested, :three])

        assert_equal Hash[nested: { one: derivatives[:nested][:one] }], @attacher.derivatives

        assert_equal derivatives[:nested][:two],   two
        assert_equal derivatives[:nested][:three], three

        assert two.exists?
        assert three.exists?
      end

      it "allows deleting removed derivatives" do
        @attacher.add_derivatives({ one: fakeio, two: fakeio, three: fakeio })

        two, three = @attacher.remove_derivatives(:two, :three, delete: true)

        refute two.exists?
        refute three.exists?
      end
    end

    describe "#remove_derivative" do
      it "removes top level derivative" do
        @attacher.add_derivatives({ one: fakeio, two: fakeio })

        derivatives = @attacher.derivatives.dup

        two = @attacher.remove_derivative(:two)

        assert_equal Hash[one: derivatives[:one]], @attacher.derivatives

        assert_equal derivatives[:two], two
        assert two.exists?
      end

      it "removes nested derivative" do
        @attacher.add_derivatives({ nested: { one: fakeio, two: fakeio } })

        derivatives = { nested: @attacher.derivatives[:nested].dup }

        two = @attacher.remove_derivative([:nested, :two])

        assert_equal Hash[nested: { one: derivatives[:nested][:one] }], @attacher.derivatives

        assert_equal derivatives[:nested][:two], two
        assert two.exists?
      end

      it "allows deleting removed derivative" do
        @attacher.add_derivatives({ one: fakeio, two: fakeio })

        two = @attacher.remove_derivative(:two, delete: true)

        refute two.exists?
      end
    end

    describe "#merge_derivatives" do
      it "merges current derivatives with given derivatives" do
        @attacher.merge_derivatives @attacher.upload_derivatives({ one: fakeio })
        @attacher.merge_derivatives @attacher.upload_derivatives({ two: fakeio })

        assert_kind_of Shrine::UploadedFile, @attacher.derivatives[:one]
        assert_kind_of Shrine::UploadedFile, @attacher.derivatives[:two]
      end

      it "does deep merging" do
        @attacher.add_derivatives({ hash: { one: fakeio("one") }, array: [fakeio("0")] })

        @attacher.merge_derivatives @attacher.upload_derivatives({
          hash: { two: fakeio("two") }, array: [fakeio("1")]
        })

        assert_equal "one", @attacher.derivatives[:hash][:one].read
        assert_equal "two", @attacher.derivatives[:hash][:two].read
        assert_equal "0",   @attacher.derivatives[:array][0].read
        assert_equal "1",   @attacher.derivatives[:array][1].read
      end
    end

    describe "#set_derivatives" do
      it "sets given derivatives" do
        derivatives = @attacher.upload_derivatives({ one: fakeio })
        @attacher.set_derivatives(derivatives)

        assert_equal derivatives, @attacher.derivatives
      end

      it "returns set derivatives" do
        derivatives = @attacher.upload_derivatives({ one: fakeio })

        assert_equal derivatives, @attacher.set_derivatives(derivatives)
      end

      it "doesn't clear the attached file" do
        @attacher.attach(fakeio)
        @attacher.set_derivatives @attacher.upload_derivatives({ one: fakeio })

        assert_kind_of Shrine::UploadedFile, @attacher.file
      end

      it "triggers model writing" do
        @shrine.plugin :model

        model = model(file_data: nil)
        @attacher.load_model(model, :file)

        @attacher.attach(fakeio)
        assert_equal @attacher.column_data, model.file_data

        @attacher.set_derivatives @attacher.upload_derivatives({ one: fakeio })
        assert_equal @attacher.column_data, model.file_data
      end
    end

    describe "#data" do
      it "adds derivatives data to existing hash" do
        @attacher.attach(fakeio)
        @attacher.add_derivatives({ one: fakeio })

        assert_equal @attacher.file.data.merge(
          "derivatives" => {
            "one" => @attacher.derivatives[:one].data
          }
        ), @attacher.data
      end

      it "handles nested derivatives" do
        @attacher.attach(fakeio)
        @attacher.add_derivatives({ one: { two: fakeio } })

        assert_equal @attacher.file.data.merge(
          "derivatives" => {
            "one" => { "two" => @attacher.derivatives[:one][:two].data }
          }
        ), @attacher.data
      end

      it "allows no attached file" do
        @attacher.add_derivatives({ one: fakeio })

        assert_equal Hash[
          "derivatives" => {
            "one" => @attacher.derivatives[:one].data
          }
        ], @attacher.data
      end

      it "returns attached file data without derivatives" do
        @attacher.attach(fakeio)

        assert_equal @attacher.file.data, @attacher.data
      end

      it "returns nil without attached file or derivatives" do
        assert_nil @attacher.data
      end
    end

    describe "#load_data" do
      it "loads derivatives" do
        file        = @attacher.upload(fakeio)
        derivatives = @attacher.upload_derivatives({ one: fakeio })

        @attacher.load_data file.data.merge(
          "derivatives" => {
            "one" => derivatives[:one].data,
          }
        )

        assert_equal file,        @attacher.file
        assert_equal derivatives, @attacher.derivatives
      end

      it "handles nested derivatives" do
        file        = @attacher.upload(fakeio)
        derivatives = @attacher.upload_derivatives({ one: { two: fakeio } })

        @attacher.load_data file.data.merge(
          "derivatives" => {
            "one" => { "two" => derivatives[:one][:two].data }
          }
        )

        assert_equal file,        @attacher.file
        assert_equal derivatives, @attacher.derivatives
      end

      it "loads derivatives without attached file" do
        derivatives = @attacher.upload_derivatives({ one: fakeio })

        @attacher.load_data(
          "derivatives" => {
            "one" => derivatives[:one].data,
          }
        )

        assert_equal derivatives, @attacher.derivatives
        assert_nil @attacher.file
      end

      it "handles symbol keys" do
        file        = @attacher.upload(fakeio)
        derivatives = @attacher.upload_derivatives({ one: fakeio })

        @attacher.load_data file.data.merge(
          derivatives: {
            one: derivatives[:one].data,
          }
        )

        assert_equal file,        @attacher.file
        assert_equal derivatives, @attacher.derivatives
      end

      it "clears derivatives when there is no derivatives data" do
        @attacher.attach(fakeio)
        @attacher.add_derivatives({ one: fakeio })

        @attacher.load_data @attacher.file.data

        assert_equal Hash.new, @attacher.derivatives
      end

      it "works with frozen data hash" do
        file        = @attacher.upload(fakeio)
        derivatives = @attacher.upload_derivatives({ one: fakeio })

        @attacher.load_data file.data.merge(
          "derivatives" => {
            "one" => derivatives[:one].data,
          }
        ).freeze
      end

      it "loads attached file data" do
        file = @attacher.upload(fakeio)

        @attacher.load_data(file.data)

        assert_equal file, @attacher.file
      end

      it "loads no attached file or derivatives" do
        @attacher.attach(fakeio)
        @attacher.add_derivatives({ one: fakeio })

        @attacher.load_data(nil)

        assert_nil @attacher.file
        assert_equal Hash.new, @attacher.derivatives
      end
    end

    describe "#change" do
      it "clears derivatives" do
        @attacher.attach(fakeio)
        @attacher.add_derivatives({ one: fakeio })

        file = @attacher.upload(fakeio)
        @attacher.change(file)

        assert_equal Hash.new, @attacher.derivatives
        assert_equal file,     @attacher.file
      end

      it "records previous derivatives" do
        file        = @attacher.attach(fakeio)
        derivatives = @attacher.add_derivatives({ one: fakeio })

        @attacher.change(nil)
        @attacher.destroy_previous

        refute file.exists?
        refute derivatives[:one].exists?
      end
    end

    describe "#derivatives=" do
      it "sets given derivatives" do
        derivatives = { one: @attacher.upload(fakeio) }
        @attacher.derivatives = derivatives

        assert_equal derivatives, @attacher.derivatives
      end

      it "raises exception if given object is not a Hash" do
        assert_raises ArgumentError do
          @attacher.derivatives = [@attacher.upload(fakeio)]
        end
      end
    end

    describe "#map_derivative" do
      it "iterates over nested derivatives" do
        derivatives = { one: fakeio, two: { three: fakeio } }
        yielded     = @attacher.map_derivative(derivatives).to_a

        assert_equal [
          [[:one],         derivatives[:one]],
          [[:two, :three], derivatives[:two][:three]],
        ], yielded
      end
    end

    describe "versions compatibility" do
      before do
        @shrine.plugin :derivatives, versions_compatibility: true
      end

      describe "#load_data" do
        it "loads versions data with original (string)" do
          file    = @attacher.upload(fakeio)
          version = @attacher.upload(fakeio)

          @attacher.load_data("original" => file.data, "version" => version.data)

          assert_equal file,                   @attacher.file
          assert_equal Hash[version: version], @attacher.derivatives
        end

        it "loads versions data with original (symbol)" do
          file    = @attacher.upload(fakeio)
          version = @attacher.upload(fakeio)

          @attacher.load_data(original: file.data, version: version.data)

          assert_equal file,                   @attacher.file
          assert_equal Hash[version: version], @attacher.derivatives
        end

        it "loads versions data without original (string)" do
          version = @attacher.upload(fakeio)

          @attacher.load_data("version" => version.data)

          assert_equal Hash[version: version], @attacher.derivatives
          assert_nil @attacher.file
        end

        it "loads versions data without original (symbol)" do
          version = @attacher.upload(fakeio)

          @attacher.load_data(version: version.data)

          assert_equal Hash[version: version], @attacher.derivatives
          assert_nil @attacher.file
        end

        it "still works with native data format (string)" do
          file    = @attacher.upload(fakeio)
          version = @attacher.upload(fakeio)

          @attacher.load_data file.data.merge(
            "derivatives" => {
              "version" => version.data
            }
          )

          assert_equal file,                   @attacher.file
          assert_equal Hash[version: version], @attacher.derivatives
        end

        it "still works with native data format (symbol)" do
          file    = @attacher.upload(fakeio)
          version = @attacher.upload(fakeio)

          @attacher.load_data file.data.merge(
            derivatives: {
              version: version.data
            }
          )

          assert_equal file,                   @attacher.file
          assert_equal Hash[version: version], @attacher.derivatives
        end

        it "still works with plain file data (string)" do
          file = @attacher.upload(fakeio)

          @attacher.load_data(file.data)

          assert_equal file,     @attacher.file
          assert_equal Hash.new, @attacher.derivatives
        end

        it "still works with plain file data (symbol)" do
          file = @attacher.upload(fakeio)

          @attacher.load_data(
            id:       file.id,
            storage:  file.storage_key,
            metadata: file.metadata,
          )

          assert_equal file,     @attacher.file
          assert_equal Hash.new, @attacher.derivatives
        end

        it "still works with nil data" do
          @attacher.attach(fakeio)
          @attacher.add_derivatives({ one: fakeio })

          @attacher.load_data(nil)

          assert_nil @attacher.file
          assert_equal Hash.new, @attacher.derivatives
        end
      end
    end
  end

  describe "Shrine" do
    describe ".derivatives" do
      it "loads derivatives from Hash" do
        file = @attacher.upload(fakeio)

        derivatives = @shrine.derivatives({ "one" => file.data })

        assert_equal Hash[one: file], derivatives
      end

      it "loads derivatives from JSON" do
        file = @attacher.upload(fakeio)

        derivatives = @shrine.derivatives({ "one" => file.data }.to_json)

        assert_equal Hash[one: file], derivatives
      end

      it "loads nested derivatives" do
        file = @attacher.upload(fakeio)

        derivatives = @shrine.derivatives({ "one" => { "two" => [file.data] } })

        assert_equal Hash[one: { two: [file] }], derivatives
      end

      it "handles top-level arrays" do
        file = @attacher.upload(fakeio)

        derivatives = @shrine.derivatives([file.data])

        assert_equal [file], derivatives
      end

      it "handles symbol keys" do
        file = @attacher.upload(fakeio)

        derivatives = @shrine.derivatives({
          one: {
            id:       file.id,
            storage:  file.storage_key,
            metadata: file.metadata,
          }
        })

        assert_equal Hash[one: file], derivatives
      end

      it "allows UploadedFile values" do
        file = @attacher.upload(fakeio)

        derivatives = @shrine.derivatives({ one: file })

        assert_equal Hash[one: file], derivatives
      end

      it "raises exception on invalid input" do
        assert_raises(ArgumentError) { @shrine.derivatives(:invalid) }
      end
    end

    describe ".map_derivative" do
      it "iterates over simple hash" do
        derivatives = { one: fakeio }

        @shrine.map_derivative(derivatives) do |path, file|
          assert_equal [:one],            path
          assert_equal derivatives[:one], file
        end
      end

      it "iterates over simple array" do
        derivatives = [fakeio]

        @shrine.map_derivative(derivatives) do |path, file|
          assert_equal [0],            path
          assert_equal derivatives[0], file
        end
      end

      it "iterates over nested hash" do
        derivatives = { one: { two: fakeio } }

        @shrine.map_derivative(derivatives) do |path, file|
          assert_equal [:one, :two],            path
          assert_equal derivatives[:one][:two], file
        end
      end

      it "iterates over nested array" do
        derivatives = { one: [fakeio] }

        @shrine.map_derivative(derivatives) do |path, file|
          assert_equal [:one, 0],            path
          assert_equal derivatives[:one][0], file
        end
      end

      it "symbolizes hash keys" do
        derivatives = { "one" => { "two" => fakeio } }

        @shrine.map_derivative(derivatives) do |path, file|
          assert_equal [:one, :two],              path
          assert_equal derivatives["one"]["two"], file
        end
      end

      it "returns mapped collection" do
        derivatives = { "one" => [fakeio] }

        result = @shrine.map_derivative(derivatives) do |path, derivative|
          :mapped_value
        end

        assert_equal Hash[one: [:mapped_value]], result
      end

      it "returns enumerator when block is not passed" do
        derivatives = { one: fakeio }

        enumerator = @shrine.map_derivative(derivatives)

        assert_instance_of Enumerator, enumerator

        assert_equal [[[:one], derivatives[:one]]], enumerator.to_a
      end
    end
  end
end

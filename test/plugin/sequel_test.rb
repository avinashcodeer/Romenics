require "test_helper"
require "./test/support/sequel"
require "shrine/plugins/sequel"

describe Shrine::Plugins::Sequel do
  before do
    @shrine = shrine { plugin :sequel }

    user_class = Class.new(Sequel::Model)
    user_class.set_dataset(:users)

    @user     = user_class.new
    @attacher = @shrine::Attacher.from_model(@user, :avatar)
  end

  describe "Attachment" do
    describe "validate" do
      before do
        @shrine.plugin :validation
      end

      it "adds attacher errors to the record" do
        @user.class.include @shrine::Attachment.new(:avatar)

        @attacher.class.validate { errors << "error" }
        @user.avatar = fakeio
        refute @user.valid?
        assert_equal Hash[avatar: ["error"]], @user.errors.to_hash
      end

      it "is skipped if validations are disabled" do
        @shrine.plugin :sequel, validations: false
        @user.class.include @shrine::Attachment.new(:avatar)

        @attacher.class.validate { errors << "error" }
        @user.avatar = fakeio
        assert @user.valid?
      end
    end

    describe "before_save" do
      it "calls Attacher#save if attachment has changed" do
        @user.class.include @shrine::Attachment.new(:avatar)

        @user.avatar = fakeio
        @user.avatar_attacher.expects(:save).once
        @user.save
      end

      it "doesn't call Attacher#save if attachment has not changed" do
        @user.class.include @shrine::Attachment.new(:avatar)

        @user.name = "Janko"
        @user.avatar_attacher.expects(:save).never
        @user.save
      end

      it "is skipped when hooks are disabled" do
        @shrine.plugin :sequel, hooks: false
        @user.class.include @shrine::Attachment.new(:avatar)

        @user.avatar = fakeio
        @user.avatar_attacher.expects(:save).never
        @user.save
      end
    end

    describe "after_save" do
      it "finalizes attacher when attachment changes" do
        @user.class.include @shrine::Attachment.new(:avatar)

        previous_file = @attacher.upload(fakeio)
        @user.avatar_data = previous_file.to_json

        @user.avatar = fakeio
        @user.save

        assert_equal :store, @user.avatar.storage_key
        refute previous_file.exists?
      end

      it "persists changes after finalization" do
        @user.class.include @shrine::Attachment.new(:avatar)

        @user.avatar = fakeio
        @user.save
        @user.reload

        assert_equal :store, @user.avatar.storage_key
      end

      it "performs finalization after the transaction commits" do
        @user.class.include @shrine::Attachment.new(:avatar)

        @user.avatar = fakeio

        @user.db.transaction do
          @user.save
          assert_equal :cache, @user.avatar.storage_key
        end
        assert_equal :store, @user.avatar.storage_key
      end

      it "ignores validation errors" do
        @user.class.include @shrine::Attachment.new(:avatar)
        @user.instance_eval do
          def validate
            errors.add(:name, "must be present")
          end
        end

        @user.avatar = fakeio
        @user.save(validate: false)
        @user.reload

        assert_equal :store, @user.avatar.storage_key
      end

      it "is skipped when hooks are disabled" do
        @shrine.plugin :sequel, hooks: false
        @user.class.include @shrine::Attachment.new(:avatar)

        @user.avatar = fakeio
        @user.save

        assert_equal :cache, @user.avatar.storage_key
      end
    end

    describe "after_destroy" do
      it "deletes attached files" do
        @user.class.include @shrine::Attachment.new(:avatar)

        @attacher.set @attacher.upload(fakeio)
        @user.save

        @user.destroy

        refute @user.avatar.exists?
      end

      it "is skipped when hooks are disabled" do
        @shrine.plugin :sequel, hooks: false
        @user.class.include @shrine::Attachment.new(:avatar)

        @attacher.set @attacher.upload(fakeio)
        @user.save

        @user.destroy

        assert @user.avatar.exists?
      end
    end

    describe "#_refresh" do
      it "reloads the attacher on Sequel::Model#reload" do
        @user.class.include @shrine::Attachment.new(:avatar)

        @user.save
        @user.avatar_attacher # ensure attacher is memoized

        file = @attacher.upload(fakeio)
        @user.this.update(avatar_data: file.to_json)

        @user.reload

        assert_equal file, @user.avatar
      end

      it "reloads the attacher on Sequel::Model#refresh" do
        @user.class.include @shrine::Attachment.new(:avatar)

        @user.save
        @user.avatar_attacher # ensure attacher is memoized

        file = @attacher.upload(fakeio)
        @user.this.update(avatar_data: file.to_json)

        @user.refresh

        assert_equal file, @user.avatar
      end

      it "reloads the attacher on Sequel::Model#lock!" do
        @user.class.include @shrine::Attachment.new(:avatar)

        @user.save
        @user.avatar_attacher # ensure attacher is memoized

        file = @attacher.upload(fakeio)
        @user.this.update(avatar_data: file.to_json)

        @user.db.transaction { @user.lock! }

        assert_equal file, @user.avatar
      end

      it "preserves state other than the file" do
        @user.class.include @shrine::Attachment.new(:avatar)

        @user.save
        @user.avatar_attacher(cache: :other_cache)
        @user.avatar_attacher.context[:foo] = "bar"
        @user.reload

        assert_equal :other_cache, @user.avatar_attacher.cache_key
        assert_equal "bar",        @user.avatar_attacher.context[:foo]
      end

      it "doesn't initialize the attacher if it hasn't been initialized" do
        @user.class.include @shrine::Attachment.new(:avatar)

        @user.save
        @user = @user.class.with_pk!(@user.id)
        @user.reload

        refute @user.instance_variable_defined?(:@avatar_attacher)
      end

      it "returns self" do
        @user.class.include @shrine::Attachment.new(:avatar)

        @user.save

        assert_equal @user, @user.reload
      end

      it "keeps private visibility" do
        @user.class.include @shrine::Attachment.new(:avatar)

        assert_includes @user.class.private_instance_methods, :_refresh
      end
    end

    it "can still be included into non-Sequel classes" do
      model_class = model_class(:avatar_data)
      model_class.include @shrine::Attachment.new(:avatar)

      %i[validate after_save after_destroy _refresh].each do |method_name|
        refute_includes model_class.instance_methods, method_name
      end
    end
  end

  describe "Attacher" do
    describe "JSON columns" do
      after do
        @user.class.db_schema[:avatar_data][:type] = :string # revert schema change
      end

      it "handles json type" do
        @user.class.db_schema[:avatar_data][:type] = :json

        @attacher.load_model(@user, :avatar)
        @attacher.attach(fakeio)

        assert_equal @attacher.file.data, @user.avatar_data

        @attacher.reload

        assert_equal @attacher.file.data, @user.avatar_data
      end

      it "handles jsonb type" do
        @user.class.db_schema[:avatar_data][:type] = :jsonb

        @attacher.load_model(@user, :avatar)
        @attacher.attach(fakeio)

        assert_equal @attacher.file.data, @user.avatar_data

        @attacher.reload

        assert_equal @attacher.file.data, @user.avatar_data
      end
    end

    describe "#atomic_promote" do
      it "promotes cached file to permanent storage" do
        @attacher.attach_cached(fakeio)
        @user.save

        @attacher.atomic_promote

        assert @attacher.stored?
        @attacher.reload
        assert @attacher.stored?
      end

      it "updates the record with promoted file" do
        @attacher.attach_cached(fakeio)
        @user.save

        @attacher.atomic_promote

        @user.reload
        @attacher.reload
        assert @attacher.stored?
      end

      it "returns the promoted file" do
        @attacher.attach_cached(fakeio)
        @user.save

        file = @attacher.atomic_promote

        assert_equal @attacher.file, file
      end

      it "accepts promote options" do
        @attacher.attach_cached(fakeio)
        @user.save

        @attacher.atomic_promote(location: "foo")

        assert_equal "foo", @attacher.file.id
      end

      it "persists any other attribute changes" do
        @attacher.attach_cached(fakeio)
        @user.save

        @user.name = "Janko"
        @attacher.atomic_promote

        assert_equal "Janko", @user.name
        assert_equal "Janko", @user.reload.name
      end

      it "executes the given block before persisting" do
        @attacher.attach_cached(fakeio)
        @user.save

        @attacher.atomic_promote { @user.name = "Janko" }

        assert_equal "Janko", @user.name
        assert_equal "Janko", @user.reload.name
      end

      it "fails on attachment change" do
        @attacher.attach_cached(fakeio)
        @user.save

        @user.this.update(avatar_data: nil)

        @user.name = "Janko"
        assert_raises(Shrine::AttachmentChanged) do
          @attacher.atomic_promote { @block_called = true }
        end

        @user.reload
        @attacher.reload

        assert_nil @attacher.file
        assert_nil @user.name
        refute @block_called
      end

      it "respects column serializer" do
        @attacher = @shrine::Attacher.from_model(@user, :avatar, column_serializer: RubySerializer)
        @attacher.attach_cached(fakeio)
        @user.save

        @attacher.atomic_promote

        @user.reload
        @attacher.reload
        assert @attacher.stored?
      end

      it "accepts custom reload strategy" do
        cached_file = @attacher.attach_cached(fakeio)
        @user.save

        @user.this.update(avatar_data: nil) # this change will not be detected

        @user.name = "Janko"
        @attacher.atomic_promote(reload: -> (&block) {
          block.call @user.class.new(avatar_data: cached_file.to_json)
        })

        @user.reload
        @attacher.reload
        assert @attacher.stored?
        assert_equal "Janko", @user.name
      end

      it "allows disabling reloading" do
        cached_file = @attacher.attach_cached(fakeio)
        @user.save

        @user.this.update(avatar_data: nil) # this change will not be detected

        @user.name = "Janko"
        @attacher.atomic_promote(reload: false)

        @user.reload
        @attacher.reload
        assert @attacher.stored?
        assert_equal "Janko", @user.name
      end

      it "accepts custom persist strategy" do
        @attacher.attach_cached(fakeio)
        @user.save

        @attacher.atomic_promote(persist: -> {
          @user.name = "Janko"
          @user.save
        })

        @user.reload
        @attacher.reload
        assert @attacher.stored?
        assert_equal "Janko", @user.name
      end

      it "allows disabling persistence" do
        @attacher.attach_cached(fakeio)
        @user.save

        @user.name = "Janko"
        @attacher.atomic_promote(persist: false)

        assert @attacher.stored?
        assert_equal "Janko", @user.name

        @user.reload
        @attacher.reload
        assert @attacher.cached?
        assert_nil @user.name
      end

      it "raises NotImplementedError for non-Sequel attacher" do
        @attacher = @shrine::Attacher.new

        assert_raises NotImplementedError do
          @attacher.atomic_promote
        end
      end
    end

    describe "#atomic_persist" do
      it "persists the record" do
        file = @attacher.attach(fakeio)
        @user.save

        @user.name = "Janko"
        @attacher.atomic_persist

        assert_equal "Janko", @user.name
        assert_equal "Janko", @user.reload.name
        assert_equal file,    @attacher.file
      end

      it "executes the given block before persisting" do
        @attacher.attach(fakeio)
        @user.save

        @attacher.atomic_persist { @user.name = "Janko" }

        assert_equal "Janko", @user.name
        assert_equal "Janko", @user.reload.name
      end

      it "fails on attachment change" do
        @attacher.attach(fakeio)
        @user.save

        @user.this.update(avatar_data: nil)

        @user.name = "Janko"
        assert_raises(Shrine::AttachmentChanged) do
          @attacher.atomic_persist { @block_called = true }
        end

        @user.reload
        @attacher.reload

        assert_nil @attacher.file
        assert_nil @user.name
        refute @block_called
      end

      it "respects column serializer" do
        @attacher = @shrine::Attacher.from_model(@user, :avatar, column_serializer: RubySerializer)
        @attacher.attach(fakeio)
        @user.save

        @user.name = "Janko"
        @attacher.atomic_persist

        @user.reload
        @attacher.reload
        assert_equal "Janko", @user.name
      end

      it "accepts custom reload strategy" do
        @attacher.attach(fakeio)
        @user.save

        @user.this.update(avatar_data: nil) # this change will not be detected

        @user.name = "Name"
        @attacher.atomic_persist(reload: -> (&block) { block.call(@user) })

        assert_equal "Name", @user.reload.name
      end

      it "allows disabling reloading" do
        @attacher.attach(fakeio)
        @user.save

        @user.this.update(avatar_data: nil) # this change will not be detected

        @user.name = "Name"
        @attacher.atomic_persist(reload: false)

        assert_equal "Name", @user.reload.name
      end

      it "accepts custom persist strategy" do
        @attacher.attach(fakeio)
        @user.save

        @attacher.atomic_persist(persist: -> {
          @user.name = "Janko"
          @user.save
        })

        assert_equal "Janko", @user.name
        assert_equal "Janko", @user.reload.name
      end

      it "allows disabling persistence" do
        @attacher.attach(fakeio)
        @user.save

        @user.name = "Janko"
        @attacher.atomic_persist(persist: false)

        assert_equal "Janko", @user.name
        assert_nil @user.reload.name
      end

      it "accepts current file" do
        @user.save

        file = @attacher.upload(fakeio)
        @user.this.update(avatar_data: file.to_json)

        assert_raises(Shrine::AttachmentChanged) do
          @attacher.atomic_persist
        end

        @user.name = "Janko"
        @attacher.atomic_persist(file)

        assert_equal "Janko", @user.name
        assert_equal "Janko", @user.reload.name
      end

      it "raises NotImplementedError for non-Sequel attacher" do
        @attacher = @shrine::Attacher.new

        assert_raises NotImplementedError do
          @attacher.atomic_persist
        end
      end
    end

    describe "#persist" do
      it "persists the record" do
        file = @attacher.upload(fakeio)
        @user.avatar_data = file.to_json

        @attacher.persist

        assert_equal file.to_json, @user.reload.avatar_data
      end

      it "persists only changes" do
        @user.save
        @user.this.update(name: "Janko")

        file = @attacher.upload(fakeio)
        @user.avatar_data = file.to_json

        @attacher.persist

        assert_equal "Janko", @user.reload.name
      end

      it "skips validations" do
        @user.instance_eval do
          def validate
            errors.add(:name, "must be present")
          end
        end

        @user.name = "Janko"
        @user.save(validate: false)

        @user.name = nil
        @attacher.persist

        assert_nil @user.reload.name
      end

      it "triggers hooks when persisting" do
        @user.save

        after_save_called = false
        @user.class.send(:define_method, :after_save) { after_save_called = true }

        @user.name = "Janko"
        @attacher.persist

        assert after_save_called
      end

      it "raises NotImplementedError for non-Sequel attacher" do
        @attacher = @shrine::Attacher.new

        assert_raises NotImplementedError do
          @attacher.persist
        end
      end
    end
  end
end

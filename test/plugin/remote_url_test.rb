require "test_helper"
require "shrine/plugins/remote_url"
require "dry-monitor"

describe Shrine::Plugins::RemoteUrl do
  before do
    Down.stubs(:download).with(good_url, max_size: nil).returns(StringIO.new("file"))
    Down.stubs(:download).with(bad_url, max_size: nil).raises(Down::Error.new("file not found"))

    @attacher = attacher { plugin :remote_url, max_size: nil }
    @shrine = @attacher.shrine_class
    @user = @attacher.record
  end

  it "enables attaching a file via a remote url" do
    @user.avatar_remote_url = good_url
    assert @user.avatar
    assert_equal "file", @user.avatar.read
  end

  it "keeps the remote url value if downloading doesn't succeed" do
    @user.avatar_remote_url = good_url
    assert_nil @user.avatar_remote_url
    @user.avatar_remote_url = bad_url
    assert_equal bad_url, @user.avatar_remote_url
  end

  it "aborts assignment on download errors" do
    @user.avatar = fakeio
    @user.avatar_remote_url = bad_url
    assert @user.avatar
  end

  it "ignores empty urls" do
    @user.avatar = fakeio
    @user.avatar_remote_url = ""
    assert @user.avatar
    assert_nil @user.avatar_remote_url
  end

  it "ignores nil values" do
    @user.avatar = fakeio
    @user.avatar_remote_url = nil
    assert @user.avatar
    assert_nil @user.avatar_remote_url
  end

  it "accepts :max_size" do
    @shrine.plugin :remote_url, max_size: 1
    Down.stubs(:download).with(good_url, max_size: 1).raises(Down::TooLarge.new("file is too large"))
    @user.avatar_remote_url = good_url
    refute @user.avatar
  end

  it "accepts custom downloader" do
    @shrine.plugin :remote_url, downloader: ->(url, **){fakeio(url)}
    @user.avatar_remote_url = "foo"
    assert_equal "foo", @user.avatar.read
  end

  it "accepts additional downloader options" do
    @shrine.plugin :remote_url, downloader: ->(url, max_size:, **options){fakeio(options.to_s)}
    @attacher.assign_remote_url(good_url, downloader: { foo: "bar" })
    assert_equal "{:foo=>\"bar\"}", @user.avatar.read
  end

  it "accepts additional uploader options" do
    @attacher.assign_remote_url(good_url, location: "foo")
    assert_equal "foo", @attacher.get.id
  end

  it "transforms download errors into validation errors" do
    @user.avatar_remote_url = good_url
    assert_empty @user.avatar_attacher.errors

    @user.avatar_remote_url = bad_url
    assert_equal ["download failed: file not found"], @user.avatar_attacher.errors

    @shrine.plugin :remote_url, max_size: 1
    Down.stubs(:download).with(good_url, max_size: 1).raises(Down::TooLarge.new("file is too large"))
    @user.avatar_remote_url = good_url
    assert_equal ["download failed: file is too large"], @user.avatar_attacher.errors
  end

  it "accepts custom error message" do
    @shrine.plugin :remote_url, error_message: "download failed"
    @user.avatar_remote_url = bad_url
    assert_equal ["download failed"], @user.avatar_attacher.errors

    @shrine.plugin :remote_url, error_message: ->(url){"download failed: #{url}"}
    @user.avatar_remote_url = bad_url
    assert_equal ["download failed: #{bad_url}"], @user.avatar_attacher.errors

    @shrine.plugin :remote_url, error_message: ->(url, error){error.message}
    @user.avatar_remote_url = bad_url
    assert_equal ["file not found"], @user.avatar_attacher.errors
  end

  it "has a default error message when downloader returns nil" do
    @shrine.plugin :remote_url, downloader: ->(url, **){nil}
    @user.avatar_remote_url = good_url
    assert_equal ["download failed"], @user.avatar_attacher.errors
  end

  it "clears any existing errors" do
    @user.avatar_attacher.errors << "foo"
    @user.avatar_remote_url = bad_url
    refute_includes @user.avatar_attacher.errors, "foo"
  end

  describe "with instrumentation" do
    before do
      @shrine.plugin :instrumentation, notifications: Dry::Monitor::Notifications.new(:test)
    end

    it "logs remote URL download" do
      @shrine.plugin :remote_url

      assert_logged /^Remote URL \(\d+ms\) – \{.+\}$/ do
        @shrine.remote_url(good_url)
      end
    end

    it "sends a remote URL download event" do
      @shrine.plugin :remote_url

      @shrine.subscribe(:remote_url) { |event| @event = event }
      @shrine.remote_url(good_url)

      refute_nil @event
      assert_equal :remote_url,         @event.name
      assert_equal good_url,            @event[:remote_url]
      assert_equal Hash[max_size: nil], @event[:download_options]
      assert_equal @shrine,             @event[:uploader]
      assert_kind_of Integer,           @event.duration
    end

    it "allows swapping log subscriber" do
      @shrine.plugin :remote_url, log_subscriber: -> (event) { @event = event }

      refute_logged /^Remote URL/ do
        @shrine.remote_url(good_url)
      end

      refute_nil @event
    end

    it "allows disabling log subscriber" do
      @shrine.plugin :remote_url, log_subscriber: nil

      refute_logged /^Remote URL/ do
        @shrine.remote_url(good_url)
      end
    end
  end

  def good_url
    "http://example.com/good.jpg"
  end

  def bad_url
    "http://example.com/bad.jpg"
  end
end

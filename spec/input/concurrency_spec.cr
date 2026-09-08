# spec/input/concurrency_spec.cr
require "../spec_helper"

private def isolated(name : String, &block : ->) : Fiber::ExecutionContext::Isolated
  Fiber::ExecutionContext::Isolated.new(name, &block)
end

describe "Term::Input::Events under a middleman" do
  it "serialises producers running in separate isolated contexts" do
    count  = Atomic(Int32).new(0)
    mutex  = Mutex.new
    filter = Term::Mux::InputFilter.new
    events = Term::Input::Events.new(filter)
    events.on_key { count.add(1) }

    group = WaitGroup.new(4)

    contexts = (0...4).map do |n|
      isolated("producer-#{n}") do
        500.times { mutex.synchronize { filter.feed("\e[A".to_slice) } }
        group.done
      end
    end

    group.wait
    contexts.each(&.wait)

    actual   = count.get
    expected = 2000
    report("4 concurrent producers (500 per context)", expected, actual)
    actual.should eq expected
  end

  it "keeps sequence assembly intact across chunk splits" do
    seen   = Atomic(Int32).new(0)
    mutex  = Mutex.new
    filter = Term::Mux::InputFilter.new
    events = Term::Input::Events.new(filter)
    events.on_mouse { seen.add(1) }

    group = WaitGroup.new(1)

    writer = isolated("writer") do
      1000.times do
        mutex.synchronize do
          filter.feed("\e[<0;".to_slice)
          filter.feed("10;20M".to_slice)
        end
      end
      group.done
    end

    group.wait
    writer.wait

    actual   = seen.get
    expected = 1000
    report("split sequence writing from an isolated context", expected, actual)
    actual.should eq expected
  end

  it "assembles a paste fed from an isolated context" do
    result = Channel(Array(String)).new
    pastes = [] of String
    filter = Term::Mux::InputFilter.new
    events = Term::Input::Events.new(filter)
    events.on_paste { |content| pastes << content }

    expected_content = "payload" * 500

    ctx = isolated("paster") do
      filter.feed("\e[200~".to_slice)
      500.times { filter.feed("payload".to_slice) }
      filter.feed("\e[201~".to_slice)
      result.send(pastes)
    end

    actual = result.receive
    report("500-part paste loop from isolated context", "[very long string]", "pastes size: #{actual.size}")

    actual.should eq [expected_content]
    ctx.wait
  end
end

expect  = require 'expect.js'
_       = require 'underscore'
async   = require 'async'
config  = require '../../../test/test_config'
common  = require '../../../test/common'
api_methods = require("../../../lib/api_methods")(config)
www_schema = require('../../../lib/schema').load(config)
clock_schema = require("../lib/schema").load(config)
clock = require("../lib/clock")(config)

timeoutSet = (a, b) -> setTimeout(b, a)

describe "clock", ->
  before (done) ->
    common.startUp (server) =>
      @server = server
      async.series [
        (done) =>
          # get all users and groups for convenience
          common.getAllUsersAndGroups (err, maps) =>
            @all_users = maps.users
            @all_groups = maps.groups
            done()
        (done) =>
          # Establish a session.
          @session = {}
          common.stubBrowserID({email: "one@mockmyid.com"})
          api_methods.authenticate(@session, "mock assertion", done)
        (done) =>
          # Build a clock to use.
          new clock_schema.Clock({
            name: "Meeting"
            sharing: { group_id: @all_groups["two-members"].id }
            present: [{
              name:    @all_users["one@mockmyid.com"].name
              user_id: @all_users["one@mockmyid.com"]._id
            }, {
              name:    @all_users["two@mockmyid.com"].name
              user_id: @all_users["two@mockmyid.com"]._id
            }]
          }).save (err, clock) =>
            @clock = clock
            done(err)
      ], done

  after (done) ->
    common.shutDown(@server, done)

  it "has correct url [lib]", (done) ->
    expect(@clock.url).to.be("/c/#{@clock.id}/")
    expect(@clock.absolute_url).to.be("http://localhost:#{config.port}/clock/c/#{@clock.id}/")
    done()

  it "posts events [lib]", (done) ->
    clock.post_event @session, @clock, {type: "create"}, 0, (err, event) =>
        expect(err).to.be(null)
        expect(event.application).to.be("clock")
        expect(event.type).to.be("create")
        expect(event.entity).to.be(@clock.id)
        www_schema.Event.findOne {entity: @clock.id}, (err, doc) =>
          expect(err).to.be(null)
          expect(doc.id).to.be(event.id)
          expect(doc.entity).to.be(event.entity)
          expect("#{doc.group}").to.be(@clock.sharing.group_id)
          expect(doc.url).to.be(@clock.url)
          done()

  it "fetches a clock [lib]", (done) ->
    clock.fetch_clock @clock.id, @session, (err, doc) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      expect(doc.id).to.eql(@clock.id)
      done()

  it "controls permissions when fetching a clock [lib]", (done) ->
    clock.fetch_clock @clock.id, {}, (err, doc) =>
      expect(err).to.eql("Permission denied")
      done()

  it "fetch clock list [lib]", (done) ->
    clock.fetch_clock_list @session, (err, docs) =>
      expect(docs.public).to.eql([])
      expect(docs.group.length).to.be(1)
      expect(docs.group[0].id).to.eql(@clock.id)
      done()

  it "controls permissions when fetching clock list [lib]", (done) ->
    clock.fetch_clock_list {}, (err, docs) =>
      expect(docs.public).to.eql([])
      expect(docs.group).to.eql([])
      done()

  it "saves changes to a clock [lib]", (done) ->
    changes = {name: "Duh Best", _id: @clock.id}
    clock.save_clock @session, {model: changes}, (err, doc, event, si) =>
      expect(err).to.be(null)
      expect(doc.id).to.be(@clock.id)
      expect(doc.name).to.be("Duh Best")
      expect(event).to.not.be(null)
      expect(event.type).to.be("update")
      expect(event.entity).to.eql(doc.id)
      expect(event.url).to.be(doc.url)

      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: "Clock"
        aspect: "name"
        collective: "changed clocks"
        verbed: "changed"
        manner: "from \"Meeting\" to \"Duh Best\""
      })

      expect(si).to.not.be(null)
      expect(si.url).to.be(doc.url)
      done()

  it "saves sharing change to a clock [lib]", (done) ->
    group_id = @all_groups["two-members"].id
    changes = {sharing: {group_id: group_id}, _id: @clock.id}
    clock.save_clock @session, {model: changes}, (err, doc, event, si) =>
      expect(err).to.be(null)
      expect(doc.sharing.group_id).to.eql(group_id)
      expect(event).to.not.be(null)
      expect(si).to.not.be(null)
      expect(si.sharing.group_id).to.eql(group_id)

      expect(event.type).to.be("update")
      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: "Duh Best"
        aspect: "sharing"
        collective: "changed clocks"
        verbed: "changed"
        manner: ""
      })

      clock_schema.Clock.findOne {_id: @clock.id}, (err, doc) =>
        expect(err).to.be(null)
        expect(doc).to.not.be(null)
        expect(doc.sharing.group_id).to.eql(group_id)
        done()

  _set_time_with = null

  it "sets time [lib]", (done) ->
    _set_time_with = (start_date, stop_date, cb) =>
      clock.set_time @session, {
        _id: @clock.id
        category: "Male"
        index: 0
        time: {start: start_date, stop: stop_date}
        now: new Date()
      }, cb

    @start = new Date()

    _set_time_with @start, null, (err, doc) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      cat = _.find(doc.categories, (c) -> c.name == "Male")
      expect(cat.times.length).to.be(1)
      expect(cat.times[0].start).to.eql(@start)
      expect(cat.times[0].stop).to.be(null)
      done()

  it "refuses future end times [lib]", (done) ->
    _set_time_with @start, new Date(new Date().getTime() + 1000), (err, doc) ->
      expect(err).to.be("Bad time")
      done()

  it "refuses end times before prior times [lib]", (done) ->
    _set_time_with @start, new Date(@start.getTime() - 1000), (err, doc) ->
      expect(err).to.be("Bad time")
      done()

  it "allows cojent end times [lib]", (done) ->
    stop = new Date()
    _set_time_with @start, stop, (err, doc) =>
      expect(err).to.be(null)
      cat = _.find(doc.categories, (c) -> c.name == "Male")
      expect(cat.times[0].start).to.eql(@start)
      expect(cat.times[0].stop).to.eql(stop)
      done()

  it "creates new clocks [lib]", (done) ->
    clock.save_clock @session, {model: {
        name: "Good times"
        about: "For sure"
    }}, (err, clock, event, si) ->
      expect(err).to.be(null)
      expect(clock).to.not.be(null)
      expect(event).to.not.be(null)
      expect(si).to.not.be(null)

      expect(clock.name).to.be("Good times")
      expect(event.type).to.be("create")
      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: "Progressive Clock"
        aspect: "\"Good times\""
        collective: "new clocks"
        verbed: "created"
        manner: ""
      })
      done()

  it "updates multiple params at once [lib]", (done) ->
    json = @clock.toJSON()
    cats = (_.extend({}, cat) for cat in json.categories)
    cats = cats.slice(0, 3)
    cats[0].name = "One"
    cats[1].name = "Two"
    cats[2].name = "Three"
    clock.save_clock @session, {model: {
      _id: @clock._id
      name: "New name"
      about: "New about that is rather long, longer than 30 chars I should think"
      sharing: {group_id: @all_groups["not-one-members"]._id}
      categories: cats
    }}, (err, clock, event, si) ->
      expect(err).to.be(null)
      expect(clock).to.not.be(null)
      expect(event).to.not.be(null)
      expect(si).to.not.be(null)

      expect(event.type).to.be("update")
      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(4)
      expect(terms[0]).to.eql({
        entity: "Clock"
        aspect: "name"
        collective: "changed clocks"
        verbed: "changed"
        manner: "from \"Duh Best\" to \"New name\""
      })
      expect(terms[1]).to.eql({
        entity: "New name"
        aspect: "about text"
        collective: "changed clocks"
        verbed: "changed"
        manner: "to \"New about that is rather lo...\""
      })
      expect(terms[2]).to.eql({
        entity: "New name"
        aspect: "categories"
        collective: "changed clocks"
        verbed: "changed"
        manner: "to One, Two, Three"
      })
      expect(terms[3]).to.eql({
        entity: "New name"
        aspect: "sharing"
        collective: "changed clocks"
        verbed: "changed"
        manner: ""
      })
      done()


  it "about link [live]", (done) ->
    this.timeout(20000)
    browser = common.fetchBrowser()
    browser.visit "#{config.apps.clock.url}/", (e, browser, status) ->
      expect(status).to.be(200)
      browser.clickLink(".about")
      # Check the about link.
      expect(browser.location.pathname).to.be("/clock/about/")
      expect(browser.text("h3")).to.be("About the Progressive Clock")
      done()
  
  it "adds a clock [live]", (done) ->
    this.timeout(20000)
    browser = common.fetchBrowser()
    browser.visit "#{config.apps.clock.url}/", (e, browser, status) ->
      browser.clickLink(".add-new-clock")
      expect(browser.location.pathname).to.be("/clock/add/")
      expect(browser.text("h1")).to.be("Add new Clock")
      browser.fill("#id_name", "Fun")
      expect(
        browser.evaluate('$("#category_controls [name=item-0]").val()')
      ).to.be("Male")
      browser.query("input[type=submit]").click()
      common.await =>
        if browser.location.pathname.substring(0, "/clock/c/".length) == "/clock/c/"
          done()
          return true

  it "connects to detail page [live]", (done) ->
    this.timeout(20000)
    browser = common.fetchBrowser()
    browser.visit @clock.absolute_url, (e, browser, status) ->
      expect(status).to.be(200)
      done()

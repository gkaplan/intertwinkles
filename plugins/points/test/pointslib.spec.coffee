expect      = require 'expect.js'
_           = require 'underscore'
async       = require 'async'
config      = require '../../../test/test_config'
common      = require '../../../test/common'
api_methods = require("../../../lib/api_methods")(config)
www_schema  = require('../../../lib/schema').load(config)
ps_schema   = require("../lib/schema").load(config)
pointslib   = require("../lib/pointslib")(config)

timeoutSet = (a, b) -> setTimeout(b, a)

describe "pointslib", ->
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
          api_methods.authenticate @session, "mock assertion", =>
            @session.anon_id = "anon_id_1"
            done()
        (done) =>
          @session2 = {}
          common.stubBrowserID({email: "two@mockmyid.com"})
          api_methods.authenticate @session2, "mock assertion", =>
            @session2.anon_id = "anon_id_2"
            done()

      ], done

  after (done) ->
    common.shutDown(@server, done)

  it "creates a pointset", (done) ->
    pointslib.save_pointset @session, {
      model: {
        name: "My Ten Point"
        slug: "my-ten-point"
        sharing: {group_id: @all_groups['two-members'].id}
      }
    }, (err, doc, event, si) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      expect(event).to.not.be(null)
      expect(si).to.not.be(null)

      expect(doc.name).to.be("My Ten Point")
      expect(doc.slug).to.be("my-ten-point")
      expect(p for p in doc.drafts).to.eql([])
      expect(p for p in doc.points).to.eql([])
      expect(doc.sharing.group_id).to.eql(@all_groups['two-members'].id)
      expect(doc.url).to.eql("/u/my-ten-point/")
      expect(doc.absolute_url).to.eql("http://localhost:#{config.port}/points/u/my-ten-point/")

      expect(event.application).to.be("points")
      expect(event.url).to.be(doc.url)
      expect(event.absolute_url).to.be(doc.absolute_url)
      expect(event.type).to.be("create")
      expect(event.user.toString()).to.be(@all_users['one@mockmyid.com'].id)
      expect(event.via_user).to.be(undefined)
      expect(event.group.toString()).to.eql(@all_groups['two-members'].id)

      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: "Points of Unity"
        aspect: "\"My Ten Point\""
        collective: "created points of unity"
        verbed: "created"
        manner: ""
      })

      expect(si.application).to.be("points")
      expect(si.entity).to.eql(doc.id)
      expect(si.url).to.eql(doc.url)
      expect(si.absolute_url).to.eql(doc.absolute_url)
      expect(si.type).to.be("pointset")
      expect(si.summary).to.be(doc.name)
      expect(si.title).to.be(doc.name)
      expect(si.sharing.group_id).to.eql(@all_groups['two-members'].id)
      expect(si.sharing.extra_editors.length).to.be(0)
      expect(si.sharing.extra_viewers.length).to.be(0)
      expect(si.sharing.advertise).to.be(undefined)
      expect(si.sharing.public_edit_until).to.be(undefined)
      expect(si.sharing.public_view_until).to.be(undefined)
      expect(si.text).to.be("My Ten Point")

      @pointset = doc
      done()

  it "updates a pointset", (done) ->
    pointslib.save_pointset @session, {
      model: {
        _id: @pointset.id
        name: "Your Ten Point"
      }
    }, (err, doc, event, si) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      expect(event).to.not.be(null)
      expect(si).to.not.be(null)

      expect(doc.name).to.be("Your Ten Point")
      expect(doc.slug).to.be("my-ten-point")
      expect(event.type).to.be("update")
      expect(event.user.toString()).to.be(@session.auth.user_id)
      expect(event.via_user).to.be(undefined)
      expect(si.text).to.be("Your Ten Point")

      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: "Points of Unity"
        aspect: "name"
        collective: "changed points of unity"
        verbed: "changed"
        manner: "from \"My Ten Point\" to \"Your Ten Point\""
      })

      @pointset = doc

      ps_schema.PointSet.find {}, (err, docs) ->
        expect(err).to.be(null)
        expect(docs.length).to.be(1)
        www_schema.Event.find {application: "points"}, (err, docs) ->
          expect(err).to.be(null)
          expect(docs.length).to.be(2)
          www_schema.SearchIndex.find {application: "points"}, (err, docs) ->
            expect(err).to.be(null)
            expect(docs.length).to.be(1)
            done()

  it "adds a point", (done) ->
    pointslib.revise_point @session, {
      _id: @pointset.id,
      text: "Be excellent to each other."
      user_id: @session.auth.user_id
      name: @session.users[@session.auth.user_id].name
    }, (err, doc, point, event, si) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      expect(event).to.not.be(null)

      expect(doc.drafts.length).to.be(1)
      p = doc.drafts[0]
      expect(p.revisions.length).to.be(1)
      expect(p.revisions[0].text).to.be("Be excellent to each other.")
      expect(p.revisions[0].supporters.length).to.be(1)
      expect(p.revisions[0].supporters[0].user_id.toString()).to.eql(
        @all_users['one@mockmyid.com'].id)
  
      expect(event.type).to.be("append")
      expect(event.user.toString()).to.be(@session.auth.user_id)
      expect(event.via_user).to.be(undefined)
      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: "Your Ten Point"
        aspect: "point"
        collective: "added points"
        verbed: "added"
        manner: "Be excellent to each other."
      })

      @pointset = doc
      done()

  it "revises a point", (done) ->
    pointslib.revise_point @session2, {
      _id: @pointset.id
      point_id: @pointset.drafts[0]._id.toString()
      text: "Party on, dude."
      user_id: @session2.auth.user_id
      name: @session2.users[@session2.auth.user_id]
    }, (err, doc, point, event, si) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      expect(event).to.not.be(null)
      expect(doc.drafts.length).to.be(1)
      p = doc.drafts[0]
      expect(p.revisions.length).to.be(2)
      expect(p.revisions[0].text).to.be("Party on, dude.")
      expect(p.revisions[1].text).to.be("Be excellent to each other.")
      expect(p.revisions[0].supporters.length).to.be(1)
      expect(p.revisions[0].supporters[0].user_id.toString()).to.eql(
        @all_users['two@mockmyid.com'].id
      )

      expect(event.type).to.be("append")
      expect(event.user.toString()).to.be(@session2.auth.user_id)
      expect(event.via_user).to.be(undefined)
      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: "Your Ten Point"
        aspect: "point"
        collective: "edited points"
        verbed: "edited"
        manner: "Party on, dude."
      })

      done()

  it "supports a point", (done) ->
    pointslib.change_support @session, {
      _id: @pointset.id
      point_id: @pointset.drafts[0]._id.toString()
      user_id: @session.auth.user_id
      vote: true
    }, (err, doc, point, event) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      expect(event).to.not.be(null)

      p = doc.drafts[0]
      expect(p.revisions[0].supporters.length).to.be(2)
      supporter_ids = (
        s.user_id.toString() for s in p.revisions[0].supporters
      )
      expect(supporter_ids).to.eql([
        @session2.auth.user_id.toString(), @session.auth.user_id.toString()
      ])
      expect(event.type).to.be("vote")
      expect(event.user.toString()).to.be(@session.auth.user_id)
      expect(event.via_user).to.be(undefined)

      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: "Your Ten Point"
        aspect: "vote"
        collective: "votes"
        verbed: "added"
        manner: "Party on, dude."
      })

      done()

  it "unsupports a point", (done) ->
    # This will be @session unsupporting on behalf of @session2
    pointslib.change_support @session, {
      _id: @pointset.id
      user_id: @session2.auth.user_id
      point_id: @pointset.drafts[0]._id.toString()
      vote: false
    }, (err, doc, point, event) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      expect(event).to.not.be(null)
      expect(point._id).to.eql(doc.drafts[0]._id)
      p = doc.drafts[0]
      expect(p.revisions[0].supporters.length).to.be(1)
      expect(p.revisions[0].supporters[0].user_id.toString()).to.be(
        @session.auth.user_id)

      expect(event.user.toString()).to.be(@session2.auth.user_id)
      expect(event.via_user.toString()).to.be(@session.auth.user_id)

      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: "Your Ten Point"
        aspect: "vote"
        collective: "votes"
        verbed: "removed"
        manner: "Party on, dude."
      })

      done()

  it "supports a point anonymously", (done) ->
    pointslib.save_pointset @session, {
      model: {
        _id: @pointset.id
        sharing: {
          public_edit_until: new Date(new Date().getTime() + 100000)
          advertise: true
        }
      }
    }, (err, doc, event, si) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      expect(event).to.not.be(null)
      expect(si).to.not.be(null)
      expect(doc.sharing.public_edit_until > new Date()).to.be(true)

      pointslib.change_support {}, {
        _id: @pointset.id
        user_id: null
        name: "George"
        point_id: @pointset.drafts[0]._id.toString()
        vote: true
      }, (err, doc, point, event) =>
        expect(err).to.be(null)
        expect(doc).to.not.be(null)
        expect(event).to.not.be(null)
        expect(point._id).to.eql(doc.drafts[0]._id)
        expect(doc.drafts[0].revisions[0].supporters.length).to.be(2)
        expect(doc.drafts[0].revisions[0].supporters[1].name).to.be("George")
        expect(doc.drafts[0].revisions[0].supporters[1].user_id).to.be(null)
        expect(event.data.user.name).to.be("George")
        expect(event.user).to.be(undefined)
        expect(event.via_user).to.be(undefined)

        pointslib.change_support {}, {
          _id: @pointset.id
          user_id: null
          name: "George"
          point_id: @pointset.drafts[0]._id.toString()
          vote: false
        }, (err, doc, point, event) =>
          expect(err).to.be(null)
          expect(doc).to.not.be(null)
          expect(event).to.not.be(null)
          expect(event.user).to.be(undefined)
          expect(event.via_user).to.be(undefined)

          expect(point._id).to.eql(doc.drafts[0]._id)
          expect(doc.drafts[0].revisions[0].supporters.length).to.be(1)
          expect(doc.drafts[0].revisions[0].supporters[0].name).to.be(undefined)
          expect(
            doc.drafts[0].revisions[0].supporters[0].user_id.toString()
          ).to.be(
            @session.auth.user_id
          )
          expect(event.data.user.name).to.be("George")
          done()

  it "fetches a pointset", (done) ->
    pointslib.fetch_pointset "my-ten-point", {}, (err, doc, event) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      expect(doc.id).to.be(@pointset.id)
      expect(event).to.not.be(null)
      expect(event.type).to.be("visit")
      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: "Your Ten Point"
        aspect: ""
        collective: "visits"
        verbed: "visited"
        manner: ""
      })
      done()

  it "fetches a pointset list", (done) ->
    pointslib.fetch_pointset_list @session, (err, docs) =>
      expect(err).to.be(null)
      expect(docs.group.length).to.be(1)
      expect(docs.group[0].id).to.be(@pointset.id)
      expect(docs.public.length).to.be(1)
      expect(docs.public[0].id).to.be(@pointset.id)

      pointslib.fetch_pointset_list {}, (err, docs) =>
        expect(err).to.be(null)
        expect(docs.group.length).to.be(0)
        expect(docs.public.length).to.be(1)
        expect(docs.public[0].id).to.be(@pointset.id)
        done()

  it "indicates editing", (done) ->
    pointslib.set_editing @session, {
      _id: @pointset._id
      point_id: @pointset.drafts[0]._id
      editing: true
    }, (err, doc) =>
      expect(doc.drafts[0].editing.length).to.be(1)
      expect(doc.drafts[0].editing[0]).to.be(@session.anon_id)
      done()

  it "stops indicating editing", (done) ->
    pointslib.set_editing @session, {
      _id: @pointset._id
      point_id: @pointset.drafts[0]._id
      editing: false
    }, (err, doc) =>
      expect(doc.drafts[0].editing.length).to.be(0)
      done()

  it "adds more points", (done) ->
    pointslib.revise_point @session, {
      _id: @pointset.id
      text: "Whoa."
      user_id: undefined
      name: "Anonymouse"
    }, (err, doc, point, event, si) =>
      expect(err).to.be(null)
      expect(doc.drafts.length).to.be(2)
      pointslib.revise_point @session, {
        _id: @pointset.id
        text: "G'day, mate."
        user_id: undefined
        name: "Aussie"
      }, (err, doc, point, event, si) =>
        expect(err).to.be(null)
        expect(doc.drafts.length).to.be(3)
        @pointset = doc
        done()

  it "approves points", (done) ->
    pointslib.set_approved @session, {
      _id: @pointset.id
      point_id: @pointset.drafts[0]._id
      approved: true
    }, (err, doc, point, event) =>
      expect(err).to.be(null)
      expect(doc).to.not.be(null)
      expect(point).to.not.be(null)
      expect(event).to.not.be(null)

      expect(doc.points.length).to.be(1)
      expect(doc.drafts.length).to.be(2)
      expect(doc.points[0]._id.toString()).to.be(
        @pointset.drafts[0]._id.toString()
      )
      expect(doc.is_approved(point)).to.be(true)
      expect(_.find(doc.drafts, (p) =>
        p._id.toString() == @pointset.drafts[0]._id.toString()
      )).to.be(undefined)

      expect(event.type).to.be("approve")
      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: "Your Ten Point"
        aspect: "point"
        collective: "adopted points"
        verbed: "adopted"
        manner: "G'day, mate."
      })

      @pointset = doc
      pointslib.set_approved @session, {
        _id: @pointset.id
        point_id: @pointset.drafts[0]._id
        approved: true
      }, (err, doc, point, event) =>
        expect(err).to.be(null)
        expect(doc).to.not.be(null)
        expect(point).to.not.be(null)
        expect(event).to.not.be(null)

        expect(doc.points.length).to.be(2)
        expect(doc.drafts.length).to.be(1)
        expect(doc.points[1]._id.toString()).to.be(
          @pointset.drafts[0]._id.toString()
        )
        expect(doc.is_approved(point)).to.be(true)
        expect(doc.drafts[0]._id.toString()).to.not.be(
          point._id.toString()
        )

        expect(event.type).to.be("approve")
        terms = api_methods.get_event_grammar(event)
        expect(terms.length).to.be(1)
        expect(terms[0]).to.eql({
          entity: "Your Ten Point"
          aspect: "point"
          collective: "adopted points"
          verbed: "adopted"
          manner: "Whoa."
        })

        @pointset = doc
        done()

  it "unapproves points", (done) ->
    pointslib.set_approved @session, {
      _id: @pointset.id
      point_id: @pointset.points[0]._id
      approved: false
    }, (err, doc, point, event) =>
      expect(err).to.be(null)
      expect(doc.points.length).to.be(1)
      expect(doc.drafts.length).to.be(2)
      expect(doc.drafts[0]._id.toString()).to.be(
        @pointset.points[0]._id.toString()
      )

      @pointset = doc

      expect(event.type).to.be("approve")
      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: "Your Ten Point"
        aspect: "point"
        collective: "adopted points"
        verbed: "retired"
        manner: "G'day, mate."
      })

      pointslib.set_approved @session, {
        _id: @pointset.id
        point_id: @pointset.points[0]._id
        approved: false
      }, (err, doc, point, event) =>
        expect(err).to.be(null)
        expect(doc.points.length).to.be(0)
        expect(doc.drafts.length).to.be(3)

        expect(event.type).to.be("approve")
        terms = api_methods.get_event_grammar(event)
        expect(terms.length).to.be(1)
        expect(terms[0]).to.eql({
          entity: "Your Ten Point"
          aspect: "point"
          collective: "adopted points"
          verbed: "retired"
          manner: "Whoa."
        })

        @pointset = doc
        done()

  it "moves points", (done) ->
    _check_move = (from, to, result, error, cb) =>
      pointslib.move_point @session, {
        _id: @pointset._id
        point_id: @pointset.drafts[from]._id
        position: to
      }, (err, doc, point) =>
        expect(err).to.be(error)
        expect(p._id.toString() for p in doc.drafts).to.eql(
          @pointset.drafts[i]._id.toString() for i in result
        )
        return cb() if error?
        # move it back.
        pointslib.move_point @session, {
          _id: @pointset._id
          point_id: @pointset.drafts[from]._id
          position: from
        }, (err, doc, point) =>
          expect(err).to.be(null)
          expect(p._id.toString() for p in doc.drafts).to.eql(
            p._id.toString() for p in @pointset.drafts)
          cb()

    async.series [
      (done) -> _check_move(0, 1, [1, 0, 2], null, done)
      (done) -> _check_move(0, 2, [1, 2, 0], null, done)
      (done) -> _check_move(1, 0, [1, 0, 2], null, done)
      (done) -> _check_move(1, 2, [0, 2, 1], null, done)
      (done) -> _check_move(2, 0, [2, 0, 1], null, done)
      (done) -> _check_move(2, 1, [0, 2, 1], null, done)
      (done) -> _check_move(0, 3, [0, 1, 2], "Bad position 3", done)
      (done) -> _check_move(0, -1, [0, 1, 2], "Bad position -1", done)
      (done) -> _check_move(0, 0, [0, 1, 2], "No change", done)
      (done) -> _check_move(1, 1, [0, 1, 2], "No change", done)
    ], (err, results) ->
      done()

  it "trashes single points", (done) ->
    [session, pointset] = [@session, @pointset]
    _check_event = (event, type, exp_terms) ->
      expect(event.type).to.be(type)
      expect(event.application).to.be("points")
      expect(event.url).to.be(pointset.url)
      expect(event.absolute_url).to.be(pointset.absolute_url)
      expect(event.entity).to.be(pointset.id)
      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql(exp_terms)

    async.waterfall [
      # Adopt a point so we have an adopted to play with.
      (done) ->
        pointslib.set_approved session, {
          _id: pointset._id
          point_id: pointset.drafts[0]._id
          approved: true
        }, (err, doc, point, event) ->
          common.no_err_args([err, doc, point, event])
          done(null, doc)

      # Move from approved points to trash
      (pointset, done) ->
        point = pointset.points[0]
        expect(point).to.not.be(undefined)
        points_length = pointset.points.length
        pointslib.trash_point session, {
          _id: pointset._id
          point_id: point._id
          is_trash: true
        }, (err, doc, point, event) ->
          common.no_err_args([err, doc, point, event])
          expect(_.find(doc.points, (p) -> p._id == point._id)).to.be(undefined)
          expect(doc.points.length).to.be(points_length - 1)
          expect(doc.trashed_points[0]._id.toString()).to.be(point._id.toString())

          _check_event(event, "trash_point", {
            entity: pointset.title
            aspect: ""
            collective: "point removals"
            verbed: "moved point to trash"
            manner: "Whoa."
          })
          done(null, doc)

      # Restore from trash
      (pointset, done) ->
        point = pointset.trashed_points[0]
        expect(point).to.not.be(undefined)
        points_length = pointset.trashed_points.length
        pointslib.trash_point session, {
          _id: pointset._id
          point_id: point._id
          is_trash: false
        }, (err, doc, outpoint, event) ->
          common.no_err_args([err, doc, outpoint, event])
          expect(_.find(doc.trashed_points, (p) -> p._id == point._id)).to.be(undefined)
          expect(doc.points.length).to.be(points_length - 1)
          expect(doc.drafts[0]._id).to.eql(point._id)
          _check_event(event, "untrash_point", {
            entity: pointset.title
            aspect: ""
            collective: "point removals"
            verbed: "restored point from trash"
            manner: "Whoa."
          })
          done(null, doc)

      # Move from drafts to trash
      (pointset, done) ->
        point = pointset.drafts[0]
        expect(point).to.not.be(undefined)
        points_length = pointset.drafts.length
        pointslib.trash_point session, {
          _id: pointset._id
          point_id: point._id
          is_trash: true
        }, (err, doc, outpoint, event) ->
          common.no_err_args([err, doc, outpoint, event])
          expect(_.find(doc.trashed_points, (p) -> p._id == point._id)).to.be(undefined)
          expect(doc.drafts.length).to.be(points_length - 1)
          expect(doc.trashed_points[0]._id).to.eql(point._id)
          _check_event(event, "trash_point", {
            entity: pointset.title
            aspect: ""
            collective: "point removals"
            verbed: "moved point to trash"
            manner: "Whoa."
          })
          done(null, doc)

    ], (err, pointset) =>
      @pointset = pointset
      done(err)

  it "trashes a pointset", (done) ->
    [session, session2, doc] = [@session, @session2, @pointset]
    api_methods.trash_entity session, {
      application: "points"
      entity: doc.id
      group: doc.sharing.group_id
      trash: true
    }, (err, event, si, doc) ->
      common.no_err_args([err, event, si, doc])
      expect(si.trash).to.be(true)
      expect(doc.trash).to.be(true)
      expect(event.type).to.be("trash")
      expect(event.absolute_url).to.be(doc.absolute_url)
      expect(event.url).to.be(doc.url)
      expect(event.entity).to.be(doc.id)
      expect(event.application).to.be("points")
      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: doc.title
        aspect: ""
        collective: "removals"
        verbed: "moved to trash"
        manner: ""
      })
      done()

  it "untrashes a pointset", (done) ->
    [session, session2, doc] = [@session, @session2, @pointset]
    api_methods.trash_entity session2, {
      application: "points"
      entity: doc.id
      group: doc.sharing.group_id
      trash: false
    }, (err, event, si, doc) ->
      common.no_err_args([err, event, si, doc])
      expect(si.trash).to.be(false)
      expect(doc.trash).to.be(false)
      expect(event.type).to.be("untrash")
      expect(event.absolute_url).to.be(doc.absolute_url)
      expect(event.url).to.be(doc.url)
      expect(event.entity).to.be(doc.id)
      expect(event.application).to.be("points")
      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: doc.title
        aspect: ""
        collective: "removals"
        verbed: "restored from trash"
        manner: ""
      })
      done()

  it "requests deletion", (done) ->
    [session, session2, doc] = [@session, @session2, @pointset]
    # Request deletion
    api_methods.request_deletion session, {
      application: "points"
      entity: doc.id
      group: doc.sharing.group_id
      url: doc.url
      title: doc.title
    }, (err, dr, trashing, event, notices) ->
      common.no_err_args([err, dr, trashing, event, notices])
      [trash_event, si, doc] = trashing
      common.no_err_args([null, trash_event, si, doc])

      expect(doc.trash).to.be(true)
      expect(si.trash).to.be(true)

      expect(event.type).to.be("deletion")
      expect(event.url).to.be(dr.entity_url)
      expect(event.absolute_url).to.be(doc.absolute_url)
      expect(event.entity).to.be(doc.id)
      expect(event.application).to.be('points')
      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: doc.title
        aspect: ""
        collective: "removals"
        verbed: "deletion requested"
        manner: ""
      })
      done()

  it "confirms deletion", (done) ->
    [session, session2, doc] = [@session, @session2, @pointset]
    www_schema.DeletionRequest.findOne {entity: doc.id}, (err, dr) ->
      api_methods.confirm_deletion session2, dr._id, (err, notices) ->
        expect(err).to.be(null)
        expect(notices).to.be(undefined)
        ps_schema.PointSet.findOne {_id: doc._id}, (err, tdoc) ->
          expect(err).to.be(null)
          expect(tdoc).to.be(null)
          done()

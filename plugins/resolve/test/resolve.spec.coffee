expect  = require 'expect.js'
_       = require 'underscore'
async   = require 'async'
config  = require '../../../test/test_config'
common  = require '../../../test/common'
logger  = require('log4js').getLogger("test-resolve")
api_methods = require("../../../lib/api_methods")(config)
www_schema = require('../../../lib/schema').load(config)
resolve_schema = require("../lib/schema").load(config)
resolve = require("../lib/resolve")(config)

describe "resolve", ->
  before (done) ->
    common.startUp (server) =>
      @server = server

      # Establish a session
      @session = {}
      common.stubBrowserID({email: "one@mockmyid.com"})
      async.series [
        (done) =>
          www_schema.User.findOne {email: "one@mockmyid.com"}, (err, doc) =>
            @user = doc
            done(err)
        (done) =>
          api_methods.authenticate(@session, "assertion", done)
        (done) =>
          # Build a proposal to work with.
          new resolve_schema.Proposal({
            revisions: [{
              user_id: @user.id
              name: "One"
              text: "Test proposal?"
            }]
          }).save (err, doc) =>
            @proposal = doc
            done(err)
      ], done

  after (done) ->
    common.shutDown(@server, done)

  it "Posts events", (done) ->
    resolve.post_event @session, @proposal, "visit", {}, 0, (err, event) =>
      expect(err).to.be(null)
      expect(event.application).to.be("resolve")
      expect(event.entity).to.be(@proposal.id)
      www_schema.Event.findOne {entity: @proposal.id}, (err, doc) =>
        expect(err).to.be(null)
        expect(doc.id).to.be(event.id)
        expect(doc.entity).to.be(event.entity)
        expect(doc.group).to.be(@proposal.sharing.group_id)
        expect(doc.anon_id).to.be(@session.anon_id)
        
        terms = api_methods.get_event_grammar(doc)
        expect(terms.length).to.be(1)
        expect(terms[0].entity).to.be(@proposal.title)
        expect(terms[0].aspect).to.be("proposal")
        expect(terms[0].collective).to.be("visited proposals")
        expect(terms[0].verbed).to.be("visited")
        expect(terms[0].manner).to.be("")

        done()

  it "Posts search indices", (done) ->
    resolve.post_search_index @proposal, (err, si) =>
      expect(err).to.be(null)
      expect(si).to.not.be(null)
      expect(si.entity).to.be(@proposal.id)
      expect(si.application).to.be("resolve")
      www_schema.SearchIndex.findOne {entity: @proposal.id}, (err, doc) ->
        expect(err).to.be(null)
        expect(doc.id).to.be(si.id)
        done()
 
  it "Posts proposal revision twinkles", (done) ->
    resolve.post_twinkle @session, @proposal.id, @proposal.revisions[0].id, (err, tw) =>
      expect(err).to.be(null)
      expect(tw).to.not.be(null)
      expect(tw.sender.toString()).to.be(@session.auth.user_id)
      expect(tw.url).to.be(@proposal.url)
      expect(tw.absolute_url).to.be(@proposal.absolute_url)
      @twinkle_to_remove = tw
      done()

  it "Removes a twinkle", (done) ->
    resolve.remove_twinkle @session, @twinkle_to_remove.id, @proposal.id, (err, tw, doc) =>
      expect(err).to.be(null)
      expect(tw).to.not.be(null)
      expect(tw.id).to.be(@twinkle_to_remove.id)
      expect(doc.id).to.be(@proposal.id)
      www_schema.Twinkle.findOne {_id: @twinkle_to_remove.id}, (err, doc) ->
        expect(err).to.be(null)
        expect(doc).to.be(null)
        done()

  it "Creates a proposal", (done) ->
    group = _.find @session.groups, (g) -> g.name == "Two Members"
    resolve.create_proposal @session, {
      proposal: {
        proposal: "This is my proposal."
        sharing: { group_id: group.id }
      }
    }, (err, proposal, event, si, notices) =>
      expect(err).to.be(null)
      expect(proposal).to.not.be(null)
      expect(proposal.revisions[0].text).to.be("This is my proposal.")
      expect(proposal.revisions[0].user_id).to.be(@session.auth.user_id)
      expect(proposal.url).to.be("/p/#{proposal.id}/")
      expect(proposal.absolute_url).to.be(
        "http://localhost:#{config.port}/resolve/p/#{proposal.id}/"
      )
      expect(event.type).to.be("create")
      expect(event.absolute_url).to.be(proposal.absolute_url)
      expect(event.application).to.be("resolve")
      expect(si.entity.toString()).to.be(proposal.id)
      expect(si.absolute_url).to.be(proposal.absolute_url)
      expect(notices.length).to.be(_.size(group.members))

      for notice in notices
        expect(notice.url).to.be(proposal.url)
        expect(notice.absolute_url).to.be(proposal.absolute_url)

      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: "Proposal"
        aspect: "\"#{proposal.title}\""
        collective: 'created proposals'
        verbed: 'created'
        manner: ""
      })

      @proposal_with_notices = proposal
      www_schema.Notification.find {entity: @proposal_with_notices.id}, (err, docs) =>
        expect(err).to.be(null)
        expect(docs.length).to.be(2)
        done()

  it "Updates notifications based on resolution", (done) ->
    #general test of update notifications method.
    @proposal_with_notices.resolved = new Date()
    @proposal_with_notices.save (err, doc) =>
      www_schema.Notification.find {entity: doc.id}, (err, docs) =>
        expect(err).to.be(null)
        expect(docs.length).to.be(2)
        resolve.update_notifications @session, doc, (err, notifications) =>
          expect(notifications.length).to.be(2)
          expect(_.all(n.cleared for n in notifications)).to.be(true)
          www_schema.Notification.find {entity: doc.id, cleared: false}, (err, docs) =>
            expect(docs.length).to.be(0)
            done()

  it "Updates a proposal", (done) ->
    expect(@proposal_with_notices.resolved).to.not.be(null)
    expect(@proposal_with_notices.sharing.group_id).to.not.be(null)
    resolve.update_proposal @session, {
      proposal: { reopened: true, _id: @proposal_with_notices.id }
    }, (err, proposal, event, si, notices) =>
      expect(err).to.be(null)
      expect(proposal).to.not.be(null)
      expect(proposal.id).to.be(@proposal_with_notices.id)
      expect(proposal.resolved).to.be(null)

      expect(event.group.toString()).to.be(
        @proposal_with_notices.sharing.group_id.toString()
      )
      expect(event.url).to.be(proposal.url)
      expect(event.absolute_url).to.be(proposal.absolute_url)

      for notice in notices
        expect(notice.url).to.be(proposal.url)
        expect(notice.absolute_url).to.be(proposal.absolute_url)

      expect(err).to.be(null)
      @proposal_with_notices = proposal

      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: proposal.title
        aspect: "proposal"
        collective: 'changed proposals'
        verbed: 'reopened'
        manner: ""
      })

      done()

  it "Updates notifications based on votes", (done) ->
    prop = @proposal_with_notices
    expect(prop.resolved).to.be(null)
    user_id = prop.revisions[0].user_id
    prop.opinions.push {
      user_id: user_id
      name: @session.users[user_id].name
      revisions: [{
        vote: "weak_yes"
        text: "Okie"
      }]
    }
    prop.save (err, doc) =>
      resolve.update_notifications @session, doc, (err, notifications) =>
        expect(err).to.be(null)
        expect(notifications?.length).to.be(3)
        cleared = 0
        uncleared = 0
        for notice in notifications
          if notice.cleared
            cleared += 1
          else
            uncleared += 1
            expect(notice.recipient.toString()).to.not.eql(user_id.toString())
        expect(cleared).to.be(2)
        expect(uncleared).to.be(1)
        doc.opinions.pop()
        doc.save  (err, doc) =>
          expect(err).to.be(null)
          expect(doc).to.not.be(null)
          resolve.update_notifications @session, doc, (err, notifications) =>
            expect(err).to.be(null)
            expect(notifications.length).to.be(3)
            cleared = 0
            uncleared = 0
            for notice in notifications
              if notice.cleared
                cleared += 1
                expect(notice.recipient.toString()).to.not.eql(user_id.toString())
              else
                uncleared += 1
            expect(cleared).to.be(1)
            expect(uncleared).to.be(2)
            done()

  it "Opinion: error out", (done) ->
    resolve.add_opinion @session, {
      opinion: {
        user_id: @session.auth.user_id
        name: @session.users[@session.auth.user_id].name
        text: "Oh yeah"
        vote: "weak_yes"
      }
    }, (err, proposal) =>
      expect(proposal).to.be(undefined)
      expect(err).to.not.be(null)
      done()

  it "Adds an opinion as self", (done) ->
    start_length = @proposal.opinions.length
    resolve.add_opinion @session, {
      proposal: {_id: @proposal._id}
      opinion: {
        user_id: @session.auth.user_id
        name: @session.users[@session.auth.user_id].name
        text: "Super!!!"
        vote: "weak_yes"
      }
    }, (err, proposal, event, si, notices) =>
      expect(err).to.be(null)
      expect(proposal).to.not.be(null)
      expect(proposal.opinions.length).to.be(start_length + 1)
      expect(proposal.opinions[start_length].user_id).to.be(@session.auth.user_id)
      expect(proposal.opinions[start_length].revisions[0].text).to.be("Super!!!")
      expect(proposal.opinions[start_length].revisions[0].vote).to.be("weak_yes")
    
      expect(event?.type).to.be("append")
      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: proposal.title
        aspect: "opinion"
        collective: 'proposal responses'
        verbed: 'added'
        manner: "Approve with reservations"
      })

      expect(si.text.indexOf("Super!!!")).to.not.be(-1)
      expect(notices.length).to.be(0)
      # TODO: Fix this data blob to be less silly.
      @proposal = proposal
      done()

  it "Adds an opinion as group member", (done) ->
    start_length = @proposal.opinions.length
    www_schema.User.findOne {email: "two@mockmyid.com" }, (err, user) =>
      expect(err).to.be(null)
      expect(user).to.not.be(null)
      # @session belongs to one@mockmyid.com.
      resolve.add_opinion @session, {
        proposal: {_id: @proposal._id}
        opinion: {
          user_id: user._id
          name: user.name
          text: "Far out"
          vote: "no"
        }
      }, (err, proposal, event, si, notices) =>
        expect(err).to.be(null)
        expect(proposal).to.not.be(null)
        expect(proposal.opinions.length).to.be(start_length + 1)
        expect(proposal.opinions[start_length].user_id).to.eql(user.id)
        expect(proposal.opinions[start_length].revisions[0].text).to.be("Far out")

        terms = api_methods.get_event_grammar(event)
        expect(terms.length).to.be(1)
        expect(terms[0]).to.eql({
          entity: proposal.title
          aspect: "opinion"
          collective: 'proposal responses'
          verbed: 'added'
          manner: "Have concerns"
        })

        @proposal = proposal
        done()

  it "Adds an opinion for anonymous", (done) ->
    start_length = @proposal.opinions.length
    # @session belongs to one@mockmyid.com.
    resolve.add_opinion @session, {
      proposal: {_id: @proposal._id}
      opinion: {
        user_id: undefined
        name: "Anonymouse"
        text: "Fur out"
        vote: "no"
      }
    }, (err, proposal, event, si, notices) =>
      expect(err).to.be(null)
      expect(proposal).to.not.be(null)
      expect(proposal.opinions.length).to.be(start_length + 1)
      expect(proposal.opinions[start_length].user_id).to.eql(null)
      expect(proposal.opinions[start_length].name).to.be("Anonymouse")
      expect(proposal.opinions[start_length].revisions[0].text).to.be("Fur out")
      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: proposal.title
        aspect: "opinion"
        collective: 'proposal responses'
        verbed: 'added'
        manner: "Have concerns"
      })
      @proposal = proposal
      done()

  it "Adds an opinion for group member, as anonymous", (done) ->
    start_length = @proposal.opinions.length
    # @session belongs to one@mockmyid.com.
    resolve.add_opinion {}, {
      proposal: {_id: @proposal._id}
      opinion: {
        user_id: undefined
        name: "One"
        text: "Four out"
        vote: "abstain"
      }
    }, (err, proposal, event, si, notices) =>
      expect(err).to.be(null)
      expect(proposal).to.not.be(null)
      expect(proposal.opinions.length).to.be(start_length + 1)
      expect(proposal.opinions[start_length].user_id).to.eql(null)
      expect(proposal.opinions[start_length].name).to.be("One")
      expect(proposal.opinions[start_length].revisions[0].text).to.be("Four out")
      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: proposal.title
        aspect: "opinion"
        collective: 'proposal responses'
        verbed: 'added'
        manner: "I have a conflict of interest"
      })
      @proposal = proposal
      done()

  it "Adds a second opinion as self", (done) ->
    start_length = @proposal.opinions.length
    # @session belongs to one@mockmyid.com.
    resolve.add_opinion @session, {
      proposal: {_id: @proposal._id}
      opinion: {
        user_id: @session.auth.user_id
        name: @session.users[@session.auth.user_id].name
        text: "On second thought..."
        vote: "abstain"
      }
    }, (err, proposal, event, si, notices) =>
      expect(err).to.be(null)
      expect(proposal).to.not.be(null)
      expect(proposal.opinions.length).to.be(start_length) # no increase
      op = _.find proposal.opinions, (o) => o.user_id == @session.auth.user_id
      expect(op?.revisions.length).to.be(2)
      expect(op.revisions[0].text).to.be("On second thought...")
      expect(op.revisions[1].text).to.be("Super!!!")
      @opinion_to_remove = op
      @proposal = proposal
      done()

  it "Removes an opinion", (done) ->
    start_length = @proposal.opinions.length
    resolve.remove_opinion @session, {
      proposal: {_id: @proposal._id}
      opinion: {_id: @opinion_to_remove._id}
    }, (err, proposal, event, si, notices) =>
      expect(err).to.be(null)
      expect(proposal).to.not.be(null)
      expect(err).to.be(null)
      expect(proposal).to.not.be(null)
      expect(proposal.opinions.length).to.be(start_length - 1)
      expect(_.find proposal.opinions, (o) =>
        o.user_id == @opinion_to_remove.user_id
      ).to.be(undefined)

      terms = api_methods.get_event_grammar(event)
      expect(terms.length).to.be(1)
      expect(terms[0]).to.eql({
        entity: proposal.title
        aspect: "opinion"
        collective: 'proposal responses'
        verbed: 'removed'
        manner: "(was \"I have a conflict of interest\")"
      })

      done()


window.console ?= {}
for key in ["log", "error", "debug", "info"]
  window.console[key] ?= (->)
unless window.intertwinkles?
  window.intertwinkles = intertwinkles = {}

class intertwinkles.BaseView extends Backbone.View
  softNav: (event) =>
    event.preventDefault()
    intertwinkles.app.navigate($(event.currentTarget).attr("href"), {
      trigger: true
    })
  initialize: ->
    @views = []

  remove: =>
    if @views?
      view.remove() for view in @views
    super()

  addView: (selector, view) =>
    @$(selector).html(view.el)
    view.render()
    @views.push(view)

  validateFields: (container, selectors) =>
    cleaned_data = {}
    dirty = false
    $(".error", container).removeClass("error")
    $(".error-msg", container).remove()
    for [selector, test, msg, name] in selectors
      el = @$(selector)
      if el.attr("type") == "checkbox"
        val = el.is(":checked")
      else
        val = el.val()

      clean = test(val)
      if clean?
        cleaned_data[name or el.attr("name")] = clean
      else
        dirty = true
        parent = el.closest(".control-group")
        parent.addClass("error")
        parent.find(".controls").prepend(
          "<span class='error-msg help-inline'>#{msg}</span>"
        )
    if dirty
      $(".error", container)[0].scrollIntoView()
      return false
    return cleaned_data

  renderUser: (user_id, name) ->
    if user_id? and intertwinkles.users?[user_id]? and intertwinkles.users[user_id].icon?
      user = intertwinkles.users[user_id]
      return "<span class='user'><img src='#{user.icon.tiny}' /> #{user.name}</span>"
    else
      return "<span class='user'><i class='icon-user'></i> #{name or "Anonymous"}</span>"

class intertwinkles.BaseModalFormView extends intertwinkles.BaseView
  events:
    'submit form': 'submit'

  initialize: (options={}) ->
    super()
    @context = options.context
    @validation = options.validation

  remove: =>
    @removed = true
    @$el.on "hidden", => super()
    @$el.modal('hide')

  submit: (event) =>
    event.preventDefault()
    if @validation
      cleaned_data = @validateFields(@el, @validation)
    else
      cleaned_data = null
    if cleaned_data != false
      $(event.currentTarget).addClass("loading").attr("disabled", true)
      @trigger "submitted", cleaned_data

  render: =>
    @$el.addClass("modal hide fade")
    @$el.html @template(@context)
    @$el.modal('show')
    @$el.on "hidden", =>
      @trigger "hidden", this

intertwinkles.BaseEvents = {
  'click .softnav': 'softNav'
}

intertwinkles.now = () ->
  d = new Date(new Date().getTime() + (intertwinkles.BROWSER_CLOCK_SKEW or 0))
  return d

intertwinkles.parse_date = (date) ->
  return new Date() unless date?
  return new Date(date.getTime()) if _.isDate(date)
  return new Date(date) if _.isNumber(date)
  if _.isString(date) and date.indexOf('Z') != -1
    d = (parseInt(i, 10) for i in date.split(/[^0-9]+/) when i)
    return new Date(Date.UTC(d[0], d[1] - 1, d[2], d[3], d[4], d[5], d[6] or 0))

  date = new Date(date)
  if isNaN(date)
    throw new Error("Unrecognized date format: #{date}")
  return date


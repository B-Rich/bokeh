
define [
  "underscore",
  "backbone",
  "./tool",
  "./event_generators",
], (_, Backbone, Tool, EventGenerators) ->

  TwoPointEventGenerator = EventGenerators.TwoPointEventGenerator

  class BoxSelectToolView extends Tool.View
    initialize: (options) ->
      super(options)
      @select_every_mousemove = @mget('select_every_mousemove')

    bind_bokeh_events: () ->
      super()
      for renderer in @mget_obj ('renderers')
        rendererview = @plot_view.renderers[renderer.id]
        @listenTo(rendererview.xrange(), 'change', @select_callback)
        @listenTo(rendererview.yrange(), 'change', @select_callback)
        @listenTo(renderer, 'change', @select_callback)

    eventGeneratorClass: TwoPointEventGenerator
    toolType: "BoxSelectTool"

    evgen_options:
      keyName: "shiftKey"
      buttonText: "Select"
      buttonIcon: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABwAAAAcCAYAAAByDd+UAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAALEgAACxIB0t1+/AAAABx0RVh0U29mdHdhcmUAQWRvYmUgRmlyZXdvcmtzIENTNui8sowAAAE1SURBVEiJ7ZXNUcQwDIU/7VDA3rnkQAF0QEpJCZSQEihhSxEFMLMlmA44cH8col2CsVlCfmYPvJlMLMnjJ8mSbJLYErtN2a6BsAPczM5roAvZJ9ruS4Q3BV0a/X0ke7anZvMgLcLGRRMeLoZSQe6yDZ2kpwWIXFIxpfkdNlRyPxEPwL7mzfhrap5NgaRW0j47G0nbt0XuQS/JFzhTEeXFCBNwnEsIPANvJcN/W/wV19MWpVk6G2bmQfzNVnotZt1h1IHXaiGPMDG/LRqGOyziC6GZHWaSXYRlee6A1sw6SQ2Dt8nMkqQ2nPKCrePzDbwDboF34CV0R+ARKI42hb6PEdWHrB9sJ7kGP3EsMmki+jbEluEOX4FD6NJ5PY5wCYyidf1ieK+ONRrf459KxrxKV8fmKf0AQEJj/A0qfJ8AAAAASUVORK5CYII="
      cursor: "crosshair"
      restrict_to_innercanvas: true

    tool_events:
      SetBasepoint: "_start_selecting"
      UpdatingMouseMove: "_selecting"
      deactivated: "_stop_selecting"
      DragEnd: "_dragend"

    pause:()->
      return null

    view_coords: (sx, sy) ->
      [vx, vy] = [
        @plot_view.view_state.sx_to_vx(sx),
        @plot_view.view_state.sy_to_vy(sy)
      ]
      return [vx, vy]

    _stop_selecting: () ->
      @trigger('stopselect')
      @basepoint_set = false
      @plot_view.unpause()

    _start_selecting: (e) ->
      @plot_view.pause()
      @trigger('startselect')
      [vx, vy] = @view_coords(e.bokehX, e.bokehY)
      @mset({'start_vx': vx, 'start_vy': vy, 'current_vx': null, 'current_vy': null})
      @basepoint_set = true

    _get_selection_range: ->
      if @mget('select_x')
        xrange = [@mget('start_vx'), @mget('current_vx')]
        xrange = [_.min(xrange), _.max(xrange)]
      else
        range = @plot_view.view_state.get('inner_range_horizontal')
        xrange = [range.get('start'), range.get('end')]
      if @mget('select_y')
        yrange = [@mget('start_vy'), @mget('current_vy')]
        yrange = [_.min(yrange), _.max(yrange)]
      else
        range = @plot_view.view_state.get('inner_range_vertical')
        yrange = [range.get('start'), range.get('end')]
      return [xrange, yrange]

    _selecting: (e, x_, y_) ->
      [vx, vy] = @view_coords(e.bokehX, e.bokehY)
      @mset({'current_vx': vx, 'current_vy': vy})

      [@xrange, @yrange] = @_get_selection_range()
      @trigger('boxselect', @xrange, @yrange)

      if @select_every_mousemove
        @_select_data()

      @plot_view.render_overlays(true)
      return null

    _dragend : () ->
      @_select_data()

    _select_data: () ->
      if not @basepoint_set
        return

      geometry = {
        type: 'rect'
        vx0: @xrange[0]
        vx1: @xrange[1]
        vy0: @yrange[0]
        vy1: @yrange[1]
      }

      datasources = {}
      datasource_selections = {}
      for renderer in @mget_obj('renderers')
        datasource = renderer.get_obj('data_source')
        datasources[datasource.id] = datasource

      for renderer in @mget_obj('renderers')
        datasource_id = renderer.get_obj('data_source').id
        _.setdefault(datasource_selections, datasource_id, [])
        #the select call of the render converts the screen coordinates
        #of @xrange and @yrange into data space coordinates
        selected = @plot_view.renderers[renderer.id].hit_test(geometry)
        datasource_selections[datasource_id].push(selected)

      for own k,v of datasource_selections

        #FIXME: I'm not sure why this is here, when will v have more than one element?
        #
        # This next line is the equivalent of calling
        #_.intersection(v[0], v[1], v[2]...) for however many
        #subelements v has.  each member of the v list will have another
        #list inside it.  thus this line finds the intersection of the
        #lists of v.
        selected = _.intersection.apply(_, v)
        ds = datasources[k]
        ds.save(
          selected:selected
        ,
          {patch: true}
        )
        @plot_view.unpause()
      return null

  class BoxSelectTool extends Tool.Model
    default_view: BoxSelectToolView
    type: "BoxSelectTool"

    defaults: () ->
      return _.extend(super(), {
        renderers: []
        select_x: true
        select_y: true
        select_every_mousemove: false
        data_source_options: {} # backbone options for save on datasource
      })

    display_defaults: () ->
      super()

  class BoxSelectTools extends Backbone.Collection
    model: BoxSelectTool

  return {
    "Model": BoxSelectTool,
    "Collection": new BoxSelectTools(),
    "View": BoxSelectToolView,
  }

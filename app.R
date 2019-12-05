##########################################################
################### sHydrology_map ####################### 
### A Shiny-Leaflet interface to the HYDAT database.  ####
##########################################################
# Leaflet map
#
# By M. Marchildon
# v.1.3
# Nov, 2019
##########################################################


source("functions/pkg.R", local=TRUE)
source("functions/shiny_leaflet_functions.R", local=TRUE)
source("functions/HYDAT_query.R", local=TRUE)

shinyApp(
  ui <- bootstrapPage(
    useShinyjs(),
    tags$style(type = "text/css", "html, body {width:100%;height:100%}"),
    tags$head(includeCSS("functions/styles.css")),
    
    div(
      id = "app-content",
      list(tags$head(HTML('<link rel="icon", href="favicon.png",type="image/png" />'))),
      div(style="padding: 1px 0px; width: '100%'", titlePanel(title="", windowTitle="sHydrology"))
    ),
    
    leafletOutput("map", width = "100%", height = "100%"),
    
    absolutePanel(id = "panl", class = "panel panel-default", fixed = TRUE,
                  draggable = FALSE, top = 10, left = "auto", right = 10, bottom = "auto",
                  width = 330, height = "auto",
                  
                  h2("Hydrograph explorer"),
                  sliderInput("YRrng", "Select date envelope", min(tblSta$YRb), max(tblSta$YRe),
                              value = c(max(tblSta$YRe)-30,max(tblSta$YRe)), sep=""),
                  
                  selectInput("POR", "minimum period of length/count of data", c("no limit" = 0, "5yr" = 5, "10yr" = 10, "30yr" = 30)),
                  checkboxInput("chkMet", "show climate stations", FALSE),
                  
                  h4("Hydrograph preview:"),
                  dygraphOutput("hydgrph", height = 200), br(),
                  div(style="display:inline-block",actionButton("expnd", "Analyze")),
                  div(style="display:inline-block",downloadButton('dnld', 'Download CSV'))
    )
  ),
  
  
  server <- function(input, output, session) {
    shinyjs::disable("dnld")
    shinyjs::disable("expnd")
    
    
    ################################
    ## map/object rendering
    
    # leaflet map
    output$map <- renderLeaflet({
      m <- leaflet() %>%
        addTiles(group='OSM') %>% # OpenStreetMap by default
        addProviderTiles(providers$OpenTopoMap, group='Topo') %>%
        addProviderTiles(providers$Stamen.TonerLite, group = "Toner Lite") %>%
        addMarkers(lng = tblSta$LNG, lat = tblSta$LAT) %>%
        addLayersControl (
          baseGroups = c("Topo", "OSM", "Toner Lite"),
          options = layersControlOptions(position = "bottomleft")
        ) #%>%
        # addDrawToolbar(
        #   targetGroup='Selected',
        #   polylineOptions=FALSE,
        #   markerOptions = FALSE,
        #   # polygonOptions = drawPolygonOptions(shapeOptions=drawShapeOptions(fillOpacity = 0,color = 'white',weight = 3)),
        #   # rectangleOptions = drawRectangleOptions(shapeOptions=drawShapeOptions(fillOpacity = 0,color = 'white',weight = 3)),
        #   # circleOptions = drawCircleOptions(shapeOptions = drawShapeOptions(fillOpacity = 0,color = 'white',weight = 3)),
        #   circleMarkerOptions = FALSE,
        #   editOptions = editToolbarOptions(edit = FALSE, selectedPathOptions = selectedPathOptions())
        # )
    })
    
    observe({
      d <- filteredData()
      # coordinates <- SpatialPointsDataFrame(d[,c('LNG', 'LAT')], d)
      m <- leafletProxy("map") %>%
        clearPopups() %>% 
        clearMarkers() %>%
        clearMarkerClusters() %>%
        addMarkers(data = d,
                   layerId = ~IID, clusterId = 1,
                   lng = ~LNG, lat = ~LAT,
                   popup = ~paste0(NAM1,': ',NAM2),
                   clusterOptions = markerClusterOptions()) %>%
        clearMarkers()
      if (input$chkMet) {
        if (is.null(tblStaMet)) qMetLoc()
        if (!is.null(tblStaMet)){
          m %>% addCircleMarkers(data = filteredDataMet(), # addCircleMarkers
                 layerId = ~IID, clusterId = 2,
                 lng = ~LNG, lat = ~LAT,
                 popup = ~paste0(NAM1,': ',NAM2,'<br><a href="',metlnk,LID,'" target="_blank">analyse climate data</a>'),
                 # clusterOptions = markerClusterOptions(),
                 color = 'red', radius = 10)
        }
      }
    })
    
    filteredData <- reactive({
      p <- as.numeric(input$POR)*365.25
      tblSta[tblSta$YRe >= input$YRrng[1] & tblSta$YRb <= input$YRrng[2] & tblSta$CNT > p,]
    })
    
    filteredDataMet <- reactive({
      p <- as.numeric(input$POR)*365.25
      tblStaMet[tblStaMet$YRe >= input$YRrng[1] & tblStaMet$YRb <= input$YRrng[2] & tblStaMet$pcnt > p,]   
    })
    
    # observeEvent(input$map_draw_new_feature, { # see: https://redoakstrategic.com/geoshaper/
    #   found_in_bounds <- findLocations(shape = input$map_draw_new_feature
    #                                    , location_coordinates = coordinates
    #                                    , location_id_colname = "IID")
    #   print(found_in_bounds)
    # })

    # hydrograph preview
    output$hydgrph <- renderDygraph({
      if (!is.null(sta$hyd)){
        qxts <- xts(sta$hyd$Flow, order.by = sta$hyd$Date)
        lw <- max(20,25 + (log10(max(sta$hyd$Flow))-2)*8) # dynamic plot fitting
        colnames(qxts) <- 'Discharge'
        dygraph(qxts) %>%
          # dyLegend(show = 'always') %>%
          dyOptions(axisLineWidth = 1.5, fillGraph = TRUE, stepPlot = TRUE) %>%
          dyAxis(name='y', labelWidth=0, axisLabelWidth=lw) %>%
          dyRangeSelector(strokeColor = '')
      }
    })
    
    # reactives
    sta <- reactiveValues(loc=NULL, id=NULL, name=NULL, name2=NULL, hyd=NULL, DTb=NULL, DTe=NULL)
    
    observe({
      if (!is.null(input$map_marker_click)){
        e <- input$map_marker_click
        sta$id <- e$id
        if (!is.null(sta$id)){
          if (!is.null(e$clusterId)){
            switch(e$clusterId,
                   { # 1=surface water
                     withProgress(message = 'Rendering plot..', value = 0.1, {
                       starow <- tblSta[tblSta$IID==sta$id,]
                       sta$loc <- starow$LID
                       sta$name <- as.character(starow$NAM1)
                       sta$name2 <- as.character(starow$NAM2)
                       sta$hyd <- qTemporalSW(idbc,sta$id)
                       sta$DTb <- min(sta$hyd$Date, na.rm=T)
                       sta$DTe <- max(sta$hyd$Date, na.rm=T)          
                       setProgress(1)
                     })
                     shinyjs::enable("dnld")
                     shinyjs::enable("expnd")
                     wlnk <- paste0("window.open('",swlnk,sta$loc,"', '_blank')")
                     onclick("expnd", runjs(wlnk))
                   },
                   { # 2=climate
                     # do nothing
                   },
                   {print(e)} # default
            )            
          }
        }
      }
    })
    
    output$dnld <- downloadHandler(
      filename <- function() { paste0(sta$name, '.csv') },
      content <- function(file) {
        if(!is.null(sta$hyd)) write.csv(sta$hyd[!is.na(sta$hyd$Flow),], file, row.names = FALSE)
      } 
    )
    
    session$onSessionEnded(stopApp)
  }
)
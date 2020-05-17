

################################
## map/object rendering

# icons
blueIcon <- makeIcon(
  iconUrl = "ico/blue-map-pin.png",
  iconWidth = 19, iconHeight = 30,
  iconAnchorX = 10, iconAnchorY = 30
)
redIcon <- makeIcon(
  iconUrl = "ico/red-map-pin.png",
  iconWidth = 19, iconHeight = 30,
  iconAnchorX = 10, iconAnchorY = 30
)

# leaflet map
output$map <- renderLeaflet({
  m <- leaflet() %>%
    addTiles(group='OSM') %>% # OpenStreetMap by default
    addProviderTiles(providers$OpenTopoMap, group='Topo', options = providerTileOptions(attribution=" Map data: © OpenStreetMap contributors, SRTM | Map style: © OpenTopoMap (CC-BY-SA) | Oak Ridges Moraine Groundwater Program")) %>%
    addProviderTiles(providers$Stamen.TonerLite, group = "Toner Lite", options = providerTileOptions(attribution=" Map tiles by Stamen Design, CC BY 3.0 — Map data © OpenStreetMap contributors | Oak Ridges Moraine Groundwater Program")) %>%
    addMarkers(lng = tblSta$LNG, lat = tblSta$LAT, icon = blueIcon) %>%
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
  d <- filteredDataSW()
  m <- leafletProxy("map") %>%
    clearPopups() %>%
    clearMarkers() %>%
    clearMarkerClusters() %>%
    addMarkers(data = d,
               layerId = ~IID, clusterId = 1,
               lng = ~LNG, lat = ~LAT,
               icon = blueIcon,
               popup = ~paste0(NAM1,': ',NAM2,'<br><a href="',swlnk,LID,'" target="_blank">analyze streamflow data</a>'),
               clusterOptions = markerClusterOptions()) %>%
    clearMarkers()
  if (input$chkMet) {
    if (is.null(tblStaMet)) qMetLoc()
    if (!is.null(tblStaMet)){
      # m %>% addCircleMarkers(data = filteredDataMet(), # addCircleMarkers
      #        layerId = ~IID, clusterId = 2,
      #        lng = ~LNG, lat = ~LAT,
      #        popup = ~paste0(NAM1,': ',NAM2,'<br><a href="',metlnk,LID,'" target="_blank">analyse climate data</a>'),
      #        # clusterOptions = markerClusterOptions(),
      #        color = 'red', radius = 10)
      m %>% addMarkers(data = filteredDataMet(),
                       layerId = ~IID, clusterId = 2,
                       lng = ~LNG, lat = ~LAT,
                       icon = redIcon,
                       popup = ~paste0(NAM1,': ',NAM2,'<br><a href="',metlnk,LID,'" target="_blank">analyze climate data</a>'),
                       clusterOptions = markerClusterOptions())
    }
  }
})

filteredDataSW <- reactive({
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

# Dygraph hydrograph preview in absolutePanel
output$hydgrph <- renderDygraph({
  if (!is.null(sta$hyd)){
    switch(sta$typ,
           { # 1=surface water
             qxts <- xts(sta$hyd$Flow, order.by = sta$hyd$Date)
             lw <- max(20,25 + (log10(max(sta$hyd$Flow))-2)*8) # dynamic plot fitting
             colnames(qxts) <- 'Discharge'
             dygraph(qxts) %>%
               # dyLegend(show = 'always') %>%
               dyOptions(axisLineWidth = 1.5, fillGraph = TRUE, stepPlot = TRUE) %>%
               dyAxis(name='y', labelWidth=0, axisLabelWidth=lw) %>%
               dyRangeSelector(strokeColor = '')                 
           },
           { # 2=climate
             qxts <- xts(cbind(sta$hyd$Pre,sta$hyd$Tem), order.by = sta$hyd$Date)
             lw <- max(20,25 + (log10(max(sta$hyd$Pre))-2)*8) # dynamic plot fitting
             colnames(qxts) <- c('Precip','Temp')
             dygraph(qxts) %>%
               # dyLegend(show = 'always') %>%
               dyOptions(axisLineWidth = 1.5, fillGraph = TRUE, stepPlot = TRUE) %>%
               dyAxis(name='y', labelWidth=0, axisLabelWidth=lw) %>%
               dyRangeSelector(strokeColor = '')  
           })
  }
})

# reactives
sta <- reactiveValues(loc=NULL, id=NULL, typ=NULL, name=NULL, name2=NULL, hyd=NULL, DTb=NULL, DTe=NULL)

observe({
  if (!is.null(input$map_marker_click)){
    e <- input$map_marker_click
    sta$id <- e$id
    if (!is.null(sta$id)){
      if (!is.null(e$clusterId)){
        switch(e$clusterId,
               { # 1=surface water
                 withProgress(message = 'Querying..', value = 0.1, {
                   starow <- tblSta[tblSta$IID==sta$id,]
                   sta$loc <- starow$LID
                   sta$typ <- 1
                   sta$name <- as.character(starow$NAM1)
                   sta$name2 <- as.character(starow$NAM2)
                   sta$hyd <- qTemporalSW(idbcsw,sta$id)
                   incProgress(0.5, detail = 'Rendering plot..')
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
                 withProgress(message = 'Querying..', value = 0.1, {
                   starow <- tblStaMet[tblStaMet$IID==sta$id,]
                   sta$loc <- starow$LID
                   sta$typ <- 2
                   sta$name <- as.character(starow$NAM1)
                   sta$name2 <- as.character(starow$NAM2)
                   sta$hyd <- qTemporalMET(idbcmet,sta$id)
                   incProgress(0.5, detail = 'Rendering plot..')
                   sta$DTb <- min(sta$hyd$Date, na.rm=T)
                   sta$DTe <- max(sta$hyd$Date, na.rm=T)          
                   setProgress(1)
                 })
                 shinyjs::enable("dnld")
                 shinyjs::enable("expnd")
                 wlnk <- paste0("window.open('",metlnk,sta$loc,"', '_blank')")
                 onclick("expnd", runjs(wlnk))
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
    switch(sta$typ,
           { # 1=surface water
             if(!is.null(sta$hyd)) write.csv(sta$hyd[!is.na(sta$hyd$Flow),], file, row.names = FALSE)               
           },
           { # 2=climate
             if(!is.null(sta$hyd)) write.csv(sta$hyd, file, row.names = FALSE)
           })
  } 
)
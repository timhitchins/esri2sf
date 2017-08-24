library(httr)
library(jsonlite)
library(sf)
library(dplyr)

#' main function
#' This function is the interface to the user.
#' @importFrom jsonlite httr sf dplyr
#' @param url string for service url. ex) https://sampleserver1.arcgisonline.com/ArcGIS/rest/services/Demographics/ESRI_Census_USA/MapServer/3
#' @param outFields vector of fields you want to include. default is '*' for all fields
#' @param where string for where condition. default is 1=1 for all rows
#' @param token. string for authentication token if needed.
#' @examples
#' url <- "https://sampleserver1.arcgisonline.com/ArcGIS/rest/services/Demographics/ESRI_Census_USA/MapServer/3"
#' outFields <- c("POP2007", "POP2000")
#' where <- "STATE_NAME = 'Michigan'"
#' df <- esri2sf(url, outFields=outFields, where=where)
#' plot(df)
#' @export
esri2sf <- function(url, outFields=c("*"), where="1=1", token='') {
  layerInfo <- jsonlite::fromJSON(httr::content(httr::POST(url, query=list(f="json", token=token), encode="form")))
  print(layerInfo$type)
  geomType <- layerInfo$geometryType
  print(geomType)
  queryUrl <- paste(url, "query", sep="/")
  esriFeatures <- getEsriFeatures(queryUrl, outFields, where, token)
  simpleFeatures <- esri2sfGeom(esriFeatures, geomType)
  return(simpleFeatures)
}

getEsriFeatures <- function(queryUrl, fields, where, token='') {
  ids <- getObjectIds(queryUrl, where, token)
  idSplits <- split(ids, ceiling(seq_along(ids)/500))
  results <- lapply(idSplits, getEsriFeaturesByIds, queryUrl, fields, token)
  merged <- unlist(results, recursive=FALSE)
  return(merged)
}

getObjectIds <- function(queryUrl, where, token=''){
  # create Simple Features from ArcGIS servers json response
  query <- list(
    where=where,
    returnIdsOnly="true",
    token=token,
    f="json"
  )
  responseRaw <- httr::content(httr::POST(queryUrl, body=query, encode="form"))
  response <- jsonlite::fromJSON(responseRaw)
  return(response$objectIds)
}

getEsriFeaturesByIds <- function(ids, queryUrl, fields, token=''){
  # create Simple Features from ArcGIS servers json response
  query <- list(
    objectIds=paste(ids, collapse=","),
    outFields=paste(fields, collapse=","),
    token=token,
    outSR='4326',
    f="json"
  )
  responseRaw <- httr::content(httr::POST(queryUrl, body=query, encode="form"))
  response <- jsonlite::fromJSON(responseRaw,
                       simplifyDataFrame = FALSE,
                       simplifyVector = FALSE,
                       digits=NA)
  esriJsonFeatures <- response$features
  return(esriJsonFeatures)
}

esri2sfGeom <- function(jsonFeats, geomType) {
  # convert esri json to simple feature
  if (geomType == 'esriGeometryPolygon') {
    geoms <- esri2sfPolygon(jsonFeats)
  }
  if (geomType == 'esriGeometryPoint') {
    geoms <- esri2sfPoint(jsonFeats)
  }
  if (geomType == 'esriGeometryPolyline') {
    geoms <- esri2sfPolyline(jsonFeats)
  }
  # attributes
  atts <- lapply(jsonFeats, '[[', 1)
  af <- dplyr::bind_rows(lapply(atts, as.data.frame.list, stringsAsFactors=FALSE))
  # geometry + attributes
  df <- sf::st_sf(geoms, af, geom=geoms, crs="+init=epsg:4326")
  return(df)
}

esri2sfPoint <- function(features) {
  getPointGeometry <- function(feature) {
    return(sf::st_point(unlist(feature$geometry)))
  }
  geoms <- sf::st_sfc(lapply(features, getPointGeometry))
  return(geoms)
}

esri2sfPolygon <- function(features) {
  ring2matrix <- function(ring) {
    return(do.call(rbind, lapply(ring, unlist)))
  }
  rings2multipoly <- function(rings) {
    return(sf::st_multipolygon(list(lapply(rings, ring2matrix))))
  }
  getGeometry <- function(feature) {
    return(rings2multipoly(feature$geometry$rings))
  }
  geoms <- sf::st_sfc(lapply(features, getGeometry))
  return(geoms)
}

esri2sfPolyline <- function(features) {
  path2matrix <- function(path) {
    return(do.call(rbind, lapply(path, unlist)))
  }
  paths2multiline <- function(paths) {
    return(sf::st_multilinestring(lapply(paths, path2matrix)))
  }
  getGeometry <- function(feature) {
    return(paths2multiline(feature$geometry$paths))
  }
  geoms <- sf::st_sfc(lapply(features, getGeometry))
  return(geoms)
}

generateToken <- function(server, uid){
  # generate auth token from GIS server
  pwd <- rstudioapi::askForPassword("pwd")
  query <- list(
    username=uid,
    password=pwd,
    expiration="5000",
    client="requestip",
    f="json"
  )
  url <- paste(server, "arcgis/admin/generateToken", sep="/")
  r <- httr::POST(url, body=query, encode="form")
  token <- jsonlite::fromJSON(httr::content(r, "parsed"))$token
  return(token)
}
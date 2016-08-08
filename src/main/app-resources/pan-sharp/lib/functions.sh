#!/bin/bash

# define the exit codes
SUCCESS=0
ERR_NO_URL=5
ERR_NO_PRD=8
ERR_GDAL_VRT=10
ERR_MAP_BANDS=15
ERR_OTB_BUNDLETOPERFECTSENSOR=20
ERR_DN2REF_4=25
ERR_DN2REF_3=25
ERR_DN2REF_2=25
ERR_GDAL_VRT2=30
ERR_GDAL_TRANSLATE=35
ERR_GDAL_WARP=40
ERR_GDAL_TRANSLATE=45
ERR_GDAL_ADDO=50
ERR_PUBLISH=55

# add a trap to exit gracefully
function cleanExit ()
{
  local retval=$?
  local msg=""
  case "${retval}" in
    ${SUCCESS}) msg="Processing successfully concluded";;
    ${ERR_NO_URL}) msg="The Landsat 8 product online resource could not be resolved";;
    ${ERR_NO_PRD}) msg="The Landsat 8 product online resource could not be retrieved";;
    ${ERR_GDAL_VRT}) msg="Failed to create the RGB VRT";;
    ${ERR_MAP_BANDS}) msg="Failed to map RGB bands";;
    ${ERR_OTB_BUNDLETOPERFECTSENSOR}) msg="Failed to apply BundleToPerfectSensor OTB operator";;
    ${ERR_DN2REF_4}) msg="Failed to convert DN to reflectance";;
    ${ERR_DN2REF_3}) msg="Failed to convert DN to reflectance";;
    ${ERR_DN2REF_2}) msg="Failed to convert DN to reflectance";;
    ${ERR_GDAL_VRT2}) msg="Failed to create VRT with panchromatic bands";;
    ${ERR_GDAL_TRANSLATE}) msg="Failed to apply gdal_translate";;
    ${ERR_GDAL_WARP}) msg="Failed to warp";;
    ${ERR_GDAL_TRANSLATE2}) msg="Failed to apply gdal_translate";;
    ${ERR_ADDO}) msg="Failed to create levels";;
    ${ERR_PUBLISH}) msg="Failed to publish the results";;
    *) msg="Unknown error";;
  esac

  [ "${retval}" != "0" ] && ciop-log "ERROR" "Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
  exit ${retval}
}

function setOTBenv() {
    
  . /etc/profile.d/otb.sh

  export otb_ram=4096
 # export GDAL_DATA=/usr/share/gdal/
}

function setGDALEnv() {

  export GDAL_HOME=/usr/local/gdal-t2/
  export PATH=$GDAL_HOME/bin/:$PATH
  export LD_LIBRARY_PATH=$GDAL_HOME/lib/:$LD_LIBRARY_PATH
  export GDAL_DATA=$GDAL_HOME/share/gdal

}

function mapBands() {

  local vrt=$1

  xmlstarlet ed -L -a "/VRTDataset/VRTRasterBand[@band="1"]/NoDataValue" \
    -t elem -n "ColorInterp" -v "Red" \
    ${vrt}

  xmlstarlet ed -L -a "/VRTDataset/VRTRasterBand[@band="2"]/NoDataValue" \
    -t elem -n "ColorInterp" -v "Green" \
    ${vrt}

  xmlstarlet ed -L -a "/VRTDataset/VRTRasterBand[@band="3"]/NoDataValue" \
    -t elem -n "ColorInterp" -v "Blue" \
    ${vrt}
}

function url_resolver() {

  local url=""
  local reference="$1"
  
  url="$(opensearch-client -m EOP -p es=gateway "${reference}" enclosure )"

  echo "${url}"

}

function metadata() {

  local xpath="$1"
  local value="$2"
  local target_xml="$3"
 
  xmlstarlet ed -L \
    -N A="http://www.opengis.net/opt/2.1" \
    -N B="http://www.opengis.net/om/2.0" \
    -N C="http://www.opengis.net/gml/3.2" \
    -N D="http://www.opengis.net/eop/2.1" \
    -u  "${xpath}" \
    -v "${value}" \
    ${target_xml}
 
}

function main() {

  # set OTB environment
  setOTBenv

  setGDALEnv

  cd ${TMPDIR}

  num_steps=7

  while read input
  do 
    ciop-log "INFO" "(1 of ${num_steps}) Retrieve Landsat 8 product from ${input}"

    # temporary path until eo-samples indes is ready
    read identifier startdate enddate < <( opensearch-client ${input} identifier,startdate,enddate | tr "," " " )
    #read identifier < <( opensearch-client ${input} identifier )
    online_resource="$( url_resolver ${input} )"
    [ -z "${online_resource}" ] && return ${ERR_NO_URL} 

    local_resource="$( echo ${online_resource} | ciop-copy -U -O ${TMPDIR} - )"
    [ -z "${local_resource}" ] && return ${ERR_NO_PRD}  
 
    ciop-log "INFO" "(2 of ${num_steps}) Extract ${identifier}"
    
    mkdir ${identifier}
    tar jxf ${local_resource} -C ${identifier}

    export DIR=${identifier}

    ciop-log "INFO" "(3 of ${num_steps}) Create VRT with RGB bands" 
    gdalbuildvrt \
      -separate \
      -q \
      -srcnodata "0 0 0"\
      -vrtnodata "0 0 0"\
      ${DIR}/rgb.vrt \
      ${DIR}/*B4.TIF ${DIR}/*B3.TIF ${DIR}/*B2.TIF || return ${ERR_GDAL_VRT}

    mapBands ${DIR}/rgb.vrt || return ${ERR_MAP_BANDS}

    ciop-log "INFO" "(4 of ${num_steps}) OTB BundleToPerfectSensor"
    
    otbcli_BundleToPerfectSensor \
      -progress false \
      -ram ${otb_ram} \
      -inp ${DIR}/*B8.TIF \
      -inxs ${DIR}/rgb.vrt \
      -out ${DIR}/${DIR}_PANSHARP.tif uint16 || return ${ERR_OTB_BUNDLETOPERFECTSENSOR}

    rm -f ${DIR}/rgb.vrt

    ciop-log "INFO" "(5 of ${num_steps}) Produce result metadata"

    target_xml=${TMPDIR}/${DIR}/${DIR}_PANSHARP.tif.xml
    cp /application/pan-sharp/etc/eop-template.xml ${target_xml}

    # set product type
    metadata \
      "//A:EarthObservation/D:metaDataProperty/D:EarthObservationMetaData/D:productType" \
      "LP8_PANSHARP" \
      ${target_xml}

    # set processor name
    metadata \
      "//A:EarthObservation/D:metaDataProperty/D:EarthObservationMetaData/D:processing/D:ProcessingInformation/D:processorName" \
      "dcs-landsat8-pansharpening" \
      ${target_xml}

    metadata \
      "//A:EarthObservation/D:metaDataProperty/D:EarthObservationMetaData/D:processing/D:ProcessingInformation/D:processorVersion" \
      "1.0" \
      ${target_xml}

    # set processor name
    metadata \
      "//A:EarthObservation/D:metaDataProperty/D:EarthObservationMetaData/D:processing/D:ProcessingInformation/D:nativeProductFormat" \
      "GEOTIFF" \
      ${target_xml}

    # set processor name
    metadata \
      "//A:EarthObservation/D:metaDataProperty/D:EarthObservationMetaData/D:processing/D:ProcessingInformation/D:processingCenter" \
      "Terradue Cloud Platform" \
      ${target_xml}
  
    # set startdate
    metadata \
      "//A:EarthObservation/B:phenomenonTime/C:TimePeriod/C:beginPosition" \
      "${startdate}" \
      ${target_xml}

    # set stopdate
    metadata \
      "//A:EarthObservation/B:phenomenonTime/C:TimePeriod/C:endPosition" \
      "${enddate}" \
      ${target_xml}   
  
    # set orbit direction
    metadata \
      "//A:EarthObservation/B:procedure/D:EarthObservationEquipment/D:acquisitionParameters/D:Acquisition/D:orbitDirection" \
      "DESCENDING" \
      ${target_xml}


    [ -z "${path}" ] && path="$( echo ${identifier} | cut -c 4-6)"
    row="$( echo ${identifier} | cut -c 7-9)"

    # set path
    metadata \
      "//A:EarthObservation/B:procedure/D:EarthObservationEquipment/D:acquisitionParameters/D:Acquisition/D:wrsLongitudeGrid" \
      "${path}" \
      ${target_xml} 

    # set row
    metadata \
      "//A:EarthObservation/B:procedure/D:EarthObservationEquipment/D:acquisitionParameters/D:Acquisition/D:wrsLatitudeGrid" \
      "${row}" \
      ${target_xml} 

    ciop-log "INFO" "(6 of ${num_steps}) Publish pan-sharpened RGB image"
    ciop-publish -m ${TMPDIR}/${DIR}/${DIR}_PANSHARP.tif || exit ${ERR_PUBLISH}
    
    ciop-log "INFO" "(7 of ${num_steps}) Publish eop metadata"
    ciop-publish -m ${target_xml} || exit ${ERR_PUBLISH}
  done

}


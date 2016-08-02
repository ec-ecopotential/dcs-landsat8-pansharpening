#!/bin/bash

set -x 

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

function getGain() {

  local band=$1

  gain=$( cat $DIR/*_MTL.txt | grep REFLECTANCE_MULT_BAND_${band} | cut -d "=" -f 2 | tr -d " " )

  echo ${gain}

}

function getOffset() {

  local band=$1

  offset=$( cat $DIR/*_MTL.txt | grep REFLECTANCE_ADD_BAND_${band} | cut -d "=" -f 2 | tr -d " " )

  echo ${offset}

}

function DNtoReflectance() {

  local band=$1
  local base_name=$2

  gain=$( getGain ${band} )
  offset=$( getOffset ${band} )

  [ ${band} -eq 4 ] && pan_band=1
  [ ${band} -eq 3 ] && pan_band=2
  [ ${band} -eq 2 ] && pan_band=3

  otbcli_BandMath \
    -progress false \
    -il ${base_name}/pan-${base_name}.tif \
    -exp "${gain} * im1b${pan_band} + ${offset}" \
    -out ${base_name}/PAN_TOA_REFLECTANCE_B${band}.TIF

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
  
  #read identifier path < <( opensearch-client -m EOP  "${reference}" identifier,wrsLongitudeGrid | tr "," " " )
  #[ -z "${path}" ] && path="$( echo ${identifier} | cut -c 4-6)"
  #row="$( echo ${identifier} | cut -c 7-9)"

  #url="http://storage.googleapis.com/earthengine-public/landsat/L8/${path}/${row}/${identifier}.tar.bz"
  url="$(opensearch-client -m EOP -p es=gateway "${reference}" enclosure )"
  #[ -z "$( curl -s --head "${url}" | head -n 1 | grep "HTTP/1.[01] [23].." )" ] && return 1

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

  # set the gdal addo levels
  addo="2 4 8 16 32 64 128 256 512 1024 2048 4096 8192"

  # set OTB environment
  setOTBenv

  setGDALEnv

  cd ${TMPDIR}

  num_steps=14

  while read input
  do 
    ciop-log "INFO" "(1 of ${num_steps}) Retrieve Landsat 8 product from ${input}"

    # temporary path until eo-samples indes is ready
    #read identifier startdate enddate < <( opensearch-client ${input} identifier,startdate,enddate | tr "," " " )
    read identifier < <( opensearch-client ${input} identifier )
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
      -out ${DIR}/pan-${DIR}.tif uint16 || return ${ERR_OTB_BUNDLETOPERFECTSENSOR}

    rm -f ${DIR}/rgb.vrt

    ciop-log "INFO" "(5 of ${num_steps}) Conversion of DN to reflectance"

    DNtoReflectance 4 ${DIR} || return ${ERR_DN2REF_4}
    DNtoReflectance 3 ${DIR} || return ${ERR_DN2REF_3}
    DNtoReflectance 2 ${DIR} || return ${ERR_DN2REF_2}

    rm -f ${DIR}/pan-${DIR}.tif

    ciop-log "INFO" "(6 of ${num_steps}) Create VRT with RGB pansharpened bands"

    gdalbuildvrt \
      -separate \
      -q \
      -srcnodata "0 0 0"\
      -vrtnodata "0 0 0"\
      ${DIR}/pan_rgb.vrt \
      ${DIR}/PAN*B4.TIF ${DIR}/PAN*B3.TIF ${DIR}/PAN*B2.TIF || return ${ERR_GDAL_VRT2}

    ciop-log "INFO" "(7 of ${num_steps}) Rescale to bitr"

    gdal_translate \
      -q \
      -ot Byte \
      -scale 0 1 0 255 \
      -a_nodata "0 0 0" \
      ${DIR}/pan_rgb.vrt ${DIR}/${DIR}_PANSHARP.tif || return ${ERR_GDAL_TRANSLATE}

    rm -f ${DIR}/PAN*B?.TIF

    rm -f ${DIR}/pan_rgb.vrt

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

    ciop-log "INFO" "(13 of ${num_steps}) Publish pan-sharpened RGB image"
    ciop-publish -m ${TMPDIR}/${DIR}/${DIR}_PANSHARP.tif || exit ${ERR_PUBLISH}
    
    ciop-log "INFO" "(14 of ${num_steps}) Publish eop metadata"
    ciop-publish -m ${target_xml} || exit ${ERR_PUBLISH}
  done

}


#!/bin/bash
# Script to create a screenshot of a given website URL
# Requires: phantomjs (http://phantomjs.org/)
#           pngquant (https://github.com/pornel/improved-pngquant)

# the script finishes with 0 if it worked, and the absolute path to the image

PHANTOMJS=/path/to/phantomjs-1.9.7.../bin/phantomjs
RASTERIZE=/path/to/rasterize.js
PNGQUANT=pngquant
# used to store the resulting image:
TMP=/tmp

if [ $# -eq 0 ]
then
    echo "No URL supplied"
    exit 1
fi

URL=$1
AGENT=$2
TMP_FILE="${TMP}/zg_webshot_$$.png"

echo "Snap URL: ${URL}"
$PHANTOMJS $RASTERIZE "$URL" $TMP_FILE 1024px
if [ ! -f $TMP_FILE ];
then
    echo "Temp file not found!"
    exit 1
fi

# remove png's alpha channel:
convert -background white -flatten $TMP_FILE $TMP_FILE || exit 1

$PNGQUANT --force --ext .png --speed 10 $TMP_FILE || exit 1

echo $TMP_FILE

exit 0


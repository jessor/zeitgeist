#!/bin/bash
# Script to create a screenshot of a given website URL
# Requires: wkkhtmltoimage (http://code.google.com/p/wkhtmltopdf/)
#           pngquant (https://github.com/pornel/improved-pngquant)
#           xvfb-run (http://www.x.org/releases/X11R7.6/doc/man/man1/Xvfb.1.xhtml)

# the script finishes with 0 if it worked, and the absolute path to the image

WKHTML=wkhtmltoimage
PNGQUANT=pngquant
XVFB=xvfb-run
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
$XVFB -a $WKHTML --use-xserver --quality 90 --load-error-handling ignore --custom-header-propagation --custom-header "User-Agent" "$AGENT" "$URL" $TMP_FILE
if [ ! -f $TMP_FILE ];
then
    echo "Temp file not found!"
    exit 1
fi
$PNGQUANT --force --ext .png --speed 10 $TMP_FILE || exit 1

echo $TMP_FILE

exit 0


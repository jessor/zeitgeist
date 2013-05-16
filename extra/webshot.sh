#!/bin/bash
# Script to create a screenshot of a given website URL
# Requires: wkkhtmltoimage (http://code.google.com/p/wkhtmltopdf/)
#           optipng (http://optipng.sourceforge.net/)
#           xvfb-run (http://www.x.org/releases/X11R7.6/doc/man/man1/Xvfb.1.xhtml)

# the script finishes with 0 if it worked, and the absolute path to the image

WKHTML=/usr/bin/wkhtmltoimage
OPTIPNG=/usr/bin/optipng
XVFB=xvfb-run
# used to store the resulting image:
TMP=/tmp

if [ $# -eq 0 ]
then
    echo "No URL supplied"
    exit 1
fi

URL=$1
TMP_FILE="${TMP}/zg_webshot_$$.png"

$XVFB -a $WKHTML "$URL" $TMP_FILE || exit 1
$OPTIPNG $TMP_FILE || exit 1

echo $TMP_FILE

exit 0


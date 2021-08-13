#!/bin/bash
#usage: 

#Function to display usage message
function usage()
{
   echo "./zeroSSLCertValidation.sh <<< \"<certificateDomainName> <RESPONSE_FILE>\""
   echo "example: ./zeroSSLCertValidation.sh <<< \"myhost.example.com /full/path/to/certificate.resp\""
   exit 1
}

#validation input
function validate_input()
{
   if [ -z "$CERT_NAME" ];
   then
      echo "Certification Domain name not provided."
      usage
   fi

   if [ ! -f "$RESPONSE_FILE" ];
   then
     echo "Response file not found: $RESPONSE_FILE. Please check and try again. "
     exit 1
   fi
}

function cleanup()
{
  echo "killing python http server process : ${pid}"
  kill "${pid}"
  echo "cleaning up temporary files..."
  rm -rf status.resp
  #mv "$CERT_NAME".resp $CURR_DIR/generated/
}

#main

trap cleanup EXIT

CURR_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $CURR_DIR/cert.cfg

read CERT_NAME RESPONSE_FILE

echo "CERT_NAME: $CERT_NAME"
echo "RESPONSE_FILE: $RESPONSE_FILE"

validate_input

ID="$(cat $RESPONSE_FILE | jq -r '.id')"
URL=$(cat $RESPONSE_FILE | jq -r ".validation.other_methods.\"${CERT_NAME}\".file_validation_url_http")
echo "URL: $URL"
FILE_NAME="${URL##*/}"
echo "FILENAME: $FILE_NAME"

#Create Target Directory to host File for Certification Verification
TARGET_DIR="$CURR_DIR/.well-known/pki-validation"
mkdir -p $TARGET_DIR

cat $RESPONSE_FILE | jq -r ".validation.other_methods.\"${CERT_NAME}\".file_validation_content|join(\"\n\")" > $TARGET_DIR/$FILE_NAME

cat $TARGET_DIR/$FILE_NAME

#enable port 80
sudo firewall-cmd --zone=public --add-port=80/tcp
sudo firewall-cmd --runtime-to-permanent
sudo systemctl restart firewalld

#kill any stale process running on port 80
ps aux | grep SimpleHTTPServer | grep -v grep | awk '{print $2}' | xargs kill

#start webserver using python simplehttp server
echo "starting webserver at port 80"
python -m SimpleHTTPServer 80 &
pid=$!

VALIDATION_URL="http://$CERT_NAME/.well-known/pki-validation/$FILE_NAME"
echo "VALIDATION URL: $VALIDATION_URL"

echo "wait for few seconds for the web server to start listening"
sleep 5s

STATUS=$(curl -o /dev/null --silent -Iw '%{http_code}' $VALIDATION_URL)

if [ "$STATUS" == "200" ];
then
  echo "Certificate Validation Text file avaialble at $VALIDATION_URL"
else
  echo "Certificate Validation Text file not available at $VALIDATION_URL"
  exit 1
fi


curl -s -X GET http://api.zerossl.com/certificates/${ID}?access_key="$ZEROSSL_KEY" -o status.resp
CERT_STATUS=$(cat status.resp | jq -r '.status')

echo "status of certificate before initiating verification"
if [ "$CERT_STATUS" == "draft" ];
then
 echo "Certificate ${ID} is in Draft Status. Can proceed with Verification".
 curl -s -X POST https://api.zerossl.com/certificates/${ID}/challenges?access_key="$ZEROSSL_KEY" -d validation_method=HTTP_CSR_HASH
 echo "wait for 10 secs to ensure certification is verified"
 sleep 10s
fi

curl -s -X GET http://api.zerossl.com/certificates/${ID}?access_key="$ZEROSSL_KEY" -o status.resp
echo "status of certificate after initiating verification"
CERT_STATUS=$(cat status.resp | jq -r '.status')

if [ "$CERT_STATUS" == "issued" ];
then
  echo "Certificate Domain Verification Successful and Certificate has been issued"
else
  echo "Certification Domain verification failed"
  exit 1
fi

echo "downloading certificate..."
curl  https://api.zerossl.com/certificates/${ID}/download?access_key="$ZEROSSL_KEY" --output $CURR_DIR/certificate.zip
echo "certificate download successfully."


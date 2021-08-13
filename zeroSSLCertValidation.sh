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

#main
CURR_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $CURR_DIR/cert.cfg

read CERT_NAME RESPONSE_FILE

echo "CERT_NAME: $CERT_NAME"
echo "RESPONSE_FILE: $RESPONSE_FILE"

validate_input

ID="$(cat $RESPONSE_FILE | jq -r '.id')"
URL=$(cat $RESPONSE_FILE | jq -r ".validation.other_methods.\"${CERT_NAME}\".file_validation_url_http")
echo $URL
FILE_NAME="${URL##*/}"
echo $FILE_NAME

#Create Target Directory to host File for Certification Verification
TARGET_DIR="$CURR_DIR/.well-known/pki-validation"
mkdir -p $TARGET_DIR

cat $RESPONSE_FILE | jq -r ".validation.other_methods.\"${CERT_NAME}\".file_validation_content|join(\"\n\")" > $TARGET_DIR/$FILE_NAME

#enable port 80
sudo firewall-cmd --zone=public --add-port=80/tcp
sudo firewall-cmd --runtime-to-permanent
sudo systemctl restart firewalld

#start webserver using python simplehttp server
echo "starting webserver at port 80"
python -m SimpleHTTPServer 80 &
pid=$!

sleep 1

VALIDATION_URL="http://$CERT_NAME/.well-known/pki-validation/EB8C2D0F5C6256039A5206FE2B5A4EF3.txt"
status=$(curl -I $VALIDATION_URL  2>&1 | awk '/HTTP\// {print $2}')

if [ $status != 200 ];
then
  echo "Certification Validation Text file not available at $VALIDATION_URL"
  exit 1
fi

curl -s -X POST https://api.zerossl.com/certificates/${ID}/challenges?access_key="$ZEROSSL_KEY" -d validation_method=HTTP_CSR_HASH -0 validation.resp

VALIDATION_STATUS=$(cat validation.resp | jq -r '.status')

if [ "$VALIDATION_STATUS" == "pending_validation" ];
then
  echo "Certificate Domain Verification Successfull. Pending issuance"
else
  echo "Certification Domain verification failed"
  exit 1
fi

#Download the certificate
curl  https://api.zerossl.com/certificates/${ID}/download?access_key="$ZEROSSL_KEY" --output $CURR_DIR/certificate.zip

kill "${pid}"

#!/bin/bash

#Function to display usage message
function usage()
{
   echo "./zeroSSLCertificateRequest.sh <<< \"<certificateDomainName>\""
   echo "example: ./zeroSSLCertificateRequest.sh <<< \"mydomain.example.com\""
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
}


#main
CURR_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source $CURR_DIR/cert.cfg

read CERT_NAME

validate_input

GENERATED_DIR="$CURR_DIR/generated"

mkdir -p $GENERATED_DIR

# Create CSR and Private Key
openssl req -new \
 -newkey rsa:2048 -nodes -keyout "$GENERATED_DIR/$CERT_NAME".key \
 -out $CURR_DIR/"$CERT_NAME".csr \
 -subj "/C=IN/ST=Karnataka/L=Bangalore/O=Oracle India Pvt Limited/OU=WLS QA/CN=$CERT_NAME"

RESPONSE_FILE="$CURR_DIR/${CERT_NAME}.resp"
# Draft certificate at ZeroSSL
curl -s -X POST https://api.zerossl.com/certificates?access_key="$ZEROSSL_KEY" \
        --data-urlencode certificate_csr@"$CERT_NAME".csr \
        -d certificate_domains="$CERT_NAME" \
        -d certificate_validity_days=90 \
        -o $RESPONSE_FILE


mv "$CERT_NAME".csr ${GENERATED_DIR}/${CERT_NAME}.csr

echo "Successfully created certificate request"
echo "Use zeroCertValidation.sh to validate the certificate on zerossl to generate and download  the certificate"


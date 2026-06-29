#!/bin/bash
openssl pkcs12 -in "$1" -clcerts -nokeys -out cert.pem -legacy
openssl pkcs12 -in "$1" -clcerts -nodes -out key.pem -legacy

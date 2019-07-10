#!/bin/sh

# This script runs our evaluation, generating an output file with numbers.

dune exec runner/runner.exe run tests/borrowck 2>&1 > /dev/null
MATCHES=`jq '.matches | length' tests/borrowck/results.json`
DOESNTMATCH=`jq '.doesntmatch | length' tests/borrowck/results.json`
MISSING=`jq '.missing | length' tests/borrowck/results.json`
TYPEERROR=`jq '.typeerror | length' tests/borrowck/results.json`
REDUCERERROR=`jq '.reducererror | length' tests/borrowck/results.json`

echo "${MATCHES} borrowck MATCHING"
echo "${DOESNTMATCH} borrowck FAILING"
echo "${MISSING} borrowck UNCHECKED"
echo "${TYPEERROR} borrowck UNSUPPORTED BY OXIDE"
echo "${REDUCERERROR} borrowck UNANNOTATED OR UNSUPPORTED BY DESUGARER"

for dir in `ls tests/disqualified`
do
    COUNT=`ls -l tests/disqualified/$dir | wc -l | tr -d [:space:]`
    echo "${COUNT} disqualified/$dir"
done

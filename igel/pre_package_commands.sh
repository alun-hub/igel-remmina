#!/bin/bash
set -e

find input/ -name "*.a" -delete
find input/ -name "*.la" -delete
find input/ -path "*/share/doc/*" -delete
find input/ -path "*/share/man/*" -delete
find input/ -path "*/share/locale/*" -delete

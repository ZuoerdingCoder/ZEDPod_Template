#!/bin/bash

cd `dirname $0`
pod repo update LigoPods --verbose
pod update --verbose --no-repo-update

#!/bin/bash
cat << EOF
{
  "headers": {
    "x-buildbuddy-api-key": ["${RBE_API_KEY}"]
  },
  "token": "dummy"
}
EOF

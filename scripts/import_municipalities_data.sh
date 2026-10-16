#!/bin/bash
set -e
exec /app/python_virtual_env/bin/python3 /app/scripts/central_import.py --dataset municipalities

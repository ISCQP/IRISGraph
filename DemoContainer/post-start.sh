#!/bin/sh
# Run by iris-main (--after) once IRIS is up. Changes the administrator password only when TESTBED_ADMIN_PASSWORD is set.
iris session IRIS -U TESTBED '##class(Install.Testbed).PostStart()' || true

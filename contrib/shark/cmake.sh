#!/bin/bash
rm -f shark--3.0.sql
touch shark--3.0.sql
cat shark--1.0.sql >> shark--3.0.sql
cat upgrade_script/shark--1.0--2.0.sql upgrade_script/shark--2.0--3.0.sql >> dolphin--3.0.sql
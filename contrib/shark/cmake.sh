#!/bin/bash
rm -f shark--3.0.sql
touch shark--3.0.sql
cat shark--1.0.sql >> shark--3.0.sql
for i in `ls upgrade_script/ | sort`; do cat upgrade_script/$i >> shark--2.0.sql; done
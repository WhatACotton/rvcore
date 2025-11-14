#!/bin/bash

# Run C program test for Sdtrig module

MODULE=test_sdtrig_c
TOPLEVEL=top_with_ram_sim

make -f Makefile.clint MODULE=$MODULE TOPLEVEL=$TOPLEVEL clean
make -f Makefile.clint MODULE=$MODULE TOPLEVEL=$TOPLEVEL

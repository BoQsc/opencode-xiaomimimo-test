#!/bin/bash
# Build CrossUI Notepad for Linux
# Requires: DMD (D compiler), libx11-dev, libgl-dev
# Install on Ubuntu/Debian: sudo apt install dmd-compiler libx11-dev libgl-dev
# Install on Fedora: sudo dnf install dmd libX11-devel mesa-libGL-devel

rm -f crossui crossui.o font_backend_d.o

dmd crossui.d font_backend_d.d \
    -ofcrossui \
    -O -release -inline \
    -L-lX11 \
    -L-lGL \
    -L-lXext \
    -defaultlib=phobos2 \
    -L--export-dynamic

if [ $? -eq 0 ]; then
    echo "Build successful: ./crossui"
else
    echo "Build failed with errors."
fi

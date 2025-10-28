#!/bin/bash

# Check if exiftool is installed
if ! command -v exiftool &> /dev/null; then
    echo "Error: exiftool is not installed."
    echo "Please install exiftool first:"
    echo "  On Ubuntu/Debian: sudo apt-get install libimage-exiftool-perl"
    echo "  On CentOS/RHEL: sudo yum install perl-Image-ExifTool"
    echo "  On Fedora: sudo dnf install perl-Image-ExifTool"
    echo "  On Arch: sudo pacman -S perl-image-exiftool"
    echo "  On macOS: brew install exiftool"
    exit 1
fi

echo "exiftool is installed: $(exiftool -ver)"

# Compile the program
echo "Compiling the program..."
make clean && make

if [ $? -eq 0 ]; then
    echo "Compilation successful!"
    echo "Usage: ./generate_images [num_images] [size] [block_size] [quality] [output_path] [colors...]"
    echo "Example: ./generate_images 5 500 50 85"
else
    echo "Compilation failed!"
    exit 1
fi
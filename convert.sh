#!/bin/bash

# LICENSE: Unlicense
#
# This is free and unencumbered software released into the public domain.
# 
# Anyone is free to copy, modify, publish, use, compile, sell, or
# distribute this software, either in source code form or as a compiled
# binary, for any purpose, commercial or non-commercial, and by any
# means.
# 
# In jurisdictions that recognize copyright laws, the author or authors
# of this software dedicate any and all copyright interest in the
# software to the public domain. We make this dedication for the benefit
# of the public at large and to the detriment of our heirs and
# successors. We intend this dedication to be an overt act of
# relinquishment in perpetuity of all present and future rights to this
# software under copyright law.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.

# Default values
MAX_JOBS=4
INPUT_DIR="./videos"
OUTPUT_DIR="./output"
CRF=28

# Function to display help message
usage() {
    printf "Usage: %s [options] [input_directory]\n" "$0"
    printf "\nOptions:\n"
    printf "  -h               Display this help message\n"
    printf "  -j <jobs>        Maximum number of concurrent ffmpeg jobs (default: 4)\n"
    printf "  -o <output_dir>  Output directory (default: ./output)\n"
    printf "  --crf <crf>      CRF value for ffmpeg (default: 28)\n"
    printf "  input_directory  Directory containing videos to convert (default: ./videos)\n"
    exit 0
}

# Parse command line options
while getopts ":h:j:o:-:" opt; do
    case ${opt} in
        h )
            usage
            ;;
        j )
            if [[ $OPTARG =~ ^[1-9][0-9]*$ ]]; then
                MAX_JOBS=$OPTARG
            else
                printf "Invalid value for -j. Must be a positive integer.\n"
                exit 1
            fi
            ;;
        o )
            OUTPUT_DIR=$OPTARG
            ;;
        - )
            case "${OPTARG}" in
                crf)
                    val="${!OPTIND}"; OPTIND=$((OPTIND + 1))
                    if [[ $val =~ ^[0-9]+$ ]]; then
                        CRF=$val
                    else
                        printf "Invalid value for --crf. Must be an integer.\n"
                        exit 1
                    fi
                    ;;
                *)
                    usage
                    ;;
            esac
            ;;
        * )
            usage
            ;;
    esac
done
shift $((OPTIND - 1))

# Override input directory if provided
if [ -n "$1" ]; then
    INPUT_DIR="$1"
fi

# Check if ffmpeg is installed
if ! command -v ffmpeg &> /dev/null; then
    printf "ffmpeg could not be found, please install it first.\n"
    printf "Download link: https://www.ffmpeg.org/download.html\n"
    exit 1
fi

# Check if the input directory exists
if [ ! -d "$INPUT_DIR" ]; then
    printf "Input directory %s does not exist.\n" "$INPUT_DIR"
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Prevent looping if no files are found
shopt -s nullglob

# Function to handle script termination
cleanup() {
    printf "Cleaning up...\n"
    wait
    exit 1
}

# Trap signals to handle script termination and normal exit
trap 'cleanup' INT TERM EXIT

# Recursively find all video files
mapfile -t files < <(find "$INPUT_DIR" -type f \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.mkv" \))

if [ ${#files[@]} -eq 0 ]; then
    printf "No files found in the input directory.\n"
    exit 0
fi

# Iterate over each video file in the input directory
for input_file in "${files[@]}"; do
    base_name=$(basename "$input_file")
    output_file="$OUTPUT_DIR/${base_name%.*}.mp4"
    
    if [ -e "$output_file" ]; then
        printf "%s already exists, skipping...\n" "$output_file"
        continue
    fi
    
    {
        if ! ffmpeg -i "$input_file" -c:v libx265 -crf "$CRF" -preset medium -c:a copy -tag:v hvc1 "$output_file"; then
            printf "Error converting %s\n" "$input_file" >&2
        else
            printf "Converted %s to %s\n" "$input_file" "$output_file"
        fi
    } &
    
    current_jobs=$(jobs -p | wc -l)
    if [ "$current_jobs" -ge "$MAX_JOBS" ]; then
        wait -n || true
    fi

done

wait
trap - EXIT

printf "All videos have been converted and saved in the %s directory.\n" "$OUTPUT_DIR"

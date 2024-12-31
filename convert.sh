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
PRESET="medium"
VERBOSE=false
VERSION="1.0-beta"

# Function to display help message
usage() {
    printf "Usage: %s [options] [input_directory]\n" "$0"
    printf "\nOptions:\n"
    printf "  -h, --help               Display this help message\n"
    printf "  -j, --jobs <jobs>        Maximum number of concurrent ffmpeg jobs (default: 4)\n"
    printf "  -o, --output <output_dir>  Output directory (default: ./output)\n"
    printf "  -c, --crf <crf>          CRF value for ffmpeg (default: 28)\n"
    printf "  -p, --preset <preset>    Preset value for ffmpeg (default: medium)\n"
    printf "  -v, --verbose            Enable verbose mode\n"
    printf "  --update                 Update this script to the latest version from the repository\n"
    printf "  input_directory          Directory containing videos to convert (default: ./videos)\n"
    exit 0
}

# Function to update the script
update_script() {
    local script_url="https://raw.githubusercontent.com/misakazip/h265-converter/main/convert.sh"
    curl -o "$0" -sSL "$script_url" && chmod +x "$0"
    printf "The script has been updated to the latest(%s) version.\n" $VERSION
    exit 0
}

# Parse command line options
while getopts ":h:j:o:c:p:v-:" opt; do
    case ${opt} in
        h )
            usage
            ;;
        j )
            val=$OPTARG
            if [[ $val =~ ^[1-9][0-9]*$ ]]; then
                MAX_JOBS=$val
            else
                printf "Invalid value for -j. Must be a positive integer.\n"
                exit 1
            fi
            ;;
        o )
            OUTPUT_DIR=$OPTARG
            ;;
        c )
            val=$OPTARG
            if [[ $val =~ ^[0-9]+$ ]]; then
                CRF=$val
            else
                printf "Invalid value for -c. Must be an integer.\n"
                exit 1
            fi
            ;;
        p )
            PRESET=$OPTARG
            ;;
        v )
            VERBOSE=true
            ;;
        - )
            case "${OPTARG}" in
                help)
                    usage
                    ;;
                jobs)
                    val="${!OPTIND}"; OPTIND=$((OPTIND + 1))
                    if [[ $val =~ ^[1-9][0-9]*$ ]]; then
                        MAX_JOBS=$val
                    else
                        printf "Invalid value for --jobs. Must be a positive integer.\n"
                        exit 1
                    fi
                    ;;
                output)
                    OUTPUT_DIR="${!OPTIND}"; OPTIND=$((OPTIND + 1))
                    ;;
                crf)
                    val="${!OPTIND}"; OPTIND=$((OPTIND + 1))
                    if [[ $val =~ ^[0-9]+$ ]]; then
                        CRF=$val
                    else
                        printf "Invalid value for --crf. Must be an integer.\n"
                        exit 1
                    fi
                    ;;
                preset)
                    PRESET="${!OPTIND}"; OPTIND=$((OPTIND + 1))
                    ;;
                verbose)
                    VERBOSE=true
                    ;;
                update)
                    update_script
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

# Enable verbose mode if specified
if $VERBOSE; then
    set -x
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
mkdir -p "$OUTPUT_DIR" || {
    printf "Failed to create output directory %s.\n" "$OUTPUT_DIR"
    exit 1
}

# Prevent looping if no files are found
shopt -s nullglob

# Function to handle script termination
cleanup() {
    printf "Cleaning up...\n"
    jobs -p | xargs -r wait
    exit 1
}

# Trap signals to handle script termination and normal exit
trap 'cleanup' INT TERM
trap 'exit 0' EXIT

# Recursively find all video files
mapfile -t files < <(find "$INPUT_DIR" -type f \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.flv" \) ! -name ".*")

if [ ${#files[@]} -eq 0 ]; then
    printf "No files found in the input directory.\n"
    exit 0
fi

job_count=0

# Iterate over each video file in the input directory
for input_file in "${files[@]}"; do
    base_name=$(basename "$input_file")
    output_file="$OUTPUT_DIR/${base_name%.*}.mp4"
    
    if [ -e "$output_file" ]; then
        printf "%s already exists, skipping...\n" "$output_file"
        continue
    fi
    
    {
        if ! ffmpeg -i "$input_file" -c:v libx265 -crf "$CRF" -preset "$PRESET" -c:a copy -tag:v hvc1 "$output_file"; then
            printf "Error converting %s\n" "$input_file" >&2
        else
            printf "Converted %s to %s\n" "$input_file" "$output_file"
        fi
    } &
    
    ((job_count++))
    if [ "$job_count" -ge "$MAX_JOBS" ]; then
        wait -n || true
        ((job_count--))
    fi

done

wait

printf "All videos have been converted and saved in the %s directory.\n" "$OUTPUT_DIR"

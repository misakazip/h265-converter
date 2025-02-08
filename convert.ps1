#!/usr/bin/env pwsh

param (
    [string[]]$args
)

# Default values
$MAX_JOBS = 4
$INPUT_DIR = "./videos"
$OUTPUT_DIR = "./output"
$CRF = 28
$PRESET = "medium"
$VERBOSE = $false
$VERSION = "1.0-beta"

# Function to display help message
function Show-Help {
    Write-Output "Usage: ./convert.ps1 [options] [input_directory]"
    Write-Output ""
    Write-Output "Options:"
    Write-Output "  -h, --help               Display this help message"
    Write-Output "  -j, --jobs <jobs>        Maximum number of concurrent ffmpeg jobs (default: 4)"
    Write-Output "  -o, --output <output_dir>  Output directory (default: ./output)"
    Write-Output "  -c, --crf <crf>          CRF value for ffmpeg (default: 28)"
    Write-Output "  -p, --preset <preset>    Preset value for ffmpeg (default: medium)"
    Write-Output "  -v, --verbose            Enable verbose mode"
    Write-Output "  --update                 Update this script to the latest version from the repository"
    Write-Output "  input_directory          Directory containing videos to convert (default: ./videos)"
    exit
}

# Function to update the script
function Update-Script {
    $script_url = "https://raw.githubusercontent.com/misakazip/h265-converter/main/convert.sh"
    Invoke-WebRequest -Uri $script_url -OutFile $MyInvocation.MyCommand.Path
    Write-Output "The script has been updated to the latest($VERSION) version."
    exit
}

# Parse command line options
for ($i = 0; $i -lt $args.Length; $i++) {
    switch ($args[$i]) {
        '-h' { Show-Help }
        '--help' { Show-Help }
        '-j' { 
            $i++
            if ($args[$i] -match '^[1-9][0-9]*$') {
                $MAX_JOBS = [int]$args[$i]
            } else {
                Write-Output "Invalid value for -j. Must be a positive integer."
                exit
            }
        }
        '--jobs' { 
            $i++
            if ($args[$i] -match '^[1-9][0-9]*$') {
                $MAX_JOBS = [int]$args[$i]
            } else {
                Write-Output "Invalid value for --jobs. Must be a positive integer."
                exit
            }
        }
        '-o' { 
            $i++
            $OUTPUT_DIR = $args[$i]
        }
        '--output' { 
            $i++
            $OUTPUT_DIR = $args[$i]
        }
        '-c' { 
            $i++
            if ($args[$i] -match '^[0-9]+$') {
                $CRF = [int]$args[$i]
            } else {
                Write-Output "Invalid value for -c. Must be an integer."
                exit
            }
        }
        '--crf' { 
            $i++
            if ($args[$i] -match '^[0-9]+$') {
                $CRF = [int]$args[$i]
            } else {
                Write-Output "Invalid value for --crf. Must be an integer."
                exit
            }
        }
        '-p' { 
            $i++
            $PRESET = $args[$i]
        }
        '--preset' { 
            $i++
            $PRESET = $args[$i]
        }
        '-v' { $VERBOSE = $true }
        '--verbose' { $VERBOSE = $true }
        '--update' { Update-Script }
        default {
            if ($args[$i].StartsWith('-')) {
                Show-Help
            } else {
                $INPUT_DIR = $args[$i]
            }
        }
    }
}

# Check if ffmpeg is installed
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Output "ffmpeg could not be found, please install it first."
    Write-Output "Download link: https://www.ffmpeg.org/download.html"
    exit
}

# Check if the input directory exists
if (-not (Test-Path $INPUT_DIR)) {
    Write-Output "Input directory $INPUT_DIR does not exist."
    exit
}

# Create output directory if it doesn't exist
if (-not (Test-Path $OUTPUT_DIR)) {
    New-Item -ItemType Directory -Path $OUTPUT_DIR | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Output "Failed to create output directory $OUTPUT_DIR."
        exit
    }
}

# Recursively find all video files
$files = Get-ChildItem -Path $INPUT_DIR -Recurse -Include *.mp4, *.mov, *.mkv, *.avi, *.flv | Where-Object { -not $_.Name.StartsWith('.') }

if ($files.Count -eq 0) {
    Write-Output "No files found in the input directory."
    exit
}

$job_count = 0

# Iterate over each video file in the input directory
foreach ($file in $files) {
    $input_file = $file.FullName
    $base_name = $file.BaseName
    $output_file = "$OUTPUT_DIR\$base_name.mp4"
    
    if (Test-Path $output_file) {
        Write-Output "$output_file already exists, skipping..."
        continue
    }
    
    Start-Job -ScriptBlock {
        param ($input_file, $output_file, $CRF, $PRESET)
        ffmpeg -i $input_file -c:v libx265 -crf $CRF -preset $PRESET -c:a copy -tag:v hvc1 $output_file
        if ($LASTEXITCODE -ne 0) {
            Write-Output "Error converting $input_file"
        } else {
            Write-Output "Converted $input_file to $output_file"
        }
    } -ArgumentList $input_file, $output_file, $CRF, $PRESET
    
    $job_count++
    if ($job_count -ge $MAX_JOBS) {
        Wait-Job -Any | Out-Null
        $job_count--
    }
}

Wait-Job | Out-Null

Write-Output "All videos have been converted and saved in the $OUTPUT_DIR directory."


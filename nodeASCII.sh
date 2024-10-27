#!/bin/bash

# Function to fetch and extract a specific metric
fetch_metric() {
    local metric="$1"
    curl -s "http://localhost:9100/metrics" | grep "^$metric" | awk '{print $2}'
}

# Function to generate graph
generate_graph() {
    gnuplot <<EOF
    set term dumb 160 48
    set multiplot layout 2,2 title "Node Exporter Metrics" font ",20"
    
    set title "Temperature (°C)"
    set ylabel "Celsius"
    set xlabel "Sample Number (0.1s intervals)"
    set autoscale
    set key left top
    plot "temp_data.txt" using 1:2 with linespoints title "Temperature"

    set title "Filesystem Available (GB)"
    set ylabel "GB"
    set autoscale
    plot "temp_data.txt" using 1:3 with linespoints title "Filesystem"

    set title "Memory Used (GB)"
    set ylabel "GB"
    set autoscale
    plot "temp_data.txt" using 1:4 with linespoints title "Memory"

    set title "CPU Usage (%)"
    set ylabel "Percentage"
    set yrange [0:100]
    set autoscale x
    plot "temp_data.txt" using 1:5 with linespoints title "CPU"

    unset multiplot
EOF
}

# Initialize data file and buffers
> temp_data.txt
> buffer1
> buffer2

# Trap ctrl-c and call cleanup
trap cleanup INT

function cleanup() {
    echo "Cleaning up..."
    rm -f temp_data.txt buffer1 buffer2
    tput cnorm  # Show cursor
    exit 0
}

# Hide cursor
tput civis

# Main loop
count=0
while true; do
    count=$((count+1))
    
    # Fetch metrics and perform calculations
    temp=$(fetch_metric "node_hwmon_temp_celsius")
    
    fs_avail=$(fetch_metric 'node_filesystem_avail_bytes{mountpoint="/"}')
    fs_avail_gb=$(echo "scale=2; $fs_avail / (1024*1024*1024)" | bc -l)
    
    mem_total=$(fetch_metric "node_memory_MemTotal_bytes")
    mem_avail=$(fetch_metric "node_memory_MemAvailable_bytes")
    mem_used_gb=$(echo "scale=2; ($mem_total - $mem_avail) / (1024*1024*1024)" | bc -l)
    
    cpu_idle=$(fetch_metric 'node_cpu_seconds_total{mode="idle"}')
    cpu_total=$(fetch_metric "node_cpu_seconds_total")
    cpu_usage=$(echo "scale=2; (1 - $cpu_idle / $cpu_total) * 100" | bc -l)
    
    # Ensure all values are numbers
    temp=${temp:-0}
    fs_avail_gb=${fs_avail_gb:-0}
    mem_used_gb=${mem_used_gb:-0}
    cpu_usage=${cpu_usage:-0}
    
    # Debug output
    echo "Debug: temp=$temp, fs_avail_gb=$fs_avail_gb, mem_used_gb=$mem_used_gb, cpu_usage=$cpu_usage" >&2
    
    # Append to data file
    echo "$count $temp $fs_avail_gb $mem_used_gb $cpu_usage" >> temp_data.txt
    
    # Keep only the last 20 lines
    tail -n 20 temp_data.txt > temp_data_recent.txt
    mv temp_data_recent.txt temp_data.txt
    
    # Generate graph in a buffer
    generate_graph > buffer1
    
    # Swap buffers
    mv buffer1 buffer2
    
    # Clear screen and display buffer
    tput cup 0 0
    cat buffer2
    
    # Wait for 0.1 seconds
    sleep .1
done

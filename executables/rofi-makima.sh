#!/bin/bash
sudo -E makima 2>/dev/null &
mk_pid=$!
rofi -show drun

cleanup() {
    sudo kill $mk_pid
}

trap cleanup EXIT SIGINT SIGTERM
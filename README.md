# audio_sample_rate
A Swift program to change the sample rate of current device for MacOS.
    Usage: audio-sample-rate [OPTIONS]
    
    Options:
      -l, --list              List available sample rates for current device
      -c, --current           Show current sample rate
      -s, --set <rate>        Set sample rate (e.g., 44100, 48000, 96000)
      -h, --help              Show this help message
    
    Examples:
      audio-sample-rate --list
      audio-sample-rate --current
      audio-sample-rate --set 48000

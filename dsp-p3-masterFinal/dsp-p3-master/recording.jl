using Gtk, PortAudio, WAV, Sound

function record()
  # Initialize variables that are used throughout
  S = 44100 # Sampling rate (samples/second)
  N = 1024 # Buffer length
  maxtime = 1000 # Maximum recording time in seconds (for demo)
  global recording = false # Flag
  nsample = 0 # Count number of samples recorded
  song = Float32[] # Initialize "song" as an empty array

  # Callbacks

  function record_loop!(in_stream, buf)
    Niter = floor(Int, maxtime * S / N)
    println("\nRecording up to Niter=$Niter ($maxtime sec).")
    for iter in 1:Niter
      if !recording
        break
      end
      read!(in_stream, buf)
      append!(song, buf) # Append buffer to song
      nsample += N
      print("\riter=$iter/$Niter nsample=$nsample")
    end
  end

  function call_record(w)
    in_stream = PortAudioStream(1, 0) # Default input device
    buf = read(in_stream, N) # Warm-up
    global recording = true
    global song = zeros(Float32, maxtime * S)
    @async record_loop!(in_stream, buf)
  end

  function call_stop(w)
    global recording = false
    sleep(0.1) # Ensure the async record loop finished
    duration = round(nsample / S, digits=2)
    flush(stdout)
    println("\nStopped recording at nsample=$nsample, duration $duration seconds.")
    global song = song[1:nsample] # Truncate song to the recorded duration
  end

  function call_play(w)
    # println("Playing recording.")
    @async sound(song, S) # Play the entire recording
  end

  function call_export(w)
    wavwrite(song, "recordedFromComputer.wav", Fs=S)
  end

  # GUI setup
  win = GtkWindow("Recorder", 600, 200)
  g = GtkGrid()
  set_gtk_property!(g, :column_spacing, 10)
  set_gtk_property!(g, :row_homogeneous, true)
  set_gtk_property!(g, :column_homogeneous, true)

  function make_button(string, callback, column, stylename, styledata)
    b = GtkButton(string)
    signal_connect((w) -> callback(w), b, "clicked")
    g[column, 1] = b
    s = GtkCssProvider(data="#$stylename {$styledata}")
    push!(GAccessor.style_context(b), GtkStyleProvider(s), 600)
    set_gtk_property!(b, :name, stylename)
    return b
  end

  # Create buttons with callbacks, positions, and styles
  make_button("Record", call_record, 1, "wr", "color:white; background:red;")
  make_button("Stop", call_stop, 2, "yb", "color:yellow; background:blue;")
  make_button("Play", call_play, 3, "wg", "color:white; background:green;")
  make_button("Export", call_export, 4, "yb", "color:yellow; background:black;")

  push!(win, g) # Add grid to window
  showall(win) # Display the window with all buttons
end

record()
